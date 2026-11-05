extends Reference
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const Kit=preload("user://mod/core/workspace4/Kit.gd")
const Galaxy=preload("user://mod/core/workspace4/Galaxy.gd")
var editor
var host
var tabs: TabContainer
var item={}
var source_status: Label
var camera_picker: OptionButton
var session_picker: OptionButton
var playlist: ItemList
var updating=false
var media_buttons={}
var seek: HSlider
var seek_dragging=false
var keyboard_presets=[]

func setup(owner_editor, parent: Control):
	editor=owner_editor
	host=parent
	editor.output.sources.connect("changed",self,"_source_changed")

func refresh():
	if host==null: return
	var selected_tab=tabs.current_tab if tabs!=null and is_instance_valid(tabs) else 0
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	source_status=null
	media_buttons.clear()
	seek=null
	camera_picker=null
	session_picker=null
	playlist=null
	item=editor.canvas.find_item(editor.canvas.selection[0]) if editor.canvas.selection.size()==1 else {}
	var title=editor.menu.label(str(item.get("name","Layout")) if not item.empty() else (str(editor.canvas.selection.size())+" selected" if editor.canvas.selection.size()>1 else "Layout"),17,Galaxy.color("ink"))
	title.clip_text=true
	host.add_child(title)
	if item.get("type")=="game" and item.source.get("presentation","Card")=="Plain text":
		Kit.action(editor.menu,host,"Use level card","gamepad",self,"_game_preset")
	tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	editor._style_tabs(tabs)
	host.add_child(tabs)
	if not item.empty():
		var style=_tab("Style")
		_style(style)
		var source=_tab("Source")
		_source(source)
	var layout=_tab("Layout")
	_layout(layout)
	if not item.empty(): tabs.current_tab=min(selected_tab,2)
	_source_changed()

func _tab(name: String):
	var scroll=editor._scroll(tabs,name)
	var content=Kit.column(scroll,9)
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return content

func _heading(parent: Control, text: String):
	var label=editor.menu.label(text,13,Galaxy.color("accent"))
	parent.add_child(label)

func _label(parent: Control, text: String) -> HBoxContainer:
	var row=Kit.row(parent,6)
	var label=editor.menu.label(text,13,Galaxy.color("muted"))
	label.rect_min_size.x=84
	row.add_child(label)
	return row

func _field(parent: Control, label: String, value: String, path: Array):
	var row=_label(parent,label)
	var field=Kit.field(editor.menu,row,value,"",null,"")
	field.rect_min_size.x=100
	field.connect("text_changed",editor,"edit_property",[path])
	return field

func _number(parent: Control, label: String, value: float, low: float, high: float, step: float, path: Array, factor=1.0):
	var row=_label(parent,label)
	var spin=SpinBox.new()
	spin.min_value=low
	spin.max_value=high
	spin.step=step
	spin.value=value*factor
	spin.rect_min_size=Vector2(100,32)
	spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	spin.get_line_edit().add_font_override("font",editor.menu.font(14))
	spin.get_line_edit().add_color_override("font_color",Galaxy.color("ink"))
	spin.get_line_edit().add_color_override("cursor_color",Galaxy.color("accent"))
	spin.get_line_edit().add_stylebox_override("normal",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),8,8))
	spin.get_line_edit().add_stylebox_override("focus",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),8,8))
	spin.connect("value_changed",self,"_number_changed",[path,factor])
	row.add_child(spin)
	return spin
func _number_changed(value: float, path: Array, factor: float): editor.edit_property(value/factor,path)

func _toggle(parent: Control, text: String, value: bool, path: Array):
	var control=Kit.action(editor.menu,parent,text,"check" if value else "",self,"_toggled",[path])
	control.toggle_mode=true
	control.pressed=value
	control.hint_tooltip="Click to "+("disable" if value else "enable")+"."
	return control
