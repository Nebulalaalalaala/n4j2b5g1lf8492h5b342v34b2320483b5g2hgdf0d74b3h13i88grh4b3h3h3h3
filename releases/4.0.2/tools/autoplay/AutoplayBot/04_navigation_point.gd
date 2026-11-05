extends "user://mod/tools/autoplay/AutoplayBot/03_search_world.gd"

func _search_frame_for_tick(action: Dictionary, tick: int, player) -> Dictionary:
	var control := str(action.get("control", ""))
	if control == "same_wall_climb" or control == "alternating_wall_climb":
		return _reactive_wall_climb_frame(action, tick, player, control == "alternating_wall_climb")
	var direction := int(action.get("dir", 0))
	var reverse_tick := int(action.get("reverse_tick", -1))
	if reverse_tick >= 0 and tick >= reverse_tick:
		direction = -direction
	var dir_stop_tick := int(action.get("dir_stop_tick", -1))
	if dir_stop_tick >= 0 and tick >= dir_stop_tick:
		direction = 0
	var switch_period := int(action.get("switch_period", 0))
	if switch_period > 0 and int(tick / switch_period) % 2 == 1:
		direction = -direction
	var jump_mode := str(action.get("jump", "none"))
	var jumping := false
	match jump_mode:
		"tap":
			jumping = tick < 5
		"hold":
			jumping = tick < 19
		"late":
			jumping = tick >= 8 and tick < 18
		"on_land":
			var grounded_now := float(player.stick_to_ground_timer) > 0.0 if player != null and "stick_to_ground_timer" in player else false
			if grounded_now and not bool(action.get("_land_jump_used", false)):
				action["_land_jump_used"] = true
				action["_land_jump_until"] = tick + 7
			jumping = tick < int(action.get("_land_jump_until", -1))
		"double":
			jumping = tick < 5 or (tick >= 16 and tick < 22)
		"wall":
			jumping = tick < 5 or (tick >= 11 and tick < 16) or (tick >= 22 and tick < 27)
	var dash_edge := tick == int(action.get("dash_tick", -1))
	var frame := {
		ACTION_LEFT: direction < 0,
		ACTION_RIGHT: direction > 0,
		ACTION_JUMP: jumping,
		ACTION_DASH: dash_edge,
	}
	if dash_edge:
		frame[DASH_DIRECTION_KEY] = direction >= 0 if direction != 0 else _preferred_direction >= 0
	return frame


func _reactive_wall_climb_frame(action: Dictionary, tick: int, player, alternating: bool) -> Dictionary:
	var on_wall := bool(player.wallslide_counter) if player != null and "wallslide_counter" in player else false
	var wall_direction := int(action.get("_active_wall_dir", action.get("wall_dir", _preferred_direction)))
	if on_wall and player != null:
		var sensed_direction := _nearby_wall_direction(player.position)
		if sensed_direction != 0:
			wall_direction = sensed_direction
	if wall_direction == 0:
		wall_direction = _preferred_direction if _preferred_direction != 0 else 1
	action["_active_wall_dir"] = wall_direction

	var previous_on_wall := bool(action.get("_previous_on_wall", false))
	var launch_tick := int(action.get("_launch_tick", -1000))
	var relaunch_cooldown := int(action.get("relaunch_cooldown", 9))
	# Fire once at the restored wall state, then once on every new wall contact.
	# The cooldown guarantees a real released-jump gap between both edges.
	if on_wall and (tick == 0 or not previous_on_wall) and tick - launch_tick >= relaunch_cooldown:
		launch_tick = tick
		action["_launch_tick"] = launch_tick
		action["_launch_wall_dir"] = wall_direction
		action["_jump_until"] = tick + int(action.get("jump_hold_ticks", 7))
	action["_previous_on_wall"] = on_wall

	var launch_wall_direction := int(action.get("_launch_wall_dir", wall_direction))
	var since_launch := tick - launch_tick
	var direction := wall_direction
	if launch_tick > -1000:
		if alternating:
			# In a shaft, keep crossing away from the wall just used; sensing a
			# new contact flips wall_direction and launches toward the other side.
			direction = -launch_wall_direction
		else:
			var away_ticks := int(action.get("away_ticks", 7))
			direction = -launch_wall_direction if since_launch < away_ticks else launch_wall_direction
	var jumping := tick < int(action.get("_jump_until", -1))
	return {
		ACTION_LEFT: direction < 0,
		ACTION_RIGHT: direction > 0,
		ACTION_JUMP: jumping,
		ACTION_DASH: false,
	}


