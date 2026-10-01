extends "user://mod/tools/editor-plus/EditorPlus/01_placeholders.gd"

func _ready() -> void:
	layer = 156
	pause_mode = Node.PAUSE_MODE_PROCESS
	var saved_scale = SavedSettings.get_value("editor_plus_scale_percent", 100.0)
	if typeof(saved_scale) in [TYPE_INT, TYPE_REAL] and not is_nan(float(saved_scale)) and not is_inf(float(saved_scale)):
		window_scale = max(0.1, float(saved_scale) / 100.0)
	scale_auto_fit = bool(SavedSettings.get_value("editor_plus_scale_fit", true))
	var saved_size = SavedSettings.get_value("editor_plus_window_size", [])
	if saved_size is Array and saved_size.size() == 2:
		if typeof(saved_size[0]) in [TYPE_INT, TYPE_REAL] and typeof(saved_size[1]) in [TYPE_INT, TYPE_REAL]:
			if not is_nan(float(saved_size[0])) and not is_inf(float(saved_size[0])) and not is_nan(float(saved_size[1])) and not is_inf(float(saved_size[1])):
				window_size = Vector2(max(520, saved_size[0]), max(400, saved_size[1]))
	geometry = load(get_script().resource_path.get_base_dir().plus_file("EditorGeometry.gd")).new()
	add_child(geometry)
	recovery = load(get_script().resource_path.get_base_dir().plus_file("EditorRecovery.gd")).new()
	get_tree().connect("node_added", self, "_consider")
	_scan(get_tree().root)
	_build()
	object_order = load(get_script().resource_path.get_base_dir().plus_file("EditorOrder.gd")).new()
	object_order.host = self

func _scan(node) -> void:
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _consider(node) -> void:
	var extension = ""
	if node is LevelEditor_AnimationEditor:
		extension = "EditorAnimation.gd"
	elif node is TweenSequenceEditor:
		extension = "EditorTweenSequence.gd"
	elif node is LevelEditorToolSelect:
		extension = "EditorSelection.gd"
	if not extension.empty():
		var script = load(get_script().resource_path.get_base_dir().plus_file(extension))
		if script == null or not script.can_instance():
			return
		var not_ready = node.get("sequence_editor") == null if node is LevelEditor_AnimationEditor else node.get("animation_row_parent") == null
		if node is LevelEditorToolSelect:
			not_ready = node.get("inspector") == null
		if node.get_script() != script and not_ready:
			var exports = {}
			for property in node.get_property_list():
				var value = node.get(property.name)
				if property.type in [TYPE_NODE_PATH, TYPE_COLOR] or value is Texture or value is PackedScene:
					exports[property.name] = value
			node.set_script(script)
			for key in exports:
				node.set(key, exports[key])
	if node is LevelEditor:
		call_deferred("attach", node)

func attach(node) -> void:
	if not is_instance_valid(node) or node == editor:
		return
	editor = node
	var root = editor.ui_root
	if root.is_connected("gui_input", editor, "on_ui_root_gui_input"):
		root.disconnect("gui_input", editor, "on_ui_root_gui_input")
	root.connect("gui_input", self, "_editor_input")
	var inspector = editor.tool_select.inspector
	if inspector.animation_editor.has_signal("editor_animation_changed"):
		inspector.animation_editor.connect("editor_animation_changed", self, "_refresh")
	if inspector.is_connected("rotate_pressed", editor.tool_select, "on_rotate_button_pressed"):
		inspector.disconnect("rotate_pressed", editor.tool_select, "on_rotate_button_pressed")
	inspector.connect("rotate_pressed", self, "rotate_shape", [1])
	editor.tool_select.connect("selected_nodes_changed", self, "_selection_changed")
	editor.level.connect("loaded_level", self, "_level_changed")
	editor.level.connect("unloading_level", groups_panel, "leave_level")
	editor.connect("tree_exiting", groups_panel, "leave_level")
	editor.level.connect("added_node", groups_panel, "node_added")
	editor.tool_select.editor_groups = groups_panel
	editor.tool_select.editor_geometry = geometry
	editor.level_save_dialog.connect("save_button_pressed", groups_panel, "save_groups")
	groups_panel.load_groups()
	# Replace only the play-button connection, so the snapshot precedes playtest.
	if editor.play_button.is_connected("pressed", editor, "on_play_pressed"):
		editor.play_button.disconnect("pressed", editor, "on_play_pressed")
	editor.play_button.connect("pressed", self, "_play")
	elapsed = 0
	last_selection = ""
	thumbnail_hidden.clear()
	_apply_thumbnail()
	_refresh()