func _toggled(path: Array):
	var target=editor.document if path[0]=="layout" else item
	for i in range(1,path.size()): target=target[path[i]]
	editor.edit_property(not target,path)
	editor.checkpoint()
	refresh()

func _choice(parent: Control, label: String, choices: Array, value: String, path: Array):
	parent.add_child(editor.menu.label(label,13,Galaxy.color("muted")))
	var picker=OptionButton.new()
	editor._style_option(picker)
	picker.rect_min_size.y=32
	for name in choices:
		var option_label=str(name)
		if path.back()=="mode": option_label={"system":"Windows media","local":"Local audio"}.get(option_label,option_label)
		elif path.back()=="scale_mode": option_label="Follow game screen" if option_label=="screen" else "Fixed aspect ratio"
		elif path.back()=="field": option_label={"level":"Level name","players":"Player count","location":"Location"}.get(option_label,option_label)
		elif path.back()=="action": option_label={"":"Raw key","player_left":"Left","player_right":"Right","player_up":"Jump","player_dash":"Dash"}.get(option_label,option_label)
		elif path.back()=="repeat": option_label={"off":"Off","one":"Repeat track","all":"Repeat playlist"}.get(option_label,option_label)
		picker.add_item(option_label)
		picker.set_item_metadata(picker.get_item_count()-1,str(name))
		if str(name)==value: picker.select(picker.get_item_count()-1)
	picker.connect("item_selected",self,"_choice_changed",[picker,path])
	parent.add_child(picker)
	return picker
func _choice_changed(index: int, picker: OptionButton, path: Array):
	editor.edit_property(str(picker.get_item_metadata(index)),path)
	if item.get("type")=="media":
		if path.has("mode"): editor.output.sources.set_playlist(item.source)
		if path.has("preset"):
			var size={"Compact":Vector2(430,124),"Minimal":Vector2(360,52),"Expanded":Vector2(470,220),"Artwork Focus":Vector2(320,400),"Floating Pop-out":Vector2(450,200)}.get(item.source.preset,Vector2(430,124))
			item.w=size.x/editor.document.width
			item.h=size.y/editor.document.height
			editor.canvas.place()
	editor.checkpoint()
	refresh()

func _color(parent: Control, label: String, value: String, path: Array):
	var button=Kit.color_button(_label(parent,label),Color(value),null,"")
	button.connect("color_changed",self,"_color_changed",[path])
	for state in ["normal","hover","pressed","disabled"]: button.add_stylebox_override(state,Galaxy.box(Color(value),Galaxy.color("line"),8,6))
	button.add_stylebox_override("focus",StyleBoxEmpty.new())
func _color_changed(color: Color, path: Array): editor.edit_property(color.to_html(false),path)

func _style(parent: Control):
	_field(parent,"Name",item.name,["widget","name"])
	_heading(parent,"POSITION & SIZE")
	for spec in [["X","x",editor.document.width],["Y","y",editor.document.height],["Width","w",editor.document.width],["Height","h",editor.document.height]]:
		_number(parent,spec[0],item[spec[1]],8 if spec[1] in ["w","h"] else -8000,16000,1,["widget",spec[1]],spec[2])
	_number(parent,"Rotation",item.rotation,-360,360,1,["widget","rotation"])
	_number(parent,"Opacity",item.opacity,0,100,1,["widget","opacity"],100)
	_heading(parent,"APPEARANCE")
	_color(parent,"Text",item.color,["widget","color"])
	_color(parent,"Accent",item.accent,["widget","accent"])
	_color(parent,"Background",item.background,["widget","background"])
	_number(parent,"Fill opacity",item.background_opacity,0,100,1,["widget","background_opacity"],100)
	_number(parent,"Corners",item.radius,0,120,1,["widget","radius"])
	_number(parent,"Padding",item.padding,0,100,1,["widget","padding"])
	_toggle(parent,"Border",item.border,["widget","border"])
	if item.border:
		_color(parent,"Border",item.border_color,["widget","border_color"])
		_number(parent,"Line width",item.border_width,0,16,1,["widget","border_width"])
	_toggle(parent,"Shadow",item.shadow,["widget","shadow"])
	_choice(parent,"Font",Doc.FONT_NAMES,item.font,["widget","font"])
	_number(parent,"Text size",item.font_size,8,320,1,["widget","font_size"])
	_number(parent,"Text outline",item.get("font_outline",0),0,12,1,["widget","font_outline"])

