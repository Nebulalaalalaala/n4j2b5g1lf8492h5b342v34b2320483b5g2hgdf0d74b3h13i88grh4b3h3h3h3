extends "user://mod/core/TASTool/09_ui_kit.gd"

func _on_updater_check_now_pressed() -> void:
	if _updater != null and is_instance_valid(_updater):
		_updater.call("check_now", true)


func _on_updater_status_changed(status: String, detail: String) -> void:
	if _updater_status_label != null:
		_updater_status_label.text = status + " — " + detail
	_log_action("Updater: " + status + " — " + detail, null)


func _on_updater_latest_version_changed(version: String) -> void:
	if _updater_latest_label != null:
		_updater_latest_label.text = "LATEST  " + version


func _on_updater_update_available(manifest: Dictionary) -> void:
	_pending_update_manifest = manifest.duplicate(true)
	if _updater_install_button != null and is_instance_valid(_updater_install_button):
		_updater_install_button.disabled = false
	var version := str(manifest.get("version", ""))
	# Automatic checks ask on the first launches that find this version; Check Now always asks.
	if not bool(_updater.get("last_check_manual")):
		if str(SavedSettings.get_value(SETTING_UPDATE_PROMPT_VERSION, "")) != version:
			SavedSettings.set_value(SETTING_UPDATE_PROMPT_VERSION, version)
			SavedSettings.set_value(SETTING_UPDATE_PROMPT_COUNT, 0)
			SavedSettings.set_value(SETTING_UPDATE_PROMPT_MUTED, false)
		var shown := int(SavedSettings.get_value(SETTING_UPDATE_PROMPT_COUNT, 0))
		if bool(SavedSettings.get_value(SETTING_UPDATE_PROMPT_MUTED, false)) or shown >= UPDATE_PROMPT_LAUNCHES:
			return
		SavedSettings.set_value(SETTING_UPDATE_PROMPT_COUNT, shown + 1)
	var changelog := str(manifest.get("changelog", ""))
	var message := "Goobplayability %s is ready to install." % version
	if not changelog.empty():
		message += "\n\n" + changelog
	message += "\n\nYou can also install it later from Settings → Client Tools → Updates."
	_show_update_choice_popup("UPDATE READY", message)


func _on_updater_install_confirmed() -> void:
	_close_tool_popup()
	if _updater != null and is_instance_valid(_updater):
		_updater.call("install_available_update")


func _on_updater_install_pressed() -> void:
	if not _pending_update_manifest.empty():
		_on_updater_install_confirmed()


func _on_updater_dont_remind() -> void:
	SavedSettings.set_value(SETTING_UPDATE_PROMPT_MUTED, true)
	_close_tool_popup()


func _on_updater_update_installed(version: String) -> void:
	_pending_update_manifest = {}
	if _updater_install_button != null and is_instance_valid(_updater_install_button):
		_updater_install_button.disabled = true
	_show_responsive_popup("UPDATE INSTALLED", "Goobplayability %s is installed.\n\nRestart Goober Dash to load the new scripts. The previous version remains available through Settings → Client Tools → Roll Back." % version)


func _on_updater_rollback_changed(available: bool) -> void:
	if _updater_rollback_button != null:
		_updater_rollback_button.disabled = not available


func _on_updater_rollback_pressed() -> void:
	_show_rollback_choice_popup()


func _on_updater_rollback_confirmed() -> void:
	_close_tool_popup()
	if _updater != null and is_instance_valid(_updater) and bool(_updater.call("rollback_last_update")):
		_show_responsive_popup("ROLLBACK READY", "The previous Goobplayability scripts were restored. Restart Goober Dash to load them.")


func _update_practice_live_airborne_clock() -> void:
	# During playback the reconstructed integrator below owns this counter;
	# updating it here as well would count every replay tick twice.
	if _practice_playback:
		return
	var p: = _get_local_player()
	if p == null or not p.alive or not p.body_enabled:
		_practice_playback_air_hold_ticks = 0
		_practice_playback_air_hold_dir = 0.0
		_practice_live_airborne_player_id = 0
		return
	var player_id: = p.get_instance_id()
	if player_id != _practice_live_airborne_player_id:
		_practice_live_airborne_player_id = player_id
		_practice_playback_air_hold_ticks = 0
	if p.stick_to_ground_timer > 0.0:
		_practice_playback_air_hold_ticks = 0
	else:
		_practice_playback_air_hold_ticks += 1


