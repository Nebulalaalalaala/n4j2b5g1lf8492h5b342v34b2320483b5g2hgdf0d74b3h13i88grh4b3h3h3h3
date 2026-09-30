extends "user://mod/core/TASTool/06_windows_1.gd"

func _build_menu_window() -> void:
	_menu_window = VBoxContainer.new()
	_menu_window.add_constant_override("separation", 10)
	# Pure layout wrapper -- must never itself catch clicks aimed at the
	# game/menu underneath. Only actual controls (the tab button, drag
	# grip, scale buttons, and the panel background while it's open)
	# should intercept anything.
	_menu_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_menu_window)

	# --- the drop-down tab, with its own drag grip and a UI Scale control
	# (applies to both windows -- reachable without opening the panel) ---
	_tab_row = HBoxContainer.new()
	_tab_row.add_constant_override("separation", 6)
	_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_row.add_child(_make_drag_handle("menu"))

	_tab_button = Button.new()
	_tab_button.text = _tab_text()
	_style_button(_tab_button, COLOR_PANEL_BG, 999, 4)
	if _header_font != null:
		_tab_button.add_font_override("font", _header_font)
	_tab_button.rect_min_size = TAB_SIZE
	_tab_button.align = Button.ALIGN_CENTER
	_tab_button.focus_mode = Control.FOCUS_NONE # see _make_button -- keeps Space free for the game
	_tab_button.connect("pressed", self, "_on_tab_pressed")
	_tab_row.add_child(_tab_button)

	var scale_minus: = _make_small_button("−", COLOR_BLUE, 40)
	scale_minus.connect("pressed", self, "_on_ui_scale_delta_pressed", [-UI_SCALE_STEP])
	_tab_row.add_child(scale_minus)
	_scale_label = _make_label("%d%%" % round(ui_scale * 100), _small_font, COLOR_WHITE)
	_scale_label.rect_min_size = Vector2(56, 0)
	_scale_label.align = Label.ALIGN_CENTER
	_scale_label.valign = Label.VALIGN_CENTER
	_scale_label.visible = true
	_tab_row.add_child(_scale_label)
	_scale_input = SpinBox.new()
	# Percentage is shown by the label; +/- never acquire keyboard focus.
	_scale_input.visible = false
	_scale_input.focus_mode = Control.FOCUS_NONE
	_scale_input.get_line_edit().focus_mode = Control.FOCUS_NONE
	_scale_input.get_line_edit().editable = false
	_scale_input.min_value = UI_SCALE_MIN * 100
	_scale_input.max_value = 1000
	_scale_input.allow_greater = true
	_scale_input.step = 5
	_scale_input.value = ui_scale * 100
	_scale_input.suffix = "%"
	_scale_input.rect_min_size = Vector2(110, 38)
	_scale_input.hint_tooltip = "Menu scale. No upper cap. Ctrl+0 resets the main windows."
	_scale_input.get_line_edit().add_font_override("font", _small_font)
	_scale_input.connect("value_changed", self, "_on_ui_scale_percent_changed")
	_tab_row.add_child(_scale_input)
	var scale_plus: = _make_small_button("+", COLOR_BLUE, 40)
	scale_plus.connect("pressed", self, "_on_ui_scale_delta_pressed", [UI_SCALE_STEP])
	_tab_row.add_child(scale_plus)
	var scale_fit := _make_small_button("Fit", COLOR_BLUE, 52)
	scale_fit.connect("pressed", self, "_on_main_ui_fit")
	_tab_row.add_child(scale_fit)
	var scale_reset := _make_small_button("Reset", COLOR_BLUE, 66)
	scale_reset.hint_tooltip = "Restore 100% scale and default main-menu/log size and position (Ctrl+0)."
	scale_reset.connect("pressed", self, "_on_main_ui_scale_reset")
	_tab_row.add_child(scale_reset)

	# Performance readout is part of Debug Mode and stays completely hidden
	# during ordinary use.
	_diag_label = _make_label("", _small_font, COLOR_TEXT_DIM)
	_diag_label.visible = _debug_mode_enabled
	_tab_row.add_child(_diag_label)

	_menu_window.add_child(_tab_row)

	# --- transient status toast ---
	# THE TWENTY-NINTH-PASS FIX (2026-08-31, user report: "the GUI keeps
	# moving up and down... sometimes I accidentally click the wrong
	# button"): this pill sits directly inside _menu_window, a
	# VBoxContainer, right above _menu_panel (which holds every section
	# page -- including the Place Checkpoint/Undo/Clear row). Toggling a
	# direct child of a BoxContainer's own `.visible` doesn't just hide it
	# in place -- Godot's BoxContainer skips invisible children entirely
	# when it re-sorts, so the toast popping in and out of existence
	# (every ~2.5s, driven by _status_message_timer, and Macro Bot Mode
	# fires a fresh status message on nearly every action -- checkpoint
	# placed, died, respawned, ...) yanked _menu_panel and everything in it
	# up and down by the toast's own height each time. That's exactly what
	# was landing clicks on the wrong button while placing checkpoints
	# rapidly. Fixed by never touching `.visible` again -- the toast now
	# stays permanently present in the layout (a constant-height slot,
	# same as any other row) and shows/hides purely via `modulate.a`, which
	# affects only how it DRAWS, not how BoxContainer sizes/sorts around
	# it. Everything below it now stays put regardless of how often status
	# messages fire.
	_toast_pill = PanelContainer.new()
	_toast_pill.add_stylebox_override("panel", _make_flat_style(COLOR_PINK_DARK, COLOR_WHITE, 3, 999))
	var toast_label: = _make_label(" ", _body_font, COLOR_WHITE) # single space, not "" -- keeps the reserved slot's height identical to a real one-line message even before anything's ever been shown
	# Fixed width + clipped, no autowrap: a long status message (plenty of
	# them run a full sentence or more) would otherwise stretch this pill --
	# and therefore the whole window's width -- out to fit it, which is the
	# same "things keep shifting under my cursor" problem this whole pass is
	# about, just sideways instead of vertically. Clipping trades showing
	# the tail of a very long message for a window that never moves.
	toast_label.rect_min_size.x = TAB_SIZE.x - 40
	toast_label.clip_text = true
	_toast_pill.add_child(toast_label)
	_toast_pill.set_meta("label", toast_label)
	_toast_pill.modulate.a = 0.0
	_menu_window.add_child(_toast_pill)

	# --- the drop-down panel itself -- background alpha is configurable
	# (menu_background_opacity) so the game stays visible through it ---
	var panel_bg: = _theme_fill(Color(COLOR_PANEL_BG.r, COLOR_PANEL_BG.g, COLOR_PANEL_BG.b, menu_background_opacity))

	_menu_panel = PanelContainer.new()
	_menu_panel.add_stylebox_override("panel", _make_flat_style(panel_bg, COLOR_PANEL_BORDER, 3, 26))
	_menu_panel.rect_min_size = Vector2(MENU_PANEL_MIN_W, 0)
	_menu_window.add_child(_menu_panel)

	var vb: = VBoxContainer.new()
	vb.add_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_panel.add_child(vb)

	var title_row: = HBoxContainer.new()
	title_row.add_constant_override("separation", 12)
	# Claude Experimental Mode icon slot -- hidden (rect_min_size stays 0,0
	# via TextureRect's own default) unless _apply_claude_experimental_icons()
	# turns it on, so this changes nothing about the title's normal appearance.
	# Sized to match the base game's own icon-next-to-heading convention (see
	# the 44x44 icon in the old "CLIENT TOOLS"
	# heading) rather than the cramped ~24-28px this started at.
	_claude_menu_title_icon = TextureRect.new()
	_claude_menu_title_icon.expand = true
	_claude_menu_title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_claude_menu_title_icon.rect_min_size = Vector2(40, 40)
	_claude_menu_title_icon.visible = false
	title_row.add_child(_claude_menu_title_icon)
	var title_label: = _make_label("GOOBPLAYABILITY", _title_font, COLOR_BLUE)
	title_label.valign = Label.VALIGN_CENTER
	title_row.add_child(title_label)
	vb.add_child(title_row)

	_inactive_label = _make_label("Goobplayability is unavailable in live multiplayer matches.", _body_font, COLOR_TEXT_DIM)
	_inactive_label.visible = false
	_inactive_label.autowrap = true
	_inactive_label.rect_min_size = Vector2(MENU_PANEL_MIN_W - 60, 0)
	vb.add_child(_inactive_label)

	# Each heading below is now its own tab/page instead of one long
	# scrolling wall of every section stacked on top of each other -- and
	# each page is individually height-capped and independently scrollable
	# (see _add_tab_page), so a tall one (Macro Bot) can never push the tab
	# strip itself off-screen or make the window taller than the viewport.
	_section_tabs = TabContainer.new()
	_section_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	_section_tabs.add_stylebox_override("panel", _make_flat_style(panel_bg, COLOR_PANEL_BORDER, 2, 16))
	_section_tabs.add_stylebox_override("tab_fg", _make_flat_style(COLOR_PINK, COLOR_WHITE, 2, 12))
	_section_tabs.add_stylebox_override("tab_bg", _make_flat_style(COLOR_BLUE.darkened(0.35), Color(1, 1, 1, 0.3), 2, 12))
	if _body_font != null:
		_section_tabs.add_font_override("font", _body_font)
	_section_tabs.add_color_override("font_color_fg", _theme_text(COLOR_WHITE))
	_section_tabs.add_color_override("font_color_bg", _theme_text(COLOR_TEXT_DIM))
	vb.add_child(_section_tabs)

	# Claude Experimental Mode: replace the native pill tab strip with a flat
	# nav-link row (populated once every _add_tab_page() call below has run,
	# then moved above _section_tabs in vb's child order). Classic mode never
	# creates or shows this -- _section_tabs.tabs_visible stays at its default
	# and looks exactly as before.
	_claude_menu_nav_row = HBoxContainer.new()
	_claude_menu_nav_row.add_constant_override("separation", 6)
	_claude_menu_nav_row.visible = _modern_theme_active()
	if _modern_theme_active():
		_section_tabs.tabs_visible = false
	vb.add_child(_claude_menu_nav_row)
	vb.move_child(_claude_menu_nav_row, _section_tabs.get_index())

	# TOOLS -- speed/frame-step/buffered-input controls (formerly their own
	# "Playback" tab) plus Perfect Jumpzone (formerly its own "Jumpzone" tab),
	# consolidated per the user's 2026-08-30 request: Macro Bot Mode is now
	# the only macro/checkpoint system this file has, so everything that
	# isn't specifically part of IT lives here instead of its own tab.
	var playback_page: = _add_tab_page(_section_tabs, "Tools")
	_build_tools_page(playback_page)

	# PRACTICE CHECKPOINTS
	var practice_page: = _add_tab_page(_section_tabs, "Macro Bot")
	_build_macro_bot_page(practice_page)

	# AUTOPLAY -- kept as its own top-level page so learning controls and live
	# attempt results do not crowd the manual Macro Bot recording workflow.
	var autoplay_page: = _add_tab_page(_section_tabs, "Autoplay")
	if _autoplay_bot != null and is_instance_valid(_autoplay_bot) and _autoplay_bot.has_method("build_tab"):
		_autoplay_bot.call("build_tab", autoplay_page)
	else:
		autoplay_page.add_child(_make_label("Autoplay failed to load. Check the Goobplayability log for a script error.", _body_font, COLOR_PINK))

	# Populate the flat nav row built earlier, now that all _add_tab_page()
	# calls above have run and _section_tabs actually has its final tabs.
	_claude_menu_nav_buttons = []
	for i in range(_section_tabs.get_tab_count()):
		var is_active: = (i == _section_tabs.current_tab)
		var nav_btn: = _make_small_button(_section_tabs.get_tab_title(i).to_upper(), COLOR_PINK if is_active else COLOR_BLUE, 130)
		nav_btn.toggle_mode = true
		nav_btn.pressed = is_active
		nav_btn.connect("pressed", self, "_on_claude_menu_nav_pressed", [i])
		_claude_menu_nav_buttons.append(nav_btn)
		_claude_menu_nav_row.add_child(nav_btn)

	var resize_row := HBoxContainer.new()
	var resize_spacer := Control.new()
	resize_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resize_row.add_child(resize_spacer)
	resize_row.add_child(_make_resize_handle("menu"))
	vb.add_child(resize_row)
	var workspace_script = load(ModPaths.WORKSPACE_MENU)
	if workspace_script != null and workspace_script.can_instance():
		if _workspace_menu != null and is_instance_valid(_workspace_menu):
			_workspace_menu.queue_free()
		_workspace_menu = workspace_script.new()
		add_child(_workspace_menu)
		_workspace_menu.call("build", self, vb, _section_tabs, resize_row)
