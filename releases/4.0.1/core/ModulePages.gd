extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Presentation adapter. Controllers, signals and working module contents are reused.
var menu
var tool
var mounted = {}
var zoom = 1.0
var zoom_target = 1.0
var zoom_cursor = Vector2.ZERO
var zoom_anchor = Vector2.ZERO
var guide
var tutorials
var opening = false
var fit_elapsed = 0.0

func build(owner):
	menu = owner
	tool = menu.tas_tool
	pause_mode = Node.PAUSE_MODE_PROCESS
	tutorials = load(get_script().resource_path.get_base_dir().plus_file("ModuleGuidePages.gd")).new()
	for key in ["tab:0","tab:1","tab:2","themes","wins"]:
		if not menu.pages.has(key):
			continue
		var page = content_for(key)
		add_help(page,key)

func content_for(key):
	for child in menu.tabs.get_child(menu.pages[key]).get_children():
		if child is VBoxContainer:
			return child
	return null

func add_help(page,key):
	# Simple browsing/account actions need tooltips, not another tutorial page.
	if not key in ["tab:0","tab:1","tab:2","replays","council"]:
		return
	# The tutorial viewer lived in Editor+, which 4.0 removed.
	if not is_instance_valid(tool.get("_game_tools")) or tool._game_tools.get("_editor_plus") == null:
		return
	var help = menu.button("?  Tutorial","tutorial:"+key)
	help.hint_tooltip = "How to use this tool · examples and diagrams"
	page.add_child(help)
	page.move_child(help,0)

func open_page(key):
	if key.begins_with("tutorial:"):
		open_guide(key.trim_prefix("tutorial:"))
		return true
	if menu.has_method("_open_redesigned_page") and menu._open_redesigned_page(key):
		return true
	var targets = {"maps":["_match_map_preview","open_window"],"rated":["_match_map_preview","open_window"],"replays":["_replay_hub","open_hub"],"game":["_game_tools","open_window"],"social":["_social_hub","open_window"],"loadouts":["_cosmetic_loadouts","open_window"]}
	var module
	var root
	var panel
	if targets.has(key):
		module = tool.get(targets[key][0])
		if not is_instance_valid(module):
			return false
		if key in ["maps","rated"]:
			module.set_catalog_mode(key=="rated")
		opening = true
		module.call(targets[key][1])
		opening = false
		root = module._modal_root
		for child in root.get_children():
			if child is PanelContainer:
				panel = child
				break
	elif key == "council":
		tool._replay_hub.ensure_council()
		module = tool._replay_hub._council
		if module == null:
			return false
		panel = module.panel
		if mounted.has(key):
			root = mounted[key].root
		else:
			root = Control.new()
			panel.get_parent().remove_child(panel)
			root.add_child(panel)
	elif key == "accounts":
		opening = true
		tool._game_tools._account_access.open_signin()
		opening = false
		module = tool._game_tools._account_access._manager.view
		root = module.root
		panel = module.panel
	else:
		return false
	if not is_instance_valid(panel):
		return false
	if not menu.pages.has(key):
		var content = menu.page(key,menu.nav[key].text if menu.nav.has(key) else "Looks")
		add_help(content,key)
	var content = content_for(key)
	# One controller serves match maps and the separate ratings page.
	if not mounted.has(key):
		mounted[key] = {"root":root,"panel":panel,"module":module}
	root.set_meta("shell_embedded",true)
	panel.set_meta("shell_embedded",true)
	if key in ["council","accounts"]:
		# Their standalone drag/scale/close row is superseded by the shared shell.
		panel.get_child(0).get_child(0).hide()
	if key == "accounts" and content.get_node_or_null("AccountExtras") == null and is_instance_valid(tool._game_tools):
		# Native account settings and name change, moved here from Game tools.
		var extras = HBoxContainer.new()
		extras.name = "AccountExtras"
		extras.add_constant_override("separation",10)
		content.add_child(extras)
		content.move_child(extras,0)
		for entry in [["Account settings","open_settings"],["Change name","open_name_change"]]:
			var action = menu.button(entry[0],"",-1)
			action.disconnect("pressed",menu,"select")
			action.connect("pressed",tool._game_tools,"_open_account",[entry[1]])
			extras.add_child(action)
	if root.get_parent()!=content:
		if root.get_parent()!=null:
			root.get_parent().remove_child(root)
		content.add_child(root)
	for child in root.get_children():
		if child is ColorRect:
			child.hide()
	root.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
	root.rect_scale = Vector2.ONE
	root.rect_position = Vector2.ZERO
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
	panel.rect_scale = Vector2.ONE
	panel.rect_position = Vector2.ZERO
	if not panel.has_meta("shell_styled"):
		style_content(panel)
		panel.set_meta("shell_styled",true)
	root.show()
	panel.show()
	menu.tabs.current_tab = menu.pages[key]
	menu.active = key
	menu.notice.hide()
	tool._set_menu_open(true)
	menu._sync_nav()
	sync_visibility()
	if key=="council":
		module.open()
	fit_panel(mounted[key])
	# Font sampling is maintained by the shared shell's scale handler.
	return true

