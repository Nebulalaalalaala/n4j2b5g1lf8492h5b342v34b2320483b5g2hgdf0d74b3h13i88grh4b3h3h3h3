extends VBoxContainer

const KEY = "_goobplayability_visual"
var host
var layer_input: SpinBox
var opacity_input: SpinBox
var status: Label
var originals = {}
var pending = {}

func build(owner) -> void:
	host = owner
	name = "Appearance"
	add_constant_override("separation", 10)
	status = host._label("Select objects to edit their appearance.", 14)
	status.autowrap = true
	status.rect_min_size = Vector2(380, 44)
	add_child(status)
	var row = host._row(self)
	row.add_child(host._label("Draw layer", 14))
	layer_input = SpinBox.new()
	layer_input.rect_min_size.x = 100
	layer_input.min_value = -6
	layer_input.max_value = 6
	layer_input.step = 1
	row.add_child(layer_input)
	button(row, "Apply", "layer")
	row = host._row(self)
	row.add_child(host._label("Opacity %", 14))
	opacity_input = SpinBox.new()
	opacity_input.rect_min_size.x = 100
	opacity_input.min_value = 0
	opacity_input.max_value = 100
	opacity_input.value = 100
	row.add_child(opacity_input)
	button(row, "Apply", "opacity")
	button(self, "Reset selected visuals", "reset")
	var note = host._label("Higher layers draw in front across object types. Layer 0 keeps native ordering.\n\nSaved in level properties; Goobplayability is required to render these settings. Collision and laser timing are unchanged.", 13, Color("9ba8ad"))
	note.autowrap = true
	note.rect_min_size = Vector2(380, 105)
	add_child(note)

func button(parent, text: String, action: String) -> void:
	var control = host._button(parent, text, "_refresh")
	control.disconnect("pressed", host, "_refresh")
	control.connect("pressed", self, "change", [action])

func _ready() -> void:
	get_tree().connect("node_added", self, "observe")
	scan(get_tree().root)

func scan(node) -> void:
	observe(node)
	for child in node.get_children():
		scan(child)

func observe(node) -> void:
	var owner = node
	while owner != null and not owner is LevelNode:
		owner = owner.get_parent()
	if owner != null and owner.properties.has(KEY) and not pending.has(owner.get_instance_id()):
		pending[owner.get_instance_id()] = true
		call_deferred("apply_visual", owner)

func valid(value) -> bool:
	if not value is Dictionary:
		return false
	var layer = value.get("layer", 0)
	var opacity = value.get("opacity", 1.0)
	if not typeof(layer) in [TYPE_INT, TYPE_REAL] or not typeof(opacity) in [TYPE_INT, TYPE_REAL]:
		return false
	return not is_nan(float(layer)) and not is_inf(float(layer)) and layer == int(layer) and layer >= -6 and layer <= 6 and not is_nan(float(opacity)) and not is_inf(float(opacity)) and opacity >= 0 and opacity <= 1

func collect(node, root, items: Array) -> void:
	if node is Node2D and (node == root or not node.z_as_relative):
		items.append(node)
	for child in node.get_children():
		collect(child, root, items)

func apply_visual(node) -> void:
	if not is_instance_valid(node):
		return
	pending.erase(node.get_instance_id())
	var data = node.properties.get(KEY, {})
	if not valid(data):
		data = {}
	var items = []
	collect(node, node, items)
	for item in items:
		var id = item.get_instance_id()
		if not originals.has(id):
			originals[id] = {"node": item, "z": item.z_index, "color": item.modulate}
		var requested = int(originals[id].z) + int(data.get("layer", 0)) * 512
		if requested < -4096 or requested > 4096:
			return
	for item in items:
		var state = originals[item.get_instance_id()]
		item.z_index = int(state.z) + int(data.get("layer", 0)) * 512
	var color = originals[node.get_instance_id()].color
	color.a *= float(data.get("opacity", 1.0))
	node.modulate = color
	# Deleted renderers should not accumulate across theme/level changes.
	for id in originals.keys():
		if not is_instance_valid(originals[id].node):
			originals.erase(id)

func change(action: String) -> void:
	var before = []
	var after = []
	for node in host.selected():
		var original = node.properties.get(KEY, null)
		var value = original.duplicate(true) if valid(original) else {}
		if action == "layer":
			value.layer = int(layer_input.value)
		elif action == "opacity":
			value.opacity = opacity_input.value / 100.0
		elif action == "reset":
			value = null
		else:
			return
		var items = []
		collect(node, node, items)
		for item in items:
			var base = originals.get(item.get_instance_id(), {"z": item.z_index}).z
			var requested = int(base) + (0 if value == null else int(value.get("layer", 0))) * 512
			if requested < -4096 or requested > 4096:
				status.text = "This object's native draw range cannot fit that layer. Nothing changed."
				return
		before.append({"id": node.level_node_index, "value": original.duplicate(true) if original is Dictionary else original})
		after.append({"id": node.level_node_index, "value": value})
	if before.empty() or var2str(before) == var2str(after):
		return
	host.editor.undo.create_action("Editor+ Visual " + action)
	host.editor.undo.add_do_method(self, "apply_states", after)
	host.editor.undo.add_undo_method(self, "apply_states", before)
	host.editor.undo.commit_action()

func apply_states(states: Array) -> void:
	if not host.available():
		return
	for state in states:
		var node = host.editor.level.get_level_node(state.id)
		if node == null:
			continue
		if state.value == null:
			node.properties.erase(KEY)
		else:
			node.properties[KEY] = state.value.duplicate(true) if state.value is Dictionary else state.value
		apply_visual(node)
	refresh()

func refresh() -> void:
	if status == null:
		return
	var nodes = host.selected()
	if nodes.empty():
		status.text = "Select objects to edit their appearance."
		return
	var layers = []
	var opacities = []
	for node in nodes:
		var value = node.properties.get(KEY, {})
		if not valid(value):
			value = {}
		if not layers.has(value.get("layer", 0)):
			layers.append(value.get("layer", 0))
		if not opacities.has(value.get("opacity", 1.0)):
			opacities.append(value.get("opacity", 1.0))
	status.text = "%d objects · Layer: %s · Opacity: %s" % [nodes.size(), str(layers[0]) if layers.size() == 1 else "Mixed", str(round(opacities[0] * 100)) + "%" if opacities.size() == 1 else "Mixed"]
	if layers.size() == 1 and not layer_input.get_line_edit().has_focus():
		layer_input.value = layers[0]
	if opacities.size() == 1 and not opacity_input.get_line_edit().has_focus():
		opacity_input.value = opacities[0] * 100

func _exit_tree() -> void:
	for state in originals.values():
		if is_instance_valid(state.node):
			state.node.z_index = state.z
			state.node.modulate = state.color
