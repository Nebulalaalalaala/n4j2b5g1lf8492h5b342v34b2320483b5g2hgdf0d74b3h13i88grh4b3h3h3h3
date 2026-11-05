extends Node
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const Library=preload("user://mod/core/workspace4/overlays/OverlayLibrary.gd")
const Kit=preload("user://mod/core/workspace4/Kit.gd")
const Galaxy=preload("user://mod/core/workspace4/Galaxy.gd")
const Geometry=preload("user://mod/core/GoobWindowGeometry.gd")
const RECOVERY="user://goobplayability/overlays/draft.json"
const STATE="user://goobplayability/overlays/editor.json"
var menu
var tas_tool
var editor_fonts={}
var zoom_readout: Label
var resolution_readout: Label
var visible=false
var window_layer: CanvasLayer
var output
var document={}
var saved=""
var frame: Panel
var canvas
var inspector
var layer_list: VBoxContainer
var status: Label
var title: Label
var layout_picker: OptionButton
var history=[]
var cursor=0
var clipboard=[]
var wanted_open=false
var f1_hidden=false
var window_drag=false
var window_resize=false
var ui_scale=1.0
var geometry=Geometry.new()
var pending_edit_deadline=0
var next_draft_save=0
var dirty=false
var name_popup: PopupPanel
var name_edit: LineEdit
var name_action=""
var resume_popup=""
var name_field: LineEdit
var dialog: FileDialog
var file_action=""
var chooser=""
var binding=false
var saved_window={}
var library=[]
var properties
var undo_button: Button
var redo_button: Button
var live_button: Button
var preview_capture: Viewport
var preview_backdrop: CanvasLayer
var preview_scene_id=0
var preview_next_sync=0
var background_picker: OptionButton

func setup(owner_menu, layer_node):
	tas_tool=owner_menu.get("tas_tool")
	menu=self # Editor fonts are independent of Workspace zoom/text scaling.
	output=layer_node

func font(size: int):
	if not editor_fonts.has(size): editor_fonts[size]=load("user://mod/core/workspace4/overlays/OverlayWidget.gd")._font(size,"Inter Semibold")
	return editor_fonts[size]

func label(text: String, size=17, color=Color.white):
	var result=Label.new()
	result.text=text
	result.add_font_override("font",font(size))
	result.add_color_override("font_color",color)
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return result

func _ready():
	visible=false
	pause_mode=Node.PAUSE_MODE_PROCESS
	add_to_group("goob_f1_windows")
	document=output.layout.duplicate(true)
	Doc.reframe(document,get_viewport().get_visible_rect().size)
	saved=JSON.print(document)
	history=[document.duplicate(true)]
	saved_window=Doc.read(STATE)
	_build()
	get_viewport().connect("size_changed",self,"_fit_window")
	visible=false
	frame.visible=false
	set_process_input(false)
	set_process(false)

