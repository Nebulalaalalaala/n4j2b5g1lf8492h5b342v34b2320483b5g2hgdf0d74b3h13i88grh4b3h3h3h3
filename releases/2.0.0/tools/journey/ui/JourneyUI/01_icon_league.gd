extends "user://mod/tools/journey/ui/JourneyUI/00_state.gd"

func league(rank) -> Dictionary:
	return LEAGUES.get(str(rank.get("art", "bronze")), LEAGUES.bronze)

# ------------------------------------------------------------------ type
# "display" = Baloo 2 ExtraBold (titles, numbers, buttons); "text" = Inter
# SemiBold (supporting copy). Falls back to Baloo if Inter is missing.
func font(kind, size, outline = 0):
	var key = "%s%d_%d" % [kind, size, outline]
	if _fonts.has(key):
		return _fonts[key]
	var f = DynamicFont.new()
	f.font_data = _inter_data if kind == "text" and _inter_data != null else _baloo_data
	f.size = size
	f.use_filter = true
	f.use_mipmaps = true
	if outline > 0:
		f.outline_size = outline
		f.outline_color = INK
	if kind == "caps":
		f.extra_spacing_char = 2
	if kind == "display" or kind == "caps" or kind == "title":
		f.extra_spacing_top = -int(size * 0.18)
		f.extra_spacing_bottom = -int(size * 0.12)
	_fonts[key] = f
	return f

func label(parent, text, role = "body", color = WHITE, align = Label.ALIGN_LEFT):
	var l = Label.new()
	l.text = text
	var spec = ROLES[role]
	l.add_font_override("font", font(spec[0], spec[1], spec[2]))
	l.add_color_override("font_color", color)
	l.align = align
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if role == "title":
		l.add_color_override("font_color_shadow", INK)
		l.add_constant_override("shadow_offset_x", 0)
		l.add_constant_override("shadow_offset_y", 7)
	# Wrap only where the label gets real width (a VBox gives it the column);
	# an autowrapped label in an HBox collapses to one character wide.
	if role in ["body", "small"] and parent is VBoxContainer:
		l.autowrap = true
	if parent != null:
		parent.add_child(l)
	return l

# ------------------------------------------------------------------ layout
func box(parent, vertical = true, gap = 20):
	var b = VBoxContainer.new() if vertical else HBoxContainer.new()
	b.add_constant_override("separation", gap)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(b)
	return b

func grow(control, horizontal = true, vertical = false, ratio = 1.0):
	if horizontal:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_stretch_ratio = ratio
		# A label that fills a row wraps instead of forcing the row wider.
		if control is Label and not control.clip_text:
			control.autowrap = true
	if vertical:
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return control

