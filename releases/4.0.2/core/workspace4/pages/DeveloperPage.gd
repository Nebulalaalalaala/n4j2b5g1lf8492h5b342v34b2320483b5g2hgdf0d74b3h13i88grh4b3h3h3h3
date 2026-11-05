extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Layout = preload("user://mod/core/workspace4/PageLayout.gd")
var menu
var ui
var tabs
var report_actions

func build(owner,content):
	menu = owner
	ui = Layout.new(menu)
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("developer",menu.font(15))
	var diagnostics = tabs.add_tab("Diagnostics","bug")
	var reports = tabs.add_tab("Reports","folder")
	var run = ui.card(diagnostics,"Replay checks","target")
	var controls = menu.tas_tool.get("_debug_tools_container")
	if is_instance_valid(controls):
		ui.move(controls,run)
		ui.skin(controls)
		for row in controls.get_children():
			if row is HBoxContainer: ui.wrap(row,220)
	for section in menu._developer_sections:
		ui.move(section,run)
		ui.skin(section)
	var files = ui.card(reports,"Logs & reports","folder")
	var actions = ui.grid(files,200)
	report_actions = actions
	Kit.action(menu,actions,"Action log","bug",menu,"select",["logs"])
	Kit.action(menu,actions,"Player data outline","save",menu,"select",["player-outline"])
	Kit.action(menu,actions,"Open diagnostics","folder",self,"_folder")
	ui.note(files,"Available while Debug tools is enabled.")
	Kit.action(menu,files,"Debug settings","settings",menu,"select",["settings"])
	tabs.finish()

func _folder(): OS.shell_open(ProjectSettings.globalize_path("user://tas_diagnostics"))

func refresh():
	var game = menu.tas_tool.get("_game_tools")
	if not is_instance_valid(game) or not is_instance_valid(game._ping_optimizer): return
	for control in game._ping_optimizer.get_children():
		if control is Button and control.text in ["SAVE LAG REPORT","STOP COUNCIL RECORDING"]:
			ui.move(control,report_actions)
			ui.skin(control)
