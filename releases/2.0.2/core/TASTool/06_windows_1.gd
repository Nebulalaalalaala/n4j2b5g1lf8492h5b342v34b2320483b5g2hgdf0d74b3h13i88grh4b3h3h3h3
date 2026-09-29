extends "user://mod/core/TASTool/05_game_lookup.gd"

func _open_module_page(key: String) -> bool:
	if _workspace_menu == null or _workspace_menu.shell == null or _workspace_menu.shell.opening:
		return false
	if not _workspace_menu.enabled(key):
		return true
	_workspace_menu.select(key)
	return true


# ----------------------------------------------------------------------
#  Phase 1.3 -- persistent GUI layout. Main/log windows are Containers, so
#  their meaningful dimensions are the child minimums that actually drive
#  layout; free-floating Timeline/Sandbox panels use exact pixel rectangles.
# ----------------------------------------------------------------------
func _load_gui_layout_store() -> void:
	_gui_layout_config = ConfigFile.new()
	_gui_layout_config.load(GUI_LAYOUT_PATH)


func save_gui_panel_layout(key: String, target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	_gui_layout_config.set_value("panels", key + "_position", target.rect_position)
	_gui_layout_config.set_value("panels", key + "_size", target.rect_size)
	_gui_layout_config.save(GUI_LAYOUT_PATH)


func restore_gui_panel_layout(key: String, target: Control, minimum_size: Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not _gui_layout_config.has_section_key("panels", key + "_position") or not _gui_layout_config.has_section_key("panels", key + "_size"):
		return false
	var viewport_size: Vector2 = get_gui_viewport_size()
	var saved_size: Vector2 = _gui_layout_config.get_value("panels", key + "_size", target.rect_size)
	var size := Vector2(clamp(saved_size.x, minimum_size.x, max(minimum_size.x, viewport_size.x - 12.0)), clamp(saved_size.y, minimum_size.y, max(minimum_size.y, viewport_size.y - 12.0)))
	var saved_position: Vector2 = _gui_layout_config.get_value("panels", key + "_position", target.rect_position)
	var position := saved_position
	if _window_geometry != null:
		position = _window_geometry.moved_position(saved_position, size, Vector2.ZERO, viewport_size, 110.0, 60.0)
	else:
		position.x = clamp(position.x, -size.x + 110.0, viewport_size.x - 110.0)
		position.y = clamp(position.y, 0.0, viewport_size.y - 60.0)
	target.rect_position = position
	target.rect_size = size
	return true


func _initialize_main_gui_layout() -> void:
	if _menu_window == null or _log_window == null:
		return
	var menu_height := 240.0
	if not _tool_tab_scrolls.empty() and _tool_tab_scrolls[0] != null:
		menu_height = _tool_tab_scrolls[0].rect_min_size.y
	_gui_layout_defaults["menu"] = {"position": _menu_window.rect_position, "width": _menu_panel.rect_min_size.x, "height": menu_height}
	_gui_layout_defaults["log"] = {"position": _log_window.rect_position, "width": _log_panel.rect_min_size.x, "height": _log_scroll.rect_min_size.y if _log_scroll != null else 140.0}
	ui_scale = float(_gui_layout_config.get_value("main_windows", "scale", ui_scale))
	_apply_ui_scale()
	_restore_main_window_layout("menu")
	_restore_main_window_layout("log")


func _save_main_window_layout(which: String) -> void:
	var window: Control = _menu_window if which == "menu" else _log_window
	if window == null:
		return
	_gui_layout_config.set_value("main_windows", which + "_position", window.rect_position)
	_gui_layout_config.set_value("main_windows", "scale", ui_scale)
	if which == "menu":
		_gui_layout_config.set_value("main_windows", which + "_width", _menu_panel.rect_min_size.x)
		var height := 240.0
		if not _tool_tab_scrolls.empty() and _tool_tab_scrolls[0] != null:
			height = _tool_tab_scrolls[0].rect_min_size.y
		_gui_layout_config.set_value("main_windows", which + "_height", height)
	else:
		_gui_layout_config.set_value("main_windows", which + "_width", _log_panel.rect_min_size.x)
		_gui_layout_config.set_value("main_windows", which + "_height", _log_scroll.rect_min_size.y if _log_scroll != null else 140.0)
	_gui_layout_config.save(GUI_LAYOUT_PATH)


func _restore_main_window_layout(which: String) -> void:
	if not _gui_layout_defaults.has(which):
		return
	var defaults: Dictionary = _gui_layout_defaults[which]
	var window: Control = _menu_window if which == "menu" else _log_window
	var minimum_width := 520.0 if which == "menu" else 420.0
	var minimum_height := 240.0 if which == "menu" else 140.0
	var position: Vector2 = _gui_layout_config.get_value("main_windows", which + "_position", defaults["position"])
	var width := float(_gui_layout_config.get_value("main_windows", which + "_width", defaults["width"]))
	var height := float(_gui_layout_config.get_value("main_windows", which + "_height", defaults["height"]))
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	width = max(width, minimum_width)
	height = max(height, minimum_height)
	var scaled_size := Vector2(width, height + 100.0) * get_gui_scale_factor()
	if _window_geometry != null:
		position = _window_geometry.moved_position(position, scaled_size, Vector2.ZERO, viewport_size, 120.0, 48.0)
	window.rect_position = position
	if which == "menu":
		_menu_panel.rect_min_size.x = width
		for scroll in _tool_tab_scrolls:
			if scroll != null:
				scroll.rect_min_size.y = height
	else:
		_log_panel.rect_min_size.x = width
		if _log_scroll != null:
			_log_scroll.rect_min_size.y = height


func _on_reset_gui_layout_pressed() -> void:
	ui_scale = 1.0
	_apply_ui_scale()
	_gui_layout_config.erase_section("main_windows")
	_gui_layout_config.erase_section("panels")
	_gui_layout_config.save(GUI_LAYOUT_PATH)
	_restore_main_window_layout("menu")
	_restore_main_window_layout("log")
	if _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("reset_saved_layout"):
		_macro_editor.call("reset_saved_layout")
	if _cosmetic_sandbox != null and is_instance_valid(_cosmetic_sandbox) and _cosmetic_sandbox.has_method("reset_saved_layout"):
		_cosmetic_sandbox.call("reset_saved_layout")
	_show_responsive_popup("LAYOUT RESET", "Goobplayability windows were returned to their default positions and sizes for this resolution.")


func _show_native_notify(title: String, message: String) -> void:
	_show_responsive_popup(title, message)


func _set_menu_open(open: bool) -> void:
	_menu_open = open
	if open:
		_ui_next_diag_refresh_msec = 0 # refresh immediately after reopening, then return to the throttled cadence below
	_apply_menu_open_state()


func _apply_menu_open_state() -> void:
	if _menu_panel != null:
		_menu_panel.visible = _menu_open
	if _tab_button != null:
		_tab_button.text = _tab_text()
	_update_mouse_capture()


func get_gui_viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size / get_gui_scale_factor()


func get_gui_scale_factor() -> float:
	# The game's 960x540 canvas is stretched again by the viewport. UI percent
	# describes screen pixels, not a second multiplication by game stretch.
	var stretch: Vector2 = get_viewport().get_final_transform().get_scale()
	return max(UI_SCALE_MIN, ui_scale) / max(0.01, abs(stretch.x))


# Creates one page of the section-tab menu: a fixed-height ScrollContainer
# (so a tall section scrolls internally instead of growing the window past
# the screen or pushing the tab strip out of view) wrapping a VBoxContainer
# that the section's own controls get added to. The ScrollContainer's
# `name` becomes that tab's visible title in the TabContainer.
func _add_tab_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll: = ScrollContainer.new()
	scroll.name = title
	scroll.rect_min_size = Vector2(0, MENU_TAB_CONTENT_H)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_tab_scrolls.append(scroll)
	var page: = VBoxContainer.new()
	page.add_constant_override("separation", 10)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	tabs.add_child(scroll)
	return page


func _tab_text() -> String:
	var arrow: = "▴" if _menu_open else "▾"
	if not enabled:
		return "GOOBPLAYABILITY — DISABLED"
	var speed: float = _saved_time_scale if _is_paused else Engine.time_scale
	var bits: = "Workspace %s   %.2fx" % [arrow, speed]
	if _is_paused:
		bits += "  STOPPED"
	if _is_recording():
		bits += "  ● REC"
	return bits
