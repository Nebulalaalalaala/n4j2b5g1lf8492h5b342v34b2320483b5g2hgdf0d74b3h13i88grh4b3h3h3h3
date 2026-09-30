extends VBoxContainer

var host
var picker: OptionButton
var input: LineEdit
var choices: OptionButton
var current: Label
var hint: Label
var apply_button: Button
var shared = []
var applying = false
var selection_key = ""

func build(owner) -> void:
	host = owner
	name = "Properties"
	add_constant_override("separation", 12)
	add_child(host._label("Shared properties", 18, Color("9dd6bd")))
	picker = OptionButton.new()
	_style_choice(picker)
	picker.rect_min_size.x = 360
	picker.connect("item_selected", self, "_pick")
	add_child(picker)
	current = host._label("Select objects to see compatible properties.", 14, Color("9ba8ad"))
	current.autowrap = true
	current.rect_min_size.y = 40
	add_child(current)
	input = LineEdit.new()
	input.max_length = 4096
	input.connect("text_entered", self, "_enter")
	add_child(input)
	choices = OptionButton.new()
	_style_choice(choices)
	add_child(choices)
	apply_button = Button.new()
	apply_button.text = "Apply to selection"
	apply_button.add_stylebox_override("normal", host._style(Color("30463b")))
	apply_button.connect("pressed", self, "apply_selected")
	add_child(apply_button)
	hint = host._label("One change, one undo. Only properties shared by every selected object appear.", 13, Color("9ba8ad"))
	hint.autowrap = true
	hint.rect_min_size = Vector2(350, 60)
	add_child(hint)

func _style_choice(control: OptionButton) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		control.add_stylebox_override(state, host._style(Color("30463b") if state == "focus" else Color("22282c")))
	control.get_popup().add_stylebox_override("panel", host._style(Color("22282c")))
	control.get_popup().add_font_override("font", host.tool._make_font(14))

func definitions(node) -> Dictionary:
	var panel = host.editor.tool_select.inspector.properties_panel
	var result = panel.default_property_definitions.duplicate()
	for key in panel.disable_default_properties_map.get(node.node_type, []):
		result.erase(key)
	result.merge(node.property_definitions, true)
	return result

func definition(node, key: String):
	var value = definitions(node).get(key)
	if value != null and not node.property_definitions.has(key) and not value.link_property.empty():
		value.link_target = node
	return value

func read_value(node, key: String):
	var def = definition(node, key)
	return def.get_value(node.properties) if def != null else null

func _compatible(a, b) -> bool:
	if a == null or b == null or a.get_script() != b.get_script() or a.link_property != b.link_property:
		return false
	if a is LevelNode_PropertyEnum:
		return var2str(a.enum_values) == var2str(b.enum_values)
	return typeof(a.default_value()) == typeof(b.default_value())

func refresh() -> void:
	if picker == null:
		return
	var previous = shared[picker.selected] if picker.selected >= 0 and picker.selected < shared.size() else ""
	var nodes = host.selected()
	var context = ""
	for node in nodes:
		context += str(node.get_instance_id()) + ":"
	if context != selection_key:
		selection_key = context
		hint.text = "One change, one undo. Only properties shared by every selected object appear."
	shared.clear()
	if not nodes.empty():
		var first = definitions(nodes[0])
		for key in first:
			var def = first[key]
			# Vector transforms already have the precision Selection controls.
			if not typeof(def.default_value()) in [TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING]:
				continue
			var compatible = true
			for node in nodes:
				compatible = compatible and _compatible(def, definitions(node).get(key))
			if compatible:
				shared.append(key)
	shared.sort()
	picker.clear()
	for key in shared:
		picker.add_item(key.replace("_", " ").capitalize())
	picker.disabled = shared.empty()
	picker.selected = max(0, shared.find(previous)) if not shared.empty() else -1
	_pick(picker.selected)
	hook_native()

func _pick(index: int) -> void:
	input.hide()
	choices.hide()
	apply_button.disabled = true
	var nodes = host.selected()
	if index < 0 or index >= shared.size() or nodes.empty():
		current.text = "No shared scalar properties. Select matching object types."
		return
	var key = shared[index]
	var def = definition(nodes[0], key)
	var value = read_value(nodes[0], key)
	var mixed = false
	for node in nodes:
		mixed = mixed or var2str(read_value(node, key)) != var2str(value)
	current.text = "%d objects · %s" % [nodes.size(), "Mixed values" if mixed else "Current: " + str(value)]
	choices.clear()
	if def is LevelNode_PropertyEnum or typeof(value) == TYPE_BOOL:
		choices.show()
		choices.add_item("Choose a value…", -1)
		var names = def.enum_values if def is LevelNode_PropertyEnum else ["Off", "On"]
		for i in names.size():
			choices.add_item(str(names[i]), i)
		choices.selected = 0 if mixed else int(value) + 1
	else:
		input.show()
		input.placeholder_text = "Mixed — enter a replacement" if mixed else "Value"
		if not input.has_focus():
			input.text = "" if mixed else str(value)
	apply_button.disabled = false

