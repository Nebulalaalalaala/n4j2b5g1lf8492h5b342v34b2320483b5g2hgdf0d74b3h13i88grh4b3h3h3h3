extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const Layout = preload("user://mod/core/workspace4/PageLayout.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Runtime = preload("user://mod/core/workspace4/EffectRuntime.gd")
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
const History = preload("user://mod/core/workspace4/effects/EffectHistory.gd")
const Scene = preload("user://mod/core/workspace4/effects/EffectScene.gd")
const Graph = preload("user://mod/core/workspace4/effects/EffectGraph.gd")
const Tile = preload("user://mod/core/workspace4/effects/EffectPresetTile.gd")
const OldPage = preload("user://mod/core/workspace4/pages/EffectsPage.gd")
const DRAFT = "user://goobplayability/effect-studio/draft.json"
var menu
var runtime
var ui
var tabs
var inspector_tabs
var effect = {}
var history = History.new()
var selected = 0
var name_field
var undo_button
var redo_button
var layer_list
var add_buttons = []
var duplicate_button
var remove_button
var up_button
var down_button
var stage
var mover
var preview
var avatar
var status
var saved_list
var saved_filter = ""
var color_graph
var curve_graph
var color_button
var curve_kind = "size_curve"
var playing = true
var preview_time = 0.0
var dirty_at = 0
var paused_button
var number_labels = {}
var sharing_toggle
var sharing_status
var sharing_elapsed = 0.0

func build(owner,content,service):
	menu = owner
	runtime = service
	ui = Layout.new(menu)
	effect = Document.clean(Kit.read_json(DRAFT,{}))
	if effect.empty(): effect = Document.clean(runtime.worn)
	if effect.empty(): effect = Document.clean(Document.presets()["Arctic Fox"])
	history.reset(effect)
	var toolbar = Kit.column(content,8)
	name_field = Kit.field(menu,toolbar,str(effect.name),"Effect name",self,"_name")
	var actions = Kit.row(toolbar)
	Kit.action(menu,actions,"Save","save",self,"_save",[],true)
	Kit.action(menu,actions,"Wear","check",self,"_wear")
	Kit.action(menu,actions,"Take off","close",self,"_take_off")
	actions.add_child(menu._spacer())
	undo_button = Kit.action(menu,actions,"","undo",self,"_undo")
	undo_button.hint_tooltip = "Undo · Ctrl+Z"
	redo_button = Kit.action(menu,actions,"","redo",self,"_redo")
	redo_button.hint_tooltip = "Redo · Ctrl+Y"
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("effects",menu.font(15))
	var design = tabs.add_tab("Design","effects")
	var presets = tabs.add_tab("Presets","star")
	var saved = tabs.add_tab("Saved","folder")
	_build_design(design)
	_build_presets(presets)
	_build_saved(saved)
	status = ui.note(content,"")
	tabs.finish()
	_rebuild_layers()
	_build_inspector()
	_update_preview()
	_list_saved()
	_sync_history()
	var timer = Timer.new()
	timer.wait_time = 1.0/30.0
	timer.pause_mode = Node.PAUSE_MODE_PROCESS
	content.add_child(timer)
	timer.connect("timeout",self,"_move")
	timer.start()
	var shortcuts = load("user://mod/core/workspace4/effects/EffectShortcuts.gd").new()
	shortcuts.editor = self
	content.add_child(shortcuts)
	runtime.connect("changed",self,"refresh")
	content.connect("tree_exiting",self,"_closed")
	call_deferred("_make_avatar")

func _closed():
	if is_instance_valid(runtime) and runtime.is_connected("changed",self,"refresh"):
		runtime.disconnect("changed",self,"refresh")

func _build_design(parent):
	var body = ui.grid(parent,310)
	var left = ui.card(body,"Preview","eye")
	stage = Panel.new()
	stage.rect_min_size = Vector2(250,230)
	stage.rect_clip_content = true
	stage.add_stylebox_override("panel",Galaxy.box(Galaxy.color("raised"),Galaxy.color("border"),0,12))
	left.add_child(stage)
	mover = Node2D.new()
	mover.z_index = 10
	stage.add_child(mover)
	preview = Scene.new()
	mover.add_child(preview)
	var controls = Kit.row(left)
	paused_button = Kit.action(menu,controls,"Pause","pause",self,"_pause")
	Kit.action(menu,controls,"Reset","rewind",self,"_reset_preview")
	Kit.action(menu,controls,"Avatar Studio","avatar",menu,"select",["sandbox"])
	var attach = Kit.action(menu,left,"Link effect to current Look","link",self,"_link_outfit")
	attach.hint_tooltip = "Wear this effect and include it when you save or update your Avatar Studio Look."
	left.add_child(menu.label("Layers",17,Galaxy.color("ink")))
	layer_list = ItemList.new()
	layer_list.rect_min_size.y = 150
	layer_list.add_font_override("font",menu.font(15))
	layer_list.add_stylebox_override("bg",Galaxy.box(Galaxy.color("raised"),Galaxy.color("border"),6))
	layer_list.add_color_override("font_color",Galaxy.color("ink"))
	layer_list.add_color_override("font_color_selected",Galaxy.color("ink"))
	layer_list.hint_tooltip = "Layers draw from back to front. Select one to edit it."
	layer_list.connect("item_selected",self,"_select_layer")
	left.add_child(layer_list)
	var add = Kit.row(left)
	add_buttons.append(Kit.action(menu,add,"Trail","plus",self,"_add",["trail"]))
	add_buttons.append(Kit.action(menu,add,"Emitter","plus",self,"_add",["emitter"]))
	var tools = ui.grid(left,100)
	up_button = Kit.action(menu,tools,"Up","stepback",self,"_reorder",[-1])
	down_button = Kit.action(menu,tools,"Down","step",self,"_reorder",[1])
	duplicate_button = Kit.action(menu,tools,"Duplicate","copy",self,"_duplicate")
	remove_button = Kit.action(menu,tools,"Remove","trash",self,"_remove")
	var right = ui.card(body,"Layer properties","settings")
	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(250,500)
	scroll.scroll_horizontal_enabled = false
	right.add_child(scroll)
	inspector_tabs = PageTabs.new()
	inspector_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector_tabs)
	inspector_tabs.setup("effect-layer",menu.font(14))
	inspector_tabs.add_tab("Shape","box")
	inspector_tabs.add_tab("Colour","palette")
	inspector_tabs.add_tab("Curves","trajectory")
	inspector_tabs.finish()

