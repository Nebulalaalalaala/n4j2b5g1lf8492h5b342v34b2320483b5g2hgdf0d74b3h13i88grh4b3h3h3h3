extends "user://mod/core/TASTool/07_windows_2.gd"

# ----------------------------------------------------------------------
#  Native Settings integration / persistent client-tool visibility
# ----------------------------------------------------------------------
func _load_client_tool_preferences() -> void:
	# The Goobplayability GUI is always available now (F1 shows or hides it); the old off
	# switch lived in the game's settings and is gone, so a saved "off" is ignored.
	_tas_gui_enabled = true
	_sandbox_gui_enabled = bool(SavedSettings.get_value(SETTING_SANDBOX_GUI, true))
	_replay_hub_gui_enabled = bool(SavedSettings.get_value(SETTING_REPLAY_HUB_GUI, false))
	_game_tools_gui_enabled = bool(SavedSettings.get_value(SETTING_GAME_TOOLS_GUI, false))
	_social_hub_gui_enabled = bool(SavedSettings.get_value(SETTING_SOCIAL_HUB_GUI, true))
	_cosmetic_loadouts_gui_enabled = bool(SavedSettings.get_value(SETTING_COSMETIC_LOADOUTS_GUI, true))
	_editor_theme_pack_enabled = bool(SavedSettings.get_value(SETTING_EDITOR_THEME_PACK, true))
	_match_map_preview_enabled = bool(SavedSettings.get_value(SETTING_MATCH_MAP_PREVIEW, true))
	_wins_leaderboard_enabled = bool(SavedSettings.get_value(SETTING_WINS_LEADERBOARD, true))
	_leaderboard_search_enabled = bool(SavedSettings.get_value(SETTING_LEADERBOARD_SEARCH, true))
	_custom_lobby_code_enabled = bool(SavedSettings.get_value(SETTING_CUSTOM_LOBBY_CODE, true))
	_hitbox_viewer_enabled = bool(SavedSettings.get_value(SETTING_HITBOX_VIEWER, false))
	_trajectory_preview_enabled = bool(SavedSettings.get_value(SETTING_TRAJECTORY_PREVIEW, false))
	_input_display_enabled = bool(SavedSettings.get_value(SETTING_INPUT_DISPLAY, false))
	_input_display_detailed = bool(SavedSettings.get_value(SETTING_INPUT_DISPLAY_DETAILED, false))
	_input_display_hold_frames = bool(SavedSettings.get_value(SETTING_INPUT_DISPLAY_HOLD_FRAMES, false))
	_visual_seam_polish_enabled = bool(SavedSettings.get_value(SETTING_VISUAL_SEAM_POLISH, false))
	# Moving level geometry is part of deterministic playback, so new installs
	# and users who never touched this preference should get the safe behavior.
	# The toggle remains available for levels whose custom animation setup does
	# not tolerate seeking.
	_sync_moving_objects_enabled = bool(SavedSettings.get_value(SETTING_SYNC_MOVING_OBJECTS, true))
	_replay_check_stop_on_desync = bool(SavedSettings.get_value(SETTING_STOP_ON_DESYNC, false))
	_self_test_stop_on_failure = bool(SavedSettings.get_value(SETTING_SELF_TEST_STOP_ON_FAILURE, false))
	_update_checks_enabled = bool(SavedSettings.get_value(SETTING_UPDATE_CHECKS, true))
	_claude_experimental_icons_enabled = bool(SavedSettings.get_value(SETTING_CLAUDE_EXPERIMENTAL_ICONS, false))
	for category in _hitbox_categories.keys():
		_hitbox_categories[category] = bool(SavedSettings.get_value(SETTING_HITBOX_CATEGORY_PREFIX + str(category), category == "player"))


func _load_claude_icon(icon_name: String, size: int = 40) -> Texture:
	var cache_key: = "%s@%d" % [icon_name, size]
	if _claude_icon_texture_cache.has(cache_key):
		return _claude_icon_texture_cache[cache_key]
	var texture: Texture = null
	var path: = CLAUDE_EXPERIMENTAL_ICON_DIR + icon_name + ".png"
	if File.new().file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			_strip_icon_background(image)
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
			var image_texture := ImageTexture.new()
			image_texture.create_from_image(image, Texture.FLAGS_DEFAULT)
			texture = image_texture
	_claude_icon_texture_cache[cache_key] = texture
	return texture


func _on_settings_tas_gui_toggled(value: bool) -> void:
	_tas_gui_enabled = value
	SavedSettings.set_value(SETTING_TAS_GUI, value)
	_apply_tas_gui_visibility()


