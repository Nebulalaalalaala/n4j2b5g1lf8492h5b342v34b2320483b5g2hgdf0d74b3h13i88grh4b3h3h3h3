extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Layout = preload("user://mod/core/workspace4/PageLayout.gd")
var menu
var module
var ui
var tabs
var match_page
var rated_page
var list
var status
var query
var rating_rows = []

func build(owner, content):
	menu = owner
	module = menu.tas_tool.get("_match_map_preview")
	ui = Layout.new(menu)
	if not is_instance_valid(module):
		ui.note(content,"Maps is unavailable in this installation.")
		return
	module.workspace_view = self
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("maps",menu.font(15))
	match_page = tabs.add_tab("This match","flag")
	rated_page = tabs.add_tab("Top rated","star")
	ui.note(match_page,"Maps selected by the server for your current match.","The remaining player count decides which selected map comes next.")
	var actions = Kit.row(rated_page)
	query = Kit.field(menu,actions,"","Find a level or creator",self,"_filter")
	query.clear_button_enabled = true
	query.hint_tooltip = "Search the loaded results."
	ui.choice(actions,["All time","Today","This week","This month"],0,self,"_period")
	var refresh = Kit.action(menu,actions,"Refresh","redo",self,"_request")
	refresh.hint_tooltip = "Uses the existing five-minute server cache."
	status = ui.note(content,"")
	list = Kit.column(content,10)
	module._maps_list = list
	module._subtitle_label = status
	module._rating_buttons = []
	for i in 2: tabs._buttons[i].connect("pressed",self,"_mode",[i==1])
	tabs.finish()

func open(key):
	tabs.select(1 if key=="rated" else 0,false)
	_mode(key=="rated")

func _mode(rated):
	rating_rows.clear()
	module.set_catalog_mode(rated)
	if rated: module._show_top_rated(module._rating_period)
	else: module._render_maps()

func _period(index):
	module._show_top_rated([0,3,2,1][index])

func _request():
	module._show_top_rated(module._rating_period)

func _filter(text):
	var term = text.strip_edges().to_lower()
	for item in rating_rows:
		if is_instance_valid(item[0]): item[0].visible = term.empty() or term in item[1]

func map_row(entry,index,current,recorded):
	var color_key = "warning" if entry.get("mode","")=="Knockout" else "success"
	var card = ui.card(list,"","",color_key)
	var panel = card.get_parent()
	list.remove_child(panel)
	var line = Kit.row(card)
	ui.badge(line,str(index+1),color_key)
	var info = Kit.column(line,4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title = menu.label(str(entry.get("name","Unknown map")),18,Galaxy.color("ink"))
	title.autowrap = true
	info.add_child(title)
	var details = str(entry.get("author",""))
	if not details.empty(): details = "by "+details
	if float(entry.get("rating",0))>0: details += " · ★ %.1f" % float(entry.rating)
	ui.note(info,details)
	ui.badge(line,"Now" if index==current else str(entry.get("mode","Race")),color_key)
	var history = recorded.get(str(entry.get("name","")),{})
	if not history.empty():
		var text = "%d recordings" % history.runs.size()
		if history.get("fastest",-1)>=0: text += " · fastest %.1fs" % history.fastest
		ui.note(card,text)
	if current>=0 and index<current: panel.modulate.a = 0.65
	return panel

func render_ratings(levels):
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	rating_rows.clear()
	status.text = "Server ratings · refreshed at most every 5 minutes" if not levels.empty() else "No levels returned for this period."
	var seen = {}
	for entry in levels:
		if not entry is Dictionary or str(entry.get("id","")).empty() or seen.has(entry.id): continue
		seen[entry.id] = true
		var card = ui.card(list,"")
		var line = Kit.row(card)
		var info = Kit.column(line,4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name = str(entry.get("name",entry.get("level_name","Untitled level")))
		var author = str(entry.get("author_name",entry.get("author",entry.get("username","Unknown creator"))))
		var title = menu.label(name,18,Galaxy.color("ink"))
		title.autowrap = true
		info.add_child(title)
		ui.note(info,"by "+author)
		if entry.has("update_time"):
			title.hint_tooltip = "Updated: "+str(entry.update_time)
			title.mouse_filter = Control.MOUSE_FILTER_PASS
		if str(entry.get("published",""))=="Curated": ui.badge(line,"Curated","success")
		var count = int(entry.get("rating_count",0))
		var rating = float(entry.get("rating",entry.get("average_rating",0)))
		ui.note(card,"★ %.2f · %d ratings%s" % [rating,count," · small sample" if count<10 else ""])
		Kit.action(menu,line,"Open level","play",self,"_open_level",[str(entry.id),entry])
		rating_rows.append([card.get_parent(),(name+" "+author).to_lower()])
	_filter(query.text)

func _open_level(id,data):
	var scene = module.get_tree().current_scene
	var playground = scene.find_node("PLAYGROUND",true,false) if scene!=null else null
	if playground!=null and playground.has_method("on_level_selected"):
		menu.tas_tool._set_menu_open(false)
	module._open_rated_level(id,data)
