extends "user://mod/tools/tas/TASTool/27_timeline.gd"

func _attach_section_replay_card(card) -> void:
	if is_instance_valid(card):
		_tas_studio().leaderboard_boxes().attach_native(card)

func _on_section_boxes_from_leaderboard() -> void:
	_tas_studio().leaderboard_boxes().open_leaderboard()

# Tools and Macro Bot pages, 4.0 layout. Every control is the same field,
# handler and bound argument as before; toggles are shown as switch rows that
# wrap the original button (see core/workspace4/ToggleRow.gd).

const V4PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const V4ToggleRow = preload("user://mod/core/workspace4/ToggleRow.gd")
const V4Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")


func _v4_row(parent: Control, button: Button, title: String, description: String, icon_name: String, on_text: String = "") -> Control:
	var row = V4ToggleRow.new()
	parent.add_child(row)
	row.setup(button, title, description, icon_name, _body_font, _small_font, on_text)
	return row


func _v4_hbox(parent: Control, separation: int = 10) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", separation)
	parent.add_child(row)
	return row


func _v4_columns(parent: Control) -> Array:
	var columns = _v4_hbox(parent, 12)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_constant_override("separation", 12)
	columns.add_child(left)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_constant_override("separation", 12)
	columns.add_child(right)
	return [left, right]


func _v4_spacer(parent: Control) -> void:
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


func _v4_hint(parent: Control, text: String) -> Label:
	var label = _make_label(text, _small_font, COLOR_TEXT_DIM)
	label.autowrap = true
	parent.add_child(label)
	return label


# − value + with small buttons. The value label is the tool's own label.
func _v4_stepper(parent: Control, caption: String, value_label: Label, method: String, minus_args: Array, plus_args: Array, width: int = 84) -> HBoxContainer:
	var row = _v4_hbox(parent, 6)
	if not caption.empty():
		var title = _make_label(caption, _body_font, COLOR_TEXT_DIM)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
	var minus = _make_small_button("−", COLOR_BLUE, 38)
	minus.connect("pressed", self, method, minus_args)
	row.add_child(minus)
	value_label.rect_min_size = Vector2(width, 0)
	value_label.align = Label.ALIGN_CENTER
	value_label.valign = Label.VALIGN_CENTER
	row.add_child(value_label)
	var plus = _make_small_button("+", COLOR_BLUE, 38)
	plus.connect("pressed", self, method, plus_args)
	row.add_child(plus)
	return row