func _on_settings_sandbox_gui_toggled(value: bool) -> void:
	_sandbox_gui_enabled = value
	SavedSettings.set_value(SETTING_SANDBOX_GUI, value)
	if _cosmetic_sandbox != null and is_instance_valid(_cosmetic_sandbox) and _cosmetic_sandbox.has_method("set_gui_enabled"):
		_cosmetic_sandbox.call("set_gui_enabled", value)


func _on_settings_game_tools_gui_toggled(value: bool) -> void:
	_game_tools_gui_enabled = value
	SavedSettings.set_value(SETTING_GAME_TOOLS_GUI, value)
	if _game_tools != null and is_instance_valid(_game_tools) and _game_tools.has_method("set_gui_enabled"):
		_game_tools.call("set_gui_enabled", value)


func _on_settings_social_hub_gui_toggled(value: bool) -> void:
	_social_hub_gui_enabled = value
	SavedSettings.set_value(SETTING_SOCIAL_HUB_GUI, value)
	if _social_hub != null and is_instance_valid(_social_hub) and _social_hub.has_method("set_gui_enabled"):
		_social_hub.call("set_gui_enabled", value)


func _on_settings_cosmetic_loadouts_toggled(value: bool) -> void:
	_cosmetic_loadouts_gui_enabled = value
	SavedSettings.set_value(SETTING_COSMETIC_LOADOUTS_GUI, value)
	if _cosmetic_loadouts != null and is_instance_valid(_cosmetic_loadouts) and _cosmetic_loadouts.has_method("set_gui_enabled"):
		_cosmetic_loadouts.call("set_gui_enabled", value)


func _on_settings_editor_theme_pack_toggled(value: bool) -> void:
	_editor_theme_pack_enabled = value
	SavedSettings.set_value(SETTING_EDITOR_THEME_PACK, value)
	if _editor_theme_pack != null and is_instance_valid(_editor_theme_pack) and _editor_theme_pack.has_method("set_gui_enabled"):
		_editor_theme_pack.call("set_gui_enabled", value)


func _on_settings_match_map_preview_toggled(value: bool) -> void:
	_match_map_preview_enabled = value
	SavedSettings.set_value(SETTING_MATCH_MAP_PREVIEW, value)
	if _match_map_preview != null and is_instance_valid(_match_map_preview) and _match_map_preview.has_method("set_gui_enabled"):
		_match_map_preview.call("set_gui_enabled", value)


func _on_settings_wins_leaderboard_toggled(value: bool) -> void:
	_wins_leaderboard_enabled = value
	SavedSettings.set_value(SETTING_WINS_LEADERBOARD, value)
	if _wins_leaderboard != null and is_instance_valid(_wins_leaderboard) and _wins_leaderboard.has_method("set_gui_enabled"):
		_wins_leaderboard.call("set_gui_enabled", value)


func _on_settings_replay_hub_gui_toggled(value: bool) -> void:
	_replay_hub_gui_enabled = value
	SavedSettings.set_value(SETTING_REPLAY_HUB_GUI, value)
	if _replay_hub != null and is_instance_valid(_replay_hub) and _replay_hub.has_method("set_gui_enabled"):
		_replay_hub.call("set_gui_enabled", value)


# If the Leaderboard tab has already been opened this session, the search
# row was already built (or deliberately skipped) by _inject_leaderboard_search
# the first time -- toggling here just shows/hides what's already there.
# Turning it ON for the first time after the tab was already opened while it
# was OFF won't retroactively build it (nothing to show/hide yet); like the
# Claude Experimental Mode reskin, that case needs a restart of the
# Leaderboard tab/game to pick up, which is consistent with how the rest of
# this mod already handles "read once at build time" settings.
func _on_settings_leaderboard_search_toggled(value: bool) -> void:
	_leaderboard_search_enabled = value
	SavedSettings.set_value(SETTING_LEADERBOARD_SEARCH, value)
	if _leaderboard_search_row != null and is_instance_valid(_leaderboard_search_row):
		_leaderboard_search_row.visible = value
	if _leaderboard_search_status_label != null and is_instance_valid(_leaderboard_search_status_label):
		_leaderboard_search_status_label.visible = value


# Same "already built, just hidden/shown" behavior as the leaderboard search
# toggle above -- see its comment for why turning this ON after the Custom
# Lobby screen was already visited this session (while OFF) needs a restart.
func _on_settings_custom_lobby_code_toggled(value: bool) -> void:
	_custom_lobby_code_enabled = value
	SavedSettings.set_value(SETTING_CUSTOM_LOBBY_CODE, value)
	if _custom_lobby_code_row != null and is_instance_valid(_custom_lobby_code_row):
		_custom_lobby_code_row.visible = value
	if _custom_lobby_code_status_label != null and is_instance_valid(_custom_lobby_code_status_label):
		_custom_lobby_code_status_label.visible = value


