extends "user://mod/tools/tas/TASTool/17_speed_and_frames.gd"

func _reset_post_native_momentum_guard() -> void:
	_post_guard_player_id = 0
	_post_guard_prev_alive = true
	_post_guard_saw_gameplay_death = false
	_post_guard_probe_ticks_left = 0
	_post_guard_last_accepted_position = Vector2.ZERO
	_post_guard_last_accepted_vx = 0.0


# Called by TASPostPhysicsGuard.gd at priority +1000000, after this main
# script's -1000000 input/recording callback and after the ordinary game
# nodes.  The pre-native freeze above remains useful throughout the dead
# hold; this closes its blind spot on the native death/respawn step itself.
func _post_native_death_momentum_guard() -> void:
	if not enabled or _tool_restricted() or _noclip_enabled:
		_reset_post_native_momentum_guard()
		return
	var player: = _get_local_player()
	if player == null:
		_reset_post_native_momentum_guard()
		return
	var player_id: = player.get_instance_id()
	if player_id != _post_guard_player_id:
		_post_guard_player_id = player_id
		_post_guard_prev_alive = player.alive
		_post_guard_saw_gameplay_death = false
		_post_guard_probe_ticks_left = 0
		_post_guard_last_accepted_position = player.position
		_post_guard_last_accepted_vx = player.linear_velocity.x
		return

	if not player.alive:
		# A committed macro contains no failed attempts. Repair replay-only
		# deaths here, after native collision handling but before the idle
		# renderer, so neither the dead pose nor its displacement is displayed.
		# The early playback callback keeps the same recovery as a fallback for
		# unusual callback ordering where this late guard does not run.
		if _practice_playback and _recover_authoritative_playback_death(player):
			_practice_playback_state_corrections += 1
			_post_guard_prev_alive = true
			_post_guard_saw_gameplay_death = false
			_post_guard_probe_ticks_left = 0
			_post_guard_last_accepted_position = player.position
			_post_guard_last_accepted_vx = player.linear_velocity.x
			_log_action("Macro Bot Mode: repaired unexpected replay collision at frame %d/%d before rendering." % [_practice_playback_index, _practice_playback_frames.size()], null)
			return
		if _post_guard_prev_alive:
			_post_guard_saw_gameplay_death = true
		# Undo the death-step displacement after native collision handling,
		# before rendering, then leave the existing pre-native freeze to hold
		# the same state on every later dead callback.
		if _post_guard_saw_gameplay_death:
			player.position = _freeze_last_alive_position
			player.linear_velocity = Vector2.ZERO
			player.ground_tangent_speed = 0.0
			player.body_enabled = false
			if player.body != null:
				player.body.global_position = _freeze_last_alive_position
				player.body.linear_velocity = Vector2.ZERO
				player.body.enabled = false
		_post_guard_prev_alive = false
		_post_guard_probe_ticks_left = 0
		return

	# Cached ground momentum is cleared while dead, before native respawn.
	# Once alive, native contacts own velocity: a bounce/platform impulse is
	# valid even on the first respawn tick and must never be speed-filtered.
	_post_guard_prev_alive = true
	_post_guard_saw_gameplay_death = false
	_post_guard_probe_ticks_left = 0


# ----------------------------------------------------------------------
#  Gating
# ----------------------------------------------------------------------
# True only when we're actually inside a LIVE network game (real competitive
# multiplayer) -- the one case `only_active_in_debug_or_solo` exists to keep
# the local physics tools out of. Time Trials, editor tests and tutorials are
# all local simulations and are intentionally supported. No game at all
# (main menu, level select, any other screen) is not restricted either, so
# the menu remains available for setting things up before entering a level.
func _tool_restricted() -> bool:
	if not only_active_in_debug_or_solo:
		return false
	if OS.is_debug_build():
		return false
	var g: = _find_game()
	if g == null:
		return false
	var gd: WPGameData = g.wp_game_data
	if gd == null:
		return false
	if gd.is_time_trial:
		return false
	if "is_level_editor" in gd and gd.is_level_editor:
		return false
	if "is_tutorial" in gd and gd.is_tutorial:
		return false
	return true


# Connect as soon as WPGame enters the tree.  That normally puts this callback
# ahead of TimeTrialGameplayScene._ready()'s own game_over callback, which is
# important: the recording replay must be stopped and made ineligible before
# the stock callback reaches async_submit_replay().
func _connect_game_over_submission_guard(game: WPGame) -> void:
	if game == null or not game.has_signal("game_over"):
		return
	if not game.is_connected("game_over", self, "_on_tas_game_over_before_native"):
		game.connect("game_over", self, "_on_tas_game_over_before_native")


