extends Node

const ModPaths = preload("user://mod/core/ModPaths.gd")
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const Notices = preload("user://mod/core/workspace4/Notices.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")

# Workspace menu (F1), Goobplayability 4.0 look: galaxy theme (dark or light),
# grouped navigation, and the Arctic Fox peeking over the Workspace banner.
# Presentation only: existing pages, signals and module controllers stay
# intact. New 4.0 pages live in core/workspace4/. The previous look lives in
# WorkspaceMenuClassic.gd (Settings > Appearance > Classic menu look).
# MINT is the accent colour (kept as a name so module code keeps working).
var BG = Galaxy.color("bg")
var SURFACE = Galaxy.color("surface")
var RAISED = Galaxy.color("raised")
var BORDER = Galaxy.color("border")
var INK = Galaxy.color("ink")
var MUTED = Galaxy.color("muted")
var MINT = Galaxy.color("accent")
var SELECTED = Galaxy.color("hover")
const ACCENTS = [["Violet", "a68bff"], ["Ocean", "6fb8ff"], ["Mint", "7fe0b4"], ["Rose", "ff8ec6"], ["Amber", "ffc46b"]]
const GROUP_COLORS = {"": "7fe0b4", "PLAY": "7fe0b4", "REPLAYS": "6fb8ff", "CREATE": "ff8ec6", "COMMUNITY": "ffc46b", "GENERAL": "a9b8c2", "EXPERIMENTAL": "ff9d66", "DEVELOPER": "b49cff"}
# [label, route key, 4.0 icon name, group]. Match maps and Top rated sit under
# Game tools (CHILD_KEYS). Hidden modules (Speedrun Lab, Friends & party) keep
# their routes; their handlers decide visibility.
const ITEMS = [
	["Workspace", "home", "home", ""],
	["Tools", "tab:0", "tools", ""],
	["Game tools", "game", "gamepad", ""],
	["Maps", "maps", "map", ""],
	["Macro Bot", "tab:1", "macro", ""],
	["Speedrun Lab", "speedrun-lab", "target", ""],
	["Replay library", "replays", "replay", "REPLAYS"],
	["Level Council", "council", "council", "REPLAYS"],
	["Avatar Studio", "sandbox", "avatar", "CREATE"],
	["Level themes", "themes", "paint", "CREATE"],
	["Overlay Studio", "overlay", "overlay", "CREATE"],
	["Effects Editor", "effects", "effects", "CREATE"],
	["Clip Studio", "clips", "clip", "CREATE"],
	["Wins", "wins", "trophy", "COMMUNITY"],
	["Workshop", "workshop", "workshop", "COMMUNITY"],
	["News", "news", "news", "COMMUNITY"],
	["Accounts", "accounts", "user", "GENERAL"],
	["Notifications", "notifications", "bell", "GENERAL"],
	["Settings", "settings", "settings", "GENERAL"],
	["Autoplay", "tab:2", "flask", "EXPERIMENTAL"],
	["Developer tools", "developer", "bug", "DEVELOPER"],
]
const CHILD_KEYS = ["maps"]
const PAGE_SEARCH = {"maps":"match maps top rated levels discover rotation", "themes":"editor themes match themes level appearance palettes", "developer":"diagnostics debug reports logs"}
# [title, subtitle, key, icon, planet colour]
const TILES = [
	["Macro Bot", "Record · edit · replay", "tab:1", "macro", "violet"],
	["Game tools", "FPS boost · ping · emotes", "game", "gamepad", "cyan"],
	["Replay library", "Your recordings", "replays", "replay", "blue"],
	["Avatar Studio", "Outfits · effects · colours", "sandbox", "avatar", "pink"],
	["Match maps", "This match's rounds", "maps", "map", "mint"],
	["Level Council", "Public match recordings", "council", "council", "gold"],
]
const QUICK = [["Performance", "performance"], ["Infinite dash", "dash"], ["Emote wheel", "emotes"]]
const SETTING_NOTES = {
	"_macro_load_opens_level": "Off: load into Macro Bot only",
	"_sandbox_gui_enabled": "Outfits, effects and colours",
	"_replay_hub_gui_enabled": "Recordings and Level Council",
	"_game_tools_gui_enabled": "FPS boost, ping, emotes, accounts",
	"_social_hub_gui_enabled": "Friends list and parties",
	"_cosmetic_loadouts_gui_enabled": "Saved outfits",
	"_editor_theme_pack_enabled": "Extra themes in the level editor picker",
	"_match_map_preview_enabled": "Map preview before a round",
	"_wins_leaderboard_enabled": "Wins history",
	"_leaderboard_search_enabled": "Player search on leaderboards",
	"_custom_lobby_code_enabled": "Choose your own lobby code",
	"_debug_mode_enabled": "Diagnostics and logs",
	"_update_checks_enabled": "Check for new versions at start",
}
var main_handler = load(ModPaths.path("MainHandler.gd")).new()
var tas_tool
var tabs: TabContainer
var heading: Label
var heading_chip: PanelContainer
var heading_chip_label: Label
var nav = {}
var nav_groups = []
var nav_colors = {}
var pages = {}
var fonts = {}
var icons = {}
var active = "home"
var notice: Label
var _wins_period = "all_time"
var _wins_rows: VBoxContainer
var _wins_summary: Label
var _wins_signature = ""
var _wins_view = null
var _setting_checks = []
var _developer_sections = []
var shell
var search_query = ""
var links = []
var _fps_label: Label
var _stat_labels = {}
var _recent_row: HBoxContainer
var _quick_buttons = {}
var _accent_buttons = []
var _glass_slider: HSlider
var nav_icons = {}
var hero = null
var bell: Button
var overlay_layer = null
var effect_runtime = null
var v4_pages = {}
var _v4_pending = {}

func _init():
	# First 4.0 start: move everyone onto the galaxy accent once.
	if not bool(SavedSettings.get_value("workspace_v4", false)):
		SavedSettings.set_value("workspace_v4", true)
		SavedSettings.set_value("workspace_accent", "a68bff")
	var accent = str(SavedSettings.get_value("workspace_accent", "a68bff"))
	if Galaxy.is_light() and accent == "a68bff":
		accent = "6240ca"
	if accent.length() == 6 and accent.is_valid_hex_number(false):
		MINT = Color(accent)
		SELECTED = Color(MINT.r, MINT.g, MINT.b, 0.16)

func tint(group: String) -> Color:
	return Color(GROUP_COLORS.get(group, "7fe0b4"))

func box(fill: Color, line: Color = BORDER, padding: int = 16) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = line
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.corner_detail = 10
	s.anti_aliasing = true
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

# A card edge in the group's colour on the left only.
func edge_box(fill: Color, edge: Color, padding: int = 14) -> StyleBoxFlat:
	var s = box(fill, edge, padding)
	s.set_border_width_all(0)
	s.border_width_left = 3
	return s

func font(size: int) -> DynamicFont:
	if not fonts.has(size):
		fonts[size] = tas_tool.call("_make_font", size)
	return fonts[size]

func label(text: String, size: int = 17, color: Color = INK) -> Label:
	var result = Label.new()
	result.text = text
	result.add_font_override("font", font(size))
	result.add_color_override("font_color", color)
	result.add_color_override("font_color_shadow", Color.transparent)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

# Atlas glyphs are cream lines on a dark tile; the tile is keyed out and the
# lines take the given colour.
func icon(index, color = null) -> Texture:
	var pixels = int(round(24 * _text_k))
	if typeof(index) == TYPE_STRING:
		return Galaxy.icon(index, color if color != null else MUTED, pixels)
	var key = str(index) + ("" if color == null else color.to_html(false)) + "@" + str(pixels)
	if icons.has(key):
		return icons[key]
	var image = Image.new()
	var path = ModPaths.WORKSPACE_ATLAS
	if image.load(path) != OK:
		return null
	var size = Vector2(image.get_width(), image.get_height())
	var origin = Vector2(0.085 + (index % 4) * 0.21, 0.085 + int(index / 4) * 0.21)
	var tile = image.get_rect(Rect2((origin + Vector2(0.012, 0.012)) * size, size * 0.186))
	tile.convert(Image.FORMAT_RGBA8)
	tile.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
	var ink = color if color != null else Color("dfe6e1")
	tile.lock()
	for y in range(pixels):
		for x in range(pixels):
			var pixel = tile.get_pixel(x, y)
			var light = (pixel.r + pixel.g + pixel.b) / 3.0
			tile.set_pixel(x, y, Color(ink.r, ink.g, ink.b, clamp((light - 0.16) / 0.55, 0.0, 1.0)))
	tile.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(tile, Texture.FLAG_FILTER)
	icons[key] = texture
	return texture

# Goobplayability's mark (the pink bean tile).
func _bean() -> Texture:
	var image = Image.new()
	if image.load(ModPaths.ICONS_DIR + "goob_bean.png") != OK:
		return icon(15)
	image.resize(72, 72, Image.INTERPOLATE_LANCZOS)
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER)
	return texture