func _assemble_search_frames(node: Dictionary) -> Array:
	var result := []
	for segment in node.get("segments", []):
		for frame in segment:
			result.append(frame.duplicate(true))
	return result


func _build_navigation_route(game: Node, start_position: Vector2) -> bool:
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
	_navigation_route.clear()
	_route_lengths.clear()
	_route_total_length = 0.0
	_route_is_relaxed = false
	_route_is_partial = false
	_route_goal_kind = "finish"
	_nav_sampled_point_count = 0
	_search_frontier.clear()
	_search_visited.clear()
	_search_visited_order.clear()
	_search_source.clear()
	_search_pending_actions.clear()
	_search_action.clear()
	_search_expansions = 0
	_search_accepted = 0
	_search_best_route_progress = 0.0
	_search_best_finish_distance = INF
	_collect_navigation_geometry(game)
	_rebuild_geometry_spatial_index()
	return _plan_navigation_route_from_geometry(start_position)


func _plan_navigation_route_from_geometry(start_position: Vector2) -> bool:
	_nav_point_merge_buckets.clear()
	_navigation_route.clear()
	_route_lengths.clear()
	_route_total_length = 0.0
	_route_is_relaxed = false
	_route_is_partial = false
	_route_goal_kind = "finish"
	var points := []
	_add_navigation_point(points, start_position)
	# Goals are inserted before surfaces so even an enormous community level
	# cannot lose them when the bounded sampling budget is reached.
	var checkpoint_indices := []
	for checkpoint_index in range(_checkpoint_nav_points.size()):
		var checkpoint_id := int(_checkpoint_node_ids[checkpoint_index]) if checkpoint_index < _checkpoint_node_ids.size() else 0
		if checkpoint_id != 0 and _completed_checkpoint_node_ids.has(checkpoint_id):
			continue
		var checkpoint_point: Vector2 = _checkpoint_nav_points[checkpoint_index]
		# A checkpoint is a wide sensor on many maps. Do not immediately route
		# back into the same sensor after its real ID has just changed.
		if checkpoint_index < _checkpoint_rects.size() and _checkpoint_rects[checkpoint_index].grow(90.0).has_point(start_position):
			continue
		if start_position.distance_to(checkpoint_point) <= NAV_WAYPOINT_REACHED:
			continue
		checkpoint_indices.append(_add_navigation_point(points, checkpoint_point))
	var finish_indices := []
	for point in _finish_nav_points:
		finish_indices.append(_add_navigation_point(points, point))
	for rect in _solid_rects:
		_sample_solid_navigation_points(rect, points)
		if points.size() >= NAV_MAX_POINTS:
			break
	_nav_sampled_point_count = points.size()

	# Prefer a complete finish route. On heavily animated or split-lane levels
	# the static graph may not connect that far, so a reachable checkpoint becomes
	# an intermediate landmark. A real checkpoint contact replans from that newly
	# proven physics state instead of continuing to aim at the old landmark.
	_navigation_route = _astar_navigation_route(points, finish_indices, false)
	if _navigation_route.empty():
		_navigation_route = _astar_navigation_route(points, finish_indices, true)
		_route_is_relaxed = not _navigation_route.empty()
	if _navigation_route.empty() and not checkpoint_indices.empty():
		_route_goal_kind = "reachable checkpoint"
		_navigation_route = _astar_navigation_route(points, checkpoint_indices, false)
		if _navigation_route.empty():
			_navigation_route = _astar_navigation_route(points, checkpoint_indices, true)
			_route_is_relaxed = not _navigation_route.empty()
	# Hundreds of moving pieces can make a complete static route impossible.
	# Preserve the best connected prefix instead of throwing away all map
	# guidance and blindly wandering from the spawn.
	if _navigation_route.empty():
		var partial_goals: Array = checkpoint_indices.duplicate(false)
		for finish_index in finish_indices:
			if not partial_goals.has(finish_index):
				partial_goals.append(finish_index)
		_navigation_route = _astar_navigation_route(points, partial_goals, true, true)
		_route_is_relaxed = not _navigation_route.empty()
		_route_is_partial = not _navigation_route.empty()
		_route_goal_kind = "reachable route prefix"
	if _navigation_route.empty():
		return false
	_rebuild_route_lengths()
	_route_index = 1 if _navigation_route.size() > 1 else 0
	return true


