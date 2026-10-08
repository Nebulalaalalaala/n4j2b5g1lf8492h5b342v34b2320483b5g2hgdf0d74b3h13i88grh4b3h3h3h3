extends VBoxContainer

var host
var track: OptionButton
var key_index: SpinBox
var summary: Label
var duration: LineEdit
var value_input: LineEdit
var offset: LineEdit
var repeat_choice: OptionButton

func build(owner) -> void:
	host = owner
	name = "Tweens"
	add_constant_override("separation", 8)
	var top = host._row(self)
	track = OptionButton.new()
	track.add_item("Movement")
	track.add_item("Rotation")
	track.connect("item_selected", self, "_track")
	host.properties._style_choice(track)
	top.add_child(track)
	top.add_child(host._label("Key", 14))
	key_index = SpinBox.new()
	key_index.min_value = 1
	key_index.max_value = 999
	key_index.step = 1
	key_index.rect_min_size.x = 70
	key_index.connect("value_changed", self, "_key")
	top.add_child(key_index)
	summary = host._label("Select objects to edit their animations.", 13, Color("9ba8ad"))
	summary.autowrap = true
	summary.rect_min_size = Vector2(360, 44)
	add_child(summary)
	var add_row = host._row(self)
	_button(add_row, "+ Key", "_action", ["add"])
	_button(add_row, "+ Delay", "_action", ["delay"])
	_button(add_row, "↑", "_action", ["up"])
	_button(add_row, "↓", "_action", ["down"])
	_button(add_row, "Delete", "_action", ["delete"])
	duration = _field("Duration · s", "duration")
	value_input = _field("Value · X, Y", "value")
	value_input.hint_tooltip = "Movement: X, Y offset. Rotation: degrees. Delay keys have no value."
	offset = _field("Loop offset · s", "offset")
	var repeat_row = host._row(self)
	repeat_row.add_child(host._label("Repeat", 14))
	repeat_choice = OptionButton.new()
	for text in ["Choose…", "Off", "On"]:
		repeat_choice.add_item(text)
	host.properties._style_choice(repeat_choice)
	repeat_row.add_child(repeat_choice)
	_button(repeat_row, "Apply", "_action", ["repeat"])
	var note = host._label("Edits use the same numbered key on every selected object. Reordering preserves each object's own values.", 12, Color("9ba8ad"))
	note.autowrap = true
	note.rect_min_size = Vector2(350, 46)
	add_child(note)

func _button(parent, text: String, method: String, binds: Array) -> void:
	var button = Button.new()
	button.text = text
	button.add_stylebox_override("normal", host._style(Color("22282c")))
	button.add_stylebox_override("hover", host._style(Color("30463b")))
	button.connect("pressed", self, method, binds)
	parent.add_child(button)

func _field(title: String, key: String) -> LineEdit:
	var row = host._row(self)
	var label = host._label(title, 13)
	label.rect_min_size.x = 105
	row.add_child(label)
	var field = LineEdit.new()
	field.rect_min_size.x = 130
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	_button(row, "Apply", "_action", [key])
	field.connect("text_entered", self, "_enter", [key])
	return field

func _enter(_text: String, key: String) -> void:
	_action(key)

func animation():
	if not host.available():
		return null
	var editor = host.editor.tool_select.inspector.animation_editor
	return editor if editor.has_method("reorder_keys") else null

func _track(_index: int) -> void:
	var editor = animation()
	if editor != null:
		editor.selected_key = "position" if track.selected == 0 else "rotation_degrees"
		editor._update_plus_button()
		editor.render_node_ids(editor._selected_node_ids)
	refresh()

func _key(_index: float) -> void:
	refresh()

func _show_value(field: LineEdit, values: Array) -> void:
	if field.has_focus():
		return
	field.text = ""
	field.placeholder_text = "No key"
	if values.empty():
		return
	for value in values:
		if var2str(value) != var2str(values[0]):
			field.placeholder_text = "Mixed"
			return
	if values[0] == null:
		field.placeholder_text = "Delay"
	else:
		field.text = ("%s, %s" % [values[0].x, values[0].y]) if typeof(values[0]) == TYPE_VECTOR2 else str(values[0])

func refresh() -> void:
	if summary == null:
		return
	var editor = animation()
	var durations = []
	var values = []
	var offsets = []
	var repeats = []
	var counts = []
	if editor != null:
		track.selected = 0 if editor.selected_key == "position" else 1
		for node in host.selected():
			var sequence = node.animation.animation_data.get_sequence(editor.selected_key) if node.animation != null else null
			counts.append(sequence.tweens.size() if sequence != null else 0)
			var frame = editor.get_key_frame(node.level_node_index, editor.selected_key, int(key_index.value) - 1)
			if frame != null:
				durations.append(frame.duration)
				values.append(frame.value)
			if node.animation != null:
				offsets.append(node.animation.animation_data.offset)
				repeats.append(node.animation.animation_data.repeat)
	var smallest = 999999
	var largest = 0
	for count in counts:
		smallest = min(smallest, count)
		largest = max(largest, count)
	var count_text = str(largest) if smallest == largest else "%d–%d" % [smallest, largest]
	summary.text = "Select objects in the editor." if counts.empty() else "%d objects · %s keys each\n%s" % [counts.size(), count_text, "Shared key available" if durations.size() == counts.size() else "This key is missing on some objects; add a key or choose another."]
	_show_value(duration, durations if durations.size() == counts.size() else [])
	_show_value(value_input, values if values.size() == counts.size() else [])
	_show_value(offset, offsets if offsets.size() == counts.size() else [])
	repeat_choice.selected = 0
	if not repeats.empty() and repeats.size() == counts.size():
		var same = true
		for value in repeats:
			same = same and value == repeats[0]
		if same:
			repeat_choice.selected = 2 if repeats[0] else 1
	value_input.get_parent().get_child(0).text = "Value · X, Y" if track.selected == 0 else "Value · degrees"

func _action(action: String) -> void:
	var editor = animation()
	if editor == null or host.selected().empty():
		return
	var index = int(key_index.value) - 1
	if action in ["add", "delay"]:
		editor.add_key(action == "delay")
	elif action == "repeat":
		if repeat_choice.selected > 0:
			editor.set_animation_option("repeat", repeat_choice.selected == 2)
	elif action == "offset":
		if offset.text.is_valid_float():
			editor.set_animation_option("offset", float(offset.text))
	elif not editor.keys_exist(index):
		host.message.text = "Choose a key that exists on every selected object."
		return
	elif action == "delete":
		editor.on_delete_button_pressed(index)
	elif action in ["up", "down"]:
		editor.reorder_keys(index, index + (-1 if action == "up" else 1))
	elif action == "duration" and duration.text.is_valid_float():
		editor.on_duration_changed(index, float(duration.text))
	elif action == "value":
		for id in editor._selected_node_ids:
			if editor.get_key_frame(id, editor.selected_key, index).value == null:
				host.message.text = "Delay keys have duration only."
				return
		if track.selected == 0:
			var parts = value_input.text.split(",")
			if parts.size() == 2 and parts[0].strip_edges().is_valid_float() and parts[1].strip_edges().is_valid_float():
				editor.on_value_changed(index, Vector2(float(parts[0]), float(parts[1])))
		elif value_input.text.is_valid_float():
			editor.on_value_changed(index, float(value_input.text))
	refresh()
