extends "user://mod/tools/autoplay/AutoplayBot/05_finish_route.gd"

func _dump_current_level_for_diagnostics() -> void:
	var scene = get_tree().current_scene
	if scene == null or not ("parameters" in scene):
		return
	var parameters = scene.get("parameters")
	if parameters == null:
		return
	var level_data_string := ""
	if "level_data_string" in parameters:
		level_data_string = str(parameters.get("level_data_string"))
	if level_data_string.empty() and "level_data" in parameters:
		var level_data = parameters.get("level_data")
		if typeof(level_data) == TYPE_DICTIONARY and not level_data.empty():
			level_data_string = to_json(level_data)
	if level_data_string.empty():
		return
	var level_id := str(parameters.get("level_id")) if "level_id" in parameters else ""
	if level_id.empty():
		level_id = "local_%d" % int(OS.get_unix_time())
	var safe_level_id := level_id.replace("/", "_").replace("\\", "_").replace(":", "_")
	var directory := Directory.new()
	var diagnostics_dir := ModPaths.DIAGNOSTICS_DIR
	if not directory.dir_exists(diagnostics_dir):
		directory.make_dir_recursive(diagnostics_dir)
	var path := diagnostics_dir.plus_file("autoplay_level_%s.json" % safe_level_id)
	var file := File.new()
	if file.open(path, File.WRITE) == OK:
		file.store_string(level_data_string)
		file.close()


func _log(message: String) -> void:
	if tas_tool != null and not message.empty():
		tas_tool.call("_log_action", message, null)