func _build_tools_page(playback_page: VBoxContainer) -> void:
	var tabs = V4PageTabs.new()
	playback_page.add_child(tabs)
	tabs.setup("tools", _body_font)
	var time_tab = tabs.add_tab("Time control", "tools")
	var inspect_tab = tabs.add_tab("Inspection", "eye")
	var assist_tab = tabs.add_tab("Inputs & assists", "keyboard")

	# TIME CONTROL
	var cols = _v4_columns(time_tab)
	var speed_card = _open_card(cols[0], "Game speed")
	var speed_row = _v4_hbox(speed_card, 10)
	_play_stop_button = _make_button("■ STOP", COLOR_BLUE, 130)
	_play_stop_button.hint_tooltip = "Pause or resume the game."
	_play_stop_button.connect("pressed", self, "_toggle_pause")
	speed_row.add_child(_play_stop_button)
	_v4_spacer(speed_row)
	_speed_label = _make_label("1.00x", _header_font, COLOR_WHITE)
	var speed_stepper = _v4_stepper(speed_row, "", _speed_label, "_adjust_time_scale", [-TIME_SCALE_STEP], [TIME_SCALE_STEP], 96)
	speed_stepper.get_child(0).hint_tooltip = "Slower"
	speed_stepper.get_child(2).hint_tooltip = "Faster"
	var reset_row = _v4_hbox(speed_card, 10)
	_v4_hint(reset_row, "Speed changes how fast the game runs while you work.").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reset_btn = _make_small_button("Reset to 1×", COLOR_BLUE, 120)
	reset_btn.hint_tooltip = "Back to normal speed."
	reset_btn.connect("pressed", self, "_on_reset_speed_pressed")
	reset_row.add_child(reset_btn)

	var step_card = _open_card(cols[1], "Frame stepping")
	_frame_step_checkbox = _make_button("Frame-Step Mode: %s" % ("ON" if enable_frame_step else "OFF"), COLOR_PINK if enable_frame_step else COLOR_BLUE, 0)
	_frame_step_checkbox.toggle_mode = true
	_frame_step_checkbox.set_pressed_no_signal(enable_frame_step)
	_frame_step_checkbox.connect("toggled", self, "_on_enable_frame_step_toggled")
	_frame_step_checkbox.hint_tooltip = "Pause physics and advance it manually."
	_v4_row(step_card, _frame_step_checkbox, "Frame stepping", "Pause physics and advance it by hand", "step")
	var step_row = _v4_hbox(step_card, 10)
	_step_button = _make_button("Step ▸", COLOR_PINK, 110)
	_step_button.disabled = not enable_frame_step
	_step_button.connect("pressed", self, "_request_frame_step")
	_step_button.hint_tooltip = "Advance the configured number of physics frames."
	step_row.add_child(_step_button)
	_v4_spacer(step_row)
	_step_config_row = HBoxContainer.new()
	_step_config_row.add_constant_override("separation", 6)
	step_row.add_child(_step_config_row)
	_step_count_label = _make_label("%d" % frame_step_count, _header_font, COLOR_WHITE)
	_v4_stepper(_step_config_row, "per press", _step_count_label, "_on_step_count_delta_pressed", [-1], [1], 52)
	_v4_hint(step_card, "Hold during the next step")
	var buffer_row = _v4_hbox(step_card, 6)
	for entry in BUFFERABLE_ACTIONS:
		var label: String = entry[0]
		var action: String = entry[1]
		var buf_btn = _make_small_button(label, COLOR_BLUE, 0)
		buf_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buf_btn.hint_tooltip = "Hold %s during the next frame step." % label.capitalize()
		buf_btn.connect("pressed", self, "_on_toggle_buffered_action_pressed", [action])
		_buffer_action_buttons[action] = buf_btn
		buffer_row.add_child(buf_btn)

	var run_card = _open_card(time_tab, "Run options")
	_tas_run_options().build_controls(self, run_card)

	# INSPECTION
	cols = _v4_columns(inspect_tab)
	var world_card = _open_card(cols[0], "World overlays")
	_hitbox_viewer_button = _make_button("◫ Hitbox Viewer: OFF", COLOR_BLUE, 0)
	_hitbox_viewer_button.hint_tooltip = "Show selected collision shapes."
	_hitbox_viewer_button.connect("pressed", self, "_on_toggle_hitbox_viewer_pressed")
	_v4_row(world_card, _hitbox_viewer_button, "Hitbox viewer", "Show collision shapes in the level", "hitbox")
	_hitbox_category_row = HBoxContainer.new()
	_hitbox_category_row.add_constant_override("separation", 6)
	_hitbox_category_row.visible = _hitbox_viewer_enabled
	for entry in HITBOX_CATEGORIES:
		var category: String = entry[0]
		var category_button := _make_small_button(entry[1], COLOR_BLUE, 0)
		category_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_button.toggle_mode = true
		category_button.pressed = bool(_hitbox_categories.get(category, false))
		category_button.hint_tooltip = entry[2]
		category_button.connect("toggled", self, "_on_hitbox_category_toggled", [category])
		_hitbox_category_buttons[category] = category_button
		_hitbox_category_row.add_child(category_button)
	world_card.add_child(_hitbox_category_row)
	_refresh_hitbox_category_ui()
	_trajectory_preview_button = _make_button("⌁ Trajectory Preview: OFF", COLOR_BLUE, 0)
	_trajectory_preview_button.hint_tooltip = "Estimate: current velocity + gravity, stopped at the first solid or hazard. Red × = predicted death. Does not know future inputs, wind, moving objects or laser phase changes."
	_trajectory_preview_button.connect("pressed", self, "_on_toggle_trajectory_preview_pressed")
	_v4_row(world_card, _trajectory_preview_button, "Trajectory preview", "Estimate from speed and gravity", "trajectory")
	_frame_info_button = _make_button("ℹ Frame info: OFF", COLOR_BLUE, 0)
	_frame_info_button.hint_tooltip = "Exact position, speed and timers for the current frame, plus the gap to your reference run."
	_frame_info_button.connect("pressed", self, "_on_toggle_frame_info_pressed")
	_v4_row(world_card, _frame_info_button, "Frame info", "Position, speed and timers for this frame", "frameinfo")

	var input_card = _open_card(cols[1], "Input display")
	_input_display_button = _make_button("⌨ Input Display: OFF", COLOR_BLUE, 0)
	_input_display_button.hint_tooltip = "Show a small overlay of recorded/live input state."
	_input_display_button.connect("pressed", self, "_on_toggle_input_display_pressed")
	_v4_row(input_card, _input_display_button, "Input display", "Overlay of live and recorded inputs", "keyboard")
	_input_display_detailed_button = _make_small_button("Compact", COLOR_BLUE, 0)
	_input_display_detailed_button.hint_tooltip = "Toggle between a compact and a detailed (LIVE/REPLAY tag) overlay."
	_input_display_detailed_button.connect("pressed", self, "_on_toggle_input_display_detailed_pressed")
	_input_display_detailed_button.visible = _input_display_enabled
	_v4_row(input_card, _input_display_detailed_button, "Detailed", "Adds LIVE and REPLAY tags", "", "Detailed")
	_input_display_hold_frames_button = _make_small_button("Frame Holds: OFF", COLOR_BLUE, 0)
	_input_display_hold_frames_button.hint_tooltip = "Show how many ticks each held input has been down."
	_input_display_hold_frames_button.connect("pressed", self, "_on_toggle_input_display_hold_frames_pressed")
	_input_display_hold_frames_button.visible = _input_display_enabled
	_v4_row(input_card, _input_display_hold_frames_button, "Hold frames", "Ticks each held input has been down", "")

	var display_card = _open_card(cols[1], "Display")
	_fps_limit_label = _make_label(("%d FPS" % fps_limit) if fps_limit > 0 else "Uncapped", _header_font, COLOR_WHITE)
	var fps_row = _v4_stepper(display_card, "Render FPS limit", _fps_limit_label, "_on_fps_limit_delta_pressed", [-FPS_LIMIT_STEP], [FPS_LIMIT_STEP], 110)
	fps_row.get_child(1).hint_tooltip = "Lower the render FPS limit."
	fps_row.get_child(3).hint_tooltip = "Raise the render FPS limit. 0 is uncapped."
	_v4_hint(display_card, "Limits drawing only. Recorded ticks stay the same.")

	# INPUTS & ASSISTS
	cols = _v4_columns(assist_tab)
	var assist_card = _open_card(cols[0], "Input assists")
	_jumpzone_button = _make_button("⤒ Perfect Jumpzone: OFF", COLOR_BLUE, 0)
	_jumpzone_button.hint_tooltip = "Repeat Jump using the configured rhythm."
	_jumpzone_button.connect("pressed", self, "_on_toggle_jumpzone_pressed")
	_v4_row(assist_card, _jumpzone_button, "Perfect Jumpzone", "Repeats Jump on a rhythm", "bolt")
	_jumpzone_config_row = VBoxContainer.new()
	_jumpzone_config_row.add_constant_override("separation", 8)
	assist_card.add_child(_jumpzone_config_row)
	_jumpzone_interval_label = _make_label("%.0fms" % jumpzone_interval_ms, _header_font, COLOR_WHITE)
	_v4_stepper(_jumpzone_config_row, "Interval", _jumpzone_interval_label, "_on_jumpzone_interval_delta_pressed", [-JUMPZONE_TIMING_STEP_MS], [JUMPZONE_TIMING_STEP_MS], 90)
	_jumpzone_hold_label = _make_label("%.0fms" % jumpzone_hold_ms, _header_font, COLOR_WHITE)
	_v4_stepper(_jumpzone_config_row, "Hold", _jumpzone_hold_label, "_on_jumpzone_hold_delta_pressed", [-JUMPZONE_TIMING_STEP_MS], [JUMPZONE_TIMING_STEP_MS], 90)

	var recorded_card = _open_card(cols[1], "Recorded inputs")
	_v4_hint(recorded_card, "Frame-by-frame input editing lives in the Macro Bot timeline.")
	var timeline_btn = _make_button("▤ Edit recorded inputs", COLOR_PURPLE, 0)
	timeline_btn.hint_tooltip = "Open the detailed frame timeline for the working run."
	timeline_btn.connect("pressed", self, "_on_edit_current_practice_macro_pressed")
	recorded_card.add_child(timeline_btn)
	tabs.finish()