func button(text: String, key: String, glyph: int = -1) -> Button:
	var result = Button.new()
	result.text = text
	result.rect_min_size = Vector2(0, 36)
	result.align = Button.ALIGN_LEFT
	result.focus_mode = Control.FOCUS_NONE
	result.add_font_override("font", font(16))
	result.add_color_override("font_color", INK)
	result.add_color_override("font_color_hover", INK)
	result.add_color_override("font_color_pressed", MINT)
	result.add_constant_override("hseparation", 10)
	result.add_stylebox_override("normal", box(SURFACE, BORDER, 12))
	result.add_stylebox_override("hover", box(RAISED, MINT.darkened(0.35), 12))
	result.add_stylebox_override("pressed", box(SELECTED, MINT, 12))
	result.add_stylebox_override("focus", StyleBoxEmpty.new())
	if glyph >= 0:
		result.icon = icon(glyph)
	for state in ["normal", "hover", "pressed"]:
		var style = result.get_stylebox(state).duplicate()
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		result.add_stylebox_override(state, style)
	result.connect("pressed", self, "select", [key])
	links.append([result, key])
	return result

func page(key: String, title: String) -> VBoxContainer:
	var content: VBoxContainer = tas_tool.call("_add_tab_page", tabs, title)
	content.add_constant_override("separation", 12)
	pages[key] = content.get_parent().get_index()
	return content

func card(parent: VBoxContainer, title: String, accent = null) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", box(SURFACE, BORDER, 18))
	parent.add_child(panel)
	var inner = VBoxContainer.new()
	inner.add_constant_override("separation", 10)
	panel.add_child(inner)
	if not title.empty():
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar = ColorRect.new()
		bar.color = accent if accent is Color else MINT
		bar.rect_min_size = Vector2(4, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		row.add_child(label(title, 18))
		inner.add_child(row)
	return inner

func chip(text: String, color: Color) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = box(Color(color.r, color.g, color.b, 0.16), Color(color.r, color.g, color.b, 0.45), 10)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.set_corner_radius_all(12)
	panel.add_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var text_label = label(text, 13, color.lightened(0.15))
	panel.add_child(text_label)
	return panel

func _spacer() -> Control:
	var space = Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return space

func _slim_scrollbar(bar: ScrollBar) -> void:
	bar.add_stylebox_override("scroll", StyleBoxEmpty.new())
	bar.add_stylebox_override("scroll_focus", StyleBoxEmpty.new())
	for entry in [["grabber", BORDER], ["grabber_highlight", MUTED.darkened(0.3)], ["grabber_pressed", MINT.darkened(0.3)]]:
		var style = box(entry[1], entry[1], 2)
		style.content_margin_left = 3
		style.content_margin_right = 3
		bar.add_stylebox_override(entry[0], style)

func _glass_alpha() -> float:
	return clamp(float(SavedSettings.get_value("workspace_glass", 0.97)), 0.7, 1.0)

func _panel_style() -> StyleBoxFlat:
	var style = box(Color(BG.r, BG.g, BG.b, _glass_alpha()), BORDER, 20)
	style.set_corner_radius_all(18)
	style.border_color = Color(MINT.r, MINT.g, MINT.b, 0.35)
	style.shadow_color = Color(0.2, 0.1, 0.45, 0.55)
	style.shadow_size = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _rainbow() -> TextureRect:
	var gradient = Gradient.new()
	gradient.offsets = PoolRealArray([0.0, 0.33, 0.66, 1.0])
	gradient.colors = PoolColorArray([MINT, Color("7fd8ff"), Color("ff8ec6"), Color("ffd86b")])
	var texture = GradientTexture.new()
	texture.gradient = gradient
	texture.width = 256
	var strip = TextureRect.new()
	strip.name = "WorkspaceAccentStrip"
	strip.texture = texture
	strip.expand = true
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.rect_min_size = Vector2(0, 3)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.modulate.a = 0.85
	return strip

func build(owner_tool, root: VBoxContainer, section_tabs: TabContainer, resize_row: Control) -> void:
	tas_tool = owner_tool
	tabs = section_tabs
	# Discard presentation chrome only. Page contents are never reconstructed.
	for child in root.get_children():
		if child != tabs and child != resize_row and child != tas_tool.get("_inactive_label"):
			child.hide()
	root.add_constant_override("separation", 12)
	var header = HBoxContainer.new()
	header.name = "WorkspaceDragHeader"
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.hint_tooltip = "Drag to move the menu"
	header.connect("gui_input", tas_tool, "_on_drag_gui_input", ["menu"])
	header.add_constant_override("separation", 12)
	var mark_frame = PanelContainer.new()
	var mark_style = box(Color("8c72f0"), Color("ffd86b"), 2)
	mark_style.set_corner_radius_all(19)
	mark_style.content_margin_top = 2
	mark_style.content_margin_bottom = 2
	mark_style.shadow_color = Color(0.65, 0.55, 1.0, 0.35)
	mark_style.shadow_size = 6
	mark_frame.add_stylebox_override("panel", mark_style)
	mark_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark = TextureRect.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.texture = Galaxy.texture("fox-head.png")
	if mark.texture == null:
		mark.texture = _bean()
	mark.expand = true
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.rect_min_size = Vector2(32, 32)
	mark_frame.add_child(mark)
	header.add_child(mark_frame)
	var titles = HBoxContainer.new()
	titles.add_constant_override("separation", 8)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(label("Goobplayability", 22))
	var version_chip = chip("4.0", Galaxy.color("star"))
	version_chip.hint_tooltip = "Version " + str(tas_tool.call("_get_goobplayability_version"))
	version_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	titles.add_child(version_chip)
	header.add_child(titles)
	header.add_child(_spacer())
	var search = LineEdit.new()
	search.name = "WorkspaceSearch"
	search.placeholder_text = "Search tools"
	search.rect_min_size = Vector2(240, 38)
	search.clear_button_enabled = true
	search.add_font_override("font", font(15))
	search.add_stylebox_override("normal", box(SURFACE, BORDER, 14))
	search.add_stylebox_override("focus", box(SURFACE, MINT, 14))
	search.add_color_override("font_color", INK)
	search.add_color_override("font_color_uneditable", MUTED)
	search.connect("text_changed", self, "_filter")
	search.connect("text_entered", self, "_search_entered")
	header.add_child(search)
	var fps_chip = chip("— FPS", Color("6fb8ff"))
	fps_chip.hint_tooltip = "Frames per second"
	fps_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	_fps_label = fps_chip.get_child(0)
	header.add_child(fps_chip)
	bell = Button.new()
	bell.focus_mode = Control.FOCUS_NONE
	bell.hint_tooltip = "Notifications"
	bell.rect_min_size = Vector2(38, 38)
	bell.add_font_override("font", font(14))
	bell.add_color_override("font_color", Galaxy.color("star"))
	bell.add_stylebox_override("normal", box(SURFACE, BORDER, 8))
	bell.add_stylebox_override("hover", box(RAISED, MINT, 8))
	bell.add_stylebox_override("pressed", box(RAISED, MINT, 8))
	bell.add_stylebox_override("focus", StyleBoxEmpty.new())
	bell.icon = icon("bell", INK)
	bell.connect("pressed", self, "select", ["notifications"])
	header.add_child(bell)
	var theme_button = Button.new()
	theme_button.focus_mode = Control.FOCUS_NONE
	theme_button.hint_tooltip = "Dark / light theme (applies after restart)"
	theme_button.rect_min_size = Vector2(38, 38)
	theme_button.icon = icon("moon" if not Galaxy.is_light() else "sun", INK)
	theme_button.add_stylebox_override("normal", box(SURFACE, BORDER, 8))
	theme_button.add_stylebox_override("hover", box(RAISED, MINT, 8))
	theme_button.add_stylebox_override("pressed", box(RAISED, MINT, 8))
	theme_button.add_stylebox_override("focus", StyleBoxEmpty.new())
	theme_button.connect("pressed", self, "_set_theme", ["dark" if Galaxy.is_light() else "light"])
	header.add_child(theme_button)
	var close = button("×", "close")
	close.align = Button.ALIGN_CENTER
	close.rect_min_size = Vector2(38, 38)
	close.hint_tooltip = "Close menu (F1)"
	close.add_stylebox_override("normal", box(SURFACE, BORDER, 8))
	close.add_stylebox_override("hover", box(Color("3a2328"), Color("ff7f8a"), 8))
	header.add_child(close)
	root.add_child(header)
	root.move_child(header, 0)
	var strip = _rainbow()
	root.add_child(strip)
	root.move_child(strip, 1)
	var body = HBoxContainer.new()
	body.add_constant_override("separation", 18)
	root.add_child(body)
	root.move_child(body, resize_row.get_index())
	var sidebar_panel = PanelContainer.new()
	var sidebar_style = box(Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.55), Color(BORDER.r, BORDER.g, BORDER.b, 0.6), 8)
	sidebar_style.content_margin_top = 8
	sidebar_style.content_margin_bottom = 8
	sidebar_panel.add_stylebox_override("panel", sidebar_style)
	sidebar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sidebar_panel)
	var sidebar_scroll = ScrollContainer.new()
	sidebar_scroll.rect_min_size = Vector2(212, 0)
	sidebar_scroll.scroll_horizontal_enabled = false
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_panel.add_child(sidebar_scroll)
	_slim_scrollbar(sidebar_scroll.get_v_scrollbar())
	var sidebar = VBoxContainer.new()
	sidebar.add_constant_override("separation", 2)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(sidebar)
	var last_group = ""
	for item in ITEMS:
		if item[3] != last_group:
			last_group = item[3]
			var group = HBoxContainer.new()
			group.add_constant_override("separation", 7)
			group.rect_min_size.y = 28
			group.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.rect_min_size.y = 30 if not item[3].empty() else 4
			var group_label = label(item[3], 12, Galaxy.color("dim"))
			group_label.size_flags_vertical = Control.SIZE_SHRINK_END
			group.add_child(group_label)
			sidebar.add_child(group)
			nav_groups.append(group)
		var link = button(item[0], item[1], -1)
		link.icon = icon(item[2], MUTED)
		nav_icons[item[1]] = item[2]
		sidebar.add_child(link)
		nav[item[1]] = link
		nav_colors[item[1]] = MINT
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_constant_override("separation", 12)
	body.add_child(content)
	var heading_row = HBoxContainer.new()
	heading_row.add_constant_override("separation", 12)
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading = label("Workspace", 28)
	heading_row.add_child(heading)
	heading_chip = chip("PLAY", MINT)
	heading_chip_label = heading_chip.get_child(0)
	heading_row.add_child(heading_chip)
	content.add_child(heading_row)
	notice = label("", 15, Color("ffc46b"))
	notice.autowrap = true
	notice.visible = false
	content.add_child(notice)
	root.remove_child(tabs)
	content.add_child(tabs)
	tabs.tabs_visible = false
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_stylebox_override("panel", StyleBoxEmpty.new())
	for i in range(tabs.get_tab_count()):
		pages["tab:%d" % i] = i
	_build_home()
	_build_settings()
	var developer = page("developer", "Developer tools")
	var tools_content = tabs.get_child(pages["tab:0"]).get_child(0)
	for child in tools_content.get_children():
		if child.has_meta("workspace_developer"):
			_developer_sections.append(child)
	var developer_script = ModPaths.try_load(ModPaths.CORE_DIR+"workspace4/pages/DeveloperPage.gd")
	if developer_script != null and developer_script.can_instance():
		var builder = developer_script.new()
		builder.build(self,developer)
		v4_pages["developer"] = builder
	_sync_developer()
	_build_wins()
	_build_v4_pages()
	shell = load(get_script().resource_path.get_base_dir().plus_file("ModulePages.gd")).new()
	add_child(shell)
	shell.build(self)
	tabs.connect("tab_changed", self, "_tab_changed")
	for child in tabs.get_children():
		if child is ScrollContainer:
			_slim_scrollbar(child.get_v_scrollbar())
	tas_tool.get("_menu_panel").add_stylebox_override("panel", _panel_style())
	# Friends & party is dropped: switch its module off if it was still on.
	if bool(tas_tool.get("_social_hub_gui_enabled")) and tas_tool.has_method("_on_settings_social_hub_gui_toggled"):
		tas_tool.call("_on_settings_social_hub_gui_toggled", false)
	select("home")
	call_deferred("_skin_modules")
	if not get_viewport().is_connected("size_changed", self, "apply_scale"):
		get_viewport().connect("size_changed", self, "apply_scale")
	var refresh = Timer.new()
	refresh.wait_time = 1.0
	refresh.connect("timeout", self, "_refresh_wins")
	refresh.connect("timeout", self, "_refresh_visibility")
	refresh.connect("timeout", self, "_refresh_status")
	add_child(refresh)
	refresh.start()

