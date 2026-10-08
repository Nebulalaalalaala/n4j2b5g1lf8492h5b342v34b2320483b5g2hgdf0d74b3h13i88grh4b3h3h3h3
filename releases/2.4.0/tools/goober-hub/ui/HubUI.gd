extends "user://mod/tools/journey/ui/JourneyUI.gd"
# Goober Hub's design kit: Journey type and art, a warmer social palette.
const BASE = Color("0b2149")
const PANEL = Color("13306a")
const INSET = Color("1c4182")
const EDGE = Color("3a63a8")
const SOFT = Color("c3d8f5")
const DIM = Color("8eaedb")
const HUB_PINK = Color("ff69b4")
const MINT = Color("5fe3b8")
const GOLD = Color("ffd34d")
const LILAC = Color("b9a6ff")
const SKY = Color("7cc4ff")
const CLAN_COLORS = [Color("ff69b4"), Color("7cc4ff"), Color("5fe3b8"), Color("ffd34d"), Color("b9a6ff"), Color("ff8a5c"), Color("ff5f6d"), Color("9be15d")]
const REACTIONS = [["gg", "GG"], ["fire", "Fire"], ["wow", "Wow"], ["clap", "Clap"], ["heart", "Love"]]
const REACTION_GLYPHS = {"gg": "flag", "fire": "sparkle", "wow": "star", "clap": "check", "heart": "goober"}
var thumbnail_shader

func _init(journey_art).(journey_art):
	pass

# look: {"body", "dark", "hat", "hat_color"} from HubProfiles.look_for, or null
# for a name-based colour until the player's profile has loaded.
func goober(parent, look, size = 46, fallback_id = ""):
	var g = load(ModPaths.path("HubMiniGoober.gd")).new()
	g.rect_min_size = Vector2(size, size)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.size_flags_horizontal = 0
	g.mouth = int(abs(str(fallback_id).hash())) % 3
	if look is Dictionary:
		g.body = look.body
		g.dark = look.dark
		g.hat = str(look.get("hat", ""))
		g.hat_color = look.get("hat_color", Color.white)
	else:
		g.body = name_color(fallback_id)
		g.dark = g.body.darkened(0.35)
	if parent != null:
		parent.add_child(g)
	return g

func page_color(page):
	return {"Home": HUB_PINK, "Profile": GOLD, "Clans": LILAC, "Passport": MINT, "Messages": SKY}.get(page, HUB_PINK)

func text(parent, value, size = 22, color = WHITE):
	var item = Label.new()
	item.text = str(value)
	item.add_font_override("font", font("text", size))
	item.add_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.valign = Label.VALIGN_CENTER
	if parent != null:
		parent.add_child(item)
	return item

func title(parent, value, size = 34, color = WHITE):
	var item = text(parent, value, size, color)
	item.add_font_override("font", font("display", size))
	return item

func wrap(parent, value, size = 20, color = SOFT):
	var item = text(parent, value, size, color)
	item.autowrap = true
	item.valign = Label.VALIGN_TOP
	grow(item)
	return item

func surface(parent, fill = PANEL, pad = 22, radius = 24):
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look = flat(fill, radius, pad, 5, fill.darkened(0.42), true)
	look.shadow_size = 10
	look.shadow_offset = Vector2(0, 6)
	look.shadow_color = Color(0, 0.06, 0.18, 0.22)
	panel.add_stylebox_override("panel", look)
	if parent != null:
		parent.add_child(panel)
	return panel

func inset(parent, pad = 14, radius = 18, fill = INSET):
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_stylebox_override("panel", flat(fill, radius, pad, 0, BASE, false))
	if parent != null:
		parent.add_child(panel)
	return panel