func _build():
	window_layer=CanvasLayer.new()
	window_layer.layer=140
	add_child(window_layer)
	frame=Panel.new()
	frame.rect_size=Vector2(1480,900)
	frame.theme=_make_theme()
	frame.add_stylebox_override("panel",Galaxy.box(Galaxy.color("bg"),Galaxy.color("line"),0,18))
	frame.mouse_filter=Control.MOUSE_FILTER_STOP
	window_layer.add_child(frame)
	var margin=MarginContainer.new()
	margin.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	margin.add_constant_override("margin_left",16)
	margin.add_constant_override("margin_right",16)
	margin.add_constant_override("margin_top",12)
	margin.add_constant_override("margin_bottom",20)
	frame.add_child(margin)
	var column=Kit.column(margin,12)
	var header=Kit.row(column,12)
	header.rect_min_size.y=38
	header.mouse_filter=Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape=Control.CURSOR_MOVE
	header.hint_tooltip="Drag this title bar to move the editor. Resize from the lower-right corner."
	header.connect("gui_input",self,"_header_input")
	title=menu.label("Overlay Studio",22,Galaxy.color("ink"))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	Kit.action(menu,header,"Fit window","expand",self,"_maximize").hint_tooltip="Use the available screen space."
	Kit.action(menu,header,"Close","close",self,"close").hint_tooltip="Keep your draft. F1 hides all editors together."
	var toolbar=Kit.row(column,8)
	layout_picker=OptionButton.new()
	_style_option(layout_picker)
	layout_picker.rect_min_size.x=200
	layout_picker.connect("item_selected",self,"_layout_selected")
	toolbar.add_child(layout_picker)
	Kit.action(menu,toolbar,"New","plus",self,"_new_layout")
	Kit.action(menu,toolbar,"Save as","copy",self,"_save_as")
	Kit.action(menu,toolbar,"Rename","editor",self,"_rename_layout")
	Kit.action(menu,toolbar,"Delete","trash",self,"_delete_layout")
	Kit.action(menu,toolbar,"Import","folder",self,"_files",["layout_import"])
	Kit.action(menu,toolbar,"Export","forward",self,"_files",["layout_export"])
	var body=Kit.row(column,12)
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var left=TabContainer.new()
	left.rect_min_size.x=190
	left.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_style_tabs(left)
	body.add_child(left)
	var add_scroll=_scroll(left,"Add widgets")
	var library_column=Kit.column(add_scroll,10)
	for section in [["Music & Media",[["Universal player","media","play"]]],["Input displays",[["Keyboard","keyboard","keyboard"]]],["Text & Graphics",[["Text","text","editor"],["Image","image","overlay"]]],["Game information",[["Frame rate","fps","signal"],["Level info","game","gamepad"]]],["Utilities",[["Clock","clock","timeline"]]]]:
		library_column.add_child(menu.label(section[0],13,Galaxy.color("muted")))
		for entry in section[1]:
			var button=Kit.action(menu,library_column,entry[0],entry[2],self,"add_widget",[entry[1]])
			button.hint_tooltip="Add "+str(Doc.TITLES.get(entry[1],entry[0]))+" to this layout."
	var layers_scroll=_scroll(left,"Layers")
	layer_list=Kit.column(layers_scroll,6)
	canvas=load("user://mod/core/workspace4/overlays/OverlayCanvas.gd").new()
	canvas.rect_min_size=Vector2(320,240)
	canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(canvas)
	canvas.connect("selected",self,"_selection")
	canvas.connect("gesture_finished",self,"checkpoint")
	canvas.connect("edited",self,"_edited")
	canvas.connect("view_changed",self,"_view_changed")
	var right=VBoxContainer.new()
	right.rect_min_size.x=260
	right.rect_clip_content=true
	body.add_child(right)
	properties=load("user://mod/core/workspace4/overlays/OverlayProperties.gd").new()
	properties.setup(self,right)
	var bottom=Kit.row(column,6)
	undo_button=Kit.action(menu,bottom,"","undo",self,"undo")
	undo_button.hint_tooltip="Undo · Ctrl+Z"
	redo_button=Kit.action(menu,bottom,"","redo",self,"redo")
	redo_button.hint_tooltip="Redo · Ctrl+Shift+Z"
	Kit.action(menu,bottom,"−","",self,"_zoom",[-1])
	Kit.action(menu,bottom,"Fit","compact",canvas,"fit")
	Kit.action(menu,bottom,"+","",self,"_zoom",[1])
	Kit.action(menu,bottom,"100%","",canvas,"actual_size").hint_tooltip="One design pixel per editor pixel."
	Kit.action(menu,bottom,"Selection","",canvas,"focus_selection").hint_tooltip="Zoom to the selected widget. Double-click also frames the selection."
	zoom_readout=menu.label("",13,Galaxy.color("muted"))
	bottom.add_child(zoom_readout)
	bottom=Kit.row(column,6)
	var snap=Kit.action(menu,bottom,"Snap","hitbox",self,"_snap")
	snap.toggle_mode=true
	snap.pressed=true
	snap.hint_tooltip="Snap to edges, centers and the grid. Hold Alt to bypass."
	var align=OptionButton.new()
	_style_option(align)
	for text in ["Align…","Left","Center horizontally","Right","Top","Center vertically","Bottom","Group","Ungroup"]: align.add_item(text)
	align.connect("item_selected",self,"_align",[align])
	bottom.add_child(align)
	var background=OptionButton.new()
	_style_option(background)
	for text in ["Sample scene","Checkerboard","Solid colour","Live game"]: background.add_item(text)
	background_picker=background
	background.set_item_disabled(3,not _has_live_game())
	background.hint_tooltip="Preview background only. Live game is available inside a level."
	background.connect("item_selected",self,"_background",[background])
	bottom.add_child(background)
	live_button=Kit.action(menu,bottom,"Test media","play",self,"_preview")
	live_button.hint_tooltip="Enable media buttons. Other widgets remain draggable. In game, hold Alt to use media controls."
	Kit.action(menu,bottom,"Save layout","save",self,"save",[],true)
	resolution_readout=menu.label("",13,Galaxy.color("muted"))
	bottom.add_child(resolution_readout)
	status=menu.label("Drag widgets · Scroll to zoom · Middle mouse to pan",13,Galaxy.color("muted"))
	column.add_child(status)
	var grip=Control.new()
	grip.anchor_left=1
	grip.anchor_top=1
	grip.anchor_right=1
	grip.anchor_bottom=1
	grip.margin_left=-24
	grip.margin_top=-24
	grip.mouse_default_cursor_shape=Control.CURSOR_FDIAGSIZE
	grip.connect("gui_input",self,"_resize_input")
	frame.add_child(grip)
	var mark=menu.label("◢",16,Galaxy.color("accent"))
	mark.rect_position=Vector2(7,5)
	grip.add_child(mark)
	dialog=FileDialog.new()
	dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.connect("file_selected",self,"_file_selected")
	dialog.connect("files_selected",self,"_audio_selected")
	frame.add_child(dialog)
	_refresh_library()
	canvas.set_document(document,output.sources)
	_refresh_layers()
	properties.refresh()
	_fit_window()