# ------------------------------------------------------------------ home

func _build_home() -> void:
	var home = page("home", "Workspace")
	hero = load(ModPaths.CORE_DIR + "workspace4/FoxHero.gd").new()
	home.add_child(hero)
	hero.build(self)
	home.add_child(label("QUICK LAUNCH", 13, Galaxy.color("dim")))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_constant_override("hseparation", 12)
	grid.add_constant_override("vseparation", 12)
	home.add_child(grid)
	for entry in TILES:
		grid.add_child(_tile(entry[0], entry[1], entry[2], entry[3], entry[4]))
	var lower = HBoxContainer.new()
	lower.add_constant_override("separation", 12)
	home.add_child(lower)
	var quick_panel = PanelContainer.new()
	quick_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(quick_panel)
	quick_panel.add_stylebox_override("panel", box(SURFACE, BORDER, 16))
	var quick = VBoxContainer.new()
	quick.add_constant_override("separation", 8)
	quick_panel.add_child(quick)
	quick.add_child(label("QUICK TOGGLES", 14, MUTED))
	var quick_grid = GridContainer.new()
	quick_grid.columns = 2
	quick_grid.add_constant_override("hseparation", 8)
	quick_grid.add_constant_override("vseparation", 8)
	quick.add_child(quick_grid)
	for entry in QUICK:
		var toggle = Button.new()
		toggle.text = entry[0]
		toggle.align = Button.ALIGN_LEFT
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.rect_min_size = Vector2(170, 36)
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.add_font_override("font", font(15))
		toggle.add_constant_override("hseparation", 8)
		toggle.connect("pressed", self, "_quick_pressed", [entry[1]])
		quick_grid.add_child(toggle)
		_quick_buttons[entry[1]] = toggle
	var quick_empty = label("Turn on Game tools in Settings to use these.", 14, MUTED)
	quick_empty.name = "QuickEmpty"
	quick.add_child(quick_empty)
	var recent_panel = PanelContainer.new()
	recent_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(recent_panel)
	recent_panel.add_stylebox_override("panel", box(SURFACE, BORDER, 16))
	var recent = VBoxContainer.new()
	recent.add_constant_override("separation", 8)
	recent_panel.add_child(recent)
	recent.add_child(label("RECENT", 14, MUTED))
	_recent_row = HBoxContainer.new()
	_recent_row.add_constant_override("separation", 8)
	recent.add_child(_recent_row)
	var shortcuts = HBoxContainer.new()
	shortcuts.add_constant_override("separation", 8)
	home.add_child(shortcuts)
	for entry in [["Input & overlays", "tab:0", "keyboard"], ["Timeline editor", "timeline", "timeline"], ["Settings", "settings", "settings"]]:
		var shortcut = button(entry[0], entry[1], -1)
		shortcut.icon = icon(entry[2], MUTED.lightened(0.2))
		_icon_users.append([shortcut, entry[2], MUTED.lightened(0.2)])
		shortcut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shortcuts.add_child(shortcut)
	_rebuild_recent()
	_sync_quick()

# Quick launch card: the tool's icon on a glossy planet.
func _tile(title: String, subtitle: String, key: String, glyph: String, planet: String) -> Button:
	var tile = Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.rect_min_size = Vector2(220, 68)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.hint_tooltip = subtitle
	tile.add_stylebox_override("normal", box(SURFACE, BORDER, 14))
	var hover = box(RAISED, Color(MINT.r, MINT.g, MINT.b, 0.55), 14)
	hover.shadow_color = Color(MINT.r, MINT.g, MINT.b, 0.16)
	hover.shadow_size = 8
	tile.add_stylebox_override("hover", hover)
	tile.add_stylebox_override("pressed", box(SELECTED, MINT, 14))
	tile.add_stylebox_override("focus", StyleBoxEmpty.new())
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_right = 1
	row.anchor_bottom = 1
	row.margin_left = 12
	row.margin_right = -10
	tile.add_child(row)
	var orb = TextureRect.new()
	orb.texture = Galaxy.texture("orb-%s.png" % planet)
	orb.expand = true
	orb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	orb.rect_min_size = Vector2(44, 44)
	orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture = TextureRect.new()
	picture.texture = icon(glyph, Color(1, 1, 1))
	picture.expand = true
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.anchor_right = 1
	picture.anchor_bottom = 1
	picture.margin_left = 12
	picture.margin_top = 12
	picture.margin_right = -12
	picture.margin_bottom = -12
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.add_child(picture)
	_icon_users.append([picture, glyph, Color(1, 1, 1)])
	row.add_child(orb)
	var words = VBoxContainer.new()
	words.add_constant_override("separation", 1)
	words.alignment = BoxContainer.ALIGN_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(label(title, 17))
	var small = label(subtitle, 14, MUTED)
	small.clip_text = true
	words.add_child(small)
	row.add_child(words)
	tile.connect("pressed", self, "select", [key])
	tile.connect("mouse_entered", self, "_tile_hover", [tile, true])
	tile.connect("mouse_exited", self, "_tile_hover", [tile, false])
	links.append([tile, key])
	return tile

func _rebuild_recent() -> void:
	if _recent_row == null:
		return
	for child in _recent_row.get_children():
		_recent_row.remove_child(child)
		child.queue_free()
	var recent = SavedSettings.get_value("workspace_recent", [])
	var shown = 0
	if typeof(recent) == TYPE_ARRAY:
		for key in recent:
			if not nav.has(str(key)) or not enabled(str(key)):
				continue
			var link = button(nav[key].text, str(key), -1)
			link.icon = nav[key].icon
			link.add_stylebox_override("normal", edge_box(SURFACE.lightened(0.03), nav_colors.get(key, MINT), 10))
			_recent_row.add_child(link)
			shown += 1
			if shown >= 2:
				break
	if shown == 0:
		_recent_row.add_child(label("Tools you open show up here.", 14, MUTED))