func action(parent, value, target, method, arg = null, kind = "quiet", glyph = "", accent = HUB_PINK):
	var b = load(ModPaths.path("HubButton.gd")).new()
	b.configure(value, font("text", 20), art.texture("icon_" + glyph) if not glyph.empty() else null)
	b.size_flags_horizontal = 0
	parent.add_child(b)
	if target != null and not method.empty():
		if arg == null:
			b.connect("pressed", target, method)
		else:
			b.connect("pressed", target, method, [arg])
	paint_action(b, kind, accent)
	return b

func paint_action(button, kind = "quiet", accent = HUB_PINK):
	var fill = INSET
	var ink = WHITE
	var edge = BASE.darkened(0.1)
	if kind == "primary":
		fill = GOLD
		ink = BASE
		edge = fill.darkened(0.25)
	elif kind == "accent":
		fill = HUB_PINK
		ink = BASE
		edge = Color("c23b85")
	elif kind in ["secondary", "selected"]:
		fill = Color("f2f7ff")
		ink = BASE
		edge = Color("8db2dc")
	elif kind == "tab":
		fill = PANEL
		edge = PANEL
	elif kind == "danger":
		fill = Color("4a2346")
		ink = Color("ffb3c6")
		edge = Color("2a1028")
	button.glossy = kind != "tab"
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var bg = fill.lightened(0.12) if state in ["hover", "focus"] else fill
		var color = ink
		if state == "pressed":
			bg = fill.darkened(0.08)
		if state == "disabled":
			bg = Color("1a3360")
			color = Color("7092be")
		var look = flat(bg, 18, 16, 0 if state in ["pressed", "disabled"] or kind == "tab" else 4, bg.darkened(0.25) if state == "disabled" else edge, false)
		look.content_margin_top = 7
		look.content_margin_bottom = 7
		if state == "focus":
			look.set_border_width_all(2)
			look.border_color = accent
		button.add_stylebox_override(state, look)
		button.add_color_override("font_color" + ("" if state == "normal" else "_" + state), color)
		button.add_color_override("icon_color_" + state, color if kind in ["primary", "accent", "secondary", "selected", "danger"] or state == "disabled" else accent)

func section(parent, name, glyph = "", trailing = "", color = HUB_PINK):
	var row = box(parent, false, 10)
	if not glyph.empty():
		icon(row, glyph, 26, color)
	var heading = title(row, name, 27)
	heading.add_color_override("font_color_shadow", BASE)
	heading.add_constant_override("shadow_offset_y", 2)
	spacer(row)
	if not trailing.empty():
		var note = text(row, trailing, 17, WHITE)
		note.add_color_override("font_color_shadow", BASE)
		note.add_constant_override("shadow_offset_y", 2)
	return row

func stat(parent, value, caption, color = WHITE, glyph = ""):
	var panel = inset(parent, 16, 20)
	grow(panel)
	var row = box(panel, false, 12)
	if not glyph.empty():
		icon(row, glyph, 30, color)
	var col = box(row, true, 0)
	grow(col)
	title(col, str(value), 32, color)
	text(col, caption, 15, DIM)
	return panel

func tag(parent, value, accent = GOLD, ink = BASE):
	var panel = inset(parent, 9, 10, accent)
	panel.size_flags_horizontal = 0
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var look = panel.get_stylebox("panel")
	look.content_margin_top = 3
	look.content_margin_bottom = 3
	text(panel, value, 14, ink).align = Label.ALIGN_CENTER
	return panel

# Round initial bubble used wherever a player appears in a list.
func bubble(parent, name, size = 46, color = HUB_PINK):
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.rect_min_size = Vector2.ONE * size
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.size_flags_horizontal = 0
	var look = flat(color.darkened(0.15), int(size / 2), 0, 3, color.darkened(0.5), false)
	panel.add_stylebox_override("panel", look)
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)
	var initial = str(name).strip_edges().left(1).to_upper()
	title(center, initial if not initial.empty() else "?", int(size * 0.5), BASE)
	if parent != null:
		parent.add_child(panel)
	return panel

static func name_color(id) -> Color:
	return CLAN_COLORS[int(abs(str(id).hash())) % CLAN_COLORS.size()]

