extends Control
# Lightweight catalogue swatch. Full theme art is loaded only on selection.
var definition = {}
func _ready():
	rect_min_size.y = 68
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized",self,"update")
func _draw():
	var top = definition.get("top",Color("445277"))
	var bottom = definition.get("bottom",Color("8885aa"))
	for i in 32:
		draw_rect(Rect2(0,rect_size.y*i/32.0,rect_size.x,rect_size.y/32.0+1),top.linear_interpolate(bottom,i/31.0))
	var accent = definition.get("accent",Color("b49cff"))
	draw_line(Vector2(0,rect_size.y*0.78),Vector2(rect_size.x,rect_size.y*0.78),accent,3,true)
	for x in range(16,int(rect_size.x),26):
		draw_circle(Vector2(x,rect_size.y*0.35),2,Color(accent.r,accent.g,accent.b,0.5))
