extends "user://mod/tools/autoplay/AutoplayBot/02_advance_learning.gd"

func _light_snapshot(player) -> Dictionary:
	# A search frontier must be a complete restorable physics state, including
	# momentum, dash/wall timers, race time, and (when enabled in Macro Bot)
	# moving-world state. Starting from _start_snapshot here was the reason an
	# apparently learned mid-level branch could silently inherit spawn timing.
	var snap: Dictionary = tas_tool.call("_snapshot_player", player).duplicate(true)
	snap["alive"] = true
	snap["body_enabled"] = true
	snap["dead_counter"] = 0
	if "last_checkpoint" in player:
		snap["last_checkpoint"] = player.last_checkpoint
	if "last_checkpoint_anchor" in player:
		snap["last_checkpoint_anchor"] = player.last_checkpoint_anchor
	_capture_autoplay_world_state(snap)
	return snap


func _capture_autoplay_world_state(snapshot: Dictionary) -> void:
	# Frontier branches are stitched from different moments of the same level.
	# Their moving platforms must therefore be part of every restorable source
	# state even when the general Macro Bot option was left disabled.
	if tas_tool == null or _game == null or not is_instance_valid(_game):
		return
	snapshot["moving_world_state"] = tas_tool.call("_snapshot_moving_world_state", _game)


func _restore_autoplay_world_state(snapshot: Dictionary) -> void:
	if tas_tool != null and snapshot.has("moving_world_state"):
		tas_tool.call("_restore_moving_world_state", snapshot, true)


func _finish_trial(success: bool, died: bool) -> void:
	_release_inputs()
	var player = tas_tool.call("_get_local_player")
	if died or player == null or not player.alive:
		_prepare_next_trial()
		return
	var end_snapshot := _light_snapshot(player)
	var node := _build_search_node(end_snapshot, _trial_frames)
	_accept_search_node(node, success, "segment end")
	var path_ticks := int(node.get("path_ticks", 0))
	if success:
		_solved = true
		_solved_ticks = path_ticks
		_status_text = "Solved on attempt %d in %.2fs." % [_attempt, float(_trial_tick) / _physics_fps()]
		_status_text = "Solved after %d physics probes in %.2fs." % [_attempt, float(path_ticks) / _physics_fps()]
		_log("Autoplay: solved after %d real-physics probes; best route is ready" % _attempt)
		_stop_internal(_status_text, false)
		return
	_prepare_next_trial()


func _build_search_node(snapshot: Dictionary, segment_frames: Array) -> Dictionary:
	var checkpoint_ids: Array = _search_source.get("checkpoint_ids", [_start_checkpoint]).duplicate(false)
	if checkpoint_ids.empty():
		checkpoint_ids.append(_start_checkpoint)
	var checkpoint_id := int(snapshot.get("last_checkpoint", _start_checkpoint))
	if checkpoint_id != 0 and not checkpoint_ids.has(checkpoint_id):
		checkpoint_ids.append(checkpoint_id)
	var checkpoint_depth := max(0, checkpoint_ids.size() - 1)
	var path_ticks := int(_search_source.get("path_ticks", 0)) + segment_frames.size()
	var segments: Array = _search_source.get("segments", []).duplicate(false)
	var stored_segment: Array = segment_frames.duplicate(true)
	# A search edge starts from an independently restored world phase. Preserve
	# that phase on its first recorded frame so Autoplay replay—and a copy sent
	# to Macro Bot—recreates the same moving platforms at every stitched join.
	if not stored_segment.empty():
		var source_snapshot: Dictionary = _search_source.get("snapshot", {})
		if source_snapshot.has("moving_world_state") and stored_segment[0].has(FRAME_STATE_KEY):
			stored_segment[0][FRAME_STATE_KEY]["moving_world_state"] = source_snapshot["moving_world_state"].duplicate(true)
	segments.append(stored_segment)
	return {
		"snapshot": snapshot,
		"segments": segments,
		"path_ticks": path_ticks,
		"checkpoint_ids": checkpoint_ids,
		"checkpoint_depth": checkpoint_depth,
		"score": _search_state_score(snapshot, path_ticks, checkpoint_depth),
		"route_index": _route_index,
	}


