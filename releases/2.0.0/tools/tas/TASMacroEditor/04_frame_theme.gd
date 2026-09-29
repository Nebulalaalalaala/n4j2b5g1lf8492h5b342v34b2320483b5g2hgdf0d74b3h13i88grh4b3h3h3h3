extends "user://mod/tools/tas/TASMacroEditor/03_preview_timeline.gd"

func _on_action_toggled(value: bool, action: String) -> void:
	if _updating_controls or _flat_frames.empty():
		return
	_frame_at_selected()[action] = value
	_mark_dirty("Changed %s at frame %d" % [ACTION_LABELS[action], _selected_frame])
	_rebuild_timeline()


func _on_dash_direction_changed(index: int) -> void:
	if _updating_controls or _flat_frames.empty():
		return
	_frame_at_selected()[DASH_DIRECTION_KEY] = index == 1
	_mark_dirty("Changed dash direction at frame %d" % _selected_frame)
	_rebuild_timeline()


func _apply_state_values() -> void:
	if _flat_frames.empty():
		return
	var frame := _frame_at_selected()
	var state = frame.get(STATE_KEY, {})
	if typeof(state) != TYPE_DICTIONARY:
		_status.text = "This legacy frame has no state block to edit."
		return
	state["position"] = Vector2(_position_x.value, _position_y.value)
	state["linear_velocity"] = Vector2(_velocity_x.value, _velocity_y.value)
	frame[STATE_KEY] = state
	_mark_dirty("Advanced state updated — test this macro before relying on it")
	_rebuild_timeline()


func _duplicate_frame() -> void:
	_insert_frame_copy(false)


func _insert_neutral_frame() -> void:
	_insert_frame_copy(true)


func _insert_frame_copy(neutral: bool) -> void:
	if _flat_frames.empty():
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment: Array = working_data["segments"][int(location.x)]
	var copied: Dictionary = segment[int(location.y)].duplicate(true)
	if neutral:
		for action in ACTIONS:
			copied[action] = false
		copied.erase(DASH_DIRECTION_KEY)
	segment.insert(int(location.y) + 1, copied)
	working_data["segments"][int(location.x)] = segment
	_selected_frame += 1
	_mark_dirty("Inserted %s frame" % ("neutral" if neutral else "duplicate"))
	_rebuild_timeline()


func _delete_frame() -> void:
	if _flat_frames.empty():
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment: Array = working_data["segments"][int(location.x)]
	if segment.size() <= 1:
		_status.text = "A segment must keep at least one frame so checkpoint boundaries stay valid."
		return
	segment.remove(int(location.y))
	working_data["segments"][int(location.x)] = segment
	_selected_frame = min(_selected_frame, _flat_frames.size() - 2)
	_mark_dirty("Deleted one frame — timing after it shifted earlier")
	_rebuild_timeline()


func _move_frame(direction: int) -> void:
	if _flat_frames.empty():
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment: Array = working_data["segments"][int(location.x)]
	var local_index := int(location.y)
	var destination := local_index + direction
	if destination < 0 or destination >= segment.size():
		_status.text = "Frames cannot move across checkpoint boundaries."
		return
	var temp = segment[local_index]
	segment[local_index] = segment[destination]
	segment[destination] = temp
	working_data["segments"][int(location.x)] = segment
	_selected_frame += direction
	_mark_dirty("Moved frame within its segment")
	_rebuild_timeline()


func _frame_at_selected() -> Dictionary:
	var location: Vector2 = _locations[_selected_frame]
	return working_data["segments"][int(location.x)][int(location.y)]