func _make_theme() -> Theme:
	var theme=Theme.new()
	theme.default_font=menu.font(14)
	for type in ["Button","OptionButton","LineEdit","TextEdit","PopupMenu","ItemList","Label","ColorPickerButton","SpinBox"]:
		theme.set_color("font_color",type,Galaxy.color("ink"))
		theme.set_color("font_color_hover",type,Galaxy.color("ink"))
		theme.set_color("font_color_pressed",type,Galaxy.color("ink"))
		theme.set_color("font_color_disabled",type,Galaxy.color("dim"))
	for type in ["Button","OptionButton","ColorPickerButton"]:
		for state in ["normal","hover","pressed","disabled"]: theme.set_stylebox(state,type,Galaxy.box(Galaxy.color("surface") if state=="normal" else Galaxy.color("hover"),Galaxy.color("line"),10,8))
		theme.set_stylebox("focus",type,StyleBoxEmpty.new())
	for type in ["LineEdit","TextEdit","ItemList"]:
		theme.set_stylebox("normal" if type!="ItemList" else "bg",type,Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),8,8))
		theme.set_stylebox("focus",type,Galaxy.box(Galaxy.color("surface"),Galaxy.color("accent"),8,8))
		theme.set_color("selection_color",type,Galaxy.color("accent").darkened(0.4))
		theme.set_color("cursor_color",type,Galaxy.color("accent"))
	for type in ["Panel","PopupPanel","PopupMenu","TooltipPanel","WindowDialog"]: theme.set_stylebox("panel",type,Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),10,10))
	theme.set_stylebox("hover","PopupMenu",Galaxy.box(Galaxy.color("hover"),Color.transparent,6,6))
	theme.set_font("font","TooltipLabel",menu.font(14))
	theme.set_color("font_color","TooltipLabel",Galaxy.color("ink"))
	theme.set_icon("arrow","OptionButton",Galaxy.icon("chev-down",Galaxy.color("muted"),14))
	theme.set_constant("arrow_margin","OptionButton",6)
	theme.set_icon("checked","PopupMenu",Galaxy.icon("check",Galaxy.color("accent"),14))
	theme.set_icon("radio_checked","PopupMenu",Galaxy.icon("check",Galaxy.color("accent"),14))
	var transparent=Image.new()
	transparent.create(2,2,false,Image.FORMAT_RGBA8)
	transparent.fill(Color.transparent)
	var empty=ImageTexture.new()
	empty.create_from_image(transparent)
	theme.set_icon("unchecked","PopupMenu",empty)
	theme.set_icon("radio_unchecked","PopupMenu",empty)
	theme.set_icon("bg","ColorPickerButton",empty)
	return theme

func _style_option(control: OptionButton):
	control.focus_mode=Control.FOCUS_NONE
	control.add_icon_override("arrow",Galaxy.icon("chev-down",Galaxy.color("muted"),14))
	control.add_constant_override("arrow_margin",6)
	control.add_font_override("font",menu.font(14))
	control.add_color_override("font_color",Galaxy.color("ink"))
	control.add_color_override("font_color_hover",Galaxy.color("ink"))
	for state in ["normal","hover","pressed"]: control.add_stylebox_override(state,Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),10,9))
	var popup=control.get_popup()
	popup.add_font_override("font",menu.font(15))
	popup.add_color_override("font_color",Galaxy.color("ink"))
	popup.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),10,10))