func _accept_search_node(node: Dictionary, success: bool, reason: String) -> bool:
	var snapshot: Dictionary = node.get("snapshot", {})
	var state_key := _search_state_key(snapshot)
	var score := float(node.get("score", -INF))
	var accepted := success or not _search_visited.has(state_key) or score > float(_search_visited.get(state_key, -INF)) + 8.0
	if not accepted:
		return false
	_remember_search_state(state_key, score)
	_search_accepted += 1
	var path_ticks := int(node.get("path_ticks", 0))
	# A long level must not silently turn its current duration into a hard wall.
	# As soon as a verified path reaches that wall, extend the horizon and keep
	# this exact node in the frontier so learning continues from it immediately.
	if not success and path_ticks + SEARCH_DEFAULT_SEGMENT_TICKS >= _horizon_ticks() and _attempt_seconds < MAX_ATTEMPT_SECONDS:
		var previous_horizon := _attempt_seconds
		_attempt_seconds = min(MAX_ATTEMPT_SECONDS, _attempt_seconds + AUTO_HORIZON_EXTENSION_SECONDS)
		_log("Autoplay: verified path reached %ds; extending learning horizon to %ds" % [previous_horizon, _attempt_seconds])
		_refresh_ui(true)
	if not success and path_ticks < _horizon_ticks():
		_search_frontier.append(node)
		_prune_search_frontier()
	var checkpoint_depth := int(node.get("checkpoint_depth", 0))
	var reached_deeper_checkpoint := checkpoint_depth > _best_checkpoint
	var better_route := checkpoint_depth > _best_checkpoint or (checkpoint_depth == _best_checkpoint and score > _best_score + 4.0)
	if success or _best_frames.empty() or better_route:
		var position: Vector2 = snapshot.get("position", Vector2.ZERO)
		var finish_distance := _distance_to_finish(position)
		var route_progress := _route_progress_at(position)
		_best_score = score
		_best_frames = _assemble_search_frames(node)
		_locked_frames = _best_frames.duplicate(true)
		_best_end_snapshot = snapshot.duplicate(true)
		_best_progress_tick = path_ticks
		_best_finish_distance = finish_distance
		_best_checkpoint = checkpoint_depth
		_search_best_route_progress = max(_search_best_route_progress, route_progress)
		_search_best_finish_distance = min(_search_best_finish_distance, finish_distance)
		_locked_finish_distance = finish_distance
		_locked_projection = route_progress
		_locked_checkpoint = checkpoint_depth
		if reached_deeper_checkpoint:
			var checkpoint_id := int(snapshot.get("last_checkpoint", 0))
			_record_completed_checkpoint_goal(checkpoint_id, position)
			var replanned := _plan_navigation_route_from_geometry(position)
			if replanned:
				node["route_index"] = 1 if _navigation_route.size() > 1 else 0
				_log("Autoplay mapper: checkpoint reached; replanned %d points toward %s%s" % [_navigation_route.size(), _route_goal_kind, " (partial)" if _route_is_partial else ""])
		_log("Autoplay: kept %s at %.2fs (checkpoint chain %d, pos %.0f,%.0f, state %s)" % [reason, float(path_ticks) / _physics_fps(), checkpoint_depth, position.x, position.y, state_key])
	return true


func _record_completed_checkpoint_goal(checkpoint_id: int, position: Vector2) -> void:
	if checkpoint_id != 0 and _checkpoint_node_ids.has(checkpoint_id):
		_completed_checkpoint_node_ids[checkpoint_id] = true
		return
	# Older builds may expose the player's checkpoint ID without exposing the
	# same object ID on the LevelNode. In that case, associate the contact with
	# the closest sensor at the exact checkpoint snapshot.
	var closest_index := -1
	var closest_distance := INF
	for index in range(_checkpoint_nav_points.size()):
		if index < _checkpoint_rects.size() and _checkpoint_rects[index].grow(110.0).has_point(position):
			closest_index = index
			break
		var distance := position.distance_squared_to(_checkpoint_nav_points[index])
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	if closest_index >= 0 and closest_index < _checkpoint_node_ids.size():
		var node_id := int(_checkpoint_node_ids[closest_index])
		if node_id != 0:
			_completed_checkpoint_node_ids[node_id] = true


