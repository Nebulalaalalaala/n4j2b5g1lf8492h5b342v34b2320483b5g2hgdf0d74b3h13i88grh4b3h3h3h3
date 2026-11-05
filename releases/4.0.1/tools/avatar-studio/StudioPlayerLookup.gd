extends Node

# Avatar Studio, Looks page: find a player by name (or user ID) and wear their
# profile look locally, then save it like any other Look.
# The server refuses username lookups (see 15_leaderboard_search.gd), so names
# come from players the mod already knows: the wins leaderboard snapshot and
# profiles the Goober Hub has loaded. A full user ID always works.
const ModPaths = preload("user://mod/core/ModPaths.gd")
const COOLDOWN_MSEC = 3000
const MAX_RESULTS = 6

var studio
var field: LineEdit
var results: VBoxContainer
var note: Label
var _names = {}          # user id -> name
var _names_loaded = false
var _next_request = 0
var _busy = false

func build(parent: Node) -> void:
	parent.add_child(studio.label("Player look", 16, studio.DIM))
	var r = studio.row(parent)
	field = LineEdit.new()
	field.placeholder_text = "Username or user ID"
	field.max_length = 64
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_font_override("font", studio.font(16))
	field.connect("text_entered", self, "_find")
	r.add_child(field)
	var find = studio.button("Find", "")
	find.connect("pressed", self, "_find_pressed")
	r.add_child(find)
	results = VBoxContainer.new()
	results.add_constant_override("separation", 6)
	parent.add_child(results)
	note = studio.label("", 13, studio.DIM)
	note.autowrap = true
	parent.add_child(note)

func _find_pressed() -> void:
	_find(field.text)

func _find(text: String) -> void:
	var query = text.strip_edges()
	for child in results.get_children():
		child.queue_free()
	if query.empty():
		note.text = "Type a name or a user ID."
		return
	if _is_user_id(query):
		_load(query.to_lower(), "")
		return
	var matches = search(query)
	if matches.empty():
		note.text = "No player found with that name. Players show up here once they are on the wins leaderboard or you have opened their profile. A full user ID always works."
		return
	if matches.size() == 1 or matches[0].name.to_lower() == query.to_lower():
		_load(matches[0].id, matches[0].name)
		return
	note.text = "Pick a player."
	for entry in matches:
		var b = studio.button(entry.name, "")
		b.align = Button.ALIGN_LEFT
		b.connect("pressed", self, "_load", [entry.id, entry.name])
		results.add_child(b)

# Exact name first, then names starting with the text, then names containing it.
func search(query: String) -> Array:
	_load_names()
	var q = query.to_lower()
	var exact = []
	var starts = []
	var contains = []
	for id in _names:
		var name = str(_names[id])
		var low = name.to_lower()
		if low == q:
			exact.append({"id": id, "name": name})
		elif low.begins_with(q):
			starts.append({"id": id, "name": name})
		elif q.length() >= 3 and low.find(q) >= 0:
			contains.append({"id": id, "name": name})
	var found = exact + starts + contains
	return found.slice(0, MAX_RESULTS - 1) if found.size() > MAX_RESULTS else found

func _load_names() -> void:
	var hub = studio.tool_ref.get_node_or_null("GooberHub") if studio.tool_ref != null else null
	var profiles = hub.get("profiles") if hub != null else null
	if profiles != null and profiles.get("native") is Dictionary:
		for id in profiles.native:
			var name = str(profiles.native[id].get("name", ""))
			if not name.empty():
				_names[str(id)] = name
	if _names_loaded:
		return
	_names_loaded = true
	var f = File.new()
	if not f.file_exists(ModPaths.WINS_SNAPSHOTS) or f.open(ModPaths.WINS_SNAPSHOTS, File.READ) != OK:
		return
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var keys = parsed.result.keys()
	keys.sort()
	for key in keys:
		var snapshot = parsed.result[key]
		if typeof(snapshot) != TYPE_DICTIONARY or typeof(snapshot.get("rows")) != TYPE_ARRAY:
			continue
		for row in snapshot.rows:
			if typeof(row) == TYPE_DICTIONARY and _is_user_id(str(row.get("id", ""))) and not str(row.get("username", "")).empty():
				_names[str(row.id)] = str(row.username)

func _load(user_id: String, name: String) -> void:
	if _busy:
		return
	var now = OS.get_ticks_msec()
	if now < _next_request:
		note.text = "Wait a moment before loading another player."
		return
	var moonlight = get_node_or_null("/root/Moonlight")
	if moonlight == null or moonlight.get("session") == null:
		note.text = "Not logged in."
		return
	_busy = true
	_next_request = now + COOLDOWN_MSEC
	note.text = "Loading " + (name if not name.empty() else "player") + "..."
	var state = moonlight.call_rpc("query_player_profile", {"user_id": user_id}, false)
	var response = yield(state, "completed") if state is GDScriptFunctionState else state
	_busy = false
	if not is_instance_valid(studio):
		return
	if not response is Dictionary or response.has("error") or not response.get("skin") is Dictionary:
		note.text = "Could not load that player."
		return
	if name.empty():
		name = str(response.get("display_name", "Player"))
	var ids = []
	for key in response.skin:
		if not str(response.skin[key]).empty():
			ids.append(str(response.skin[key]))
	if ids.empty():
		note.text = name + " has no look to copy."
		return
	_names[user_id] = name
	for child in results.get_children():
		child.queue_free()
	studio.apply_outfit(ids)
	if studio.dev_match != null:
		studio.dev_match.observe(user_id, ids)
	studio.look_name.text = name + "'s look"
	note.text = "Wearing " + name + "'s look. Save as new to keep it."

func _is_user_id(s: String) -> bool:
	if s.length() != 36:
		return false
	for i in range(s.length()):
		var c = s[i]
		if c == "-":
			continue
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")):
			return false
	return true