func _build_inspector():
	for page in inspector_tabs._pages:
		for child in page.get_children():
			page.remove_child(child)
			child.queue_free()
	number_labels.clear()
	var layer = effect.layers[selected]
	var shape = inspector_tabs._pages[0]
	Kit.field(menu,shape,layer.name,"Layer name",self,"_layer_name")
	var enabled = CheckButton.new()
	enabled.text = "Visible"
	enabled.pressed = layer.enabled
	enabled.add_font_override("font",menu.font(15))
	enabled.connect("toggled",self,"_set",["enabled"])
	shape.add_child(enabled)
	ui.choice(shape,["Additive glow","Normal blend"],0 if layer.blend=="add" else 1,self,"_blend")
	_number(shape,"Opacity","opacity",0,1,0.01)
	if layer.type=="trail": _number(shape,"Width","width",1,40,0.5)
	else:
		ui.choice(shape,["Soft dot","Star","Diamond"],Document.SHAPES.find(layer.shape),self,"_shape")
		for spec in [["Size","size",1,64,0.5],["Particles","amount",4,160,1],["Speed","speed",0,200,1],["Spread","spread",0,360,1]]: _number(shape,spec[0],spec[1],spec[2],spec[3],spec[4])
	_number(shape,"Lifetime","lifetime",0.1,3,0.05)
	if layer.type=="emitter":
		_number(shape,"Gravity X","gravity_x",-150,150,1)
		_number(shape,"Gravity Y","gravity_y",-150,150,1)
		_number(shape,"Rotation","rotation",-360,360,1)
	_number(shape,"Offset X","offset_x",-100,100,1)
	_number(shape,"Offset Y","offset_y",-100,100,1)
	var color = inspector_tabs._pages[1]
	ui.choice(color,["Custom gradient","Goober colour"],1 if layer.color_mode=="goober" else 0,self,"_color_mode")
	color_graph = Graph.new()
	color_graph.font = menu.font(12)
	color_graph.set_points(layer.gradient,"gradient")
	color_graph.connect("edited",self,"_graph",["gradient"])
	color_graph.connect("selection_changed",self,"_stop_selected")
	color.add_child(color_graph)
	var row = Kit.row(color)
	row.add_child(menu.label("Selected stop",14,Galaxy.color("muted")))
	color_button = Kit.color_button(row,Document.color(layer.gradient[0].color),self,"_stop_color")
	color_button.edit_alpha = true
	ui.note(color,"Click the bar to add · drag a stop to move it")
	var curves = inspector_tabs._pages[2]
	ui.choice(curves,["Size / width","Opacity"],0 if curve_kind=="size_curve" else 1,self,"_curve_kind")
	curve_graph = Graph.new()
	curve_graph.font = menu.font(12)
	curve_graph.set_points(layer[curve_kind])
	curve_graph.connect("edited",self,"_curve_graph")
	curves.add_child(curve_graph)
	ui.note(curves,"Particle age →", "Double-click to add a point; drag to shape. Endpoints stay at age 0 and 1.")
	var presets = ui.grid(curves,100)
	for spec in [["Fade",[{"t":0.0,"v":1.0},{"t":1.0,"v":0.0}]],["Hold",[{"t":0.0,"v":1.0},{"t":1.0,"v":1.0}]],["Pulse",[{"t":0.0,"v":0.1},{"t":0.3,"v":1.0},{"t":1.0,"v":0.0}]]]:
		Kit.action(menu,presets,spec[0],"",self,"_curve_preset",[spec[1]])