func _search_state_score(snapshot: Dictionary, path_ticks: int, checkpoint_depth: int) -> float:
	var position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var finish_distance := _distance_to_finish(position)
	var route_progress := _route_progress_at(position)
	var grounded := float(snapshot.get("stick_to_ground_timer", 0.0)) > 0.0
	var on_wall := bool(snapshot.get("wallslide_counter", false))
	var start_position: Vector2 = _start_snapshot.get("position", position)
	var score := float(checkpoint_depth) * 50000.0
	# Finish distance is deliberately weak: many real layouts first travel far
	# away from the finish. Reached checkpoints and spatial exploration are the
	# reliable signals; a mapped route, when available, only breaks ties.
	score += clamp(_initial_finish_distance - finish_distance, -2500.0, 2500.0) * 0.20
	score += route_progress * (0.30 if _navigation_route.size() > 1 else 0.0)
	score += min(start_position.distance_to(position), 5000.0) * 0.06
	score += 90.0 if grounded else 0.0
	score += 70.0 if on_wall else 0.0
	score += 25.0 if int(snapshot.get("dash_cooldown", 0)) <= 0 else 0.0
	score += min(float(path_ticks), 360.0) * 0.08
	return score


func _search_state_key(snapshot: Dictionary) -> String:
	var position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var velocity: Vector2 = snapshot.get("linear_velocity", Vector2.ZERO)
	var position_x := int(round(position.x / SEARCH_POSITION_CELL))
	var position_y := int(round(position.y / SEARCH_POSITION_CELL))
	var velocity_x := int(round(velocity.x / SEARCH_VELOCITY_CELL))
	var velocity_y := int(round(velocity.y / SEARCH_VELOCITY_CELL))
	var grounded := 1 if float(snapshot.get("stick_to_ground_timer", 0.0)) > 0.0 else 0
	var on_wall := 1 if bool(snapshot.get("wallslide_counter", false)) else 0
	var dash_cooldown_bucket := int(round(float(snapshot.get("dash_cooldown", 0)) / 6.0))
	var checkpoint := int(snapshot.get("last_checkpoint", _start_checkpoint))
	# Static levels must not manufacture sixteen "different" copies of the
	# exact same stuck position merely because the Time Trial clock advanced.
	# Preserve phase only when a restorable moving-world snapshot proves that
	# timing is actually part of the state.
	var play_phase := 0
	if _moving_world_state_has_timing(snapshot):
		# Four broad phases keep moving-platform timing searchable without
		# allowing clock differences to crowd out actual movement states.
		play_phase = int(floor(float(snapshot.get("play_time", 0.0)))) % 4
	return "%d:%d:%d:%d:%d:%d:%d:%d:%d" % [checkpoint, position_x, position_y, velocity_x, velocity_y, grounded, on_wall, dash_cooldown_bucket, play_phase]


func _moving_world_state_has_timing(snapshot: Dictionary) -> bool:
	var moving_world_state = snapshot.get("moving_world_state", [])
	if typeof(moving_world_state) != TYPE_ARRAY:
		return false
	for entry_value in moving_world_state:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("kind", "")) == "animation" and bool(entry.get("playing", false)) and not str(entry.get("animation", "")).empty():
			return true
		var linear_velocity = entry.get("linear_velocity", Vector2.ZERO)
		if typeof(linear_velocity) == TYPE_VECTOR2 and linear_velocity.length_squared() > 1.0:
			return true
		if abs(float(entry.get("angular_velocity", 0.0))) > 0.01:
			return true
	return false


func _remember_search_state(key: String, score: float) -> void:
	if not _search_visited.has(key):
		_search_visited_order.append(key)
	_search_visited[key] = score
	while _search_visited_order.size() > SEARCH_VISITED_LIMIT:
		var oldest = _search_visited_order.pop_front()
		_search_visited.erase(oldest)