func _source(parent: Control):
	match item.type:
		"text":
			parent.add_child(editor.menu.label("Text",14,Galaxy.color("muted")))
			var field=TextEdit.new()
			field.text=item.source.text
			field.rect_min_size=Vector2(200,120)
			field.add_font_override("font",editor.menu.font(15))
			field.add_color_override("font_color",Galaxy.color("ink"))
			field.add_stylebox_override("normal",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),8,8))
			field.connect("text_changed",self,"_text",[field])
			parent.add_child(field)
			var picker=_choice(parent,"Alignment",["Left","Center","Right"],["Left","Center","Right"][int(clamp(item.source.align,0,2))],["widget","source","align_label"])
			picker.disconnect("item_selected",self,"_choice_changed")
			picker.connect("item_selected",self,"_text_align")
			_toggle(parent,"Wrap text",item.source.wrap,["widget","source","wrap"])
		"image":
			Kit.action(editor.menu,parent,"Choose image…","folder",editor,"_files",["image"])
			_field(parent,"File",item.source.path,["widget","source","path"])
			_toggle(parent,"Keep aspect ratio",item.source.aspect_lock,["widget","source","aspect_lock"])
			_crop(parent)
		"clock":
			_choice(parent,"Time format",["24h","12h"],item.source.format,["widget","source","format"])
			_toggle(parent,"Show seconds",item.source.seconds,["widget","source","seconds"])
		"fps": _toggle(parent,"Show FPS suffix",item.source.suffix,["widget","source","suffix"])
		"game":
			_choice(parent,"Display",["level","location","players"],item.source.field,["widget","source","field"])
			_choice(parent,"Appearance",["Card","Plain text"],item.source.presentation,["widget","source","presentation"])
			_toggle(parent,"Theme artwork",item.source.artwork,["widget","source","artwork"])
			_toggle(parent,"Creator",item.source.author,["widget","source","author"])
			_toggle(parent,"Details",item.source.details,["widget","source","details"])
			_toggle(parent,"Show outside levels",item.source.show_idle,["widget","source","show_idle"])
			Kit.action(editor.menu,parent,"Use level card","gamepad",self,"_game_preset")
		"keyboard": _keyboard(parent)
		"media": _media(parent)
		"camera": _camera(parent)
func _game_preset():
	if item.get("type")!="game": return
	var defaults=Doc.widget("game",Vector2(editor.document.width,editor.document.height))
	for key in ["w","h","background_opacity","border","shadow","padding","radius"]: item[key]=defaults[key]
	item.source.presentation="Card"
	editor.canvas.refresh_selected()
	editor.checkpoint()
	refresh()

func _text(field: TextEdit): editor.edit_property(field.text,["widget","source","text"])
func _text_align(index: int): editor.edit_property(index,["widget","source","align"])

func _crop(parent: Control):
	_toggle(parent,"Mirror",item.source.mirror,["widget","source","mirror"])
	_heading(parent,"CROP · PERCENT")
	for i in 4:
		_number(parent,["Left","Top","Width","Height"][i],item.source.crop[i],0 if i<2 else 1,99 if i<2 else 100,1,["widget","source","crop",i],100)

