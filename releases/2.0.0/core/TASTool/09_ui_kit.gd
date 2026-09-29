extends "user://mod/core/TASTool/08_settings.gd"

# Loads one approved icon PNG from user://mod/icons/<icon_name>.png (shipped
# alongside the mod scripts, same as any other mod file -- not a res:// project
# asset, so it has no .import metadata and must be loaded as a raw Image), and
# resizes it to the exact pixel size it will be displayed at using high-quality
# (Lanczos) interpolation. The source art is a fixed 142x142 -- letting each
# TextureRect scale that down at draw time on top of whatever ui_scale
# multiplier is active is what made the first pass look muddy/misproportioned;
# baking in one clean, correctly-sized resample per (icon, size) pair fixes
# that regardless of display size.
# Cached per (icon_name, size) pair -- including a cached "not found" -> null
# -- so repeated calls (e.g. every time the toggle flips) don't re-hit the
# filesystem or re-resample. Returns null -- never an error -- if the icons/
# folder hasn't been installed, so every caller of this must already treat a
# null Texture as "just don't show an icon there."
# The approved icon PNGs are fully opaque 142x142 squares -- the dark
# rounded-tile art is baked into the pixels, not a transparent background
# behind a cut-out glyph. Under the modern black theme that tile reads as a
# mismatched floating chip against the near-black panels, so this keys out
# the tile's own fill color to transparent at load time, leaving just the
# glyph. This never touches the source PNG on disk -- only the in-memory
# copy used to build the runtime texture -- so the approved asset itself is
# never redesigned.
func _strip_icon_background(image: Image) -> void:
	var w: = image.get_width()
	var h: = image.get_height()
	if w < 4 or h < 4:
		return
	image.lock()
	var bg: = Color(0, 0, 0)
	var samples: = [
		image.get_pixel(1, 1), image.get_pixel(w - 2, 1),
		image.get_pixel(1, h - 2), image.get_pixel(w - 2, h - 2),
		image.get_pixel(w / 2, 1), image.get_pixel(1, h / 2),
	]
	for s in samples:
		bg += s
	bg /= samples.size()
	var threshold: = 0.16
	var feather: = 0.1
	for y in range(h):
		for x in range(w):
			var px: = image.get_pixel(x, y)
			var dist: = sqrt(pow(px.r - bg.r, 2) + pow(px.g - bg.g, 2) + pow(px.b - bg.b, 2))
			if dist <= threshold:
				px.a = 0.0
				image.set_pixel(x, y, px)
			elif dist <= threshold + feather:
				px.a = (dist - threshold) / feather
				image.set_pixel(x, y, px)
	image.unlock()


# Applies (or removes) Claude Experimental Mode's icon skin everywhere it's
# wired up. Called once after the overlay is first built and again every time
# the toggle changes. Purely additive/cosmetic -- see the SETTING_CLAUDE_EXPERIMENTAL_ICONS
# comment above.
func _apply_claude_experimental_icons() -> void:
	_set_claude_icon_slot(_claude_menu_title_icon, "goobplayability", 40)
	_set_claude_icon_slot(_claude_log_title_icon, "debug_logs", 36)
	# Deliberately NOT icon-izing the _section_tabs tab strip itself: Godot's
	# built-in TabContainer tab-icon slot is sized off the tab's own (short)
	# height with no control over padding, so these detailed 142x142 icons
	# came out squished and out of proportion there -- exactly what looked
	# "horrible." The two title bars above give the same icons room to
	# actually read correctly instead.
	if _cosmetic_sandbox != null and is_instance_valid(_cosmetic_sandbox) and _cosmetic_sandbox.has_method("set_claude_experimental_icons_enabled"):
		_cosmetic_sandbox.call("set_claude_experimental_icons_enabled", _claude_experimental_icons_enabled)
	if _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("set_claude_experimental_icons_enabled"):
		_macro_editor.call("set_claude_experimental_icons_enabled", _claude_experimental_icons_enabled)
	if _replay_hub != null and is_instance_valid(_replay_hub) and _replay_hub.has_method("set_claude_experimental_icons_enabled"):
		_replay_hub.call("set_claude_experimental_icons_enabled", _claude_experimental_icons_enabled)
	if _game_tools != null and is_instance_valid(_game_tools) and _game_tools.has_method("set_claude_experimental_icons_enabled"):
		_game_tools.call("set_claude_experimental_icons_enabled", _claude_experimental_icons_enabled)
	if _social_hub != null and is_instance_valid(_social_hub) and _social_hub.has_method("set_claude_experimental_icons_enabled"):
		_social_hub.call("set_claude_experimental_icons_enabled", _claude_experimental_icons_enabled)
	for module in [_cosmetic_loadouts, _editor_theme_pack, _match_map_preview, _wins_leaderboard]:
		if module != null and is_instance_valid(module) and module.has_method("set_claude_experimental_icons_enabled"):
			module.call("set_claude_experimental_icons_enabled", _claude_experimental_icons_enabled)


