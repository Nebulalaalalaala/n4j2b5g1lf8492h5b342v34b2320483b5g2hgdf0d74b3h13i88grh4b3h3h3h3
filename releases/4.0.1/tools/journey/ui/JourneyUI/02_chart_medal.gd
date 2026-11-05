extends "user://mod/tools/journey/ui/JourneyUI/01_icon_league.gd"

# Achievement medallion: tier frame + collection emblem; locked shows a navy
# silhouette with a lock so it stays previewable but clearly unearned.
func medal(parent, tier_index, emblem, size = 140, locked = false):
	var holder = Control.new()
	holder.rect_min_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var frame = image(holder, "medal_" + TIER_ART[clamp(tier_index, 0, 5)], size)
	frame.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var mark = image(holder, "emblem_" + emblem, size * 0.42)
	mark.anchor_left = 0.5
	mark.anchor_right = 0.5
	mark.anchor_top = 0.5
	mark.anchor_bottom = 0.5
	mark.margin_left = -size * 0.21
	mark.margin_right = size * 0.21
	mark.margin_top = -size * 0.18
	mark.margin_bottom = size * 0.24
	if locked:
		frame.modulate = Color(0.34, 0.47, 0.66, 0.9)
		mark.modulate = Color(0.45, 0.58, 0.78, 0.55)
		var lock = icon(holder, "lock", int(size * 0.24), WHITE)
		lock.anchor_left = 0.5
		lock.anchor_right = 0.5
		lock.anchor_top = 1
		lock.anchor_bottom = 1
		lock.margin_left = -size * 0.12
		lock.margin_right = size * 0.12
		lock.margin_top = -size * 0.3
		lock.margin_bottom = -size * 0.06
	if parent != null:
		parent.add_child(holder)
	return holder

func switch(parent, on, target, method, arg = null):
	var w = Switch.new()
	w.on = bool(on)
	w.rect_min_size = Vector2(112, 60)
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w.focus_mode = Control.FOCUS_ALL
	w.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	w.colors = [NAVY_DEEP, GREEN, WHITE, PINK_LIGHT]
	if target != null:
		if arg == null:
			w.connect("toggled", target, method)
		else:
			w.connect("toggled", target, method, [arg])
	if parent != null:
		parent.add_child(w)
	return w

# Segmented control: one navy track, the selected option as a raised white pill.
func segmented(parent, options, current, target, method):
	var track = PanelContainer.new()
	var s = flat(NAVY_DEEP, 34, 6, 0, INK, false)
	track.add_stylebox_override("panel", s)
	track.size_flags_horizontal = 0
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row = box(track, false, 4)
	for option in options:
		var key = option[0] if option is Array else option
		var text = option[1] if option is Array else option
		var active = key == current
		var b = Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_font_override("font", font("display", 28))
		for state in ["normal", "hover", "pressed", "focus"]:
			var bg = WHITE if active else (NAVY_3 if state in ["hover", "focus"] else Color(0, 0, 0, 0))
			var st = flat(bg, 28, 26, 0, INK, false)
			st.content_margin_top = 10
			st.content_margin_bottom = 10
			b.add_stylebox_override(state, st)
		for c in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]:
			b.add_color_override(c, INK if active else WHITE)
		b.connect("pressed", target, method, [key])
		row.add_child(b)
	if parent != null:
		parent.add_child(track)
	return track

func search_field(parent, placeholder, text, target, method):
	var e = LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.caret_blink = true
	e.clear_button_enabled = true
	e.add_font_override("font", font("text", 29))
	e.add_color_override("font_color", WHITE)
	e.add_color_override("font_color_uneditable", MUTED)
	e.add_color_override("cursor_color", PINK_LIGHT)
	e.add_color_override("clear_button_color", MUTED)
	e.add_color_override("selection_color", Color(1, 0.22, 0.59, 0.45))
	var normal = flat(NAVY_DEEP, 30, 28, 0, INK, false)
	normal.content_margin_top = 16
	normal.content_margin_bottom = 16
	var focus = normal.duplicate()
	focus.border_width_left = 4
	focus.border_width_right = 4
	focus.border_width_top = 4
	focus.border_width_bottom = 4
	focus.border_color = PINK_LIGHT
	e.add_stylebox_override("normal", normal)
	e.add_stylebox_override("focus", focus)
	e.add_stylebox_override("read_only", normal)
	e.rect_min_size = Vector2(360, 0)
	e.connect("text_changed", target, method)
	if parent != null:
		parent.add_child(e)
	return e

# Big number + quiet label; value "—" is used for anything not tracked.
func kpi(parent, value, caption, detail = "", accent = WHITE, icon_key = ""):
	var p = well(parent, NAVY_2, 26, 32)
	grow(p)
	var col = box(p, true, 2)
	var top = box(col, false, 10)
	if icon_key != "":
		icon(top, icon_key, 32, accent)
	label(top, caption.to_upper(), "caps", MUTED)
	label(col, str(value), "num_l", accent if str(value) != "—" else FAINT)
	if detail != "":
		label(col, detail, "small", FAINT)
	return p

func chart(parent, values, labels, color = YELLOW, highlight = -1, height = 260, missing = []):
	var c = Chart.new()
	c.values = values
	c.labels = labels
	c.color = color
	c.highlight = highlight
	c.missing = missing
	c.ui = self
	c.rect_min_size = Vector2(200, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grow(c)
	if parent != null:
		parent.add_child(c)
	return c

# Personal-best line: faster times plot higher, so improvement reads upward. The
# range is padded so small improvements still read as a slope.
func pb_chart(parent, times, labels, color = GREEN_LIGHT, height = 300):
	var c = PBChart.new()
	c.times = times
	c.labels = labels
	c.color = color
	c.ui = self
	c.rect_min_size = Vector2(200, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grow(c)
	if parent != null:
		parent.add_child(c)
	return c

# Expanding flash ring for big moments; progress 0..1 grows and fades it.
func ring(parent, color = WHITE):
	var r = FlashRing.new()
	r.color = color
	r.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r