func _remember(key: String) -> void:
	if key in ["home", "settings", "close"] or not nav.has(key):
		return
	var recent = SavedSettings.get_value("workspace_recent", [])
	if typeof(recent) != TYPE_ARRAY:
		recent = []
	recent = recent.duplicate()
	recent.erase(key)
	recent.push_front(key)
	if recent.size() > 6:
		recent.resize(6)
	SavedSettings.set_value("workspace_recent", recent)

func _game_tools():
	var module = tas_tool.get("_game_tools")
	return module if module != null and is_instance_valid(module) and module.has_method("_tool_card_pressed") else null

func _quick_state(key: String):
	var module = _game_tools()
	if module == null:
		return null
	match key:
		"performance":
			return module.performance_enabled() if module.has_method("performance_enabled") else null
		"dash":
			return bool(module.get("_infinite_dash_enabled"))
		"emotes":
			return module._emote_wheel.binding != 0 if module.get("_emote_wheel") != null else null
	return null

func _quick_pressed(key: String) -> void:
	var module = _game_tools()
	if module != null:
		module._tool_card_pressed(key)
	_sync_quick()

func _sync_quick() -> void:
	var any = false
	for key in _quick_buttons:
		any = any or _quick_state(key) != null
	if not _quick_buttons.empty():
		var empty = _quick_buttons.values()[0].get_parent().get_parent().get_node_or_null("QuickEmpty")
		if empty != null:
			empty.visible = not any
	for key in _quick_buttons:
		var toggle = _quick_buttons[key]
		var state = _quick_state(key)
		toggle.visible = state != null
		if state == null:
			continue
		var on = bool(state)
		toggle.icon = _toggle_icon(on)
		toggle.add_color_override("font_color", MINT if on else INK)
		toggle.add_color_override("font_color_hover", MINT if on else INK)
		toggle.add_stylebox_override("normal", box(SELECTED if on else BG, MINT.darkened(0.3) if on else BORDER, 10))
		toggle.add_stylebox_override("hover", box(SELECTED.lightened(0.05) if on else RAISED, MINT, 10))
		toggle.add_stylebox_override("pressed", box(SELECTED, MINT, 10))
		toggle.add_stylebox_override("focus", StyleBoxEmpty.new())

func _refresh_status() -> void:
	if _fps_label == null or not is_instance_valid(_fps_label):
		return
	var menu_window = tas_tool.get("_menu_window")
	if menu_window != null and not menu_window.is_visible_in_tree():
		return
	var fps = int(Engine.get_frames_per_second())
	_fps_label.text = "%d FPS" % fps
	if active != "home":
		return
	if hero != null:
		hero.set_chip("fps", "%d FPS" % fps)
	var place = "Menus"
	var game = tas_tool.call("_find_game") if tas_tool.has_method("_find_game") else null
	var scene = get_tree().current_scene
	if game != null:
		place = "In a race"
	elif scene != null:
		var scene_name = str(scene.name)
		if "Editor" in scene_name:
			place = "Level editor"
		elif scene_name == "HomeScene":
			place = "Home"
		elif scene_name == "ConnectingScene":
			place = "Connecting"
	if hero != null:
		hero.set_chip("game", place)
	var on = 0
	var total = 0
	for entry in _setting_checks:
		if entry[1] in ["_debug_mode_enabled", "_update_checks_enabled", "_macro_load_opens_level"]:
			continue
		total += 1
		if bool(tas_tool.get(entry[1])):
			on += 1
	if hero != null:
		hero.set_chip("tools", "%d tools on" % on)
	_sync_bell()
	_sync_quick()

# -------------------------------------------------------------- settings

func _build_settings() -> void:
	var settings_root = page("settings", "Settings")
	# 4.0: settings split into tabs instead of one long page.
	var settings_tabs = PageTabs.new()
	settings_root.add_child(settings_tabs)
	settings_tabs.setup("settings", font(15))
	var general_tab = settings_tabs.add_tab("General", "settings")
	var tools_tab = settings_tabs.add_tab("Tools", "tools")
	var keys_tab = settings_tabs.add_tab("Shortcuts", "keyboard")
	var backup_tab = settings_tabs.add_tab("Modes & backup", "save")
	var settings = general_tab
	var categories = {}
	var grids = {}
	for entry in [["General", "GENERAL", general_tab], ["Gameplay / Tools", "PLAY", tools_tab], ["Experimental", "EXPERIMENTAL", tools_tab], ["Developer", "DEVELOPER", tools_tab]]:
		categories[entry[0]] = card(entry[2], entry[0], tint(entry[1]))
	categories["Experimental"].add_child(label("Features still being tested.", 14, MUTED))
	categories["Experimental"].add_child(button("Autoplay", "tab:2", 4))
	for entry in [["Load opens level", "_macro_load_opens_level", "_on_settings_macro_load_opens_level_toggled"], ["Avatar Studio", "_sandbox_gui_enabled", "_on_settings_sandbox_gui_toggled"], ["Replay library", "_replay_hub_gui_enabled", "_on_settings_replay_hub_gui_toggled"], ["Game tools", "_game_tools_gui_enabled", "_on_settings_game_tools_gui_toggled"], ["Looks", "_cosmetic_loadouts_gui_enabled", "_on_settings_cosmetic_loadouts_toggled"], ["Editor themes", "_editor_theme_pack_enabled", "_on_settings_editor_theme_pack_toggled"], ["Match maps", "_match_map_preview_enabled", "_on_settings_match_map_preview_toggled"], ["Wins leaderboard", "_wins_leaderboard_enabled", "_on_settings_wins_leaderboard_toggled"], ["Leaderboard search", "_leaderboard_search_enabled", "_on_settings_leaderboard_search_toggled"], ["Custom lobby code", "_custom_lobby_code_enabled", "_on_settings_custom_lobby_code_toggled"], ["Debug tools", "_debug_mode_enabled", "_on_settings_debug_mode_toggled"], ["Update checks", "_update_checks_enabled", "_on_settings_update_checks_toggled"]]:
		if not main_handler.setting_available(entry[1]):
			continue
		var check = CheckButton.new()
		check.hint_tooltip = SETTING_NOTES.get(entry[1], "")
		check.pressed = bool(tas_tool.get(entry[1]))
		check.focus_mode = Control.FOCUS_NONE
		check.add_icon_override("on", _toggle_icon(true))
		check.add_icon_override("off", _toggle_icon(false))
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			check.add_stylebox_override(state, StyleBoxEmpty.new())
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		check.connect("toggled", self, "_setting_changed", [entry[2]])
		_setting_checks.append([check, entry[1]])
		var category = "Gameplay / Tools"
		if entry[1] == "_debug_mode_enabled":
			category = "Developer"
		elif entry[1] == "_social_hub_gui_enabled":
			category = "Experimental"
		elif entry[1] in ["_update_checks_enabled", "_sandbox_gui_enabled", "_cosmetic_loadouts_gui_enabled"]:
			category = "General"
		if not grids.has(category):
			grids[category] = GridContainer.new()
			grids[category].columns = 2
			grids[category].add_constant_override("hseparation", 10)
			grids[category].add_constant_override("vseparation", 10)
			categories[category].add_child(grids[category])
		var tile = PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_stylebox_override("panel", box(BG, BORDER, 14))
		grids[category].add_child(tile)
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		tile.add_child(row)
		var words = VBoxContainer.new()
		words.add_constant_override("separation", 1)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(words)
		words.add_child(label(entry[0], 16))
		words.add_child(label(SETTING_NOTES.get(entry[1], ""), 14, MUTED))
		row.add_child(check)
	categories["Developer"].add_child(button("Action log", "logs", 12))
	_build_appearance(general_tab)
	_build_modes(backup_tab)
	var system = card(general_tab, "Interface & updates", Color("6fb8ff"))
	var shortcuts = card(keys_tab, "Keyboard shortcuts", Color("ffc46b"))
	var shortcut_view = load(ModPaths.path("ToolKeybindSettings.gd")).new()
	shortcuts.add_child(shortcut_view)
	shortcut_view.build(tas_tool._keybinds, self)
	var system_row = GridContainer.new()
	system_row.columns = 2
	system_row.add_constant_override("hseparation", 10)
	system_row.add_constant_override("vseparation", 10)
	system.add_child(system_row)
	for entry in [["Reset window layout", "reset-layout", 0], ["Replay introduction", "intro", 0], ["Check for updates", "updates", 11], ["Install update", "install-update", 11], ["Roll back last update", "rollback", 12]]:
		var action = button(entry[0], entry[1], entry[2])
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		system_row.add_child(action)
	system.add_child(label("Version " + str(tas_tool.call("_get_goobplayability_version")), 14, MUTED))
	var status = label("", 14, MUTED)
	status.autowrap = true
	system.add_child(status)
	tas_tool.set("_updater_status_label", status)
	settings_tabs.finish()
	_build_performance(settings_root)