func _keyboard(parent: Control):
	keyboard_presets=editor.Library.widget_presets("keyboard")
	var choices=["GooberDash","WASD","Arrows","WASD + Space","WASD + Shift","Custom"]
	for preset in keyboard_presets: choices.append("Saved · "+str(preset.name))
	var picker=_choice(parent,"Layout",choices,item.source.preset,["widget","source","preset"])
	picker.disconnect("item_selected",self,"_choice_changed")
	picker.connect("item_selected",self,"_keyboard_preset",[picker])
	Kit.action(editor.menu,parent,"Finish key layout" if editor.canvas.key_mode else "Edit keys on canvas","keyboard",self,"_key_mode")
	if editor.canvas.key_mode:
		var row=Kit.row(parent,4)
		Kit.action(editor.menu,row,"+ Key","plus",self,"_key_add",[false])
		Kit.action(editor.menu,row,"+ Mouse","plus",self,"_key_add",[true])
		var index=editor.canvas.key_selected
		if index>=0 and index<item.source.keys.size():
			var key=item.source.keys[index]
			_heading(parent,"SELECTED KEY")
			_field(parent,"Label",key.label,["widget","source","keys",index,"label"])
			_choice(parent,"Shape",["rounded","square","circle"],key.shape,["widget","source","keys",index,"shape"])
			if key.kind=="key":
				Kit.action(editor.menu,parent,"Press a key to bind…","keyboard",self,"_key_bind")
				_choice(parent,"Game action",["","player_left","player_right","player_up","player_dash"],key.action,["widget","source","keys",index,"action"])
			else: _number(parent,"Mouse button",key.code,1,5,1,["widget","source","keys",index,"code"])
			Kit.action(editor.menu,parent,"Remove key","trash",self,"_key_remove")
		else: Kit.hint(editor.menu,parent,"Click a key. Drag it or its corner to arrange the layout.")
	Kit.action(editor.menu,parent,"Save keyboard preset","save",self,"_save_keyboard_preset")
	_color(parent,"Idle",item.source.idle,["widget","source","idle"])
	_color(parent,"Pressed",item.source.pressed,["widget","source","pressed"])
	_color(parent,"Key text",item.source.text,["widget","source","text"])
	_toggle(parent,"Press animation",item.source.animate,["widget","source","animate"])
	_toggle(parent,"Rising pressed keys",item.source.rise,["widget","source","rise"])
	_number(parent,"Rise duration",item.source.rise_seconds,0.25,2,0.05,["widget","source","rise_seconds"])
	_number(parent,"Rise distance",item.source.rise_distance,20,400,5,["widget","source","rise_distance"])
	_toggle(parent,"Input counters",item.source.counter,["widget","source","counter"])
func _keyboard_preset(index: int, picker: OptionButton):
	var preset=picker.get_item_text(index)
	item.source.preset=preset
	if index>=6 and index-6<keyboard_presets.size():
		var saved=keyboard_presets[index-6].widget
		for key in ["source","font","font_size","font_outline","color","background","background_opacity","accent","border","border_color","border_width","radius","shadow","padding"]: item[key]=saved[key].duplicate(true) if saved[key] is Dictionary or saved[key] is Array else saved[key]
		item.source.preset=preset
	elif preset!="Custom": item.source.keys=Doc.keys(preset)
	editor.canvas.key_selected=-1
	editor.checkpoint()
	editor.canvas.refresh_selected()
	refresh()
func _save_keyboard_preset():
	editor.message("Keyboard preset saved as “"+str(item.name)+"”." if editor.Library.save_widget(item) else "Could not save the keyboard preset.")
	refresh()
func _key_mode():
	editor.canvas.key_mode=not editor.canvas.key_mode
	editor.canvas.key_selected=-1
	editor.canvas.update()
	refresh()