func _place_timeline_checkpoint() -> void:
	_set_preview_direction(0)
	if _flat_frames.empty() or _boundaries.has(_selected_frame):
		_status.text = "This frame already starts a checkpoint."
		return
	var state = _frame_at_selected().get(STATE_KEY, {})
	if typeof(state) != TYPE_DICTIONARY or not state.has("position") or not state.has("linear_velocity"):
		_status.text = "This legacy frame has no state for a checkpoint."
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment_index := int(location.x)
	var local_index := int(location.y)
	var checkpoints: Array = working_data.get("checkpoints", [])
	if segment_index >= checkpoints.size():
		_status.text = "Missing source checkpoint; working copy unchanged."
		return
	var snapshot: Dictionary = checkpoints[segment_index].duplicate(true)
	# A previous checkpoint's full world snapshot must not override this frame.
	snapshot.erase("moving_world_state")
	snapshot.erase("moving_world_time")
	for key in ["ground_tangent_speed", "ground_normal", "practice_playback_air_hold_ticks", "practice_playback_air_hold_dir"]:
		if not state.has(key):
			snapshot.erase(key)
	for key in state:
		snapshot[key] = state[key]
	snapshot["alive"] = bool(state.get("alive", true))
	snapshot["body_enabled"] = bool(state.get("body_enabled", true))
	var segment: Array = working_data["segments"][segment_index]
	working_data["segments"][segment_index] = segment.slice(0, local_index - 1)
	working_data["segments"].insert(segment_index + 1, segment.slice(local_index, segment.size() - 1))
	checkpoints.insert(segment_index + 1, snapshot)
	working_data["checkpoints"] = checkpoints
	_mark_dirty("Checkpoint placed at %.3fs" % _timeline_seconds())
	_rebuild_timeline()


func _on_name_changed(value: String) -> void:
	if _updating_controls:
		return
	working_data["name"] = value.strip_edges()
	_mark_dirty("Renamed macro")


func _mark_dirty(message: String) -> void:
	_dirty = true
	_status.text = "UNSAVED · " + message
	_status.add_color_override("font_color", _theme_accent(ORANGE))


func _save_changes() -> void:
	working_data["name"] = _name_edit.text.strip_edges()
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_save_macro_editor_data"):
		tas_tool.call("_save_macro_editor_data", slot, working_data.duplicate(true))
		_dirty = false
		_status.text = "Saved safely. Timeline and checkpoint boundaries rebuilt."
		_status.add_color_override("font_color", _theme_accent(GREEN))


func _play_working_copy() -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_play_macro_editor_data"):
		var play_slot := slot
		var play_data := working_data.duplicate(true)
		close_editor()
		tas_tool.call("_play_macro_editor_data", play_slot, play_data)

func _continue_from_selected() -> void:
	if _flat_frames.empty() or tas_tool == null:
		return
	var data = working_data.duplicate(true)
	var selected = _selected_frame
	close_editor()
	if not tas_tool.call("_continue_macro_editor_data",data,selected):
		_status.text = "Open this replay's local level first; Continue From requires a native-tick recording."
		_root.show()
		tas_tool.call("_begin_macro_editor_preview")


func _number_field(parent: GridContainer, title: String) -> SpinBox:
	parent.add_child(_label(title, _small_font, DIM))
	var field := SpinBox.new()
	field.min_value = -1000000
	field.max_value = 1000000
	field.step = 0.01
	field.rect_min_size = Vector2(175, 46)
	field.add_font_override("font", _body_font)
	parent.add_child(field)
	return field


func _panel_box(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_stylebox_override("panel", _style(NAVY_2, Color(0.2, 0.48, 0.72), 2, 16))
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 5)
	box.add_child(_label(title, _body_font, WHITE))
	panel.add_child(box)
	return panel


func _modern_theme_active() -> bool:
	return true


