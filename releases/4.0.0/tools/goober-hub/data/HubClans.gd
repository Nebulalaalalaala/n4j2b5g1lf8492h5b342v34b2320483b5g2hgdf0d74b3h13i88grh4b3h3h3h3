extends Node
# Goobplayability clans (Supabase). One clan per player, up to 50 members,
# roles leader / officer / member, open or request-to-join.
signal changed
signal acted(action, ok, message)

const EMBLEMS = ["crown", "podium", "streak", "clock", "conqueror", "exploration", "builder"]
var api
var identity
var clans = {}        # clan id -> row (+ "count")
var members = {}      # clan id -> [{"user_id", "role", "joined_at"}]
var requests = {}     # clan id -> [user id]
var mine = ""         # your clan id or ""
var status = "idle"
var _fetched = 0
var _pending_action = ""
var pending_post = {}   # feed event to post when this action succeeds

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	api.connect("done", self, "_done")

func fetch(force = false):
	if not force and OS.get_unix_time() - _fetched < 60:
		return
	_fetched = OS.get_unix_time()
	status = "loading"
	api.select("hub_clans?select=*&order=created_at.asc&limit=500", "clans")
	api.select("hub_clan_members?select=*&limit=5000", "clan_members")
	api.select("hub_clan_requests?select=*&limit=2000", "clan_requests")

func _done(tag, ok, data, message):
	if tag == "clans":
		status = "ready" if ok else ("missing" if message == "missing" else "error")
		if ok and data is Array:
			clans = {}
			for r in data:
				clans[str(r.id)] = r
		emit_signal("changed")
	elif tag == "clan_members" and ok and data is Array:
		members = {}
		mine = ""
		for r in data:
			var list = members.get(str(r.clan_id), [])
			list.append(r)
			members[str(r.clan_id)] = list
			if str(r.user_id) == identity.user_id:
				mine = str(r.clan_id)
		emit_signal("changed")
	elif tag == "clan_requests" and ok and data is Array:
		requests = {}
		for r in data:
			var list = requests.get(str(r.clan_id), [])
			list.append(str(r.user_id))
			requests[str(r.clan_id)] = list
		emit_signal("changed")
	elif tag == "clan_action":
		if not ok and message.find("not allowed") >= 0:
			identity.refused()
		emit_signal("acted", _pending_action, ok, _friendly(message) if not ok else str(data) if data != null else "ok")
		fetch(true)

func _friendly(message):
	var known = {"leave your clan first": "Leave your clan first.", "invalid name or tag": "Names are 3-24 letters or numbers, tags 2-5.",
		"try again tomorrow": "You can found two clans a day. Try again tomorrow.", "clan is full": "This clan is full.",
		"links and contact details": "Links and contact details aren't allowed.", "not allowed": "You can't do that.",
		"hub_clans_name": "That clan name is taken.", "hub_clans_tag": "That tag is taken."}
	for k in known:
		if message.find(k) >= 0:
			return known[k]
	return "Something went wrong. Try again."

func act(action, clan_id = "", target = "", data = {}):
	if not identity.signed_in():
		emit_signal("acted", action, false, "Goober Hub isn't signed in yet.")
		return
	_pending_action = action
	api.call_fn("hub_clan", identity.auth({"p_action": action, "p_clan": clan_id if not str(clan_id).empty() else null,
		"p_target": target if not str(target).empty() else null, "p_data": data}), "clan_action")

func clan_of(user_id) -> String:
	for id in members:
		for m in members[id]:
			if str(m.user_id) == str(user_id):
				return id
	return ""

func role_of(user_id, clan_id) -> String:
	for m in members.get(str(clan_id), []):
		if str(m.user_id) == str(user_id):
			return str(m.role)
	return ""

func member_ids(clan_id) -> Array:
	var list = []
	for m in members.get(str(clan_id), []):
		list.append(str(m.user_id))
	return list

func listing(query = "") -> Array:
	var list = []
	for id in clans:
		var c = clans[id].duplicate()
		c.count = members.get(id, []).size()
		if query.empty() or str(c.name).to_lower().find(query.to_lower()) >= 0 or str(c.tag).to_lower().find(query.to_lower()) >= 0:
			list.append(c)
	list.sort_custom(self, "_bigger")
	return list

func _bigger(a, b):
	return int(a.count) > int(b.count) if int(a.count) != int(b.count) else str(a.name) < str(b.name)