func _number(parent,title,key,low,high,step):
	var row = Kit.row(parent)
	row.add_child(menu.label(title,14,Galaxy.color("muted")))
	row.add_child(menu._spacer())
	var value = menu.label(_value_text(effect.layers[selected][key]),14,Galaxy.color("ink"))
	row.add_child(value)
	number_labels[key] = value
	var slider = Kit.slider(parent,low,high,step,float(effect.layers[selected][key]),null,"")
	slider.connect("value_changed",self,"_number_changed",[key])
	slider.connect("drag_ended",self,"_end_gesture")

func _build_presets(parent):
	var grid = ui.grid(parent,190)
	var presets = Document.presets()
	for name in presets:
		var card = ui.card(grid,"")
		var tile = Tile.new()
		tile.document = Document.clean(presets[name])
		card.add_child(tile)
		Kit.action(menu,card,name,"",self,"_preset",[name])

func _build_saved(parent):
	Kit.field(menu,parent,"","Find a saved effect",self,"_search_saved")
	saved_list = ItemList.new()
	saved_list.rect_min_size.y = 280
	saved_list.add_font_override("font",menu.font(15))
	saved_list.add_stylebox_override("bg",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),8))
	saved_list.add_color_override("font_color",Galaxy.color("ink"))
	saved_list.add_color_override("font_color_selected",Galaxy.color("ink"))
	saved_list.connect("item_activated",self,"_open_saved")
	parent.add_child(saved_list)
	var actions = Kit.row(parent)
	Kit.action(menu,actions,"Open","folder",self,"_open_selected")
	Kit.action(menu,actions,"Refresh","redo",self,"_list_saved")
	Kit.action(menu,actions,"Workshop","workshop",menu,"select",["workshop"])