# Bottom of Settings: find what costs frames, or unload Goobplayability for
# this session (not an uninstall; restarting the game loads it again).
var _perf_status = null
var _unload_button = null
var _unload_armed = false

func _build_performance(parent: VBoxContainer) -> void:
	var perf = card(parent, "Performance", Galaxy.color("danger"))
	var row = Kit.row(perf, 8)
	Kit.action(self, row, "Find what's slowing the game", "signal", self, "_run_perf_probe")
	_unload_button = Kit.action(self, row, "Unload Goobplayability", "close", self, "_unload_pressed")
	_unload_button.add_color_override("font_color", Galaxy.color("danger"))
	_perf_status = label("Unload turns every Goobplayability tool off until you restart the game. Nothing is uninstalled.", 14, MUTED)
	_perf_status.autowrap = true
	perf.add_child(_perf_status)

func _run_perf_probe() -> void:
	if tas_tool.get("_practice_active") == true or tas_tool.get("_practice_playback") == true:
		_perf_status.text = "Stop Macro Bot recording or playback first."
		return
	if has_node("GoobPerfProbe"):
		return
	tas_tool.call("_set_menu_open", false)
	var probe = load(ModPaths.CORE_DIR + "workspace4/PerfProbe.gd").new()
	probe.name = "GoobPerfProbe"
	probe.tas_tool = tas_tool
	probe.connect("finished", self, "_perf_probe_finished")
	add_child(probe)

func _perf_probe_finished(lines: Array) -> void:
	_perf_status.text = PoolStringArray(lines).join("\n")
	tas_tool.call("_set_menu_open", true)
	select("settings")

func _unload_pressed() -> void:
	if not _unload_armed:
		_unload_armed = true
		_unload_button.text = "Click again to unload"
		get_tree().create_timer(4.0).connect("timeout", self, "_disarm_unload")
		return
	load(ModPaths.CORE_DIR + "workspace4/Unloader.gd").unload(get_tree(), tas_tool)

func _disarm_unload() -> void:
	if _unload_armed and is_instance_valid(_unload_button):
		_unload_armed = false
		_unload_button.text = "Unload Goobplayability"

var _mode_status = null

# Racing / TAS / Building presets and settings export / import.
func _build_modes(settings: VBoxContainer) -> void:
	var presets = load(ModPaths.CORE_DIR + "ModePresets.gd")
	if presets == null:
		return
	var modes = card(settings, "Modes & backup", Color("7fe0b4"))
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	modes.add_child(row)
	for key in ["racing", "tas", "building"]:
		var spec = presets.MODES[key]
		var mode_button = Button.new()
		mode_button.text = spec.name
		mode_button.hint_tooltip = spec.note
		mode_button.focus_mode = Control.FOCUS_NONE
		mode_button.rect_min_size = Vector2(120, 38)
		mode_button.add_font_override("font", font(15))
		mode_button.add_stylebox_override("normal", box(BG, BORDER, 12))
		mode_button.add_stylebox_override("hover", box(RAISED, MINT, 12))
		mode_button.add_stylebox_override("pressed", box(SELECTED, MINT, 12))
		mode_button.add_stylebox_override("focus", StyleBoxEmpty.new())
		mode_button.connect("pressed", self, "_apply_mode", [key])
		row.add_child(mode_button)
	var backup = HBoxContainer.new()
	backup.add_constant_override("separation", 8)
	modes.add_child(backup)
	for entry in [["Export settings", "_export_settings"], ["Import settings", "_import_settings"]]:
		var action = Button.new()
		action.text = entry[0]
		action.focus_mode = Control.FOCUS_NONE
		action.rect_min_size = Vector2(150, 34)
		action.add_font_override("font", font(14))
		action.add_stylebox_override("normal", box(BG, BORDER, 12))
		action.add_stylebox_override("hover", box(RAISED, MINT, 12))
		action.add_stylebox_override("focus", StyleBoxEmpty.new())
		action.connect("pressed", self, entry[1])
		backup.add_child(action)
	_mode_status = label("Export saves your Goobplayability settings (no account data) to Documents/" + presets.EXPORT_NAME + ".", 14, MUTED)
	_mode_status.autowrap = true
	modes.add_child(_mode_status)

func _apply_mode(key: String) -> void:
	_mode_status.text = load(ModPaths.CORE_DIR + "ModePresets.gd").new().apply(tas_tool, key)

func _export_settings() -> void:
	_mode_status.text = load(ModPaths.CORE_DIR + "ModePresets.gd").new().export_settings()

func _import_settings() -> void:
	_mode_status.text = load(ModPaths.CORE_DIR + "ModePresets.gd").new().import_settings()

func _build_appearance(settings: VBoxContainer) -> void:
	var look = card(settings, "Appearance", Color("ff8ec6"))
	look.add_child(label("Theme", 15))
	var themes = HBoxContainer.new()
	themes.add_constant_override("separation", 8)
	look.add_child(themes)
	for entry in [["Dark", "dark", "moon"], ["Light", "light", "sun"]]:
		var choice = Kit.action(self, themes, entry[0], entry[2], self, "_set_theme", [entry[1]], Galaxy.theme_name() == entry[1])
		choice.rect_min_size.x = 110
	var motion = CheckButton.new()
	motion.text = "Reduced motion"
	motion.hint_tooltip = "Stops twinkling stars and other decoration"
	motion.pressed = bool(SavedSettings.get_value("workspace_reduced_motion", false))
	motion.focus_mode = Control.FOCUS_NONE
	motion.add_icon_override("on", _toggle_icon(true))
	motion.add_icon_override("off", _toggle_icon(false))
	motion.add_font_override("font", font(17))
	motion.add_color_override("font_color", INK)
	motion.add_color_override("font_color_hover", INK)
	motion.add_color_override("font_color_pressed", INK)
	motion.connect("toggled", self, "_set_reduced_motion")
	look.add_child(motion)
	var control_motion = CheckButton.new()
	control_motion.text = "Animate controls"
	control_motion.hint_tooltip = "Subtle hover, press, toggle and input feedback. Reduced motion takes priority."
	control_motion.pressed = bool(SavedSettings.get_value("workspace_control_motion",true))
	control_motion.focus_mode = Control.FOCUS_NONE
	control_motion.add_font_override("font",font(17))
	control_motion.connect("toggled",self,"_set_control_motion")
	look.add_child(control_motion)
	var cards_toggle = CheckButton.new()
	cards_toggle.text = "Player cards in matches"
	cards_toggle.hint_tooltip = "Hover a Goober for name and ping, click for its card"
	cards_toggle.pressed = bool(SavedSettings.get_value("player_cards_enabled", true))
	cards_toggle.focus_mode = Control.FOCUS_NONE
	cards_toggle.add_icon_override("on", _toggle_icon(true))
	cards_toggle.add_icon_override("off", _toggle_icon(false))
	cards_toggle.add_font_override("font", font(17))
	cards_toggle.add_color_override("font_color", INK)
	cards_toggle.add_color_override("font_color_hover", INK)
	cards_toggle.add_color_override("font_color_pressed", INK)
	cards_toggle.connect("toggled", self, "_set_player_cards")
	look.add_child(cards_toggle)
	var meters_toggle = cards_toggle.duplicate(Node.DUPLICATE_SCRIPTS)
	meters_toggle.text = "Dash recharge on other players"
	meters_toggle.hint_tooltip = "A small ring over each other Goober while its dash recharges"
	meters_toggle.pressed = bool(SavedSettings.get_value("player_dash_meters", true))
	meters_toggle.connect("toggled", self, "_set_dash_meters")
	look.add_child(meters_toggle)
	look.add_child(label("Accent colour", 15))
	var swatches = HBoxContainer.new()
	swatches.add_constant_override("separation", 8)
	look.add_child(swatches)
	for entry in ACCENTS:
		var color = Color(entry[1])
		var swatch = Button.new()
		swatch.text = entry[0]
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.rect_min_size = Vector2(92, 34)
		swatch.add_font_override("font", font(14))
		swatch.add_color_override("font_color", color.lightened(0.2))
		swatch.add_color_override("font_color_hover", color.lightened(0.3))
		swatch.connect("pressed", self, "_set_accent", [entry[1]])
		swatches.add_child(swatch)
		_accent_buttons.append([swatch, color])
	_style_accent_buttons()
	look.add_child(label("Text size", 15))
	var sizes = HBoxContainer.new()
	sizes.add_constant_override("separation", 8)
	look.add_child(sizes)
	for entry in TEXT_SIZES:
		var size_button = Button.new()
		size_button.text = entry[0]
		size_button.focus_mode = Control.FOCUS_NONE
		size_button.rect_min_size = Vector2(92, 34)
		size_button.add_font_override("font", font(14))
		size_button.add_stylebox_override("hover", box(RAISED, MINT, 10))
		size_button.add_stylebox_override("pressed", box(SELECTED, MINT, 10))
		size_button.add_stylebox_override("focus", StyleBoxEmpty.new())
		size_button.connect("pressed", self, "_set_text_size", [entry[1]])
		sizes.add_child(size_button)
		_text_buttons.append([size_button, entry[1]])
	_style_text_buttons()
	look.add_child(label("Panel see-through", 15))
	_glass_slider = HSlider.new()
	_glass_slider.min_value = 70
	_glass_slider.max_value = 100
	_glass_slider.step = 1
	_glass_slider.value = _glass_alpha() * 100.0
	_glass_slider.rect_min_size = Vector2(260, 24)
	_glass_slider.focus_mode = Control.FOCUS_NONE
	_glass_slider.connect("value_changed", self, "_set_glass")
	look.add_child(_glass_slider)
	var classic = CheckButton.new()
	classic.text = "Classic menu look"
	classic.pressed = bool(SavedSettings.get_value("workspace_classic", false))
	classic.focus_mode = Control.FOCUS_NONE
	classic.add_icon_override("on", _toggle_icon(true))
	classic.add_icon_override("off", _toggle_icon(false))
	classic.add_font_override("font", font(17))
	classic.add_color_override("font_color", INK)
	classic.add_color_override("font_color_hover", INK)
	classic.add_color_override("font_color_pressed", INK)
	classic.connect("toggled", self, "_set_classic")
	look.add_child(classic)
	look.add_child(label("Applies after restarting the game.", 14, MUTED))

