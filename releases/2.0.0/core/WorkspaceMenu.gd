extends Node

const ModPaths = preload("user://mod/core/ModPaths.gd")

# Presentation only: existing pages, signals and module controllers stay intact.
const BG = Color("181c20")
const SURFACE = Color("22282c")
const BORDER = Color("343c40")
const INK = Color("f0f1eb")
const MUTED = Color("9ba8ad")
const MINT = Color("9dd6bd")
const SELECTED = Color("293d36")
const ITEMS = [
	["Workspace", "home", 0, ""],
	["Tools", "tab:0", 1, "GAMEPLAY / TOOLS"],
	["Macro Bot", "tab:1", 3, ""],
	["Replay library", "replays", 2, ""],
	["Level Council", "council", 10, ""],
	["Accounts", "accounts", 5, ""],
	["Game tools", "game", 1, ""],
	["Avatar Studio", "sandbox", 5, "CREATE"],
	["Editor+", "editor-plus", 7, ""],
	["Editor themes", "themes", 7, ""],
	["Wins", "wins", 9, ""],
	["Match maps", "maps", 10, ""],
	["Top rated levels", "rated", 7, ""],
	["Settings", "settings", 11, "GENERAL"],
	["Autoplay", "tab:2", 4, "EXPERIMENTAL"],
	["Friends & party", "social", 8, ""],
	["Developer tools", "developer", 12, "DEVELOPER"],
	["Action log", "logs", 12, ""],
]
var main_handler = load(ModPaths.path("MainHandler.gd")).new()
var tas_tool
var tabs: TabContainer
var heading: Label
var nav = {}
var nav_groups = []
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

func box(fill: Color, line: Color = BORDER, padding: int = 16) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = line
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = 10
	s.content_margin_bottom = 10
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
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func icon(index: int) -> Texture:
	if icons.has(index):
		return icons[index]
	var image = Image.new()
	var path = ModPaths.WORKSPACE_ATLAS
	if image.load(path) != OK:
		return null
	var size = Vector2(image.get_width(), image.get_height())
	var origin = Vector2(0.085 + (index % 4) * 0.21, 0.085 + int(index / 4) * 0.21)
	var tile = image.get_rect(Rect2(origin * size, size * 0.21))
	tile.resize(24, 24, Image.INTERPOLATE_LANCZOS)
	var texture = ImageTexture.new()
	texture.create_from_image(tile, Texture.FLAG_FILTER)
	icons[index] = texture
	return texture

func button(text: String, key: String, glyph: int = -1) -> Button:
	var result = Button.new()
	result.text = text
	result.rect_min_size = Vector2(0, 34)
	result.align = Button.ALIGN_LEFT
	result.focus_mode = Control.FOCUS_NONE
	result.add_font_override("font", font(16))
	result.add_color_override("font_color", INK)
	result.add_color_override("font_color_hover", INK)
	result.add_color_override("font_color_pressed", MINT)
	result.add_constant_override("hseparation", 10)
	result.add_stylebox_override("normal", box(BG, BG, 8))
	result.add_stylebox_override("hover", box(SURFACE, BORDER, 10))
	result.add_stylebox_override("pressed", box(SELECTED, SELECTED, 10))
	result.add_stylebox_override("focus", StyleBoxEmpty.new())
	if glyph >= 0:
		result.icon = icon(glyph)
	for state in ["normal", "hover", "pressed"]:
		var style = result.get_stylebox(state).duplicate()
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		result.add_stylebox_override(state, style)
	result.connect("pressed", self, "select", [key])
	links.append([result,key])
	return result

func page(key: String, title: String) -> VBoxContainer:
	var content: VBoxContainer = tas_tool.call("_add_tab_page", tabs, title)
	content.add_constant_override("separation", 10)
	pages[key] = content.get_parent().get_index()
	return content

func card(parent: VBoxContainer, title: String) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", box(SURFACE))
	parent.add_child(panel)
	var inner = VBoxContainer.new()
	inner.add_constant_override("separation", 12)
	panel.add_child(inner)
	if not title.empty():
		inner.add_child(label(title, 18))
	return inner

