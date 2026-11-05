extends Reference

# Mode presets (Racing / TAS / Building) and settings export / import.
# Presets only flip existing tool switches; nothing new is stored besides the
# chosen mode. Export writes Goobplayability's settings (never account data)
# to a JSON file in Documents.

const MODES = {
	"racing": {"name": "Racing", "note": "Performance and FPS / ping readout on; TAS overlays off", "performance": true, "readout": true, "hitbox": false, "trajectory": false, "input_display": false, "frame_info": false, "guides": null},
	"tas": {"name": "TAS", "note": "Hitboxes, input display and frame info on; readout on", "performance": null, "readout": true, "hitbox": true, "trajectory": false, "input_display": true, "frame_info": true, "guides": null},
	"building": {"name": "Building", "note": "Editor guides on; TAS overlays and readout off", "performance": null, "readout": false, "hitbox": false, "trajectory": false, "input_display": false, "frame_info": false, "guides": true},
}
const EXPORT_NAME = "Goobplayability-settings.json"
const PRIVATE_WORDS = ["token", "session", "account", "auth", "password", "email", "user_id", "device_id", "key_", "secret", "credential", "leaderboard", "supabase", "api", "webhook", "council_worker"]


func apply(owner_tool, mode: String) -> String:
	if not MODES.has(mode):
		return ""
	# A preset only changes panels and overlays; it never interrupts a job.
	if owner_tool.has_method("_tas_studio_busy") and owner_tool._tas_studio_busy():
		return "Wait for the TAS job or practice to finish, then pick the mode again"
	var spec = MODES[mode]
	var game_tools = owner_tool.get("_game_tools")
	if spec.performance != null and game_tools != null and game_tools.has_method("performance_enabled"):
		if bool(game_tools.performance_enabled()) != bool(spec.performance):
			game_tools._tool_card_pressed("performance")
	if spec.readout != null and game_tools != null and game_tools.get("_readout") != null:
		game_tools._readout.set_enabled(bool(spec.readout))
		game_tools._sync_cards()
	for entry in [["hitbox", "_hitbox_viewer_enabled", "_on_toggle_hitbox_viewer_pressed"], ["trajectory", "_trajectory_preview_enabled", "_on_toggle_trajectory_preview_pressed"], ["input_display", "_input_display_enabled", "_on_toggle_input_display_pressed"]]:
		if spec[entry[0]] == null or not owner_tool.has_method(entry[2]):
			continue
		if bool(owner_tool.get(entry[1])) != bool(spec[entry[0]]):
			owner_tool.call(entry[2])
	if spec.frame_info != null and owner_tool.has_method("_tas_studio") and owner_tool._tas_studio() != null:
		var studio = owner_tool._tas_studio()
		if studio.info_visible() != bool(spec.frame_info) and owner_tool.has_method("_on_toggle_frame_info_pressed") and owner_tool.get("_frame_info_button") != null:
			owner_tool._on_toggle_frame_info_pressed()
		elif studio.info_visible() != bool(spec.frame_info):
			studio.set_info_visible(bool(spec.frame_info))
	if spec.guides != null:
		SavedSettings.set_value("editor_align_guides", bool(spec.guides))
	SavedSettings.set_value("workspace_mode", mode)
	return "%s mode on: %s" % [spec.name, spec.note.to_lower()]


func _private(key: String) -> bool:
	var lower = key.to_lower()
	for word in PRIVATE_WORDS:
		if word in lower:
			return true
	return false


func export_path() -> String:
	if OS.get_name() == "Windows":
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).plus_file(EXPORT_NAME)
	return OS.get_user_data_dir().plus_file(EXPORT_NAME)


func export_settings() -> String:
	var config = SavedSettings.get("config_file")
	if config == null:
		return "Settings are not available"
	var data = {}
	for key in config.get_section_keys("main"):
		if not _private(str(key)):
			data[str(key)] = config.get_value("main", key)
	var file = File.new()
	if file.open(export_path(), File.WRITE) != OK:
		return "Couldn't write " + export_path()
	file.store_string(JSON.print({"goobplayability_settings": 1, "saved_at": OS.get_unix_time(), "settings": var2str(data)}, "\t"))
	file.close()
	return "Saved %d settings to %s" % [data.size(), export_path()]


func import_settings() -> String:
	var file = File.new()
	if not file.file_exists(export_path()) or file.open(export_path(), File.READ) != OK:
		return "Put %s in your Documents folder first" % EXPORT_NAME
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY or not parsed.result.has("settings"):
		return "That file isn't a Goobplayability settings export"
	var text = str(parsed.result.settings)
	# Plain values only: never let a file create objects.
	if "Object(" in text or "Resource(" in text or "ExtResource(" in text or "SubResource(" in text:
		return "That file isn't a Goobplayability settings export"
	var data = str2var(text)
	if typeof(data) != TYPE_DICTIONARY:
		return "That file isn't a Goobplayability settings export"
	# Keep a copy of the current settings first, then only take values whose
	# type matches what this version already stores.
	var config = SavedSettings.get("config_file")
	var backup = {}
	if config != null:
		for key in config.get_section_keys("main"):
			if not _private(str(key)):
				backup[str(key)] = config.get_value("main", key)
	var backup_file = File.new()
	var backup_path = export_path().get_base_dir().plus_file("Goobplayability-settings-before-import.json")
	if backup_file.open(backup_path, File.WRITE) == OK:
		backup_file.store_string(JSON.print({"goobplayability_settings": 1, "saved_at": OS.get_unix_time(), "settings": var2str(backup)}, "\t"))
		backup_file.close()
	var count = 0
	var skipped = 0
	for key in data:
		if _private(str(key)):
			continue
		if backup.has(str(key)) and typeof(backup[str(key)]) != typeof(data[key]):
			skipped += 1
			continue
		SavedSettings.set_value(str(key), data[key])
		count += 1
	var summary = "Loaded %d settings" % count
	if skipped > 0:
		summary += ", skipped %d that didn't fit this version" % skipped
	return summary + ". Your old settings were saved as Goobplayability-settings-before-import.json. Restart the game to apply everything."