func empty(parent, name, detail = "", glyph = "goober", color = HUB_PINK):
	var panel = surface(parent, PANEL, 28)
	var col = box(panel, true, 10)
	col.alignment = BoxContainer.ALIGN_CENTER
	var mark = CenterContainer.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mark)
	tile_icon(mark, glyph, color, 66)
	title(col, name, 26).align = Label.ALIGN_CENTER
	if not detail.empty():
		var l = wrap(col, detail, 18, DIM)
		l.align = Label.ALIGN_CENTER
	return col

func ago(timestamp) -> String:
	var seconds = OS.get_unix_time() - int(timestamp)
	if seconds < 60:
		return "just now"
	if seconds < 3600:
		return "%d min ago" % (seconds / 60)
	if seconds < 86400:
		return "%d h ago" % (seconds / 3600)
	if seconds < 86400 * 2:
		return "yesterday"
	if seconds < 86400 * 30:
		return "%d days ago" % (seconds / 86400)
	return date_text(timestamp)

func month_year(timestamp) -> String:
	if int(timestamp) <= 0:
		return "-"
	var d = OS.get_datetime_from_unix_time(int(timestamp))
	return "%s %d" % [["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(d.month) - 1], int(d.year)]

func shot(parent, name, height = 160):
	var definitions = load(ModPaths.JOURNEY_DIR + "ui/JourneyPages/00_state.gd")
	var key = definitions.map_key(name)
	var texture = art.texture(key) if File.new().file_exists(ModPaths.JOURNEY_ASSETS_DIR + key + ".png") else null
	var holder = Control.new()
	holder.rect_min_size = Vector2(0, height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	if thumbnail_shader == null:
		thumbnail_shader = Shader.new()
		thumbnail_shader.code = definitions.THUMB_SHADER
	var material = ShaderMaterial.new()
	material.shader = thumbnail_shader
	material.set_shader_param("radius", 18.0)
	material.set_shader_param("shade", 0.6)
	if texture != null:
		material.set_shader_param("shot", texture)
		material.set_shader_param("has_shot", true)
		material.set_shader_param("shot_size", texture.get_size())
	else:
		material.set_shader_param("tint", INSET)
	var picture = ColorRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.material = material
	picture.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	holder.add_child(picture)
	picture.connect("resized", self, "_shot_resize", [picture])
	var overlay = VBoxContainer.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.anchor_top = 1
	overlay.anchor_bottom = 1
	overlay.anchor_right = 1
	overlay.margin_left = 16
	overlay.margin_right = -16
	overlay.margin_bottom = -12
	overlay.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(overlay)
	var label = title(overlay, name, 24)
	label.clip_text = true
	label.add_color_override("font_color_shadow", BASE)
	label.add_constant_override("shadow_offset_y", 2)
	return holder

func _shot_resize(picture):
	picture.material.set_shader_param("box", picture.rect_size)

func field(parent, placeholder, value = "", length = 120):
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = str(value)
	edit.max_length = length
	edit.add_font_override("font", font("text", 20))
	edit.add_color_override("font_color", WHITE)
	edit.add_color_override("font_color_placeholder", DIM)
	edit.add_color_override("cursor_color", HUB_PINK)
	for state in ["normal", "focus"]:
		var look = flat(BASE, 16, 16, 0, BASE, false)
		look.content_margin_top = 10
		look.content_margin_bottom = 10
		if state == "focus":
			look.set_border_width_all(2)
			look.border_color = HUB_PINK
		edit.add_stylebox_override(state, look)
	edit.rect_min_size.y = 46
	grow(edit)
	parent.add_child(edit)
	return edit

# Two-option or more selector built from HubButtons (tabs inside a page).
func choice(parent, options, current, target, method):
	var row = box(parent, false, 6)
	for option in options:
		var b = action(row, option, target, method, option, "selected" if option == current else "tab")
		b.rect_min_size.y = 42
	return row
