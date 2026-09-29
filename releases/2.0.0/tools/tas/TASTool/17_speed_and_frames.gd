extends "user://mod/tools/match-info/TASTool/16_lobby_code.gd"

func _capture_practice_native_frame(player: WPPlayer) -> void:
	if player.alive and not _noclip_enabled:
		var frame: = _capture_practice_frame()
		var g: = _find_game()
		# Input alone cannot serialize the native physics body's private contact/
		# integration state. Keep the observable beginning-of-tick state beside
		# every input frame so playback can repair a drift at the first callback
		# where it becomes visible, before it cascades into a missed jump/death.
		frame[PRACTICE_FRAME_STATE_KEY] = _capture_practice_frame_state(player, g)
		# Godot invokes this method exactly once for each fixed physics step,
		# including every catch-up step. The game's play_time is updated by a
		# different node later in the same ordered step and is therefore not a
		# valid callback fingerprint here. Record the observed input once and
		# never synthesize or discard macro frames.
		_practice_current_segment.append(frame)
		if _diag_enabled:
			_diag_live_current.append(_capture_diag_entry(player, g, frame))
		_live_tick_fingerprint_normal += 1
		# The status label itself is updated once per idle frame from
		# _update_overlay() (and only when the text actually changes), not
		# here on every physics frame -- see the PERFORMANCE note there.


# ----------------------------------------------------------------------
#  Slowdown / pause / frame-step
# ----------------------------------------------------------------------
func _handle_speed_hotkeys() -> void:
	if _just_pressed(KEY_PLAY_STOP):
		_toggle_pause()
	if enable_frame_step and _just_pressed(KEY_FRAME_STEP):
		_request_frame_step()
	if _just_pressed(KEY_SLOWER):
		_adjust_time_scale(-TIME_SCALE_STEP)
	if _just_pressed(KEY_FASTER):
		_adjust_time_scale(TIME_SCALE_STEP)
	if _just_pressed(KEY_RESET_SPEED):
		_on_reset_speed_pressed()


func _toggle_pause() -> void:
	var before: = _snapshot_engine_state()
	if _is_paused:
		Engine.time_scale = _saved_time_scale
		_is_paused = false
		_log_action("Playing (%.2fx)" % Engine.time_scale, {"type": "engine_state", "state": before})
	else:
		_saved_time_scale = Engine.time_scale
		Engine.time_scale = 0.0
		_is_paused = true
		_log_action("Stopped", {"type": "engine_state", "state": before})


func _request_frame_step() -> void:
	if not enable_frame_step:
		return
	if not _is_paused:
		_saved_time_scale = Engine.time_scale
		_is_paused = true
	_step_start_physics_frame = Engine.get_physics_frames()
	Engine.time_scale = 1.0
	_pending_frame_step = true
	# Buffered Inputs: press+hold every armed action for the duration of this
	# step, so it's registered on the physics frame(s) about to run instead
	# of needing the real key physically held at this exact moment.
	for entry in BUFFERABLE_ACTIONS:
		var action: String = entry[1]
		if _buffered_actions.get(action, false):
			_inject_action(action, true)
			_injected_actions_held.append(action)
	_set_status("Frame step (%d frames)" % frame_step_count)


func _process_frame_step_watch() -> void:
	if _pending_frame_step and Engine.get_physics_frames() >= _step_start_physics_frame + frame_step_count:
		Engine.time_scale = 0.0
		_pending_frame_step = false
		for action in _injected_actions_held:
			_inject_action(action, false)
		_injected_actions_held.clear()


func _adjust_time_scale(delta_scale: float) -> void:
	var before: = _snapshot_engine_state()
	if _is_paused:
		_saved_time_scale = clamp(_saved_time_scale + delta_scale, TIME_SCALE_MIN, TIME_SCALE_MAX)
		_log_action("Speed (stopped, resumes at) %.2fx" % _saved_time_scale, {"type": "engine_state", "state": before})
	else:
		Engine.time_scale = clamp(Engine.time_scale + delta_scale, TIME_SCALE_MIN, TIME_SCALE_MAX)
		_log_action("Speed %.2fx" % Engine.time_scale, {"type": "engine_state", "state": before})


func _set_active_time_scale(v: float) -> void:
	v = clamp(v, TIME_SCALE_MIN, TIME_SCALE_MAX)
	if _is_paused:
		_saved_time_scale = v
	else:
		Engine.time_scale = v


func _on_reset_speed_pressed() -> void:
	var before: = _snapshot_engine_state()
	_set_active_time_scale(1.0)
	_log_action("Speed reset to 1.0x", {"type": "engine_state", "state": before})


