extends "user://mod/tools/tas/TASTool/23_input_assists.gd"

# ----------------------------------------------------------------------
#  Macro Bot Mode hotkeys
# ----------------------------------------------------------------------
func _handle_macro_bot_hotkeys() -> void:
	var checkpoint_pressed: bool = _just_pressed(KEY_PLACE_CHECKPOINT)
	if checkpoint_pressed and _macro_hotkeys_allowed():
		_on_place_practice_checkpoint_pressed()
	if _just_pressed(KEY_U) and _macro_hotkeys_allowed():
		_on_undo_practice_checkpoint_pressed()


func _macro_hotkeys_allowed() -> bool:
	if not enabled or not _practice_active or _practice_playback or _macro_editor_preview_active or get_tree().paused:
		return false
	if _tool_restricted():
		return false
	if _autoplay_bot != null and is_instance_valid(_autoplay_bot) and bool(_autoplay_bot.call("is_active")):
		return false
	if _menu_window != null:
		var focus = _menu_window.get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return false
	var game := _find_game()
	var player := _get_local_player()
	return game != null and not game.is_game_over() and player != null and _player_ready_for_checkpoint(player) and _game_ready_for_practice_start()


func _apply_recorded_practice_frame_state(p: WPPlayer, state: Dictionary) -> bool:
	var corrected: = false
	# Autoplay stitches independently verified physics branches. The first frame
	# of each branch carries its exact moving-platform phase; restore only those
	# marked boundaries without touching the global race clocks below.
	if state.has("moving_world_state") or state.has("moving_world_time"):
		_restore_moving_world_state(state, true)
		corrected = true
	if state.has("position") and p.position.distance_to(state["position"]) > DIAG_POSITION_EPSILON:
		# Rendering follows the saved sample track, not this transient native
		# drift. Restarting a seam tween here slows the image on every correction.
		p.position = state["position"]
		if p.body != null:
			p.body.global_position = state["position"]
		corrected = true
	if state.has("linear_velocity") and (p.linear_velocity.distance_to(state["linear_velocity"]) > DIAG_VELOCITY_EPSILON or (p.body != null and p.body.linear_velocity.distance_to(state["linear_velocity"]) > DIAG_VELOCITY_EPSILON)):
		p.linear_velocity = state["linear_velocity"]
		if p.body != null:
			p.body.linear_velocity = state["linear_velocity"]
		corrected = true
	# The horizontal replay integrator runs later in this same callback. Seed
	# it from the authoritative beginning-of-tick velocity every time so it
	# cannot immediately overwrite a correction with its own stale estimate.
	if state.has("linear_velocity"):
		_practice_playback_computed_vx = state["linear_velocity"].x
	for field in PRACTICE_FRAME_RESYNC_SCALAR_FIELDS:
		if state.has(field) and p.get(field) != state[field]:
			p.set(field, state[field])
			corrected = true
	_restore_practice_ground_motion(p, state)
	if state.has("practice_playback_air_hold_ticks") and _practice_playback_air_hold_ticks != state["practice_playback_air_hold_ticks"]:
		_practice_playback_air_hold_ticks = state["practice_playback_air_hold_ticks"]
		corrected = true
	if state.has("practice_playback_air_hold_dir") and not is_equal_approx(_practice_playback_air_hold_dir, state["practice_playback_air_hold_dir"]):
		_practice_playback_air_hold_dir = state["practice_playback_air_hold_dir"]
		corrected = true
	# Never restore play_time/state_time/time_remaining here. They are global
	# race/server clocks, not player state. Reasserting the recorded values
	# made the visible clock oscillate and produced invalid native/LB replay
	# timestamps whenever a macro was started later in the same attempt.
	# The values remain in the frame state as read-only diagnostics.
	return corrected