# If the tool was injected while a Time Trial was already alive, its callback
# may predate ours.  Reconnect just those two callbacks when recording starts,
# preserving every other game_over listener and guaranteeing our guard runs
# first.  The stock connection has no binds or flags in the decompiled scene.
func _ensure_game_over_submission_guard_runs_first() -> void:
	var game: = _find_game()
	var scene: = get_tree().current_scene
	if game == null or scene == null or not game.has_signal("game_over"):
		return
	if not ("parameters" in scene) or not scene.has_method("on_game_over"):
		_connect_game_over_submission_guard(game)
		return
	var native_connected: = game.is_connected("game_over", scene, "on_game_over")
	if not native_connected:
		_connect_game_over_submission_guard(game)
		return
	if game.is_connected("game_over", self, "_on_tas_game_over_before_native"):
		game.disconnect("game_over", self, "_on_tas_game_over_before_native")
	game.disconnect("game_over", scene, "on_game_over")
	game.connect("game_over", self, "_on_tas_game_over_before_native")
	game.connect("game_over", scene, "on_game_over")


# Called from TASPostPhysicsGuard's very-late idle callback, after both the
# native player renderer and GameCamera have updated themselves. Overriding
# both together is important: GameCamera follows renderer.position_node, so
# fixing only the goober would leave the entire level/camera doing the same
# checkpoint shake around a stable sprite.
func _post_renderer_stitch_guard() -> void:
	_update_macro_playback_timer()
	if not _practice_playback:
		if _practice_playback_visual_valid:
			var ending_player: = _get_local_player()
			if ending_player != null:
				_reset_renderer_smoothing(ending_player)
			_reset_playback_visual_track()
		return
	if not _practice_playback_visual_valid:
		return
	var player: = _get_local_player()
	if player == null or player.get_instance_id() != _practice_playback_visual_player_id:
		_reset_playback_visual_track()
		return
	if _practice_playback_visual_renderer == null or not is_instance_valid(_practice_playback_visual_renderer):
		_practice_playback_visual_renderer = _find_player_renderer(player)
	if _practice_playback_visual_camera == null or not is_instance_valid(_practice_playback_visual_camera):
		_practice_playback_visual_camera = _find_playback_camera()
	# This build does not expose a reliable interpolation fraction on every
	# renderer backend. Use the actual wall time since the completed sample;
	# otherwise the value often stays at 1 and playback visibly stair-steps.
	var tick_usec := 1000000.0 / (max(1.0, float(Engine.iterations_per_second)) * max(0.05, Engine.time_scale))
	var interpolation := clamp(float(OS.get_ticks_usec() - _practice_playback_visual_sample_usec) / tick_usec, 0.0, 1.0)
	# Use the engine's accumulator when available: wall time since a callback
	# is near zero at every rendered frame when physics runs once per frame.
	if Engine.has_method("get_physics_interpolation_fraction"):
		interpolation = clamp(float(Engine.call("get_physics_interpolation_fraction")), 0.0, 1.0)
	var visual_position: Vector2 = _practice_playback_visual_previous.linear_interpolate(_practice_playback_visual_current, interpolation)
	if _visual_seam_polish_enabled:
		var polish_delta := get_process_delta_time()
		if _visual_seam_filter_remaining > 0.0:
			var follow_alpha := 1.0 - exp(-polish_delta / 0.028)
			_visual_seam_filter_position = _visual_seam_filter_position.linear_interpolate(visual_position, clamp(follow_alpha, 0.0, 1.0))
			visual_position = _visual_seam_filter_position
			_visual_seam_filter_remaining = max(0.0, _visual_seam_filter_remaining - polish_delta)
		else:
			_visual_seam_filter_position = visual_position
	_visual_seam_last_output = visual_position
	_visual_seam_output_valid = true
	var renderer: = _practice_playback_visual_renderer
	var renderer_delta: = Vector2.ZERO
	var renderer_global_delta: = Vector2.ZERO
	var has_renderer_delta: = false
	if renderer != null and is_instance_valid(renderer):
		# Prevent the renderer's own correction-oriented smooth_damp from
		# carrying a stale boundary offset into the following frames.
		if renderer.get("is_smoothing") != null:
			renderer.is_smoothing = false
		if renderer.get("smoothed_p") != null:
			renderer.smoothed_p = player.linear_velocity
		if renderer.get("prev_position") != null:
			renderer.prev_position = player.position
		if renderer.get("prev_velocity") != null:
			renderer.prev_velocity = player.linear_velocity
		var position_node = renderer.get("position_node")
		if position_node != null and is_instance_valid(position_node):
			renderer_delta = visual_position - position_node.position
			has_renderer_delta = true
			var old_global_position: Vector2 = position_node.global_position
			position_node.position = visual_position
			renderer_global_delta = position_node.global_position - old_global_position
		var ui_node = renderer.get("ui_node")
		if ui_node != null and is_instance_valid(ui_node):
			ui_node.rect_position = visual_position
		# Some renderer configurations detach the Spine sprite from Position.
		# Apply the same displacement there without moving ordinary descendants
		# twice. Otherwise the camera/UI smooth while the avatar still jitters.
		var spine = renderer.get("spine")
		if has_renderer_delta and spine is Node2D and position_node is Node2D and not position_node.is_a_parent_of(spine):
			spine.global_position += renderer_global_delta
		# The native pose can retain the just-ended dash's facing for one frame.
		# Correct only the rendered pose when movement AND velocity agree. Keep
		# real skids, active dashes, and wall-slide poses intact.
		var holder = renderer.get("spine_holder")
		if holder is Node2D and player.alive and player.dash_timer <= 0 and not player.wallslide_counter:
			var pose_index: int = _practice_playback_index - 1
			if pose_index >= 0 and pose_index < _practice_playback_frames.size():
				var move: float = _practice_playback_movement_value(_practice_playback_frames[pose_index])
				if move != 0.0 and move * player.linear_velocity.x >= -0.01:
					var before: Transform2D = holder.global_transform
					holder.scale.x = -sign(move) * abs(holder.scale.x)
					if spine is Node2D and not holder.is_a_parent_of(spine) and abs(before.x.x * before.y.y - before.x.y * before.y.x) > 0.000001:
						spine.global_transform = holder.global_transform * before.affine_inverse() * spine.global_transform
	var camera: = _practice_playback_visual_camera
	if camera != null and is_instance_valid(camera) and has_renderer_delta:
		# GameCamera already ran at this point and may have applied its own
		# offsets/smoothing. Move its completed result by exactly the same
		# render-only correction as the player instead of replacing it with the
		# player's absolute position. Replacing it (and zeroing its smooth-damp
		# velocity every idle frame) made the camera alternate between its native
		# result and ours, which presented as a small shake at stitch boundaries.
		camera.position += renderer_delta
		camera.force_update_scroll()


