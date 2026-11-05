extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Layout = preload("user://mod/core/workspace4/PageLayout.gd")
var menu
var module
var ui
var tabs
var switches = {}
var content_root

func build(owner, content):
	menu = owner
	content_root = content
	module = menu.tas_tool.get("_game_tools")
	ui = Layout.new(menu)
	if not is_instance_valid(module):
		ui.note(content,"Game tools is unavailable in this installation.")
		return
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("game",menu.font(15))
	var overview = tabs.add_tab("Quick tools","gamepad")
	var performance = tabs.add_tab("Performance","signal")
	var local = tabs.add_tab("Local play","play")
	var comforts=load("user://mod/core/workspace4/pages/ComfortCards.gd").new()
	overview.add_child(comforts)
	comforts.build(menu,module.comfort)
	var grid = ui.grid(overview,250)
	for spec in [["performance","Performance","signal","Ping optimizer and FPS Boost together."],["readout","FPS / ping","signal","Show a small corner readout."],["dash","Infinite dash","bolt","Keeps dash available; online snapshots may override it."],["emotes","Emote wheel","avatar","Hold the wheel key, point, then release."]]:
		if not module._tool_cards.has(spec[0]): continue
		var card = ui.card(grid,spec[1],spec[2])
		var line = Kit.row(card)
		var toggle = CheckButton.new()
		toggle.text = "Enabled"
		toggle.hint_tooltip = spec[3]
		toggle.add_font_override("font",menu.font(15))
		toggle.connect("toggled",self,"_toggle",[spec[0]])
		line.add_child(toggle)
		switches[spec[0]] = toggle
		line.add_child(menu._spacer())
		if spec[0]=="performance": Kit.action(menu,line,"Configure","settings",self,"_tab",[1])
		elif spec[0]=="readout": Kit.action(menu,line,"Position","settings",self,"_tab",[1])
		elif spec[0]=="emotes": Kit.action(menu,line,"Shortcut","keyboard",module,"_open_shortcut_settings")
	var links = ui.card(overview,"More ways to play","map")
	var actions = Kit.row(links)
	Kit.action(menu,actions,"Maps","map",menu,"select",["maps"])
	Kit.action(menu,actions,"Level themes","layers",menu,"select",["themes"])
	Kit.action(menu,actions,"Accounts","user",menu,"select",["accounts"])
	var perf = ui.card(performance,"Connection","signal")
	ui.move(module._ping_optimizer,perf)
	ui.skin(module._ping_optimizer)
	module._ping_optimizer.get_child(0).hide()
	module._ping_optimizer.notice.hide()
	module._ping_optimizer.level_description.hide()
	module._ping_optimizer.connect("settings_changed",self,"_sync_performance_text")
	_sync_performance_text()
	if menu.v4_pages.has("developer"): menu.v4_pages.developer.refresh()
	if is_instance_valid(module._fps_boost):
		var fps = ui.card(performance,"Rendering","settings")
		ui.move(module._fps_boost,fps)
		ui.skin(module._fps_boost)
		for control in module._fps_boost.get_children():
			if control is Label and control!=module._fps_boost.meter: control.hide()
	var readout = ui.card(performance,"Corner readout","signal")
	ui.move(module._tool_details["readout"],readout)
	ui.skin(module._tool_details["readout"])
	var session = ui.card(local,"Your own match","gamepad")
	ui.note(session,"Solo matchmaking · no online rewards")
	var controls = Kit.row(session)
	for spec in [["Play","play","_play_local_mode"],["Requeue","redo","_retry_local_mode"],["Stop","stop","_stop_local_mode"]]:
		Kit.action(menu,controls,spec[0],spec[1],module,spec[2])
	ui.move(module._local_status,session)
	ui.skin(module._local_status)
	if is_instance_valid(module._status_label):
		var status = ui.card(local,"Player status","user")
		ui.move(module._status_label,status)
		ui.skin(module._status_label)
	tabs.finish()
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.pause_mode = Node.PAUSE_MODE_PROCESS
	content.add_child(timer)
	timer.connect("timeout",self,"_refresh_visible")
	timer.start()
	refresh()

func _refresh_visible():
	if content_root.is_visible_in_tree(): refresh()

func _sync_performance_text():
	module._ping_optimizer.level_picker.hint_tooltip = module._ping_optimizer.level_description.text

func _tab(index): tabs.select(index)

func _toggle(_value,key):
	module._tool_card_pressed(key)
	refresh()

func refresh():
	if not is_instance_valid(module): return
	var states = {"performance":module.performance_enabled(),"readout":module._readout!=null and module._readout.enabled,"dash":module._infinite_dash_enabled,"emotes":module._emote_wheel!=null and module._emote_wheel.binding!=0}
	for key in switches:
		switches[key].set_pressed_no_signal(bool(states.get(key,false)))
		switches[key].text = "On" if states.get(key,false) else "Off"