func build(owner_tool, root: VBoxContainer, section_tabs: TabContainer, resize_row: Control) -> void:
	tas_tool = owner_tool
	tabs = section_tabs
	# Discard presentation chrome only. Page contents are never reconstructed.
	for child in root.get_children():
		if child != tabs and child != resize_row and child != tas_tool.get("_inactive_label"):
			child.hide()
	root.add_constant_override("separation", 16)
	var header = HBoxContainer.new()
	header.name = "WorkspaceDragHeader"
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.hint_tooltip = "Drag to move the menu"
	header.connect("gui_input", tas_tool, "_on_drag_gui_input", ["menu"])
	header.add_constant_override("separation", 12)
	var mark = TextureRect.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.texture = icon(15)
	mark.expand = true
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.rect_min_size = Vector2(36, 36)
	header.add_child(mark)
	header.add_child(label("Goobplayability", 22))
	var space = Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(space)
	header.add_child(label("WORKSPACE", 12, MUTED))
	var close = button("×", "close")
	close.rect_min_size.x = 36
	close.hint_tooltip = "Close menu"
	header.add_child(close)
	root.add_child(header)
	root.move_child(header, 0)
	var body = HBoxContainer.new()
	body.add_constant_override("separation", 22)
	root.add_child(body)
	root.move_child(body, resize_row.get_index())
	var sidebar_scroll = ScrollContainer.new()
	sidebar_scroll.rect_min_size = Vector2(204, 0)
	sidebar_scroll.scroll_horizontal_enabled = false
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sidebar_scroll)
	var sidebar = VBoxContainer.new()
	sidebar.add_constant_override("separation", 3)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(sidebar)
	var search = LineEdit.new()
	search.placeholder_text = "Find a module"
	search.rect_min_size.y = 38
	search.add_font_override("font", font(15))
	search.add_stylebox_override("normal", box(BG))
	search.add_stylebox_override("focus", box(BG, MINT))
	search.add_color_override("font_color", INK)
	search.connect("text_changed", self, "_filter")
	sidebar.add_child(search)
	for item in ITEMS:
		if not item[3].empty():
			var group = label(item[3], 11, MUTED)
			group.rect_min_size.y = 26
			group.valign = Label.VALIGN_BOTTOM
			sidebar.add_child(group)
			nav_groups.append(group)
		var link = button(item[0], item[1], item[2])
		sidebar.add_child(link)
		nav[item[1]] = link
	var divider = VSeparator.new()
	var line = StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	line.vertical = true
	divider.add_stylebox_override("separator", line)
	body.add_child(divider)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_constant_override("separation", 12)
	body.add_child(content)
	heading = label("Workspace", 26)
	content.add_child(heading)
	notice = label("", 15, MUTED)
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
	developer.add_child(label("Uses the existing Debug tools setting.", 14, MUTED))
	developer.add_child(button("Debug settings", "settings", 11))
	developer.add_child(button("Save player data outline", "player-outline", 12))
	var diagnostics = tas_tool.get("_debug_tools_container")
	if diagnostics != null:
		diagnostics.get_parent().remove_child(diagnostics)
		developer.add_child(diagnostics)
	var tools_content = tabs.get_child(pages["tab:0"]).get_child(0)
	for child in tools_content.get_children():
		if child.has_meta("workspace_developer"):
			tools_content.remove_child(child)
			developer.add_child(child)
			_developer_sections.append(child)
	_sync_developer()
	_build_themes()
	_build_wins()
	shell = load(get_script().resource_path.get_base_dir().plus_file("ModulePages.gd")).new()
	add_child(shell)
	shell.build(self)
	tabs.connect("tab_changed", self, "_tab_changed")
	tas_tool.get("_menu_panel").add_stylebox_override("panel", box(BG, BORDER, 20))
	select("home")
	call_deferred("_skin_modules")
	if not get_viewport().is_connected("size_changed", self, "apply_scale"):
		get_viewport().connect("size_changed", self, "apply_scale")
	var refresh = Timer.new()
	refresh.wait_time = 1.0
	refresh.connect("timeout", self, "_refresh_wins")
	refresh.connect("timeout", self, "_refresh_visibility")
	add_child(refresh)
	refresh.start()