func sync_visibility():
	var current = menu.tabs.get_child(menu.tabs.current_tab)
	for item in mounted.values():
		if is_instance_valid(item.root):
			item.root.visible = current.is_a_parent_of(item.root)

func fit_panel(item):
	var root = item.root
	var panel = item.panel
	if not is_instance_valid(root):
		return
	if root == panel:
		# Let VBoxContainer own this direct child. Feeding a PanelContainer's
		# decorated minimum back into its custom minimum can grow it endlessly.
		return
	panel.rect_position = Vector2.ZERO
	var minimum = panel.get_combined_minimum_size()
	var width = max(minimum.x,root.get_parent().rect_size.x)
	# Fill the page's visible height so embedded windows are not squeezed.
	var page_height = 0.0
	var page = root.get_parent().get_parent() if root.get_parent() != null else null
	if page is ScrollContainer:
		page_height = page.rect_size.y - root.rect_position.y - 12
	var factor = min(1.0,max(1,root.get_parent().rect_size.x)/max(1,minimum.x))
	var height = max(max(480,page_height/factor),minimum.y)
	if not panel.rect_scale.is_equal_approx(Vector2.ONE*factor):
		panel.rect_scale = Vector2.ONE*factor
	if abs(root.rect_min_size.y-height*factor) > 1.0 or root.rect_min_size.x != 0:
		root.rect_min_size = Vector2(0,round(height*factor))
	if abs(panel.rect_size.x-width) > 1.0 or abs(panel.rect_size.y-height) > 1.0:
		panel.rect_size = Vector2(round(width),round(height))

func style_content(node):
	if node is Button and not node is OptionButton and node.get_script()==null and not node.has_meta("council_styled"):
		node.add_font_override("font",menu.font(17))
		node.rect_min_size = Vector2(min(node.rect_min_size.x,140),min(node.rect_min_size.y,38))
		for state in ["normal","hover","pressed"]:
			node.add_stylebox_override(state,menu.box(menu.SURFACE if state!="pressed" else menu.SELECTED,menu.BORDER,10))
	elif node is Label and node.has_font_override("font"):
		var font = node.get_font("font")
		if font is DynamicFont and font.size>22:
			node.add_font_override("font",menu.font(22))
	if node is MarginContainer:
		for side in ["left","right","top","bottom"]:
			node.add_constant_override("margin_"+side,12)
	for child in node.get_children():
		style_content(child)

func open_guide(key):
	if not key in ["tab:0","tab:1","tab:2","replays","council"]:
		return
	if not is_instance_valid(tool._game_tools):
		return
	var editor = tool._game_tools._editor_plus
	if not is_instance_valid(editor):
		return
	if guide == null:
		guide = load(ModPaths.path("EditorGuide.gd")).new()
		editor.add_child(guide)
		guide.build(editor)
	guide.set_pages(tutorials.for_tool(key),"Tool tutorial")
	guide.open()

func zoom_at(cursor,multiplier):
	var window = tool._menu_window
	zoom_cursor = cursor
	zoom_anchor = (cursor-window.rect_position)/window.rect_scale
	zoom_target = clamp(zoom_target*multiplier,0.35,3.0)

func apply_zoom():
	tool._menu_window.rect_scale = Vector2.ONE*tool.get_gui_scale_factor()*zoom

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.control and event.button_index in [BUTTON_WHEEL_UP,BUTTON_WHEEL_DOWN] and tool._menu_window.is_visible_in_tree():
		if tool._menu_window.get_global_rect().has_point(event.position):
			zoom_at(event.position,1.12 if event.button_index==BUTTON_WHEEL_UP else 1.0/1.12)
			get_tree().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.control and event.scancode==KEY_0 and tool._menu_window.is_visible_in_tree():
		zoom = 1.0
		zoom_target = 1.0
		menu.apply_scale()
		tool._menu_window.rect_position = Vector2(20,20)
		get_tree().set_input_as_handled()

func _process(delta):
	if menu == null:
		return
	if abs(zoom-zoom_target)>0.0001:
		zoom = lerp(zoom,zoom_target,min(1.0,delta*18))
		apply_zoom()
		tool._menu_window.rect_position = zoom_cursor-zoom_anchor*tool._menu_window.rect_scale
		if abs(zoom-zoom_target)<0.001:
			menu._scale_fonts(tool._menu_window,tool.get_gui_scale_factor()*zoom,{})
			if menu.has_method("_apply_text_scale"):
				menu._apply_text_scale(tool.get_gui_scale_factor()*zoom)
	# Fit the shown module page only while the menu is open, ten times a second.
	# (Measuring a large page every frame, even with the menu closed, made the
	# game stutter.)
	fit_elapsed += delta
	if fit_elapsed < 0.1 or not tool._menu_window.is_visible_in_tree() or not bool(tool.get("_menu_open")):
		return
	fit_elapsed = 0.0
	if mounted.has(menu.active):
		fit_panel(mounted[menu.active])
		if not mounted[menu.active].root.visible or not mounted[menu.active].panel.visible:
			menu.select("home")