func _build_sharing(parent):
	var card = ui.card(parent,"Visibility","user")
	sharing_toggle = CheckButton.new()
	sharing_toggle.text = "Share my worn effect"
	sharing_toggle.pressed = bool(SavedSettings.get_value("custom_effects_sharing",false))
	sharing_toggle.add_font_override("font",menu.font(15))
	sharing_toggle.hint_tooltip = "Sends the worn visual effect through the existing public-avatar channel. Updated Goobplayability clients can show it. Nicknames and account names are not sent."
	sharing_toggle.connect("toggled",runtime,"set_sharing")
	card.add_child(sharing_toggle)
	ui.note(card,"Visible to updated Goobplayability clients · sync can take a minute")
	sharing_status = ui.note(card,"")
	var quality = ui.card(parent,"Other players’ effects","effects")
	ui.choice(quality,["Balanced","Reduced","Hidden"],["balanced","reduced","off"].find(str(SavedSettings.get_value("remote_effects_quality","balanced"))),self,"_remote_quality")
	ui.note(quality,"Rendering is limited to eight nearby players.","Remote documents and particle counts are bounded. This setting changes cosmetic rendering only.")
	var identities = ui.card(parent,"Player indicators","user")
	for spec in [["client_identity_labels","Goobplayability logo & role icons"],["client_name_gradients","Access-tier name gradients"]]:
		var check = CheckButton.new()
		check.text = spec[1]
		check.pressed = bool(SavedSettings.get_value(spec[0],true))
		check.add_font_override("font",menu.font(15))
		check.hint_tooltip = "Labels come from Journey's admin-awarded SQL badges. Actual account names and permissions are unchanged."
		check.connect("toggled",self,"_identity_option",[spec[0]])
		identities.add_child(check)
	Kit.action(menu,parent,"Avatar Studio","avatar",menu,"select",["sandbox"])

func _make_avatar():
	var tools = menu.tas_tool.get("_game_tools")
	if is_instance_valid(tools) and is_instance_valid(tools._match_themes):
		avatar = tools._match_themes.make_goober()
		if is_instance_valid(avatar):
			mover.add_child(avatar)
			avatar.scale = Vector2.ONE*0.018
			tools._match_themes.dress_goober(avatar)
	if not is_instance_valid(avatar):
		var art = Sprite.new()
		art.texture = Galaxy.texture("fox-head.png")
		art.scale = Vector2.ONE*(38.0/max(1.0,art.texture.get_width()))
		mover.add_child(art)
		avatar = art

func _move():
	sharing_elapsed+=1.0/30.0
	if sharing_elapsed>=1.0 and is_instance_valid(sharing_status) and sharing_status.is_visible_in_tree():
		sharing_elapsed = 0.0
		_refresh_sharing()
	if dirty_at>0 and OS.get_ticks_msec()-dirty_at>700:
		Kit.write_json(DRAFT,Document.export_data(effect))
		dirty_at = 0
	if not stage.is_visible_in_tree(): return
	if playing: preview_time+=1.0/30.0
	mover.position = Vector2(stage.rect_size.x*0.5+cos(preview_time*1.3)*stage.rect_size.x*0.3,stage.rect_size.y*0.52+sin(preview_time*2.6)*stage.rect_size.y*0.19)
	preview.modulate.a = 1.0

func _pause():
	playing = not playing
	paused_button.text = "Pause" if playing else "Play"
func _reset_preview():
	preview_time = 0
	preview.clear_trails()

func _body_color():
	var sandbox = menu.tas_tool.get("_cosmetic_sandbox")
	return sandbox.custom_color if is_instance_valid(sandbox) and sandbox.custom_color_enabled else Color("7cc4ff")
func _update_preview(): preview.configure(effect,_body_color())
func _value_text(value): return str(int(value)) if is_equal_approx(float(value),round(float(value))) else "%.2f" % float(value)