func _key_add(mouse: bool):
	if item.source.keys.size()>=64: return
	item.source.preset="Custom"
	item.source.keys.append({"id":Doc.uid(),"label":"LMB" if mouse else "Key","action":"","code":1 if mouse else KEY_SPACE,"kind":"mouse" if mouse else "key","shape":"rounded","x":0.1,"y":0.1,"w":0.2,"h":0.35})
	editor.canvas.key_selected=item.source.keys.size()-1
	editor.checkpoint()
	editor.canvas.refresh_selected()
	refresh()
func _key_remove():
	item.source.keys.remove(editor.canvas.key_selected)
	editor.canvas.key_selected=-1
	editor.checkpoint()
	editor.canvas.refresh_selected()
	refresh()
func _key_bind():
	editor.binding=true
	editor.message("Press the key to show. Escape cancels.")
func bind_key(event: InputEventKey):
	if event.scancode==KEY_ESCAPE: return
	var index=editor.canvas.key_selected
	if index<0 or index>=item.source.keys.size(): return
	item.source.keys[index].action=""
	item.source.keys[index].code=event.scancode
	item.source.keys[index].label=OS.get_scancode_string(event.scancode)
	editor.checkpoint()
	editor.canvas.refresh_selected()
	refresh()

func _media(parent: Control):
	_choice(parent,"Source",["system","local"],item.source.mode,["widget","source","mode"])
	if item.source.mode=="system":
		session_picker=OptionButton.new()
		editor._style_option(session_picker)
		session_picker.connect("item_selected",self,"_session")
		parent.add_child(session_picker)
		Kit.action(editor.menu,parent,"Refresh Windows sources","redo",editor.output.sources,"retry")
	else:
		editor.output.sources.set_playlist(item.source)
		Kit.action(editor.menu,parent,"Add audio files…","folder",editor,"_files",["audio"])
		playlist=ItemList.new()
		playlist.rect_min_size=Vector2(200,120)
		playlist.add_font_override("font",editor.menu.font(13))
		playlist.add_color_override("font_color",Galaxy.color("ink"))
		playlist.add_stylebox_override("bg",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),8,8))
		for path in item.source.playlist: playlist.add_item(str(path).get_file())
		playlist.connect("item_activated",self,"_play_track")
		parent.add_child(playlist)
		var row=Kit.row(parent,4)
		Kit.action(editor.menu,row,"Play","play",self,"_play_selected")
		Kit.action(editor.menu,row,"Remove","trash",self,"_remove_track")
		var order=Kit.row(parent,4)
		Kit.action(editor.menu,order,"Move up","",self,"_move_track",[-1])
		Kit.action(editor.menu,order,"Move down","",self,"_move_track",[1])
		_toggle(parent,"Shuffle",item.source.shuffle,["widget","source","shuffle"])
		_choice(parent,"Repeat",["off","one","all"],item.source.repeat,["widget","source","repeat"])
		var volume=_number(parent,"Volume",item.source.volume,0,100,1,["widget","source","volume"],100)
		volume.connect("value_changed",self,"_volume")
	var controls=Kit.row(parent,4)
	for action in [["previous","‹"],["toggle","Play / pause"],["next","›"]]: media_buttons[action[0]]=Kit.action(editor.menu,controls,action[1],"",self,"_control",[action[0]])
	seek=Kit.slider(parent,0,100,0.1,0,null,"")
	seek.hint_tooltip="Seek in the current track. Disabled if the source does not support it."
	seek.connect("drag_started",self,"_seek_start")
	seek.connect("drag_ended",self,"_seek_end")
	source_status=Kit.hint(editor.menu,parent,"")
	_choice(parent,"Player design",["Compact","Minimal","Expanded","Artwork Focus","Floating Pop-out"],item.source.preset,["widget","source","preset"])
	for pair in [["Artwork","artwork"],["Artist","artist"],["Source name","source_icon"],["Progress","progress"],["Playback controls","controls"]]: _toggle(parent,pair[0],item.source[pair[1]],["widget","source",pair[1]])
	_choice(parent,"When stopped",["show","hide"],item.source.when_stopped,["widget","source","when_stopped"])
	_toggle(parent,"Track transition",item.source.transition,["widget","source","transition"])
