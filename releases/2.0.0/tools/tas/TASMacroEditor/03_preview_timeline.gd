extends "user://mod/tools/tas/TASMacroEditor/02_editor_freecam.gd"

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.connect("gui_input", self, "_on_editor_background_gui_input")
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.025)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.add_child(dim)
	_timeline_panel = PanelContainer.new()
	_timeline_panel.anchor_left = 0.015
	_timeline_panel.anchor_top = 0.42
	_timeline_panel.anchor_right = 0.985
	_timeline_panel.anchor_bottom = 0.985
	_timeline_panel.add_stylebox_override("panel", _style(NAVY, Color(0.26, 0.67, 1.0, 0.9), 4, 24))
	_root.add_child(_timeline_panel)
	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	var timeline_section_scroll := ScrollContainer.new()
	timeline_section_scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	timeline_section_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_section_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline_panel.add_child(timeline_section_scroll)
	timeline_section_scroll.add_child(margin)
	var main := VBoxContainer.new()
	_timeline_content = main
	main.add_constant_override("separation", 10)
	margin.add_child(main)

	var freecam_panel := PanelContainer.new()
	freecam_panel.anchor_left = 0.015
	freecam_panel.anchor_top = 0.025
	freecam_panel.anchor_right = 0.46
	freecam_panel.anchor_bottom = 0.115
	freecam_panel.add_stylebox_override("panel", _style(NAVY, Color(0.26, 0.67, 1.0), 4, 18))
	_root.add_child(freecam_panel)
	var freecam_row := HBoxContainer.new()
	freecam_row.add_constant_override("separation", 8)
	freecam_panel.add_child(freecam_row)
	var freecam_title := _label("⋮⋮  FREECAM", _body_font, WHITE)
	freecam_title.hint_tooltip = "Right-drag the level or use arrow keys to move the camera."
	freecam_title.valign = Label.VALIGN_CENTER
	freecam_row.add_child(freecam_title)
	_add_editor_move_handle("freecam", freecam_panel, freecam_title)
	var zoom_out := _button("−", PANEL, 52)
	zoom_out.hint_tooltip = "Zoom out"
	zoom_out.connect("pressed", self, "_zoom_freecam", [1.15])
	freecam_row.add_child(zoom_out)
	_freecam_zoom_label = _label("100%", _body_font, WHITE)
	_freecam_zoom_label.rect_min_size = Vector2(82, 48)
	_freecam_zoom_label.align = Label.ALIGN_CENTER
	_freecam_zoom_label.valign = Label.VALIGN_CENTER
	freecam_row.add_child(_freecam_zoom_label)
	var zoom_in := _button("+", PANEL, 52)
	zoom_in.hint_tooltip = "Zoom in"
	zoom_in.connect("pressed", self, "_zoom_freecam", [1.0 / 1.15])
	freecam_row.add_child(zoom_in)
	var center := _button("CENTER", BLUE, 124)
	center.hint_tooltip = "Re-center and follow the scrubbed player."
	center.connect("pressed", self, "_center_freecam")
	freecam_row.add_child(center)
	var reset_camera := _button("RESET", PANEL, 112)
	reset_camera.hint_tooltip = "Restore the level camera position and zoom."
	reset_camera.connect("pressed", self, "_reset_freecam")
	freecam_row.add_child(reset_camera)

	var header := HBoxContainer.new()
	header.add_constant_override("separation", 12)
	main.add_child(header)
	_claude_title_icon = TextureRect.new()
	_claude_title_icon.expand = true
	_claude_title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_claude_title_icon.rect_min_size = Vector2(40, 40)
	_claude_title_icon.visible = false
	header.add_child(_claude_title_icon)
	var title := _label("⋮⋮  TIMELINE", _body_font, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_editor_move_handle("timeline", _timeline_panel, title)
	_name_edit = LineEdit.new()
	_name_edit.rect_min_size = Vector2(180, 48)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_font_override("font", _body_font)
	_name_edit.placeholder_text = "Macro name"
	_name_edit.connect("text_changed", self, "_on_name_changed")
	header.add_child(_name_edit)
	var save := _button("SAVE CHANGES", GREEN, 175)
	save.hint_tooltip = "Save this edited macro."
	save.connect("pressed", self, "_save_changes")
	header.add_child(save)
	var close := _button("×", PINK, 56)
	close.connect("pressed", self, "close_editor")
	header.add_child(close)

	var transport := HBoxContainer.new()
	transport.add_constant_override("separation", 8)
	main.add_child(transport)
	var previous := _button("‹", PANEL, 54)
	previous.hint_tooltip = "Previous frame"
	previous.connect("pressed", self, "_select_relative", [-1])
	transport.add_child(previous)
	var next := _button("›", PANEL, 54)
	next.hint_tooltip = "Next frame"
	next.connect("pressed", self, "_select_relative", [1])
	transport.add_child(next)
	transport.add_child(_label("Frame", _body_font, DIM))
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 0
	_frame_spin.step = 1
	_frame_spin.rounded = true
	_frame_spin.rect_min_size = Vector2(130, 48)
	_frame_spin.add_font_override("font", _body_font)
	_frame_spin.connect("value_changed", self, "_on_frame_spin_changed")
	transport.add_child(_frame_spin)
	_segment_jump = OptionButton.new()
	_segment_jump.rect_min_size = Vector2(230, 48)
	_segment_jump.add_font_override("font", _body_font)
	_segment_jump.connect("item_selected", self, "_on_segment_selected")
	transport.add_child(_segment_jump)
	var play := _button("▶  PLAY MACRO", BLUE, 190)
	play.hint_tooltip = "Play this working copy without saving first."
	play.connect("pressed", self, "_play_working_copy")
	transport.add_child(play)
	var transport_spacer := Control.new()
	transport_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transport.add_child(transport_spacer)
	_active_actions_label = _label("INPUT: NONE", _body_font, WHITE)
	_active_actions_label.align = Label.ALIGN_RIGHT
	_active_actions_label.valign = Label.VALIGN_CENTER
	_active_actions_label.rect_min_size = Vector2(0, 28)
	_active_actions_label.clip_text = true
	main.add_child(_active_actions_label)

	var view_row := HBoxContainer.new()
	view_row.add_constant_override("separation", 10)
	main.add_child(view_row)
	for entry in [["◀", -1, "Preview backward"], ["Ⅱ", 0, "Pause preview"], ["▶", 1, "Preview forward"]]:
		var control := _button(entry[0], PANEL, 48)
		control.hint_tooltip = entry[2]
		control.connect("pressed", self, "_set_preview_direction", [entry[1]])
		view_row.add_child(control)
	_preview_clock = _label("00:00.000", _small_font, WHITE)
	_preview_clock.hint_tooltip = "Recorded timeline time. Preview does not advance the live race clock."
	view_row.add_child(_preview_clock)
	var preview_speed := OptionButton.new()
	preview_speed.add_font_override("font", _small_font)
	for speed in [0.25, 0.5, 1.0, 2.0]:
		preview_speed.add_item(str(speed) + "×")
	preview_speed.select(2)
	preview_speed.hint_tooltip = "Forward / reverse preview speed"
	preview_speed.connect("item_selected", self, "_on_preview_speed_changed")
	view_row.add_child(preview_speed)
	var checkpoint := _button("+ CHECKPOINT", PANEL, 150)
	checkpoint.hint_tooltip = "Split the working copy at this recorded frame. Save Changes keeps it."
	checkpoint.connect("pressed", self, "_place_timeline_checkpoint")
	view_row.add_child(checkpoint)
	var continue_button = _button("CONTINUE FROM HERE",PANEL,200)
	continue_button.hint_tooltip = "Replays through the selected frame, then pauses. Resume to record a new ending. Saved replay stays unchanged. Open its local level first."
	continue_button.connect("pressed",self,"_continue_from_selected")
	transport.add_child(continue_button)
	for entry in [["Inspector", "details"], ["Camera", "freecam"]]:
		var toggle := _button(entry[0], PANEL, 105)
		toggle.hint_tooltip = "Show / hide " + str(entry[0]).to_lower()
		toggle.connect("pressed", self, "_toggle_editor_panel", [entry[1]])
		view_row.add_child(toggle)
	var summary_row := HBoxContainer.new()
	summary_row.add_constant_override("separation", 10)
	main.add_child(summary_row)
	_summary_label = _label("", _small_font, DIM)
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.clip_text = true
	summary_row.add_child(_summary_label)
	var zoom_label := _label("TIMELINE ZOOM", _small_font, DIM)
	zoom_label.hint_tooltip = "Mouse wheel also zooms around the cursor."
	summary_row.add_child(zoom_label)
	_zoom = HSlider.new()
	_zoom.min_value = 0.08
	_zoom.max_value = 12.0
	_zoom.step = 0.01
	_zoom.value = 1.75
	_zoom.rect_min_size = Vector2(210, 44)
	_zoom.connect("value_changed", self, "_on_zoom_changed")
	summary_row.add_child(_zoom)

	_timeline = TimelineView.new()
	_timeline.display_font = _small_font
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.connect("frame_selected", self, "_select_frame")
	_timeline.connect("viewport_changed", self, "_on_timeline_view_changed")
	main.add_child(_timeline)
	_scroll = HSlider.new()
	_scroll.min_value = 0
	_scroll.step = 1
	_scroll.hint_tooltip = "Drag to scrub the player backward and forward through the run."
	_scroll.connect("value_changed", self, "_on_scroll_changed")
	main.add_child(_scroll)

	_details_panel = PanelContainer.new()
	_details_panel.anchor_left = 0.68
	_details_panel.anchor_top = 0.025
	_details_panel.anchor_right = 0.985
	_details_panel.anchor_bottom = 0.395
	_details_panel.add_stylebox_override("panel", _style(NAVY, Color(0.26, 0.67, 1.0, 0.9), 4, 20))
	_root.add_child(_details_panel)
	var details_margin := MarginContainer.new()
	details_margin.add_constant_override("margin_left", 14)
	details_margin.add_constant_override("margin_right", 14)
	details_margin.add_constant_override("margin_top", 12)
	details_margin.add_constant_override("margin_bottom", 12)
	_details_panel.add_child(details_margin)
	var details_root := VBoxContainer.new()
	details_root.add_constant_override("separation", 8)
	details_margin.add_child(details_root)
	var details_title := _label("⋮⋮  FRAME INSPECTOR", _body_font, WHITE)
	details_root.add_child(details_title)
	_add_editor_move_handle("details", _details_panel, details_title)
	var details_scroll := ScrollContainer.new()
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_root.add_child(details_scroll)
	var bottom := VBoxContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_constant_override("separation", 10)
	details_scroll.add_child(bottom)
	var input_panel := _panel_box("SELECTED FRAME INPUT")
	input_panel.rect_min_size = Vector2(0, 0)
	bottom.add_child(input_panel)
	var input_box: VBoxContainer = input_panel.get_child(0)
	for action in ACTIONS:
		var check := CheckButton.new()
		check.text = ACTION_LABELS[action]
		check.add_font_override("font", _body_font)
		check.add_color_override("font_color", ACTION_COLORS[action])
		check.connect("toggled", self, "_on_action_toggled", [action])
		input_box.add_child(check)
		_action_checks[action] = check
	_dash_direction = OptionButton.new()
	_dash_direction.add_font_override("font", _body_font)
	_dash_direction.add_item("Dash direction: LEFT", 0)
	_dash_direction.add_item("Dash direction: RIGHT", 1)
	_dash_direction.connect("item_selected", self, "_on_dash_direction_changed")
	input_box.add_child(_dash_direction)

	var state_panel := _panel_box("AUTHORITATIVE STATE")
	state_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(state_panel)
	var state_box: VBoxContainer = state_panel.get_child(0)
	_state_label = _label("", _small_font, DIM)
	_state_label.autowrap = true
	state_box.add_child(_state_label)
	var values := GridContainer.new()
	values.columns = 2
	state_box.add_child(values)
	_position_x = _number_field(values, "Position X")
	_position_y = _number_field(values, "Position Y")
	_velocity_x = _number_field(values, "Velocity X")
	_velocity_y = _number_field(values, "Velocity Y")
	var apply_state := _button("APPLY STATE VALUES", ORANGE, 210)
	apply_state.hint_tooltip = "Advanced: changing position or velocity can make a macro invalid"
	apply_state.connect("pressed", self, "_apply_state_values")
	state_box.add_child(apply_state)

	var edit_panel := _panel_box("FRAME TOOLS")
	edit_panel.rect_min_size = Vector2(0, 0)
	bottom.add_child(edit_panel)
	var edit_box: VBoxContainer = edit_panel.get_child(0)
	var duplicate := _button("DUPLICATE FRAME", BLUE, 220)
	duplicate.connect("pressed", self, "_duplicate_frame")
	edit_box.add_child(duplicate)
	var neutral := _button("INSERT NEUTRAL COPY", PANEL, 220)
	neutral.connect("pressed", self, "_insert_neutral_frame")
	edit_box.add_child(neutral)
	var move_row := HBoxContainer.new()
	var move_left := _button("← MOVE", PANEL, 105)
	move_left.connect("pressed", self, "_move_frame", [-1])
	move_row.add_child(move_left)
	var move_right := _button("MOVE →", PANEL, 105)
	move_right.connect("pressed", self, "_move_frame", [1])
	move_row.add_child(move_right)
	edit_box.add_child(move_row)
	var delete := _button("DELETE FRAME", PINK, 220)
	delete.connect("pressed", self, "_delete_frame")
	edit_box.add_child(delete)

	_status = _label("Drag the timeline to scrub · Wheel zooms · Right-drag pans the level", _small_font, WHITE)
	main.add_child(_status)
	_add_editor_resize_grip("timeline", _timeline_panel, Vector2(520, 300))
	_add_editor_resize_grip("details", _details_panel, Vector2(300, 220))
	_add_editor_resize_grip("freecam", freecam_panel, Vector2(650, 58))
	call_deferred("_sync_editor_resize_grips")


func _rebuild_timeline() -> void:
	_set_preview_direction(0)
	_flat_frames.clear()
	_locations.clear()
	_boundaries.clear()
	var cumulative := 0
	var segments: Array = working_data.get("segments", [])
	for segment_index in range(segments.size()):
		_boundaries.append(cumulative)
		var segment: Array = segments[segment_index]
		for local_index in range(segment.size()):
			_flat_frames.append(segment[local_index])
			_locations.append(Vector2(segment_index, local_index))
			cumulative += 1
	_selected_frame = clamp(_selected_frame, 0, max(0, _flat_frames.size() - 1))
	var checkpoints: Array = working_data.get("checkpoints", [])
	for index in range(min(checkpoints.size(), _boundaries.size())):
		checkpoints[index]["timeline_version"] = 1
		checkpoints[index]["timeline_frame"] = int(_boundaries[index])
		checkpoints[index]["timeline_time"] = float(_boundaries[index]) / 60.0
	_timeline.set_timeline_data(_flat_frames, _boundaries)
	_timeline.set_selected_frame(_selected_frame)
	_frame_spin.max_value = max(0, _flat_frames.size() - 1)
	_scroll.max_value = max(0, _flat_frames.size() - 1)
	var duration := float(_flat_frames.size()) / 60.0
	_summary_label.text = "%s FRAMES   ·   %02d:%05.2f   ·   %d CHECKPOINTS" % [_flat_frames.size(), int(duration) / 60, fmod(duration, 60.0), _boundaries.size()]
	_segment_jump.clear()
	for i in range(_boundaries.size()):
		_segment_jump.add_item("Checkpoint %d · frame %d" % [i, _boundaries[i]])
	_refresh_inspector()
	call_deferred("_fit_editor_panels")


func _select_frame(frame_index: int, from_transport: bool = false) -> void:
	if not from_transport:
		_set_preview_direction(0)
	_selected_frame = clamp(frame_index, 0, max(0, _flat_frames.size() - 1))
	_timeline.set_selected_frame(_selected_frame)
	_refresh_inspector()


func _set_preview_direction(direction: int) -> void:
	_preview_direction = int(clamp(direction, -1, 1))
	_preview_fraction = 0.0
	if _flat_frames.empty():
		_preview_direction = 0


func _advance_preview(delta: float) -> void:
	if _preview_direction == 0:
		return
	if tas_tool == null or not is_instance_valid(tas_tool) or not bool(tas_tool.get("_macro_editor_preview_active")):
		_set_preview_direction(0)
		return
	# Recorded input ticks, not backwards physics or a rewritten race clock.
	_preview_fraction += max(0.0, delta) * 60.0 * _preview_speed
	var steps := int(_preview_fraction + 0.000001)
	if steps == 0:
		return
	_preview_fraction = max(0.0, _preview_fraction - steps)
	_select_frame(_selected_frame + steps * _preview_direction, true)
	if _selected_frame == 0 or _selected_frame == _flat_frames.size() - 1:
		_set_preview_direction(0)


func _timeline_seconds() -> float:
	return float(_selected_frame) / 60.0


func _on_preview_speed_changed(index: int) -> void:
	_preview_speed = [0.25, 0.5, 1.0, 2.0][int(clamp(index, 0, 3))]


func _select_relative(delta: int) -> void:
	_select_frame(_selected_frame + delta)


func _on_frame_spin_changed(value: float) -> void:
	if not _updating_controls:
		_select_frame(int(value))


func _on_segment_selected(index: int) -> void:
	if index >= 0 and index < _boundaries.size():
		_select_frame(int(_boundaries[index]))


func _on_zoom_changed(value: float) -> void:
	_timeline.set_zoom(value)


func _on_scroll_changed(value: float) -> void:
	if not _updating_controls:
		_select_frame(int(value))


func _on_timeline_view_changed(scroll_frame: float, pixels_per_frame: float) -> void:
	_updating_controls = true
	_zoom.value = pixels_per_frame
	_updating_controls = false


func _refresh_inspector() -> void:
	_updating_controls = true
	var seconds := _timeline_seconds()
	_preview_clock.text = "%02d:%06.3f" % [int(seconds) / 60, fmod(seconds, 60.0)]
	_frame_spin.value = _selected_frame
	_scroll.value = _selected_frame
	if _flat_frames.empty():
		_state_label.text = "No frame selected"
		_active_actions_label.text = "INPUT: NONE"
		_updating_controls = false
		return
	var frame: Dictionary = _flat_frames[_selected_frame]
	var active_actions := []
	for action in ACTIONS:
		var active := bool(frame.get(action, false))
		_action_checks[action].set_pressed_no_signal(active)
		if active:
			active_actions.append(ACTION_LABELS[action])
	_dash_direction.select(1 if bool(frame.get(DASH_DIRECTION_KEY, true)) else 0)
	_active_actions_label.text = "INPUT: %s" % (" + ".join(active_actions) if not active_actions.empty() else "NONE")
	_active_actions_label.add_color_override("font_color", _theme_accent(GREEN) if not active_actions.empty() else _theme_text(DIM))
	var location: Vector2 = _locations[_selected_frame]
	var state = frame.get(STATE_KEY, {})
	if typeof(state) == TYPE_DICTIONARY:
		var position: Vector2 = state.get("position", Vector2.ZERO)
		var velocity: Vector2 = state.get("linear_velocity", Vector2.ZERO)
		_position_x.value = position.x
		_position_y.value = position.y
		_velocity_x.value = velocity.x
		_velocity_y.value = velocity.y
		_state_label.text = "Segment %d · local frame %d · %.3fs\nPosition %s   Velocity %s\nDash cooldown %s · Coyote %s · Ground timer %s" % [int(location.x), int(location.y), seconds, position, velocity, state.get("dash_cooldown", "—"), state.get("coyote_timer", "—"), state.get("stick_to_ground_timer", "—")]
	else:
		_state_label.text = "Legacy input-only frame · no authoritative state stored"
	_updating_controls = false
	_preview_selected_frame(frame)


func _preview_selected_frame(frame: Dictionary) -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_preview_macro_editor_frame"):
		var shown := bool(tas_tool.call("_preview_macro_editor_frame", frame))
		if shown and tas_tool.has_method("_set_macro_editor_time"):
			tas_tool.call("_set_macro_editor_time", _timeline_seconds())
		if not shown:
			_set_preview_direction(0)
		if not shown and not frame.has(STATE_KEY):
			_status.text = "This old input-only macro has no recorded positions to preview."
