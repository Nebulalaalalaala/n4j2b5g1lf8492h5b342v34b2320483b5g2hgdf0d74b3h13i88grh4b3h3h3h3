extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Goob Builder: the signed-in account's published levels, read with the same
# calls the level editor's MY LEVELS tab uses (levels_query_my_levels, then
# levels_editor_get once per newly published level to count its objects).
# Read-only and rare: the list at most once every REFRESH seconds, one level at
# a time with a pause between, and a published level (locked by the game) is
# never downloaded twice. Cached per account in journey/<sha>.builder.json.
signal updated

const REFRESH = 21600
const MIN_OBJECTS = 200
const DIRECTORY = "user://goobplayability/journey"
var account_id = ""
var data = {}
var busy = false
var fetching = true
var checked = 0.0
var _queue = []

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS

func configure(owner):
	if str(owner) == account_id:
		return
	account_id = str(owner)
	data = _read()
	_queue = []

# Summary for the achievement: null until the first check has finished.
func summary():
	if account_id.empty() or int(data.get("checked_at", 0)) == 0:
		return null
	var levels = []
	for id in data.get("levels", {}):
		var level = data.levels[id]
		if level is Dictionary and bool(level.get("public", false)) and level.has("objects"):
			levels.append({"id": str(id), "name": str(level.get("name", "")), "objects": int(level.objects), "time": int(level.get("time", 0)),
				"qualifies": int(level.objects) > MIN_OBJECTS, "certified": _certified(str(id))})
	return {"levels": levels, "checked_at": int(data.checked_at)}

func _process(delta):
	checked += delta
	if checked < 10.0 or busy or account_id.empty() or not fetching:
		return
	checked = 0.0
	var moonlight = get_node_or_null("/root/Moonlight")
	if moonlight == null or moonlight.session == null:
		return
	if not _queue.empty():
		busy = true
		_download(moonlight, _queue.pop_front())
	elif OS.get_unix_time() - int(data.get("list_at", 0)) >= REFRESH:
		busy = true
		_list(moonlight)

func _list(moonlight):
	var owner = account_id
	var response = yield(moonlight.call_rpc("levels_query_my_levels", {}, false, true), "completed")
	busy = false
	if owner != account_id or not response is Dictionary or response.has("error") or not response.get("levels") is Array:
		checked = -290.0
		return
	var levels = data.get("levels", {})
	var seen = {}
	for level in response.levels:
		if not level is Dictionary:
			continue
		var id = str(level.get("id", level.get("uuid", "")))
		if id.empty():
			continue
		seen[id] = true
		var entry = levels.get(id, {})
		entry.name = str(level.get("level_name", level.get("name", "")))
		entry.public = str(level.get("pub_state", level.get("published", ""))) == "Public"
		entry.time = int(level.get("update_time", entry.get("time", 0)))
		levels[id] = entry
		if entry.public and not entry.has("objects"):
			_queue.append(id)
	for id in levels.keys():
		if not seen.has(id):
			levels.erase(id)
	data.levels = levels
	data.list_at = OS.get_unix_time()
	if _queue.empty():
		_done()
	else:
		_write()

func _download(moonlight, id):
	var owner = account_id
	var response = yield(moonlight.call_rpc("levels_editor_get", {"id": id}, false, true, true), "completed")
	busy = false
	checked = 8.5
	if owner != account_id or not response is Dictionary or response.has("error"):
		_queue.clear()
		checked = -290.0
		return
	var text = str(response.get("data", response.get("level_data", "")))
	var parsed = JSON.parse(text)
	if parsed.error == OK and parsed.result is Dictionary and parsed.result.get("nodes") is Array and data.get("levels", {}).has(id):
		data.levels[id].objects = parsed.result.nodes.size()
	if _queue.empty():
		_done()
	else:
		_write()

func _done():
	data.checked_at = OS.get_unix_time()
	_write()
	emit_signal("updated")

func _certified(id) -> bool:
	for level in load(ModPaths.path("JourneyCertified.gd")).load_cache().get("levels", []):
		if str(level.get("id", "")) == id:
			return true
	return false

func _path():
	return DIRECTORY.plus_file(account_id.sha256_text() + ".builder.json")

func _read() -> Dictionary:
	var file = File.new()
	if account_id.empty() or file.open(_path(), File.READ) != OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}

func _write():
	Directory.new().make_dir_recursive(DIRECTORY)
	var file = File.new()
	if file.open(_path(), File.WRITE) == OK:
		file.store_string(JSON.print(data, "\t"))
		file.close()