func available() -> bool:
	return is_instance_valid(editor) and editor.is_inside_tree() and not editor.is_playing and editor.level.loaded_level != null

func selected() -> Array:
	var result = []
	if available():
		for node in editor.tool_select.selected_nodes:
			if is_instance_valid(node):
				result.append(node)
	return result

func _editor_input(event) -> void:
	if is_instance_valid(guide) and guide.visible:
		return
	if not is_instance_valid(editor):
		return
	if event is InputEventKey:
		var focus = editor.ui_root.get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if tool._keybinds.matches(event,"editor_undo") or tool._keybinds.matches(event,"editor_redo") or tool._keybinds.matches(event,"editor_redo_alt"):
			if event.pressed and not event.echo and available():
				history_step(not tool._keybinds.matches(event,"editor_undo"))
			return
		if tool._keybinds.matches(event,"editor_thumbnail"):
			if event.pressed and not event.echo:
				toggle_thumbnail()
			return
		if (tool._keybinds.matches(event,"editor_rotate") or tool._keybinds.matches(event,"editor_rotate_back")) and editor.active_tool == editor.tool_select:
			if event.pressed and not event.echo and available():
				rotate_shape(-1 if tool._keybinds.matches(event,"editor_rotate_back") else 1)
			return
	editor.on_ui_root_gui_input(event)

func _state(node) -> Dictionary:
	return {"id": node.level_node_index, "rect": node.grid_rect, "pivot": node.pivot, "rot": node.rot, "shape": node.shape_rotation}

func _commit(title: String, before: Array, after: Array) -> void:
	if not available() or before.empty() or var2str(before) == var2str(after):
		return
	editor.undo.create_action(title)
	editor.undo.add_do_method(self, "_apply", after)
	editor.undo.add_undo_method(self, "_apply", before)
	editor.undo.commit_action()
	_refresh()

func _apply(states: Array) -> void:
	if not available():
		return
	for state in states:
		var node = editor.level.get_level_node(state.id)
		if node == null:
			continue
		geometry.set_rect(node, state.rect)
		node.pivot = state.pivot
		node.rot = state.rot
		node.shape_rotation = state.shape
		if state.has("animation"):
			if node.animation != null:
				node.remove_animation()
			if state.animation != null:
				node.create_animation_node()
				node.animation.set_animation_data(state.animation.deep_copy())
		if state.rect.size.x < 1 or state.rect.size.y < 1:
			var data = node.serialize_level_node().duplicate(true)
			data.x = state.rect.position.x
			data.y = state.rect.position.y
			data.width = state.rect.size.x
			data.height = state.rect.size.y
			data.pivot_x = state.pivot.x
			data.pivot_y = state.pivot.y
			data.rotation = state.rot
			data.shape_rotation = state.shape
			geometry.restore(node, data)
	editor.tool_select.update_selected_nodes_rect()
	editor.level.recalculate_aabb()
	call_deferred("_refresh")

func nudge(direction: Vector2) -> void:
	var before = []
	var after = []
	for node in selected():
		var state = _state(node)
		before.append(state.duplicate(true))
		state.rect.position += direction * step.value
		after.append(state)
	_commit("Editor+ Move selection", before, after)

func change_order(action: String) -> void:
	object_order.change(action)

func rotate_shape(amount: int) -> void:
	var before = []
	var after = []
	for node in selected():
		var state = _state(node)
		before.append(state.duplicate(true))
		state.shape = posmod(state.shape + amount, 4)
		after.append(state)
	_commit("Editor+ Rotate shapes", before, after)