# This listener is deliberately ordered before TimeTrialGameplayScene's stock
# listener.  The stock code submits whenever the finish beats the cached PB;
# merely stopping replay recording is not enough.  For this one signal dispatch
# we also make the loaded level fail its RACE eligibility check, then restore
# the original type on the deferred call after all signal listeners have run.
func _on_tas_game_over_before_native(winner_id: int) -> void:
	if not _practice_active and not _practice_playback:
		return
	var game: = _find_game()
	var scene: = get_tree().current_scene
	if game == null or not _is_normal_linked_time_trial_scene(scene):
		return
	if game.has_method("is_local_player") and not game.is_local_player(winner_id):
		return

	var player: = _get_local_player()
	var was_recording: bool = _practice_active
	if _practice_active:
		_finalize_practice_recording_at_finish(player)
	call_deferred("_mark_tas_result_timer", scene)
	_practice_active = false
	_practice_awaiting_native_respawn = false
	game.set_replay_status(NetworkGame.REPLAY_STATUS_NONE)

	var loaded_level = null
	if ("level" in game) and game.get("level") != null and ("loaded_level" in game.get("level")):
		loaded_level = game.get("level").get("loaded_level")
	if loaded_level != null and ("level_type" in loaded_level):
		var original_level_type = loaded_level.get("level_type")
		loaded_level.set("level_type", -1)
		call_deferred("_restore_macro_recording_level_type", loaded_level, original_level_type)

	_log_action("TAS result marked locally -- not submitted to the leaderboard", null)
	_refresh_practice_ui()
	if was_recording:
		call_deferred("_show_native_notify", "REPLAY RECORDED", "Replay recorded.\n\nIt is ready in Macro Bot and was not submitted to the leaderboard.")


func _mark_tas_result_timer(scene) -> void:
	if not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	var renderer = scene.game_hud.time_trial_panel.level_info_panel.time_renderer
	_mark_tas_timer_labels(renderer.this_time_time_pill)