func _mark_tas_timer_labels(pill) -> void:
	# Presentation only. Do not change finish_time, score, PB or label contents.
	for label in [pill.time_label, pill.time_label_frac, pill.time_label_s]:
		if is_instance_valid(label) and not label.has_meta("tas_result_mark"):
			label.set_meta("tas_result_mark", {"scale":label.rect_scale,"pivot":label.rect_pivot_offset,"tooltip":label.hint_tooltip})
			label.rect_pivot_offset = label.rect_size * 0.5
			label.rect_scale *= 0.98
			label.hint_tooltip = "TAS-assisted local result"
			if not label.is_connected("visibility_changed",self,"_reset_hidden_tas_timer"):
				label.connect("visibility_changed",self,"_reset_hidden_tas_timer",[label])


func _reset_hidden_tas_timer(label) -> void:
	if not is_instance_valid(label) or label.is_visible_in_tree() or not label.has_meta("tas_result_mark"):
		return
	var original = label.get_meta("tas_result_mark")
	label.rect_scale = original.scale
	label.rect_pivot_offset = original.pivot
	label.hint_tooltip = original.tooltip
	label.remove_meta("tas_result_mark")


func _show_responsive_popup(title: String, message: String, accept_text := "OK", accept_method := "_close_tool_popup", cancel_text := "", extra_text := "", extra_method := "") -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer):
		_tool_popup_layer.queue_free()
	_tool_popup_layer = CanvasLayer.new()
	_tool_popup_layer.layer = 260
	_tool_popup_layer.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(_tool_popup_layer)
	var root := Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_tool_popup_layer.add_child(root)
	root.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
	root.rect_size = get_gui_viewport_size()
	root.rect_scale = Vector2.ONE * get_gui_scale_factor()
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.72)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(center)
	var viewport_size: Vector2 = get_gui_viewport_size()
	var estimated_lines := message.count("\n") + int(ceil(float(message.length()) / 54.0)) + 2
	var panel := PanelContainer.new()
	var max_popup_width := max(300.0, min(920.0, viewport_size.x - 36.0))
	var max_popup_height := max(240.0, min(720.0, viewport_size.y - 36.0))
	var popup_width := clamp(viewport_size.x * 0.64, min(520.0, max_popup_width), max_popup_width)
	var popup_height := clamp(190.0 + float(estimated_lines) * 31.0, min(300.0, max_popup_height), max_popup_height)
	panel.rect_min_size = Vector2(popup_width, popup_height)
	panel.add_stylebox_override("panel", _make_flat_style(Color(0.015, 0.12, 0.24, 0.98), COLOR_BLUE, 5, 28))
	# _make_flat_style() above already remaps the panel bg/border for
	# Claude Experimental Mode; the title/body text below need their own
	# remap since they're plain color overrides, not routed through it.
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_constant_override("separation", 16)
	margin.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.align = Label.ALIGN_CENTER
	title_label.autowrap = true
	title_label.add_font_override("font", _title_font)
	title_label.add_color_override("font_color", _theme_text(COLOR_WHITE))
	column.add_child(title_label)
	var separator := HSeparator.new()
	column.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.text = message
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_font_override("normal_font", _body_font)
	body.add_color_override("default_color", _theme_text(COLOR_WHITE))
	body.rect_min_size = Vector2(max(420.0, panel.rect_min_size.x - 76.0), max(110.0, float(estimated_lines) * 31.0))
	scroll.add_child(body)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGN_CENTER
	action_row.add_constant_override("separation", 14)
	column.add_child(action_row)
	if not cancel_text.empty():
		var cancel := _make_button(cancel_text, COLOR_BLUE, 220)
		cancel.rect_min_size.y = 58
		cancel.connect("pressed", self, "_close_tool_popup")
		action_row.add_child(cancel)
	if not extra_text.empty():
		var extra := _make_button(extra_text, COLOR_BLUE, 220)
		extra.rect_min_size.y = 58
		extra.connect("pressed", self, extra_method)
		action_row.add_child(extra)
	var okay := _make_button(accept_text, COLOR_PINK, 220)
	okay.rect_min_size.y = 58
	okay.connect("pressed", self, accept_method)
	action_row.add_child(okay)


