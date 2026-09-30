extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# One-off: writes the shape of the signed-in account's game data (Moonlight storage,
# filled from player_fetch_data at login) as field names and value kinds only.
# No values are written, so no email, ids, tokens or wallet amounts.
const OUT = ModPaths.DIAGNOSTICS_DIR + "/player-data-outline.txt"
const MAX_LINES = 1500
const MANY_KEYS = 40   # bigger dictionaries (e.g. cosmetics by id) show one sample entry

var lines = []

func save(tree: SceneTree) -> String:
	var moonlight = tree.root.get_node_or_null("Moonlight")
	var storage = moonlight.get("storage") if moonlight != null else null
	if storage == null or not storage.get("data") is Dictionary or storage.data.empty():
		return "Sign in first; the game data isn't loaded yet."
	lines = ["Goobplayability player data outline (field names and kinds only)", ""]
	_walk(storage.data, "", 0)
	Directory.new().make_dir_recursive(OUT.get_base_dir())
	var file = File.new()
	if file.open(OUT, File.WRITE) != OK:
		return "Couldn't write the outline."
	file.store_string(PoolStringArray(lines).join("\n"))
	file.close()
	return "Saved tas_diagnostics/player-data-outline.txt"

func _walk(value, path: String, depth: int) -> void:
	if lines.size() >= MAX_LINES or depth > 10:
		return
	if value is Dictionary:
		var keys = value.keys()
		keys.sort()
		if keys.size() > MANY_KEYS:
			lines.append("%s: %d entries, e.g." % [path, keys.size()])
			_walk(value[keys[0]], path + ".<key>", depth + 1)
			return
		for key in keys:
			_walk(value[key], (path + "." if not path.empty() else "") + str(key), depth + 1)
	elif value is Array:
		lines.append("%s: list of %d" % [path, value.size()])
		if not value.empty():
			_walk(value[0], path + "[]", depth + 1)
	elif value is String and _kind(value) == "JSON text":
		lines.append("%s: JSON text" % path)
		_walk(JSON.parse(value).result, path, depth + 1)
	else:
		lines.append("%s: %s" % [path, _kind(value)])

func _kind(value) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true/false"
		TYPE_INT, TYPE_REAL:
			return "date (unix)" if value > 1400000000 and value < 2200000000 else "number"
		TYPE_STRING:
			var text = str(value)
			if text.length() >= 19 and text.substr(4, 1) == "-" and text.substr(10, 1) == "T":
				return "date (text)"
			if text.begins_with("{") or text.begins_with("["):
				var parsed = JSON.parse(text)
				if parsed.error == OK:
					return "JSON text"
			return "text"
	return "value"
