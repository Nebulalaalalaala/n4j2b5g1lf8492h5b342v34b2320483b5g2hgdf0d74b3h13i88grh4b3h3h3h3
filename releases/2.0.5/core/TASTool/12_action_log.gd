extends "user://mod/core/TASTool/11_render_fixes.gd"

# `undo_data` is null for actions that genuinely cannot be reversed, or a
# Dictionary with a "type" key understood by _apply_undo().
func _log_action(text: String, undo_data) -> void:
	_set_status(text)
	var entry: = {"text": text, "time": _format_time(), "undo": undo_data}
	_log_entries.append(entry)
	_add_log_row(entry)
	while _log_entries.size() > MAX_LOG_ENTRIES:
		var oldest: Dictionary = _log_entries.pop_front()
		if oldest.has("row") and is_instance_valid(oldest["row"]):
			oldest["row"].queue_free()


func _snapshot_engine_state() -> Dictionary:
	return {
		"is_paused": _is_paused,
		"time_scale": Engine.time_scale,
		"saved_time_scale": _saved_time_scale,
	}


func _on_undo_pressed(entry: Dictionary) -> void:
	var undo = entry.get("undo", null)
	if undo == null:
		return
	_apply_undo(undo)
	_set_status("Undid: %s" % entry["text"])
	_remove_log_entry(entry)


func _on_log_delete_pressed(entry: Dictionary) -> void:
	_remove_log_entry(entry)


func _remove_log_entry(entry: Dictionary) -> void:
	_log_entries.erase(entry)
	if entry.has("row") and is_instance_valid(entry["row"]):
		entry["row"].queue_free()


func _on_clear_log_pressed() -> void:
	for entry in _log_entries:
		if entry.has("row") and is_instance_valid(entry["row"]):
			entry["row"].queue_free()
	_log_entries.clear()


# Truncates a flat diag log to its first `limit` ticks without relying on
# Array.slice() -- not available on every 3.x build's GDScript Array, so
# this just builds the sub-array by hand. Used to keep the key-event report
# honest about the same "diagnostic coverage" boundary
# _diag_coverage_prefix_ticks() already enforces for Divergence Diagnostics,
# rather than silently comparing events built from ticks that may not
# actually correspond to the same moment on both sides.
func _cap_flat_log(flat: Array, limit: int) -> Array:
	if limit >= flat.size():
		return flat
	var capped: = []
	for i in range(limit):
		capped.append(flat[i])
	return capped


func _set_log_open(open: bool) -> void:
	_log_open = open and _debug_mode_enabled
	_apply_log_open_state()


func _apply_log_open_state() -> void:
	if _log_panel != null:
		_log_panel.visible = _log_open and _debug_mode_enabled
	if _log_tab_row != null:
		_log_tab_row.visible = _debug_mode_enabled and enabled and _tas_gui_enabled and not _overlay_hidden
	if _log_tab_button != null:
		_log_tab_button.text = _log_tab_text()
	_update_mouse_capture()


func _on_log_tab_pressed() -> void:
	_set_log_open(not _log_open)


func _log_tab_text() -> String:
	var arrow: = "▴" if _log_open else "▾"
	return "LOG %s   (%d)" % [arrow, _log_entries.size()]