func _close_tool_popup() -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer):
		_tool_popup_layer.queue_free()
	_tool_popup_layer = null


# Keeps the most-recently-placed checkpoint visually distinct (pink) from
# earlier ones (blue) so it's obvious at a glance which one death will send
# you back to.
func _restyle_practice_markers() -> void:
	for i in _practice_markers.size():
		var m = _practice_markers[i]
		if is_instance_valid(m):
			m.setup(COLOR_PINK if i == _practice_markers.size() - 1 else COLOR_BLUE, str(i), _header_font)


func _set_practice_markers_visible(markers_visible: bool) -> void:
	for marker in _practice_markers:
		if is_instance_valid(marker):
			marker.visible = markers_visible


func _make_resize_handle(which: String) -> Button:
	var handle := _make_small_button("↘", Color(0.08, 0.34, 0.55, 0.78), 48)
	handle.rect_min_size = Vector2(48, 38)
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.hint_tooltip = "Drag to resize this window."
	handle.connect("gui_input", self, "_on_resize_gui_input", [which])
	return handle


func _apply_ui_scale() -> void:
	if is_nan(ui_scale) or is_inf(ui_scale):
		ui_scale = 1.0
	ui_scale = max(ui_scale, UI_SCALE_MIN)
	if _menu_window != null:
		_menu_window.rect_scale = Vector2.ONE * get_gui_scale_factor()
	if _log_window != null:
		_log_window.rect_scale = Vector2.ONE * get_gui_scale_factor()
	if _scale_label != null:
		_scale_label.text = "%d%%" % round(ui_scale * 100)
	if _scale_input != null:
		_scale_input.set_block_signals(true)
		_scale_input.value = ui_scale * 100.0
		_scale_input.set_block_signals(false)
	if _workspace_menu != null and is_instance_valid(_workspace_menu):
		_workspace_menu.call("apply_scale")


# ----------------------------------------------------------------------
#  Shared UI building helpers. Everything is built from real
#  Control/Button nodes, styled after GooberDash's own UI: thick
#  white-bordered, heavily rounded pill buttons over a dark rounded panel,
#  in the game's Baloo font.
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
#  Claude Experimental Mode "modern black" theme remap.
#
#  This does NOT introduce a second set of drawing code paths: it remaps
#  known classic-palette Color values, by value, to their modern equivalents
#  inside the same shared helpers every menu already builds through. When
#  the experimental toggle is off, every function here is a pure passthrough
#  and the classic look is byte-for-byte unchanged. Only background/border/
#  text tones are remapped -- brand accent colors (blue/pink/green/purple
#  button fills) are left alone so the mod's identity stays intact, just on
#  a flat dark surface instead of the classic navy pill.
#
#  Comparisons are RGB-only (never full Color equality) so a caller's own
#  alpha -- e.g. the user's menu_background_opacity slider baked into a
#  panel color -- always survives the remap unchanged.
# ----------------------------------------------------------------------
func _modern_theme_active() -> bool:
	return true


