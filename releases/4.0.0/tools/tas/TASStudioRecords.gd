extends Reference

# Autosave of the working run and gold splits (best time per section).
# Autosave writes from a thread so a long run never stalls a frame.
# Golds are matched by where a section starts and ends, so the same
# checkpoints placed in a later attempt compare against earlier ones.

const DATA_DIR = "user://goobplayability/"
const RECOVERY_PATH = DATA_DIR + "tas_recovery.tasmacro"
const PREVIOUS_PATH = DATA_DIR + "tas_recovery.previous.tasmacro"
const RESTART_PATH = DATA_DIR + "tas_before_section_restart.tasmacro"
const GOLDS_PATH = DATA_DIR + "tas_golds.dat"
const AUTOSAVE_EVERY = 30.0
const MATCH_DISTANCE = 24.0

var studio = null
var elapsed = 0.0
var check_elapsed = 0.0
var last_signature = ""
var last_checkpoints = 0
var saved_revision = -1
var thread = null
var golds = {}
var golds_dirty = false
var new_golds = {}   # "a:b" -> true for golds set this session

func setup(owner) -> void:
	studio = owner
	var file = File.new()
	if file.open(GOLDS_PATH, File.READ) == OK:
		var loaded = file.get_var(false)
		file.close()
		if typeof(loaded) == TYPE_DICTIONARY:
			golds = loaded


func tick(delta: float) -> void:
	if thread != null and not thread.is_alive():
		thread.wait_to_finish()
		thread = null
	check_elapsed += delta
	if check_elapsed < 2.0:
		return
	check_elapsed = 0.0
	elapsed += 2.0
	var tool = studio.tool
	if tool == null or studio.busy():
		return
	var game = tool._find_game()
	if game == null or not game.is_server() or tool._tool_restricted():
		return # never copy/label a previous solo project during a public match
	var checkpoints = tool._practice_checkpoints.size()
	if checkpoints != last_checkpoints:
		last_checkpoints = checkpoints
		_update_golds()
		save_recovery()
	elif elapsed >= AUTOSAVE_EVERY or (studio.revision != saved_revision and elapsed >= 4.0):
		save_recovery()
	if golds_dirty:
		golds_dirty = false
		var file = File.new()
		Directory.new().make_dir_recursive(DATA_DIR)
		if file.open(GOLDS_PATH, File.WRITE) == OK:
			file.store_var(golds, false)
			file.close()


# ---------------------------------------------------------------- autosave

# The tool's run is saved as a normal format-3 macro, so old playback keeps
# working. "studio" carries what the macro format can't: the part of the run
# after the cursor, sections with their takes, and markers.
func save_recovery() -> void:
	elapsed = 0.0
	var tool = studio.tool
	if thread != null or tool._practice_checkpoints.empty():
		return
	studio.sync()
	var segments = tool._practice_segments.duplicate()
	if not tool._practice_current_segment.empty():
		segments.append(tool._practice_current_segment.duplicate())
	var count = 0
	for segment in segments:
		count += segment.size()
	var signature = "%d:%d:%d:%d" % [studio.revision, tool._practice_checkpoints.size(), count, studio.full.size()]
	if signature == last_signature or count == 0:
		return
	var checkpoints = tool._practice_checkpoints.duplicate()
	var context = tool._capture_current_time_trial_level_context()
	var data = {"format_version": 3, "checkpoints": checkpoints, "segments": segments, "level_id": str(context.get("level_id", "")), "level_name": str(context.get("level_name", "")), "saved_at": OS.get_unix_time(), "frames": count, "studio": studio.project_data(count)}
	thread = Thread.new()
	if thread.start(self, "_write", data) != OK:
		thread = null
		_write(data)
	last_signature = signature
	saved_revision = studio.revision


# Write a temporary file, check it reads back, keep the previous save, then
# swap. A crash mid-write leaves the last good save in place.
func _write(data: Dictionary) -> void:
	_write_checked(data, RECOVERY_PATH, PREVIOUS_PATH)


