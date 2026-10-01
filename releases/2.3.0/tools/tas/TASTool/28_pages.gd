extends "user://mod/tools/tas/TASTool/27_timeline.gd"

# Tools page (speed, frame stepping, buffered inputs, jumpzone, overlays toggles).
# Built by _build_menu_window; only exists when Macro Bot is installed.
func _build_tools_page(playback_page: VBoxContainer) -> void:
	# See _open_card()'s comment. playback_root always points at the page's
	# true top-level container; playback_page gets reassigned to whichever
	# card is currently "open" so every existing add_child() call below keeps
	# working completely unchanged, landing in a card instead of loose in the
	# page once Claude Experimental Mode is active.
	var playback_root: = playback_page

	# FRAME RATE LIMIT (2026-09-01, added directly per the user's own
	# request -- see FPS_LIMIT_SETTINGS_PATH's big comment above for why:
	# OPEN INVESTIGATION NOTES item 1 has pointed at unstable render frame
	# timing as a likely contributor to real Divergence Diagnostics
	# residuals, and testing that theory needed an in-game way to cap the
	# frame rate that didn't exist until now). Same +/-/label pattern as
	# Perfect Jumpzone's interval/hold controls below.
	playback_page = _open_card(playback_root, "Frame Rate")
	var fps_limit_row: = HBoxContainer.new()
	fps_limit_row.add_constant_override("separation", 10)
	fps_limit_row.add_child(_make_label("Frame Rate Limit:", _body_font, COLOR_TEXT_DIM))
	var fps_limit_minus: = _make_button("−", COLOR_BLUE, 54)
	fps_limit_minus.hint_tooltip = "Lower the render FPS limit."
	fps_limit_minus.connect("pressed", self, "_on_fps_limit_delta_pressed", [-FPS_LIMIT_STEP])
	fps_limit_row.add_child(fps_limit_minus)
	_fps_limit_label = _make_label(("%d FPS" % fps_limit) if fps_limit > 0 else "Uncapped", _header_font, COLOR_WHITE)
	_fps_limit_label.rect_min_size = Vector2(110, 0)
	_fps_limit_label.align = Label.ALIGN_CENTER
	_fps_limit_label.valign = Label.VALIGN_CENTER
	fps_limit_row.add_child(_fps_limit_label)
	var fps_limit_plus: = _make_button("+", COLOR_BLUE, 54)
	fps_limit_plus.hint_tooltip = "Raise the render FPS limit. 0 is uncapped."
	fps_limit_plus.connect("pressed", self, "_on_fps_limit_delta_pressed", [FPS_LIMIT_STEP])
	fps_limit_row.add_child(fps_limit_plus)
	playback_page.add_child(fps_limit_row)

	playback_page = _open_card(playback_root, "Visual Debug")
	if playback_page != playback_root:
		playback_page.get_parent().set_meta("workspace_developer", true)
	var visual_debug_row := HBoxContainer.new()
	visual_debug_row.add_constant_override("separation", 10)
	_hitbox_viewer_button = _make_button("◫ Hitbox Viewer: OFF", COLOR_BLUE, 250)
	_hitbox_viewer_button.hint_tooltip = "Show selected collision shapes."
	_hitbox_viewer_button.connect("pressed", self, "_on_toggle_hitbox_viewer_pressed")
	visual_debug_row.add_child(_hitbox_viewer_button)
	_trajectory_preview_button = _make_button("⌁ Trajectory Preview: OFF", COLOR_BLUE, 280)
	_trajectory_preview_button.hint_tooltip = "Preview the current ballistic path."
	_trajectory_preview_button.connect("pressed", self, "_on_toggle_trajectory_preview_pressed")
	visual_debug_row.add_child(_trajectory_preview_button)
	playback_page.add_child(visual_debug_row)
	_hitbox_category_row = HBoxContainer.new()
	_hitbox_category_row.add_constant_override("separation", 7)
	_hitbox_category_row.visible = _hitbox_viewer_enabled
	_hitbox_category_row.add_child(_make_label("Show:", _small_font, COLOR_TEXT_DIM))
	for entry in HITBOX_CATEGORIES:
		var category: String = entry[0]
		var category_button := _make_small_button(entry[1], COLOR_BLUE, 92)
		category_button.toggle_mode = true
		category_button.pressed = bool(_hitbox_categories.get(category, false))
		category_button.hint_tooltip = entry[2]
		category_button.connect("toggled", self, "_on_hitbox_category_toggled", [category])
		_hitbox_category_buttons[category] = category_button
		_hitbox_category_row.add_child(category_button)
	playback_page.add_child(_hitbox_category_row)
	_refresh_hitbox_category_ui()

	# INPUT DISPLAY (Phase 1.2) -- shows recorded/live input state in a small
	# overlay (TASInputDisplay.gd). Compact by default; Detailed adds a
	# LIVE/REPLAY tag, and Frame Holds adds a per-action held-tick counter.
	playback_page = _open_card(playback_root, "Input Display")
	var input_display_row: = HBoxContainer.new()
	input_display_row.add_constant_override("separation", 10)
	_input_display_button = _make_button("⌨ Input Display: OFF", COLOR_BLUE, 250)
	_input_display_button.hint_tooltip = "Show a small overlay of recorded/live input state."
	_input_display_button.connect("pressed", self, "_on_toggle_input_display_pressed")
	input_display_row.add_child(_input_display_button)
	_input_display_detailed_button = _make_small_button("Compact", COLOR_BLUE, 90)
	_input_display_detailed_button.hint_tooltip = "Toggle between a compact and a detailed (LIVE/REPLAY tag) overlay."
	_input_display_detailed_button.connect("pressed", self, "_on_toggle_input_display_detailed_pressed")
	_input_display_detailed_button.visible = _input_display_enabled
	input_display_row.add_child(_input_display_detailed_button)
	_input_display_hold_frames_button = _make_small_button("Frame Holds: OFF", COLOR_BLUE, 130)
	_input_display_hold_frames_button.hint_tooltip = "Show how many ticks each held input has been down."
	_input_display_hold_frames_button.connect("pressed", self, "_on_toggle_input_display_hold_frames_pressed")
	_input_display_hold_frames_button.visible = _input_display_enabled
	input_display_row.add_child(_input_display_hold_frames_button)
	playback_page.add_child(input_display_row)

	playback_page = _open_card(playback_root, "Playback Speed")
	var playback_row: = HBoxContainer.new()
	playback_row.add_constant_override("separation", 10)
	_play_stop_button = _make_button("■ STOP", COLOR_BLUE, 160)
	_play_stop_button.connect("pressed", self, "_toggle_pause")
	playback_row.add_child(_play_stop_button)
	var slower_btn: = _make_button("−", COLOR_BLUE, 54)
	slower_btn.connect("pressed", self, "_adjust_time_scale", [-TIME_SCALE_STEP])
	playback_row.add_child(slower_btn)
	_speed_label = _make_label("1.00x", _header_font, COLOR_WHITE)
	_speed_label.rect_min_size = Vector2(110, 0)
	_speed_label.align = Label.ALIGN_CENTER
	_speed_label.valign = Label.VALIGN_CENTER
	playback_row.add_child(_speed_label)
	var faster_btn: = _make_button("+", COLOR_BLUE, 54)
	faster_btn.connect("pressed", self, "_adjust_time_scale", [TIME_SCALE_STEP])
	playback_row.add_child(faster_btn)
	var reset_btn: = _make_button("Reset", COLOR_BLUE, 110)
	reset_btn.connect("pressed", self, "_on_reset_speed_pressed")
	playback_row.add_child(reset_btn)
	playback_page.add_child(playback_row)

	playback_page = _open_card(playback_root, "Frame Stepping")
	var step_row: = HBoxContainer.new()
	step_row.add_constant_override("separation", 10)
	_frame_step_checkbox = CheckBox.new()
	_frame_step_checkbox.text = "Frame-Step Mode"
	_frame_step_checkbox.pressed = enable_frame_step
	if _body_font != null:
		_frame_step_checkbox.add_font_override("font", _body_font)
	_frame_step_checkbox.add_color_override("font_color", _theme_text(COLOR_TEXT_DIM))
	_frame_step_checkbox.focus_mode = Control.FOCUS_NONE
	_frame_step_checkbox.connect("toggled", self, "_on_enable_frame_step_toggled")
	_frame_step_checkbox.hint_tooltip = "Pause physics and advance it manually."
	step_row.add_child(_frame_step_checkbox)
	_step_button = _make_button("Step ▸", COLOR_BLUE, 110)
	_step_button.disabled = not enable_frame_step
	_step_button.connect("pressed", self, "_request_frame_step")
	_step_button.hint_tooltip = "Advance the configured number of physics frames."
	step_row.add_child(_step_button)
	var step_config_btn: = _make_button("Configure", COLOR_BLUE, 140)
	step_config_btn.connect("pressed", self, "_on_toggle_step_config_pressed")
	step_row.add_child(step_config_btn)
	playback_page.add_child(step_row)

	_step_config_row = HBoxContainer.new()
	_step_config_row.add_constant_override("separation", 10)
	_step_config_row.visible = false
	_step_config_row.add_child(_make_label("Steps per press:", _body_font, COLOR_TEXT_DIM))
	var step_minus: = _make_button("−", COLOR_BLUE, 54)
	step_minus.connect("pressed", self, "_on_step_count_delta_pressed", [-1])
	_step_config_row.add_child(step_minus)
	_step_count_label = _make_label("%d" % frame_step_count, _header_font, COLOR_WHITE)
	_step_count_label.rect_min_size = Vector2(60, 0)
	_step_count_label.align = Label.ALIGN_CENTER
	_step_config_row.add_child(_step_count_label)
	var step_plus: = _make_button("+", COLOR_BLUE, 54)
	step_plus.connect("pressed", self, "_on_step_count_delta_pressed", [1])
	_step_config_row.add_child(step_plus)
	playback_page.add_child(_step_config_row)

	var buffered_label := _make_label("BUFFERED INPUTS", _small_font, COLOR_TEXT_DIM)
	buffered_label.hint_tooltip = "Armed actions stay held during the next frame step."
	playback_page.add_child(buffered_label)
	var buffer_row: = HBoxContainer.new()
	buffer_row.add_constant_override("separation", 8)
	for entry in BUFFERABLE_ACTIONS:
		var label: String = entry[0]
		var action: String = entry[1]
		var buf_btn: = _make_button(label, COLOR_BLUE, 0)
		buf_btn.hint_tooltip = "Hold %s during the next frame step." % label.capitalize()
		buf_btn.connect("pressed", self, "_on_toggle_buffered_action_pressed", [action])
		_buffer_action_buttons[action] = buf_btn
		buffer_row.add_child(buf_btn)
	playback_page.add_child(buffer_row)

	# PERFECT JUMPZONE -- folded into the same "Tools" page as the speed/
	# frame-step controls above (see the comment on playback_page's creation).
	playback_page = _open_card(playback_root, "Perfect Jumpzone")
	var jumpzone_page: = playback_page
	jumpzone_page.add_child(HSeparator.new())
	var jumpzone_row: = HBoxContainer.new()
	jumpzone_row.add_constant_override("separation", 10)
	_jumpzone_button = _make_button("⤒ Perfect Jumpzone: OFF", COLOR_BLUE, 300)
	_jumpzone_button.hint_tooltip = "Repeat Jump using the configured rhythm."
	_jumpzone_button.connect("pressed", self, "_on_toggle_jumpzone_pressed")
	jumpzone_row.add_child(_jumpzone_button)
	var jumpzone_config_btn: = _make_button("Configure", COLOR_BLUE, 140)
	jumpzone_config_btn.connect("pressed", self, "_on_toggle_jumpzone_config_pressed")
	jumpzone_row.add_child(jumpzone_config_btn)
	jumpzone_page.add_child(jumpzone_row)

	_jumpzone_config_row = VBoxContainer.new()
	_jumpzone_config_row.add_constant_override("separation", 8)
	_jumpzone_config_row.visible = false

	var jz_interval_row: = HBoxContainer.new()
	jz_interval_row.add_constant_override("separation", 10)
	jz_interval_row.add_child(_make_label("Interval:", _body_font, COLOR_TEXT_DIM))
	var jz_interval_minus: = _make_button("−", COLOR_BLUE, 54)
	jz_interval_minus.connect("pressed", self, "_on_jumpzone_interval_delta_pressed", [-JUMPZONE_TIMING_STEP_MS])
	jz_interval_row.add_child(jz_interval_minus)
	_jumpzone_interval_label = _make_label("%.0fms" % jumpzone_interval_ms, _header_font, COLOR_WHITE)
	_jumpzone_interval_label.rect_min_size = Vector2(90, 0)
	_jumpzone_interval_label.align = Label.ALIGN_CENTER
	jz_interval_row.add_child(_jumpzone_interval_label)
	var jz_interval_plus: = _make_button("+", COLOR_BLUE, 54)
	jz_interval_plus.connect("pressed", self, "_on_jumpzone_interval_delta_pressed", [JUMPZONE_TIMING_STEP_MS])
	jz_interval_row.add_child(jz_interval_plus)
	_jumpzone_config_row.add_child(jz_interval_row)

	var jz_hold_row: = HBoxContainer.new()
	jz_hold_row.add_constant_override("separation", 10)
	jz_hold_row.add_child(_make_label("Hold time:", _body_font, COLOR_TEXT_DIM))
	var jz_hold_minus: = _make_button("−", COLOR_BLUE, 54)
	jz_hold_minus.connect("pressed", self, "_on_jumpzone_hold_delta_pressed", [-JUMPZONE_TIMING_STEP_MS])
	jz_hold_row.add_child(jz_hold_minus)
	_jumpzone_hold_label = _make_label("%.0fms" % jumpzone_hold_ms, _header_font, COLOR_WHITE)
	_jumpzone_hold_label.rect_min_size = Vector2(90, 0)
	_jumpzone_hold_label.align = Label.ALIGN_CENTER
	jz_hold_row.add_child(_jumpzone_hold_label)
	var jz_hold_plus: = _make_button("+", COLOR_BLUE, 54)
	jz_hold_plus.connect("pressed", self, "_on_jumpzone_hold_delta_pressed", [JUMPZONE_TIMING_STEP_MS])
	jz_hold_row.add_child(jz_hold_plus)
	_jumpzone_config_row.add_child(jz_hold_row)

	jumpzone_page.add_child(_jumpzone_config_row)