func _seek_start(): seek_dragging=true
func _seek_end(_changed):
	seek_dragging=false
	editor.output.sources.control("seek",item.source,seek.value)
func _volume(_value): editor.output.sources.set_playlist(item.source)
func _control(action: String): editor.output.sources.control(action,item.source)
func _play_track(index: int): editor.output.sources.play_track(index)
func _play_selected():
	var selected=playlist.get_selected_items()
	if not selected.empty(): _play_track(selected[0])
func _move_track(direction: int):
	var selected=playlist.get_selected_items()
	if selected.empty(): return
	var index=int(selected[0])
	var target=int(clamp(index+direction,0,item.source.playlist.size()-1))
	var path=item.source.playlist[index]
	item.source.playlist.remove(index)
	item.source.playlist.insert(target,path)
	editor.output.sources.set_playlist(item.source)
	editor.checkpoint()
	refresh()
	playlist.select(target)
func _remove_track():
	var selected=playlist.get_selected_items()
	if selected.empty(): return
	item.source.playlist.remove(selected[0])
	editor.output.sources.set_playlist(item.source)
	editor.checkpoint()
	refresh()
func _session(index: int):
	item.source.session=str(session_picker.get_item_metadata(index))
	item.source.app=""
	for entry in editor.output.sources.state.get("sessions",[]):
		if entry.id==item.source.session: item.source.app=entry.app
	editor.checkpoint()
	editor.canvas.refresh_selected()

func _camera(parent: Control):
	camera_picker=OptionButton.new()
	editor._style_option(camera_picker)
	camera_picker.connect("item_selected",self,"_camera_pick")
	parent.add_child(camera_picker)
	Kit.action(editor.menu,parent,"Refresh cameras","redo",self,"_refresh_devices")
	Kit.action(editor.menu,parent,"Turn camera off" if editor.output.sources.camera_opt_in.has(item.source.device) else "Enable camera…","camera",self,"_enable_camera")
	source_status=Kit.hint(editor.menu,parent,"")
	_number(parent,"Width",item.source.width,160,1920,160,["widget","source","width"])
	_number(parent,"Height",item.source.height,120,1080,120,["widget","source","height"])
	_number(parent,"FPS",item.source.fps,5,30,5,["widget","source","fps"])
	var apply_format=Kit.action(editor.menu,parent,"Apply capture format","check",self,"_camera_format")
	apply_format.disabled=not editor.output.sources.camera_opt_in.has(item.source.device)
	apply_format.hint_tooltip="Restart the active feed with this format. When off, these settings apply on Enable."
	_crop(parent)
func _refresh_devices():
	editor.output.sources.retry()
	editor.output.sources.command({"action":"devices"})
func _camera_pick(index: int):
	item.source.device=str(camera_picker.get_item_metadata(index))
	editor.checkpoint()
	editor.canvas.refresh_selected()
	refresh()
func _enable_camera():
	if str(item.source.device).empty():
		editor.message("Select a connected camera first. No camera has been activated.")
		return
	editor.output.sources.camera_enable(item.source.device,not editor.output.sources.camera_opt_in.has(item.source.device))
	refresh()
func _camera_format():
	if editor.output.sources.camera_opt_in.has(item.source.device):
		editor.output.sources.camera_enable(item.source.device,false)
		editor.output.sources.camera_enable(item.source.device,true)

