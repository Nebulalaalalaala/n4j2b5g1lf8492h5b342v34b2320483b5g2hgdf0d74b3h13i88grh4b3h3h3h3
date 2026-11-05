extends Control
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
var document = {}
func _ready():
	rect_min_size.y = 76
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized",self,"update")
func _draw():
	if document.empty(): return
	var gradient = document.layers[0].gradient
	for i in 28:
		var a = i/28.0
		var b = (i+1)/28.0
		var first = Vector2(12+a*(rect_size.x-24),rect_size.y*0.5+sin(a*TAU)*16)
		var next = Vector2(12+b*(rect_size.x-24),rect_size.y*0.5+sin(b*TAU)*16)
		draw_line(first,next,Document.sample_color(gradient,a),3,true)
		if i%4==0: draw_circle(first+Vector2(0,-10-i%3*3),2,Document.sample_color(gradient,a))
