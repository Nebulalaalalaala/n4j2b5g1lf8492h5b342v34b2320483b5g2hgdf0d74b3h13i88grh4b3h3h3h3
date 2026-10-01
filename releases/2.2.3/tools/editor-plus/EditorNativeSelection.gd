extends "res://project_specific/level_editor/tools/LevelEditorToolSelect.gd"

# Native selection behavior with exact fractional selection bounds.
func _process_tool(delta: float) -> void :
	if level_editor.gesture_recognizer.is_recognizing_gesture():
		return
	
	var edge_detect_buffer: = 15.0
	
	var overlapping_nodes: = []
	if level_editor.is_mouse_present:
		overlapping_nodes = level_editor.level.overlap_point(mouse_position)
		for index in range(overlapping_nodes.size() - 1, -1, -1):
			var node = overlapping_nodes[index]
			if (node.grid_rect.size.x < 1 or node.grid_rect.size.y < 1) and not editor_world_rect(node).has_point(mouse_position):
				overlapping_nodes.remove(index)
	
	
	hovering_node = null
	if hovering_multiple_index >= overlapping_nodes.size():
		hovering_multiple_index = 0
	if overlapping_nodes.size() > 0:
		hovering_node = overlapping_nodes[hovering_multiple_index]
	
	
	hovering_node_edge_mask = 0
	if not Input.is_key_pressed(KEY_SHIFT):
		
		
		if hovering_node != null and selected_nodes.has(hovering_node):
			for i in LevelGrid2.FACE_MAX:
				var distance_to_edge: = LevelGrid2.distance_to_edge_of_rect(editor_world_rect(hovering_node), mouse_position, i)
				var exact_size = editor_world_rect(hovering_node).size
				if distance_to_edge <= min(edge_detect_buffer, min(exact_size.x, exact_size.y) * 0.25):
					hovering_node_edge_mask = hovering_node_edge_mask | 1 << i
	
	
	if is_mouse_down and not was_mouse_down:
		selected_nodes_move_accumulator = Vector2.ZERO
		selected_nodes_move_root = LevelGrid2.world_to_grid_2d(mouse_position)
		clicked_node = hovering_node
		clicked_node_edge_mask = hovering_node_edge_mask
		if hovering_node:
			clicked_node_edge_original_rect = hovering_node.grid_rect
		else:
			clicked_node_edge_original_rect = Rect2()
		if not Input.is_key_pressed(KEY_SHIFT) and clicked_node != null and selected_nodes.has(clicked_node):
			if clicked_node_edge_mask > 0:
				
				click_state = ClickState.ClickedEdge
			else:
				click_state = ClickState.ClickedNode
		else:
			click_state = ClickState.ClickedNothing

	
	
















		
	
	if click_state == ClickState.ClickedNothing:
		if is_mouse_down:
			
			var mouse_distance: = mouse_down_position.distance_to(mouse_position)
			if mouse_distance > 10.0:
				var mouse_rect: = LevelGrid2.grid_rect_to_world_rect(LevelGrid2.world_to_enclosing_grid_rect(mouse_down_position, mouse_position))
				boxed_nodes = level_editor.level.overlap_rect(mouse_rect)
			elif hovering_node != null:
				boxed_nodes = [hovering_node]
			else:
				boxed_nodes = []
		
		
		if not is_mouse_down and was_mouse_down:
			if Input.is_key_pressed(KEY_SHIFT):
				var any_unselected: = false
				for b in boxed_nodes:
					if not selected_nodes.has(b):
						any_unselected = true
						break
				
				for b in boxed_nodes:
					if any_unselected:
						if not selected_nodes.has(b):
							selected_nodes.append(b)
					else:
						if selected_nodes.has(b):
							selected_nodes.erase(b)
				
				_selected_nodes_changed()
			else:
				
				
				
				set_selected_nodes(boxed_nodes)
	
	
	if is_mouse_down:
		match click_state:
			ClickState.ClickedEdge:
				
				
				
				var mouse_grid_position_rounded: = LevelGrid2.world_to_grid_rounded_2d(mouse_position)
				_move_selected_edge_mask(clicked_node, clicked_node_edge_mask, mouse_grid_position_rounded)
				update_selected_nodes_rect()
				
				level_editor.level.recalculate_aabb()
			ClickState.ClickedNode:
				
				var mouse_grid_position: = LevelGrid2.world_to_grid_2d(mouse_position)
				var selected_node_move_delta: = mouse_grid_position - selected_nodes_move_root
				selected_nodes_move_root = mouse_grid_position
				selected_nodes_move_accumulator += selected_node_move_delta
				if abs(selected_node_move_delta.x) > 0 or abs(selected_node_move_delta.y) > 0:
					var selected_node_ids: = _create_selected_node_ids_array()
					_move_node_ids(selected_node_ids, selected_node_move_delta)
	
	if not is_mouse_down:
		match click_state:
			ClickState.ClickedEdge:
				
				var clicked_node_id: = clicked_node.level_node_index
				var grid_rect: = clicked_node.grid_rect
				level_editor.undo.create_action("Resize Node")
				level_editor.undo.add_do_method(self, "_set_node_id_grid_rect", clicked_node_id, grid_rect)
				level_editor.undo.add_undo_method(self, "_set_node_id_grid_rect", clicked_node_id, clicked_node_edge_original_rect)
				level_editor.undo.commit_action()
				
			ClickState.ClickedNode:
				var selected_node_ids: = _create_selected_node_ids_array()
				var new_positions: = []
				var old_positions: = []
				for i in selected_nodes.size():
					var level_node: LevelNode = selected_nodes[i]
					new_positions.append(level_node.grid_rect.position)
					old_positions.append(level_node.grid_rect.position - selected_nodes_move_accumulator)
				level_editor.undo.create_action("Move Nodes")
				level_editor.undo.add_do_method(self, "_move_node_ids_to", selected_node_ids, new_positions)
				level_editor.undo.add_undo_method(self, "_move_node_ids_to", selected_node_ids, old_positions)
				level_editor.undo.commit_action()
	
	if not is_mouse_down:
		
		boxed_nodes.clear()
		clicked_node_edge_mask = 0
		clicked_node = null
		click_state = ClickState.None
		selected_nodes_move_accumulator = Vector2.ZERO
		
	was_mouse_down = is_mouse_down