func _layout(parent: Control):
	_field(parent,"Name",editor.document.name,["layout","name"])
	_toggle(parent,"Show overlay in game",editor.document.enabled,["layout","enabled"])
	_heading(parent,"CANVAS SIZE")
	_choice(parent,"Sizing",["screen","fit"],editor.document.get("scale_mode","screen"),["layout","scale_mode"])
	_number(parent,"Width",editor.document.width,640,7680,1,["layout","width"])
	var height=_number(parent,"Height",editor.document.height,360,4320,1,["layout","height"])
	height.editable=editor.document.get("scale_mode","screen")=="fit"
	height.hint_tooltip="Follows the game screen. Choose Fixed aspect ratio to set a custom height."
	Kit.action(editor.menu,parent,"Match game screen","expand",editor,"_use_game_size")
	Kit.action(editor.menu,parent,"Apply canvas size","check",editor.canvas,"fit")
	Kit.action(editor.menu,parent,"Restore unsaved draft","rewind",editor,"restore_draft")
	if not editor.canvas.selection.empty():
		_heading(parent,"SELECTION")
		Kit.action(editor.menu,parent,"Duplicate","copy",editor,"duplicate_selection")
		Kit.action(editor.menu,parent,"Copy","copy",editor,"copy_selection")
		Kit.action(editor.menu,parent,"Paste","copy",editor,"paste_selection")
		var row=Kit.row(parent,6)
		Kit.action(editor.menu,row,"Bring forward","forward",editor,"reorder",[1])
		Kit.action(editor.menu,row,"Send back","rewind",editor,"reorder",[-1])
		Kit.action(editor.menu,parent,"Delete selected","trash",editor,"delete_selection")
		if not item.empty():
			_toggle(parent,"Visible",item.visible,["widget","visible"])
			_toggle(parent,"Locked",item.locked,["widget","locked"])
	var tip=Kit.hint(editor.menu,parent,"F1 hides the editor. Saved gameplay widgets keep their own visibility.")
	tip.hint_tooltip="Draft changes stay here until Save layout applies them."
func show_layout():
	if tabs!=null: tabs.current_tab=tabs.get_tab_count()-1

func _source_changed():
	if not is_instance_valid(editor) or not editor.visible: return
	var service=editor.output.sources
	if source_status!=null and is_instance_valid(source_status):
		if item.get("type")=="camera": source_status.text=str(service.state.get("camera_error","")) if not str(service.state.get("camera_error","")).empty() else ("No camera connected" if service.state.get("cameras",[]).empty() else ("Camera active" if service.camera_running.has(item.source.device) else "Camera off · Enable to grant access"))
		elif item.get("type")=="media":
			var media=service.media(item.source)
			source_status.text=str(media.get("title",""))+"\n"+str(media.get("artist",""))
			for action in media_buttons:
				if is_instance_valid(media_buttons[action]): media_buttons[action].disabled=not media.get("controls",{}).get(action,false)
			if seek!=null and is_instance_valid(seek) and not seek_dragging:
				seek.editable=bool(media.get("controls",{}).get("seek",false)) and float(media.get("duration",0))>0
				seek.max_value=max(1,float(media.get("duration",0)))
				seek.value=float(media.get("position",0))
	if camera_picker!=null and is_instance_valid(camera_picker) and not camera_picker.get_popup().visible:
		camera_picker.clear()
		camera_picker.add_item("Choose camera")
		camera_picker.set_item_metadata(0,"")
		for device in service.state.get("cameras",[]):
			camera_picker.add_item(device.name)
			var index=camera_picker.get_item_count()-1
			camera_picker.set_item_metadata(index,device.id)
			if device.id==item.source.device: camera_picker.select(index)
	if session_picker!=null and is_instance_valid(session_picker) and not session_picker.get_popup().visible:
		session_picker.clear()
		session_picker.add_item("Automatic · active player")
		session_picker.set_item_metadata(0,"auto")
		for session in service.state.get("sessions",[]):
			var title=str(session.get("info",{}).get("title",""))
			session_picker.add_item(str(session.app).get_file()+" · "+title)
			var index=session_picker.get_item_count()-1
			session_picker.set_item_metadata(index,session.id)
			if session.id==item.source.session or (item.source.session!="auto" and session.app==item.source.app): session_picker.select(index)
