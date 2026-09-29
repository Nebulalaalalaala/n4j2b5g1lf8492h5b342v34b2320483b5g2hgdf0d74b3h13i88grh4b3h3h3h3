extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Dims the screen around one control, rings it and shows a caption with buttons.
# The ringed control stays clickable. show_step() again to move on; clear() hides it.
signal pressed(id)
signal lost   # the ringed control was freed (e.g. its menu was rebuilt)

const DIM = Color(0.0, 0.025, 0.08, 0.62)
const BG = Color("181c20")
const BORDER = Color("343c40")
const INK = Color("f0f1eb")
const MUTED = Color("9ba8ad")
const MINT = Color("9dd6bd")
const PAD = 6.0

var ui_scale = 1.0
var target = null
var shown_key = ""
var dims = []
var ring
var bubble
var caption
var actions
var tween
var fonts = {}
var clock = 0.0
var active = false


func _ready():
	layer = 250
	pause_mode = Node.PAUSE_MODE_PROCESS
	for i in 4:
		var dim = ColorRect.new()
		dim.color = DIM
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(dim)
		dims.append(dim)
	ring = Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line = StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = MINT
	line.set_border_width_all(3)
	line.set_corner_radius_all(10)
	ring.add_stylebox_override("panel", line)
	add_child(ring)
	bubble = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 10
	bubble.add_stylebox_override("panel", style)
	add_child(bubble)
	var column = VBoxContainer.new()
	column.add_constant_override("separation", 12)
	bubble.add_child(column)
	caption = Label.new()
	caption.autowrap = true
	caption.rect_min_size.x = 380
	if _font(19) != null:
		caption.add_font_override("font", _font(19))
	caption.add_color_override("font_color", INK)
	column.add_child(caption)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGN_END
	actions.add_constant_override("separation", 10)
	column.add_child(actions)
	tween = Tween.new()
	add_child(tween)
	clear()


# target: a Control to ring, or null for a caption pill at the top of the screen.
# buttons: [[text, id, primary], ...]
func show_step(new_target, text: String, buttons: Array) -> void:
	var key = text + str(new_target.get_instance_id() if new_target != null else 0)
	target = new_target
	if key == shown_key:
		return
	shown_key = key
	active = true
	caption.text = text
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	for entry in buttons:
		actions.add_child(_button(entry[0], entry[1], entry.size() > 2 and entry[2]))
	bubble.rect_size = Vector2.ZERO
	bubble.visible = true
	call_deferred("_scroll_into_view")
	ring.visible = target != null
	for dim in dims:
		dim.visible = target != null
	_place()
	tween.stop_all()
	bubble.modulate.a = 0.0
	tween.interpolate_property(bubble, "modulate:a", 0.0, 1.0, 0.25)
	if target != null:
		ring.rect_scale = Vector2.ONE * 1.12
		tween.interpolate_property(ring, "rect_scale", Vector2.ONE * 1.12, Vector2.ONE, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
		for dim in dims:
			if dim.modulate.a < 1.0:
				tween.interpolate_property(dim, "modulate:a", dim.modulate.a, 1.0, 0.3)
	tween.start()


func clear() -> void:
	active = false
	target = null
	shown_key = ""
	bubble.visible = false
	ring.visible = false
	for dim in dims:
		dim.visible = false
		dim.modulate.a = 0.0


func _process(delta):
	clock += delta
	if not active:
		return
	if target != null and not is_instance_valid(target):
		clear()
		emit_signal("lost")
		return
	var showing = target == null or target.is_visible_in_tree()
	bubble.visible = showing
	ring.visible = showing and target != null
	for dim in dims:
		dim.visible = showing and target != null
	if not showing:
		return
	_place()
	ring.self_modulate.a = 0.75 + 0.25 * sin(clock * 3.0)


func _place() -> void:
	var view = get_viewport().get_visible_rect().size
	var scale = ui_scale / max(0.01, abs(get_viewport().get_final_transform().get_scale().x))
	bubble.rect_scale = Vector2.ONE * scale
	var size = bubble.get_combined_minimum_size() * scale
	if target == null:
		bubble.rect_position = Vector2((view.x - size.x) * 0.5, 24.0 * scale)
		return
	var hole = _canvas_rect(target).grow(PAD)
	# Only the part that is actually on screen (inside any scrolling list).
	var parent = target.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			hole = hole.clip(_canvas_rect(parent))
		parent = parent.get_parent() if parent is Control else null
	hole = hole.clip(Rect2(Vector2.ZERO, view))
	dims[0].rect_position = Vector2.ZERO
	dims[0].rect_size = Vector2(view.x, max(0.0, hole.position.y))
	dims[1].rect_position = Vector2(0, hole.end.y)
	dims[1].rect_size = Vector2(view.x, max(0.0, view.y - hole.end.y))
	dims[2].rect_position = Vector2(0, hole.position.y)
	dims[2].rect_size = Vector2(max(0.0, hole.position.x), hole.size.y)
	dims[3].rect_position = Vector2(hole.end.x, hole.position.y)
	dims[3].rect_size = Vector2(max(0.0, view.x - hole.end.x), hole.size.y)
	ring.rect_position = hole.position
	ring.rect_size = hole.size
	ring.rect_pivot_offset = hole.size * 0.5
	var gap = 16.0 * scale
	var spot = Vector2(hole.end.x + gap, hole.position.y)
	if spot.x + size.x > view.x - gap:
		spot.x = hole.position.x - gap - size.x
	if spot.x < gap:
		spot = Vector2(clamp(hole.position.x, gap, view.x - size.x - gap), hole.end.y + gap)
		if spot.y + size.y > view.y - gap:
			spot.y = hole.position.y - gap - size.y
	spot.y = clamp(spot.y, gap, max(gap, view.y - size.y - gap))
	bubble.rect_position = spot


func _canvas_rect(control: Control) -> Rect2:
	var t = control.get_global_transform_with_canvas()
	return Rect2(t.origin, control.rect_size * t.get_scale())


func _scroll_into_view() -> void:
	if target == null or not is_instance_valid(target):
		return
	var parent = target.get_parent()
	while parent != null and parent is Control:
		if parent is ScrollContainer:
			parent.ensure_control_visible(target)
			return
		parent = parent.get_parent()


func _button(text: String, id: String, primary: bool) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _font(16) != null:
		b.add_font_override("font", _font(16))
	b.add_color_override("font_color", BG if primary else MUTED)
	b.add_color_override("font_color_hover", BG if primary else INK)
	for state in ["normal", "hover", "pressed"]:
		var s = StyleBoxFlat.new()
		s.bg_color = MINT if primary else Color(0, 0, 0, 0)
		if primary and state != "normal":
			s.bg_color = MINT.lightened(0.15)
		s.set_corner_radius_all(8)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		b.add_stylebox_override(state, s)
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.connect("pressed", self, "emit_signal", ["pressed", id])
	return b


func _font(size: int) -> Font:
	if not fonts.has(size):
		fonts[size] = null
		var data = load(ModPaths.MAIN_FONT) if File.new().file_exists(ModPaths.MAIN_FONT) else null
		if data is DynamicFontData:
			var font = DynamicFont.new()
			font.font_data = data
			font.size = size
			fonts[size] = font
	return fonts[size]
