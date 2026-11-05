extends Control
signal selected
signal gesture_started
signal gesture_finished
signal edited
signal view_changed
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const Widget=preload("user://mod/core/workspace4/overlays/OverlayWidget.gd")
const Galaxy=preload("user://mod/core/workspace4/Galaxy.gd")
var document={}
var sources
var stage: Control
var widgets={}
var selection=[]
var zoom=1.0
var pan=Vector2.ZERO
var factor=1.0
var origin=Vector2.ZERO
var background="Sample scene"
var sample_texture
var solid=Color("202441")
var snap=true
var guides=[]
var dragging=false
var resizing=false
var panning=false
var start=Vector2.ZERO
var originals={}
var bounds=Rect2()
var live=false
var key_mode=false
var key_selected=-1
var game_texture
var live_view: Viewport
var last_size=Vector2.ZERO

func _ready():
	sample_texture=load("res://project_specific/level_themes/snow/background.png")
	rect_clip_content=true
	mouse_filter=Control.MOUSE_FILTER_STOP
	focus_mode=Control.FOCUS_NONE
	stage=Control.new()
	stage.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	connect("resized",self,"fit")
	connect("gui_input",self,"_gui")

func set_document(data: Dictionary, service):
	document=data
	sources=service
	rebuild()

func rebuild():
	if stage==null or document.empty(): return
	for child in stage.get_children():
		stage.remove_child(child)
		child.queue_free()
	widgets.clear()
	for item in document.widgets:
		var widget=Widget.new()
		widget.setup(item,sources,reference_size(),true)
		stage.add_child(widget)
		widgets[item.id]=widget
		widget.set_interactive(live and item.type=="media")
	# Control draw order follows sibling order in the shipped Godot 3 build.
	for item in document.widgets:
		if item.type=="fps": stage.move_child(widgets[item.id],stage.get_child_count()-1)
	place()

func reference_size() -> Vector2:
	return Doc.reference(document,get_viewport().get_visible_rect().size)

func place():
	if stage==null or document.empty(): return
	var reference=reference_size()
	factor=max(0.01,min((rect_size.x-40)/reference.x,(rect_size.y-40)/reference.y))*zoom
	origin=(rect_size-reference*factor)/2+pan
	stage.rect_position=origin
	stage.rect_size=reference
	stage.rect_scale=Vector2.ONE*factor
	for item in document.widgets:
		if not widgets.has(item.id): continue
		var widget=widgets[item.id]
		widget.rect_position=Vector2(item.x,item.y)*reference
		widget.rect_size=Vector2(item.w,item.h)*reference
		widget.rect_pivot_offset=widget.rect_size/2
		widget.visible=item.visible
		widget.rect_rotation=item.rotation
	update()
	emit_signal("view_changed")

func fit():
	zoom=1.0
	pan=Vector2.ZERO
	place()

func set_zoom(value: float):
	zoom=clamp(value,0.1,24)
	place()

func actual_size():
	var reference=reference_size()
	var fit_factor=max(0.01,min((rect_size.x-40)/reference.x,(rect_size.y-40)/reference.y))
	set_zoom(1.0/fit_factor)
	pan=Vector2.ZERO
	place()

func focus_selection():
	if selection.empty(): return
	var box=selected_rect()
	var reference=reference_size()
	var fit_factor=max(0.01,min((rect_size.x-40)/reference.x,(rect_size.y-40)/reference.y))
	var desired=min((rect_size.x-100)/max(1,box.size.x),(rect_size.y-100)/max(1,box.size.y))
	zoom=clamp(min(desired,2.0)/fit_factor,0.1,24)
	pan=(reference/2-box.position-box.size/2)*fit_factor*zoom
	place()

func set_preview(value: bool):
	live=value
	for widget in widgets.values(): widget.set_interactive(value and widget.item.type=="media")
	update()

func refresh_selected():
	for id in selection:
		if widgets.has(id): widgets[id].refresh()
	place()

func find_item(id: String) -> Dictionary:
	for item in document.get("widgets",[]):
		if item.id==id: return item
	return {}

func selected_rect() -> Rect2:
	var result=Rect2()
	var first=true
	var reference=reference_size()
	for id in selection:
		var item=find_item(id)
		if item.empty(): continue
		var box=Doc.rect(item,reference)
		result=box if first else result.merge(box)
		first=false
	return result