func _color_rgb_eq(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


# Remaps a background/fill/panel color. Must be called BEFORE any
# .lightened()/.darkened() transform is applied at the call site -- once a
# classic const has been transformed it no longer matches by value and
# would silently fall through unremapped.
func _theme_fill(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, COLOR_PANEL_BG) or _color_rgb_eq(color, Color(0.015, 0.12, 0.24)):
		return Color(COLOR_MODERN_BG.r, COLOR_MODERN_BG.g, COLOR_MODERN_BG.b, color.a)
	if _color_rgb_eq(color, COLOR_SLOT_EMPTY):
		return Color(COLOR_MODERN_SLOT_EMPTY.r, COLOR_MODERN_SLOT_EMPTY.g, COLOR_MODERN_SLOT_EMPTY.b, color.a)
	if _color_rgb_eq(color, COLOR_SLOT_FILLED):
		return Color(COLOR_MODERN_SLOT_FILLED.r, COLOR_MODERN_SLOT_FILLED.g, COLOR_MODERN_SLOT_FILLED.b, color.a)
	if _color_rgb_eq(color, COLOR_GRIP):
		return Color(COLOR_MODERN_GRIP.r, COLOR_MODERN_GRIP.g, COLOR_MODERN_GRIP.b, color.a)
	if _color_rgb_eq(color, COLOR_DISABLED):
		return Color(COLOR_MODERN_DISABLED.r, COLOR_MODERN_DISABLED.g, COLOR_MODERN_DISABLED.b, color.a)
	return color


func _theme_border(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, COLOR_WHITE) or _color_rgb_eq(color, COLOR_PANEL_BORDER):
		return Color(COLOR_MODERN_BORDER.r, COLOR_MODERN_BORDER.g, COLOR_MODERN_BORDER.b, color.a)
	return color


func _theme_text(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, COLOR_WHITE):
		return Color(COLOR_MODERN_WHITE.r, COLOR_MODERN_WHITE.g, COLOR_MODERN_WHITE.b, color.a)
	if _color_rgb_eq(color, COLOR_TEXT_DIM):
		return Color(COLOR_MODERN_TEXT_DIM.r, COLOR_MODERN_TEXT_DIM.g, COLOR_MODERN_TEXT_DIM.b, color.a)
	if _color_rgb_eq(color, COLOR_BLUE):
		# _theme_accent() maps COLOR_BLUE to a dark neutral slate meant for
		# BUTTON BACKGROUNDS -- as TEXT (the GOOBPLAYABILITY/ACTION LOG
		# titles) that's nearly unreadable on a near-black panel. Titles
		# read as plain near-white instead, matching the reference design's
		# plain white headings; accent color stays reserved for buttons and
		# the pink/teal "active" signal below.
		return Color(COLOR_MODERN_WHITE.r, COLOR_MODERN_WHITE.g, COLOR_MODERN_WHITE.b, color.a)
	# Any heading/label still colored with a classic brand accent (pink
	# "DEBUG TOOLS", card headers, etc.) gets the same new accent identity
	# as buttons below, instead of silently staying GooberDash blue/pink.
	if _color_rgb_eq(color, COLOR_PINK) or _color_rgb_eq(color, COLOR_PLAY_GREEN):
		return Color(0.616, 0.839, 0.741, color.a)
	return _theme_accent(color)


# Button backgrounds are brand accent colors (blue/pink/green/purple) that
# _theme_fill() deliberately leaves alone so the mod keeps its identity.
# Left at full saturation they still read as bright candy-colored pills next
# to the flat near-black panels, so this applies a uniform darken/mute pass
# on top of whatever _theme_fill() already did (a no-op on colors already
# remapped to the near-black palette -- they're darkened further by a
# negligible, invisible amount).
func _theme_accent(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	# A restrained, professional palette instead of a "confetti" of five
	# equally-loud hues: COLOR_BLUE is used almost everywhere as the default/
	# inactive button color, so it becomes a calm neutral slate -- not another
	# saturated accent. COLOR_PINK is this codebase's actual "active/selected/
	# primary" signal (every toggle turns pink when ON; PINK is also the
	# popup confirm button), so IT gets the one vivid accent color. Red is
	# reserved for genuinely destructive actions (PINK_DARK: Clear, delete),
	# green for play/positive, violet for the Edit Timeline action. Matched
	# by value against the classic consts (see _color_rgb_eq), alpha always
	# preserved.
	if _color_rgb_eq(color, COLOR_BLUE):
		return Color(0.22, 0.23, 0.26, color.a) # neutral slate (default/inactive)
	if _color_rgb_eq(color, COLOR_PINK):
		return Color(0.21, 0.38, 0.31, color.a) # teal (active/primary accent)
	if _color_rgb_eq(color, COLOR_PINK_DARK):
		return Color(0.43, 0.23, 0.23, color.a) # red (destructive)
	if _color_rgb_eq(color, COLOR_PLAY_GREEN):
		return Color(0.22, 0.40, 0.32, color.a) # green (play/positive)
	if _color_rgb_eq(color, COLOR_PURPLE):
		return Color(0.22, 0.28, 0.29, color.a)
	return color


# Lazily loads the modern-theme sans font once and reuses the same
# DynamicFontData across every size (it's a private instance we created
# ourselves, not a shared res:// resource, so there's no risk of one caller's
# settings clobbering another's). Returns null (and caches that miss) if the
# font file isn't installed, so _make_font() can fall back to Baloo cleanly.
func _get_claude_modern_font_data() -> DynamicFontData:
	if _claude_modern_font_load_attempted:
		return _claude_modern_font_data
	_claude_modern_font_load_attempted = true
	if File.new().file_exists(CLAUDE_EXPERIMENTAL_FONT_PATH):
		var data: = DynamicFontData.new()
		data.font_path = CLAUDE_EXPERIMENTAL_FONT_PATH
		data.antialiased = true
		data.override_oversampling = 2.0
		_claude_modern_font_data = data
	return _claude_modern_font_data


func _make_font(size: int) -> DynamicFont:
	var f: = DynamicFont.new()
	var crisp_data: DynamicFontData = null
	if _modern_theme_active():
		crisp_data = _get_claude_modern_font_data()
	if crisp_data == null:
		var data: = load(FONT_PATH)
		if data == null or not (data is DynamicFontData):
			return null
		crisp_data = data.duplicate()
		crisp_data.antialiased = true
		crisp_data.override_oversampling = 2.0
	f.font_data = crisp_data
	f.size = size
	if _modern_theme_active():
		# Flat modern text has no outline -- it's a game-HUD look that
		# clashes with the reference design's plain text.
		f.outline_size = 0
		f.outline_color = Color(0, 0, 0, 0)
	else:
		f.outline_size = 1
		f.outline_color = Color(0, 0.02, 0.05, 0.95)
	f.use_filter = true
	f.use_mipmaps = true
	return f


func _make_flat_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	var s: = StyleBoxFlat.new()
	s.bg_color = _theme_fill(bg)
	s.border_color = _theme_border(border)
	var w: = border_w
	var c: = corner
	if _modern_theme_active():
		# Thinner hairline borders, less aggressively rounded corners --
		# matches the flat card look instead of the classic pill shape.
		w = min(border_w, 1)
		c = min(corner, 8)
	s.border_width_left = w
	s.border_width_top = w
	s.border_width_right = w
	s.border_width_bottom = w
	s.corner_radius_top_left = c
	s.corner_radius_top_right = c
	s.corner_radius_bottom_right = c
	s.corner_radius_bottom_left = c
	s.corner_detail = 12
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_label(text: String, font: DynamicFont, color: Color) -> Label:
	var l: = Label.new()
	l.text = text
	if font != null:
		l.add_font_override("font", font)
	l.add_color_override("font_color", _theme_text(color))
	if _modern_theme_active():
		l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	else:
		l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	l.add_constant_override("shadow_offset_x", 1)
	l.add_constant_override("shadow_offset_y", 1)
	return l


# Applies GooberDash-style pill/rounded button visuals across all states.
func _style_button(btn: Button, bg: Color, corner: int = 18, border_w: int = 4) -> void:
	# Remap bg BEFORE lightened()/darkened() -- a transformed color no
	# longer equals the classic const it came from and would fail the
	# value-based remap in _make_flat_style/_theme_fill.
	var themed_bg: = _theme_accent(_theme_fill(bg))
	var w: = border_w
	if _modern_theme_active():
		# Flat modern buttons read on color/elevation alone, no ring border.
		w = 0
	btn.add_stylebox_override("normal", _make_flat_style(themed_bg, COLOR_WHITE, w, corner))
	btn.add_stylebox_override("hover", _make_flat_style(themed_bg.lightened(0.15), COLOR_WHITE, w, corner))
	btn.add_stylebox_override("pressed", _make_flat_style(themed_bg.darkened(0.2), COLOR_WHITE, w, corner))
	btn.add_stylebox_override("focus", _make_flat_style(themed_bg.lightened(0.15), COLOR_WHITE, w, corner))
	btn.add_stylebox_override("disabled", _make_flat_style(COLOR_DISABLED, Color(1, 1, 1, 0.3), w, corner))
	if _body_font != null:
		btn.add_font_override("font", _body_font)
	btn.add_color_override("font_color", _theme_text(COLOR_WHITE))
	btn.add_color_override("font_color_hover", _theme_text(COLOR_WHITE))
	btn.add_color_override("font_color_pressed", _theme_text(COLOR_WHITE))
	btn.add_color_override("font_color_disabled", _theme_text(Color(1, 1, 1, 0.5)))


func _make_button(text: String, bg: Color, min_w: int = 0) -> Button:
	var btn: = Button.new()
	btn.text = text
	_style_button(btn, bg)
	btn.rect_min_size = Vector2(min_w, BUTTON_H)
	# No keyboard focus -- otherwise a clicked button stays focused and the
	# game's own Space/Enter-bound actions (e.g. dash on Space) would
	# re-trigger it via Godot's default ui_accept-activates-focused-control
	# behavior instead of reaching the game.
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _make_small_button(text: String, bg: Color, min_w: int = 0) -> Button:
	var btn: = Button.new()
	btn.text = text
	_style_button(btn, bg, 12, 3)
	if _small_font != null:
		btn.add_font_override("font", _small_font)
	btn.rect_min_size = Vector2(min_w, 40)
	btn.focus_mode = Control.FOCUS_NONE
	return btn


# Claude Experimental Mode content grouping. In classic mode this is a
# complete no-op -- it returns `parent` unchanged, so every existing
# .add_child() call downstream keeps landing exactly where it always has and
# the classic layout is pixel-identical. In modern mode it opens a bordered
# card (with an accent-bar header) as a new child of `parent` and returns
# the card's own inner container, so reassigning a page variable to this
# call's result (e.g. `playback_page = _open_card(playback_root, "...")`)
# redirects every subsequent add_child() in that section into the card
# without touching a single line of the section's actual control-building
# code. This is the only mechanism used to visually group the "Tools" and
# "Macro Bot" pages into sections -- see _build_menu_window().
func _open_card(parent: VBoxContainer, title: String) -> VBoxContainer:
	if not _modern_theme_active():
		return parent
	var card: = PanelContainer.new()
	card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, COLOR_PANEL_BORDER, 1, 10))
	parent.add_child(card)
	var inner: = VBoxContainer.new()
	inner.add_constant_override("separation", 10)
	card.add_child(inner)
	if not title.empty():
		var header: = HBoxContainer.new()
		header.add_constant_override("separation", 8)
		var accent: = ColorRect.new()
		accent.color = _theme_accent(COLOR_PINK) # the teal "active/primary" accent, not the neutral default
		accent.rect_min_size = Vector2(3, 14)
		header.add_child(accent)
		header.add_child(_make_label(title.to_upper(), _small_font, COLOR_PINK))
		inner.add_child(header)
	return inner


# A small draggable grip bar. Connect its gui_input to move `which` window.
func _make_drag_handle(which: String) -> PanelContainer:
	var grip: = PanelContainer.new()
	grip.add_stylebox_override("panel", _make_flat_style(COLOR_GRIP, COLOR_WHITE, 3, 999))
	grip.rect_min_size = GRIP_SIZE
	var label: = _make_label("⠿", _header_font, COLOR_TEXT_DIM)
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip.add_child(label)
	grip.connect("gui_input", self, "_on_drag_gui_input", [which])
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	return grip