func _style_tabs(control: TabContainer):
	control.add_font_override("font",menu.font(14))
	control.add_color_override("font_color_fg",Galaxy.color("ink"))
	control.add_color_override("font_color_bg",Galaxy.color("muted"))
	control.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),8,12))
	control.add_stylebox_override("tab_fg",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),8,8))
	control.add_stylebox_override("tab_bg",Galaxy.box(Galaxy.color("bg"),Galaxy.color("border"),8,8))

func _scroll(parent: Control, name: String):
	var scroll=ScrollContainer.new()
	scroll.name=name
	scroll.scroll_horizontal_enabled=false
	parent.add_child(scroll)
	return scroll

func open():
	wanted_open=true
	f1_hidden=false
	visible=true
	frame.visible=true
	set_process_input(true)
	output.set_editor_visible(true)
	_fit_window()
	next_draft_save=OS.get_ticks_msec()+30000
	background_picker.set_item_disabled(3,not _has_live_game())
	if canvas.background=="Live game" and preview_capture==null: _start_game_preview()
	_preview_running()
	if menu.tas_tool!=null: menu.tas_tool.call("_update_mouse_capture")
	var recovery=Doc.read(RECOVERY)
	if not recovery.empty() and JSON.print(recovery)!=saved and history.size()==1:
		status.text="An unsaved draft is available. Restore it from Layout properties."
	properties.refresh()

func close():
	if name_popup!=null: name_popup.hide()
	if dialog!=null: dialog.hide()
	_recover_save()
	wanted_open=false
	visible=false
	frame.visible=false
	set_process_input(false)
	output.set_editor_visible(false)
	next_draft_save=0
	_drop_game_preview()
	_preview_running()
	_store_window()
	if menu.tas_tool!=null: menu.tas_tool.call("_update_mouse_capture")

func is_interface_open() -> bool: return wanted_open and not f1_hidden
func set_f1_hidden(value: bool):
	if value:
		_recover_save()
		resume_popup="name" if name_popup!=null and name_popup.visible else ("file" if dialog!=null and dialog.visible else "")
		if name_popup!=null: name_popup.hide()
		if dialog!=null: dialog.hide()
		_drop_game_preview()
	f1_hidden=value
	visible=wanted_open and not value
	frame.visible=visible
	set_process_input(visible)
	output.set_editor_visible(visible)
	if visible: next_draft_save=OS.get_ticks_msec()+30000
	else: next_draft_save=0
	_preview_running()
	if visible:
		if canvas.background=="Live game" and preview_capture==null: _start_game_preview()
		if resume_popup=="name": name_popup.popup_centered(Vector2(360,160))
		elif resume_popup=="file": dialog.popup_centered_ratio(0.75)
		resume_popup=""

func _fit_window():
	if frame==null: return
	var size=get_viewport().get_visible_rect().size
	if not document.empty() and Doc.reframe(document,size) and canvas!=null:
		canvas.place()
		if properties!=null: properties.refresh()
	var native_scale=max(0.01,abs(get_viewport().get_final_transform().get_scale().x))
	var physical=size*native_scale
	ui_scale=max(0.3,min(1.0,min((physical.x-32)/1180.0,(physical.y-32)/820.0)))/native_scale
	frame.rect_scale=Vector2.ONE*ui_scale
	if not saved_window.empty():
		frame.rect_size=Vector2(Doc.finite(saved_window.get("w",1480),1480,900,2400),Doc.finite(saved_window.get("h",900),900,680,1600))
		frame.rect_position=Vector2(float(saved_window.get("x",12)),float(saved_window.get("y",12)))
	else:
		frame.rect_size=Vector2(min(1480,(size.x-40)/ui_scale),min(900,(size.y-40)/ui_scale))
		frame.rect_position=(size-frame.rect_size*ui_scale)/2
	frame.rect_size.x=min(frame.rect_size.x,max(900,(size.x-24)/ui_scale))
	frame.rect_size.y=min(frame.rect_size.y,max(680,(size.y-24)/ui_scale))
	frame.rect_position.x=clamp(frame.rect_position.x,0,max(0,size.x-frame.rect_size.x*ui_scale))
	frame.rect_position.y=clamp(frame.rect_position.y,0,max(0,size.y-frame.rect_size.y*ui_scale))

func _maximize():
	saved_window={}
	_fit_window()
	frame.rect_size=(get_viewport().get_visible_rect().size-Vector2(32,32))/ui_scale
	frame.rect_position=Vector2(16,16)
	canvas.fit()

func _header_input(event):
	if event is InputEventMouseButton and event.button_index==BUTTON_LEFT:
		window_drag=event.pressed
		if not event.pressed: _store_window()
	elif event is InputEventMouseMotion and window_drag:
		frame.rect_position=geometry.moved_position(frame.rect_position,frame.rect_size*ui_scale,event.relative*ui_scale,get_viewport().get_visible_rect().size,120,40)