func _on_enable_frame_step_toggled(pressed: bool) -> void:
	enable_frame_step = pressed
	if not enable_frame_step and _pending_frame_step:
		_pending_frame_step = false
		for action in _injected_actions_held:
			_inject_action(action, false)
		_injected_actions_held.clear()
	if _step_button != null:
		_step_button.disabled = not enable_frame_step
	_set_status("Frame-Step Mode: %s" % ("ON" if enable_frame_step else "OFF"))


func _on_toggle_step_config_pressed() -> void:
	_step_config_row.visible = not _step_config_row.visible


func _on_step_count_delta_pressed(delta: int) -> void:
	frame_step_count = clamp(frame_step_count + delta, FRAME_STEP_COUNT_MIN, FRAME_STEP_COUNT_MAX)
	_step_count_label.text = "%d" % frame_step_count


func _capture_practice_frame_state(p: WPPlayer, g: WPGame) -> Dictionary:
	var state: = {
		"native_tick_clock": _has_practice_native_tick_hooks(),
		"position": p.position,
		"linear_velocity": p.linear_velocity,
		"practice_playback_air_hold_ticks": _practice_playback_air_hold_ticks,
		"practice_playback_air_hold_dir": _practice_playback_air_hold_dir,
	}
	for field in PRACTICE_FRAME_RESYNC_SCALAR_FIELDS:
		state[field] = p.get(field)
	# Native animated objects are deterministic in time. One phase value per
	# frame avoids copying every static body on every tick.
	if _sync_moving_objects_enabled and g != null and g.level != null and g.wp_game_data != null:
		state["moving_world_time"] = g.wp_game_data.play_time + _moving_phase_shift(g)
	if g != null and g.wp_game_data != null:
		var data: = g.wp_game_data
		for field in ["play_time", "state_time", "time_remaining"]:
			if field in data:
				state[field] = data.get(field)
	# Speed is presentation metadata. It never replaces the game's race clock,
	# but it lets local playback reproduce portions recorded in slow motion.
	state["tas_playback_speed"] = 0.15 if _pending_frame_step else clamp(Engine.time_scale, 0.05, 4.0)
	return state


# Captures whatever's actually reached Input.is_action_pressed() this
# physics frame for each recordable action -- real keyboard (on ANY bound
# key), joypad, touch, Buffered Inputs holds, and Perfect Jumpzone presses
# all land in the same place, so whichever produced this frame's input gets
# captured identically.
func _capture_practice_frame() -> Dictionary:
	var frame: = {}
	for action in PRACTICE_RECORD_ACTIONS:
		frame[action] = Input.is_action_pressed(action)
	if frame.get(ACTION_DASH, false):
		var player: = _get_local_player()
		var move: = sign(Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT))
		var joystick_x: = Input.get_action_strength("player_joystick_move_right") - Input.get_action_strength("player_joystick_move_left")
		if abs(joystick_x) > 0.1:
			move = joystick_x
		if move != 0.0:
			frame[PRACTICE_DASH_DIRECTION_KEY] = move > 0.0
		elif player != null:
			frame[PRACTICE_DASH_DIRECTION_KEY] = bool(player.facing_dir)
	return frame


# ----------------------------------------------------------------------
#  Frame Rate Limit -- see the big comment on FPS_LIMIT_SETTINGS_PATH above
#  for why this exists. Persisted/loaded exactly like Debug Mode just above
#  (same File.store_var()/get_var() pattern, same "tiny standalone .cfg,
#  survives a TASTool.gd restart" reasoning), applied via Engine.
#  set_target_fps() -- Godot 3.x's own built-in cap primitive, the same one
#  Project Settings > Application > Run > Max FPS drives, just exposed here
#  at runtime instead of requiring an export/rebuild. fps_limit == 0 is the
#  sentinel for "uncapped," matching Engine.set_target_fps()'s own
#  convention exactly (passing 0 there already means "no limit"), so
#  _apply_fps_limit() never needs a separate on/off flag.
# ----------------------------------------------------------------------
func _load_fps_limit_from_disk() -> void:
	var f: = File.new()
	if f.file_exists(FPS_LIMIT_SETTINGS_PATH) and f.open(FPS_LIMIT_SETTINGS_PATH, File.READ) == OK:
		var loaded = f.get_var()
		f.close()
		if typeof(loaded) == TYPE_INT or typeof(loaded) == TYPE_REAL:
			fps_limit = int(clamp(loaded, FPS_LIMIT_MIN, FPS_LIMIT_MAX))
	_apply_fps_limit()


func _save_fps_limit_to_disk() -> void:
	var f: = File.new()
	if f.open(FPS_LIMIT_SETTINGS_PATH, File.WRITE) == OK:
		f.store_var(fps_limit)
		f.close()


func _apply_fps_limit() -> void:
	Engine.set_target_fps(fps_limit) # 0 == uncapped, Engine's own convention