func _style_accent_buttons() -> void:
	for entry in _accent_buttons:
		var chosen = entry[1].to_html(false) == MINT.to_html(false)
		entry[0].add_stylebox_override("normal", box(Color(entry[1].r, entry[1].g, entry[1].b, 0.22 if chosen else 0.08), entry[1] if chosen else Color(entry[1].r, entry[1].g, entry[1].b, 0.35), 10))
		entry[0].add_stylebox_override("hover", box(Color(entry[1].r, entry[1].g, entry[1].b, 0.24), entry[1], 10))
		entry[0].add_stylebox_override("pressed", box(Color(entry[1].r, entry[1].g, entry[1].b, 0.3), entry[1], 10))
		entry[0].add_stylebox_override("focus", StyleBoxEmpty.new())

func _set_accent(hex: String) -> void:
	SavedSettings.set_value("workspace_accent", hex)
	MINT = Color(hex)
	SELECTED = MINT.darkened(0.72)
	_style_accent_buttons()
	for check in _setting_checks:
		check[0].add_icon_override("on", _toggle_icon(true))
	var strip = tas_tool.get("_menu_panel").find_node("WorkspaceAccentStrip", true, false)
	if strip != null:
		strip.texture.gradient.set_color(0, MINT)
	var search = tas_tool.get("_menu_panel").find_node("WorkspaceSearch", true, false)
	if search != null:
		search.add_stylebox_override("focus", box(SURFACE, MINT, 14))
	_sync_quick()
	_sync_nav()

func _set_glass(value: float) -> void:
	SavedSettings.set_value("workspace_glass", value / 100.0)
	tas_tool.get("_menu_panel").add_stylebox_override("panel", _panel_style())

func _set_theme(name: String) -> void:
	if name == Galaxy.theme_name():
		return
	SavedSettings.set_value("workspace_theme", name)
	var accent = str(SavedSettings.get_value("workspace_accent", "a68bff"))
	if accent == "6240ca":
		SavedSettings.set_value("workspace_accent", "a68bff")
	_message("The %s theme applies after you restart the game." % name)

func _set_reduced_motion(value: bool) -> void:
	SavedSettings.set_value("workspace_reduced_motion", value)
	if hero != null and hero.band != null:
		hero.band._sync_process()
		hero.band.update()

func _set_control_motion(value: bool) -> void:
	SavedSettings.set_value("workspace_control_motion",value)

func _sync_bell() -> void:
	if bell == null or not is_instance_valid(bell):
		return
	var count = Notices.unread()
	bell.text = str(count) if count > 0 else ""
	bell.hint_tooltip = "Notifications · %d unread" % count if count > 0 else "Notifications"

# 4.0 pages. Each page is a small script in core/workspace4/pages/.
func _build_v4_pages() -> void:
	var dir = ModPaths.CORE_DIR + "workspace4/"
	overlay_layer = load(dir + "OverlayLayer.gd").new()
	overlay_layer.name = "GoobOverlayLayer"
	add_child(overlay_layer)
	effect_runtime = load(dir + "EffectRuntime.gd").ensure(tas_tool)
	for entry in [["overlay", "Overlay Studio", "OverlayStudioPage.gd"], ["effects", "Effects Editor", "EffectsStudioPage.gd"], ["clips", "Clip Studio", "ClipStudioPage.gd"], ["workshop", "Workshop", "WorkshopPage.gd"], ["news", "News", "NewsPage.gd"], ["notifications", "Notifications", "NotificationsPage.gd"]]:
		var script = ModPaths.try_load(dir + "pages/" + entry[2])
		if script == null:
			continue
		var content = page(entry[0], entry[1])
		# Keep the data services alive, but construct editors, galleries and
		# their preview timers only when the player actually opens that page.
		_v4_pending[entry[0]] = {"script":script,"content":content}
	var cards = load(dir + "PlayerCards.gd").new()
	cards.name = "GoobPlayerCards"
	cards.tas_tool = tas_tool
	cards.menu = self
	add_child(cards)
	var bottom = load(dir + "BottomTabs.gd").new()
	bottom.name = "GoobBottomTabs"
	bottom.tool = tas_tool
	bottom.menu = self
	add_child(bottom)
	page_tween = Tween.new()
	add_child(page_tween)
	var window = tas_tool.get("_menu_window")
	if window != null and not window.is_connected("visibility_changed", self, "_window_shown"):
		window.connect("visibility_changed", self, "_window_shown")
	_sync_bell()

func _ensure_v4_page(key: String) -> void:
	if not _v4_pending.has(key): return
	var pending = _v4_pending[key]
	_v4_pending.erase(key)
	var builder = pending.script.new()
	v4_pages[key] = builder
	match key:
		"overlay", "workshop": builder.build(self,pending.content,overlay_layer)
		"effects": builder.build(self,pending.content,effect_runtime)
		_: builder.build(self,pending.content)

# Motion: pages fade in, the window fades in when opened, tiles lift on hover.
var page_tween: Tween

func _reduced_motion() -> bool:
	return bool(SavedSettings.get_value("workspace_reduced_motion", false))

func _animate_page() -> void:
	if page_tween == null or _reduced_motion():
		return
	var current = tabs.get_current_tab_control()
	if current == null:
		return
	page_tween.stop(current)
	page_tween.interpolate_property(current, "modulate", Color(1, 1, 1, 0), Color(1, 1, 1, 1), 0.18, Tween.TRANS_QUAD, Tween.EASE_OUT)
	page_tween.start()

func _window_shown() -> void:
	var window = tas_tool.get("_menu_window")
	if page_tween == null or window == null or not window.visible or _reduced_motion():
		return
	page_tween.interpolate_property(window, "modulate", Color(1, 1, 1, 0), Color(1, 1, 1, 1), 0.16, Tween.TRANS_QUAD, Tween.EASE_OUT)
	page_tween.start()

func _tile_hover(tile: Control, inside: bool) -> void:
	if page_tween == null or _reduced_motion():
		return
	tile.rect_pivot_offset = tile.rect_size / 2
	page_tween.interpolate_property(tile, "rect_scale", tile.rect_scale, Vector2.ONE * (1.03 if inside else 1.0), 0.14, Tween.TRANS_BACK, Tween.EASE_OUT)
	page_tween.start()

func _set_dash_meters(value: bool) -> void:
	SavedSettings.set_value("player_dash_meters", value)

func _set_player_cards(value: bool) -> void:
	SavedSettings.set_value("player_cards_enabled", value)

func _set_classic(value: bool) -> void:
	SavedSettings.set_value("workspace_classic", value)
	_message("The menu look changes after you restart the game.")

var _toggle_cache = {}

func _toggle_icon(on: bool) -> Texture:
	var cache_key = "%s|%s|%.2f" % [str(on), MINT.to_html(false), _text_k]
	if _toggle_cache.has(cache_key):
		return _toggle_cache[cache_key]
	var pixels = Image.new()
	pixels.create(36, 20, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.transparent)
	pixels.lock()
	var track = MINT.darkened(0.45) if on else Color("2f3a40")
	var knob = MINT.lightened(0.15) if on else Color("8d9ea5")
	for y in range(20):
		for x in range(36):
			var edge = Vector2(clamp(x, 10, 25), 10)
			var distance = Vector2(x + 0.5, y + 0.5).distance_to(edge + Vector2(0.5, 0.5))
			if distance < 9.0:
				var alpha = clamp(9.0 - distance, 0.0, 1.0)
				pixels.set_pixel(x, y, Color(track.r, track.g, track.b, alpha))
			var knob_distance = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(26.5 if on else 9.5, 10.5))
			if knob_distance < 6.5:
				var blend = clamp(6.5 - knob_distance, 0.0, 1.0)
				var under = pixels.get_pixel(x, y)
				pixels.set_pixel(x, y, under.linear_interpolate(Color(knob.r, knob.g, knob.b, 1.0), blend))
	pixels.unlock()
	if _text_k > 1.02:
		pixels.resize(int(round(36 * _text_k)), int(round(20 * _text_k)), Image.INTERPOLATE_LANCZOS)
	var texture = ImageTexture.new()
	texture.create_from_image(pixels, Texture.FLAG_FILTER)
	_toggle_cache[cache_key] = texture
	return texture