func _color_rgb_eq(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


func _theme_fill(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, NAVY):
		return Color(MODERN_BG.r, MODERN_BG.g, MODERN_BG.b, color.a)
	if _color_rgb_eq(color, NAVY_2):
		return Color(MODERN_BG_2.r, MODERN_BG_2.g, MODERN_BG_2.b, color.a)
	return color


func _theme_border(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, WHITE):
		return Color(MODERN_BORDER.r, MODERN_BORDER.g, MODERN_BORDER.b, color.a)
	return color


func _theme_text(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, WHITE):
		return Color(MODERN_WHITE.r, MODERN_WHITE.g, MODERN_WHITE.b, color.a)
	if _color_rgb_eq(color, DIM):
		return Color(MODERN_DIM.r, MODERN_DIM.g, MODERN_DIM.b, color.a)
	return _theme_accent(color)


# Button backgrounds are brand accent colors (blue/pink/green/orange/PANEL)
# that _theme_fill() deliberately leaves alone. Muted here on top of that so
# they read as flat modern tones instead of bright candy-colored pills.
func _theme_accent(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	# Same restrained palette as TASTool.gd/CosmeticSandbox.gd. In this file
	# PANEL (not BLUE) is the majority/utility button color (zoom, reset,
	# move, insert) -- that's the one that becomes a calm neutral slate.
	# BLUE here marks the handful of primary actions (Center, Play Macro,
	# Duplicate Frame), so it gets the one vivid accent color instead. PINK
	# is already this file's close/destructive color, unchanged (red).
	if _color_rgb_eq(color, PANEL):
		return Color(0.22, 0.23, 0.26, color.a)
	if _color_rgb_eq(color, BLUE):
		return Color(0.21, 0.38, 0.31, color.a)
	if _color_rgb_eq(color, PINK):
		return Color(0.43, 0.23, 0.23, color.a)
	if _color_rgb_eq(color, GREEN):
		return Color(0.22, 0.40, 0.32, color.a)
	if _color_rgb_eq(color, ORANGE):
		return Color(0.961, 0.62, 0.043, color.a)
	return color


func _get_claude_modern_font_data() -> DynamicFontData:
	if _claude_modern_font_load_attempted:
		return _claude_modern_font_data
	_claude_modern_font_load_attempted = true
	if File.new().file_exists(CLAUDE_EXPERIMENTAL_FONT_PATH):
		var data := DynamicFontData.new()
		data.font_path = CLAUDE_EXPERIMENTAL_FONT_PATH
		data.antialiased = true
		data.override_oversampling = 2.0
		_claude_modern_font_data = data
	return _claude_modern_font_data


func _font(size: int) -> DynamicFont:
	var font := DynamicFont.new()
	var data = null
	if _modern_theme_active():
		data = _get_claude_modern_font_data()
	if data == null:
		data = load(FONT_PATH)
		if data != null:
			data = data.duplicate()
			data.antialiased = true
			data.override_oversampling = 2.0
	font.font_data = data
	font.size = size
	if _modern_theme_active():
		font.outline_size = 0
		font.outline_color = Color(0, 0, 0, 0)
	else:
		font.outline_size = 1
		font.outline_color = Color(0, 0.025, 0.06, 0.95)
	font.use_filter = true
	font.use_mipmaps = true
	return font


func _label(text: String, font: DynamicFont, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_font_override("font", font)
	label.add_color_override("font_color", _theme_text(color))
	if _modern_theme_active():
		label.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	else:
		label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.95))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 2)
	return label


func _button(text: String, color: Color, width: int, icon_path: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.rect_min_size = Vector2(width, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_font_override("font", _body_font)
	var themed_color := _theme_accent(_theme_fill(color))
	var bw := 3
	if _modern_theme_active():
		bw = 0
	button.add_stylebox_override("normal", _style(themed_color, WHITE, bw, 14))
	button.add_stylebox_override("hover", _style(themed_color.lightened(0.14), WHITE, bw, 14))
	button.add_stylebox_override("pressed", _style(themed_color.darkened(0.18), WHITE, bw, 14))
	if not icon_path.empty():
		var icon = load(icon_path)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
	return button


func _style(color: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _theme_fill(color)
	style.border_color = _theme_border(border)
	var w := border_width
	var r := radius
	if _modern_theme_active():
		w = min(border_width, 2)
		r = min(radius, 10)
	style.border_width_left = w
	style.border_width_top = w
	style.border_width_right = w
	style.border_width_bottom = w
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
