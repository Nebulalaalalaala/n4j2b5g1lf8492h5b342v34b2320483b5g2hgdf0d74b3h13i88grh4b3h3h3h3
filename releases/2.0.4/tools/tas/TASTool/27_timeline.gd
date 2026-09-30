extends "user://mod/tools/tas/TASTool/26_macro_bot_3.gd"

func _continue_macro_editor_data(data: Dictionary, frame_index: int, auto_resume := false) -> bool:
	var game = _find_game()
	if game == null or not game.is_server() or _tool_restricted() or not _ensure_practice_native_tick_hooks(game):
		_log_action("Continue From: open this replay's local level first. Public matches cannot be rewound.", null)
		return false
	var frames = []
	for segment in data.get("segments",[]):
		frames += segment
	if frame_index < 0 or frame_index >= frames.size() or data.get("checkpoints",[]).empty():
		return false
	for frame in frames:
		if not bool(frame.get(PRACTICE_FRAME_STATE_KEY,{}).get("native_tick_clock",false)):
			_log_action("Continue From requires a native-tick recording; this legacy replay cannot resume accurately.",null)
			return false
	if not _install_editor_data_as_current(data):
		return false
	_practice_start_waiting = false
	_practice_auto_activate_waiting_for_alive = false
	_on_play_practice_macro_pressed()
	_practice_continue_frame = frame_index+1
	_practice_continue_auto_resume = auto_resume
	_continue_resimulating = true
	_continue_new_frames = []
	_continue_start_snapshot = {}
	_log_action("Continue From: re-simulating inputs in the CURRENT local level through frame %d. Old object states are ignored; saved slot unchanged." % frame_index,null)
	return true


func _play_macro_editor_data(slot: int, data: Dictionary) -> void:
	if _get_local_player() == null and slot > 0:
		# Allow the editor's transport button to use the slot's saved level link
		# from the main menu. Keep the edited working copy in memory only; the
		# disk file still changes exclusively through SAVE CHANGES.
		_practice_macro_slots[slot] = data.duplicate(true)
		_log_action("Opening linked level for unsaved Timeline Editor working copy from Slot %d" % slot, null)
		_on_play_saved_practice_macro_slot_pressed(slot)
		return
	if not _install_editor_data_as_current(data):
		return
	_log_action("Playing Timeline Editor working copy%s" % (" from Slot %d" % slot if slot > 0 else ""), null)
	_on_play_practice_macro_pressed()


func _install_editor_data_as_current(data: Dictionary) -> bool:
	var player := _get_local_player()
	if player == null:
		_log_action("Open the linked level before installing or playing timeline edits", null)
		return false
	_clear_practice_data()
	_practice_checkpoints = data.get("checkpoints", []).duplicate(true)
	_practice_segments = data.get("segments", []).duplicate(true)
	for snap in _practice_checkpoints:
		if typeof(snap) == TYPE_DICTIONARY and snap.has("position"):
			_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	_restyle_practice_markers()
	_practice_active = false
	_refresh_practice_ui()
	return true


# Live, reversible level preview used by TASMacroEditor. The scene tree is
# paused while editing, so scrubbing can reposition the real player without
# advancing physics, clocks, hazards, or native replay recording.
func _begin_macro_editor_preview() -> bool:
	var player := _get_local_player()
	if player == null:
		return false
	if _macro_editor_preview_active:
		_end_macro_editor_preview()
	_release_all_injected_actions()
	_macro_editor_preview_snapshot = _snapshot_player(player)
	_macro_editor_preview_player_id = player.get_instance_id()
	_macro_editor_preview_was_tree_paused = get_tree().paused
	_macro_editor_preview_active = true
	_macro_editor_timer_pills.clear()
	_collect_macro_editor_timers(get_tree().root, _macro_editor_timer_pills)
	var camera := _find_playback_camera()
	if camera != null:
		_macro_editor_preview_camera_id = camera.get_instance_id()
		_macro_editor_preview_camera_position = camera.position
		_macro_editor_preview_camera_zoom = camera.zoom
		_macro_editor_preview_camera_follow_offset = camera.position - player.position
		# Keep the real GameCamera active. LevelSDFViewport and other presentation
		# layers are wired directly to this camera, so swapping in a bare Camera2D
		# makes the editor show collision geometry without the finished level art.
		# The paused scene tree stops GameCamera's follow script while still letting
		# us move and zoom the camera directly for freecam.
		_macro_editor_camera = camera
		camera.current = true
	else:
		_macro_editor_preview_camera_id = 0
	var renderer := _find_player_renderer(player)
	if renderer != null:
		_macro_editor_preview_renderer = renderer
		_macro_editor_preview_renderer_pause_mode = renderer.pause_mode
		_macro_editor_preview_snapshot["preview_position_visible"] = renderer.position_node.visible
		_macro_editor_preview_snapshot["preview_spine_visible"] = renderer.spine_holder.visible
		renderer.pause_mode = Node.PAUSE_MODE_STOP
	_enable_macro_editor_presentation_processing()
	_macro_editor_freecam_detached = false
	get_tree().paused = true
	_refresh_macro_editor_presentation()
	return true