func _changed(gesture = "", rebuild = false):
	effect = Document.clean(effect)
	history.commit(effect,gesture)
	dirty_at = OS.get_ticks_msec()
	_update_preview()
	_sync_history()
	if rebuild:
		_rebuild_layers()
		_build_inspector()

func _name(text):
	effect.name = Document.title(text,"My effect")
	_changed("name")
func _layer_name(text):
	effect.layers[selected].name = Document.title(text,"Layer")
	_changed("layer-name")
	_rebuild_layers()
func _set(value,key):
	effect.layers[selected][key] = value
	_changed()
	_rebuild_layers()
func _number_changed(value,key):
	effect.layers[selected][key] = value
	number_labels[key].text = _value_text(value)
	_changed("number:"+key)
func _end_gesture(_changed): history.end_gesture()
func _blend(index): _set("add" if index==0 else "mix","blend")
func _shape(index): _set(Document.SHAPES[index],"shape")
func _color_mode(index): _set("goober" if index==1 else "gradient","color_mode")
func _remote_quality(index): SavedSettings.set_value("remote_effects_quality",["balanced","reduced","off"][index])
func _identity_option(value,key): SavedSettings.set_value(key,value)

func _graph(points,finished,key):
	effect.layers[selected][key] = points
	_changed("graph:"+key)
	if key=="gradient": _stop_selected(int(clamp(color_graph.selected,0,effect.layers[selected].gradient.size()-1)))
	if finished: history.end_gesture()
func _curve_graph(points,finished): _graph(points,finished,curve_kind)
func _curve_kind(index):
	curve_kind = "size_curve" if index==0 else "alpha_curve"
	curve_graph.set_points(effect.layers[selected][curve_kind])
func _curve_preset(points):
	effect.layers[selected][curve_kind] = points.duplicate(true)
	_changed()
	curve_graph.set_points(points)
func _stop_selected(index): color_button.color = Document.color(effect.layers[selected].gradient[index].color)
func _stop_color(color):
	var index = int(clamp(color_graph.selected,0,effect.layers[selected].gradient.size()-1))
	effect.layers[selected].gradient[index].color = Document.color_hex(color)
	color_graph.set_points(effect.layers[selected].gradient,"gradient")
	_changed("stop-color")

func _select_layer(index):
	selected = index
	history.end_gesture()
	_build_inspector()
func _add(kind):
	if effect.layers.size()>=Document.MAX_LAYERS: return
	effect.layers.append(Document.layer(kind,"layer-"+str(OS.get_ticks_usec())))
	selected = effect.layers.size()-1
	_changed("",true)
func _duplicate():
	if effect.layers.size()>=Document.MAX_LAYERS: return
	var copy = effect.layers[selected].duplicate(true)
	copy.id = "layer-"+str(OS.get_ticks_usec())
	copy.name = Document.title(copy.name+" copy")
	effect.layers.insert(selected+1,copy)
	selected+=1
	_changed("",true)
func _remove():
	if effect.layers.size()<=1: return
	effect.layers.remove(selected)
	selected = min(selected,effect.layers.size()-1)
	_changed("",true)
func _reorder(direction):
	var next = selected+direction
	if next<0 or next>=effect.layers.size(): return
	var value = effect.layers[selected]
	effect.layers.remove(selected)
	effect.layers.insert(next,value)
	selected = next
	_changed("",true)
func _rebuild_layers():
	layer_list.clear()
	for layer in effect.layers:
		layer_list.add_item(("" if layer.enabled else "Hidden · ")+str(layer.name),Galaxy.icon("route" if layer.type=="trail" else "effects",Galaxy.color("accent"),18))
	layer_list.select(selected)
	for button in add_buttons: button.disabled = effect.layers.size()>=Document.MAX_LAYERS
	duplicate_button.disabled = effect.layers.size()>=Document.MAX_LAYERS
	remove_button.disabled = effect.layers.size()<=1
	up_button.disabled = selected==0
	down_button.disabled = selected==effect.layers.size()-1
func _sync_history():
	undo_button.disabled = history.past.empty()
	redo_button.disabled = history.future.empty()
