extends "user://mod/tools/autoplay/AutoplayBot/04_navigation_point.gd"

func _navigation_edge_cost(from: Vector2, to: Vector2, relaxed: bool) -> float:
	var delta := to - from
	var abs_x := abs(delta.x)
	var abs_y := abs(delta.y)
	var distance := delta.length()
	if distance < 1.0:
		return INF
	var walk := abs_y <= (85.0 if relaxed else 58.0) and abs_x <= (260.0 if relaxed else NAV_MAX_WALK_X)
	var wall_step := abs_x <= (120.0 if relaxed else 82.0) and abs_y <= (205.0 if relaxed else NAV_MAX_WALL_STEP)
	var dash := abs_y <= (220.0 if relaxed else 145.0) and abs_x <= (680.0 if relaxed else NAV_MAX_DASH_X)
	var jump := abs_x <= (520.0 if relaxed else NAV_MAX_JUMP_X) and delta.y >= -(390.0 if relaxed else NAV_MAX_JUMP_UP) and delta.y <= (700.0 if relaxed else NAV_MAX_DROP)
	if not walk and not wall_step and not dash and not jump:
		return INF
	if not _navigation_arc_clear(from, to, walk, relaxed):
		return INF
	var cost := distance
	if delta.y < -20.0:
		cost += abs(delta.y) * 0.45
	if dash and not walk and not jump:
		cost += 80.0
	if relaxed:
		cost += 25.0
	return cost


func _navigation_arc_clear(from: Vector2, to: Vector2, walk: bool, relaxed: bool) -> bool:
	var delta := to - from
	var arc_height := 0.0
	if not walk:
		arc_height = clamp(72.0 + abs(delta.x) * 0.22 + max(0.0, -delta.y) * 0.18, 72.0, 230.0 if not relaxed else 290.0)
	for sample in range(1, NAV_ARC_SAMPLES):
		var t := float(sample) / float(NAV_ARC_SAMPLES)
		# Leave a wider untested landing/start pocket. Waypoints intentionally
		# sit beside a solid face, and testing that face again would reject every
		# legitimate takeoff and landing.
		if t < 0.18 or t > 0.82:
			continue
		var point: Vector2 = from.linear_interpolate(to, t)
		point.y -= sin(t * PI) * arc_height
		for hazard in _geometry_near_point(_hazard_spatial, point):
			if hazard.grow(NAV_HAZARD_MARGIN * (0.65 if relaxed else 1.0)).has_point(point):
				return false
		for solid in _geometry_near_point(_solid_spatial, point):
			if solid.grow(NAV_SOLID_MARGIN * (0.45 if relaxed else 1.0)).has_point(point):
				return false
	return true


func _reconstruct_navigation_route(points: Array, came_from: Dictionary, goal_index: int) -> Array:
	var indices := [goal_index]
	var current := goal_index
	while current != 0 and came_from.has(current):
		current = int(came_from[current])
		indices.append(current)
	if indices.back() != 0:
		return []
	indices.invert()
	var route := []
	for index in indices:
		route.append(points[int(index)])
	return route


func _rebuild_route_lengths() -> void:
	_route_lengths.clear()
	_route_lengths.append(0.0)
	_route_total_length = 0.0
	for i in range(1, _navigation_route.size()):
		_route_total_length += _navigation_route[i - 1].distance_to(_navigation_route[i])
		_route_lengths.append(_route_total_length)


func _update_route_index(position: Vector2) -> void:
	if _navigation_route.empty():
		_route_index = 0
		return
	_route_index = clamp(_route_index, 0, _navigation_route.size() - 1)
	while _route_index < _navigation_route.size() - 1:
		var target: Vector2 = _navigation_route[_route_index]
		var reached := position.distance_to(target) <= NAV_WAYPOINT_REACHED
		if not reached and _route_index > 0:
			var previous: Vector2 = _navigation_route[_route_index - 1]
			var segment := target - previous
			if segment.length_squared() > 0.001:
				var passed_plane := (position - target).dot(segment) >= 0.0
				var cross_track := abs((position - previous).cross(segment.normalized()))
				reached = passed_plane and cross_track <= NAV_WAYPOINT_REACHED * 1.8
		if not reached:
			break
		_route_index += 1
	# Landing arcs often pass close to more than one surface sample. Adopt the
	# furthest nearby forward point so the controller never turns back toward a
	# waypoint it has visibly cleared.
	var best_index := _route_index
	var best_distance := position.distance_to(_navigation_route[_route_index])
	for i in range(_route_index + 1, min(_navigation_route.size(), _route_index + 5)):
		var distance := position.distance_to(_navigation_route[i])
		if distance <= NAV_WAYPOINT_REACHED * 1.2 and distance < best_distance + 18.0:
			best_distance = distance
			best_index = i
	_route_index = best_index