func _recover_authoritative_playback_death(p: WPPlayer) -> bool:
	# Failed attempts are discarded when a segment is committed, so a dead
	# player in the middle of a stored segment can only be replay drift (most
	# commonly an old macro meeting a moving hazard at a different phase).  A
	# format-3 frame already contains the exact beginning-of-tick player state;
	# revive into that state instead of throwing the entire slot away.
	if _practice_playback_index < 0 or _practice_playback_index >= _practice_playback_frames.size():
		return false
	var frame = _practice_playback_frames[_practice_playback_index]
	if typeof(frame) != TYPE_DICTIONARY or not frame.has(PRACTICE_FRAME_STATE_KEY):
		return false
	var state = frame[PRACTICE_FRAME_STATE_KEY]
	if typeof(state) != TYPE_DICTIONARY or not state.has("position") or not state.has("linear_velocity"):
		return false
	var recovery: Dictionary = state.duplicate(true)
	recovery["alive"] = true
	recovery["body_enabled"] = true
	recovery["dead_counter"] = 0
	_restore_player(p, recovery)
	# _reset_object() is deliberately part of a real revive, but its native
	# implementation may rewrite velocity/timers. Reassert the recorded frame
	# after it, then make the three life gates explicit once more.
	_apply_recorded_practice_frame_state(p, state)
	p.alive = true
	p.body_enabled = true
	p.dead_counter = 0
	if p.body != null:
		p.body.enabled = true
		p.body.global_position = state["position"]
		p.body.linear_velocity = state["linear_velocity"]
	# _restore_player() snaps the render track to the revived (next-frame)
	# body. The post-physics sampler still owns the frame being displayed, so
	# let it initialize from that recorded frame instead of interpolating
	# backward from the recovery target.
	_reset_playback_visual_track()
	return true


func _arm_playback_settle(player: WPPlayer, snap: Dictionary) -> void:
	# State-backed playback has an exact first-tick state. Letting native
	# physics run neutral-input settling ticks changes position, contact and
	# dash availability before that input is consumed. Hand off immediately.
	if _practice_playback_index < _practice_playback_frames.size() and _practice_playback_frames[_practice_playback_index].has(PRACTICE_FRAME_STATE_KEY):
		_practice_playback_settling = false
		return
	# INSTRUMENTATION for the "just a wrong/inconsistent delay" theory: tags
	# the restore-drift watch this exact restore already armed (see
	# _arm_restore_drift_watch(), called from _restore_player() immediately
	# before this function runs every time -- checkpoint 0's own call site
	# and the boundary_idx>0 path both restore-then-arm-settle back to back,
	# so _restore_drift_watches.back() is always this restore's own watch
	# here, never some other one) with whether Playback Settle armed at all,
	# and -- once the hold actually ends, see the hold branch in
	# _advance_practice_playback() -- how many ticks it held for and whether
	# it gave up on the hard tick cap (PLAYBACK_SETTLE_MAX_TICKS) instead of
	# genuinely detecting a stable position. A settle that keeps hitting the
	# cap without ever reading "stable" IS an inconsistent, position-
	# dependent startup delay in every meaningful sense -- this is how we'd
	# actually see that, instead of guessing at it from the outside.
	if not _restore_drift_watches.empty():
		_restore_drift_watches.back()["settle_armed"] = _snapshot_is_at_rest(snap)
	if not _snapshot_is_at_rest(snap):
		_practice_playback_settling = false
		return
	_practice_playback_settling = true
	_practice_playback_settle_ticks_left = PLAYBACK_SETTLE_MAX_TICKS
	_practice_playback_settle_last_position = player.position


# A real hard restore is still required at playback start and for old macros
# which have no per-frame state. Reset the render-only history at the same
# instant so its next interpolation interval starts at the restored point,
# rather than blending from the previous segment's final rendered sample.
func _snap_playback_visual_track(player: WPPlayer) -> void:
	if not _practice_playback or player == null:
		return
	_practice_playback_visual_valid = true
	_practice_playback_visual_player_id = player.get_instance_id()
	_practice_playback_visual_previous = player.position
	_practice_playback_visual_current = player.position
	_practice_playback_visual_renderer = _find_player_renderer(player)
	_practice_playback_visual_camera = _find_playback_camera()
	_practice_playback_visual_sample_usec = OS.get_ticks_usec()


