extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Opening the home screen's Customize tab asks which customizer to use: the
# game's own (unchanged) or Avatar Studio, which then fills the page area
# between the top bar and the bottom bar instead of floating as a window.
var studio
var ui
var paginator
var tabs
var page
var root
var cards = []
var showing = false

func _ready():
	layer = 206
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("node_added", self, "_consider")
	call_deferred("_scan", get_tree().root)

func _scan(node):
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _consider(node):
	if node.name == "HomeScene":
		call_deferred("_attach", weakref(node))

func _attach(reference):
	var home = reference.get_ref()
	if not is_instance_valid(home):
		return
	var content = home.get_node_or_null("MainContentContainer")
	if content == null:
		content = home.get_node_or_null("HomeScene/MainContentContainer")
	var pages = content.get_node_or_null("SafeArea/FocusGroup/Paginator") if content != null else null
	if pages == null or pages.get_node_or_null("CUSTOMIZE") == null:
		return
	paginator = pages
	tabs = content.get_node_or_null("BottomPanel/Tabs")
	page = pages.get_node("CUSTOMIZE")
	if not pages.is_connected("page_changed", self, "_page_changed"):
		pages.connect("page_changed", self, "_page_changed")

func _page_changed(selected):
	if selected == page:
		if not studio.embedded:
			_show()
	else:
		_hide()
		_native(true)
		if studio.embedded:
			studio.close()

# The game's own Customize page stays hidden until Default is picked.
func _native(on):
	if not is_instance_valid(page):
		return
	for child in page.get_children():
		if not child is CanvasItem:
			continue
		if on and child.has_meta("studio_chooser_hidden"):
			child.visible = true
			child.remove_meta("studio_chooser_hidden")
		elif not on and child.visible:
			child.set_meta("studio_chooser_hidden", true)
			child.visible = false

# ------------------------------------------------------------------ chooser
# Fills the Customize page (between the top bar and the bottom tabs) with an
# opaque panel, so the native grid behind it never shows through.
func _build():
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	root = PanelContainer.new()
	root.name = "CustomizeChooser"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var back = ui.flat(ui.NAVY_DEEP, 48, 56, 0, ui.NAVY_DEEP, true)
	back.border_color = ui.NAVY_3
	back.set_border_width_all(4)
	root.add_stylebox_override("panel", back)
	add_child(root)
	var col = ui.box(root, true, 36)
	var head = ui.box(col, true, 4)
	ui.label(head, "Customize", "title", ui.WHITE, Label.ALIGN_CENTER).autowrap = false
	ui.label(head, "Choose how you want to dress your Goober", "body", ui.MUTED, Label.ALIGN_CENTER).autowrap = false
	var row = ui.box(col, false, 40)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards = [_card(row, "Default", "The game's own outfits and cosmetics", _native_icon(), ui.SKY_LIGHT, Color("1f5f9f"), "_pick_default"),
		_card(row, "Avatar Studio", "Layers, colours, textures and saved Looks", _studio_icon(), ui.PINK_LIGHT, Color("7c2f73"), "_pick_studio")]
	ui.label(col, "Esc uses Default", "small", ui.FAINT, Label.ALIGN_CENTER).autowrap = false
	root.hide()
	get_viewport().connect("size_changed", self, "_fit")

func _card(parent, name, detail, texture, accent, art_color, method):
	var card = ui.card(parent, ui.NAVY, 30, 40)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.clickable(card, self, method, null, ui.NAVY_2)
	var col = ui.box(card, true, 22)
	var art = PanelContainer.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look = ui.flat(art_color, 30, 24, 0, ui.NAVY_DEEP, false)
	look.border_width_top = 6
	look.border_color = art_color.lightened(0.25)
	art.add_stylebox_override("panel", look)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.rect_min_size = Vector2(0, 260)
	col.add_child(art)
	var icon = TextureRect.new()
	icon.texture = texture
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.rect_min_size = Vector2(220, 220)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.add_child(icon)
	var foot = ui.box(col, false, 18)
	var words = ui.grow(ui.box(foot, true, 2))
	ui.label(words, name, "h1", ui.WHITE).autowrap = false
	ui.label(words, detail, "small", ui.MUTED).autowrap = false
	var go = ui.pill(foot, "Open", ui.INK, accent, "chevron_right")
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card