func _route_progress_at(position: Vector2) -> float:
	if _navigation_route.size() < 2 or _route_lengths.size() != _navigation_route.size():
		return 0.0
	var best_distance_squared := INF
	var best_progress := 0.0
	for i in range(_navigation_route.size() - 1):
		var from: Vector2 = _navigation_route[i]
		var to: Vector2 = _navigation_route[i + 1]
		var segment := to - from
		var segment_length_squared := segment.length_squared()
		if segment_length_squared <= 0.001:
			continue
		var t := clamp((position - from).dot(segment) / segment_length_squared, 0.0, 1.0)
		var closest := from + segment * t
		var distance_squared := position.distance_squared_to(closest)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_progress = float(_route_lengths[i]) + sqrt(segment_length_squared) * t
	if _route_index > 0 and _route_index - 1 < _route_lengths.size():
		best_progress = max(best_progress, float(_route_lengths[_route_index - 1]))
	return best_progress


func _nearby_wall_direction(position: Vector2) -> int:
	var best_distance := 86.0
	var result := 0
	for rect_value in _geometry_near_point(_solid_spatial, position):
		var rect: Rect2 = rect_value
		if position.y < rect.position.y - 45.0 or position.y > rect.end.y + 45.0:
			continue
		var distance_to_left: float = rect.position.x - position.x
		if distance_to_left >= 8.0 and distance_to_left < best_distance:
			best_distance = distance_to_left
			result = 1
		var distance_to_right: float = position.x - rect.end.x
		if distance_to_right >= 8.0 and distance_to_right < best_distance:
			best_distance = distance_to_right
			result = -1
	return result


func _collect_finish_rects(game: Node) -> Array:
	var result := []
	if game == null or not ("level" in game) or game.level == null or not game.level.has_method("get_finish_lines"):
		return result
	for finish_line in game.level.call("get_finish_lines"):
		if finish_line != null and "world_rect" in finish_line:
			result.append(finish_line.world_rect)
	return result


func _nearest_finish_point(position: Vector2) -> Vector2:
	var best := position
	var best_distance := INF
	for rect in _finish_rects:
		var point := Vector2(clamp(position.x, rect.position.x, rect.end.x), clamp(position.y, rect.position.y, rect.end.y))
		var distance := position.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


func _distance_to_finish(position: Vector2) -> float:
	if _finish_rects.empty():
		return INF
	return position.distance_to(_nearest_finish_point(position))


func _connect_finish_signal(game: Node) -> void:
	_disconnect_finish_signal()
	_game = game
	if game != null and game.has_signal("player_hit_finish_line") and not game.is_connected("player_hit_finish_line", self, "_on_player_hit_finish_line"):
		game.connect("player_hit_finish_line", self, "_on_player_hit_finish_line")


func _disconnect_finish_signal() -> void:
	if _game != null and is_instance_valid(_game) and _game.has_signal("player_hit_finish_line") and _game.is_connected("player_hit_finish_line", self, "_on_player_hit_finish_line"):
		_game.disconnect("player_hit_finish_line", self, "_on_player_hit_finish_line")


func _on_player_hit_finish_line(player_id, _rank, _out_of, _finish_line_index, _position) -> void:
	if _game != null and _game.has_method("is_local_player") and bool(_game.call("is_local_player", int(player_id))):
		_finish_hit = true


func _on_stop_pressed() -> void:
	if is_active():
		_stop_internal("Autoplay stopped. Best attempt kept.", true)


