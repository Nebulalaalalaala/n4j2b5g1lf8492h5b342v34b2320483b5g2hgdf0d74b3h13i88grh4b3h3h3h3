extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# The activity feed: reads friends', clanmates' or everyone's events, posts
# yours (rank-ups, badges, PBs, milestones) and keeps reactions in sync.
signal changed

const WINS = [50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000]
const MAPS = [25, 50, 100, 150, 200, 300]
const STREAKS = [5, 10, 15, 20, 30, 50]
var api
var identity
var events = {"friends": [], "everyone": [], "player": [], "clan": []}
var player_shown = ""
var reactions = {}    # event id -> {user id: emoji}
var status = {"friends": "idle", "everyone": "idle", "player": "idle", "clan": "idle"}
var _fetched = {"friends": 0, "everyone": 0}

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	api.connect("done", self, "_done")

static func unix(iso) -> int:
	var text = str(iso)
	if text.length() < 19:
		return 0
	var d = {"year": int(text.substr(0, 4)), "month": int(text.substr(5, 2)), "day": int(text.substr(8, 2)),
		"hour": int(text.substr(11, 2)), "minute": int(text.substr(14, 2)), "second": int(text.substr(17, 2))}
	var t = OS.get_unix_time_from_datetime(d)
	var zone = text.substr(19).find("+")
	if zone < 0:
		zone = text.substr(19).find("-")
	if zone >= 0:
		var z = text.substr(19 + zone)
		var offset = (int(z.substr(1, 2)) * 3600 + int(z.substr(4, 2)) * 60) * (1 if z.begins_with("+") else -1)
		t -= offset
	return t

func fetch(scope, ids = [], force = false):
	if not force and OS.get_unix_time() - int(_fetched.get(scope, 0)) < 45:
		return
	_fetched[scope] = OS.get_unix_time()
	status[scope] = "loading"
	if scope == "everyone":
		api.select("hub_events?select=*&order=id.desc&limit=60", "feed:everyone")
	elif scope == "player":
		player_shown = str(ids[0]) if not ids.empty() else ""
		if identity.signed_in():
			api.call_fn("hub_feed", identity.auth({"p_ids": [player_shown]}), "feed:player")
		else:
			api.select("hub_events?select=*&user_id=eq.%s&order=id.desc&limit=30" % player_shown, "feed:player")
	elif not ids.empty() and identity.signed_in():
		# Includes friends-only activity of friends and clanmates.
		api.call_fn("hub_feed", identity.auth({"p_ids": ids.slice(0, min(150, ids.size()) - 1)}), "feed:" + scope)
	elif not ids.empty():
		api.select("hub_events?select=*&user_id=in.(%s)&order=id.desc&limit=60" % PoolStringArray(ids.slice(0, min(150, ids.size()) - 1)).join(","), "feed:" + scope)
	else:
		events[scope] = []
		status[scope] = "ready"
		emit_signal("changed")

func _done(tag, ok, data, message):
	if tag.begins_with("feed:"):
		var scope = tag.substr(5)
		if not ok:
			status[scope] = "missing" if message == "missing" else "error"
			emit_signal("changed")
			return
		var list = []
		var ids = []
		for r in data if data is Array else []:
			if r is Dictionary:
				r["at"] = unix(r.get("created_at", ""))
				list.append(r)
				ids.append(str(r.id))
		events[scope] = list
		status[scope] = "ready"
		if not ids.empty():
			api.select("hub_reactions?select=event_id,user_id,emoji&event_id=in.(%s)" % PoolStringArray(ids).join(","), "reactions")
		emit_signal("changed")
	elif tag == "reactions" and ok and data is Array:
		for r in data:
			var by = reactions.get(str(r.event_id), {})
			by[str(r.user_id)] = str(r.emoji)
			reactions[str(r.event_id)] = by
		emit_signal("changed")
	elif tag == "post" and not ok and message.find("not allowed") >= 0:
		identity.refused()