func _on_fps_limit_delta_pressed(delta: int) -> void:
	fps_limit = int(clamp(fps_limit + delta, FPS_LIMIT_MIN, FPS_LIMIT_MAX))
	_apply_fps_limit()
	_save_fps_limit_to_disk()
	_fps_limit_label.text = ("%d FPS" % fps_limit) if fps_limit > 0 else "Uncapped"
	_log_action("Frame Rate Limit: %s (saved -- stays set across restarts)" % (("%d FPS" % fps_limit) if fps_limit > 0 else "uncapped"), null)


# One physics frame of stitched playback. Re-syncs to the exact checkpoint
# snapshot at every segment boundary (rather than just trusting the
# concatenated inputs to land correctly on their own) so segments recorded
# independently can never drag each other off course.
func _has_practice_native_tick_hooks() -> bool:
	return is_instance_valid(_practice_native_tick_game) and _practice_native_tick_game == _find_game() and _practice_native_tick_game.is_connected("pre_step", self, "_on_practice_native_pre_step")


func _ensure_practice_native_tick_hooks(game: WPGame) -> bool:
	if game == null or not game.is_server() or not game.has_signal("pre_step") or not game.has_signal("tick_post_step"):
		return false
	if _practice_native_tick_game == game and game.is_connected("pre_step", self, "_on_practice_native_pre_step"):
		return true
	if is_instance_valid(_practice_native_tick_game):
		if _practice_native_tick_game.is_connected("pre_step", self, "_on_practice_native_pre_step"):
			_practice_native_tick_game.disconnect("pre_step", self, "_on_practice_native_pre_step")
		if _practice_native_tick_game.is_connected("tick_post_step", self, "_on_practice_native_post_step"):
			_practice_native_tick_game.disconnect("tick_post_step", self, "_on_practice_native_post_step")
	# WPGame copies its continuous-input buffer in local_pre_tick(). Place
	# this hook immediately before that copy, not on Godot's unrelated clock.
	var had_input_hook: bool = game.is_connected("pre_step", game, "local_pre_tick")
	if not had_input_hook:
		return false
	game.disconnect("pre_step", game, "local_pre_tick")
	game.connect("pre_step", self, "_on_practice_native_pre_step", [game])
	game.connect("pre_step", game, "local_pre_tick")
	game.connect("tick_post_step", self, "_on_practice_native_post_step", [game])
	_practice_native_tick_game = game
	return true


func _on_practice_native_pre_step(_ticks: int, game: WPGame) -> void:
	if not enabled or _tool_restricted() or game != _find_game():
		return
	if game.is_resimulating() or _is_paused or _macro_editor_preview_active:
		return
	if _practice_playback:
		if _practice_playback_uses_native_clock():
			_advance_practice_playback()
	elif _practice_active and not _practice_awaiting_native_respawn:
		var player: = _get_local_player()
		if player != null:
			_capture_practice_native_frame(player)


func _on_practice_native_post_step(_tick_rate: float, _tick_num: int, game: WPGame) -> void:
	if game != _find_game():
		return
	_post_native_death_momentum_guard()
	_capture_playback_visual_sample()
	if _practice_playback and _practice_continue_frame >= 0 and _practice_playback_index >= _practice_continue_frame:
		# Native tick_post_step precedes its final player/body synchronization.
		# Stop advancing input now; take the branch snapshot after that sync.
		_practice_playback = false
		if not _is_paused:
			_toggle_pause()
		call_deferred("_finish_macro_continue")


func _advance_continue_resimulation() -> void:
	var player = _get_local_player()
	var game = _find_game()
	if player == null or game == null or game.is_game_over() or (not _practice_playback_pending_start and not player.alive):
		_continue_resimulating = false
		_practice_continue_frame = -1
		_practice_playback = false
		_practice_playback_pending_start = false
		_release_all_injected_actions()
		Engine.time_scale = 1.0
		_log_action("Continue From stopped: the old inputs could not reach that point in the current level. Saved replay unchanged.", null)
		_refresh_practice_ui()
		return
	if _practice_playback_pending_start:
		_practice_playback_pending_start = false
		# Only seed the player once. Never restore old world objects, revive after
		# a collision, or impose the recorded trajectory on the edited geometry.
		_restore_player(player, _practice_checkpoints[0])
		_continue_start_snapshot = _snapshot_player(player)
	if _practice_playback_index >= _practice_playback_frames.size():
		return
	var frame = _practice_playback_frames[_practice_playback_index].duplicate(true)
	frame[PRACTICE_FRAME_STATE_KEY] = _capture_practice_frame_state(player, game)
	_continue_new_frames.append(frame)
	_practice_playback_frames[_practice_playback_index] = frame
	_sync_practice_playback_injected_input(frame)
	_practice_playback_index += 1