func _collect_macro_editor_timers(node: Node, result: Array) -> void:
	if node is TimeTrialPill and not node.render_game_target_time and node.game == _find_game():
		result.append({"node": node, "text": node.time_label.text, "fraction": node.time_label_frac.text})
	for child in node.get_children():
		_collect_macro_editor_timers(child, result)


func _set_macro_editor_time(seconds: float) -> void:
	if not _macro_editor_preview_active:
		return
	for entry in _macro_editor_timer_pills:
		if is_instance_valid(entry.node):
			entry.node.set_time(max(0.0, seconds))


# The native level presentation is camera-driven. Besides the SDF/fullscreen
# terrain pair, backgrounds, physics-block culling and ice shader uniforms all
# normally update in _process(). The Timeline Editor pauses gameplay, so these
# visual-only scripts must keep processing or freecam reveals a stale/incomplete
# level. Never add gameplay renderers here: several of them also drive sounds,
# particles or collision state.
func _enable_macro_editor_presentation_processing() -> void:
	_restore_macro_editor_presentation_processing()
	_collect_macro_editor_presentation_nodes(get_tree().root)
	for entry in _macro_editor_preview_presentation_nodes:
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node):
			node.pause_mode = Node.PAUSE_MODE_PROCESS


func _collect_macro_editor_presentation_nodes(node: Node) -> void:
	if node == null:
		return
	var script = node.get_script()
	if script != null:
		var script_path: String = str(script.get_path())
		if script_path in MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS:
			_macro_editor_preview_presentation_nodes.append({"node": node, "pause_mode": node.pause_mode, "script_path": script_path})
	for child in node.get_children():
		_collect_macro_editor_presentation_nodes(child)


func _refresh_macro_editor_presentation() -> void:
	# GameCamera normally updates this singleton after moving. Timeline freecam
	# moves the paused camera directly, so refresh it first; otherwise block
	# renderers continue culling against the rectangle from editor entry.
	_refresh_macro_editor_visible_rect()
	# Preserve the camera-dependent presentation pipeline order even if tree
	# order differs.
	for wanted_path in MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS:
		for entry in _macro_editor_preview_presentation_nodes:
			if entry["script_path"] != wanted_path:
				continue
			var node: Node = entry["node"]
			if node != null and is_instance_valid(node) and node.has_method("_process"):
				node.call("_process", 0.0)

	# Phase 0.9 -- Thin-Block Terrain Fallback. THIS is why every previous
	# version of this fix showed zero effect no matter what: TASTool's own
	# node never sets its own pause_mode away from the PAUSE_MODE_INHERIT
	# default, and _begin_macro_editor_preview() above pauses the whole
	# scene tree (get_tree().paused = true) for the Timeline Editor preview
	# Len has been testing in. A paused node with inherited pause_mode does
	# not receive _process() calls at all -- so _maintain_terrain_fallback_rendering(),
	# called from the top of TASTool's own _process(), was never running
	# during any of the previous attempts, regardless of what its detection
	# logic did or didn't find. This is the exact same failure mode already
	# solved for PolygonTerrain.gd itself right above (see that entry's own
	# comment in MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS) -- a dirty/pending
	# visual update that only ever gets processed on an unpaused _process()
	# tick, which the Timeline Editor may never deliver. Forcing TASTool's
	# entire _process() to PAUSE_MODE_PROCESS was deliberately avoided (it
	# also drives input injection, replay recording and hotkeys, which
	# should NOT keep running just because a visual refresh is needed) --
	# calling just this one function here, synchronously, every time the
	# Timeline Editor actually refreshes its presentation (preview start,
	# freecam move/zoom/center/reset), is the same targeted fix already
	# used for PolygonTerrain, applied to this fallback too.
	_maintain_terrain_fallback_rendering(_find_game())