func _pop_search_frontier() -> Dictionary:
	if _search_frontier.empty():
		return {}
	var selected_index := 0
	# Rotate between several objectives. No single geometric number describes
	# progress on wraparounds, vertical shafts, gravity rooms, or intentional
	# backtracking, so half the expansions pursue something other than score.
	var selection_mode := _search_expansions % 12
	if selection_mode == 5:
		selected_index = rng.randi_range(0, _search_frontier.size() - 1)
	elif selection_mode == 3:
		var deepest := int(_search_frontier[0].get("checkpoint_depth", 0))
		var deepest_score := float(_search_frontier[0].get("score", -INF))
		for i in range(1, _search_frontier.size()):
			var depth := int(_search_frontier[i].get("checkpoint_depth", 0))
			var score := float(_search_frontier[i].get("score", -INF))
			if depth > deepest or (depth == deepest and score > deepest_score):
				deepest = depth
				deepest_score = score
				selected_index = i
	elif selection_mode == 4:
		var longest := int(_search_frontier[0].get("path_ticks", 0))
		for i in range(1, _search_frontier.size()):
			var path_ticks := int(_search_frontier[i].get("path_ticks", 0))
			if path_ticks > longest:
				longest = path_ticks
				selected_index = i
	elif selection_mode == 6:
		var start_position: Vector2 = _start_snapshot.get("position", Vector2.ZERO)
		var farthest := start_position.distance_squared_to(_search_frontier[0].get("snapshot", {}).get("position", start_position))
		for i in range(1, _search_frontier.size()):
			var position: Vector2 = _search_frontier[i].get("snapshot", {}).get("position", start_position)
			var distance := start_position.distance_squared_to(position)
			if distance > farthest:
				farthest = distance
				selected_index = i
	elif selection_mode == 7:
		# Oldest retained state gives a breadth-first pass through regions that a
		# greedy or depth-first choice has not expanded yet.
		selected_index = 0
	elif selection_mode >= 8:
		# Four direction-neutral exploration passes are essential for layouts
		# that intentionally travel away from the finish or climb a wall before
		# turning back. Each extreme is selected directly from verified physics
		# states, so this does not assume which direction the level progresses.
		var selected_position: Vector2 = _search_frontier[0].get("snapshot", {}).get("position", Vector2.ZERO)
		var extreme_value := selected_position.y if selection_mode <= 9 else selected_position.x
		for i in range(1, _search_frontier.size()):
			var position: Vector2 = _search_frontier[i].get("snapshot", {}).get("position", Vector2.ZERO)
			var value := position.y if selection_mode <= 9 else position.x
			var wants_minimum := selection_mode == 8 or selection_mode == 10
			if (wants_minimum and value < extreme_value) or (not wants_minimum and value > extreme_value):
				extreme_value = value
				selected_index = i
	else:
		var best_score := float(_search_frontier[0].get("score", -INF))
		for i in range(1, _search_frontier.size()):
			var score := float(_search_frontier[i].get("score", -INF))
			if score > best_score:
				best_score = score
				selected_index = i
	var selected: Dictionary = _search_frontier[selected_index]
	_search_frontier.remove(selected_index)
	return selected


func _prune_search_frontier() -> void:
	while _search_frontier.size() > SEARCH_FRONTIER_LIMIT:
		var region_counts := {}
		for node in _search_frontier:
			var region_key := _frontier_region_key(node)
			region_counts[region_key] = int(region_counts.get(region_key, 0)) + 1
		var worst_index := -1
		var worst_score := INF
		# First remove only excess states from crowded regions. This keeps the
		# frontier spread across the map even when "toward finish" is misleading.
		for i in range(_search_frontier.size()):
			var region_key := _frontier_region_key(_search_frontier[i])
			if int(region_counts.get(region_key, 0)) <= 3:
				continue
			var score := float(_search_frontier[i].get("score", INF))
			if score < worst_score:
				worst_score = score
				worst_index = i
		if worst_index < 0:
			worst_index = 0
			worst_score = float(_search_frontier[0].get("score", INF))
			for i in range(1, _search_frontier.size()):
				var score := float(_search_frontier[i].get("score", INF))
				if score < worst_score:
					worst_score = score
					worst_index = i
		_search_frontier.remove(worst_index)


func _frontier_region_key(node: Dictionary) -> String:
	var snapshot: Dictionary = node.get("snapshot", {})
	var position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var checkpoint := int(snapshot.get("last_checkpoint", _start_checkpoint))
	var region_size := SEARCH_POSITION_CELL * 4.0
	return "%d:%d:%d" % [checkpoint, int(floor(position.x / region_size)), int(floor(position.y / region_size))]


