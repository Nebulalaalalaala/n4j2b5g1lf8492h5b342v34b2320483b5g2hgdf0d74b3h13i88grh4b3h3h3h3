extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Layout = preload("user://mod/core/workspace4/PageLayout.gd")
const Palette = preload("user://mod/core/workspace4/ThemePalette.gd")
const Catalog = preload("user://mod/tools/editor-themes/ThemeCatalog.gd")
const Folders = preload("user://mod/tools/editor-themes/ThemeFolders.gd")
var menu
var module
var ui
var tabs
var toggle
var preview
var selected_title
var selected = ""
var entries = []
var query = ""
var category = "all"
var use_button

func build(owner,content):
	menu = owner
	var game_tools = menu.tas_tool.get("_game_tools")
	module = game_tools._match_themes if is_instance_valid(game_tools) else null
	ui = Layout.new(menu)
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("themes",menu.font(15))
	var match_page = tabs.add_tab("Match look","paint")
	var catalog_page = tabs.add_tab("Editor themes","editor")
	if is_instance_valid(module):
		var controls = Kit.row(match_page)
		toggle = CheckButton.new()
		toggle.text = "Match themes"
		toggle.pressed = module.enabled
		toggle.add_font_override("font",menu.font(15))
		toggle.hint_tooltip = "Changes how matches look on your screen. Replays and TAS physics are unaffected."
		toggle.connect("toggled",module,"set_enabled")
		controls.add_child(toggle)
		ui.badge(controls,"Local appearance")
		ui.move(module,match_page)
		ui.skin(module)
		# Stack the map selector above the preview rather than force a wide
		# two-column legacy panel into a compact F1 window.
		var main = module.search.get_parent().get_parent()
		var stacked = VBoxContainer.new()
		stacked.add_constant_override("separation",14)
		module.add_child(stacked)
		module.move_child(stacked,main.get_index())
		for child in main.get_children(): ui.move(child,stacked)
		main.queue_free()
		module.search.get_parent().get_child(1).rect_min_size.y = 150
		module.choice_grid.connect("resized",self,"_fit_choices")
		module.pool_grid.connect("resized",self,"_fit_choices")
		module.connect("settings_changed",self,"refresh")
		refresh()
	else: ui.note(match_page,"Match themes is unavailable in this installation.")
	var intro = ui.card(catalog_page,"Theme collection","palette")
	ui.note(intro,"Choose a theme in the level editor’s theme picker.","These catalogue tiles show palettes. Selecting one loads the existing theme renderer for a closer preview; it does not alter your level.")
	var controls = Kit.row(intro)
	Kit.field(menu,controls,"","Search themes",self,"_search")
	ui.choice(controls,["All collections","Custom","Themed","Block Bros."],0,self,"_category")
	var detail = ui.card(catalog_page,"Selected theme","eye")
	selected_title = ui.note(detail,"Select a theme below")
	if is_instance_valid(module):
		preview = module.get_script().ThemePreview.new()
		preview.painter = module
		preview.rect_min_size.y = 170
		detail.add_child(preview)
		use_button = Kit.action(menu,detail,"Use for all matches","paint",self,"_use",[],true)
		use_button.disabled = true
	var grid = ui.grid(catalog_page,190)
	for key in Catalog.DEFINITIONS:
		var data = Catalog.DEFINITIONS[key]
		var card = ui.card(grid,"")
		var swatch = Palette.new()
		swatch.definition = data
		card.add_child(swatch)
		var button = Kit.action(menu,card,str(data.name),"",self,"_preview",[str(key)])
		button.clip_text = true
		button.hint_tooltip = str(data.name)+" · preview theme"
		entries.append([card.get_parent(),str(data.name).to_lower(),Folders.category(key,Catalog.DEFINITIONS)])
	var background = ui.card(catalog_page,"Main menu backgrounds","home")
	ui.note(background,"Unlock and equip backgrounds in Journey → Rewards.")
	tabs.finish()

func _fit_choices():
	for grid in [module.choice_grid,module.pool_grid]:
		grid.columns = int(clamp(floor((grid.rect_size.x+8)/112.0),1,6))

func _search(text):
	query = text.strip_edges().to_lower()
	_filter()
func _category(index):
	category = ["all","custom","themed","block_bros"][index]
	_filter()
func _filter():
	for entry in entries: entry[0].visible = (query.empty() or query in entry[1]) and (category=="all" or category==entry[2])
func _preview(key):
	selected = key
	if use_button!=null: use_button.disabled = false
	selected_title.text = str(Catalog.DEFINITIONS[key].name)
	if preview!=null:
		preview.value = key
		preview.res = module.theme_resource(key)
		preview.update()
func _use():
	if selected.empty() or not is_instance_valid(module): return
	module._select_target("")
	module._choose(selected)
	module.set_enabled(true)
	tabs.select(0)
func refresh():
	if is_instance_valid(module) and toggle!=null:
		toggle.set_pressed_no_signal(module.enabled)
		ui.skin(module)
		_fit_choices()