func _gui(event):
	if document.empty(): return
	if event is InputEventMouseButton:
		if event.button_index in [BUTTON_WHEEL_UP,BUTTON_WHEEL_DOWN] and event.pressed:
			set_zoom(zoom*(1.15 if event.button_index==BUTTON_WHEEL_UP else 1/1.15))
			accept_event()
			return
		if event.button_index==BUTTON_MIDDLE:
			panning=event.pressed
			accept_event()
			return
		if event.button_index!=BUTTON_LEFT: return
		if not event.pressed:
			if dragging or resizing:
				dragging=false
				resizing=false
				guides.clear()
				emit_signal("gesture_finished")
				update()
			return
		var point=(event.position-origin)/factor
		if event.doubleclick:
			focus_selection()
			return
		if key_mode and selection.size()==1:
			_key_begin(point)
			return
		bounds=selected_rect()
		var handle=Rect2(origin+(bounds.end)*factor-Vector2(6,6),Vector2(12,12))
		if not selection.empty() and handle.has_point(event.position):
			resizing=true
			_begin(point)
			return
		var hit=""
		var foreground=[]
		var regular=[]
		for i in range(document.widgets.size()-1,-1,-1):
			var item=document.widgets[i]
			(foreground if item.type=="fps" else regular).append(item)
		for item in foreground+regular:
			if not item.visible: continue
			var widget=widgets.get(item.id)
			if widget==null: continue
			var local=widget.get_transform().affine_inverse().xform(point)
			if Rect2(Vector2.ZERO,widget.rect_size).has_point(local):
				hit=item.id
				break
		if hit.empty():
			selection=[]
			emit_signal("selected")
			update()
			return
		var item=find_item(hit)
		if event.shift:
			if selection.has(hit): selection.erase(hit)
			else: selection.append(hit)
		elif not selection.has(hit): selection=[hit]
		if not item.group.empty() and not event.shift:
			for member in document.widgets:
				if member.group==item.group and not selection.has(member.id): selection.append(member.id)
		emit_signal("selected")
		if not item.locked and not selection.empty():
			dragging=true
			bounds=selected_rect()
			_begin(point)
		update()
	elif event is InputEventMouseMotion:
		if panning:
			pan+=event.relative
			place()
			return
		if not dragging and not resizing: return
		if key_mode:
			_key_move((event.position-origin)/factor)
			return
		var delta=(event.position-origin)/factor-start
		var reference=reference_size()
		if resizing:
			var size=Vector2(max(24,bounds.size.x+delta.x),max(24,bounds.size.y+delta.y))
			var ratio=size/bounds.size
			for id in originals:
				var item=find_item(id)
				if item.empty() or item.locked: continue
				var box=originals[id]
				if (event.shift or (item.type=="image" and item.source.aspect_lock)) and originals.size()==1:
					ratio=Vector2.ONE*max(ratio.x,ratio.y)
				Doc.set_rect(item,Rect2(bounds.position+(box.position-bounds.position)*ratio,box.size*ratio),reference)
		else:
			guides.clear()
			var destination=bounds.position+delta
			if snap and not event.alt: destination=_snapped(destination,bounds.size,reference)
			delta=destination-bounds.position
			for id in originals:
				var item=find_item(id)
				if not item.empty() and not item.locked: Doc.set_rect(item,Rect2(originals[id].position+delta,originals[id].size),reference)
		place()
		emit_signal("edited")

func _begin(point: Vector2):
	start=point
	originals.clear()
	var reference=reference_size()
	for id in selection:
		var item=find_item(id)
		if not item.empty(): originals[id]=Doc.rect(item,reference)
	emit_signal("gesture_started")

func _snapped(position: Vector2, size: Vector2, reference: Vector2) -> Vector2:
	var result=position.snapped(Vector2(8,8))
	var targets_x=[0.0,reference.x/2,reference.x]
	var targets_y=[0.0,reference.y/2,reference.y]
	for item in document.widgets:
		if selection.has(item.id) or not item.visible: continue
		var rect=Doc.rect(item,reference)
		targets_x.append(rect.position.x)
		targets_x.append(rect.end.x)
		targets_y.append(rect.position.y)
		targets_y.append(rect.end.y)
	var threshold=6.0/factor
	for pair in [[targets_x,0,size.x],[targets_y,1,size.y]]:
		var best=threshold
		var chosen=-1.0
		for target in pair[0]:
			for offset in [0.0,pair[2]/2,pair[2]]:
				var distance=abs(position[pair[1]]+offset-target)
				if distance<best:
					best=distance
					result[pair[1]]=target-offset
					chosen=target
		if chosen>=0: guides.append([pair[1],chosen])
	return result

