extends Control
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
signal edited(points, finished)
signal selection_changed(index)
var mode = "curve"
var points = []
var selected = 0
var dragging = false
var font

func _init():
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	rect_min_size = Vector2(160,150)
	connect("resized",self,"update")

func set_points(value, kind = "curve"):
	mode = kind
	points = value.duplicate(true)
	selected = int(clamp(selected,0,max(0,points.size()-1)))
	rect_min_size.y = 86 if mode=="gradient" else 150
	hint_tooltip = "Click to add a stop · drag to move · right-click an inner stop to remove" if mode=="gradient" else "Double-click to add a point · drag to shape · right-click an inner point to remove"
	update()

func area() -> Rect2:
	return Rect2(12,14,max(1,rect_size.x-24),max(1,rect_size.y-38))

func location(point) -> Vector2:
	var a = area()
	return a.position+Vector2(float(point.t)*a.size.x,a.size.y+10 if mode=="gradient" else (1.0-float(point.v))*a.size.y)

func nearest(position) -> int:
	var best = -1
	var distance = 13.0
	for index in points.size():
		var current = position.distance_to(location(points[index]))
		if current<distance:
			distance = current
			best = index
	return best

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			grab_focus()
			var index = nearest(event.position)
			if event.button_index==BUTTON_RIGHT:
				if index>0 and index<points.size()-1:
					points.remove(index)
					selected = int(clamp(selected,0,points.size()-1))
					emit_signal("edited",points.duplicate(true),true)
			elif event.button_index==BUTTON_LEFT:
				if index<0 and (mode=="gradient" or event.doubleclick) and points.size()<Document.MAX_POINTS:
					var a = area()
					var t = clamp((event.position.x-a.position.x)/a.size.x,0.001,0.999)
					var point = {"t":t}
					if mode=="gradient": point.color = Document.color_hex(Document.sample_color(points,t))
					else: point.v = clamp(1-(event.position.y-a.position.y)/a.size.y,0,1)
					index = 1
					while index<points.size() and points[index].t<t: index+=1
					points.insert(index,point)
					emit_signal("edited",points.duplicate(true),false)
				if index>=0:
					selected = index
					dragging = true
					emit_signal("selection_changed",selected)
		else:
			if dragging and event.button_index==BUTTON_LEFT:
				dragging = false
				emit_signal("edited",points.duplicate(true),true)
		update()
		accept_event()
	elif event is InputEventMouseMotion and dragging and not points.empty():
		var a = area()
		if selected>0 and selected<points.size()-1:
			points[selected].t = clamp((event.position.x-a.position.x)/a.size.x,float(points[selected-1].t)+0.001,float(points[selected+1].t)-0.001)
		if mode=="curve": points[selected].v = clamp(1-(event.position.y-a.position.y)/a.size.y,0,1)
		emit_signal("edited",points.duplicate(true),false)
		update()
		accept_event()
	elif event is InputEventKey and event.pressed and event.scancode==KEY_DELETE:
		if selected>0 and selected<points.size()-1:
			points.remove(selected)
			selected = int(clamp(selected,0,points.size()-1))
			emit_signal("edited",points.duplicate(true),true)
			update()
		accept_event()

func _draw():
	draw_style_box(Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),0,10),Rect2(Vector2.ZERO,rect_size))
	var a = area()
	if mode=="gradient":
		for y in range(0,int(a.size.y),8):
			for x in range(0,int(a.size.x),8):
				draw_rect(Rect2(a.position+Vector2(x,y),Vector2(8,8)),Galaxy.color("surface" if (x/8+y/8)%2==0 else "line"))
		for index in 100:
			draw_rect(Rect2(a.position+Vector2(a.size.x*index/100.0,0),Vector2(a.size.x/100.0+1,a.size.y)),Document.sample_color(points,index/99.0))
	else:
		for i in 5:
			var t = i/4.0
			draw_line(a.position+Vector2(t*a.size.x,0),a.position+Vector2(t*a.size.x,a.size.y),Galaxy.color("border"),1,true)
			draw_line(a.position+Vector2(0,t*a.size.y),a.position+Vector2(a.size.x,t*a.size.y),Galaxy.color("border"),1,true)
		for index in range(1,points.size()): draw_line(location(points[index-1]),location(points[index]),Galaxy.color("accent"),2,true)
	for index in points.size():
		var at = location(points[index])
		var color = Document.color(points[index].color) if mode=="gradient" else Galaxy.color("accent")
		draw_circle(at,6 if index==selected else 4,Galaxy.color("ink"))
		draw_circle(at,4 if index==selected else 2.5,color)
	if font!=null:
		draw_string(font,Vector2(12,rect_size.y-4),"0",Galaxy.color("muted"))
		draw_string(font,Vector2(rect_size.x-30,rect_size.y-4),"1",Galaxy.color("muted"))