func _on_play_best_pressed() -> void:
	if _best_frames.empty():
		_status_text = "There is no best attempt to play yet."
		_refresh_ui(true)
		return
	if not _is_supported_game():
		_status_text = "Play Best only works in a local Time Trial, editor test, or tutorial."
		_log(_status_text)
		_refresh_ui(true)
		return
	if is_active():
		_stop_internal("", false)
	_stop_other_input_modes()
	_saved_time_scale = Engine.time_scale
	_saved_time_scale_valid = true
	_game = tas_tool.call("_find_game")
	_game_id = _game.get_instance_id()
	_connect_finish_signal(_game)
	_replaying = true
	_learning = false
	_waiting_for_ready = false
	_trial_tick = 0
	_finish_hit = false
	var player = tas_tool.call("_get_local_player")
	if player == null:
		_stop_internal("Best-attempt replay couldn't find the local player.", true)
		return
	tas_tool.call("_restore_player", player, _start_snapshot)
	_restore_autoplay_world_state(_start_snapshot)
	tas_tool.set("_freeze_prev_alive", true)
	tas_tool.set("_freeze_last_alive_position", _start_snapshot.get("position", player.position))
	_settle_ticks = RESTORE_SETTLE_TICKS
	_status_text = "Preparing solved-run replay..." if _solved else "Preparing learned-prefix replay..."
	_log("Autoplay: replaying the solved run" if _solved else "Autoplay: replaying the learned prefix")
	_refresh_ui(true)


func _on_install_pressed() -> void:
	if _best_frames.empty() or _start_snapshot.empty() or _best_end_snapshot.empty():
		_status_text = "Finish at least one learning attempt before sending it to Macro Bot."
		_refresh_ui(true)
		return
	if is_active():
		_stop_internal("", false)
	_stop_other_input_modes()
	tas_tool.call("_clear_practice_data")
	var checkpoints := [_start_snapshot.duplicate(true), _best_end_snapshot.duplicate(true)]
	var segments := [_best_frames.duplicate(true)]
	tas_tool.set("_practice_checkpoints", checkpoints)
	tas_tool.set("_practice_segments", segments)
	tas_tool.set("_practice_current_segment", [])
	tas_tool.set("_practice_active", false)
	tas_tool.set("_practice_start_waiting", false)
	var markers := []
	var player = tas_tool.call("_get_local_player")
	if player != null:
		for snap in checkpoints:
			markers.append(tas_tool.call("_spawn_checkpoint_marker", player, snap["position"]))
	tas_tool.set("_practice_markers", markers)
	tas_tool.call("_restyle_practice_markers")
	tas_tool.call("_refresh_practice_ui")
	_status_text = "Solved run sent to Macro Bot as one editable segment." if _solved else "Learned prefix sent to Macro Bot; it does not reach the finish yet."
	_log("Autoplay: %s sent to Macro Bot (%d frames)" % ["solved run" if _solved else "learned prefix", _best_frames.size()])
	_refresh_ui(true)


func _on_reset_pressed() -> void:
	if is_active():
		_stop_internal("", false)
	_elites.clear()
	_novelty_archive.clear()
	_novelty_order.clear()
	_locked_frames.clear()
	_locked_finish_distance = INF
	_locked_projection = 0.0
	_locked_checkpoint = 0
	_best_score = -INF
	_best_genome.clear()
	_best_frames.clear()
	_best_end_snapshot.clear()
	_best_progress_tick = 0
	_best_finish_distance = INF
	_best_checkpoint = 0
	_solved = false
	_solved_ticks = 0
	_attempt = 0
	_start_snapshot.clear()
	_finish_rects.clear()
	_solid_rects.clear()
	_hazard_rects.clear()
	_checkpoint_rects.clear()
	_checkpoint_nav_points.clear()
	_checkpoint_node_ids.clear()
	_completed_checkpoint_node_ids.clear()
	_finish_nav_points.clear()
	_solid_spatial.clear()
	_hazard_spatial.clear()
	_nav_point_merge_buckets.clear()
	_nav_sampled_point_count = 0
	_navigation_route.clear()
	_route_lengths.clear()
	_route_total_length = 0.0
	_route_index = 0
	_route_is_relaxed = false
	_route_is_partial = false
	_route_goal_kind = "finish"
	_game_id = 0
	_resume_existing = false
	_status_text = "Learning reset. Start again from any position in a local level."
	_log("Autoplay: learning reset")
	_refresh_ui(true)


func _on_duration_delta(delta_seconds: int) -> void:
	_attempt_seconds = clamp(_attempt_seconds + delta_seconds, MIN_ATTEMPT_SECONDS, MAX_ATTEMPT_SECONDS)
	_refresh_ui(true)


func _on_speed_pressed() -> void:
	if is_equal_approx(_training_speed, 1.0):
		_training_speed = 2.0
	elif is_equal_approx(_training_speed, 2.0):
		_training_speed = 4.0
	else:
		_training_speed = 1.0
	if _learning:
		Engine.time_scale = _training_speed
	_refresh_ui(true)


