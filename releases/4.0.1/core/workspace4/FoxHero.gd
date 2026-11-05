extends Control

# Workspace header: the page title, the welcome banner and the Arctic Fox
# peeking over the banner's top edge with its paws on it.
# Layers: fox back (tail + head) -> banner -> paws. All fox art shares one
# 240 x 200 frame; the banner edge is at y 150 of that frame.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const StarBand = preload("user://mod/core/workspace4/StarBand.gd")
const BAND_HEIGHT = 128.0

var menu
var title: Label
var band
var tail: TextureRect
var face: TextureRect
var paws: TextureRect
var face_open: Texture
var face_blink: Texture
var fox_rect = Rect2()
var next_blink = 3.0
var blink_until = 0.0
var lift = 0.0
var text_box: VBoxContainer
var chips = {}

func build(owner_menu) -> void:
	menu = owner_menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title = menu.label("Workspace", 24)
	add_child(title)
	# Back layers: tail (sways) and head (bobs and blinks), both under the banner.
	tail = _fox_layer("fox-tail.png")
	add_child(tail)
	face_open = Galaxy.texture("fox-face.png")
	face_blink = Galaxy.texture("fox-blink.png")
	face = _fox_layer("fox-face.png")
	add_child(face)
	band = StarBand.new()
	add_child(band)
	text_box = VBoxContainer.new()
	text_box.add_constant_override("separation", 4)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(text_box)
	text_box.add_child(menu.label("Welcome back!", 26, Galaxy.color("band_ink")))
	text_box.add_child(menu.label("Goobplayability 4.0 · pick up where you left off", 15, Galaxy.color("band_sub")))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(row)
	for entry in [["fps", "signal", "— FPS"], ["game", "map", "—"], ["tools", "check", "—"]]:
		var chip = PanelContainer.new()
		var style = Galaxy.box(Color(Galaxy.color("surface").r, Galaxy.color("surface").g, Galaxy.color("surface").b, 0.62), Galaxy.color("border"), 10, 13)
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		chip.add_stylebox_override("panel", style)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner = HBoxContainer.new()
		inner.add_constant_override("separation", 6)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(inner)
		var glyph = TextureRect.new()
		glyph.texture = Galaxy.icon(entry[1], Galaxy.color("ink"), 16)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(glyph)
		var text = menu.label(entry[2], 14)
		inner.add_child(text)
		row.add_child(chip)
		chips[entry[0]] = text
	paws = _fox_layer("fox-paws.png")
	add_child(paws)
	connect("resized", self, "_layout")
	call_deferred("_layout")

func _fox_layer(file: String) -> TextureRect:
	var layer = TextureRect.new()
	layer.texture = Galaxy.texture(file)
	layer.expand = true
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer

func _layout() -> void:
	var width = rect_size.x
	var fox_w = 176.0
	var fox_right = 64.0
	var pad = 96.0
	if width < 560:
		fox_w = 112.0
		fox_right = 16.0
		pad = 62.0
	elif width < 760:
		fox_w = 136.0
		fox_right = 32.0
		pad = 74.0
	var fox_h = fox_w * 200.0 / 240.0
	rect_min_size = Vector2(0, pad + BAND_HEIGHT)
	title.rect_position = Vector2(0, pad - title.get_minimum_size().y - 12)
	band.rect_position = Vector2(0, pad)
	band.rect_size = Vector2(width, BAND_HEIGHT)
	fox_rect = Rect2(Vector2(width - fox_right - fox_w, pad - fox_h * 0.75), Vector2(fox_w, fox_h))
	for layer in [tail, face, paws]:
		layer.rect_position = fox_rect.position
		layer.rect_size = fox_rect.size
	tail.rect_pivot_offset = fox_rect.size * Vector2(166.0 / 240.0, 150.0 / 200.0)
	face.rect_pivot_offset = fox_rect.size * Vector2(100.0 / 240.0, 150.0 / 200.0)
	text_box.rect_position = Vector2(20, 18)
	text_box.rect_size = Vector2(max(120.0, width - fox_w - fox_right - 4), BAND_HEIGHT - 30)

func set_chip(key: String, text: String) -> void:
	if chips.has(key) and is_instance_valid(chips[key]):
		chips[key].text = text

# Idle life: the tail sways, the head bobs and blinks, and the fox perks up
# when the pointer is near. Off with Reduced motion and while hidden.
func _ready():
	connect("visibility_changed", self, "_sync_motion")
	_sync_motion()

func _sync_motion():
	var moving = is_visible_in_tree() and not bool(SavedSettings.get_value("workspace_reduced_motion", false))
	set_process(moving)
	if not moving and face != null:
		tail.rect_rotation = 0
		face.rect_position.y = fox_rect.position.y
		face.texture = face_open

func _process(delta):
	if face == null:
		return
	var time = OS.get_ticks_msec() / 1000.0
	tail.rect_rotation = sin(time * 1.9) * 6.0
	var near = fox_rect.grow(24).has_point(get_local_mouse_position())
	lift = lerp(lift, 7.0 if near else 0.0, min(1.0, delta * 10.0))
	face.rect_position.y = fox_rect.position.y + sin(time * 1.6) * 1.6 - lift
	face.rect_rotation = sin(time * 0.8) * 1.5 + (4.0 if near else 0.0) * (lift / 7.0)
	if time > next_blink:
		blink_until = time + 0.13
		next_blink = time + rand_range(2.6, 5.2)
	face.texture = face_blink if time < blink_until and face_blink != null else face_open