func _begin_visual_seam_blend(from_position: Vector2, to_position: Vector2) -> void:
	if not _practice_playback or not _visual_seam_polish_enabled:
		return
	var correction := from_position - to_position
	if correction.length() <= DIAG_POSITION_EPSILON:
		return
	if correction.length() > VISUAL_SEAM_MAX_DISTANCE:
		# A large correction should remain an honest snap; visually tweening a
		# goober through half the level would be worse than the seam and could
		# conceal a genuinely invalid segment.
		_visual_seam_filter_remaining = 0.0
		_visual_seam_output_valid = false
		return
	# Start the short low-pass window from the exact last displayed point. This
	# smooths the correction's direction/acceleration change without adding an
	# extra positional offset on top of the ordinary physics interpolation.
	_visual_seam_filter_position = _visual_seam_last_output if _visual_seam_output_valid else from_position
	_visual_seam_filter_remaining = VISUAL_SEAM_BLEND_SECONDS


# A checkpoint and the following segment's frame 0 are already identical in
# the saved macro. The remaining visible seam came from WHEN that identical
# state was written: the early playback callback corrects player/body state,
# then native physics advances it and the following tick corrects it again.
# Sampling that post-physics body made the render path alternate between the
# recorded point and the newly-drifted point -- a visible sawtooth even though
# gameplay itself was repaired each tick. Render format-3 macros from their
# authoritative recorded positions instead. This remains visual-only and one
# physics sample behind; legacy input-only macros retain the old body sample.
func _capture_playback_visual_sample() -> void:
	if not _practice_playback:
		return
	var player: = _get_local_player()
	if player == null:
		_reset_playback_visual_track()
		return
	var sampled_position: Vector2 = player.position
	var sampled_frame_index: int = _practice_playback_index - 1
	# Late physics callbacks can repeat without consuming a native replay tick.
	# Do not collapse the interpolation interval or restart its clock on repeats.
	if _practice_playback_visual_valid and player.get_instance_id() == _practice_playback_visual_player_id and sampled_frame_index == _practice_playback_visual_frame_index:
		return
	_practice_playback_visual_frame_index = sampled_frame_index
	if sampled_frame_index >= 0 and sampled_frame_index < _practice_playback_frames.size():
		var sampled_frame = _practice_playback_frames[sampled_frame_index]
		if typeof(sampled_frame) == TYPE_DICTIONARY and sampled_frame.has(PRACTICE_FRAME_STATE_KEY):
			var sampled_state = sampled_frame[PRACTICE_FRAME_STATE_KEY]
			if typeof(sampled_state) == TYPE_DICTIONARY:
				if sampled_state.has("position"):
					sampled_position = sampled_state["position"]
				# Native dash input and continuous movement are dispatched by two
				# different paths. Reassert the recorded facing after native physics
				# so a left dash cannot be rendered with the prior right-facing pose.
				# The saved state is BEFORE this frame's input, so its facing can
				# be stale. Held movement owns the new pose outside an active dash.
				var sampled_move: float = _practice_playback_movement_value(sampled_frame)
				if player.dash_timer > 0.0 and _practice_playback_dash_direction_valid:
					player.facing_dir = _practice_playback_dash_direction
				elif sampled_move != 0.0:
					player.facing_dir = sampled_move > 0.0
				var was_dash_held: bool = false
				if sampled_frame_index > 0:
					var previous_frame = _practice_playback_frames[sampled_frame_index - 1]
					if typeof(previous_frame) == TYPE_DICTIONARY:
						was_dash_held = bool(previous_frame.get(ACTION_DASH, false))
				if bool(sampled_frame.get(ACTION_DASH, false)) and not was_dash_held and sampled_frame.has(PRACTICE_DASH_DIRECTION_KEY):
					player.facing_dir = bool(sampled_frame[PRACTICE_DASH_DIRECTION_KEY])
	var player_id: int = player.get_instance_id()
	if not _practice_playback_visual_valid or player_id != _practice_playback_visual_player_id:
		_practice_playback_visual_valid = true
		_practice_playback_visual_player_id = player_id
		_practice_playback_visual_previous = sampled_position
		_practice_playback_visual_current = sampled_position
		_practice_playback_visual_renderer = _find_player_renderer(player)
		_practice_playback_visual_camera = _find_playback_camera()
		_practice_playback_visual_sample_usec = OS.get_ticks_usec()
		return
	_practice_playback_visual_previous = _practice_playback_visual_current
	_practice_playback_visual_current = sampled_position
	_practice_playback_visual_sample_usec = OS.get_ticks_usec()


