extends "res://project_specific/level_editor/animation_editor/LevelEditor_AnimationEditor.gd"

signal editor_animation_changed()

func render_node_ids(ids: Array):
	.render_node_ids(ids)
	emit_signal("editor_animation_changed")

func set_key_frame_values(ids: Array, index: int, key: String, property_name: String, values: Array):
	.set_key_frame_values(ids, index, key, property_name, values)
	emit_signal("editor_animation_changed")

# Preserve the native animation format and runtime; only transaction ownership changes.
func _snapshots(ids: Array) -> Array:
	var result = []
	for id in ids:
		var node = level_editor.level.get_level_node(id)
		if node == null:
			return []
		result.append({"id": id, "data": node.animation.animation_data.deep_copy() if node.animation != null else null})
	return result

func restore_animations(states: Array) -> void:
	for state in states:
		var node = level_editor.level.get_level_node(state.id)
		if node == null:
			continue
		if node.animation != null:
			node.remove_animation()
		if state.data != null:
			node.create_animation_node()
			node.animation.set_animation_data(state.data.deep_copy())
	render_node_ids(_selected_node_ids)

func add_key(delay: bool) -> void:
	var geometry = level_editor.tool_select.get("editor_geometry")
	for id in _selected_node_ids:
		var node = level_editor.level.get_level_node(id)
		if geometry != null and geometry.small(node):
			geometry.get_parent().message.text = "Sub-unit blocks must stay static. Resize to at least 1 unit before adding animation."
			return
	var before = _snapshots(_selected_node_ids)
	if before.empty():
		return
	level_editor.undo.create_action("Editor+ Add tween key")
	level_editor.undo.add_do_method(self, "create_key_frame", delay, {}, _selected_node_ids.duplicate(), selected_key, -1)
	level_editor.undo.add_undo_method(self, "restore_animations", before)
	level_editor.undo.commit_action()

func on_plus_button_pressed():
	add_key(false)

func on_plus_delay_button_pressed():
	add_key(true)

func keys_exist(index: int) -> bool:
	if _selected_node_ids.empty() or index < 0:
		return false
	for id in _selected_node_ids:
		if get_key_frame(id, selected_key, index) == null:
			return false
	return true

func on_delete_button_pressed(index: int):
	if not keys_exist(index):
		return
	var before = _snapshots(_selected_node_ids)
	level_editor.undo.create_action("Editor+ Delete tween key")
	level_editor.undo.add_do_method(self, "delete_key_frame", _selected_node_ids.duplicate(), selected_key, index)
	level_editor.undo.add_undo_method(self, "restore_animations", before)
	level_editor.undo.commit_action()

func set_key_frame_value_with_undo(action_name: String, ids: Array, index: int, key: String, property_name: String, value):
	if ids.empty():
		return
	if typeof(value) == TYPE_REAL and (is_nan(value) or is_inf(value)):
		return
	if typeof(value) == TYPE_VECTOR2 and (is_nan(value.x) or is_nan(value.y) or is_inf(value.x) or is_inf(value.y)):
		return
	if property_name == "duration" and (value < 0 or value > 3600):
		return
	var previous = []
	for id in ids:
		var frame = get_key_frame(id, key, index)
		if frame == null or not property_name in frame:
			return
		previous.append(frame.get(property_name))
	var changed = false
	for old in previous:
		changed = changed or var2str(old) != var2str(value)
	if not changed:
		return
	level_editor.undo.create_action("Editor+ " + action_name)
	level_editor.undo.add_do_method(self, "set_key_frame_values", ids.duplicate(), index, key, property_name, [value])
	level_editor.undo.add_undo_method(self, "set_key_frame_values", ids.duplicate(), index, key, property_name, previous)
	level_editor.undo.commit_action()

func set_animation_option(key: String, value) -> void:
	var states = _snapshots(_selected_node_ids)
	if states.empty():
		return
	if key == "offset" and (is_nan(value) or is_inf(value) or abs(value) > 3600):
		return
	var previous = []
	var changed = false
	for state in states:
		if state.data == null:
			return
		var old = state.data.get(key)
		previous.append(old)
		changed = changed or old != value
	if not changed:
		return
	level_editor.undo.create_action("Editor+ Animation " + key)
	level_editor.undo.add_do_method(self, "_options", _selected_node_ids.duplicate(), key, [value])
	level_editor.undo.add_undo_method(self, "_options", _selected_node_ids.duplicate(), key, previous)
	level_editor.undo.commit_action()

func _options(ids: Array, key: String, values: Array) -> void:
	for i in ids.size():
		var node = level_editor.level.get_level_node(ids[i])
		if node != null and node.animation != null:
			node.animation.animation_data.set(key, values[min(i, values.size() - 1)])
	render_node_ids(_selected_node_ids)

func on_repeat_button_pressed():
	set_animation_option("repeat", repeat_button.pressed)

func on_offset_input(text: String):
	if text.is_valid_float():
		set_animation_option("offset", float(text))

func reorder_keys(from: int, to: int) -> void:
	if from == to or not keys_exist(from) or not keys_exist(to):
		return
	level_editor.undo.create_action("Editor+ Reorder tween keys")
	level_editor.undo.add_do_method(self, "_reorder", _selected_node_ids.duplicate(), selected_key, from, to)
	level_editor.undo.add_undo_method(self, "_reorder", _selected_node_ids.duplicate(), selected_key, to, from)
	level_editor.undo.commit_action()

func _reorder(ids: Array, key: String, from: int, to: int) -> void:
	for id in ids:
		var node = level_editor.level.get_level_node(id)
		if node == null or node.animation == null:
			continue
		var sequence = node.animation.animation_data.get_sequence(key)
		if sequence == null or max(from, to) >= sequence.tweens.size():
			continue
		var tweens = sequence.tweens.duplicate()
		var frame = tweens[from]
		tweens.remove(from)
		tweens.insert(to, frame)
		sequence.tweens = tweens
	render_node_ids(_selected_node_ids)