func _write_checked(data: Dictionary, path: String, previous := "") -> bool:
	var directory = Directory.new()
	directory.make_dir_recursive(DATA_DIR)
	var temporary = path + ".tmp"
	var file = File.new()
	if file.open(temporary, File.WRITE) != OK:
		return false
	file.store_var(data, false)
	file.close()
	if file.open(temporary, File.READ) != OK:
		return false
	var check = file.get_var(false)
	file.close()
	if typeof(check) != TYPE_DICTIONARY or not check.has("segments"):
		return false
	# Keep the old file until the new one has been read successfully.
	var old = previous if not previous.empty() else path+".previous"
	if directory.file_exists(path):
		if directory.file_exists(old) and directory.remove(old)!=OK: return false
		if directory.rename(path, old)!=OK: return false
	if directory.rename(temporary, path)!=OK:
		if directory.file_exists(old): directory.rename(old,path)
		return false
	return true


func capture_restart_data() -> Dictionary:
	studio.sync()
	if studio.full.empty() and studio.sections.empty(): return {}
	if studio.full.empty():
		var has_takes = false
		for section in studio.sections:
			if not section.get("takes",[]).empty(): has_takes = true
		if not has_takes: return {} # An empty retry must not overwrite a real run's backup.
	var data = studio._working_macro_data()
	data.erase("studio_project")
	var context = studio.tool._capture_current_time_trial_level_context()
	data["level_id"] = str(context.get("level_id",""))
	data["level_name"] = str(context.get("level_name",""))
	data["saved_at"] = OS.get_unix_time()
	data["frames"] = studio.full.size()
	data["studio"] = studio.project_data(studio.full.size())
	return data.duplicate(true)


func save_before_restart(data: Dictionary) -> bool:
	return data.empty() or _write_checked(data,RESTART_PATH)


func has_restart_backup() -> bool:
	return File.new().file_exists(RESTART_PATH)


func restore_before_restart() -> String:
	if studio.busy() or (studio.bots!=null and studio.bots.busy()): return "Stop the current attempt before restoring"
	return _restore(_read_data(RESTART_PATH),"the run before the last restart")


func _read_data(path: String) -> Dictionary:
	var file = File.new()
	if file.open(path,File.READ)!=OK: return {}
	var data = file.get_var(false)
	file.close()
	return data if data is Dictionary and data.has("segments") and data.has("checkpoints") else {}


func recovery_info() -> Dictionary:
	for path in [RECOVERY_PATH, PREVIOUS_PATH]:
		var file = File.new()
		if not file.file_exists(path) or file.open(path, File.READ) != OK:
			continue
		var data = file.get_var(false)
		file.close()
		if typeof(data) == TYPE_DICTIONARY and data.has("segments") and data.has("checkpoints"):
			return data
	return {}


# Autosave for the level that's open, when nothing is recorded yet.
func offer_text() -> String:
	var tool = studio.tool
	if tool == null or not tool._practice_checkpoints.empty() or tool._get_local_player() == null:
		return ""
	var data = recovery_info()
	if data.empty() or str(data.get("level_id", "")) != level_key():
		return ""
	var date = OS.get_datetime_from_unix_time(int(data.get("saved_at", 0)) + int(OS.get_time_zone_info().get("bias", 0)) * 60)
	return "Unsaved run from %02d:%02d can be restored (Tools tab)" % [date.hour, date.minute]


func restore_recovery() -> String:
	var data = recovery_info()
	return _restore(data,"the autosaved run")