func _find_playback_camera() -> Camera2D:
	var game: = _find_game()
	if game == null or game.get_parent() == null:
		return null
	return game.get_parent().get_node_or_null("Camera2D") as Camera2D


func _reset_playback_visual_track() -> void:
	_practice_playback_visual_frame_index = -2
	_practice_playback_visual_valid = false
	_practice_playback_visual_player_id = 0
	_practice_playback_visual_previous = Vector2.ZERO
	_practice_playback_visual_current = Vector2.ZERO
	_practice_playback_visual_renderer = null
	_practice_playback_visual_camera = null
	_practice_playback_visual_sample_usec = 0
	_visual_seam_filter_position = Vector2.ZERO
	_visual_seam_last_output = Vector2.ZERO
	_visual_seam_filter_remaining = 0.0
	_visual_seam_output_valid = false


func _finalize_practice_recording_at_finish(player: WPPlayer) -> void:
	if player == null or _practice_checkpoints.empty():
		return
	# Reaching the goal is the natural last checkpoint.  Commit the tail so a
	# user can Save immediately after dismissing the popup instead of losing
	# every frame since their last manually placed checkpoint.
	if not _practice_current_segment.empty():
		_practice_segments.append(_practice_current_segment.duplicate(true))
		_diag_live_committed.append(_diag_live_current.duplicate(true))
		var snap: = _snapshot_player(player)
		_practice_checkpoints.append(snap)
		_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
		_restyle_practice_markers()
	_practice_current_segment = []
	_diag_live_current = []
	_practice_deaths_this_segment = 0
	_practice_place_pending = false
	_practice_place_ready_stable_ticks = 0


func _restore_macro_recording_level_type(loaded_level, original_level_type) -> void:
	if loaded_level != null and is_instance_valid(loaded_level) and ("level_type" in loaded_level):
		loaded_level.set("level_type", original_level_type)


# Phase 0.1 -- Replay Determinism Check. Called once per playback tick
# (right after _diag_replay_log gets this tick's entry appended) so the
# Macro Bot tab can show a live accuracy/first-desync/largest-drift readout
# instead of only finding out after pressing Compare. Reuses the exact same
# per-field comparison _on_compare_diagnostics_pressed() does below, just
# incrementally, one newly-added tick at a time, instead of over the whole
# log at once.
func _advance_replay_determinism_check() -> void:
	var replay_index: = _diag_replay_log.size() - 1
	if replay_index < 0 or replay_index >= _replay_check_live_flat.size() or replay_index >= _replay_check_safe_ticks:
		return # outside what's safely aligned this run -- see _diag_coverage_prefix_ticks()
	var live_entry: Dictionary = _replay_check_live_flat[replay_index]
	var replay_entry: Dictionary = _diag_replay_log[replay_index]
	var tick_matched: = true
	var tick_drift: = 0.0
	var tick_first_field := ""
	for field in (DIAG_VECTOR_FIELDS + DIAG_SCALAR_FIELDS + DIAG_WORLD_FIELDS):
		if not live_entry.has(field) or not replay_entry.has(field):
			continue
		if field in DIAG_VECTOR_FIELDS:
			tick_drift = max(tick_drift, live_entry[field].distance_to(replay_entry[field]))
		if not _diag_field_matches(field, live_entry[field], replay_entry[field]):
			tick_matched = false
			if tick_first_field.empty():
				tick_first_field = field
	_replay_check_compared_ticks += 1
	if tick_matched:
		_replay_check_matched_ticks += 1
	elif _replay_check_first_desync_tick == -1:
		_replay_check_first_desync_tick = replay_index
		_replay_check_first_desync_field = tick_first_field
		_replay_check_first_desync_category = _determinism_field_category(tick_first_field)
	_replay_check_largest_drift = max(_replay_check_largest_drift, tick_drift)
	if not tick_matched and _replay_check_stop_on_desync:
		_log_action("Macro Bot Mode: stopped playback at tick %d -- Replay Determinism Check found a desync (Stop on Desync is ON)." % replay_index, null)
		_practice_playback = false
		Engine.time_scale = 1.0
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1