func _build_themes() -> void:
	var themes = page("themes", "Editor themes")
	# Main menu backgrounds are Journey rank rewards now (Journey -> Rewards).
	var menu_card = card(themes, "Main menu background", tint("CREATE"))
	menu_card.add_child(label("Unlock and equip menu backgrounds in Journey → Rewards.", 15, MUTED))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	themes.add_child(grid)
	for entry in [["Space", Color("99addf")], ["Neon", Color("9dd6bd")], ["Sunset", Color("e8b38f")], ["Moon", Color("d4dfed")], ["Lagoon", Color("7dd8ce")], ["Ember", Color("f3b074")], ["Orchard", Color("c9d78e")], ["Porcelain", Color("85a6c7")], ["Mushroom Valley", Color("df9c83")], ["Floating Island", Color("b1d7b0")], ["Cloud Passage", Color("eaf0eb")], ["Sweet Hazard", Color("d3a0a0")], ["Animal Kingdom", Color("d9c482")], ["Holy Night", Color("c9dee4")], ["Wild Jungle", Color("a6c494")], ["Night Plain", Color("a2c9bd")], ["Black Forest", Color("a3b4a6")], ["Summer Beach", Color("f0d49a")]]:
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_stylebox_override("panel", edge_box(SURFACE, entry[1], 14))
		grid.add_child(panel)
		var column = VBoxContainer.new()
		column.add_constant_override("separation", 6)
		panel.add_child(column)
		column.add_child(label(entry[0], 16))
		var swatch = ColorRect.new()
		swatch.color = entry[1]
		swatch.rect_min_size.y = 8
		column.add_child(swatch)
	themes.add_child(label("Choose a pack in the level editor’s theme picker.", 15, MUTED))
	themes.add_child(button("Module settings", "settings", 11))

# ------------------------------------------------------------ navigation

func select(key: String) -> void:
	if key.begins_with("period:"):
		_wins_period = key.trim_prefix("period:")
		_refresh_wins(true)
		return
	if key.begins_with("wins-") or key.begins_with("profile:"):
		var wins = tas_tool.get("_wins_leaderboard")
		if wins != null and is_instance_valid(wins) and wins.get("gui_enabled"):
			if key == "wins-refresh":
				wins.call("_request_latest_snapshot", true)
			elif key == "wins-import":
				wins.call("_open_import_dialog")
			else:
				wins.call("_on_wins_row_pressed", key.trim_prefix("profile:"))
		return
	if key == "close":
		tas_tool.call("_on_tab_pressed")
		return
	if key == "editor-plus":
		if enabled(key):
			_remember(key)
			_open_tool(key)
		return
	if not enabled(key):
		return
	_remember(key)
	if _open_redesigned_page(key):
		return
	if shell != null and shell.open_page(key):
		return
	if pages.has(key):
		_ensure_v4_page(key)
		var changed = tabs.current_tab != pages[key]
		tabs.current_tab = pages[key]
		active = key
		if changed:
			_animate_page()
		notice.visible = false
		if key == "wins":
			_refresh_wins(true)
		if key == "settings":
			for check in _setting_checks:
				check[0].set_pressed_no_signal(bool(tas_tool.get(check[1])))
		if key == "home":
			_rebuild_recent()
			_refresh_status()
		_sync_nav()
		return
	if main_handler.owns(key):
		_open_tool(key)

func _search_entered(text: String) -> void:
	for item in ITEMS:
		if nav.has(item[1]) and nav[item[1]].visible and _matches_navigation(item[1],text):
			select("rated" if item[1]=="maps" and "rated" in text.to_lower() else item[1])
			return

func _matches_navigation(key: String,query: String) -> bool:
	var title = nav[key].text if nav.has(key) else key
	return query.strip_edges().to_lower() in (title+" "+str(PAGE_SEARCH.get(key,""))).to_lower()

func _open_tool(key: String) -> void:
	var problem = main_handler.open(tas_tool, key)
	if not problem.empty():
		_message(problem)

func _message(text: String) -> void:
	notice.text = text
	notice.visible = true

func _tab_changed(index: int) -> void:
	if shell != null:
		shell.sync_visibility()
	for key in pages:
		if pages[key] == index:
			active = key
			_sync_nav()
			break

func _sync_nav() -> void:
	for key in nav:
		var chosen = key == active
		var color = nav_colors.get(key, MINT)
		if key == "home":
			color = MINT
		var style
		if chosen:
			style = edge_box(Color(color.r, color.g, color.b, 0.14), color, 12)
		else:
			style = box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12)
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		if key in CHILD_KEYS:
			style.content_margin_left = 30
		nav[key].add_stylebox_override("normal", style)
		if nav_icons.has(key):
			nav[key].icon = icon(nav_icons[key], MINT if chosen else MUTED)
		var hover = box(Color(color.r, color.g, color.b, 0.08), Color(0, 0, 0, 0), 12)
		hover.content_margin_top = 5
		hover.content_margin_bottom = 5
		if key in CHILD_KEYS:
			hover.content_margin_left = 30
		nav[key].add_stylebox_override("hover", hover)
		nav[key].add_color_override("font_color", INK if chosen else MUTED.lightened(0.15))
		nav[key].add_color_override("font_color_hover", color.lightened(0.2))
	heading.text = tabs.get_tab_title(tabs.current_tab)
	heading.get_parent().visible = active != "home"
	if v4_pages.has(active) and v4_pages[active].has_method("refresh"):
		v4_pages[active].refresh()
	var group = ""
	for item in ITEMS:
		if item[1] == active:
			group = item[3]
	heading_chip.visible = not group.empty() and active != "home"
	if heading_chip.visible:
		var color = tint(group)
		heading_chip_label.text = group
		heading_chip_label.add_color_override("font_color", color.lightened(0.15))
		var style = heading_chip.get_stylebox("panel").duplicate()
		style.bg_color = Color(color.r, color.g, color.b, 0.16)
		style.border_color = Color(color.r, color.g, color.b, 0.45)
		heading_chip.add_stylebox_override("panel", style)

func _filter(query: String) -> void:
	search_query = query
	var searching = not query.strip_edges().empty()
	for key in nav:
		nav[key].visible = enabled(key) and (not searching or _matches_navigation(key,query))
	for entry in links:
		if is_instance_valid(entry[0]) and entry[0] != nav.get(entry[1]):
			entry[0].visible = enabled(entry[1])
	for group in nav_groups:
		var any = false
		var index = group.get_index() + 1
		var parent = group.get_parent()
		while index < parent.get_child_count() and not nav_groups.has(parent.get_child(index)):
			any = any or parent.get_child(index).visible
			index += 1
		group.visible = not searching and any

func _setting_changed(value: bool, callback: String) -> void:
	tas_tool.call(callback, value)
	_sync_developer()
	_filter(search_query)
	if not enabled(active):
		select("settings")

func enabled(key):
	# Accounts and Editor+ no longer depend on the Game tools switch.
	if key in ["accounts", "editor-plus"]:
		return main_handler.is_installed(main_handler.KEY_NEEDS[key]) and tas_tool.get("_game_tools") != null
	return main_handler.enabled(tas_tool, key)

func _refresh_visibility():
	var window = tas_tool.get("_menu_window")
	if window != null and not window.is_visible_in_tree():
		return
	_filter(search_query)


func _sync_developer() -> void:
	for section in _developer_sections:
		section.visible = bool(tas_tool.get("_debug_mode_enabled"))

func _build_wins() -> void:
	var content = page("wins", "Wins")
	var view_script = load(ModPaths.path("WinsBoardView.gd"))
	if view_script != null and view_script.can_instance():
		_wins_view = view_script.new()
		_wins_view.close_workspace_on_profile = true
		content.add_child(_wins_view)
		_wins_view.build(tas_tool.get("_wins_leaderboard"), tas_tool)
		return
	var row = HBoxContainer.new()
	content.add_child(row)
	for period in [["All time", "all_time"], ["Daily", "daily"], ["Weekly", "weekly"], ["Monthly", "monthly"], ["Yearly", "yearly"]]:
		var btn = button(period[0], "period:" + period[1])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(btn)
	var actions = HBoxContainer.new()
	content.add_child(actions)
	actions.add_child(button("Refresh", "wins-refresh"))
	actions.add_child(button("Import CSV", "wins-import"))
	_wins_summary = label("", 15, MUTED)
	_wins_summary.autowrap = true
	content.add_child(_wins_summary)
	_wins_rows = VBoxContainer.new()
	_wins_rows.add_constant_override("separation", 4)
	content.add_child(_wins_rows)