func _collect_navigation_geometry(game: Node) -> void:
	if game == null or not ("level" in game) or game.level == null:
		return
	var level = game.level
	var level_nodes := []
	if "id_to_nodes" in level and typeof(level.id_to_nodes) == TYPE_DICTIONARY:
		for key in level.id_to_nodes:
			level_nodes.append(level.id_to_nodes[key])
	elif "loaded_level" in level and level.loaded_level != null:
		level_nodes = level.loaded_level.get_children()
	for level_node in level_nodes:
		if level_node == null or not ("node_type" in level_node) or not ("world_rect" in level_node):
			continue
		var node_type := str(level_node.node_type)
		var rect_value = level_node.world_rect
		if typeof(rect_value) != TYPE_RECT2:
			continue
		var rect: Rect2 = rect_value
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if node_type == "finish_line":
			_finish_nav_points.append(_sensor_navigation_point(level_node, rect))
		elif node_type == "checkpoint":
			_checkpoint_rects.append(rect)
			_checkpoint_nav_points.append(_sensor_navigation_point(level_node, rect))
			# WPGame stores checkpoint IDs as level_node_index + 1 (the same
			# convention it uses for starting positions), not the Node instance ID.
			_checkpoint_node_ids.append(int(level_node.level_node_index) + 1 if "level_node_index" in level_node else 0)
		elif node_type in HAZARD_NODE_TYPES or (("collision_type" in level_node) and int(level_node.collision_type) == 2):
			_hazard_rects.append(rect)
		elif node_type in SOLID_NODE_TYPES:
			_solid_rects.append(rect)


func _sensor_navigation_point(level_node, rect: Rect2) -> Vector2:
	var shape_rotation := int(level_node.shape_rotation) if "shape_rotation" in level_node else 0
	var normal := Vector2.UP.rotated(float(shape_rotation) * PI * 0.5)
	var half_extent := 0.5 * (abs(normal.x) * rect.size.x + abs(normal.y) * rect.size.y)
	return rect.get_center() + normal * (half_extent + NAV_PLAYER_CLEARANCE)


func _rebuild_geometry_spatial_index() -> void:
	_solid_spatial.clear()
	_hazard_spatial.clear()
	for rect_value in _solid_rects:
		_index_geometry_rect(_solid_spatial, rect_value)
	for rect_value in _hazard_rects:
		_index_geometry_rect(_hazard_spatial, rect_value)


func _index_geometry_rect(index: Dictionary, rect_value) -> void:
	var rect: Rect2 = rect_value
	var min_x := int(floor((rect.position.x - NAV_HAZARD_MARGIN) / NAV_GEOMETRY_BUCKET_SIZE))
	var max_x := int(floor((rect.end.x + NAV_HAZARD_MARGIN) / NAV_GEOMETRY_BUCKET_SIZE))
	var min_y := int(floor((rect.position.y - NAV_HAZARD_MARGIN) / NAV_GEOMETRY_BUCKET_SIZE))
	var max_y := int(floor((rect.end.y + NAV_HAZARD_MARGIN) / NAV_GEOMETRY_BUCKET_SIZE))
	for bucket_x in range(min_x, max_x + 1):
		for bucket_y in range(min_y, max_y + 1):
			var key := "%d:%d" % [bucket_x, bucket_y]
			if not index.has(key):
				index[key] = []
			index[key].append(rect)


