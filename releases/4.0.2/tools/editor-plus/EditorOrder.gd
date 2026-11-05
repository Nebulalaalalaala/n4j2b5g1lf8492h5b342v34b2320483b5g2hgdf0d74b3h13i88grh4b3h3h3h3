extends Reference

var host

func ids() -> Array:
	var result = []
	if not host.available():
		return result
	for node in host.editor.level.loaded_level.get_children():
		# Never reorder an unknown auxiliary child.
		if not node is LevelNode:
			return []
		result.append(node.level_node_index)
	return result

func change(action: String) -> void:
	var before = ids()
	var selected = {}
	for node in host.selected():
		selected[node.level_node_index] = true
	if before.empty() or selected.empty():
		host.message.text = "Select objects to change their order."
		return
	var after = before.duplicate()
	if action in ["front", "back"]:
		var moving = []
		var others = []
		for id in before:
			if selected.has(id):
				moving.append(id)
			else:
				others.append(id)
		after = others + moving if action == "front" else moving + others
	elif action == "forward":
		for i in range(after.size() - 2, -1, -1):
			if selected.has(after[i]) and not selected.has(after[i + 1]):
				var next = after[i + 1]
				after[i + 1] = after[i]
				after[i] = next
	elif action == "backward":
		for i in range(1, after.size()):
			if selected.has(after[i]) and not selected.has(after[i - 1]):
				var previous = after[i - 1]
				after[i - 1] = after[i]
				after[i] = previous
	else:
		return
	if var2str(before) == var2str(after):
		host.message.text = "Selection is already at that edge."
		return
	host.editor.undo.create_action("Editor+ Order " + action)
	host.editor.undo.add_do_method(self, "apply", after)
	host.editor.undo.add_undo_method(self, "apply", before)
	host.editor.undo.commit_action()

func apply(order: Array) -> void:
	var current = ids()
	if current.size() != order.size():
		return
	for id in order:
		if not current.has(id):
			return
	var parent = host.editor.level.loaded_level
	for i in range(order.size()):
		parent.move_child(host.editor.level.get_level_node(order[i]), i)
	host.editor.tool_select.update()
	host.groups_panel.save_groups()
	host.message.text = "Order updated within the game's existing draw layers."
