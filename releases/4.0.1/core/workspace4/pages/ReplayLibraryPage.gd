extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Layout = preload("user://mod/core/workspace4/PageLayout.gd")
var menu
var module
var ui
var tabs
var query
var rows = []
var observed
var community
var current = -1
var content_root

func build(owner,content):
	menu = owner
	content_root = content
	module = menu.tas_tool.get("_replay_hub")
	ui = Layout.new(menu)
	if not is_instance_valid(module):
		ui.note(content,"Replay library is unavailable in this installation.")
		return
	module.workspace_view = self
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("replays",menu.font(15))
	for spec in [["Featured","star"],["Newest","replay"],["By level","map"],["Observed","eye"]]: tabs.add_tab(spec[0],spec[1])
	var toolbar = Kit.row(content)
	query = Kit.field(menu,toolbar,"","Find a replay, level or author",self,"_filter")
	query.clear_button_enabled = true
	query.hint_tooltip = "Search the loaded results."
	Kit.action(menu,toolbar,"Refresh","redo",module,"_refresh_list")
	var share = Kit.action(menu,toolbar,"Share macro","plus",module,"_open_export_picker")
	module._community_export = share
	module._status_label = ui.note(content,"")
	community = ScrollContainer.new()
	community.scroll_horizontal_enabled = false
	community.rect_min_size.y = 320
	community.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(community)
	module._community_scroll = community
	module._list_box = Kit.column(community,10)
	module._list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	observed = module._observed_scroll
	ui.move(observed,content)
	observed.rect_min_size.y = 320
	ui.skin(observed)
	_resection_observed()
	module._observed_library.connect("refreshed",self,"_observations_refreshed")
	# The export dialog keeps its controller and lives above the F1 page.
	ui.move(module._export_root,module)
	module._export_root.hide()
	ui.skin(module._export_root)
	module._tab_buttons = []
	for i in 4: tabs._buttons[i].connect("pressed",self,"_select",[i])
	tabs.finish()
	observed.hide()
	content.connect("visibility_changed",self,"_visibility_changed")

func _visibility_changed():
	if not content_root.is_visible_in_tree() and is_instance_valid(module._export_root): module._export_root.hide()

func _observations_refreshed():
	var library = module._observed_library
	library.files_picker.disabled = library.names.empty()
	library.rounds_picker.disabled = library.names.empty()
	if library.names.empty():
		library.files_picker.add_item("No saved captures")
		library.rounds_picker.add_item("No rounds")
	library.message.hint_tooltip = library.message.text
	library.message.text = "%d local captures" % library.entries.size()

func open(_key): _select(tabs._current)

func _select(index):
	current = index
	rows.clear()
	module._active_tab = index
	query.visible = index!=module.TAB_OBSERVED
	module._refresh_list()

func _filter(text):
	var term = text.strip_edges().to_lower()
	for item in rows:
		if is_instance_valid(item[0]): item[0].visible = term.empty() or term in item[1]

func replay_card(entry):
	var card = ui.card(module._list_box,"")
	var panel = card.get_parent()
	module._list_box.remove_child(panel)
	var title = str(entry.get("title","Untitled replay"))
	var line = Kit.row(card)
	var name = menu.label(title,18,Galaxy.color("ink"))
	name.autowrap = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name)
	if bool(entry.get("featured",false)): ui.badge(line,"Featured","star")
	var author = str(entry.get("author","Anonymous"))
	var level = str(entry.get("level","Unknown level"))
	ui.note(card,author+" · "+level)
	var actions = Kit.row(card)
	ui.badge(actions,module._format_time_ms(int(entry.get("run_time_ms",0))),"playback")
	var version = ui.note(actions,"v"+str(entry.get("compatibility","unknown")))
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id = str(entry.get("id",""))
	Kit.action(menu,actions,"Download","save",module,"_on_download_pressed",[id,title])
	Kit.action(menu,actions,"Play","play",module,"_on_play_pressed",[id,title],true)
	rows.append([panel,(title+" "+author+" "+level).to_lower()])
	panel.visible = query.text.strip_edges().empty() or query.text.to_lower() in rows.back()[1]
	return panel

func _resection_observed():
	var library = module._observed_library
	var old = library.get_children()
	var capture = ui.card(library,"Local observations","eye")
	ui.note(capture,"Partial position captures · approximate times", "These are client observations, not verified original-input replays. Public spectator admission is not exposed by the game.")
	for child in old:
		if child is Label:
			if child in [library.message,library.research_label]: continue
			child.hide()
	# Reuse every existing control and signal, grouped by task.
	for node in [library.message,library.files_picker.get_parent()]: ui.move(node,capture)
	var playback = ui.card(library,"Review capture","replay")
	for node in [library.participants.get_parent(),library.slider.get_parent()]: ui.move(node,playback)
	var research = ui.card(library,"Find runs","search")
	for node in [library.mode_picker.get_parent(),library.runs_picker,library.research_label]: ui.move(node,research)
	for child in old:
		if child is HBoxContainer and child.get_parent()==library: ui.move(child,capture)
	for section in [capture,playback,research]:
		for child in section.get_children():
			if child is HBoxContainer: ui.wrap(child,210)
	ui.skin(library)

func is_open():
	return is_instance_valid(menu) and menu.active=="replays" and menu.tabs.is_visible_in_tree()
