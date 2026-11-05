extends VBoxContainer
const Players=preload("user://mod/tools/clips/ClipPlayers.gd")
const Kit=preload("user://mod/core/workspace4/Kit.gd")
const Galaxy=preload("user://mod/core/workspace4/Galaxy.gd")
var menu
var service
var rows
var search_panel
var query
var results
var status
var candidates=[]
var matches=[]
var debounce: Timer
var player_signature=""

func build(owner,recorder):
	menu=owner
	service=recorder
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_constant_override("separation",8)
	var line=Kit.row(self)
	var title=menu.label("Selected players",17,Galaxy.color("ink"))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	line.add_child(title)
	Kit.action(menu,line,"Add player","plus",self,"open_search")
	rows=Kit.column(self,6)
	search_panel=Kit.column(self,8)
	var input_row=Kit.row(search_panel)
	query=Kit.field(menu,input_row,"","Search match players or saved Wins…",self,"_typed")
	Kit.action(menu,input_row,"Refresh","redo",self,"open_search")
	Kit.action(menu,input_row,"Close","close",search_panel,"hide")
	results=ItemList.new()
	results.rect_min_size.y=180
	results.add_font_override("font",menu.font(15))
	results.add_color_override("font_color",Galaxy.color("ink"))
	results.add_stylebox_override("bg",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),8,8))
	for state in ["selected","selected_focus"]: results.add_stylebox_override(state,Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),6,6))
	results.connect("item_selected",self,"_add")
	search_panel.add_child(results)
	status=menu.label("",13,Galaxy.color("muted"))
	status.autowrap=true
	search_panel.add_child(status)
	debounce=Timer.new()
	debounce.one_shot=true
	debounce.wait_time=0.12
	debounce.connect("timeout",self,"_search")
	add_child(debounce)
	search_panel.hide()
	service.connect("settings_changed",self,"refresh")
	refresh()

func open_search():
	candidates=Players.candidates(service.tool)
	search_panel.show()
	query.grab_focus()
	_search()

func _typed(_text): debounce.start()

func _search():
	results.clear()
	matches=[]
	var selected={}
	for row in service.settings.watched_players: selected[row.id]=true
	var available=[]
	for row in candidates:
		if not selected.has(row.id): available.append(row)
	matches=Players.search(available,query.text)
	for row in matches: results.add_item(str(row.name)+"  ·  "+str(row.id).left(8))
	status.text="Choose a player. Adding one turns on Automatic highlights." if not matches.empty() else "No match in current players or saved Wins."
	if service.settings.watched_players.size()>=100: status.text="100 players selected. Remove one before adding another."

func _add(index):
	if index<0 or index>=matches.size() or service.settings.watched_players.size()>=100: return
	var selected=service.settings.watched_players.duplicate(true)
	selected.append(matches[index].duplicate())
	service.set_option("watched_players",Players.clean(selected))
	service.set_option("highlights",true)
	query.clear()
	_search()

func _remove(id):
	var selected=[]
	for row in service.settings.watched_players:
		if row.id!=id: selected.append(row)
	service.set_option("watched_players",selected)
	if search_panel.visible: _search()

func refresh():
	var signature=JSON.print(service.settings.watched_players)
	if signature==player_signature: return
	player_signature=signature
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if service.settings.watched_players.empty():
		var empty=menu.label("Keep any confirmed dash kill against a selected player.",14,Galaxy.color("muted"))
		empty.autowrap=true
		rows.add_child(empty)
	for entry in service.settings.watched_players:
		var line=Kit.row(rows)
		var name_label=menu.label(str(entry.name),15,Galaxy.color("ink"))
		name_label.autowrap=true
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		name_label.hint_tooltip=str(entry.id)
		line.add_child(name_label)
		Kit.action(menu,line,"Remove","trash",self,"_remove",[entry.id])