func mirror_selection(horizontal: bool) -> void:
	var nodes = selected()
	if nodes.empty():
		return
	var bounds = nodes[0].grid_rect
	for node in nodes:
		if not node.node_type in MIRRORABLE or not mirrorable_animation(node):
			message.text = "Flip supports blocks, ramps, floors, spikes, backgrounds, fields and disappearing blocks with position/rotation tweens. Nothing changed."
			return
		bounds = bounds.merge(node.grid_rect)
	var before = []
	var after = []
	for node in nodes:
		var state = _state(node)
		state.animation = node.animation.animation_data.deep_copy() if node.animation != null else null
		before.append(state.duplicate(true))
		if state.animation != null:
			state.animation = mirror_animation(state.animation, horizontal)
		if horizontal:
			state.rect.position.x = bounds.position.x + bounds.end.x - state.rect.end.x
			state.pivot.x = 1.0 - state.pivot.x
		else:
			state.rect.position.y = bounds.position.y + bounds.end.y - state.rect.end.y
			state.pivot.y = 1.0 - state.pivot.y
		state.rot = -state.rot
		var triangle = node.node_type in ["ramp", "background_ramp"]
		var base = (3 if horizontal else 1) if triangle else (0 if horizontal else 2)
		state.shape = posmod(base - state.shape, 4)
		after.append(state)
	_commit("Editor+ Flip " + ("horizontal" if horizontal else "vertical"), before, after)
	message.text = "Layout flipped. Native artwork stays unmirrored."

func mirrorable_animation(node) -> bool:
	if node.animation == null:
		return true
	if geometry.small(node):
		return false
	for key in node.animation.animation_data.tween_sequences:
		if not key in ["position", "rotation_degrees"]:
			return false
		for frame in node.animation.animation_data.get_sequence(key).tweens:
			if frame.value != null and (typeof(frame.value) != TYPE_VECTOR2 if key == "position" else not typeof(frame.value) in [TYPE_INT, TYPE_REAL]):
				return false
	return true

func mirror_animation(source, horizontal: bool):
	var result = source.deep_copy()
	for key in result.tween_sequences:
		var sequence = result.get_sequence(key)
		for frame in sequence.tweens:
			if frame.value == null:
				continue
			if key == "position":
				frame.value *= Vector2(-1, 1) if horizontal else Vector2(1, -1)
			else:
				frame.value = -frame.value
	return result

func _value(node, key: String) -> float:
	match key:
		"x": return node.grid_rect.position.x
		"y": return node.grid_rect.position.y
		"width": return node.grid_rect.size.x
		"height": return node.grid_rect.size.y
		"pivot_x": return node.pivot.x
		"pivot_y": return node.pivot.y
	return node.rot

func apply_field(key: String) -> void:
	var input = fields[key].text.strip_edges()
	if not input.is_valid_float():
		message.text = "Enter a number; mixed values stay unchanged until applied."
		return
	var value = float(input)
	if key in ["width", "height"]:
		if is_nan(value) or is_inf(value) or value < 0.25 or value > 1000:
			message.text = "Size must be between 0.25 and 1000 grid units."
			return
		for node in selected():
			if not node.node_type in RESIZABLE:
				message.text = "Precise size supports blocks, ramps, backgrounds, fields and disappearing blocks. Nothing changed."
				return
			if (value < 1 or node.grid_rect.size.x < 1 or node.grid_rect.size.y < 1) and (not node.node_type in geometry.TYPES or node.animation != null):
				message.text = "Sub-unit size currently supports static blocks, ice blocks and ramps only. Nothing changed."
				return
	var limit = 10.0 if key.begins_with("pivot") else (360.0 if key == "rotation" else 10000.0)
	if is_nan(value) or is_inf(value) or abs(value) > limit:
		message.text = "Value outside the supported range (±%s)." % limit
		return
	var before = []
	var after = []
	for node in selected():
		var state = _state(node)
		before.append(state.duplicate(true))
		match key:
			"x": state.rect.position.x = value
			"y": state.rect.position.y = value
			"width": state.rect.size.x = value
			"height": state.rect.size.y = value
			"pivot_x": state.pivot.x = value
			"pivot_y": state.pivot.y = value
			"rotation": state.rot = value
		after.append(state)
	_commit("Editor+ Set " + key, before, after)
	message.text = "Applied to %d selected objects." % after.size()

func _enter_field(_text: String, key: String) -> void:
	apply_field(key)

func history_step(redo: bool) -> void:
	if not available():
		return
	if redo:
		editor.undo.redo()
	else:
		editor.undo.undo()
	_refresh()

func _selection_changed(_nodes = []) -> void:
	_refresh()

func _level_changed() -> void:
	elapsed = 0
	last_selection = ""
	geometry.repair_level(editor.level.loaded_level)
	groups_panel.load_groups()
	_refresh()