func _resize_input(event):
	if event is InputEventMouseButton and event.button_index==BUTTON_LEFT:
		window_resize=event.pressed
		if not event.pressed: _store_window()
	elif event is InputEventMouseMotion and window_resize:
		var result=geometry.resized_size_and_position(frame.rect_size,frame.rect_position/ui_scale,event.relative,Vector2(900,680),get_viewport().get_visible_rect().size/ui_scale,Vector2(12,12))
		frame.rect_position=result.position*ui_scale
		frame.rect_size=result.size

func _store_window():
	saved_window={"x":frame.rect_position.x,"y":frame.rect_position.y,"w":frame.rect_size.x,"h":frame.rect_size.y}
	Doc.write(STATE,saved_window)

func add_widget(kind: String):
	if document.widgets.size()>=Doc.MAX_WIDGETS:
		message("This layout has reached 64 widgets.")
		return
	var item=Doc.widget(kind,Vector2(document.width,document.height))
	if Galaxy.is_light():
		item.color=Galaxy.color("ink").to_html(false)
		item.background=Galaxy.color("surface").to_html(false)
		item.accent=Galaxy.color("accent").to_html(false)
		item.border_color=Galaxy.color("line").to_html(false)
		if kind=="keyboard":
			item.source.idle=Galaxy.color("raised").to_html(false)
			item.source.pressed=Galaxy.color("accent").to_html(false)
			item.source.text=Galaxy.color("ink").to_html(false)
	item.x+=0.025*(document.widgets.size()%8)
	item.y+=0.035*(document.widgets.size()%8)
	document.widgets.append(item)
	canvas.selection=[item.id]
	canvas.key_mode=false
	checkpoint()
	_refresh()

func _refresh():
	canvas.set_document(document,output.sources)
	_refresh_layers()
	properties.refresh()
	_title()

func _selection():
	_refresh_layers()
	properties.refresh()

func _refresh_layers():
	for child in layer_list.get_children():
		layer_list.remove_child(child)
		child.queue_free()
	for index in range(document.widgets.size()-1,-1,-1):
		var item=document.widgets[index]
		var row=Kit.row(layer_list,3)
		var button=Kit.action(menu,row,str(item.name),"",self,"select",[item.id])
		button.clip_text=true
		button.rect_min_size.x=88
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.toggle_mode=true
		button.pressed=canvas.selection.has(item.id)
		button.hint_tooltip=item.name+(" · Group" if not item.group.empty() else "")
		Kit.action(menu,row,"","eye" if item.visible else "hide",self,"_layer_toggle",[item.id,"visible"]).hint_tooltip="Show / hide widget"
		Kit.action(menu,row,"","lock" if item.locked else "lock",self,"_layer_toggle",[item.id,"locked"]).hint_tooltip="Lock / unlock widget"

func select(id: String):
	canvas.selection=[id]
	canvas.key_mode=false
	canvas.key_selected=-1
	canvas.update()
	_selection()

func _layer_toggle(id: String, key: String):
	var item=canvas.find_item(id)
	if item.empty(): return
	item[key]=not item[key]
	checkpoint()
	_refresh()

func _edited():
	dirty=true
	_title()

func checkpoint():
	pending_edit_deadline=0
	if history.empty(): history=[document.duplicate(true)]
	if JSON.print(history[cursor])!=JSON.print(document):
		history.resize(cursor+1)
		history.append(document.duplicate(true))
		var bytes=0
		for snapshot in history: bytes+=JSON.print(snapshot).length()
		while history.size()>1 and (history.size()>80 or bytes>16777216): bytes-=JSON.print(history.pop_front()).length()
		cursor=history.size()-1
	dirty=JSON.print(document)!=saved
	_title()

func _title():
	if title==null: return
	title.text="Overlay Studio · "+str(document.get("name","My overlay"))+("  •" if dirty else "")
	undo_button.disabled=cursor<=0
	redo_button.disabled=cursor>=history.size()-1

func undo():
	checkpoint()
	if cursor<=0: return
	cursor-=1
	document=history[cursor].duplicate(true)
	_refresh()

func redo():
	if cursor>=history.size()-1: return
	cursor+=1
	document=history[cursor].duplicate(true)
	_refresh()

