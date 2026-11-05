extends "user://mod/tools/editor-plus/EditorPlus/02_mirror_selection.gd"
const GuidePaths = preload("user://mod/core/ModPaths.gd")

func show_guide() -> void:
	if not is_instance_valid(guide):
		guide = load(GuidePaths.path("EditorGuide.gd")).new()
		add_child(guide)
		guide.build(self)
	guide.open()

func _fit() -> void:
	if panel == null:
		return
	var size = get_viewport().get_visible_rect().size
	var minimum = panel.get_combined_minimum_size()
	panel.rect_size = Vector2(max(window_size.x, minimum.x), max(window_size.y, minimum.y))
	var stretch = max(0.01, abs(get_viewport().get_final_transform().get_scale().x))
	var factor = window_scale / stretch
	if scale_auto_fit:
		factor = min(factor, min((size.x - 24) / max(1, panel.rect_size.x), (size.y - 24) / max(1, panel.rect_size.y)))
	panel.rect_scale = Vector2.ONE * max(0.01, factor)
	if not resizing:
		panel.rect_position = Vector2(clamp(panel.rect_position.x, 0, max(0, size.x - panel.rect_size.x * factor)), clamp(panel.rect_position.y, 0, max(0, size.y - panel.rect_size.y * factor)))
	if scale_input != null:
		scale_input.set_block_signals(true)
		scale_input.value = panel.rect_scale.x * stretch * 100.0
		scale_input.set_block_signals(false)

func _scale_changed(percent: float) -> void:
	if is_nan(percent) or is_inf(percent):
		return
	window_scale = max(0.1, percent / 100.0)
	scale_auto_fit = false
	_save_scale()
	_fit()

func _scale_delta(amount: float) -> void:
	_scale_changed(scale_input.value * (1.0 + amount))

func _scale_to_fit() -> void:
	_fit()
	var size = get_viewport().get_visible_rect().size - Vector2(24, 24)
	var stretch = max(0.01, abs(get_viewport().get_final_transform().get_scale().x))
	window_scale = max(0.1, min(size.x / max(1, panel.rect_size.x), size.y / max(1, panel.rect_size.y)) * stretch)
	scale_auto_fit = true
	_save_scale()
	_fit()

func _scale_reset() -> void:
	resizing = false
	window_size = Vector2(520, 820)
	window_scale = 1.0
	scale_auto_fit = true
	panel.rect_position = Vector2(60, 65)
	_save_scale()
	_fit()

func _save_scale() -> void:
	SavedSettings.set_value("editor_plus_scale_percent", window_scale * 100.0)
	SavedSettings.set_value("editor_plus_scale_fit", scale_auto_fit)
	SavedSettings.set_value("editor_plus_window_size", [window_size.x, window_size.y])

func _resize_input(event) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		resizing = event.pressed
		if event.pressed:
			window_size = panel.rect_size
			window_scale = panel.rect_scale.x * max(0.01, abs(get_viewport().get_final_transform().get_scale().x))
			scale_auto_fit = false
		else:
			_save_scale()
	elif event is InputEventMouseMotion and resizing:
		var minimum = panel.get_combined_minimum_size()
		window_size = Vector2(max(minimum.x, window_size.x + event.relative.x), max(minimum.y, window_size.y + event.relative.y))
		_fit()

func _input(event) -> void:
	if resizing and event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
		resizing = false
		_save_scale()
	if panel != null and panel.visible and event is InputEventKey and event.pressed and not event.echo and event.control and event.scancode == KEY_0:
		_scale_reset()
		get_tree().set_input_as_handled()

func _drag(event) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		dragging = event.pressed
		drag_offset = panel.get_global_mouse_position() - panel.rect_position
	elif event is InputEventMouseMotion and dragging:
		panel.rect_position = panel.get_global_mouse_position() - drag_offset
		_fit()