func _snapshot_player(p: WPPlayer) -> Dictionary:
	var g: = _find_game()
	var snap: = {
		"position": p.position,
		"linear_velocity": p.linear_velocity,
		"body_enabled": p.body_enabled,
		"alive": p.alive,
		"dash_cooldown": p.dash_cooldown,
		"dash_timer": p.dash_timer,
		"coyote_timer": p.coyote_timer,
		"squish_counter": p.squish_counter,
		"wallslide_counter": p.wallslide_counter,
		"wallslide_dir": p.wallslide_dir,
		"stun_timer": p.stun_timer,
		"is_inside_one_way_platform": p.is_inside_one_way_platform,
		"dead_counter": p.dead_counter,
		"last_checkpoint": p.last_checkpoint,
		"last_checkpoint_anchor": p.last_checkpoint_anchor,
		"stick_to_ground_timer": p.stick_to_ground_timer,
		"facing_dir": p.facing_dir,
		"ground_normal": p.ground_normal,
		"ground_tangent_speed": p.ground_tangent_speed,
		# This is the continuously observed LIVE airborne clock maintained by
		# _update_practice_live_airborne_clock(), not merely the playback
		# integrator's last value. That distinction is what makes a checkpoint
		# recorded partway through a fall restore the correct native ramp phase.
		"practice_playback_air_hold_ticks": _practice_playback_air_hold_ticks,
		"practice_playback_air_hold_dir": _practice_playback_air_hold_dir,
	}
	if g != null and g.wp_game_data != null:
		snap["play_time"] = g.wp_game_data.play_time
	if _sync_moving_objects_enabled:
		snap["moving_world_state"] = _snapshot_moving_world_state(g)
		if g != null and g.level != null and g.wp_game_data != null:
			snap["moving_world_time"] = g.wp_game_data.play_time + _moving_phase_shift(g)
			snap["moving_world_version"] = 2
	return snap


func _show_update_choice_popup(title: String, message: String) -> void:
	_show_responsive_popup(title, message, "INSTALL NOW", "_on_updater_install_confirmed", "NOT NOW", "DON'T REMIND ME", "_on_updater_dont_remind")


func _show_rollback_choice_popup() -> void:
	_show_responsive_popup("ROLL BACK GOOBPLAYABILITY?", "This restores the scripts backed up immediately before the last updater installation.\n\nNo macros, settings, diagnostics, or unrelated Goober Dash files are changed. Restart the game afterward.", "RESTORE BACKUP", "_on_updater_rollback_confirmed", "CANCEL")


# Bridge for ReplayHub.gd -- lets it stamp uploads/exports with the
# installed version without duplicating the const.
func _get_goobplayability_version() -> String:
	return GOOBPLAYABILITY_VERSION


func _update_macro_playback_timer() -> void:
	# Late-render presentation only: never modify server/race clocks or finish data.
	if _macro_editor_preview_active:
		return
	for entry in _macro_playback_timer_pills:
		if not is_instance_valid(entry.node):
			continue
		if _practice_playback:
			entry.node.set_time(float(_practice_playback_index) / 60.0)
		else:
			entry.node._update_label()
	if not _practice_playback:
		_macro_playback_timer_pills.clear()


func _update_mouse_capture() -> void:
	var editor_open: bool = _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("is_open") and bool(_macro_editor.call("is_open"))
	var want_visible: = ((_menu_open or (_log_open and _debug_mode_enabled)) and _tas_gui_enabled and not _overlay_hidden) or editor_open
	if want_visible:
		if _prev_mouse_mode == -1:
			_prev_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _prev_mouse_mode != -1:
			Input.mouse_mode = _prev_mouse_mode
			_prev_mouse_mode = -1