func _on_settings_debug_mode_toggled(value: bool) -> void:
	_set_debug_mode_enabled(value)


func _on_settings_claude_experimental_icons_toggled(value: bool) -> void:
	_claude_experimental_icons_enabled = value
	SavedSettings.set_value(SETTING_CLAUDE_EXPERIMENTAL_ICONS, value)
	_apply_claude_experimental_icons()
	_log_action("Claude Experimental Mode (icon menus) %s" % ("ON" if value else "OFF"), null)


func _on_settings_update_checks_toggled(value: bool) -> void:
	_update_checks_enabled = value
	SavedSettings.set_value(SETTING_UPDATE_CHECKS, value)
	if _updater != null and is_instance_valid(_updater):
		_updater.call("set_automatic_checks", value)
		if value:
			_updater.call("check_now", false)


# ----------------------------------------------------------------------
#  Debug Mode -- persisted master switch for the 2026-08-30 tool revamp.
#  See the big comment on `_debug_mode_enabled` above for what turning this
#  on actually does; this section is just the load/save/toggle plumbing.
# ----------------------------------------------------------------------
func _load_debug_mode_from_disk() -> void:
	var f: = File.new()
	if f.file_exists(DEBUG_MODE_SETTINGS_PATH) and f.open(DEBUG_MODE_SETTINGS_PATH, File.READ) == OK:
		var loaded = f.get_var()
		f.close()
		if typeof(loaded) == TYPE_BOOL:
			_debug_mode_enabled = loaded
	if _debug_mode_enabled:
		_diag_enabled = true # keep the two in lockstep on load, same as the toggle handler below does live


func _save_debug_mode_to_disk() -> void:
	var f: = File.new()
	if f.open(DEBUG_MODE_SETTINGS_PATH, File.WRITE) == OK:
		f.store_var(_debug_mode_enabled)
		f.close()


func _set_debug_mode_enabled(value: bool) -> void:
	_debug_mode_enabled = value
	# Debug Mode owns diagnostics completely: disabling it stops background
	# capture as well as hiding the advanced controls.
	_diag_enabled = value
	if not value:
		_log_open = false
		_restore_drift_enabled = false
		_restore_drift_watches.clear()
		if _noclip_enabled and _noclip_toggle_button != null:
			_on_toggle_noclip_pressed()
	_save_debug_mode_to_disk()
	if _debug_tools_container != null:
		_debug_tools_container.visible = value
	if _diag_label != null:
		_diag_label.visible = value
	_log_action("Goobplayability Debug Mode %s" % ("ON" if value else "OFF"), null)
	_apply_log_open_state()
	_refresh_practice_ui()


func _set_stop_on_desync_enabled(value: bool) -> void:
	_replay_check_stop_on_desync = value
	SavedSettings.set_value(SETTING_STOP_ON_DESYNC, value)
	_refresh_practice_ui()


func _check_first_launch() -> String:
	var onboarding = ModPaths.try_load(ModPaths.path("Onboarding.gd"))
	if onboarding == null:
		return ""
	var result: String = onboarding.check_first_launch()
	# Installer installs start with every tool switched off, on the very first launch only.
	if result == "new" and File.new().file_exists(ModPaths.ROOT + "installed.json"):
		for setting in [SETTING_SANDBOX_GUI, SETTING_REPLAY_HUB_GUI, SETTING_GAME_TOOLS_GUI, SETTING_SOCIAL_HUB_GUI, SETTING_COSMETIC_LOADOUTS_GUI,
				SETTING_EDITOR_THEME_PACK, SETTING_MATCH_MAP_PREVIEW, SETTING_WINS_LEADERBOARD, SETTING_LEADERBOARD_SEARCH, SETTING_CUSTOM_LOBBY_CODE]:
			SavedSettings.set_value(setting, false)
	return result


func _start_onboarding(hide_overlay: bool) -> void:
	var onboarding = ModPaths.try_load(ModPaths.path("Onboarding.gd"))
	if onboarding == null or onboarding.seen("tour") or has_node("GoobOnboarding"):
		return
	var tour: Node = onboarding.new()
	tour.name = "GoobOnboarding"
	add_child(tour)
	tour.call("start", self, hide_overlay)


func _replay_onboarding() -> void:
	var onboarding = ModPaths.try_load(ModPaths.path("Onboarding.gd"))
	if onboarding == null:
		return
	onboarding.replay()
	_start_onboarding(false)