func _style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("343c40")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _label(text: String, size: int = 15, color: Color = Color("eef1ed")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_font_override("font", tool._make_font(max(17,size)))
	label.add_color_override("font_color", color)
	return label

func _row(parent) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	parent.add_child(row)
	return row

func _button(parent, title: String, method: String, args: Array = []) -> Button:
	var button = Button.new()
	button.text = title
	button.add_font_override("font", tool._make_font(17))
	button.add_stylebox_override("normal", _style(Color("22282c")))
	button.add_stylebox_override("hover", _style(Color("30463b")))
	button.add_stylebox_override("pressed", _style(Color("3a5548")))
	button.add_stylebox_override("disabled", _style(Color("1c2226")))
	button.add_color_override("font_color_disabled", Color("68767c"))
	button.connect("pressed", self, method, args)
	parent.add_child(button)
	return button

func _build() -> void:
	panel = PanelContainer.new()
	panel.rect_position = Vector2(60, 65)
	panel.rect_min_size = Vector2(520, 0)
	panel.add_stylebox_override("panel", _style(Color("181c20")))
	var theme = Theme.new()
	theme.default_font = tool._make_font(17)
	for type in ["LineEdit", "SpinBox", "ItemList", "CheckBox", "TabContainer"]:
		theme.set_font("font", type, tool._make_font(17))
		theme.set_color("font_color", type, Color("eef1ed"))
	for type in ["LineEdit", "ItemList"]:
		theme.set_stylebox("normal" if type == "LineEdit" else "bg", type, _style(Color("22282c")))
	theme.set_stylebox("panel", "TabContainer", _style(Color("181c20")))
	theme.set_stylebox("tab_fg", "TabContainer", _style(Color("30463b")))
	theme.set_stylebox("tab_bg", "TabContainer", _style(Color("22282c")))
	panel.theme = theme
	add_child(panel)
	body = VBoxContainer.new()
	body.add_constant_override("separation", 10)
	panel.add_child(body)
	var header = _row(body)
	var title = _label("Editor+", 24, Color("9dd6bd"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.connect("gui_input", self, "_drag")
	header.add_child(title)
	help_button = _button(header, "?", "show_guide")
	help_button.hint_tooltip = "Editor+ tutorial · instructions, examples and diagrams"
	_button(header, "×", "close_window")
	var scale_row = _row(body)
	scale_row.add_child(_label("Scale", 13, Color("9ba8ad")))
	_button(scale_row, "−", "_scale_delta", [-0.1])
	scale_input = SpinBox.new()
	scale_input.min_value = 10
	scale_input.max_value = 1000
	scale_input.allow_greater = true
	scale_input.step = 5
	scale_input.value = window_scale * 100.0
	scale_input.suffix = "%"
	scale_input.rect_min_size.x = 110
	scale_input.hint_tooltip = "Editor+ scale only. No upper cap. Ctrl+0 resets scale and position."
	scale_input.connect("value_changed", self, "_scale_changed")
	scale_row.add_child(scale_input)
	_button(scale_row, "+", "_scale_delta", [0.1])
	_button(scale_row, "Fit", "_scale_to_fit")
	_button(scale_row, "Reset", "_scale_reset")
	selection_label = _label("Open a level in the editor", 14, Color("9ba8ad"))
	body.add_child(selection_label)
	var history_row = _row(body)
	undo_button = _button(history_row, "Undo", "history_step", [false])
	redo_button = _button(history_row, "Redo", "history_step", [true])
	thumbnail_button = _button(history_row, "Thumbnail: Off", "toggle_thumbnail")
	thumbnail_button.hint_tooltip = "Thumbnail mode (T): hides grid lines, selection outlines, the cursor cell and your Goober with its name. Playtests still show your Goober."
	history_row.add_child(_label("Ctrl+Z / Ctrl+Y · T", 13, Color("9ba8ad")))
	section_choice = OptionButton.new()
	section_choice.hint_tooltip = "Choose an Editor+ section"
	body.add_child(section_choice)
	var tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section_choice.connect("item_selected", tabs, "set_current_tab")
	tabs.connect("tab_changed", self, "_section_changed")
	content_scroll = ScrollContainer.new()
	content_scroll.scroll_horizontal_enabled = false
	content_scroll.rect_min_size.y = 160
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content_scroll)
	content_scroll.add_child(tabs)
	var precision = VBoxContainer.new()
	precision.name = "Selection"
	precision.add_constant_override("separation", 8)
	tabs.add_child(precision)
	var nudge_row = _row(precision)
	nudge_row.add_child(_label("Move step", 14))
	step = SpinBox.new()
	step.min_value = 0.01
	step.max_value = 10
	step.step = 0.01
	step.value = 0.25
	step.rect_min_size.x = 85
	nudge_row.add_child(step)
	for entry in [["←", Vector2.LEFT], ["↑", Vector2.UP], ["↓", Vector2.DOWN], ["→", Vector2.RIGHT]]:
		_button(nudge_row, entry[0], "nudge", [entry[1]])
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 8)
	precision.add_child(grid)
	for entry in [["x", "Position X"], ["y", "Position Y"], ["width", "Width"], ["height", "Height"], ["rotation", "Rotation °"], ["pivot_x", "Pivot X"], ["pivot_y", "Pivot Y"]]:
		grid.add_child(_label(entry[1], 14))
		var field = LineEdit.new()
		field.rect_min_size.x = 125
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_font_override("font", tool._make_font(17))
		field.connect("text_entered", self, "_enter_field", [entry[0]])
		grid.add_child(field)
		fields[entry[0]] = field
		if entry[0] in ["width", "height"]:
			field.hint_tooltip = "0.25–1000 grid units. Unanimated blocks, ice blocks and ramps. Keeps grid position and normalized pivot."
		_button(grid, "Apply", "apply_field", [entry[0]])
	var rotate_row = _row(precision)
	_button(rotate_row, "Shape −90°", "rotate_shape", [-1])
	_button(rotate_row, "Shape +90°", "rotate_shape", [1])
	for entry in [["Flip H", true], ["Flip V", false]]:
		var flip = _button(rotate_row, entry[0], "mirror_selection", [entry[1]])
		flip.hint_tooltip = "Mirror supported geometry and position/rotation paths around the selection. Artwork is not texture-flipped."
	precision.add_child(_label("Apply sets one shared value. Arrows move as a group.", 12, Color("9ba8ad")))
	var order_row = _row(precision)
	for entry in [["Back", "back"], ["Backward", "backward"], ["Forward", "forward"], ["Front", "front"]]:
		var button = _button(order_row, entry[0], "change_order", [entry[1]])
		button.hint_tooltip = "Changes sibling order; the game's fixed object-type draw layers remain unchanged."
	precision.add_child(_label("Draw order · within the game's existing layers", 12, Color("9ba8ad")))
	properties = load(get_script().resource_path.get_base_dir().plus_file("EditorProperties.gd")).new()
	properties.build(self)
	tabs.add_child(properties)
	tween_panel = load(get_script().resource_path.get_base_dir().plus_file("EditorTweenPanel.gd")).new()
	tween_panel.build(self)
	tabs.add_child(tween_panel)
	groups_panel = load(get_script().resource_path.get_base_dir().plus_file("EditorGroups.gd")).new()
	groups_panel.build(self)
	tabs.add_child(groups_panel)
	var recovery_page = VBoxContainer.new()
	recovery_page.name = "Recovery"
	tabs.add_child(recovery_page)
	autosave = CheckBox.new()
	autosave.text = "Local autosave · every minute"
	autosave.pressed = bool(SavedSettings.get_value("editor_plus_autosave", true))
	autosave.connect("toggled", self, "_autosave_changed")
	recovery_page.add_child(autosave)
	recovery_list = ItemList.new()
	recovery_list.rect_min_size = Vector2(0, 250)
	recovery_page.add_child(recovery_list)
	var recovery_row = _row(recovery_page)
	_button(recovery_row, "Save snapshot", "snapshot")
	_button(recovery_row, "Restore selected", "_ask_recover")
	recovery_page.add_child(_label("Latest 20 snapshots · Local only · Original files untouched", 12, Color("9ba8ad")))
	library_panel = load(get_script().resource_path.get_base_dir().plus_file("EditorLibrary.gd")).new()
	library_panel.build(self)
	tabs.add_child(library_panel)
	appearance_panel = load(get_script().resource_path.get_base_dir().plus_file("EditorAppearance.gd")).new()
	appearance_panel.build(self)
	tabs.add_child(appearance_panel)
	laser_panel = load(get_script().resource_path.get_base_dir().plus_file("EditorLaserTiming.gd")).new()
	laser_panel.build(self)
	tabs.add_child(laser_panel)
	properties._style_choice(section_choice)
	for child in tabs.get_children():
		section_choice.add_item(child.name)
	message = _label("Select objects in the normal editor to begin.", 13, Color("9ba8ad"))
	message.autowrap = true
	message.rect_min_size = Vector2(0, 36)
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer = _row(body)
	footer.add_child(message)
	resize_grip = _button(footer, "↘", "_refresh")
	resize_grip.disconnect("pressed", self, "_refresh")
	resize_grip.rect_min_size = Vector2(44, 36)
	resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_grip.hint_tooltip = "Drag to resize Editor+. Content scrolls in smaller windows."
	resize_grip.connect("gui_input", self, "_resize_input")
	confirmation = ConfirmationDialog.new()
	confirmation.popup_exclusive = true
	confirmation.connect("confirmed", self, "_recover")
	add_child(confirmation)
	get_viewport().connect("size_changed", self, "_fit")
	panel.hide()

# Thumbnail mode only changes what is drawn: the grid mesh, the tool overlays
# (self_modulate, so tools still take input) and player/spawn-preview renderers
# (modulate alpha). Nothing native is disconnected and everything is restored.
func toggle_thumbnail() -> void:
	thumbnail = not thumbnail
	_apply_thumbnail()

func _apply_thumbnail() -> void:
	if thumbnail_button != null:
		thumbnail_button.text = "Thumbnail: On" if thumbnail else "Thumbnail: Off"
	if not is_instance_valid(editor):
		return
	if editor.grid_renderer != null:
		var mesh = editor.grid_renderer.get_node_or_null("MeshInstance2D")
		if mesh != null:
			mesh.visible = not thumbnail
	for tool_node in [editor.tool_select, editor.tool_create]:
		if is_instance_valid(tool_node):
			tool_node.self_modulate.a = 0.0 if thumbnail else 1.0
	_thumbnail_players()

func _thumbnail_players() -> void:
	var should_hide = thumbnail and is_instance_valid(editor) and not editor.is_playing
	if not should_hide:
		for entry in thumbnail_hidden.values():
			if is_instance_valid(entry.node):
				entry.node.modulate = entry.color
		thumbnail_hidden.clear()
		return
	var found = []
	_thumbnail_collect(get_tree().current_scene, found)
	for node in found:
		var id = node.get_instance_id()
		if not thumbnail_hidden.has(id):
			thumbnail_hidden[id] = {"node": node, "color": node.modulate}
		var color = thumbnail_hidden[id].color
		color.a = 0.0
		node.modulate = color

# Player renderers carry the name tag (UIHolder/UI/Username) and own the Goober spine;
# start blocks show spawn Goobers in LevelEditor_Renderer when selected.
func _thumbnail_collect(node, found: Array) -> void:
	if node == null:
		return
	if node is CanvasItem and node.has_node("UIHolder/UI/Username"):
		found.append(node)
		# The Goober's spine is reparented under the game renderer's PlayerGoobers
		# node, outside the player renderer, so it needs its own entry.
		var spine = node.get("spine")
		if spine is CanvasItem and is_instance_valid(spine):
			found.append(spine)
		return
	if node.name == "LevelEditor_Renderer" and node is Control and node.has_node("SpawnLocationTemplate"):
		found.append(node)
		return
	for child in node.get_children():
		_thumbnail_collect(child, found)

func _autosave_changed(value: bool) -> void:
	SavedSettings.set_value("editor_plus_autosave", value)

func _section_changed(index: int) -> void:
	if section_choice != null and index < section_choice.get_item_count():
		section_choice.select(index)
	call_deferred("_fit")