func _restore(data: Dictionary, description: String) -> String:
	if data.empty():
		return "No saved recovery run"
	var tool = studio.tool
	if studio.busy() or (studio.bots!=null and studio.bots.busy()): return "Stop the current attempt before restoring"
	var game = tool._find_game()
	if game!=null and tool._practice_restart_from_game_id==game.get_instance_id(): return "Wait for the level restart before restoring"
	if tool._get_local_player() == null:
		return "Open the level first"
	var context = tool._capture_current_time_trial_level_context()
	if not str(data.get("level_id", "")).empty() and str(context.get("level_id", "")) != str(data.get("level_id", "")):
		return "Open %s before restoring" % (str(data.get("level_name", "")) if not str(data.get("level_name", "")).empty() else "the original level")
	studio.cancel_practice_request()
	studio.segment_pending_start = false
	tool._practice_start_waiting = false
	tool._practice_restart_from_game_id = 0
	tool._stop_practice_mode()
	if not tool._install_editor_data_as_current(data):
		return "Couldn't restore the autosave"
	studio.sync()
	if data.get("studio") is Dictionary:
		studio.load_project_data(data.studio)
	return "Restored %s (%d frames)" % [description,studio.full.size()]


# ---------------------------------------------------------------- golds

func level_key() -> String:
	var tool = studio.tool
	var context = tool._capture_current_time_trial_level_context()
	if not str(context.get("level_id", "")).empty():
		return str(context.level_id)
	var game = tool._find_game()
	if game != null and game.level != null and game.level.loaded_level != null and "level_id" in game.level.loaded_level:
		return str(game.level.loaded_level.level_id)
	return ""


func _entry(level: Array, a: Vector2, b: Vector2):
	for entry in level:
		if entry.a.distance_to(a) <= MATCH_DISTANCE and entry.b.distance_to(b) <= MATCH_DISTANCE:
			return entry
	return null


# Checkpoint splits and marked sections keep separate golds, so a practice
# section never shows up as a checkpoint split or the other way round.
func gold_for(a, b, kind := ""):
	if a == null or b == null:
		return null
	var key = level_key() + kind
	if key.empty() or not golds.has(key):
		return null
	var entry = _entry(golds[key], a, b)
	return null if entry == null else int(entry.frames)


func offer(a, b, frames: int, kind := "") -> bool:
	if a == null or b == null or frames <= 0:
		return false
	if level_key().empty():
		return false
	var key = level_key() + kind
	if not golds.has(key):
		golds[key] = []
	var entry = _entry(golds[key], a, b)
	if entry == null:
		golds[key].append({"a": a, "b": b, "frames": frames})
		golds_dirty = true
		return true
	if frames < int(entry.frames):
		entry.frames = frames
		golds_dirty = true
		new_golds["%s:%s" % [str(a), str(b)]] = true
		return true
	return false


func _update_golds() -> void:
	studio.sync()
	for index in range(studio.bounds.size() - 1):
		if studio.bounds[index + 1] > studio.verified or index + 1 >= studio.snaps.size():
			continue
		var a = studio.snaps[index].get("position")
		var b = studio.snaps[index + 1].get("position")
		offer(a, b, studio.bounds[index + 1] - studio.bounds[index])


func on_take(section: Dictionary, frames: int) -> void:
	offer(studio.position_at(section.start), studio.position_at(section.end), frames, "|sections")


func section_gold(section: Dictionary):
	return gold_for(studio.position_at(section.start), studio.position_at(section.end), "|sections")


# Checkpoint split rows for the window: label, frames, gold or null.
func split_rows() -> Array:
	var rows = []
	for index in range(studio.bounds.size()):
		var last = studio.bounds[index + 1] if index + 1 < studio.bounds.size() else studio.full.size()
		var a = studio.snaps[index].get("position") if index < studio.snaps.size() else null
		var b = studio.snaps[index + 1].get("position") if index + 1 < studio.snaps.size() else null
		rows.append({"label": ("%d to %d" % [index, index + 1]) if b != null else ("%d to end" % index), "frames": last - studio.bounds[index], "gold": gold_for(a, b)})
	return rows


func sum_of_best() -> Dictionary:
	var total = 0
	var known = 0
	var rows = split_rows()
	for row in rows:
		if row.gold != null:
			total += int(row.gold)
			known += 1
	return {"frames": total, "known": known, "sections": rows.size()}