func _build_home() -> void:
	var home = page("home", "Workspace")
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation", 12)
	grid.add_constant_override("vseparation", 12)
	home.add_child(grid)
	for entry in [["Macro Bot", "Record · edit · replay", "tab:1", 3], ["Autoplay", "Learn a route", "tab:2", 4], ["Looks", "Save your favourite outfits", "loadouts", 6], ["Replay library", "Browse your recordings", "replays", 2], ["Friends & party", "Play together", "social", 8], ["Wins", "Daily · weekly · monthly · yearly", "wins", 9]]:
		var launch = button(entry[0], entry[2], entry[3])
		launch.hint_tooltip = entry[1]
		launch.rect_min_size = Vector2(240, 64)
		launch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		launch.add_stylebox_override("normal", box(SURFACE))
		grid.add_child(launch)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	home.add_child(row)
	row.add_child(button("Input & overlays", "tab:0", 13))
	row.add_child(button("Timeline editor", "timeline", 3))
	row.add_child(button("Settings", "settings", 11))

func _build_settings() -> void:
	var settings = page("settings", "Settings")
	var categories = {}
	for title in ["General", "Gameplay / Tools", "Experimental", "Developer"]:
		categories[title] = card(settings, title)
	categories["Experimental"].add_child(label("Features still being tested.", 14, MUTED))
	categories["Experimental"].add_child(button("Autoplay", "tab:2", 4))
	for entry in [["Avatar Studio", "_sandbox_gui_enabled", "_on_settings_sandbox_gui_toggled"], ["Replay library", "_replay_hub_gui_enabled", "_on_settings_replay_hub_gui_toggled"], ["Game tools", "_game_tools_gui_enabled", "_on_settings_game_tools_gui_toggled"], ["Friends & party", "_social_hub_gui_enabled", "_on_settings_social_hub_gui_toggled"], ["Looks", "_cosmetic_loadouts_gui_enabled", "_on_settings_cosmetic_loadouts_toggled"], ["Editor themes", "_editor_theme_pack_enabled", "_on_settings_editor_theme_pack_toggled"], ["Match maps", "_match_map_preview_enabled", "_on_settings_match_map_preview_toggled"], ["Wins leaderboard", "_wins_leaderboard_enabled", "_on_settings_wins_leaderboard_toggled"], ["Leaderboard search", "_leaderboard_search_enabled", "_on_settings_leaderboard_search_toggled"], ["Custom lobby code", "_custom_lobby_code_enabled", "_on_settings_custom_lobby_code_toggled"], ["Debug tools", "_debug_mode_enabled", "_on_settings_debug_mode_toggled"], ["Update checks", "_update_checks_enabled", "_on_settings_update_checks_toggled"]]:
		if not main_handler.setting_available(entry[1]):
			continue
		var check = CheckButton.new()
		check.text = entry[0]
		check.pressed = bool(tas_tool.get(entry[1]))
		check.focus_mode = Control.FOCUS_NONE
		check.add_icon_override("on", _toggle_icon(true))
		check.add_icon_override("off", _toggle_icon(false))
		check.add_font_override("font", font(17))
		check.add_color_override("font_color", INK)
		check.rect_min_size.y = 36
		check.connect("toggled", self, "_setting_changed", [entry[2]])
		_setting_checks.append([check, entry[1]])
		var category = "Gameplay / Tools"
		if entry[1] == "_debug_mode_enabled":
			category = "Developer"
		elif entry[1] == "_social_hub_gui_enabled":
			category = "Experimental"
		elif entry[1] in ["_update_checks_enabled", "_sandbox_gui_enabled", "_cosmetic_loadouts_gui_enabled"]:
			category = "General"
		categories[category].add_child(check)
	categories["Developer"].add_child(button("Action log", "logs", 12))
	var system = card(settings, "Interface & updates")
	system.add_child(button("Reset window layout", "reset-layout", 0))
	system.add_child(button("Check for updates", "updates", 11))
	system.add_child(button("Roll back last update", "rollback", 12))
	system.add_child(button("Replay introduction", "intro", 0))
	system.add_child(label("Version " + str(tas_tool.call("_get_goobplayability_version")), 14, MUTED))