func react(event_id, emoji):
	if not identity.signed_in():
		return
	var by = reactions.get(str(event_id), {})
	if by.get(identity.user_id, "") == emoji:
		emoji = ""
	if emoji.empty():
		by.erase(identity.user_id)
	else:
		by[identity.user_id] = emoji
	reactions[str(event_id)] = by
	api.call_fn("hub_react", identity.auth({"p_event": int(event_id), "p_emoji": emoji}), "react")
	emit_signal("changed")

func post(kind, dedupe, data):
	if identity.signed_in():
		api.call_fn("hub_post_event", identity.auth({"p_kind": kind, "p_dedupe": str(dedupe).substr(0, 80), "p_data": data}), "post")

# Compares what the game and Journey show now with what was last announced.
# The first look at an account only records the current state.
func check(hub):
	var posted = hub.store.data.posted
	var first = posted.empty()
	var model = hub.journey_model()
	if not model.empty() and model.get("rank") != null:
		var rank = model.rank
		hub.store.note_rank(int(model.get("xp", 0)), str(rank.name))
		if str(posted.get("rank", "")) != str(rank.name) and int(model.get("xp", 0)) > int(posted.get("rank_xp", -1)):
			if not first and posted.has("rank"):
				post("rank", "rank:" + str(rank.name), {"rank": str(rank.name), "art": str(rank.get("art", ""))})
			posted.rank = str(rank.name)
			posted.rank_xp = int(model.get("xp", 0))
		if model.get("achievements") != null:
			var tiers = posted.get("badges", {})
			var names = load(ModPaths.path("JourneyAchievements.gd"))
			for c in model.achievements.collections:
				var tier = int(c.get("tier", 0))
				if tier > int(tiers.get(c.key, 0)):
					if not first and posted.has("badges") and tier > 0:
						post("badge", "badge:%s:%d" % [c.key, tier], {"key": c.key, "name": str(c.get("name", c.key)), "tier": tier, "tier_name": names.tier_name(tier)})
					tiers[c.key] = tier
			posted.badges = tiers
	var records = hub.history_records()
	var after = int(posted.get("pb_after", 0))
	var newest = after
	if not records.empty():
		var progression = hub.history_store().progression(records)
		var shown = 0
		for record in records:
			if int(record.date) <= after:
				continue
			newest = max(newest, int(record.date))
			var step = progression.events.get(record.id)
			if step != null and not step.baseline and not first and shown < 3 and posted.has("pb_after"):
				shown += 1
				post("pb", "pb:" + str(record.id), {"map": str(record.map_name), "time": float(step.time), "better": float(step.improvement), "mode": str(record.mode)})
		posted.pb_after = newest
		var unique = {}
		for record in records:
			unique[str(record.map_id)] = true
		_milestone(posted, "maps", unique.size(), MAPS, "maps", first)
	var wins = hub.profiles.stat(hub.store.account, hub.profiles.stat_key("Stat_GamesWon"))
	if wins > 0:
		_milestone(posted, "wins", wins, WINS, "wins", first)
	var streak = hub.profiles.stat(hub.store.account, hub.profiles.stat_key("Stat_BestWinstreak"))
	if streak > 0:
		_milestone(posted, "streak", streak, STREAKS, "streak", first)
	var levels = hub.creations(hub.store.account)
	var known = posted.get("levels", [])
	for level in levels:
		if not known.has(str(level.id)):
			if not first and posted.has("levels"):
				post("level", "level:" + str(level.id), {"name": str(level.name), "id": str(level.id)})
			known.append(str(level.id))
	posted.levels = known
	hub.store.data.posted = posted
	hub.store.save()

func _milestone(posted, field, value, steps, kind, first):
	var reached = 0
	for step in steps:
		if value >= step:
			reached = step
	if not posted.has(field):
		posted[field] = reached   # first look: note it, don't announce
		return
	if reached > int(posted.get(field, 0)):
		if not first:
			post(kind, "%s:%d" % [kind, reached], {"count": reached})
		posted[field] = reached
