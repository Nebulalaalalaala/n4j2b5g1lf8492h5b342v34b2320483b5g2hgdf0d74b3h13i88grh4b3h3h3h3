extends "user://mod/tools/tas/TASTool/28_pages.gd"

func _set_hitbox_viewer_enabled(value: bool) -> void:
	_hitbox_viewer_enabled = value
	SavedSettings.set_value(SETTING_HITBOX_VIEWER, value)
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.call("set_show_hitboxes", value)
	_refresh_practice_ui()


func _set_hitbox_category(category: String, value: bool) -> void:
	if not _hitbox_categories.has(category):
		return
	_hitbox_categories[category] = value
	SavedSettings.set_value(SETTING_HITBOX_CATEGORY_PREFIX + category, value)
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.call("set_hitbox_category", category, value)
	_refresh_hitbox_category_ui()


func _on_hitbox_category_toggled(value: bool, category: String) -> void:
	_set_hitbox_category(category, value)


func _refresh_hitbox_category_ui() -> void:
	if _hitbox_category_row != null:
		_hitbox_category_row.visible = _hitbox_viewer_enabled
	for category in _hitbox_category_buttons.keys():
		var button: Button = _hitbox_category_buttons[category]
		if button != null:
			button.set_pressed_no_signal(bool(_hitbox_categories.get(category, false)))
			_style_button(button, COLOR_PINK if button.pressed else COLOR_BLUE, 12, 3)


func _on_toggle_hitbox_viewer_pressed() -> void:
	_set_hitbox_viewer_enabled(not _hitbox_viewer_enabled)
	_log_action("Hitbox Viewer %s" % ("ON" if _hitbox_viewer_enabled else "OFF"), null)


func _set_trajectory_preview_enabled(value: bool) -> void:
	_trajectory_preview_enabled = value
	SavedSettings.set_value(SETTING_TRAJECTORY_PREVIEW, value)
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.call("set_show_trajectory", value)
	_refresh_practice_ui()


func _on_toggle_trajectory_preview_pressed() -> void:
	_set_trajectory_preview_enabled(not _trajectory_preview_enabled)
	_log_action("Trajectory Preview %s" % ("ON" if _trajectory_preview_enabled else "OFF"), null)


func _set_input_display_enabled(value: bool) -> void:
	_input_display_enabled = value
	SavedSettings.set_value(SETTING_INPUT_DISPLAY, value)
	if _input_display != null and is_instance_valid(_input_display):
		_input_display.call("set_display_enabled", value)
	_refresh_practice_ui()


func _on_toggle_input_display_pressed() -> void:
	_set_input_display_enabled(not _input_display_enabled)
	_log_action("Input Display %s" % ("ON" if _input_display_enabled else "OFF"), null)


func _set_input_display_detailed(value: bool) -> void:
	_input_display_detailed = value
	SavedSettings.set_value(SETTING_INPUT_DISPLAY_DETAILED, value)
	if _input_display != null and is_instance_valid(_input_display):
		_input_display.call("set_detailed", value)
	_refresh_practice_ui()


func _on_toggle_input_display_detailed_pressed() -> void:
	_set_input_display_detailed(not _input_display_detailed)


func _set_input_display_hold_frames(value: bool) -> void:
	_input_display_hold_frames = value
	SavedSettings.set_value(SETTING_INPUT_DISPLAY_HOLD_FRAMES, value)
	if _input_display != null and is_instance_valid(_input_display):
		_input_display.call("set_show_hold_frames", value)
	_refresh_practice_ui()


func _on_toggle_input_display_hold_frames_pressed() -> void:
	_set_input_display_hold_frames(not _input_display_hold_frames)
