extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

var directory = ModPaths.EDITOR_PLUS_RECOVERY
var last_hash = ""
const LIMIT = 20
const MAX_BYTES = 2 * 1024 * 1024

func _snapshot_name(name: String) -> bool:
	if name.get_file() != name or not name.ends_with(".json"):
		return false
	var parts = name.trim_suffix(".json").split("_")
	if not parts.size() in [3, 4] or parts[0] != "snapshot" or parts[1].length() != 12 or parts[2].length() != 10:
		return false
	for index in range(1, parts.size()):
		if parts[index].empty():
			return false
		for character in parts[index]:
			if not str(character) in "0123456789":
				return false
	return true

func _files() -> Array:
	var result = []
	var dir = Directory.new()
	if dir.open(directory) != OK:
		return result
	dir.list_dir_begin(true, true)
	var name = dir.get_next()
	while not name.empty():
		if not dir.current_is_dir() and _snapshot_name(name):
			result.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	result.invert()
	return result

func _envelope(name: String) -> Dictionary:
	if not _snapshot_name(name):
		return {}
	var file = File.new()
	if file.open(directory.plus_file(name), File.READ) != OK:
		return {}
	if file.get_len() > MAX_BYTES:
		file.close()
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		return {}
	var data = parsed.result
	if data.get("version", 0) != 1 or not data.get("payload", null) is String or not data.get("reason", null) is String:
		return {}
	if data.payload.sha256_text() != data.get("checksum", ""):
		return {}
	if not data.get("name", null) is String or not typeof(data.get("time", null)) in [TYPE_INT, TYPE_REAL]:
		return {}
	if is_nan(float(data.time)) or is_inf(float(data.time)):
		return {}
	return data

func read(name: String) -> Dictionary:
	var envelope = _envelope(name)
	if envelope.empty():
		return {}
	var parsed = JSON.parse(envelope.payload)
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}

func entries() -> Array:
	var result = []
	for name in _files():
		var envelope = _envelope(name)
		if envelope.empty():
			continue
		var age = max(0, int(OS.get_unix_time() - envelope.get("time", 0)))
		var when = "Just now" if age < 60 else ("%dm ago" % (age / 60) if age < 3600 else "%dh ago" % (age / 3600))
		result.append({"file": name, "label": "%s · %s\n%s" % [envelope.reason, when, envelope.get("name", "Untitled")]})
	return result

func save(level: Dictionary, reason: String, changed_only: bool) -> String:
	var payload = JSON.print(level)
	var checksum = payload.sha256_text()
	if changed_only and checksum == last_hash:
		return "No changes since the last snapshot."
	var text = JSON.print({"version": 1, "time": OS.get_unix_time(), "reason": reason, "name": str(level.get("metadata", {}).get("name", "Untitled")), "checksum": checksum, "payload": payload})
	if text.to_utf8().size() > MAX_BYTES:
		return "Snapshot skipped: level exceeds the 2 MB recovery limit."
	var dir = Directory.new()
	if dir.make_dir_recursive(directory) != OK and not dir.dir_exists(directory):
		return "Snapshot failed: recovery folder unavailable."
	var name = "snapshot_%012d_%010d.json" % [OS.get_unix_time(), OS.get_ticks_msec()]
	var target = directory.plus_file(name)
	var index = 0
	while dir.file_exists(target):
		index += 1
		name = "snapshot_%012d_%010d_%03d.json" % [OS.get_unix_time(), OS.get_ticks_msec(), index]
		target = directory.plus_file(name)
	var file = File.new()
	if file.open(target + ".tmp", File.WRITE) != OK:
		return "Snapshot failed: could not write recovery file."
	file.store_string(text)
	file.close()
	if dir.rename(target + ".tmp", target) != OK or _envelope(name).empty():
		return "Snapshot failed verification; previous snapshots preserved."
	last_hash = checksum
	var files = _files()
	if files.size() > LIMIT:
		for old in files.slice(LIMIT, files.size() - 1):
			dir.remove(directory.plus_file(old))
	return "Saved · " + reason

func valid_level(data: Dictionary, types: Array) -> bool:
	if not data.get("metadata", null) is Dictionary or not data.get("nodes", null) is Array or data.nodes.size() > 20000:
		return false
	for key in ["name", "game_mode", "theme", "published"]:
		if not data.metadata.get(key, null) is String:
			return false
	if not typeof(data.metadata.get("player_count")) in [TYPE_REAL, TYPE_INT]:
		return false
	for node in data.nodes:
		if not node is Dictionary or not node.get("type", "") in types:
			return false
		for key in ["x", "y", "width", "height", "rotation", "shape_rotation", "pivot_x", "pivot_y"]:
			var number = node.get(key, null)
			if not typeof(number) in [TYPE_REAL, TYPE_INT] or is_nan(float(number)) or is_inf(float(number)):
				return false
		if node.width <= 0 or node.height <= 0:
			return false
	return true