func edit_property(value, path: Array):
	var item=canvas.find_item(canvas.selection[0]) if canvas.selection.size()==1 else {}
	var target=document if path[0]=="layout" else item
	if target.empty(): return
	var keys=path.duplicate()
	keys.pop_front()
	for i in range(keys.size()-1): target=target[keys[i]]
	target[keys.back()]=value
	if path[0]=="layout": Doc.reframe(document,get_viewport().get_visible_rect().size)
	canvas.refresh_selected()
	pending_edit_deadline=OS.get_ticks_msec()+450
	dirty=true
	_title()
	if path.has("name") or path.has("visible") or path.has("locked"): _refresh_layers()

func duplicate_selection():
	copy_selection()
	paste_selection()
func copy_selection():
	clipboard=[]
	for id in canvas.selection:
		var item=canvas.find_item(id)
		if not item.empty(): clipboard.append(item.duplicate(true))
func paste_selection():
	canvas.selection=[]
	var groups={}
	for old in clipboard:
		if document.widgets.size()>=Doc.MAX_WIDGETS: break
		var item=old.duplicate(true)
		item.id=Doc.uid()
		item.x+=0.02
		item.y+=0.02
		item.name+=" copy"
		if not item.group.empty():
			if not groups.has(item.group): groups[item.group]=Doc.uid()
			item.group=groups[item.group]
		document.widgets.append(item)
		canvas.selection.append(item.id)
	checkpoint()
	_refresh()
func delete_selection():
	for i in range(document.widgets.size()-1,-1,-1):
		if canvas.selection.has(document.widgets[i].id) and not document.widgets[i].locked: document.widgets.remove(i)
	canvas.selection=[]
	checkpoint()
	_refresh()
func reorder(direction: int):
	if canvas.selection.size()!=1: return
	for i in document.widgets.size():
		if document.widgets[i].id==canvas.selection[0]:
			var next=clamp(i+direction,0,document.widgets.size()-1)
			var item=document.widgets[i]
			document.widgets.remove(i)
			document.widgets.insert(next,item)
			break
	checkpoint()
	_refresh()

func _align(index: int, picker: OptionButton):
	picker.select(0)
	if index<=0 or canvas.selection.empty(): return
	if index in [7,8]:
		var group=Doc.uid() if index==7 else ""
		for id in canvas.selection:
			var item=canvas.find_item(id)
			if not item.empty() and not item.locked: item.group=group
	else:
		var bounds=canvas.selected_rect() if canvas.selection.size()>1 else Rect2(Vector2.ZERO,Vector2(document.width,document.height))
		for id in canvas.selection:
			var item=canvas.find_item(id)
			if item.empty() or item.locked: continue
			var rect=Doc.rect(item,Vector2(document.width,document.height))
			if index==1: rect.position.x=bounds.position.x
			elif index==2: rect.position.x=bounds.position.x+(bounds.size.x-rect.size.x)/2
			elif index==3: rect.position.x=bounds.end.x-rect.size.x
			elif index==4: rect.position.y=bounds.position.y
			elif index==5: rect.position.y=bounds.position.y+(bounds.size.y-rect.size.y)/2
			elif index==6: rect.position.y=bounds.end.y-rect.size.y
			Doc.set_rect(item,rect,Vector2(document.width,document.height))
	checkpoint()
	_refresh()

func _view_changed():
	if zoom_readout!=null: zoom_readout.text="%d%%"%int(round(canvas.factor*100))
	if resolution_readout!=null:
		var reference=canvas.reference_size()
		resolution_readout.text="%d × %d"%[round(reference.x),round(reference.y)]

func _use_game_size(refresh=true):
	var view=get_viewport().get_visible_rect().size
	document.scale_mode="screen"
	Doc.reframe(document,view)
	if refresh:
		checkpoint()
		_refresh()
		canvas.fit()

func _snap(): canvas.snap=not canvas.snap
func _zoom(direction: int): canvas.set_zoom(canvas.zoom*(1.2 if direction>0 else 1/1.2))
func _preview():
	canvas.set_preview(not canvas.live)
	live_button.text="Media on" if canvas.live else "Test media"
func _background(index: int, picker: OptionButton):
	canvas.background=picker.get_item_text(index)
	if canvas.background=="Live game": _start_game_preview()
	elif preview_capture!=null:
		preview_capture.queue_free()
		preview_capture=null
		canvas.game_texture=null
	_preview_running()
	canvas.update()
func _has_live_game() -> bool:
	return is_instance_valid(menu.tas_tool) and menu.tas_tool.has_method("_find_game") and menu.tas_tool.call("_find_game")!=null