func _build_log_window() -> void:
	_log_window = VBoxContainer.new()
	_log_window.add_constant_override("separation", 10)
	_log_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_log_window)

	_log_tab_row = HBoxContainer.new()
	_log_tab_row.add_constant_override("separation", 6)
	_log_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_tab_row.add_child(_make_drag_handle("log"))

	_log_tab_button = Button.new()
	_log_tab_button.text = _log_tab_text()
	_style_button(_log_tab_button, COLOR_PANEL_BG, 999, 4)
	if _header_font != null:
		_log_tab_button.add_font_override("font", _header_font)
	_log_tab_button.rect_min_size = TAB_SIZE
	_log_tab_button.align = Button.ALIGN_CENTER
	_log_tab_button.focus_mode = Control.FOCUS_NONE # see _make_button -- keeps Space free for the game
	_log_tab_button.connect("pressed", self, "_on_log_tab_pressed")
	_log_tab_row.add_child(_log_tab_button)
	_log_window.add_child(_log_tab_row)

	_log_panel = PanelContainer.new()
	_log_panel.add_stylebox_override("panel", _make_flat_style(Color(COLOR_PANEL_BG.r, COLOR_PANEL_BG.g, COLOR_PANEL_BG.b, menu_background_opacity), COLOR_PANEL_BORDER, 3, 26))
	_log_panel.rect_min_size = Vector2(LOG_PANEL_MIN_W, 0)
	_log_window.add_child(_log_panel)

	var vb: = VBoxContainer.new()
	vb.add_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.add_child(vb)

	var header_row: = HBoxContainer.new()
	header_row.add_constant_override("separation", 10)
	# Claude Experimental Mode icon slot -- see the matching comment in
	# _build_menu_window().
	_claude_log_title_icon = TextureRect.new()
	_claude_log_title_icon.expand = true
	_claude_log_title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_claude_log_title_icon.rect_min_size = Vector2(36, 36)
	_claude_log_title_icon.visible = false
	header_row.add_child(_claude_log_title_icon)
	var log_heading := _make_label("ACTION LOG", _title_font, COLOR_BLUE)
	log_heading.hint_tooltip = "Tool actions appear here. Entries can be undone or cleared."
	header_row.add_child(log_heading)
	var spacer: = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var clear_btn: = _make_small_button("Clear Log", COLOR_BLUE, 130)
	clear_btn.connect("pressed", self, "_on_clear_log_pressed")
	header_row.add_child(clear_btn)
	vb.add_child(header_row)

	_log_scroll = ScrollContainer.new()
	_log_scroll.rect_min_size = Vector2(0, 320)
	_log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_log_scroll)

	_log_list_vbox = VBoxContainer.new()
	_log_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list_vbox.add_constant_override("separation", 4)
	_log_scroll.add_child(_log_list_vbox)
	# Optional modules are configured before the overlay is built and may log a
	# useful startup status. Preserve those entries, then render them once the
	# Action Log container actually exists.
	for existing_entry in _log_entries:
		_add_log_row(existing_entry)
	var resize_row := HBoxContainer.new()
	var resize_spacer := Control.new()
	resize_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resize_row.add_child(resize_spacer)
	resize_row.add_child(_make_resize_handle("log"))
	vb.add_child(resize_row)


func _add_log_row(entry: Dictionary) -> void:
	if _log_list_vbox == null or not is_instance_valid(_log_list_vbox):
		return
	var row: = PanelContainer.new()
	row.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, Color(1, 1, 1, 0.25), 2, 10))

	var hb: = HBoxContainer.new()
	hb.add_constant_override("separation", 10)
	row.add_child(hb)

	var time_label: = _make_label(entry["time"], _small_font, COLOR_TEXT_DIM)
	time_label.rect_min_size = Vector2(80, 0)
	hb.add_child(time_label)

	var text_label: = _make_label(entry["text"], _small_font, COLOR_WHITE)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.autowrap = true
	hb.add_child(text_label)

	var undo_btn: = _make_small_button("Undo", COLOR_BLUE, 90)
	undo_btn.disabled = (entry["undo"] == null)
	undo_btn.connect("pressed", self, "_on_undo_pressed", [entry])
	hb.add_child(undo_btn)

	var del_btn: = _make_small_button("✕", COLOR_PINK_DARK, 46)
	del_btn.connect("pressed", self, "_on_log_delete_pressed", [entry])
	hb.add_child(del_btn)

	entry["row"] = row
	_log_list_vbox.add_child(row)


func _set_status(msg: String) -> void:
	_status_message = msg
	_status_message_timer = 2.5
	print("[TASTool] %s" % msg)
