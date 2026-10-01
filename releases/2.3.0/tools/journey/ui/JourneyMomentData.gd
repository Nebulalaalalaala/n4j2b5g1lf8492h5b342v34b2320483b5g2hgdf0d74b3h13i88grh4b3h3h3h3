extends Reference

# Presentation only. Never awards XP, persists settings, or contacts the server.
const ROW_ORDER = ["finish", "placement", "win", "sweep", "streak", "participation", "discovery", "other", "bonus"]
const ROWS = {
	"finish": ["Race completion", "flag"], "placement": ["Placement", "podium"],
	"win": ["Match win", "crown"], "participation": ["Participation", "activity"],
	"sweep": ["Clean sweep", "crown"], "streak": ["Win streak", "crown"],
	"discovery": ["Discovery", "maps"], "other": ["Other rewards", "xp"],
	"bonus": ["Daily bonus", "sparkle"]
}

static func reward_rows(entries):
	var groups = {}
	var seen = {}
	for entry in entries:
		var id = str(entry.get("id", ""))
		if id.empty() or seen.has(id):
			continue
		seen[id] = true
		var reason = str(entry.get("reason", ""))
		var key = "other"
		if id.begins_with("daily-double:"):
			key = "bonus"
		elif reason == "Race finish":
			key = "finish"
		elif reason in ["Race podium", "Race first place"]:
			key = "placement"
		elif reason == "Clean sweep":
			key = "sweep"
		elif reason.begins_with("Win streak"):
			key = "streak"
		elif reason == "Overall match victory":
			key = "win"
		elif reason == "Participation":
			key = "participation"
		elif reason == "Map discovered":
			key = "discovery"
		groups[key] = int(groups.get(key, 0)) + int(entry.get("amount", 0))
	var result = []
	for key in ROW_ORDER:
		if int(groups.get(key, 0)) > 0:
			result.append({"key": key, "name": ROWS[key][0], "icon": ROWS[key][1], "amount": groups[key]})
	return result

static func daily_remaining(entries, owner, day):
	var games = {}
	for entry in entries:
		if str(entry.get("player_id", "")) == str(owner) and str(entry.get("daily_match_day", "")) == str(day):
			games[str(entry.get("related_id", ""))] = true
	games.erase("")
	return max(0, 10 - games.size())

static func previous_completion(records, map_id):
	var progress = {"finish": false, "first": false}
	for entry in records:
		if str(entry.get("map_id", "")) == str(map_id) and str(entry.get("mode", "")) == "match_round" and not bool(entry.get("custom", false)):
			progress.finish = progress.finish or str(entry.get("result", "")) == "finish"
			progress.first = progress.first or int(entry.get("placement", 0)) == 1
	return progress

static func preference(context, owner, key, fallback):
	if owner != null and is_instance_valid(owner.screen):
		return owner.screen.prefs.get(key, fallback)
	# HomeScene is freed in a match. Preferences live in SavedSettings, not
	# in that scene, and must still apply to gameplay notifications.
	var settings = context.get_node_or_null("/root/SavedSettings") if context.is_inside_tree() else null
	return settings.get_value("journey_pref_" + key, fallback) if settings != null else fallback

# Matches the native Play button's fixed diagonal fade, not a moving sweep.
static func shine(button):
	var clip = Control.new()
	clip.name = "NativeShine"
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.rect_clip_content = true
	button.add_child(clip)
	clip.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var gradient = Gradient.new()
	gradient.colors = PoolColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5)])
	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 256
	texture.fill_from = Vector2(0, 1)
	texture.fill_to = Vector2(0, 0)
	var stripe = TextureRect.new()
	stripe.texture = texture
	stripe.expand = true
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.anchor_left = 0.5
	stripe.anchor_right = 0.5
	stripe.anchor_bottom = 1.0
	stripe.margin_left = -20
	stripe.margin_right = 40
	stripe.margin_top = -28
	stripe.margin_bottom = 90
	stripe.rect_rotation = 18.8
	clip.add_child(stripe)
