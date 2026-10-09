extends Reference

# Entry pauses and frozen display alignment only. No saved replay edits,
# manufactured input ticks, native clock rewrites or momentum resets.
var waiting_game = 0
var entry_queued = false
var pacing = false
var resume_speed = 1.0
var visual_player_id = 0
var visual_game_id = 0
var visual_renderer = null
var visual_camera = null

func arm(owner) -> void:
	var game = owner._find_game()
	if game == null or not game.is_server() or owner._tool_restricted(): return
	if waiting_game == game.get_instance_id(): return
	cancel(owner)
	waiting_game = game.get_instance_id()
	resume_speed = owner._saved_time_scale if owner._is_paused else Engine.time_scale
	owner._ensure_practice_native_tick_hooks(game)

func pace(owner, game) -> void:
	if game == null or waiting_game != game.get_instance_id() or entry_queued or owner._is_paused: return
	# Pace only the last few countdown ticks, before the engine latches the
	# next native batch. This avoids crossing the playable boundary inside
	# a multi-tick render batch. The first playable tick still runs natively.
	if game.wp_game_data.gameplay_state == WPGameData.GameplayState_LEVEL_PRE and game.wp_game_data.state_time <= 4.0 * game.tick_rate:
		pacing = true
		Engine.time_scale = min(resume_speed, 0.15)

func on_post_step(owner, game) -> void:
	if game == null or waiting_game != game.get_instance_id() or entry_queued: return
	if not owner._practice_start_waiting or not owner.enabled or owner._tool_restricted() or owner._macro_editor_preview_active or owner._practice_playback or owner._saved_macro_autoplay_slot > 0:
		cancel(owner)
		return
	var player = owner._get_local_player()
	if game.wp_game_data.gameplay_state != WPGameData.GameplayState_LEVEL_PLAY or player == null or not owner._player_ready_for_checkpoint(player): return
	entry_queued = true
	Engine.time_scale = 0.0
	owner._is_paused = true
	owner._saved_time_scale = resume_speed
	# Native post-step precedes final body->player pose synchronization.
	# Snapshot the completed playable tick only after that synchronization.
	owner.call_deferred("_commit_practice_entry_pause")

func commit(owner) -> void:
	if not entry_queued: return
	var game = owner._find_game()
	var player = owner._get_local_player()
	var valid = game != null and waiting_game == game.get_instance_id() and owner.enabled and not owner._tool_restricted() and owner._practice_start_waiting and not owner._practice_playback and not owner._macro_editor_preview_active and player != null and owner._player_ready_for_checkpoint(player) and game.wp_game_data.gameplay_state == WPGameData.GameplayState_LEVEL_PLAY
	waiting_game = 0
	entry_queued = false
	pacing = false
	if not valid:
		if owner._is_paused: owner._toggle_pause()
		return
	owner._practice_start_waiting = false
	owner._practice_auto_activate_waiting_for_alive = false
	owner._practice_ready_stable_ticks = 0
	if owner._practice_active: owner._stop_practice_mode()
	owner._start_practice_mode(owner._practice_start_reason, true)
	owner._set_status("Macro Bot: paused at the first playable frame")
	draw_paused(owner)

func cancel(owner) -> void:
	if pacing and not owner._is_paused: Engine.time_scale = resume_speed
	waiting_game = 0
	entry_queued = false
	pacing = false

func draw_paused(owner) -> bool:
	if not owner.enabled or not owner._is_paused or not owner._practice_active or owner._practice_playback or owner._pending_frame_step or owner._macro_editor_preview_active or owner._tool_restricted(): return false
	var player = owner._get_local_player()
	if player == null or not player.alive: return false
	var game = owner._find_game()
	if game == null: return false
	if visual_player_id != player.get_instance_id() or visual_game_id != game.get_instance_id():
		visual_player_id = player.get_instance_id()
		visual_game_id = game.get_instance_id()
		visual_renderer = null
		visual_camera = null
	if not is_instance_valid(visual_renderer): visual_renderer = owner._find_player_renderer(player)
	if not is_instance_valid(visual_camera): visual_camera = owner._find_playback_camera()
	var renderer = visual_renderer
	if not is_instance_valid(renderer): return false
	var position_node = renderer.get("position_node")
	if not position_node is Node2D: return false
	# Cache renderer/camera lookups across frozen frames: the ordinary helper
	# walks the scene tree. Paused display updates must not create FPS stutter.
	if renderer.get("is_smoothing") != null: renderer.is_smoothing = false
	if renderer.get("smoothed_p") != null: renderer.smoothed_p = player.linear_velocity
	if renderer.get("prev_position") != null: renderer.prev_position = player.position
	if renderer.get("prev_velocity") != null: renderer.prev_velocity = player.linear_velocity
	# Native interpolation history can still refer to the pre-restore body.
	# Display the exact frozen state AFTER renderer/camera updates. Do not
	# advance physics to make the renderer catch up, or zero its momentum.
	var delta = player.position - position_node.position
	var old_global = position_node.global_position
	position_node.position = player.position
	var global_delta = position_node.global_position - old_global
	var ui = renderer.get("ui_node")
	if ui is Control: ui.rect_position = player.position
	var spine = renderer.get("spine")
	if spine is Node2D and not position_node.is_a_parent_of(spine): spine.global_position += global_delta
	var camera = visual_camera
	if camera != null and is_instance_valid(camera):
		camera.position += delta
		camera.force_update_scroll()
	return true
