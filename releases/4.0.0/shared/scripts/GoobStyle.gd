extends Reference

# Shared Goobplayability look for module windows (4.0 galaxy neutrals): dark panels, coloured edges,
# and consistent inputs (text fields, pickers, lists, check boxes, scroll bars).
# style_tree() only touches controls that have no look of their own yet, or
# that were left on the game's default theme.

const BG = Color("14162d")
const SURFACE = Color("1a1d38")
const RAISED = Color("202441")
const EDGE = Color("2c2f55")
const INK = Color("f5f3ff")
const MUTED = Color("b8b7d6")
const MINT = Color("7fe0b4")
const SKY = Color("6fb8ff")
const VIOLET = Color("b49cff")
const ROSE = Color("ff8ec6")
const AMBER = Color("ffc46b")
const RED = Color("ff7f8a")

static func box(fill: Color, line: Color = EDGE, padding: int = 12, corner: int = 8) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner)
	style.corner_detail = 8
	style.anti_aliasing = true
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

# A card with a coloured edge on the left only.
static func card(edge: Color, fill: Color = SURFACE) -> StyleBoxFlat:
	var style = box(fill, edge, 14, 10)
	style.set_border_width_all(0)
	style.border_width_left = 3
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func arrow_icon() -> Texture:
	var image = Image.new()
	image.create(12, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	for y in range(8):
		for x in range(12):
			var middle = abs(x - 5.5)
			if middle <= 5.5 - y * 0.85 and middle >= 5.5 - y * 0.85 - 1.8 and y < 7:
				image.set_pixel(x, y, MUTED)
	image.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER)
	return texture

static func style_input(control: Control, accent: Color = MINT) -> void:
	control.set_meta("goob_styled", true)
	if control is LineEdit:
		control.add_stylebox_override("normal", box(BG, EDGE, 10))
		control.add_stylebox_override("focus", box(BG, accent, 10))
		control.add_stylebox_override("read_only", box(SURFACE, EDGE, 10))
		control.add_color_override("font_color", INK)
		control.add_color_override("font_color_uneditable", MUTED)
		control.add_color_override("cursor_color", accent)
		control.add_color_override("selection_color", Color(accent.r, accent.g, accent.b, 0.35))
		control.add_color_override("clear_button_color", MUTED)
	elif control is OptionButton:
		control.add_stylebox_override("normal", box(BG, EDGE, 10))
		control.add_stylebox_override("hover", box(RAISED, accent.darkened(0.2), 10))
		control.add_stylebox_override("pressed", box(RAISED, accent, 10))
		control.add_stylebox_override("focus", StyleBoxEmpty.new())
		control.add_stylebox_override("disabled", box(SURFACE, EDGE, 10))
		control.add_color_override("font_color", INK)
		control.add_color_override("font_color_hover", INK)
		control.add_color_override("font_color_pressed", accent)
		control.add_icon_override("arrow", arrow_icon())
		control.focus_mode = Control.FOCUS_NONE
		style_popup(control.get_popup(), accent)
		if control.has_font_override("font"):
			control.get_popup().add_font_override("font", control.get_font("font"))
	elif control is ItemList:
		control.add_stylebox_override("bg", box(BG, EDGE, 8))
		control.add_stylebox_override("bg_focus", box(BG, EDGE, 8))
		control.add_stylebox_override("selected", box(Color(accent.r, accent.g, accent.b, 0.18), Color(accent.r, accent.g, accent.b, 0.18), 4, 6))
		control.add_stylebox_override("selected_focus", box(Color(accent.r, accent.g, accent.b, 0.22), accent, 4, 6))
		control.add_stylebox_override("cursor", StyleBoxEmpty.new())
		control.add_stylebox_override("cursor_unfocused", StyleBoxEmpty.new())
		control.add_color_override("font_color", Color("dfe6e1"))
		control.add_color_override("font_color_selected", accent.lightened(0.2))
		control.add_color_override("guide_color", Color(0, 0, 0, 0))
		control.add_constant_override("vseparation", 6)
	elif control is CheckBox or control is CheckButton:
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			control.add_stylebox_override(state, StyleBoxEmpty.new())
		control.add_color_override("font_color", INK)
		control.add_color_override("font_color_hover", accent.lightened(0.2))
		control.add_color_override("font_color_pressed", INK)
		control.add_color_override("font_color_hover_pressed", accent.lightened(0.2))
		control.focus_mode = Control.FOCUS_NONE
	elif control is SpinBox:
		style_input(control.get_line_edit(), accent)

static func style_popup(popup: PopupMenu, accent: Color = MINT) -> void:
	popup.add_stylebox_override("panel", box(SURFACE, EDGE, 6))
	popup.add_stylebox_override("hover", box(Color(accent.r, accent.g, accent.b, 0.2), Color(accent.r, accent.g, accent.b, 0.2), 6, 6))
	popup.add_color_override("font_color", INK)
	popup.add_color_override("font_color_hover", accent.lightened(0.2))
	popup.add_constant_override("vseparation", 8)

static func style_scrollbar(bar: ScrollBar) -> void:
	bar.add_stylebox_override("scroll", StyleBoxEmpty.new())
	bar.add_stylebox_override("scroll_focus", StyleBoxEmpty.new())
	for entry in [["grabber", EDGE], ["grabber_highlight", MUTED.darkened(0.3)], ["grabber_pressed", MINT.darkened(0.3)]]:
		var style = box(entry[1], entry[1], 3, 4)
		bar.add_stylebox_override(entry[0], style)

# Walks a window and gives inputs, lists and scroll bars the shared look.
static func style_tree(node: Node, accent: Color = MINT) -> void:
	if node is Control and not node.has_meta("goob_styled") and not node.has_meta("council_styled"):
		if node is LineEdit or node is OptionButton or node is ItemList or node is CheckBox or node is CheckButton or node is SpinBox:
			style_input(node, accent)
		elif node is ScrollBar:
			style_scrollbar(node)
		elif node is Label:
			node.add_color_override("font_color_shadow", Color.transparent)
		elif node is PopupPanel:
			node.add_stylebox_override("panel", box(SURFACE, EDGE, 14, 10))
	for child in node.get_children():
		style_tree(child, accent)

# Text size: fonts handed in here grow with the Workspace text size (Settings >
# Appearance), so module windows stay readable at a low UI scale.
static func remember_font(font) -> void:
	if not font is DynamicFont or font.has_meta("goob_base_size"):
		return
	font.set_meta("goob_base_size", font.size)
	var fonts = Engine.get_meta("goob_fonts") if Engine.has_meta("goob_fonts") else []
	fonts.append(weakref(font))
	Engine.set_meta("goob_fonts", fonts)
	var k = float(Engine.get_meta("goob_text_k")) if Engine.has_meta("goob_text_k") else 1.0
	font.size = int(round(int(font.get_meta("goob_base_size")) * k))

static func remember_tree(node: Node) -> void:
	if node is Control:
		for name in ["font", "normal_font", "bold_font"]:
			if node.has_font_override(name):
				remember_font(node.get_font(name))
	if node is OptionButton:
		remember_tree(node.get_popup())
	for child in node.get_children():
		remember_tree(child)

static func set_text_scale(k: float) -> void:
	Engine.set_meta("goob_text_k", k)
	var alive = []
	for reference in (Engine.get_meta("goob_fonts") if Engine.has_meta("goob_fonts") else []):
		var font = reference.get_ref()
		if font == null:
			continue
		alive.append(reference)
		var size = int(round(int(font.get_meta("goob_base_size")) * k))
		if font.size != size:
			font.size = size
	Engine.set_meta("goob_fonts", alive)