func _refresh_macro_editor_visible_rect() -> void:
	var calculator: Node = get_tree().root.get_node_or_null("ViewportRectCalculator")
	if calculator == null:
		return
	# The shipped game exposes the public name; some extracted source builds use
	# the underscored implementation name. Supporting both keeps the mod portable.
	if calculator.has_method("calculate_viewport_visible_rect"):
		calculator.call("calculate_viewport_visible_rect")
	elif calculator.has_method("_calculate_viewport_visible_rect"):
		calculator.call("_calculate_viewport_visible_rect")


func _restore_macro_editor_presentation_processing() -> void:
	for entry in _macro_editor_preview_presentation_nodes:
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node):
			node.pause_mode = int(entry["pause_mode"])
	_macro_editor_preview_presentation_nodes = []


func _preview_macro_editor_frame(frame: Dictionary) -> bool:
	if not _macro_editor_preview_active:
		return false
	var player := _get_local_player()
	if player == null or player.get_instance_id() != _macro_editor_preview_player_id:
		return false
	var state = frame.get(PRACTICE_FRAME_STATE_KEY, {})
	if typeof(state) != TYPE_DICTIONARY or not state.has("position"):
		return false
	var old_position: Vector2 = player.position
	# Successful recorded segments predate explicit life flags. A live death
	# must not leave their paused preview hidden or disabled.
	player.alive = bool(state.get("alive", true))
	player.body_enabled = bool(state.get("body_enabled", true))
	if player.body != null:
		player.body.enabled = player.body_enabled
	_apply_recorded_practice_frame_state(player, state)
	_reset_renderer_smoothing(player)
	_set_macro_editor_preview_visual(player, old_position, player.position)
	return true


func _set_macro_editor_preview_visual(player: WPPlayer, from_position: Vector2, to_position: Vector2) -> void:
	var renderer := _find_player_renderer(player)
	if renderer != null:
		var position_node = renderer.get("position_node")
		if position_node != null and is_instance_valid(position_node):
			position_node.visible = player.alive
			position_node.position = to_position
		var spine_holder = renderer.get("spine_holder")
		if spine_holder != null and is_instance_valid(spine_holder):
			spine_holder.visible = player.alive
			spine_holder.scale.x = -1.0 if player.facing_dir else 1.0
		var ui_node = renderer.get("ui_node")
		if ui_node != null and is_instance_valid(ui_node):
			ui_node.rect_position = to_position
	var camera := _macro_editor_camera
	if camera != null and is_instance_valid(camera) and not _macro_editor_freecam_detached:
		camera.position += to_position - from_position
		camera.force_update_scroll()
		_refresh_macro_editor_presentation()


func _move_macro_editor_freecam(screen_delta: Vector2) -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	if camera == null or not is_instance_valid(camera):
		return
	_macro_editor_freecam_detached = true
	camera.position += screen_delta * max(camera.zoom.x, camera.zoom.y)
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


func _zoom_macro_editor_freecam(factor: float) -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	if camera == null or not is_instance_valid(camera):
		return
	var next_zoom := clamp(camera.zoom.x * factor, 0.18, 4.0)
	camera.zoom = Vector2(next_zoom, next_zoom)
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


func _center_macro_editor_freecam() -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	var player := _get_local_player()
	if camera == null or not is_instance_valid(camera) or player == null:
		return
	_macro_editor_freecam_detached = false
	camera.position = player.position + _macro_editor_preview_camera_follow_offset
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