func _draw_dynamic_rect(level_node: LevelNode, color: Color):
	if level_node.body:
		var body_type: = level_node.body.type
		if body_type == Box2DPhysicsBody.MODE_KINEMATIC or body_type == Box2DPhysicsBody.MODE_RIGID:
			var node_size: = editor_world_rect(level_node).size
			var centered_rect: = Rect2( - node_size * 0.5, node_size)
			var node_transform: = Transform2D(level_node.body.rotation, level_node.body.position)
			draw_transformed_grid_cells(centered_rect, color, false, false, node_transform)


func _draw() -> void :
	
	for i in selected_nodes.size():
		var selected_node: = selected_nodes[i] as LevelNode
		draw_grid_cells(editor_world_rect(selected_node), selected_outline_color, false, false)
		_draw_dynamic_rect(selected_node, selected_outline_color)
	
	for i in boxed_nodes.size():
		var boxed_node: = boxed_nodes[i] as LevelNode
		if not selected_nodes.has(boxed_node):
			draw_grid_cells(editor_world_rect(boxed_node), hovering_outline_color, false, false)
			_draw_dynamic_rect(boxed_node, hovering_outline_color)
	
	if click_state == ClickState.ClickedEdge:
		for edge in LevelGrid2.FACE_MAX:
			var edge_mask: = 1 << int(edge)
			if clicked_node_edge_mask & edge_mask > 0:
				draw_bounding_box_edge(editor_world_rect(clicked_node), edge, interacting_outline_color)
	
	
	var drawing_hovering_edge: = false
	if click_state == ClickState.None:
		if hovering_node:
			if not selected_nodes.has(hovering_node) and not boxed_nodes.has(hovering_node):
				
				draw_grid_cells(editor_world_rect(hovering_node), hovering_outline_color, false, false)
				_draw_dynamic_rect(hovering_node, hovering_outline_color)
		if hovering_node_edge_mask > 0:
			
			for edge in LevelGrid2.FACE_MAX:
				var edge_mask: = 1 << int(edge)
				if hovering_node_edge_mask & edge_mask > 0:
					draw_bounding_box_edge(editor_world_rect(hovering_node), edge, interactable_outline_color)
	if level_editor.is_mouse_present:
		
		if hovering_node_edge_mask == 0 and \
		click_state != ClickState.ClickedNode and \
		click_state != ClickState.ClickedEdge:
			draw_mouse_cell(mouse_down_position, mouse_position)


func update_selected_nodes_rect():
	selected_nodes_rect = Rect2()
	for i in selected_nodes.size():
		var boxed_node: = selected_nodes[i] as LevelNode
		selected_nodes_rect = selected_nodes_rect.expand(editor_world_rect(boxed_node).position)
		selected_nodes_rect = selected_nodes_rect.expand(editor_world_rect(boxed_node).end)


func editor_world_rect(node) -> Rect2:
	return LevelGrid2.grid_rect_to_world_rect(node.grid_rect)
