extends "user://mod/core/TASTool/13_changelog.gd"

func _input(event: InputEvent) -> void:
	# Recovery stays reachable even if a very large menu pushes its buttons off-screen.
	if _menu_open and event is InputEventKey and event.pressed and not event.echo and event.control and event.scancode == KEY_0:
		_on_main_ui_scale_reset()
		get_tree().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer) and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		_close_tool_popup()
		get_tree().set_input_as_handled()


# ----------------------------------------------------------------------
#  Input edge-detection helper (so holding a key only fires once)
# ----------------------------------------------------------------------
func _just_pressed(keycode: int) -> bool:
	var pressed: = Input.is_key_pressed(keycode)
	var was_pressed: bool = _prev_key_state.get(keycode, false)
	_prev_key_state[keycode] = pressed
	return pressed and not was_pressed


func _on_tab_pressed() -> void:
	_set_menu_open(not _menu_open)


func _on_drag_gui_input(event: InputEvent, which: String) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_dragging[which] = event.pressed
		if not event.pressed:
			_save_main_window_layout(which)
	elif event is InputEventMouseMotion and _dragging.get(which, false):
		var window: Control = _menu_window if which == "menu" else _log_window
		# The drag grip is a descendant of `window`, which carries
		# rect_scale from the UI Scale control -- Godot reports
		# event.relative already divided by that scale (it's in the
		# grip's own scaled-down local space), so it has to be multiplied
		# back out here or dragging would move slower/faster than the
		# mouse at anything other than 100%.
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var scaled_size: Vector2 = window.rect_size * get_gui_scale_factor()
		var screen_delta: Vector2 = event.relative * get_gui_scale_factor()
		if _window_geometry != null:
			window.rect_position = _window_geometry.moved_position(window.rect_position, scaled_size, screen_delta, viewport_size, 120.0, 48.0)
		else:
			var next: Vector2 = window.rect_position + screen_delta
			next.x = clamp(next.x, -scaled_size.x + 120.0, viewport_size.x - 120.0)
			next.y = clamp(next.y, 0.0, viewport_size.y - 48.0)
			window.rect_position = next


func _on_resize_gui_input(event: InputEvent, which: String) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_resizing[which] = event.pressed
		if not event.pressed:
			_save_main_window_layout(which)
	elif event is InputEventMouseMotion and _resizing.get(which, false):
		if which == "menu":
			_menu_panel.rect_min_size.x = max(520.0, _menu_panel.rect_min_size.x + event.relative.x)
			for scroll in _tool_tab_scrolls:
				if scroll != null:
					scroll.rect_min_size.y = max(240.0, scroll.rect_min_size.y + event.relative.y)
					scroll.set_meta("workspace_base_height", scroll.rect_min_size.y)
		else:
			_log_panel.rect_min_size.x = max(420.0, _log_panel.rect_min_size.x + event.relative.x)
			if _log_scroll != null:
				_log_scroll.rect_min_size.y = max(140.0, _log_scroll.rect_min_size.y + event.relative.y)


func _on_ui_scale_delta_pressed(delta: float) -> void:
	ui_scale = max(UI_SCALE_MIN, ui_scale * (1.0 + delta))
	_apply_ui_scale()
	_save_main_window_layout("menu")


# Claude Experimental Mode's flat nav row (see _build_menu_window()) --
# switches _section_tabs exactly like clicking a native tab would, and keeps
# the nav buttons' pressed/toggled state in sync with whichever tab is
# actually showing.
func _on_claude_menu_nav_pressed(index: int) -> void:
	_section_tabs.current_tab = index
	for i in range(_claude_menu_nav_buttons.size()):
		var btn: Button = _claude_menu_nav_buttons[i]
		var is_active: = (i == index)
		btn.pressed = is_active
		_style_button(btn, COLOR_PINK if is_active else COLOR_BLUE, 12, 3)



# ----------------------------------------------------------------------
#  Window open/close + dragging (also handles forcing the mouse cursor
#  visible so you can actually click things)
# ----------------------------------------------------------------------
func _toggle_overlay_hidden() -> void:
	_overlay_hidden = not _overlay_hidden
	if _overlay_layer != null:
		_overlay_layer.visible = _tas_gui_enabled and not _overlay_hidden
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.visible = not _overlay_hidden
	# Checkpoint markers live in world space under WPGame rather than under the
	# overlay CanvasLayer, so F1 must explicitly mirror their visibility too.
	_set_practice_markers_visible(not _overlay_hidden)
	_update_mouse_capture()


func _build_overlay() -> void:
	_title_font = _make_font(SIZE_TITLE)
	_header_font = _make_font(SIZE_HEADER)
	_body_font = _make_font(SIZE_BODY)
	_small_font = _make_font(SIZE_SMALL)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	add_child(_overlay_layer)

	_build_menu_window()
	_build_log_window()

	_menu_window.rect_position = Vector2(24, 24)
	_log_window.rect_position = Vector2(24, 24 + TAB_SIZE.y + 16)
