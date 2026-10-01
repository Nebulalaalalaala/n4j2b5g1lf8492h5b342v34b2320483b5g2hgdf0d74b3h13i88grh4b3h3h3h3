extends "user://mod/tools/autoplay/AutoplayBot/00_state.gd"

# Placeholders for functions that live in a later file of the AutoplayBot chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _light_snapshot(player) -> Dictionary:
	return {}

func _capture_autoplay_world_state(snapshot: Dictionary) -> void:
	pass

func _restore_autoplay_world_state(snapshot: Dictionary) -> void:
	pass

func _finish_trial(success: bool, died: bool) -> void:
	pass

func _build_search_node(snapshot: Dictionary, segment_frames: Array) -> Dictionary:
	return {}

func _accept_search_node(node: Dictionary, success: bool, reason: String) -> bool:
	return false

func _search_state_score(snapshot: Dictionary, path_ticks: int, checkpoint_depth: int) -> float:
	return 0.0

func _search_state_key(snapshot: Dictionary) -> String:
	return ""

func _remember_search_state(key: String, score: float) -> void:
	pass

func _pop_search_frontier() -> Dictionary:
	return {}

func _make_search_actions(snapshot: Dictionary) -> Array:
	return []

func _search_frame_for_tick(action: Dictionary, tick: int, player) -> Dictionary:
	return {}

func _assemble_search_frames(node: Dictionary) -> Array:
	return []

func _build_navigation_route(game: Node, start_position: Vector2) -> bool:
	return false

func _plan_navigation_route_from_geometry(start_position: Vector2) -> bool:
	return false

func _navigation_edge_cost(from: Vector2, to: Vector2, relaxed: bool) -> float:
	return 0.0

func _reconstruct_navigation_route(points: Array, came_from: Dictionary, goal_index: int) -> Array:
	return []

func _rebuild_route_lengths() -> void:
	pass

func _update_route_index(position: Vector2) -> void:
	pass

func _route_progress_at(position: Vector2) -> float:
	return 0.0

func _nearby_wall_direction(position: Vector2) -> int:
	return 0

func _collect_finish_rects(game: Node) -> Array:
	return []

func _nearest_finish_point(position: Vector2) -> Vector2:
	return Vector2()

func _distance_to_finish(position: Vector2) -> float:
	return 0.0

func _connect_finish_signal(game: Node) -> void:
	pass

func _stop_other_input_modes() -> void:
	pass

func _stop_internal(reason: String, write_log: bool) -> void:
	pass

func _release_inputs() -> void:
	pass

func _is_supported_game() -> bool:
	return false

func _physics_fps() -> float:
	return 0.0

func _horizon_ticks() -> int:
	return 0

func _refresh_ui(force: bool = false) -> void:
	pass

func _dump_current_level_for_diagnostics() -> void:
	pass

func _log(message: String) -> void:
	pass