func _toggle_icon(on: bool) -> Texture:
	var pixels = Image.new()
	pixels.create(30, 18, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.transparent)
	pixels.lock()
	for y in range(18):
		for x in range(30):
			var edge = Vector2(clamp(x, 9, 20), 9)
			if Vector2(x, y).distance_to(edge) < 8:
				pixels.set_pixel(x, y, SELECTED if on else BORDER)
			if Vector2(x - (21 if on else 8), y - 9).length() < 6:
				pixels.set_pixel(x, y, MINT if on else MUTED)
	pixels.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(pixels, Texture.FLAG_FILTER)
	return texture

func _build_themes() -> void:
	var themes = page("themes", "Editor themes")
	# Main menu backgrounds are Journey rank rewards now (Journey -> Rewards).
	var menu_card = card(themes, "Main menu background")
	menu_card.add_child(label("Unlock and equip menu backgrounds in Journey → Rewards.", 16, MUTED))
	for entry in [["Space", Color("99addf")], ["Neon", Color("9dd6bd")], ["Sunset", Color("e8b38f")], ["Moon", Color("d4dfed")], ["Lagoon", Color("7dd8ce")], ["Ember", Color("f3b074")], ["Orchard", Color("c9d78e")], ["Porcelain", Color("85a6c7")], ["Mushroom Valley", Color("df9c83")], ["Floating Island", Color("b1d7b0")], ["Cloud Passage", Color("eaf0eb")], ["Sweet Hazard", Color("d3a0a0")], ["Animal Kingdom", Color("d9c482")], ["Holy Night", Color("c9dee4")], ["Wild Jungle", Color("a6c494")], ["Night Plain", Color("a2c9bd")], ["Black Forest", Color("a3b4a6")], ["Summer Beach", Color("f0d49a")]]:
		var inner = card(themes, entry[0])
		var swatch = ColorRect.new()
		swatch.color = entry[1]
		swatch.rect_min_size.y = 12
		inner.add_child(swatch)
	themes.add_child(label("Choose a pack in the level editor’s theme picker.", 16, MUTED))
	themes.add_child(button("Module settings", "settings", 11))

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
			_open_tool(key)
		return
	if not enabled(key):
		return
	if shell != null and shell.open_page(key):
		return
	if pages.has(key):
		tabs.current_tab = pages[key]
		active = key
		notice.visible = false
		if key == "wins":
			_refresh_wins(true)
		if key == "settings":
			for check in _setting_checks:
				check[0].set_pressed_no_signal(bool(tas_tool.get(check[1])))
		_sync_nav()
		return
	if main_handler.owns(key):
		_open_tool(key)

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
		var style = box(SELECTED if chosen else BG, SELECTED if chosen else BG, 8)
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		nav[key].add_stylebox_override("normal", style)
		nav[key].add_color_override("font_color", MINT if chosen else INK)
	heading.text = tabs.get_tab_title(tabs.current_tab)

func _filter(query: String) -> void:
	search_query = query
	for key in nav:
		nav[key].visible = enabled(key) and (query.strip_edges().empty() or query.to_lower() in nav[key].text.to_lower())
	for entry in links:
		if is_instance_valid(entry[0]) and entry[0] != nav.get(entry[1]):
			entry[0].visible = enabled(entry[1])
	for group in nav_groups:
		group.visible = query.strip_edges().empty()

func _setting_changed(value: bool, callback: String) -> void:
	tas_tool.call(callback, value)
	_sync_developer()
	_filter(search_query)
	if not enabled(active):
		select("settings")

func enabled(key):
	return main_handler.enabled(tas_tool, key)

func _refresh_visibility():
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
		var rank = label("%02d" % (i + 1), 16, MUTED)
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


func apply_scale() -> void:
	var factor = tas_tool.get_gui_scale_factor()
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