func _determinism_field_category(field: String) -> String:
	if field == "position":
		return "position"
	if field == "linear_velocity":
		return "velocity"
	if field in ["stick_to_ground_timer", "is_inside_one_way_platform", "coyote_timer"]:
		return "ground/contact"
	if field in ["dash_cooldown", "dash_timer", "facing_dir"]:
		return "dash/facing"
	if field in ["alive", "body_enabled", "dead_counter"]:
		return "life/body"
	if field == "world_fingerprint":
		return "moving world"
	return "player state"


func _practice_recorded_frame_count() -> int:
	var count := 0
	for segment in _practice_segments:
		count += segment.size()
	return count


# See _build_divergence_context_lines() -- how many ticks have elapsed
# since the most recent boundary in _practice_playback_checkpoint_at at or
# before `tick`, or -1 if that array is empty (e.g. Compare was pressed
# without a Play Macro run in this session, or checkpoint data has since
# been cleared).
func _ticks_since_last_playback_boundary(tick: int) -> int:
	if _practice_playback_checkpoint_at.empty():
		return -1
	var best: = -1
	for boundary in _practice_playback_checkpoint_at:
		if boundary <= tick and boundary > best:
			best = boundary
	if best == -1:
		return -1
	return tick - best


func _build_practice_playback_frames() -> void:
	_practice_playback_frames = []
	_practice_playback_checkpoint_at = [0]
	for seg in _practice_segments:
		for frame in seg:
			_practice_playback_frames.append(frame)
		_practice_playback_checkpoint_at.append(_practice_playback_frames.size())


func _practice_playback_uses_native_clock() -> bool:
	if _practice_playback_frames.empty():
		return false
	var first: Dictionary = _practice_playback_frames[0]
	var state = first.get(PRACTICE_FRAME_STATE_KEY, {})
	return typeof(state) == TYPE_DICTIONARY and bool(state.get("native_tick_clock", false))


func _finish_macro_continue() -> void:
	if _practice_continue_frame < 0:
		return
	var player = _get_local_player()
	var target = _practice_continue_frame
	var resume_automatically = _practice_continue_auto_resume
	_practice_continue_frame = -1
	_continue_resimulating = false
	if player == null or not player.alive or _find_game().is_game_over():
		_log_action("Continue From: choose a frame before death or the finish.",null)
		_release_all_injected_actions()
		return
	# This is post-native-step: the complete world reached the cursor through
	# real replay, including contacts and movable bodies. Never teleport it.
	var snapshot = _snapshot_player(player)
	var segments = []
	var checkpoints = []
	var remaining = target
	for i in range(_practice_segments.size()):
		if remaining <= 0:
			break
		var source: Array = _practice_segments[i]
		var count = min(remaining,source.size())
		checkpoints.append(_practice_checkpoints[i])
		segments.append(source.slice(0,count-1) if count>0 else [])
		remaining -= count
	checkpoints.append(snapshot)
	if not _continue_new_frames.empty():
		# One newly observed prefix, not original checkpoints from another world.
		segments = [_continue_new_frames.duplicate(true)]
		checkpoints = [_continue_start_snapshot.duplicate(true), snapshot]
	_practice_playback = false
	_release_all_injected_actions()
	_clear_practice_data()
	_practice_segments = segments
	_practice_checkpoints = checkpoints
	_practice_playback_frames = []
	_practice_playback_settling = false
	_practice_playback_pending_start = false
	for checkpoint in checkpoints:
		_practice_markers.append(_spawn_checkpoint_marker(player,checkpoint.position))
	for _segment in segments:
		_diag_live_committed.append([])
	_restyle_practice_markers()
	_practice_active = true
	_practice_prev_alive = true
	_practice_place_pending = false
	_ensure_game_over_submission_guard_runs_first()
	if not _is_paused:
		_toggle_pause()
	_update_macro_playback_timer()
	_refresh_practice_ui()
	if resume_automatically:
		if _is_paused:
			_toggle_pause()
		_log_action("Continue From End: recording new frames now. Original saved replay unchanged; save explicitly when ready.",null)
	else:
		_log_action("Continue From Here: paused after frame %d. Press F5 / Play to record a new ending; saved replay unchanged." % (target-1),null)