func _start_game_preview():
	if preview_capture!=null: return
	if not _has_live_game():
		canvas.background="Sample scene"
		background_picker.select(0)
		message("Open a level to use live game preview.")
		return
	preview_capture=Viewport.new()
	preview_capture.disable_3d=true
	preview_capture.size=get_viewport().get_visible_rect().size
	preview_capture.world_2d=get_viewport().world_2d
	preview_capture.canvas_transform=get_viewport().canvas_transform
	preview_capture.render_target_update_mode=Viewport.UPDATE_ALWAYS
	preview_capture.render_target_v_flip=true
	preview_capture.transparent_bg=true
	frame.add_child(preview_capture)
	canvas.game_texture=preview_capture.get_texture()
	preview_backdrop=CanvasLayer.new()
	preview_backdrop.layer=-1
	preview_capture.add_child(preview_backdrop)
	preview_scene_id=0
	preview_next_sync=0
	_preview_running()
	canvas.update()

func _drop_game_preview():
	if preview_capture!=null:
		frame.remove_child(preview_capture)
		preview_capture.queue_free()
		preview_capture=null
		preview_backdrop=null
		canvas.game_texture=null
		canvas.update()

func _preview_running():
	var active=preview_capture!=null and visible and canvas.background=="Live game"
	set_process(visible)
	if preview_capture!=null: preview_capture.render_target_update_mode=Viewport.UPDATE_ALWAYS if active else Viewport.UPDATE_DISABLED
func _process(_delta):
	if not visible: return
	var now=OS.get_ticks_msec()
	if pending_edit_deadline>0 and now>=pending_edit_deadline: checkpoint()
	if next_draft_save>0 and now>=next_draft_save:
		next_draft_save=now+30000
		_recover_save()
	if preview_capture==null or canvas.background!="Live game": return
	var view=get_viewport()
	if preview_capture.canvas_transform!=view.canvas_transform: preview_capture.canvas_transform=view.canvas_transform
	if preview_capture.size!=view.get_visible_rect().size: preview_capture.size=view.get_visible_rect().size
	if OS.get_ticks_msec()<preview_next_sync: return
	preview_next_sync=OS.get_ticks_msec()+500
	var scene=get_tree().current_scene
	var background=scene.get_node_or_null("Background") if is_instance_valid(scene) else null
	var id=0
	if background!=null and background.get("base_background") is Control:
		var source=background.get("base_background")
		id=source.get_instance_id()
		for child in source.get_children():
			if child is TextureRect and child.texture!=null: id+=child.texture.get_instance_id()
		if id!=preview_scene_id:
			for child in preview_backdrop.get_children():
				preview_backdrop.remove_child(child)
				child.queue_free()
			var copy=source.duplicate(0) # Presentation only: no scripts, signals or game simulation.
			preview_backdrop.add_child(copy)
			copy.rect_position=Vector2.ZERO
			copy.rect_size=preview_capture.size
			copy.mouse_filter=Control.MOUSE_FILTER_IGNORE
			preview_scene_id=id

func save():
	checkpoint()
	if output.apply_document(document):
		saved=JSON.print(document)
		dirty=false
		Library.save(document)
		Directory.new().remove(RECOVERY)
		message("Layout saved"+(" · Live in game" if document.enabled else " · Gameplay overlay is hidden"))
		_refresh_library()
		_title()
	else: message("Could not save the layout. Your draft is still here.")
func _new_layout():
	_recover_save()
	document=Doc.empty("Untitled overlay")
	_use_game_size(false)
	canvas.selection=[]
	checkpoint()
	_refresh()
func _save_as(): _prompt_name("save_as")
func _rename_layout(): _prompt_name("rename")
func _prompt_name(action: String):
	name_action=action
	if name_popup==null:
		name_popup=PopupPanel.new()
		name_popup.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),16,14))
		frame.add_child(name_popup)
		var body=Kit.column(name_popup,12)
		body.add_child(menu.label("Name your layout",18,Galaxy.color("ink")))
		name_edit=Kit.field(menu,body,"","Layout name",null,"")
		name_edit.max_length=80
		name_edit.rect_min_size.x=280
		name_edit.connect("text_entered",self,"_submit_name_entered")
		var row=Kit.row(body,10)
		Kit.action(menu,row,"Cancel","",name_popup,"hide")
		Kit.action(menu,row,"Confirm","check",self,"_submit_name",[],true)
	name_edit.text=str(document.name)+(" copy" if action=="save_as" else "")
	name_popup.popup_centered(Vector2(360,160))
	name_edit.grab_focus()
	name_edit.select_all()