func _update_overlay() -> void:
	if _tab_button == null:
		return
	if not _tas_gui_enabled:
		return

	# F1-hidden: the whole overlay CanvasLayer is already invisible (and
	# therefore free to render), so there's nothing on screen for any of
	# the below to usefully update -- skip the work entirely. Everything
	# picks back up correctly the moment it's shown again, since every
	# update below is itself guarded by an actual-value comparison rather
	# than assuming what state the UI was last left in.
	if _overlay_hidden:
		return

	if not enabled:
		# Fully disabled means fully out of the way -- hide the tab bars
		# themselves too, not just the dropdown panels, so there's nothing
		# left sitting over the game (or another menu) blocking clicks.
		_tab_row.visible = false
		_log_tab_row.visible = false
		_menu_panel.visible = false
		_toast_pill.modulate.a = 0.0
		return

	_tab_row.visible = true
	_log_tab_row.visible = _debug_mode_enabled
	if not _debug_mode_enabled:
		_log_panel.visible = false

	# The diagnostic is useful while the panel is open, but rewriting a Label
	# every rendered frame invalidates the surrounding Container layout. On an
	# uncapped main menu that can happen hundreds of times per second even while
	# the whole panel is closed. Sample it at 4 Hz, only while visible, and only
	# assign when its text actually changed; this measures FPS without lowering
	# or capping it.
	if _diag_label != null and _debug_mode_enabled and _menu_open:
		var now_msec: = OS.get_ticks_msec()
		if now_msec >= _ui_next_diag_refresh_msec:
			_ui_next_diag_refresh_msec = now_msec + DIAGNOSTIC_UI_REFRESH_MSEC
			var diag_text: = "FPS %d | Nodes %d | Log %d | Seg %d | Play %d/%d" % [Engine.get_frames_per_second(), get_tree().get_node_count(), _log_entries.size(), _practice_current_segment.size(), _practice_playback_index, _practice_playback_frames.size()]
			if _ui_last_diag_text != diag_text:
				_ui_last_diag_text = diag_text
				_diag_label.text = diag_text

	# Every .text/.disabled/stylebox write below is gated on the displayed
	# value actually having changed -- reassigning them unconditionally
	# every idle frame (60/sec) was the real source of the lag reported
	# once the menu grew: Label/Button property writes invalidate that
	# Control's layout and force a container re-sort even when the new
	# value is identical to the old one, and that cost scales with how
	# many Controls are now in the tree.
	var tab_text: = _tab_text()
	if _ui_last_tab_text != tab_text:
		_ui_last_tab_text = tab_text
		_tab_button.text = tab_text
	var log_tab_text: = _log_tab_text()
	if _ui_last_log_tab_text != log_tab_text:
		_ui_last_log_tab_text = log_tab_text
		_log_tab_button.text = log_tab_text

	if _tool_restricted():
		_menu_panel.visible = _menu_open
		_inactive_label.visible = _workspace_menu == null or _section_tabs.current_tab < 3
		_inactive_label.text = "Gameplay actions need a local level. Saved macros and tool settings remain available."
		# Browsing saved macros/autoplay settings is safe anywhere. Their action
		# handlers retain the existing local-simulation checks.
		_section_tabs.visible = _workspace_menu != null
		if _claude_menu_nav_row != null:
			_claude_menu_nav_row.visible = false
		_toast_pill.modulate.a = 0.0
		return

	_menu_panel.visible = _menu_open
	_inactive_label.visible = false
	_section_tabs.visible = true
	if _claude_menu_nav_row != null:
		_claude_menu_nav_row.visible = _modern_theme_active() and _workspace_menu == null

	if _ui_last_paused != _is_paused:
		_ui_last_paused = _is_paused
		if _is_paused:
			_play_stop_button.text = "▶ PLAY"
			_style_button(_play_stop_button, COLOR_PINK)
		else:
			_play_stop_button.text = "■ STOP"
			_style_button(_play_stop_button, COLOR_BLUE)

	var speed: float = _saved_time_scale if _is_paused else Engine.time_scale
	var speed_text: = "%.2fx" % speed
	if _ui_last_speed_text != speed_text:
		_ui_last_speed_text = speed_text
		_speed_label.text = speed_text

	var step_disabled: = not enable_frame_step
	if _ui_last_step_disabled != step_disabled:
		_ui_last_step_disabled = step_disabled
		_step_button.disabled = step_disabled

	# Macro Bot Mode's live status line -- the underlying numbers are
	# updated every physics frame by _physics_process()/_advance_practice_
	# playback(), but the Label itself is only ever touched here, once per
	# idle frame, and only when the text actually changed.
	if _practice_status_label != null:
		var practice_text: String
		if _practice_playback:
			practice_text = "Playing back... (%d/%d frames)" % [_practice_playback_index, _practice_playback_frames.size()]
		elif _practice_active:
			practice_text = "%d checkpoint(s) -- segment: %d frame(s), %d death(s)" % [max(_practice_checkpoints.size() - 1, 0), _practice_current_segment.size(), _practice_deaths_this_segment]
		else:
			practice_text = "%d checkpoint(s) placed" % [max(_practice_checkpoints.size() - 1, 0)]
		if _ui_last_practice_status != practice_text:
			_ui_last_practice_status = practice_text
			_practice_status_label.text = practice_text

	# Phase 0.1 -- Replay Determinism Check's live readout. Same "recompute
	# every idle frame, only assign on change" pattern as the practice status
	# line just above; the underlying counters are updated every physics
	# tick by _advance_replay_determinism_check().
	if _replay_check_status_label != null and _debug_mode_enabled:
		var replay_check_text: String
		if _replay_check_compared_ticks <= 0:
			if _practice_playback and _replay_check_safe_ticks <= 0:
				replay_check_text = "Replay Accuracy: NO DATA  |  Record with Debug Mode enabled"
			else:
				replay_check_text = "Replay Accuracy: --  |  First Desync: --  |  Largest Drift: --"
		else:
			var accuracy: float = 100.0 * float(_replay_check_matched_ticks) / float(_replay_check_compared_ticks)
			var desync_text: String = ("tick %d · %s/%s" % [_replay_check_first_desync_tick, _replay_check_first_desync_category, _replay_check_first_desync_field]) if _replay_check_first_desync_tick >= 0 else "none"
			replay_check_text = "Replay Accuracy: %.1f%%  |  First Desync: %s  |  Largest Drift: %.3f units" % [accuracy, desync_text, _replay_check_largest_drift]
		if _ui_last_replay_check_status != replay_check_text:
			_ui_last_replay_check_status = replay_check_text
			_replay_check_status_label.text = replay_check_text

	if not _status_message.empty():
		_toast_pill.modulate.a = 1.0
		_toast_pill.get_meta("label").text = _status_message
	else:
		_toast_pill.modulate.a = 0.0