# Phase 0.4 -- Freecam Stability Pass. "Reset Camera" -- unlike
# _center_macro_editor_freecam() above (position only, keeps whatever zoom the
# user set), this also puts zoom back to what it was the moment preview began,
# so a lost/zoomed-out freecam can be recovered without closing the editor.
func _reset_macro_editor_freecam() -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	var player := _get_local_player()
	if camera == null or not is_instance_valid(camera) or player == null:
		return
	_macro_editor_freecam_detached = false
	camera.position = player.position + _macro_editor_preview_camera_follow_offset
	camera.zoom = _macro_editor_preview_camera_zoom
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


func _get_macro_editor_freecam_zoom_percent() -> int:
	var camera := _macro_editor_camera
	if camera == null or not is_instance_valid(camera) or is_zero_approx(camera.zoom.x):
		return 100
	return int(round(100.0 / camera.zoom.x))


func _end_macro_editor_preview() -> void:
	if not _macro_editor_preview_active:
		return
	for entry in _macro_editor_timer_pills:
		if is_instance_valid(entry.node):
			entry.node.time_label.text = entry.text
			entry.node.time_label_frac.text = entry.fraction
	_macro_editor_timer_pills.clear()
	var player := _get_local_player()
	if player != null and player.get_instance_id() == _macro_editor_preview_player_id and not _macro_editor_preview_snapshot.empty():
		var preview_position: Vector2 = player.position
		_restore_player(player, _macro_editor_preview_snapshot)
		_set_macro_editor_preview_visual(player, preview_position, player.position)
	if _macro_editor_preview_renderer != null and is_instance_valid(_macro_editor_preview_renderer):
		_macro_editor_preview_renderer.pause_mode = _macro_editor_preview_renderer_pause_mode
		_macro_editor_preview_renderer.position_node.visible = bool(_macro_editor_preview_snapshot.get("preview_position_visible", true))
		_macro_editor_preview_renderer.spine_holder.visible = bool(_macro_editor_preview_snapshot.get("preview_spine_visible", true))
	_macro_editor_preview_renderer = null
	if _macro_editor_camera != null and is_instance_valid(_macro_editor_camera) and _macro_editor_camera.get_instance_id() == _macro_editor_preview_camera_id:
		_macro_editor_camera.position = _macro_editor_preview_camera_position
		_macro_editor_camera.zoom = _macro_editor_preview_camera_zoom
		_macro_editor_camera.current = true
		_macro_editor_camera.force_update_scroll()
		_refresh_macro_editor_presentation()
	_restore_macro_editor_presentation_processing()
	_macro_editor_camera = null
	_macro_editor_preview_active = false
	_macro_editor_preview_player_id = 0
	_macro_editor_preview_snapshot = {}
	_macro_editor_preview_camera_id = 0
	_macro_editor_freecam_detached = false
	get_tree().paused = _macro_editor_preview_was_tree_paused


func _macro_editor_level_visuals_ready(game: Node) -> bool:
	# The gameplay state can become playable before every deferred renderer and
	# level decoration has completed its first idle passes. Pausing the tree at
	# that moment leaves the editor looking like a bare collision-only level.
	if game == null or not ("level" in game) or game.get("level") == null:
		return false
	if ("has_loaded_level" in game) and not bool(game.get("has_loaded_level")):
		return false
	var level = game.get("level")
	if not ("loaded_level" in level) or level.get("loaded_level") == null:
		return false
	var loaded_level: Node = level.get("loaded_level")
	if not loaded_level.is_inside_tree() or loaded_level.get_child_count() == 0:
		return false
	if not ("client_renderer" in game) or game.get("client_renderer") == null:
		return false
	var renderer: Node = game.get("client_renderer")
	if not renderer.is_inside_tree() or renderer.get_node_or_null("Level_InterpolateRenderers") == null:
		return false
	var camera := _find_playback_camera()
	return camera != null and camera.is_inside_tree()


func _macro_editor_visual_signature(game: Node) -> String:
	if not _macro_editor_level_visuals_ready(game):
		return ""
	var level = game.get("level")
	var loaded_level: Node = level.get("loaded_level")
	var renderer: Node = game.get("client_renderer")
	return "%d:%d:%d:%d" % [loaded_level.get_instance_id(), _count_scene_nodes(loaded_level), renderer.get_instance_id(), _count_scene_nodes(renderer)]


func _count_scene_nodes(node: Node) -> int:
	if node == null:
		return 0
	var count := 1
	for child in node.get_children():
		count += _count_scene_nodes(child)
	return count