func _refresh_wins(force: bool = false) -> void:
	if active != "wins" or not tabs.is_visible_in_tree():
		return
	if _wins_view != null:
		_wins_view.module = tas_tool.get("_wins_leaderboard")
		_wins_view.refresh(force)
		return
	var module = tas_tool.get("_wins_leaderboard")
	if module == null or not is_instance_valid(module):
		_wins_summary.text = "Wins module is unavailable."
		return
	if not module.get("gui_enabled"):
		_wins_summary.text = "Enable Wins leaderboard in Settings."
		_wins_signature = ""
		for child in _wins_rows.get_children():
			child.queue_free()
		return
	var latest = str(module.call("_latest_snapshot_key"))
	var snapshots = module.get("_snapshots")
	var signature = _wins_period + latest + str(snapshots.hash()) + str(module.get("_request_busy"))
	if signature == _wins_signature and not force:
		return
	_wins_signature = signature
	for child in _wins_rows.get_children():
		_wins_rows.remove_child(child)
		child.queue_free()
	if latest.empty():
		_wins_summary.text = "No snapshot yet. Refresh to download, or import a CSV."
		return
	var result = module.call("_period_result", _wins_period, latest)
	_wins_summary.text = str(result.get("title", "")) + "\n" + str(result.get("coverage", ""))
	if not result.get("available", false):
		_wins_rows.add_child(label(str(result.get("message", "No history for this period.")), 15, MUTED))
		return
	var rows: Array = result.get("rows", [])
	rows.sort_custom(module, "_sort_wins_descending")
	for i in range(min(rows.size(), 100)):
		var panel = PanelContainer.new()
		panel.add_stylebox_override("panel", box(SURFACE if i % 2 == 0 else BG))
		_wins_rows.add_child(panel)
		var row = HBoxContainer.new()
		panel.add_child(row)
		var rank = label("%02d" % (i + 1), 16, [Color("ffd166"), Color("c9d7e3"), Color("d89b72")][i] if i < 3 else MUTED)
		rank.rect_min_size.x = 44
		row.add_child(rank)
		var username = button(str(rows[i].get("username", "Unknown")), "profile:" + str(rows[i].get("id", "")))
		username.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		username.clip_text = true
		row.add_child(username)
		row.add_child(label(str(rows[i].get("wins", 0)), 17, MINT))

func _skin_modules() -> void:
	_filter(search_query)
	for key in ["_cosmetic_sandbox", "_replay_hub", "_game_tools", "_social_hub", "_cosmetic_loadouts", "_match_map_preview", "_macro_editor"]:
		var module = tas_tool.get(key)
		if module != null and is_instance_valid(module):
			_skin(module)
	apply_scale()


# Text grows when the menu is shown small (low UI scale or zoomed out), so it
# stays readable. Settings > Appearance > Text size can make it larger still.
const TEXT_SIZES = [["Auto", "auto"], ["Normal", "normal"], ["Large", "large"], ["Extra large", "xlarge"]]
var _text_buttons = []
var _text_k = 1.0
var _icon_users = []

func _apply_text_scale(effective: float) -> void:
	var mode = str(SavedSettings.get_value("workspace_text", "auto"))
	var grow = clamp(1.0 / max(0.2, effective), 1.0, 1.8)
	var k = 1.0
	if mode == "auto":
		k = grow
	elif mode == "large":
		k = max(grow, 1.0) * 1.2
	elif mode == "xlarge":
		k = max(grow, 1.0) * 1.4
	if abs(k - _text_k) > 0.02:
		_text_k = k
		for entry in _icon_users:
			if not is_instance_valid(entry[0]):
				continue
			if entry[0] is TextureRect:
				entry[0].texture = icon(entry[1], entry[2])
				entry[0].rect_min_size = Vector2(24, 24) * k
			else:
				entry[0].icon = icon(entry[1], entry[2])
		var on_icon = _toggle_icon(true)
		var off_icon = _toggle_icon(false)
		for check in _setting_checks:
			check[0].add_icon_override("on", on_icon)
			check[0].add_icon_override("off", off_icon)
		_sync_quick()
	for base in fonts:
		var size = int(round(base * k))
		if fonts[base] != null and fonts[base].size != size:
			fonts[base].size = size
	for field in ["_title_font", "_header_font", "_body_font", "_small_font"]:
		GoobStyle.remember_font(tas_tool.get(field))
	GoobStyle.set_text_scale(k)

func _set_text_size(mode: String) -> void:
	SavedSettings.set_value("workspace_text", mode)
	_style_text_buttons()
	apply_scale()

func _style_text_buttons() -> void:
	var mode = str(SavedSettings.get_value("workspace_text", "auto"))
	for entry in _text_buttons:
		var chosen = entry[1] == mode
		entry[0].add_stylebox_override("normal", box(SELECTED if chosen else SURFACE, MINT if chosen else BORDER, 10))
		entry[0].add_color_override("font_color", MINT.lightened(0.1) if chosen else INK)

func apply_scale() -> void:
	var factor = tas_tool.get_gui_scale_factor()
	_apply_text_scale(factor * (shell.zoom if shell != null else 1.0))
	for window in [tas_tool.get("_menu_window"), tas_tool.get("_log_window")]:
		if window != null:
			window.rect_scale = Vector2.ONE * factor
	var available_height = (get_viewport().get_visible_rect().size.y - tas_tool.get("_menu_window").rect_position.y) / factor
	for child in tabs.get_children():
		if child is ScrollContainer:
			if not child.has_meta("workspace_base_height"):
				child.set_meta("workspace_base_height", child.rect_min_size.y)
			child.rect_min_size.y = min(float(child.get_meta("workspace_base_height")), max(120.0, available_height - 280.0))
	tas_tool.get("_menu_window").rect_size.y = 0
	var roots = [tas_tool.get("_menu_window"), tas_tool.get("_log_window")]
	for key in ["_cosmetic_sandbox", "_replay_hub", "_game_tools", "_social_hub", "_cosmetic_loadouts", "_match_map_preview", "_macro_editor"]:
		var module = tas_tool.get(key)
		if module == null or not is_instance_valid(module):
			continue
		for field in ["_modal_root", "_export_root", "_root"]:
			if not field in module:
				continue
			var root = module.get(field)
			if root == null or not is_instance_valid(root) or not root is Control:
				continue
			if root.has_meta("shell_embedded"):
				continue
			# Scale a window's coordinate space once; its anchored children then
			# lay out against the inverse-sized root and keep their real hitboxes.
			root.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
			root.rect_position = Vector2.ZERO
			root.rect_size = get_viewport().get_visible_rect().size / factor
			root.rect_scale = Vector2.ONE * factor
			roots.append(root)
	var seen_fonts = {}
	for root in roots:
		if root != null and is_instance_valid(root):
			_scale_fonts(root, factor, seen_fonts)
	if shell != null:
		shell.apply_zoom()


func _scale_fonts(node: Node, factor: float, seen: Dictionary) -> void:
	if node is Control:
		for font_name in ["font", "normal_font", "bold_font", "mono_font"]:
			if not node.has_font_override(font_name):
				continue
			var face = node.get_font(font_name)
			if face is DynamicFont and face.font_data != null:
				if not face.use_filter:
					face.use_filter = true
				if face.use_mipmaps:
					face.use_mipmaps = false
				if not face.font_data.antialiased:
					face.font_data.antialiased = true
				var id = face.font_data.get_instance_id()
				if not seen.has(id):
					seen[id] = true
					var screen_scale = abs(get_viewport().get_final_transform().get_scale().x)
					var sampling = clamp(ceil(factor * screen_scale * 2.0), 2.0, 8.0)
					if not is_equal_approx(face.font_data.override_oversampling,sampling):
						face.font_data.override_oversampling = sampling
	for child in node.get_children():
		_scale_fonts(child, factor, seen)

func _skin(node: Node) -> void:
	if node is PanelContainer:
		node.add_stylebox_override("panel", box(BG))
	elif node is LineEdit:
		node.add_stylebox_override("normal", box(SURFACE))
		node.add_stylebox_override("focus", box(SURFACE, MINT))
		node.add_font_override("font", font(17))
		node.add_color_override("font_color", INK)
	elif node is Label:
		node.add_color_override("font_color_shadow", Color.transparent)
	for child in node.get_children():
		_skin(child)

# Lazy presentation adapters reuse the installed controllers. Old route keys
# remain valid, including rated -> Maps / Top rated. No window fitting/scaling.
func _open_redesigned_page(key: String) -> bool:
	var definitions = {"game":["Game tools","GameToolsPage.gd"],"maps":["Maps","MapsPage.gd"],"replays":["Replay library","ReplayLibraryPage.gd"],"themes":["Level themes","ThemesPage.gd"]}
	var route = "maps" if key=="rated" else key
	if not definitions.has(route): return false
	if not enabled(key): return false
	if not v4_pages.has(route):
		var script = ModPaths.try_load(ModPaths.CORE_DIR+"workspace4/pages/"+definitions[route][1])
		if script==null or not script.can_instance(): return false
		var content = page(route,definitions[route][0])
		var builder = script.new()
		builder.build(self,content)
		v4_pages[route] = builder
	var changed = tabs.current_tab!=pages[route]
	tabs.current_tab = pages[route]
	active = route
	if changed: _animate_page()
	if v4_pages[route].has_method("open"): v4_pages[route].open(key)
	notice.hide()
	tas_tool._set_menu_open(true)
	_sync_nav()
	return true