func _key_begin(point: Vector2):
	var item=find_item(selection[0])
	if item.empty() or item.type!="keyboard": return
	var box=Doc.rect(item,reference_size())
	var pad=item.padding
	var area=box.grow(-pad)
	var normalized=(point-area.position)/area.size
	if key_selected>=0 and key_selected<item.source.keys.size():
		var key=item.source.keys[key_selected]
		var end=area.position+Vector2(key.x+key.w,key.y+key.h)*area.size
		if end.distance_to(point)<10/factor: resizing=true
	if not resizing:
		key_selected=-1
		for i in range(item.source.keys.size()-1,-1,-1):
			var key=item.source.keys[i]
			if Rect2(Vector2(key.x,key.y),Vector2(key.w,key.h)).has_point(normalized):
				key_selected=i
				break
	if key_selected>=0:
		start=normalized
		var key=item.source.keys[key_selected]
		originals={"key":Rect2(Vector2(key.x,key.y),Vector2(key.w,key.h))}
		dragging=not resizing
		emit_signal("gesture_started")
	emit_signal("selected")
	update()

func _key_move(point: Vector2):
	var item=find_item(selection[0])
	if key_selected<0 or key_selected>=item.source.keys.size(): return
	var area=Doc.rect(item,reference_size()).grow(-item.padding)
	var delta=(point-area.position)/area.size-start
	var key=item.source.keys[key_selected]
	var box=originals.key
	if resizing:
		key.w=max(0.04,box.size.x+delta.x)
		key.h=max(0.08,box.size.y+delta.y)
	else:
		var position=box.position+delta
		if snap: position=position.snapped(Vector2(0.025,0.05))
		key.x=position.x
		key.y=position.y
	widgets[item.id].update()
	update()
	emit_signal("edited")

func _draw():
	draw_rect(Rect2(Vector2.ZERO,rect_size),Galaxy.color("bg"))
	if document.empty(): return
	var box=Rect2(origin,reference_size()*factor)
	if background=="Checkerboard":
		var visible_area=box.clip(Rect2(Vector2.ZERO,rect_size))
		var first=(visible_area.position-box.position)/16
		var last=(visible_area.end-box.position)/16
		for y in range(max(0,int(floor(first.y))),int(ceil(last.y))):
			for x in range(max(0,int(floor(first.x))),int(ceil(last.x))):
				draw_rect(Rect2(box.position+Vector2(x,y)*16,Vector2(16,16)),Color("2b304b") if (x+y)%2==0 else Color("22263e"))
	elif background=="Solid colour": draw_rect(box,solid)
	elif background=="Live game" and game_texture!=null: draw_texture_rect(game_texture,box,false)
	else:
		draw_rect(box,Color("234d77"))
		if sample_texture!=null: draw_texture_rect(sample_texture,box,false)

	draw_rect(box,Galaxy.color("line"),false,1)
	for id in selection:
		var item=find_item(id)
		if item.empty(): continue
		var rect=Doc.rect(item,reference_size())
		draw_rect(Rect2(origin+rect.position*factor,rect.size*factor).grow(2),Galaxy.color("accent"),false,2)
	if not selection.empty():
		var rect=selected_rect()
		var handle=origin+rect.end*factor
		draw_rect(Rect2(handle-Vector2(5,5),Vector2(10,10)),Galaxy.color("accent"))
	for guide in guides:
		if guide[0]==0: draw_line(Vector2(origin.x+guide[1]*factor,origin.y),Vector2(origin.x+guide[1]*factor,box.end.y),Galaxy.color("star"),1)
		else: draw_line(Vector2(origin.x,origin.y+guide[1]*factor),Vector2(box.end.x,origin.y+guide[1]*factor),Galaxy.color("star"),1)
	if key_mode and selection.size()==1 and key_selected>=0:
		var item=find_item(selection[0])
		if not item.empty() and key_selected<item.source.keys.size():
			var key=item.source.keys[key_selected]
			var area=Doc.rect(item,reference_size()).grow(-item.padding)
			var key_box=Rect2(origin+(area.position+Vector2(key.x,key.y)*area.size)*factor,Vector2(key.w,key.h)*area.size*factor)
			draw_rect(key_box,Galaxy.color("star"),false,2)
			draw_rect(Rect2(key_box.end-Vector2(5,5),Vector2(10,10)),Galaxy.color("star"))