func _make_search_actions(snapshot: Dictionary) -> Array:
	var position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var preferred := _physics_search_preferred_direction(position)
	var directions := [preferred, -preferred]
	var actions := []
	var dash_ready := int(snapshot.get("dash_cooldown", 0)) <= 0
	var grounded := float(snapshot.get("stick_to_ground_timer", 0.0)) > 0.0
	var on_wall := bool(snapshot.get("wallslide_counter", false))
	if on_wall:
		# A wall jump is not a fixed left/right macro. The useful direction
		# changes after launch: first move away to gain clearance, then return
		# toward the face so the next jump can fire from a genuinely higher
		# contact. The old periodic direction switch did the opposite at the
		# important moment and repeatedly fell back to the same wall state.
		var wall_direction := _nearby_wall_direction(position)
		if wall_direction == 0:
			wall_direction = preferred
		actions.append({"name": "wall pop away", "dir": -wall_direction, "jump": "tap", "dash_tick": -1, "reverse_tick": -1, "ticks": 10})
		actions.append({"name": "wall high launch", "dir": -wall_direction, "jump": "hold", "dash_tick": -1, "reverse_tick": -1, "ticks": 16})
		for away_ticks in [4, 7, 10, 13]:
			actions.append({
				"name": "same-wall climb return %d" % away_ticks,
				"control": "same_wall_climb",
				"wall_dir": wall_direction,
				"away_ticks": away_ticks,
				"jump_hold_ticks": 7,
				"ticks": 54,
			})
		actions.append({
			"name": "alternating-wall climb",
			"control": "alternating_wall_climb",
			"wall_dir": wall_direction,
			"jump_hold_ticks": 7,
			"ticks": 54,
		})
		if dash_ready:
			actions.append({"name": "wall jump dash", "dir": -wall_direction, "jump": "tap", "dash_tick": 5, "reverse_tick": 9, "ticks": 22})
		# Releasing everything is still useful for dropping to a lower route.
		actions.append({"name": "wall drop", "dir": 0, "jump": "none", "dash_tick": -1, "reverse_tick": -1, "ticks": 14})
		return actions
	for direction_value in directions:
		var direction := int(direction_value)
		var side_name := "forward" if direction == preferred else "reverse"
		if grounded:
			# Sample the rise, apex approach, and a direction release separately.
			actions.append({"name": side_name + " short run", "dir": direction, "jump": "none", "dash_tick": -1, "reverse_tick": -1, "ticks": 14})
			actions.append({"name": side_name + " tap jump", "dir": direction, "jump": "tap", "dash_tick": -1, "reverse_tick": -1, "ticks": 16})
			actions.append({"name": side_name + " held jump", "dir": direction, "jump": "hold", "dash_tick": -1, "reverse_tick": -1, "ticks": 26})
			actions.append({"name": side_name + " jump then coast", "dir": direction, "jump": "tap", "dash_tick": -1, "reverse_tick": -1, "dir_stop_tick": 11, "ticks": 28})
			if dash_ready:
				actions.append({"name": side_name + " jump dash", "dir": direction, "jump": "tap", "dash_tick": 7, "reverse_tick": -1, "ticks": 22})
		else:
			# In open air, steering and landing preparation are useful; repeatedly
			# trying a fresh ground jump is not. This makes each expansion cheaper.
			actions.append({"name": side_name + " air steer", "dir": direction, "jump": "none", "dash_tick": -1, "reverse_tick": -1, "ticks": 12})
			actions.append({"name": side_name + " long air steer", "dir": direction, "jump": "none", "dash_tick": -1, "reverse_tick": -1, "ticks": 26})
			actions.append({"name": side_name + " air reverse", "dir": direction, "jump": "none", "dash_tick": -1, "reverse_tick": 10, "ticks": 24})
			actions.append({"name": side_name + " jump-zone hold", "dir": direction, "jump": "hold", "dash_tick": -1, "reverse_tick": -1, "ticks": 22})
			actions.append({"name": side_name + " land and jump", "dir": direction, "jump": "on_land", "dash_tick": -1, "reverse_tick": -1, "ticks": 34})
			if dash_ready:
				actions.append({"name": side_name + " air dash", "dir": direction, "jump": "none", "dash_tick": 4, "reverse_tick": -1, "ticks": 20})
	# Neutral branches matter for falling onto a platform, allowing a moving
	# obstacle to pass, or releasing movement before a precise wall jump.
	actions.append({"name": "short coast", "dir": 0, "jump": "none", "dash_tick": -1, "reverse_tick": -1, "ticks": 14})
	actions.append({"name": "long coast", "dir": 0, "jump": "none", "dash_tick": -1, "reverse_tick": -1, "ticks": 34})
	if grounded or on_wall:
		actions.append({"name": "neutral jump", "dir": 0, "jump": "tap", "dash_tick": -1, "reverse_tick": -1, "ticks": 18})
	return actions


func _physics_search_preferred_direction(position: Vector2) -> int:
	var target := _nearest_finish_point(position)
	if _navigation_route.size() > 1:
		var nearest_index := 0
		var nearest_distance := INF
		for i in range(_navigation_route.size()):
			var distance := position.distance_squared_to(_navigation_route[i])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = i
		target = _navigation_route[min(nearest_index + 1, _navigation_route.size() - 1)]
	if abs(target.x - position.x) < 12.0:
		return _preferred_direction
	return 1 if target.x > position.x else -1