func _restore(value):
	effect = value.duplicate(true)
	selected = min(selected,effect.layers.size()-1)
	name_field.text = effect.name
	_rebuild_layers()
	_build_inspector()
	_update_preview()
	_sync_history()
	dirty_at = OS.get_ticks_msec()
func _undo(): _restore(history.undo())
func _redo(): _restore(history.redo())
func _preset(name):
	effect = Document.clean(Document.presets()[name])
	selected = 0
	_changed("",true)
	name_field.text = effect.name
	tabs.select(0)

func _save():
	var ok = Kit.write_json(Runtime.DIR+OldPage.file_name(effect.name),Document.export_data(effect))
	status.text = "Saved “%s”." % effect.name if ok else "Could not save this effect."
	_list_saved()
func _wear(): status.text = "Wearing “%s”." % effect.name if runtime.wear(effect) else "Could not wear this effect."
func _link_outfit():
	var sandbox = menu.tas_tool.get("_cosmetic_sandbox")
	if not is_instance_valid(sandbox) or not is_instance_valid(sandbox._studio):
		status.text = "Open Avatar Studio once, then link the effect to your Look."
		return
	if not runtime.wear(effect):
		status.text = "Could not save the effect."
		return
	load("user://mod/core/workspace4/effects/StudioEffectBridge.gd").link(sandbox._studio)
	status.text = "Linked to your current Look. Save or update the Look in Avatar Studio."
func _take_off(): status.text = "Effect taken off." if runtime.take_off() else "Could not save that change."
func _search_saved(text):
	saved_filter = text.strip_edges().to_lower()
	_list_saved()
func _list_saved():
	saved_list.clear()
	var dir = Directory.new()
	if dir.open(Runtime.DIR)!=OK: return
	var names = []
	dir.list_dir_begin(true,true)
	var name = dir.get_next()
	while not name.empty():
		if name.ends_with(".json") and name!="worn.json": names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for file in names:
		if not saved_filter.empty() and not saved_filter in file.to_lower(): continue
		saved_list.add_item(file.get_basename())
		saved_list.set_item_metadata(saved_list.get_item_count()-1,Runtime.DIR+file)
func _open_selected():
	var selected = saved_list.get_selected_items()
	if not selected.empty(): _open_saved(selected[0])
func _open_saved(index):
	var path = str(saved_list.get_item_metadata(index))
	var file = File.new()
	if file.open(path,File.READ)!=OK: return
	if file.get_len()>Document.MAX_BYTES:
		file.close()
		status.text = "That effect file is too large."
		return
	file.close()
	var loaded = Document.clean(Kit.read_json(path,{}))
	if loaded.empty():
		status.text = "That effect file is unsupported or damaged."
		return
	effect = loaded
	selected = 0
	_changed("",true)
	name_field.text = effect.name
	tabs.select(0)
func refresh():
	if sharing_toggle!=null: sharing_toggle.set_pressed_no_signal(bool(SavedSettings.get_value("custom_effects_sharing",false)))
	_refresh_sharing()

func _refresh_sharing():
	if not is_instance_valid(sharing_status): return
	sharing_status.text = ""
	if not bool(SavedSettings.get_value("custom_effects_sharing",false)): return
	for presence in menu.get_tree().get_nodes_in_group("goob_public_avatars"):
		if not is_instance_valid(presence) or presence.transport==null: continue
		var labels = {"idle":"Waiting for your game profile…","ready":"Sharing connected","schema_missing":"Sharing is unavailable on this server.","write_key_rejected":"This profile’s sharing key was rejected. Contact the administrator.","key_save_failed":"Could not save the sharing key on this PC.","retrying":"Sharing connection interrupted · retrying"}
		sharing_status.text = presence.publication_note if not presence.publication_note.empty() else str(labels.get(presence.transport.status,"Connecting…"))
		return
	sharing_status.text = "Sharing will connect after the client restarts."