func _play() -> void:
	if not is_instance_valid(editor):
		return
	if not editor.is_playing:
		groups_panel.save_groups()
		snapshot("Before playtest")
		groups_panel.restore_visibility()
	editor.on_play_pressed()
	groups_panel.apply_access()
	_refresh()

func snapshot(reason: String = "Manual snapshot") -> void:
	if not available():
		return
	groups_panel.save_groups()
	var result = recovery.save(LevelJson.serialize_level(editor.level.loaded_level), reason, reason == "Autosave")
	message.text = result
	_refresh_recovery()

func _refresh_recovery() -> void:
	if recovery_list == null:
		return
	recovery_list.clear()
	for entry in recovery.entries():
		recovery_list.add_item(entry.label)
		recovery_list.set_item_metadata(recovery_list.get_item_count() - 1, entry.file)

func _ask_recover() -> void:
	if not available() or recovery_list.get_selected_items().empty():
		return
	pending_recovery = recovery_list.get_item_metadata(recovery_list.get_selected_items()[0])
	confirmation.dialog_text = "Restore this local snapshot?\nYour current level is backed up first.\nRestoring starts a new undo history."
	confirmation.popup_centered(Vector2(430, 160))

func _recover() -> void:
	if not available():
		return
	var data = recovery.read(pending_recovery)
	if not recovery.valid_level(data, editor.node_factory.node_types):
		message.text = "Recovery file is invalid or contains unsupported objects."
		return
	if not recovery.save(LevelJson.serialize_level(editor.level.loaded_level), "Before recovery", false).begins_with("Saved"):
		message.text = "Recovery cancelled: current level could not be backed up."
		return
	var instance = LevelJson.deserialize_level(data, editor.node_factory)
	editor.level.load_level(instance)
	message.text = "Recovered locally. Use the normal Save button when ready."
	_refresh_recovery()

func _process(delta: float) -> void:
	if panel == null:
		return
	if is_instance_valid(editor) and groups_panel != null and groups_panel.suspended != editor.is_playing:
		groups_panel.apply_access()
	if dragging and not Input.is_mouse_button_pressed(BUTTON_LEFT):
		dragging = false
	# Players are re-created on reset/playtest, so re-check twice a second.
	if thumbnail or not thumbnail_hidden.empty():
		thumbnail_scan += delta
		if thumbnail_scan >= 0.5:
			thumbnail_scan = 0.0
			_thumbnail_players()
		elif thumbnail:
			# The game can re-tint the Goober; keep it hidden between scans.
			for entry in thumbnail_hidden.values():
				if is_instance_valid(entry.node) and entry.node.modulate.a != 0.0:
					entry.node.modulate.a = 0.0
	if available():
		elapsed += delta
		if elapsed >= 60:
			elapsed = 0
			if autosave.pressed:
				snapshot("Autosave")
	if panel.visible:
		_fit()
		undo_button.disabled = not available() or not editor.undo.has_undo()
		redo_button.disabled = not available() or not editor.undo.has_redo()
		var signature = str(available())
		for node in selected():
			signature += var2str(_state(node))
		if signature != last_selection:
			last_selection = signature
			_refresh()

func _refresh() -> void:
	if panel == null:
		return
	if properties != null:
		properties.refresh()
	if appearance_panel != null:
		appearance_panel.refresh()
	if laser_panel != null:
		laser_panel.refresh()
	if tween_panel != null:
		tween_panel.refresh()
	if groups_panel != null:
		groups_panel.refresh()
	var nodes = selected()
	selection_label.text = "%d selected" % nodes.size() if available() else "Open a level in the editor"
	for key in fields:
		var field = fields[key]
		field.editable = not nodes.empty()
		if field.has_focus():
			continue
		field.text = ""
		field.placeholder_text = "—"
		if nodes.empty():
			continue
		var first = _value(nodes[0], key)
		var mixed = false
		for node in nodes:
			mixed = mixed or not is_equal_approx(first, _value(node, key))
		if mixed:
			field.placeholder_text = "Mixed"
		else:
			field.text = str(first)

func open_window() -> void:
	panel.show()
	_refresh()
	_refresh_recovery()
	_fit()

func close_window() -> void:
	resizing = false
	if is_instance_valid(guide):
		guide.close()
	panel.hide()
