extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Shared pieces for Goober Hub pages: activity cards, player rows, columns.
var screen
var ui
var hub

func columns(parent, left_ratio = 1.6):
	var row = ui.box(parent, false, 22)
	ui.grow(row)
	var left = ui.box(row, true, 18)
	ui.grow(left, true, false, left_ratio)
	var right = ui.box(row, true, 18)
	ui.grow(right, true, false, 1.0)
	return [left, right]

static func clock(seconds) -> String:
	seconds = max(0.0, float(seconds))
	if seconds < 60.0:
		return "%.2fs" % seconds
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]

func badge_name(key) -> String:
	for c in load(ModPaths.path("JourneyAchievements.gd")).COLLECTIONS:
		if c[0] == str(key):
			return str(c[1])
	return str(key).capitalize()

func badge_emblem(key) -> String:
	for c in load(ModPaths.path("JourneyAchievements.gd")).COLLECTIONS:
		if c[0] == str(key):
			return str(c[3])
	return "crown"

# [sentence after the name, detail line, glyph, color]
func describe(e) -> Array:
	var d = e.get("data", {}) if e.get("data") is Dictionary else {}
	match str(e.kind):
		"rank": return ["reached " + str(d.get("rank", "a new rank")), "Journey rank", "xp", ui.GOLD]
		"badge": return ["earned \"%s\" in Journey" % badge_name(d.get("key", "")), str(d.get("tier_name", "")) + " badge", "achievements", ui.LILAC]
		"pb": return ["set a new personal record on " + str(d.get("map", "a map")), clock(d.get("time", 0)) + (" · %.2fs faster" % float(d.get("better", 0)) if float(d.get("better", 0)) > 0 else ""), "stopwatch", ui.MINT]
		"wins": return ["reached %s wins" % ui.thousands(int(d.get("count", 0))), "Win milestone", "crown", ui.GOLD]
		"maps": return ["has played %d different maps" % int(d.get("count", 0)), "Explorer", "maps", ui.SKY]
		"streak": return ["hit a %d-win streak" % int(d.get("count", 0)), "Best streak", "sparkle", ui.HUB_PINK]
		"level": return ["got a level certified: " + str(d.get("name", "")), "Creator", "hammer", ui.SKY]
		"clan_found": return ["founded the clan " + str(d.get("clan", "")), "[%s]" % str(d.get("tag", "")), "crown", ui.LILAC]
		"clan_join": return ["joined " + str(d.get("clan", "")), "[%s]" % str(d.get("tag", "")), "crown", ui.LILAC]
	return ["did something", "", "star", ui.SOFT]

func event_card(parent, e, show_name = true):
	var info = describe(e)
	var who = str(e.user_id)
	var name = hub.profiles.name_for(who) if who != hub.store.account else "You"
	var card = ui.surface(parent, ui.PANEL, 16, 22)
	ui.clickable(card, screen, "show_profile", who, ui.INSET)
	var col = ui.box(card, true, 10)
	var row = ui.box(col, false, 14)
	ui.tile_icon(row, info[2], info[3], 54)
	var words = ui.box(row, true, 2)
	ui.grow(words)
	var line = ui.wrap(words, (name + " " if show_name else "") + info[0], 21, ui.WHITE)
	line.add_font_override("font", ui.font("text", 21))
	ui.text(words, _meta(info[1], e), 15, ui.DIM)
	_reactions(col, e)
	return card

func _meta(detail, e) -> String:
	var parts = []
	if not str(detail).empty(): parts.append(str(detail))
	parts.append(ui.ago(e.get("at", 0)))
	return PoolStringArray(parts).join("  ·  ")

func _reactions(parent, e):
	var by = hub.feed.reactions.get(str(e.id), {})
	var counts = {}
	for user in by:
		counts[by[user]] = int(counts.get(by[user], 0)) + 1
	var mine = by.get(hub.store.account, "")
	var row = ui.box(parent, false, 6)
	for r in ui.REACTIONS:
		var n = int(counts.get(r[0], 0))
		var b = ui.action(row, str(n) if n > 0 else "", self, "_react", [e.id, r[0]], "selected" if mine == r[0] else "quiet", ui.REACTION_GLYPHS[r[0]], ui.HUB_PINK)
		b.rect_min_size = Vector2(b.rect_min_size.x - 24 if n > 0 else 48, 38)
		b.hint_tooltip = r[1]
		b.disabled = not hub.identity.signed_in()

func _react(pair):
	hub.feed.react(pair[0], pair[1])

func player_row(parent, user_id, detail = "", glyph_actions = []):
	var panel = ui.inset(parent, 12, 18)
	ui.clickable(panel, screen, "show_profile", str(user_id), ui.EDGE)
	var row = ui.box(panel, false, 12)
	var name = hub.profiles.name_for(user_id)
	ui.goober(row, hub.profiles.look_for(user_id), 46, user_id)
	var col = ui.box(row, true, 0)
	ui.grow(col)
	var top = ui.box(col, false, 8)
	ui.title(top, name, 22)
	var clan = hub.clans.clans.get(hub.clans.clan_of(user_id), {})
	if not clan.empty():
		ui.tag(top, str(clan.get("tag", "")), ui.CLAN_COLORS[int(clan.get("color", 0)) % 8])
	if not str(detail).empty():
		ui.text(col, detail, 15, ui.DIM)
	for a in glyph_actions:
		var b = ui.action(row, a[0], a[1], a[2], a[3], a[4] if a.size() > 4 else "quiet", a[5] if a.size() > 5 else "")
		b.rect_min_size.y = 40
	return panel

func rank_text(user_id) -> String:
	if str(user_id) == hub.store.account:
		var model = hub.journey_model()
		if not model.empty() and model.get("rank") != null:
			return str(model.rank.name)
	var r = hub.profiles.row(user_id)
	return str(r.get("journey_rank", r.get("rank", "")))

func offline_note(parent):
	var state = hub.identity.state
	if state == "ready":
		return false
	var text = {"signed_out": ["Sign in to GooberDash", "Goober Hub uses your GooberDash account."],
		"checking": ["Connecting to Goober Hub", "This takes a moment the first time."],
		"missing": ["Goober Hub isn't set up yet", "The server tables and the hub-verify function need to be added in Supabase."],
		"failed": ["Couldn't reach Goober Hub", "Press refresh to try again."]}.get(state, ["Offline", ""])
	ui.empty(parent, text[0], text[1], "session", ui.SKY)
	return true