func _stop_other_input_modes() -> void:
	if tas_tool == null:
		return
	if bool(tas_tool.get("_practice_active")):
		tas_tool.call("_stop_practice_mode")
	tas_tool.set("_practice_start_waiting", false)
	tas_tool.set("_practice_place_pending", false)
	if bool(tas_tool.get("_noclip_enabled")):
		tas_tool.call("_on_toggle_noclip_pressed")
	tas_tool.set("_jumpzone_armed", false)
	tas_tool.call("_release_all_injected_actions")


func _stop_internal(reason: String, write_log: bool) -> void:
	_release_inputs()
	_learning = false
	_replaying = false
	_waiting_for_ready = false
	_ready_ticks = 0
	_settle_ticks = 0
	_finish_hit = false
	_disconnect_finish_signal()
	if _saved_time_scale_valid:
		Engine.time_scale = _saved_time_scale
		_saved_time_scale_valid = false
	if not reason.empty():
		_status_text = reason
		if write_log:
			_log(reason)
	_refresh_ui(true)


func _release_inputs() -> void:
	if tas_tool != null:
		tas_tool.call("_release_practice_playback_injected_input")


func _is_supported_game() -> bool:
	if tas_tool == null:
		return false
	var game = tas_tool.call("_find_game")
	if game == null or not ("wp_game_data" in game) or game.wp_game_data == null:
		return false
	var data = game.wp_game_data
	var is_time_trial: bool = "is_time_trial" in data and bool(data.is_time_trial)
	var is_editor_test: bool = "is_level_editor" in data and bool(data.is_level_editor)
	var is_tutorial: bool = "is_tutorial" in data and bool(data.is_tutorial)
	return is_time_trial or is_editor_test or is_tutorial


func _physics_fps() -> float:
	return max(1.0, float(Engine.iterations_per_second))


func _horizon_ticks() -> int:
	return int(round(float(_attempt_seconds) * _physics_fps()))


func _progress_percent() -> float:
	if is_inf(_best_finish_distance) or _initial_finish_distance <= 0.0:
		return 0.0
	return clamp((_initial_finish_distance - _best_finish_distance) / _initial_finish_distance * 100.0, 0.0, 100.0)


func _result_text() -> String:
	if _best_frames.empty():
		return "No attempts yet."
	if _solved:
		return "SOLVED  •  %d physics probes  •  %.2fs  •  %d recorded frames" % [_attempt, float(_solved_ticks) / _physics_fps(), _best_frames.size()]
	return "Best verified path: %.1fs  •  checkpoint chain %d  •  %.1f%% closer  •  %d states kept  •  %d frontier states" % [float(_locked_frames.size()) / _physics_fps(), _best_checkpoint, _progress_percent(), _search_accepted, _search_frontier.size()]


func _refresh_ui(force: bool = false) -> void:
	if _status_label != null and (force or _ui_last_status != _status_text):
		_status_label.text = _status_text
		_ui_last_status = _status_text
	var result_text := _result_text()
	if _result_label != null and (force or _ui_last_result != result_text):
		_result_label.text = result_text
		_ui_last_result = result_text
	if _start_button != null:
		if _learning or _waiting_for_ready:
			_start_button.text = "■ Stop Learning"
		elif not _best_frames.empty():
			_start_button.text = "▶ Continue Learning"
		else:
			_start_button.text = "▶ Start Learning"
		_style(_start_button, COLOR_PINK if (_learning or _waiting_for_ready) else COLOR_BLUE)
	if _stop_button != null:
		_stop_button.disabled = not is_active()
	if _play_button != null:
		_play_button.text = "▶ Play Solved Run" if _solved else "▶ Play Learned Prefix"
		_play_button.disabled = _best_frames.empty() or is_active()
	if _install_button != null:
		_install_button.text = "Send Solved Run to Macro Bot" if _solved else "Send Prefix to Macro Bot"
		_install_button.disabled = _best_frames.empty()
	if _reset_button != null:
		_reset_button.disabled = _best_frames.empty() and _attempt == 0
	if _duration_label != null:
		_duration_label.text = "%ds" % _attempt_seconds
	if _speed_button != null:
		_speed_button.text = "Training Speed: %d×" % int(_training_speed)
		_style(_speed_button, COLOR_PINK if _learning else COLOR_BLUE)


func _style(button: Button, color: Color) -> void:
	if tas_tool != null and button != null:
		tas_tool.call("_style_button", button, color)
