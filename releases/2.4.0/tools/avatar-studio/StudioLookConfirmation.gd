extends Control

# Avatar Studio's own components, not the game's inherited WindowDialog theme.
signal confirmed
var studio
var host: Control
var panel: PanelContainer
var cancel_button: Button
var delete_button: Button
var closed = false

func build(source, look_name: String) -> void:
	studio = source
	host = get_parent()
	pause_mode = Node.PAUSE_MODE_PROCESS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	theme = studio.sandbox.get("_modal_panel").theme
	host.connect("visibility_changed", self, "_owner_visibility_changed")
	connect("resized", self, "_fit")
	var shade = ColorRect.new()
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.color = Color(0.04, 0.055, 0.065, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.connect("gui_input", self, "_backdrop_input")
	add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.name = "ConfirmationCard"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var surface = studio.style(studio.BG, studio.LINE)
	surface.set_corner_radius_all(12)
	surface.content_margin_left = 22
	surface.content_margin_right = 22
	surface.content_margin_top = 18
	surface.content_margin_bottom = 22
	panel.add_stylebox_override("panel", surface)
	center.add_child(panel)
	var content = studio.column(panel)
	content.add_constant_override("separation", 16)
	var header = studio.row(content)
	var eyebrow = studio.label("SAVED LOOK", 12, studio.ACCENT)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(eyebrow)
	var close_button = studio.button("×", "")
	close_button.rect_min_size = Vector2(32,32)
	close_button.hint_tooltip = "Cancel deletion"
	close_button.connect("pressed", self, "_cancel")
	header.add_child(close_button)
	var title = studio.label("Delete saved Look?", 24)
	title.autowrap = true
	content.add_child(title)
	var selected = PanelContainer.new()
	selected.add_stylebox_override("panel", studio.style(studio.PANEL))
	content.add_child(selected)
	var name_label = studio.label(look_name, 17)
	name_label.autowrap = true
	name_label.hint_tooltip = look_name
	selected.add_child(name_label)
	var note = studio.label("Only this saved Look will be removed.\nYour current appearance stays unchanged.", 15, studio.DIM)
	note.autowrap = true
	content.add_child(note)
	var actions = studio.row(content)
	actions.add_constant_override("separation", 10)
	cancel_button = studio.button("Cancel", "")
	cancel_button.name = "Cancel"
	cancel_button.connect("pressed", self, "_cancel")
	delete_button = studio.button("Delete Look", "")
	delete_button.name = "DeleteLook"
	delete_button.connect("pressed", self, "_confirm")
	delete_button.add_stylebox_override("normal", studio.style(Color("3d2c32"), Color("78545f")))
	delete_button.add_stylebox_override("hover", studio.style(Color("50363f"), Color("bc8798")))
	delete_button.add_stylebox_override("pressed", studio.style(Color("342329"), Color("bc8798")))
	delete_button.add_color_override("font_color", Color("f1ced9"))
	delete_button.add_color_override("font_color_hover", Color("ffe4ed"))
	delete_button.add_color_override("font_color_pressed", Color("f1ced9"))
	for action in [cancel_button,delete_button]:
		action.rect_min_size = Vector2(0,42)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.focus_mode = Control.FOCUS_ALL
		action.add_stylebox_override("focus", studio.style(Color(0,0,0,0),studio.ACCENT))
		actions.add_child(action)
	_fit()
	cancel_button.call_deferred("grab_focus")

func _fit() -> void:
	if not is_instance_valid(panel): return
	panel.rect_min_size.x = clamp(rect_size.x-32, min(280.0,rect_size.x), 480.0)

func _owner_visibility_changed() -> void:
	if not host.is_visible_in_tree(): _cancel()

func _backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		accept_event()
		_cancel()

func _input(event: InputEvent) -> void:
	if closed or not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel()
		elif event.scancode in [KEY_ENTER,KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			if delete_button.has_focus(): _confirm()
			else: _cancel()

func _confirm() -> void:
	if closed: return
	closed = true
	emit_signal("confirmed")
	hide()
	queue_free()

func _cancel() -> void:
	if closed: return
	closed = true
	hide()
	queue_free()