func _native_icon():
	var button = tabs.get_node_or_null("CustomizeTab") if is_instance_valid(tabs) else null
	var texture = button.get("icon_tex") if button != null else null
	return texture if texture is Texture else ui.art.texture("icon_palette")

func _studio_icon():
	var image = Image.new()
	if image.load(ModPaths.ICONS_DIR + "cosmetic_sandbox.png") != OK:
		return ui.art.texture("icon_goober")
	# The toolbar icon sits on a dark tile; drop the tile so only the glyph shows.
	image.convert(Image.FORMAT_RGBA8)
	image.lock()
	for y in image.get_height():
		for x in image.get_width():
			var c = image.get_pixel(x, y)
			var light = max(c.r, max(c.g, c.b))
			c.a *= clamp((light - 0.34) / 0.25, 0.0, 1.0)
			image.set_pixel(x, y, c)
	image.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return texture

func _fit():
	if root == null:
		return
	var area = frame_rect()
	if area == null:
		var size = get_viewport().get_visible_rect().size
		area = Rect2(size * 0.06, size * 0.88)
	# Laid out on a 1600x860 design canvas, scaled to the page area.
	var factor = max(0.2, min(area.size.x / 1600.0, area.size.y / 860.0))
	root.rect_scale = Vector2.ONE * factor
	root.rect_position = area.position
	root.rect_size = area.size / factor

func _show():
	if root == null:
		_build()
	_native(false)
	_fit()
	root.show()
	showing = true
	if ui.has_method("pop_in"):
		var tween = Tween.new()
		root.add_child(tween)
		for i in cards.size():
			ui.pop_in(tween, cards[i], 0.05 * i, 0.28, 0.92)
		tween.start()
		tween.connect("tween_all_completed", tween, "queue_free")
	if is_instance_valid(cards[0]):
		cards[0].grab_focus()

func _hide():
	if root != null:
		root.hide()
	showing = false

func _pick_default():
	_hide()
	_native(true)

func _pick_studio():
	_hide()
	studio.embed(self)

func _input(event):
	if showing and event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_ESCAPE:
		_pick_default()
		get_tree().set_input_as_handled()

# Where the embedded Studio goes, in canvas pixels: the page area between the
# native identity bar and the bottom bar.
func frame_rect():
	if not is_instance_valid(paginator):
		return null
	var transform = paginator.get_global_transform_with_canvas()
	var scale = transform.get_scale().abs()
	var top = transform.origin.y + 112 * scale.y
	var bottom = transform.origin.y + paginator.rect_size.y * scale.y - 16 * scale.y
	var panel = tabs.get_parent_control().get_node_or_null("Panel") if is_instance_valid(tabs) else null
	if panel != null:
		bottom = min(bottom, panel.get_global_transform_with_canvas().origin.y - 12 * scale.y)
	var left = transform.origin.x + 24 * scale.x
	var right = transform.origin.x + paginator.rect_size.x * scale.x - 24 * scale.x
	if right - left < 400 or bottom - top < 300:
		return null
	return Rect2(left, top, right - left, bottom - top)

# The embedded Studio was closed with its × button: back to the home page.
func studio_closed():
	if not is_instance_valid(paginator) or not is_instance_valid(tabs):
		return
	var index = paginator.pages.find(paginator.get_node_or_null("HOME"))
	if index >= 0 and paginator.get("current_page") != paginator.get_node_or_null("HOME"):
		tabs.get_node("ButtonGrouper").set_selected(index)
	call_deferred("_still_here")

# Still on Customize after closing: offer the choice again instead of the native page.
func _still_here():
	if is_instance_valid(page) and page.is_visible_in_tree() and not studio.embedded and not showing:
		_show()