func spacer(parent, width = 0, height = 0):
	var s = Control.new()
	s.rect_min_size = Vector2(width, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width == 0 and height == 0:
		grow(s)
	parent.add_child(s)
	return s

# ------------------------------------------------------------------ surfaces
func flat(color, radius = 40, pad = 32, depth = 0, depth_color = NAVY_DEEP, shadow = true):
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.anti_aliasing = true
	s.anti_aliasing_size = 1.0
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	if depth > 0:
		s.border_width_bottom = depth
		s.border_color = depth_color
		s.expand_margin_bottom = depth
	if shadow:
		s.shadow_color = Color(0, 0.08, 0.2, 0.32)
		s.shadow_size = 18
		s.shadow_offset = Vector2(0, 12)
	return s

# Primary surface: native navy panel with the "deep" bottom edge the game uses
# on its buttons, a soft shadow, and generous rounding.
func card(parent, color = NAVY, pad = 34, radius = 44):
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", flat(color, radius, pad, 8, color.darkened(0.45)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(p)
	return p

# Inset surface used for rows inside a card: no shadow, no border.
func well(parent, color = NAVY_2, pad = 22, radius = 28):
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", flat(color, radius, pad, 0, NAVY_DEEP, false))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(p)
	return p

# Card heading: optional glyph, title, optional trailing text.
func heading(parent, text, icon_key = "", trailing = "", trailing_color = MUTED):
	var row = box(parent, false, 16)
	if icon_key != "":
		icon(row, icon_key, 44, MUTED)
	label(row, text, "h2")
	if trailing != "":
		spacer(row)
		label(row, trailing, "small", trailing_color, Label.ALIGN_RIGHT)
	return row

# ------------------------------------------------------------------ buttons
# kinds: primary (native yellow PLAY), secondary (native white deep button),
# quiet (raised navy), accent (pink).
func button(parent, text, kind, target, method, arg = null, icon_key = ""):
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_font_override("font", font("display", 32 if kind != "small" else 27))
	var looks = {
		"primary": [YELLOW, ORANGE, Color("ffd84d"), INK, INK],
		"secondary": [WHITE, SKY_LIGHT, PINK, INK, WHITE],
		"quiet": [NAVY_2, NAVY_DEEP, NAVY_3, WHITE, WHITE],
		"small": [NAVY_2, NAVY_DEEP, NAVY_3, WHITE, WHITE],
		"accent": [PINK, Color("c21f6f"), PINK_LIGHT, WHITE, WHITE],
	}
	var look = looks.get(kind, looks.quiet)
	var pad = 18 if kind == "small" else 30
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var bg = look[2] if state in ["hover", "focus"] else look[0]
		if state == "disabled":
			bg = NAVY_2.darkened(0.2)
		var edge = PINK_LIGHT if kind == "secondary" and state in ["hover", "focus"] else look[1]
		var s = flat(bg, 26 if kind == "small" else 32, pad, 0 if state == "pressed" else 8, edge, false)
		s.content_margin_top = 12 if kind == "small" else 16
		s.content_margin_bottom = 12 if kind == "small" else 16
		if state == "pressed":
			s.expand_margin_top = -4
		b.add_stylebox_override(state, s)
	b.add_color_override("font_color", look[3])
	b.add_color_override("font_color_hover", look[4])
	b.add_color_override("font_color_focus", look[4])
	b.add_color_override("font_color_pressed", look[4])
	b.add_color_override("font_color_disabled", FAINT)
	if icon_key != "":
		b.icon = art.texture("icon_" + icon_key)
		b.expand_icon = true
		b.add_constant_override("hseparation", 14)
		b.add_color_override("icon_color_normal", look[3])
		b.add_color_override("icon_color_hover", look[4])
		b.add_color_override("icon_color_pressed", look[4])
		b.add_color_override("icon_color_focus", look[4])
		b.add_color_override("icon_color_disabled", FAINT)
	if icon_key != "":
		var content_h = 40 if kind != "small" else 34
		var width = pad * 2 + content_h
		if text != "":
			width += font("display", 32 if kind != "small" else 27).get_string_size(text).x + 14
		b.rect_min_size.x = max(b.rect_min_size.x, width)
	if target != null and method != "":
		if arg == null:
			b.connect("pressed", target, method)
		else:
			b.connect("pressed", target, method, [arg])
	if parent != null:
		parent.add_child(b)
	return b

# Whole-surface click target for cards and rows, with hover/focus feedback
# and keyboard/controller activation.
func clickable(panel, target, method, arg = null, hover_color = NAVY_3):
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.focus_mode = Control.FOCUS_ALL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal = panel.get_stylebox("panel")
	var lit = normal.duplicate()
	lit.bg_color = hover_color
	var ring = lit.duplicate()
	ring.border_width_left = 5
	ring.border_width_right = 5
	ring.border_width_top = 5
	ring.border_width_bottom = max(5, ring.border_width_bottom)
	ring.border_color = PINK_LIGHT
	panel.set_meta("journey_styles", [normal, lit, ring])
	panel.connect("mouse_entered", self, "_hover", [panel, 1])
	panel.connect("mouse_exited", self, "_hover", [panel, 0])
	panel.connect("focus_entered", self, "_hover", [panel, 2])
	panel.connect("focus_exited", self, "_hover", [panel, 0])
	panel.connect("gui_input", self, "_click", [panel, target, method, arg])
	return panel

func _hover(panel, state):
	if is_instance_valid(panel) and panel.has_meta("journey_styles"):
		if state == 0 and panel.has_focus():
			state = 2
		panel.add_stylebox_override("panel", panel.get_meta("journey_styles")[state])

func _click(event, panel, target, method, arg):
	var hit = event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed
	if not hit and event.is_action_pressed("ui_accept"):
		hit = true
	if hit and is_instance_valid(target):
		panel.accept_event()
		if arg == null:
			target.call_deferred(method)
		else:
			target.call_deferred(method, arg)

# ------------------------------------------------------------------ motion
# Fade + slight grow into place. Uses modulate/scale only, so containers keep
# ownership of position and size. No-op with reduced motion.
func pop_in(tween, control, delay = 0.0, duration = 0.32, from_scale = 0.94):
	if reduced_motion or tween == null or not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	control.rect_scale = Vector2(from_scale, from_scale)
	if not control.is_connected("resized", self, "_center_pivot"):
		control.connect("resized", self, "_center_pivot", [control])
	_center_pivot(control)
	tween.interpolate_property(control, "modulate:a", 0.0, 1.0, duration * 0.8, Tween.TRANS_QUAD, Tween.EASE_OUT, delay)
	tween.interpolate_property(control, "rect_scale", Vector2(from_scale, from_scale), Vector2.ONE, duration, Tween.TRANS_BACK, Tween.EASE_OUT, delay)

func _center_pivot(control):
	if is_instance_valid(control):
		control.rect_pivot_offset = control.rect_size * 0.5

func burst(parent):
	if reduced_motion or parent == null:
		return null
	var b = Burst.new()
	b.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	parent.add_child(b)
	return b

# ------------------------------------------------------------------ pieces
func icon(parent, key, size = 40, color = WHITE):
	var t = TextureRect.new()
	t.texture = art.texture("icon_" + key)
	t.expand = true
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.rect_min_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if parent != null:
		parent.add_child(t)
	return t

func image(parent, key, size, modulate = WHITE):
	var t = TextureRect.new()
	t.texture = art.texture(key)
	t.expand = true
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.rect_min_size = size if size is Vector2 else Vector2(size, size)
	t.modulate = modulate
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(t)
	return t

# Icon in a tinted rounded tile -- used for categories, quick links, quests.
func tile_icon(parent, key, color, size = 84):
	var p = PanelContainer.new()
	var s = flat(color.darkened(0.55), int(size * 0.34), 0, 0, NAVY_DEEP, false)
	s.bg_color = Color(color.r, color.g, color.b, 0.2)
	p.add_stylebox_override("panel", s)
	p.rect_min_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c = CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(c)
	icon(c, key, int(size * 0.52), color)
	if parent != null:
		parent.add_child(p)
	return p

func pill(parent, text, fg = WHITE, bg = NAVY_3, icon_key = ""):
	var p = PanelContainer.new()
	var s = flat(bg, 24, 14, 0, NAVY_DEEP, false)
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	p.add_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = 0
	var row = box(p, false, 8)
	if icon_key != "":
		icon(row, icon_key, 26, fg)
	var l = label(row, text, "caps", fg)
	l.add_font_override("font", font("caps", 24))
	if parent != null:
		parent.add_child(p)
	return p

func xp_text(amount) -> String:
	return "+" + thousands(amount) + " XP"

func thousands(value) -> String:
	var n = str(int(abs(value)))
	var out = ""
	while n.length() > 3:
		out = "," + n.substr(n.length() - 3, 3) + out
		n = n.substr(0, n.length() - 3)
	return ("-" if value < 0 else "") + n + out

func duration(seconds) -> String:
	seconds = int(seconds)
	if seconds < 60:
		return "%ds" % seconds
	var h = seconds / 3600
	var m = (seconds % 3600) / 60
	return ("%dh %02dm" % [h, m]) if h > 0 else ("%d min" % m)

func date_text(timestamp, with_time = false) -> String:
	if timestamp == null or int(timestamp) <= 0:
		return "Date unavailable"
	var d = OS.get_datetime_from_unix_time(int(timestamp) + _utc_offset())
	var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var text = "%d %s %d" % [d.day, months[d.month - 1], d.year]
	if with_time:
		text += " · %02d:%02d" % [d.hour, d.minute]
	return text

func _utc_offset() -> int:
	return int(OS.get_time_zone_info().get("bias", 0)) * 60

# ------------------------------------------------------------------ drawn
func bar(parent, ratio, fill = YELLOW, height = 26, track = Color(0, 0.05, 0.14, 0.45), ticks = 0):
	var b = Bar.new()
	b.ratio = clamp(float(ratio), 0.0, 1.0)
	b.fill = fill
	b.track = track
	b.ticks = ticks
	b.rect_min_size = Vector2(80, height)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grow(b)
	if parent != null:
		parent.add_child(b)
	return b

func ring_progress(parent, ratio, size = 96, color = YELLOW, width = 12):
	var r = Ring.new()
	r.ratio = clamp(float(ratio), 0.0, 1.0)
	r.color = color
	r.width = width
	r.rect_min_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if parent != null:
		parent.add_child(r)
	return r

# Rank badge: league art plus the division numeral (or King League number)
# drawn on the shared ribbon, and 1-3 division pips beneath it.
func badge(parent, rank, size = 160, glow = false, rays = false):
	var holder = Control.new()
	holder.rect_min_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if rays:
		var r = Glow.new()
		r.texture = art.texture("fx_rays")
		r.color = league(rank).light
		r.color.a = 0.22
		r.scale_factor = 1.7
		r.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
	if glow:
		var g = Glow.new()
		g.texture = art.texture("fx_glow")
		g.color = league(rank).light
		g.color.a = 0.55
		g.scale_factor = 1.25
		g.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(g)
	var b = Badge.new()
	b.texture = art.texture(str(rank.get("art", "bronze")))
	b.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var king = str(rank.get("league", "")) == "King League"
	b.text = str(rank.get("division", ""))
	b.text_color = INK if king else WHITE
	b.pips = 0 if king else int(rank.get("id", 0)) % 3 + 1
	b.pip_color = league(rank).base if not king else YELLOW
	b.ui = self
	b.ribbon = RIBBON
	holder.add_child(b)
	if parent != null:
		parent.add_child(holder)
	return holder
