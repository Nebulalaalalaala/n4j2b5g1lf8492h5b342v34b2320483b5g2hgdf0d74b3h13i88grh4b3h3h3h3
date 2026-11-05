extends PanelContainer

# A 4.0 settings row (icon, title, short description, switch) that wraps an
# existing tool button. The button stays the real control: it sits invisibly
# over the whole row, so clicks, shortcuts, tooltips and the tool's own
# text/style updates keep working. The row reads the button each frame to
# show the switch state.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")

var button: Button = null
var on_text := ""
var _switch: Control = null
var _title: Label = null
var _icon: TextureRect = null
var _icon_name := ""
var _hover := false
var _on := false
var _disabled := false

class Switch:
	extends Control
	var on := false
	var t := 0.0
	func _init():
		rect_min_size = Vector2(42, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw():
		var Gx = load("user://mod/core/workspace4/Galaxy.gd")
		var track = Gx.color("line").linear_interpolate(Gx.color("accent"), t)
		var r = rect_size.y / 2.0
		draw_circle(Vector2(r, r), r, track)
		draw_circle(Vector2(rect_size.x - r, r), r, track)
		draw_rect(Rect2(r, 0, rect_size.x - r * 2.0, rect_size.y), track)
		var knob_x = lerp(r, rect_size.x - r, t)
		draw_circle(Vector2(knob_x, r), r - 3.0, Color(1, 1, 1))


func setup(target: Button, title: String, description: String, icon_name: String, title_font: Font, small_font: Font, on_label: String = "") -> void:
	button = target
	on_text = on_label
	_icon_name = icon_name
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content = HBoxContainer.new()
	content.add_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	if not icon_name.empty():
		_icon = TextureRect.new()
		_icon.rect_min_size = Vector2(22, 22)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(_icon)
	var text_box = VBoxContainer.new()
	text_box.add_constant_override("separation", 1)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(text_box)
	_title = Label.new()
	_title.text = title
	_title.add_font_override("font", title_font)
	_title.add_color_override("font_color", Galaxy.color("ink"))
	text_box.add_child(_title)
	if not description.empty():
		var desc = Label.new()
		desc.text = description
		desc.autowrap = true
		desc.add_font_override("font", small_font)
		desc.add_color_override("font_color", Galaxy.color("muted"))
		text_box.add_child(desc)
	_switch = Switch.new()
	content.add_child(_switch)
	# The real button goes on top, covering the row.
	if button.get_parent() != null:
		button.get_parent().remove_child(button)
	button.rect_min_size = Vector2.ZERO
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.self_modulate = Color(1, 1, 1, 0)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	button.connect("mouse_entered", self, "_set_hover", [true])
	button.connect("mouse_exited", self, "_set_hover", [false])
	button.connect("visibility_changed", self, "_button_visibility")
	connect("visibility_changed", self, "_activity")
	_sync(true)
	call_deferred("_activity")

func _button_visibility() -> void:
	if is_instance_valid(button) and visible != button.visible: visible = button.visible
	_activity()

func _activity() -> void:
	var active = is_visible_in_tree()
	set_process(active)
	if active and is_instance_valid(button): _sync(true)


func _set_hover(value: bool) -> void:
	_hover = value
	_restyle()


func _restyle() -> void:
	var fill = Galaxy.color("hover") if _hover and not _disabled else Galaxy.color("raised")
	var line = Galaxy.color("accent") if _on else Galaxy.color("border")
	var style = Galaxy.box(fill, line, 12, 10)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	add_stylebox_override("panel", style)
	if _icon != null:
		_icon.texture = Galaxy.icon(_icon_name, Galaxy.color("accent") if _on else Galaxy.color("muted"), 20)


func _is_on() -> bool:
	if button.toggle_mode:
		return button.pressed
	var text = button.text.strip_edges()
	if not on_text.empty():
		return text == on_text
	return text.ends_with("ON")


func _process(_delta: float) -> void:
	if button == null or not is_instance_valid(button):
		return
	if visible != button.visible:
		visible = button.visible
	if not is_visible_in_tree():
		return
	_sync(false)
	var goal = 1.0 if _on else 0.0
	if abs(_switch.t - goal) > 0.001:
		_switch.t = move_toward(_switch.t, goal, _delta * 8.0)
		_switch.update()


func _sync(force: bool) -> void:
	var on = _is_on()
	var disabled = button.disabled
	if force or on != _on or disabled != _disabled:
		_on = on
		_disabled = disabled
		modulate.a = 0.5 if disabled else 1.0
		if force:
			_switch.on = on
			_switch.t = 1.0 if on else 0.0
			_switch.update()
		_restyle()
