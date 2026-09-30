extends "EditorNativeSelection.gd"

var editor_groups
var editor_geometry

func _allowed(node) -> bool:
	return is_instance_valid(node) and (not is_instance_valid(editor_groups) or not editor_groups.blocked(node.level_node_index))

func _selected_nodes_changed():
	var allowed = []
	for node in selected_nodes:
		if _allowed(node):
			allowed.append(node)
	selected_nodes = allowed
	var small_states = []
	if is_instance_valid(editor_geometry):
		for node in selected_nodes:
			if editor_geometry.small(node):
				small_states.append([node, node.serialize_level_node().duplicate(true)])
	._selected_nodes_changed()
	for pair in small_states:
		editor_geometry.restore(pair[0], pair[1])

func _process_tool(delta: float) -> void:
	var prior_rects = {}
	for node in selected_nodes:
		prior_rects[node.level_node_index] = node.grid_rect
	._process_tool(delta)
	if is_mouse_down and clicked_node != null and click_state == ClickState.ClickedEdge and is_instance_valid(editor_geometry) and clicked_node.node_type in editor_geometry.TYPES and clicked_node.animation == null:
		var rect = clicked_node_edge_original_rect
		var cell = LevelGrid2.world_to_grid_rounded_2d(mouse_position)
		if clicked_node_edge_original_rect.size.x < 1 or clicked_node_edge_original_rect.size.y < 1:
			cell = (mouse_position / LevelGrid.cell_size).snapped(Vector2.ONE * 0.25)
		for edge in UpGuys_LevelGrid.FACE_MAX:
			if clicked_node_edge_mask & (1 << edge):
				var amount = 0.0
				match edge:
					UpGuys_LevelGrid.FACE_UP: amount = rect.position.y - cell.y
					UpGuys_LevelGrid.FACE_LEFT: amount = rect.position.x - cell.x
					UpGuys_LevelGrid.FACE_RIGHT: amount = cell.x - rect.end.x
					UpGuys_LevelGrid.FACE_DOWN: amount = cell.y - rect.end.y
				rect = rect.grow_margin(edge, amount)
		if rect.size.x < 0.25 or rect.size.y < 0.25 or rect.size.x > 1000 or rect.size.y > 1000:
			rect = prior_rects.get(clicked_node.level_node_index, clicked_node_edge_original_rect)
		editor_geometry.set_rect(clicked_node, rect)
		update_selected_nodes_rect()
		level_editor.level.recalculate_aabb()
	var allowed = []
	for node in boxed_nodes:
		if _allowed(node):
			allowed.append(node)
	boxed_nodes = allowed
	if hovering_node != null and not _allowed(hovering_node):
		hovering_node = null
		hovering_node_edge_mask = 0

func refresh_group_access() -> void:
	if clicked_node != null and not _allowed(clicked_node):
		clicked_node = null
		click_state = ClickState.None
		clicked_node_edge_mask = 0
		selected_nodes_move_accumulator = Vector2.ZERO
	_selected_nodes_changed()

# Keep native placement/copy behavior; redo is independent of the clipboard.
func _paste_at_grid_location(target_grid_cell: Vector2, to_target_cell: bool):
	if copied_nodes.empty() or level_editor.is_playing:
		return
	var previous_ids = []
	for node in selected_nodes:
		previous_ids.append(node.level_node_index)
	var fractional = false
	if is_instance_valid(editor_geometry):
		for node in copied_nodes:
			fractional = fractional or editor_geometry.small(node)
	if fractional:
		var pasted = _deep_copy_nodes(copied_nodes)
		var bounds = pasted[0].grid_rect
		for node in pasted:
			bounds = bounds.merge(node.grid_rect)
		var offset = target_grid_cell - Vector2(round(bounds.size.x / 2), round(bounds.size.y / 2)) - bounds.position if to_target_cell else Vector2(2, -2)
		for node in pasted:
			var rect = node.grid_rect
			rect.position += offset
			level_editor.level.add_level_node(node)
			editor_geometry.repair(node)
			editor_geometry.set_rect(node, rect)
		set_selected_nodes(pasted)
	else:
		._paste_at_grid_location(target_grid_cell, to_target_cell)
	var snapshots = []
	var pasted_ids = []
	for node in selected_nodes:
		var data = node.serialize_level_node().duplicate(true)
		data["level_node_index"] = node.level_node_index
		snapshots.append(data)
		pasted_ids.append(node.level_node_index)
	if snapshots.empty():
		return
	level_editor.undo.create_action("Editor+ Paste objects")
	level_editor.undo.add_do_method(self, "_restore_paste", snapshots)
	level_editor.undo.add_undo_method(self, "_remove_paste", pasted_ids, previous_ids)
	level_editor.undo.commit_action()

func _restore_paste(snapshots: Array) -> void:
	var nodes = []
	for data in snapshots:
		var node = level_editor.level.get_level_node(data.level_node_index)
		# Initial commit already has the native pasted instances.
		if node == null:
			node = LevelJson.deserialize_level_node(data.duplicate(true), level_editor.node_factory)
			node.level_node_index = data.level_node_index
			level_editor.level.add_level_node(node)
			if is_instance_valid(editor_geometry):
				editor_geometry.repair(node)
		nodes.append(node)
	set_selected_nodes(nodes)
	level_editor.level.recalculate_aabb()

func _deep_copy_nodes(nodes: Array) -> Array:
	var result = []
	for node in nodes:
		if is_instance_valid(editor_geometry) and editor_geometry.small(node):
			var copy = LevelJson.deserialize_level_node(node.serialize_level_node(), level_editor.node_factory)
			copy.level_node_index = -1
			result.append(copy)
		else:
			result += ._deep_copy_nodes([node])
	return result

func undo_delete(data: Array):
	.undo_delete(data)
	if is_instance_valid(editor_geometry):
		editor_geometry.repair_level(level_editor.level.loaded_level)

func _set_node_id_grid_rect(id: int, rect: Rect2):
	var node = level_editor.level.get_level_node(id)
	if node != null:
		if is_instance_valid(editor_geometry):
			editor_geometry.set_rect(node, rect)
		else:
			node.grid_rect = rect

func _move_node_ids_to(ids: Array, positions: Array):
	for i in range(ids.size()):
		var node = level_editor.level.get_level_node(ids[i])
		if node != null:
			var rect = node.grid_rect
			rect.position = positions[i]
			_set_node_id_grid_rect(ids[i], rect)
	update_selected_nodes_rect()
	level_editor.level.recalculate_aabb()

func _move_node_ids(ids: Array, delta: Vector2):
	var positions = []
	var found = []
	for id in ids:
		var node = level_editor.level.get_level_node(id)
		if node != null:
			found.append(id)
			positions.append(node.grid_rect.position + delta)
	_move_node_ids_to(found, positions)

func _remove_paste(ids: Array, previous_ids: Array) -> void:
	set_selected_nodes([])
	for id in ids:
		var node = level_editor.level.get_level_node(id)
		if node != null:
			level_editor.level.remove_level_node(node)
	var nodes = []
	for id in previous_ids:
		var node = level_editor.level.get_level_node(id)
		if node != null:
			nodes.append(node)
	set_selected_nodes(nodes)
	level_editor.level.recalculate_aabb()