# Macro Bot page (mode, checkpoints, playback, slots).
func _build_macro_bot_page(practice_page: VBoxContainer) -> void:
	var practice_root: = practice_page

	practice_page = _open_card(practice_root, "Macro Bot Mode")
	var practice_row: = HBoxContainer.new()
	practice_row.add_constant_override("separation", 10)
	_practice_toggle_button = _make_button("▶ Start Macro Bot Mode", COLOR_BLUE, 300)
	_practice_toggle_button.hint_tooltip = "Record a run in checkpointed segments."
	_practice_toggle_button.connect("pressed", self, "_on_toggle_practice_pressed")
	practice_row.add_child(_practice_toggle_button)
	_practice_auto_respawn_button = _make_button("⟲ Auto-Respawn to Checkpoint: ON", COLOR_PINK, 320)
	_practice_auto_respawn_button.hint_tooltip = "Retry only the current segment after dying."
	_practice_auto_respawn_button.connect("pressed", self, "_on_toggle_practice_auto_respawn_pressed")
	practice_row.add_child(_practice_auto_respawn_button)
	practice_page.add_child(practice_row)

	var practice_auto_activate_row: = HBoxContainer.new()
	practice_auto_activate_row.add_constant_override("separation", 10)
	_practice_auto_activate_button = _make_button("Auto-Activate on Level Entry: OFF", COLOR_BLUE, 340)
	_practice_auto_activate_button.hint_tooltip = "Start recording when the player becomes controllable."
	_practice_auto_activate_button.connect("pressed", self, "_on_toggle_practice_auto_activate_pressed")
	practice_auto_activate_row.add_child(_practice_auto_activate_button)
	practice_page.add_child(practice_auto_activate_row)

	# Debug Tools already has its own inline "DEBUG TOOLS" heading and its own
	# whole-section visibility toggle (_debug_mode_enabled) -- placed back at
	# practice_root directly rather than inside a card so its visibility
	# isn't tangled up with a card that would otherwise stay visible (empty)
	# around it.
	practice_page = practice_root
	_debug_tools_container = VBoxContainer.new()
	_debug_tools_container.add_constant_override("separation", 4)
	_debug_tools_container.visible = _debug_mode_enabled
	practice_page.add_child(_debug_tools_container)
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

	# Phase 0.1 -- Replay Determinism Check. Live readout, updated in
	# _update_overlay() while Play Macro is running -- see
	# _advance_replay_determinism_check() for where the numbers come from.
	_stop_on_desync_button = _make_button("Stop on Desync: OFF", COLOR_BLUE, 300)
	_stop_on_desync_button.hint_tooltip = "Automatically stop Play Macro the first time replay state diverges from the recorded run."
	_stop_on_desync_button.connect("pressed", self, "_on_toggle_stop_on_desync_pressed")
	_debug_tools_container.add_child(_stop_on_desync_button)
	_replay_check_status_label = _make_label("Replay Accuracy: --  |  First Desync: --  |  Largest Drift: --", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_replay_check_status_label)

	# Phase 0.2 -- Replay Self-Test. Repeats Play Macro N times and reports
	# PASS/FAIL per run using the Replay Determinism Check above -- see
	# _start_replay_self_test() / _on_replay_self_test_run_finished().
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

	practice_page = _open_card(practice_root, "Checkpoints")
	_practice_status_label = _make_label("0 checkpoint(s) placed", _body_font, COLOR_TEXT_DIM)
	practice_page.add_child(_practice_status_label)

	var practice_action_row: = HBoxContainer.new()
	practice_action_row.add_constant_override("separation", 10)
	_practice_place_button = _make_button("Place Checkpoint", COLOR_BLUE, 220)
	_practice_place_button.hint_tooltip = "Commit the current segment and start the next one."
	_practice_place_button.disabled = true
	_practice_place_button.connect("pressed", self, "_on_place_practice_checkpoint_pressed")
	practice_action_row.add_child(_practice_place_button)
	_practice_undo_button = _make_button("↩ Undo Last", COLOR_BLUE, 170)
	_practice_undo_button.hint_tooltip = "Remove the most recent checkpoint and segment. Shortcut: " + _keybinds.caption("checkpoint_undo")
	_practice_undo_button.disabled = true
	_practice_undo_button.connect("pressed", self, "_on_undo_practice_checkpoint_pressed")
	practice_action_row.add_child(_practice_undo_button)
	_practice_clear_button = _make_button("✕ Clear", COLOR_PINK_DARK, 130)
	_practice_clear_button.hint_tooltip = "Clear the current unsaved Macro Bot run."
	_practice_clear_button.disabled = true
	_practice_clear_button.connect("pressed", self, "_on_clear_practice_pressed")
	practice_action_row.add_child(_practice_clear_button)
	practice_page.add_child(practice_action_row)

	practice_page = _open_card(practice_root, "Macro Playback")
	var practice_play_row: = HBoxContainer.new()
	practice_play_row.add_constant_override("separation", 10)
	_practice_play_button = _make_button("▶ Play Macro (stitched)", COLOR_BLUE, 260)
	_practice_play_button.hint_tooltip = "Play the current checkpointed macro."
	_practice_play_button.disabled = true
	_practice_play_button.connect("pressed", self, "_on_play_practice_macro_pressed")
	practice_play_row.add_child(_practice_play_button)
	var edit_current_button := _make_button("▤ Edit Current Timeline", COLOR_PURPLE, 250)
	edit_current_button.hint_tooltip = "Open the detailed frame timeline."
	edit_current_button.connect("pressed", self, "_on_edit_current_practice_macro_pressed")
	practice_play_row.add_child(edit_current_button)
	practice_page.add_child(practice_play_row)
	var polish_row := HBoxContainer.new()
	polish_row.add_constant_override("separation", 10)
	_visual_seam_polish_button = _make_button("◇ Visual Seam Polish: OFF", COLOR_BLUE, 300)
	_visual_seam_polish_button.hint_tooltip = "Smooth render-only checkpoint corrections. Use safe checkpoint areas."
	_visual_seam_polish_button.connect("pressed", self, "_on_toggle_visual_seam_polish_pressed")
	polish_row.add_child(_visual_seam_polish_button)
	_sync_moving_objects_button = _make_button("↻ Moving Object Sync: OFF", COLOR_BLUE, 300)
	_sync_moving_objects_button.hint_tooltip = "Capture moving platforms/hazards at checkpoints for local playback."
	_sync_moving_objects_button.connect("pressed", self, "_on_toggle_sync_moving_objects_pressed")
	polish_row.add_child(_sync_moving_objects_button)
	practice_page.add_child(polish_row)

	practice_page = _open_card(practice_root, "Macro Slots")
	var slots_heading := HBoxContainer.new()
	slots_heading.add_child(_make_label("MACRO SLOTS", _body_font, COLOR_TEXT_DIM))
	var slots_heading_spacer := Control.new()
	slots_heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_heading.add_child(slots_heading_spacer)
	var add_slot_button := _make_button("＋ CREATE MACRO SLOT", COLOR_PLAY_GREEN, 230)
	add_slot_button.hint_tooltip = "Add another persistent macro slot."
	add_slot_button.connect("pressed", self, "_on_add_practice_macro_slot_pressed")
	slots_heading.add_child(add_slot_button)
	var remove_slot_button := _make_button("− REMOVE LAST EMPTY", COLOR_BLUE, 220)
	remove_slot_button.hint_tooltip = "Remove the final slot if it is empty."
	remove_slot_button.connect("pressed", self, "_on_remove_last_practice_macro_slot_pressed")
	slots_heading.add_child(remove_slot_button)
	practice_page.add_child(slots_heading)
	_practice_macro_grid = GridContainer.new()
	_practice_macro_grid.columns = 3
	_practice_macro_grid.add_constant_override("hseparation", 10)
	_practice_macro_grid.add_constant_override("vseparation", 10)
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
	practice_page.add_child(_practice_macro_grid)
	for i in range(1, _practice_macro_slot_count + 1):
		_refresh_practice_macro_slot_ui(i)