func _geometry_near_point(index: Dictionary, point: Vector2) -> Array:
	var bucket_x := int(floor(point.x / NAV_GEOMETRY_BUCKET_SIZE))
	var bucket_y := int(floor(point.y / NAV_GEOMETRY_BUCKET_SIZE))
	return index.get("%d:%d" % [bucket_x, bucket_y], [])


func _sample_solid_navigation_points(rect: Rect2, points: Array) -> void:
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y
	var inset_x := min(NAV_PLAYER_CLEARANCE, rect.size.x * 0.35)
	var inset_y := min(NAV_PLAYER_CLEARANCE, rect.size.y * 0.35)
	var top_left := Vector2(left + inset_x, top - NAV_PLAYER_CLEARANCE)
	var top_right := Vector2(right - inset_x, top - NAV_PLAYER_CLEARANCE)
	_add_navigation_point_if_safe(points, top_left)
	_add_navigation_point_if_safe(points, top_right)
	var x := top_left.x + NAV_SAMPLE_STEP
	while x < top_right.x and points.size() < NAV_MAX_POINTS:
		_add_navigation_point_if_safe(points, Vector2(x, top - NAV_PLAYER_CLEARANCE))
		x += NAV_SAMPLE_STEP

	# Tall block faces become wall-climb waypoints. These are what let the
	# route describe alternating wall jumps rather than pretending the player
	# can fly vertically through open space.
	if rect.size.y >= NAV_SAMPLE_STEP * 0.75:
		var y := top + inset_y
		while y <= bottom - inset_y and points.size() < NAV_MAX_POINTS:
			_add_navigation_point_if_safe(points, Vector2(left - NAV_PLAYER_CLEARANCE, y))
			_add_navigation_point_if_safe(points, Vector2(right + NAV_PLAYER_CLEARANCE, y))
			y += NAV_SAMPLE_STEP


func _add_navigation_point_if_safe(points: Array, point: Vector2) -> int:
	if points.size() >= NAV_MAX_POINTS or not _navigation_point_safe(point):
		return -1
	return _add_navigation_point(points, point)


func _add_navigation_point(points: Array, point: Vector2) -> int:
	var merge_distance_squared := NAV_POINT_MERGE_DISTANCE * NAV_POINT_MERGE_DISTANCE
	var center_x := int(floor(point.x / NAV_POINT_MERGE_DISTANCE))
	var center_y := int(floor(point.y / NAV_POINT_MERGE_DISTANCE))
	for bucket_x in range(center_x - 1, center_x + 2):
		for bucket_y in range(center_y - 1, center_y + 2):
			var nearby_key := "%d:%d" % [bucket_x, bucket_y]
			for index_value in _nav_point_merge_buckets.get(nearby_key, []):
				var index := int(index_value)
				if point.distance_squared_to(points[index]) <= merge_distance_squared:
					return index
	points.append(point)
	var new_index := points.size() - 1
	var bucket_key := "%d:%d" % [center_x, center_y]
	if not _nav_point_merge_buckets.has(bucket_key):
		_nav_point_merge_buckets[bucket_key] = []
	_nav_point_merge_buckets[bucket_key].append(new_index)
	return new_index


func _navigation_point_safe(point: Vector2) -> bool:
	for hazard in _geometry_near_point(_hazard_spatial, point):
		if hazard.grow(NAV_HAZARD_MARGIN).has_point(point):
			return false
	for solid in _geometry_near_point(_solid_spatial, point):
		if solid.grow(NAV_SOLID_MARGIN).has_point(point):
			return false
	return true