func _enter(_text: String) -> void:
	apply_selected()

func apply_selected() -> void:
	var nodes = host.selected()
	if nodes.empty() or picker.selected < 0 or picker.selected >= shared.size():
		return
	var key = shared[picker.selected]
	var def = definition(nodes[0], key)
	var type = typeof(def.default_value())
	var value
	if choices.visible:
		if choices.selected <= 0:
			hint.text = "Choose a replacement for the mixed value first."
			return
		value = choices.selected - 1
		if type == TYPE_BOOL:
			value = bool(value)
	elif type == TYPE_STRING:
		value = input.text
	elif type == TYPE_INT and input.text.is_valid_integer():
		value = int(input.text)
	elif type == TYPE_REAL and input.text.is_valid_float():
		value = float(input.text)
	else:
		hint.text = "Enter a valid " + ("whole number." if type == TYPE_INT else "number.")
		return
	change(nodes, key, value)

func change(nodes: Array, key: String, value) -> bool:
	if not host.available() or nodes.empty() or applying:
		return false
	var before = []
	var after = []
	for node in nodes:
		if not is_instance_valid(node):
			return false
		var def = definition(node, key)
		if def == null:
			return false
		if typeof(value) in [TYPE_REAL, TYPE_INT] and (is_nan(float(value)) or is_inf(float(value))):
			return false
		if typeof(value) == TYPE_VECTOR2 and (is_nan(value.x) or is_inf(value.x) or is_nan(value.y) or is_inf(value.y)):
			return false
		var validated = def.validate(value)
		# Do not silently apply different clamped values to different objects.
		if var2str(validated) != var2str(value):
			hint.text = "Value does not match every selected object's allowed range or step."
			return false
		if (def is LevelNode_PropertyFloat or def is LevelNode_PropertyInt) and ((def.has_min_value and value < def.min_value) or (def.has_max_value and value > def.max_value)):
			hint.text = "Value is outside this property's allowed range."
			return false
		before.append({"id": node.level_node_index, "key": key, "value": read_value(node, key), "present": node.properties.has(key), "stored": node.properties.get(key)})
		after.append({"id": node.level_node_index, "key": key, "value": validated, "present": true, "stored": validated})
	var different = false
	for i in before.size():
		different = different or var2str(before[i].value) != var2str(after[i].value)
	if not different:
		return false
	# MERGE_ENDS under a generic name merged unrelated native property edits.
	# Keep explicit edits atomic; reuse the same native history as transforms.
	host.editor.undo.create_action("Editor+ Property: " + key)
	host.editor.undo.add_do_method(self, "_apply", after)
	host.editor.undo.add_undo_method(self, "_apply", before)
	host.editor.undo.commit_action()
	hint.text = "Applied to %d objects · Undo restores each original value." % nodes.size()
	call_deferred("refresh")
	return true

func _apply(states: Array) -> void:
	if not host.available():
		return
	applying = true
	var panel = host.editor.tool_select.inspector.properties_panel
	for state in states:
		var node = host.editor.level.get_level_node(state.id)
		if node == null:
			continue
		var def = definition(node, state.key)
		if def == null:
			continue
		var original_rect = node.grid_rect
		var was_small = host.geometry.small(node)
		node.apply_property(def, state.value)
		# Original linked values may be finer than the inspector's step. Undo
		# restores those exactly rather than rounding them through validation.
		if def.is_linked_property():
			def.link_target.set(def.link_property, state.value)
		if state.present:
			node.properties[state.key] = state.stored
		else:
			node.properties.erase(state.key)
		if was_small:
			host.geometry.set_rect(node, original_rect)
		if panel.showing_level_node_id == state.id and panel.rows.has(state.key):
			panel.rows[state.key].show_property(def, state.value)
	applying = false
	host.editor.level.recalculate_aabb()
	call_deferred("refresh")
	host.call_deferred("_refresh")

func hook_native() -> void:
	if not host.available():
		return
	var panel = host.editor.tool_select.inspector.properties_panel
	for key in panel.rows:
		var row = panel.rows[key]
		var node = host.editor.level.get_level_node(panel.showing_level_node_id)
		if node == null:
			continue
		var def = definition(node, key)
		if def == null or not typeof(def.default_value()) in [TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING, TYPE_VECTOR2]:
			continue
		if row.is_connected("property_changed", panel, "on_property_changed"):
			row.disconnect("property_changed", panel, "on_property_changed")
		if not row.is_connected("property_changed", self, "_native_changed"):
			row.connect("property_changed", self, "_native_changed", [panel.showing_level_node_id, key])

func _native_changed(value, id: int, key: String) -> void:
	if applying or not host.available():
		return
	var node = host.editor.level.get_level_node(id)
	if node != null:
		change([node], key, value)