# Macro Bot page: Run (record, use, options) and Saved macros.
func _build_macro_bot_page(practice_page: VBoxContainer) -> void:
	var practice_root: = practice_page
	var tabs = V4PageTabs.new()
	practice_root.add_child(tabs)
	tabs.setup("macro_bot", _body_font)
	var run_tab = tabs.add_tab("Run", "macro")
	var slots_tab = tabs.add_tab("Saved macros", "folder")

	# Working run summary
	var summary = PanelContainer.new()
	var summary_style = V4Galaxy.box(V4Galaxy.color("raised"), V4Galaxy.color("accent"), 16, 14)
	summary_style.content_margin_top = 12
	summary_style.content_margin_bottom = 12
	summary.add_stylebox_override("panel", summary_style)
	run_tab.add_child(summary)
	var summary_row = _v4_hbox(summary, 14)
	var orb = TextureRect.new()
	orb.texture = V4Galaxy.texture("orb-violet.png")
	orb.expand = true
	orb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	orb.rect_min_size = Vector2(46, 46)
	summary_row.add_child(orb)
	var orb_icon = TextureRect.new()
	orb_icon.texture = V4Galaxy.icon("macro", Color(1, 1, 1), 22)
	orb_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	orb_icon.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	orb.add_child(orb_icon)
	var summary_text = VBoxContainer.new()
	summary_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_text.alignment = BoxContainer.ALIGN_CENTER
	summary_text.add_constant_override("separation", 2)
	summary_row.add_child(summary_text)
	summary_text.add_child(_make_label("Working run", _small_font, COLOR_TEXT_DIM))
	_practice_status_label = _make_label("0 checkpoint(s) placed", _header_font, COLOR_WHITE)
	_practice_status_label.autowrap = true
	summary_text.add_child(_practice_status_label)

	var workflow = load("user://mod/tools/tas/TASWorkflowPanel.gd").new()
	run_tab.add_child(workflow)
	workflow.setup(self)
	# The same checkpoint controls retain their original signals and state.
	var record_card = _open_card(workflow.checkpoint_body, "Record")
	var record_row = _v4_hbox(record_card, 8)
	_practice_toggle_button = _make_button("● Start recording", COLOR_PINK, 0)
	_practice_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_toggle_button.hint_tooltip = "Macro Bot Mode: record a run in checkpointed segments."
	_practice_toggle_button.connect("pressed", self, "_on_toggle_practice_pressed")
	record_row.add_child(_practice_toggle_button)
	_practice_place_button = _make_button("Checkpoint", COLOR_BLUE, 0)
	_practice_place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_place_button.hint_tooltip = "Commit the current segment and start the next one."
	_practice_place_button.disabled = true
	_practice_place_button.connect("pressed", self, "_on_place_practice_checkpoint_pressed")
	record_row.add_child(_practice_place_button)
	var pause_button = _make_button("Pause", COLOR_BLUE, 0)
	pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_button.hint_tooltip = "Pause or resume. Same as Pause in Tools."
	pause_button.connect("pressed", self, "_toggle_pause")
	record_row.add_child(pause_button)
	_practice_undo_button = _make_button("↩ Undo", COLOR_BLUE, 0)
	_practice_undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_undo_button.hint_tooltip = "Remove the most recent checkpoint and its segment. Shortcut: " + _keybinds.caption("checkpoint_undo")
	_practice_undo_button.disabled = true
	_practice_undo_button.connect("pressed", self, "_on_undo_practice_checkpoint_pressed")
	record_row.add_child(_practice_undo_button)

	var cols = _v4_columns(run_tab)
	var use_card = _open_card(cols[0], "Use the run")
	_practice_play_button = _make_button("▶ Play working run", COLOR_PLAY_GREEN, 0)
	_practice_play_button.hint_tooltip = "Play the current checkpointed run (stitched)."
	_practice_play_button.disabled = true
	_practice_play_button.connect("pressed", self, "_on_play_practice_macro_pressed")
	use_card.add_child(_practice_play_button)
	var use_row = _v4_hbox(use_card, 8)
	_practice_open_loaded_level_button = _make_small_button("Open level", COLOR_BLUE, 0)
	_practice_open_loaded_level_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_open_loaded_level_button.hint_tooltip = "Open the loaded macro's linked level without starting playback."
	_practice_open_loaded_level_button.visible = false
	_practice_open_loaded_level_button.connect("pressed", self, "_on_open_loaded_macro_level_pressed")
	use_row.add_child(_practice_open_loaded_level_button)

	var options_card = _open_card(cols[1], "Run options")
	var edit_current_button = _make_small_button("Timeline editor", COLOR_PURPLE, 0)
	edit_current_button.icon = V4Galaxy.icon("timeline",V4Galaxy.color("ink"),18)
	edit_current_button.hint_tooltip = "Inspect and edit the working run in either TAS mode."
	edit_current_button.connect("pressed",self,"_on_edit_current_practice_macro_pressed")
	options_card.add_child(edit_current_button)
	var checkpoint_options = _open_card(workflow.checkpoint_body,"Checkpoint options")
	_practice_auto_respawn_button = _make_small_button("⟲ Auto-Respawn to Checkpoint: ON", COLOR_PINK, 0)
	_practice_auto_respawn_button.hint_tooltip = "Retry only the current segment after dying."
	_practice_auto_respawn_button.connect("pressed", self, "_on_toggle_practice_auto_respawn_pressed")
	_v4_row(checkpoint_options, _practice_auto_respawn_button, "Auto-respawn", "Retry only this segment after dying", "rewind")
	_practice_auto_activate = bool(SavedSettings.get_value("client_tools_macro_record_on_entry", false))
	_practice_auto_activate_button = _make_small_button("Record on level entry: ON" if _practice_auto_activate else "Record on level entry: OFF", COLOR_PINK if _practice_auto_activate else COLOR_BLUE, 0)
	_practice_auto_activate_button.hint_tooltip = "Starts recording on the first playable frame every time you enter or restart a level. Saved Play / Continue From are not affected."
	_practice_auto_activate_button.connect("pressed", self, "_on_toggle_practice_auto_activate_pressed")
	_v4_row(checkpoint_options, _practice_auto_activate_button, "Record on level entry", "Starts on the first playable frame", "record")

	var polish_card = _open_card(run_tab, "Playback polish")
	var polish_cols = _v4_columns(polish_card)
	_visual_seam_polish_button = _make_button("◇ Visual Seam Polish: OFF", COLOR_BLUE, 0)
	_visual_seam_polish_button.hint_tooltip = "Smooths how checkpoint corrections look in local playback. Render only; it does not change the run. Use safe checkpoint areas."
	_visual_seam_polish_button.connect("pressed", self, "_on_toggle_visual_seam_polish_pressed")
	_v4_row(polish_cols[0], _visual_seam_polish_button, "Visual seam polish", "Render only: smooths checkpoint joins", "star")
	_sync_moving_objects_button = _make_button("↻ Moving Object Sync: OFF", COLOR_BLUE, 0)
	_sync_moving_objects_button.hint_tooltip = "Capture moving platforms/hazards at checkpoints for local playback."
	_sync_moving_objects_button.connect("pressed", self, "_on_toggle_sync_moving_objects_pressed")
	_v4_row(polish_cols[1], _sync_moving_objects_button, "Moving object sync", "Captures platforms and hazards at checkpoints", "replay")

	# Debug tools: shown only when Debug tools is on (the 4.0 menu moves this
	# container to the Developer page).
	_debug_tools_container = VBoxContainer.new()
	_debug_tools_container.add_constant_override("separation", 4)
	_debug_tools_container.visible = _debug_mode_enabled
	run_tab.add_child(_debug_tools_container)
	var debug_heading := _make_label("DEBUG TOOLS", _small_font, COLOR_PINK)
	debug_heading.hint_tooltip = "Enable or disable this section in Goober Dash Settings."
	_debug_tools_container.add_child(debug_heading)
	var diag_row: = HBoxContainer.new()
	diag_row.add_constant_override("separation", 10)
	_diag_toggle_button = _make_button("Diagnostic Logging: OFF", COLOR_BLUE, 300)
	_diag_toggle_button.hint_tooltip = "Capture live and playback state for comparison."
	_diag_toggle_button.connect("pressed", self, "_on_toggle_diag_pressed")
	diag_row.add_child(_diag_toggle_button)
	_diag_compare_button = _make_button("Compare Live vs Replay", COLOR_BLUE, 260)
	_diag_compare_button.hint_tooltip = "Save a report for the first mismatch."
	_diag_compare_button.connect("pressed", self, "_on_compare_diagnostics_pressed")
	diag_row.add_child(_diag_compare_button)
	_debug_tools_container.add_child(diag_row)
	_diag_status_label = _make_label("no diagnostic data captured yet", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_diag_status_label)
	_stop_on_desync_button = _make_button("Stop on Desync: OFF", COLOR_BLUE, 300)
	_stop_on_desync_button.hint_tooltip = "Automatically stop Play Macro the first time replay state diverges from the recorded run."
	_stop_on_desync_button.connect("pressed", self, "_on_toggle_stop_on_desync_pressed")
	_debug_tools_container.add_child(_stop_on_desync_button)
	_replay_check_status_label = _make_label("Replay Accuracy: --  |  First Desync: --  |  Largest Drift: --", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_replay_check_status_label)
	var self_test_row: = HBoxContainer.new()
	self_test_row.add_constant_override("separation", 8)
	_self_test_x3_button = _make_small_button("Self-Test x3", COLOR_BLUE)
	_self_test_x3_button.connect("pressed", self, "_on_self_test_x3_pressed")
	self_test_row.add_child(_self_test_x3_button)
	_self_test_x5_button = _make_small_button("x5", COLOR_BLUE)
	_self_test_x5_button.connect("pressed", self, "_on_self_test_x5_pressed")
	self_test_row.add_child(_self_test_x5_button)
	_self_test_x10_button = _make_small_button("x10", COLOR_BLUE)
	_self_test_x10_button.connect("pressed", self, "_on_self_test_x10_pressed")
	self_test_row.add_child(_self_test_x10_button)
	_self_test_stop_on_failure_button = _make_small_button("Stop on Failure: OFF", COLOR_BLUE)
	_self_test_stop_on_failure_button.connect("pressed", self, "_on_toggle_self_test_stop_on_failure_pressed")
	self_test_row.add_child(_self_test_stop_on_failure_button)
	_debug_tools_container.add_child(self_test_row)
	_self_test_status_label = _make_label("Replay Self-Test: no runs yet", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_self_test_status_label)
	var restore_drift_row: = HBoxContainer.new()
	restore_drift_row.add_constant_override("separation", 10)
	_restore_drift_toggle_button = _make_button("Restore Drift Diagnostics: OFF", COLOR_BLUE, 300)
	_restore_drift_toggle_button.hint_tooltip = "Measure movement immediately after restores."
	_restore_drift_toggle_button.connect("pressed", self, "_on_toggle_restore_drift_pressed")
	restore_drift_row.add_child(_restore_drift_toggle_button)
	_restore_drift_save_button = _make_button("Save Restore Drift Report", COLOR_BLUE, 260)
	_restore_drift_save_button.hint_tooltip = "Save the captured restore measurements."
	_restore_drift_save_button.connect("pressed", self, "_on_save_restore_drift_report_pressed")
	restore_drift_row.add_child(_restore_drift_save_button)
	_debug_tools_container.add_child(restore_drift_row)
	_restore_drift_status_label = _make_label("no restore drift data captured yet", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_restore_drift_status_label)
	var noclip_row: = HBoxContainer.new()
	noclip_row.add_constant_override("separation", 10)
	_noclip_toggle_button = _make_button("Debug Noclip: OFF", COLOR_BLUE, 300)
	_noclip_toggle_button.hint_tooltip = "Fly with Left/Right, Jump up and Dash down."
	_noclip_toggle_button.connect("pressed", self, "_on_toggle_noclip_pressed")
	noclip_row.add_child(_noclip_toggle_button)
	_debug_tools_container.add_child(noclip_row)

	var clear_row = _v4_hbox(run_tab, 10)
	_v4_spacer(clear_row)
	_practice_clear_button = _make_small_button("✕ Clear working run", COLOR_PINK_DARK, 0)
	_practice_clear_button.hint_tooltip = "Clear the current unsaved run. Saved slots are not touched."
	_practice_clear_button.disabled = true
	_practice_clear_button.connect("pressed", self, "_on_clear_practice_pressed")
	clear_row.add_child(_practice_clear_button)

	# SAVED MACROS -- one row per slot; each row's buttons are bound to that
	# slot's real number.
	var slots_heading = _v4_hbox(slots_tab, 8)
	var add_slot_button := _make_small_button("＋ Add slot", COLOR_PLAY_GREEN, 0)
	add_slot_button.hint_tooltip = "Add another persistent macro slot."
	add_slot_button.connect("pressed", self, "_on_add_practice_macro_slot_pressed")
	slots_heading.add_child(add_slot_button)
	var remove_slot_button := _make_small_button("Remove last empty slot", COLOR_BLUE, 0)
	remove_slot_button.hint_tooltip = "Remove the final slot if it is empty. Saved macros are never removed by this."
	remove_slot_button.connect("pressed", self, "_on_remove_last_practice_macro_slot_pressed")
	slots_heading.add_child(remove_slot_button)
	_v4_spacer(slots_heading)
	slots_heading.add_child(_make_label("Save here stores the working run · Play level opens its level", _small_font, COLOR_TEXT_DIM))
	_practice_macro_grid = GridContainer.new()
	_practice_macro_grid.columns = 1
	_practice_macro_grid.add_constant_override("hseparation", 10)
	_practice_macro_grid.add_constant_override("vseparation", 8)
	_practice_macro_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_macro_slot_status_labels = [null]
	_practice_macro_slot_play_buttons = [null]
	_practice_macro_slot_load_buttons = [null]
	_practice_macro_slot_delete_buttons = [null]
	_practice_macro_slot_edit_buttons = [null]
	_practice_macro_slot_cards = [null]
	for i in range(1, _practice_macro_slot_count + 1):
		var mcard: = _build_practice_macro_slot_card(i)
		_practice_macro_slot_cards.append(mcard)
		_practice_macro_grid.add_child(mcard)
	slots_tab.add_child(_practice_macro_grid)
	for i in range(1, _practice_macro_slot_count + 1):
		_refresh_practice_macro_slot_ui(i)
	tabs.finish()


var _frame_info_button: Button = null

func _on_open_input_list_pressed() -> void:
	var studio = _tas_studio()
	if studio != null:
		studio.toggle_window()


func _on_toggle_frame_info_pressed() -> void:
	var studio = _tas_studio()
	if studio == null:
		return
	var value = not studio.info_visible()
	studio.set_info_visible(value)
	_frame_info_button.text = "ℹ Frame info: ON" if value else "ℹ Frame info: OFF"
	_style_button(_frame_info_button, COLOR_PINK if value else COLOR_BLUE)