func _astar_navigation_route(points: Array, finish_indices: Array, relaxed: bool, allow_partial := false) -> Array:
	if points.empty() or finish_indices.empty():
		return []
	var point_buckets := {}
	for point_index in range(points.size()):
		var bucket_key := _navigation_point_bucket_key(points[point_index])
		if not point_buckets.has(bucket_key):
			point_buckets[bucket_key] = []
		point_buckets[bucket_key].append(point_index)
	# The old implementation scanned the whole open list to find its cheapest
	# entry. That becomes quadratic and forced the mapper to stop at 1,800
	# points—too early for the 2,000+ object community level in the failing
	# report. A small binary heap lets the full sampled layout participate.
	var open := []
	var closed := {}
	var came_from := {}
	var cost_so_far := {0: 0.0}
	var initial_heuristic := _navigation_heuristic(points[0], points, finish_indices)
	var best_partial_index := 0
	var best_partial_heuristic := initial_heuristic
	_navigation_heap_push(open, [initial_heuristic, 0])
	while not open.empty():
		var current_entry: Array = _navigation_heap_pop(open)
		var current: int = int(current_entry[1])
		if closed.has(current):
			continue
		if finish_indices.has(current):
			return _reconstruct_navigation_route(points, came_from, current)
		closed[current] = true
		var current_heuristic := _navigation_heuristic(points[current], points, finish_indices)
		if current_heuristic < best_partial_heuristic:
			best_partial_heuristic = current_heuristic
			best_partial_index = current
		var nearby_indices := _nearby_navigation_indices(points[current], point_buckets)
		for neighbor_value in nearby_indices:
			var neighbor := int(neighbor_value)
			if neighbor == current or closed.has(neighbor):
				continue
			var edge_cost := _navigation_edge_cost(points[current], points[neighbor], relaxed)
			if is_inf(edge_cost):
				continue
			var new_cost := float(cost_so_far[current]) + edge_cost
			if not cost_so_far.has(neighbor) or new_cost < float(cost_so_far[neighbor]):
				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current
				var priority := new_cost + _navigation_heuristic(points[neighbor], points, finish_indices)
				_navigation_heap_push(open, [priority, neighbor])
	if allow_partial and best_partial_index != 0 and best_partial_heuristic < initial_heuristic - NAV_WAYPOINT_REACHED:
		return _reconstruct_navigation_route(points, came_from, best_partial_index)
	return []


func _navigation_heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if float(heap[parent][0]) <= float(heap[index][0]):
			break
		var swap = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


func _navigation_heap_pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last = heap.pop_back()
	if heap.empty():
		return first
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var smallest := left
		if right < heap.size() and float(heap[right][0]) < float(heap[left][0]):
			smallest = right
		if float(heap[index][0]) <= float(heap[smallest][0]):
			break
		var swap = heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = swap
		index = smallest
	return first


func _navigation_point_bucket_key(point: Vector2) -> String:
	return "%d:%d" % [int(floor(point.x / NAV_POINT_BUCKET_SIZE)), int(floor(point.y / NAV_POINT_BUCKET_SIZE))]


func _nearby_navigation_indices(point: Vector2, buckets: Dictionary) -> Array:
	var result := []
	var center_x := int(floor(point.x / NAV_POINT_BUCKET_SIZE))
	var center_y := int(floor(point.y / NAV_POINT_BUCKET_SIZE))
	for bucket_x in range(center_x - 1, center_x + 2):
		for bucket_y in range(center_y - 1, center_y + 2):
			var key := "%d:%d" % [bucket_x, bucket_y]
			if buckets.has(key):
				result += buckets[key]
	return result


func _navigation_heuristic(point: Vector2, points: Array, finish_indices: Array) -> float:
	var best := INF
	for finish_index in finish_indices:
		best = min(best, point.distance_to(points[int(finish_index)]))
	return best * 0.72