func _submit_name_entered(_text: String): _submit_name()
func _submit_name():
	var name=name_edit.text.strip_edges().left(80)
	if name.empty(): return
	if name_action=="save_as": document.id=Doc.uid()
	document.name=name
	name_popup.hide()
	checkpoint()
	if name_action=="save_as": save()
	else: message("Name changed · Save layout to apply")
	_refresh()
func _delete_layout():
	var id=str(document.id)
	var was_active=id==str(output.layout.get("id",""))
	if not Library.remove(id):
		message("Could not move this layout to recovery. Your layout is unchanged.")
		return
	if was_active and not output.clear_active_layout():
		Library.save(document) # Keep the named layout available if active-file writing failed.
		message("Could not clear the active layout. Your layout is still available.")
		return
	_new_layout()
	_refresh_library()
	message("Layout moved to recovery · Gameplay overlay cleared." if was_active else "Layout moved to the recovery folder.")
func _refresh_library():
	if layout_picker==null: return
	library=Library.list_layouts()
	layout_picker.clear()
	layout_picker.add_item("Layouts · "+str(library.size()))
	for value in library: layout_picker.add_item(value.name)
func _layout_selected(index: int):
	if index<=0: return
	var data=Doc.clean(Doc.read(library[index-1].path))
	if data.empty():
		message("This layout is damaged or uses a newer version.")
		return
	_recover_save()
	document=data
	canvas.selection=[]
	checkpoint()
	_refresh()
	message("Layout loaded into the editor. Save to use it in game.")
func _recover_save():
	if JSON.print(document)!=saved: Doc.write(RECOVERY,document)
func restore_draft():
	var data=Doc.clean(Doc.read(RECOVERY))
	if data.empty():
		message("No recoverable draft.")
		return
	document=data
	checkpoint()
	_refresh()
func message(text: String): status.text=text

func _files(action: String):
	file_action=action
	dialog.clear_filters()
	dialog.current_dir=OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if action in ["layout_import","layout_export"]:
		dialog.add_filter("*.json ; Overlay layout")
		dialog.mode=FileDialog.MODE_SAVE_FILE if action=="layout_export" else FileDialog.MODE_OPEN_FILE
		dialog.current_file=Library.key(str(document.name))+".overlay.json" if action=="layout_export" else ""
	elif action=="image":
		for filter in ["*.png ; PNG image","*.jpg,*.jpeg ; JPEG image","*.webp ; WebP image"]: dialog.add_filter(filter)
		dialog.mode=FileDialog.MODE_OPEN_FILE
	elif action=="audio":
		for filter in ["*.mp3 ; MP3 audio","*.wav ; WAV audio","*.ogg ; Ogg audio"]: dialog.add_filter(filter)
		dialog.mode=FileDialog.MODE_OPEN_FILES
	dialog.popup_centered_ratio(0.75)
func _file_selected(path: String):
	if file_action=="layout_export":
		message("Layout exported." if Doc.write(path,Doc.clean(document)) else "Could not export this layout.")
	elif file_action=="layout_import":
		var data=Doc.clean(Doc.read(path))
		if data.empty():
			message("Unsupported or damaged layout. Your current draft is safe.")
			return
		data.id=Doc.uid()
		_recover_save()
		document=data
		canvas.selection=[]
		checkpoint()
		_refresh()
		message("Imported as a new draft. Save to apply it.")
	elif file_action=="image":
		edit_property(path,["widget","source","path"])
		checkpoint()
		properties.refresh()
func _audio_selected(paths: PoolStringArray):
	if canvas.selection.size()!=1: return
	var item=canvas.find_item(canvas.selection[0])
	if item.empty() or item.type!="media": return
	for path in paths:
		if not item.source.playlist.has(path) and item.source.playlist.size()<256: item.source.playlist.append(path)
	output.sources.set_playlist(item.source)
	checkpoint()
	properties.refresh()

func _input(event):
	if not is_interface_open(): return
	if binding and event is InputEventKey and event.pressed and not event.echo:
		properties.bind_key(event)
		binding=false
		get_tree().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var focus=frame.get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox: return
	if event.control:
		if event.scancode==KEY_Z:
			if event.shift: redo()
			else: undo()
		elif event.scancode==KEY_Y: redo()
		elif event.scancode==KEY_C: copy_selection()
		elif event.scancode==KEY_V: paste_selection()
		elif event.scancode==KEY_D: duplicate_selection()
		elif event.scancode==KEY_S: save()
		else: return
	elif event.scancode==KEY_DELETE: delete_selection()
	else: return
	get_tree().set_input_as_handled()

func _exit_tree():
	if output!=null and is_instance_valid(output): output.set_editor_visible(false)
