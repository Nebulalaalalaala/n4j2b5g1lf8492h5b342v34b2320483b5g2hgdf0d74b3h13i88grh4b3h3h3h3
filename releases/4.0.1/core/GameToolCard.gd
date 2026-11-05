extends Button

# Game tools card: a glyph in a ring of the tool's colour. The ring fills in
# when the tool is on.
var symbol = "settings"
var active = false
var accent = Color("7fe0b4")

func _draw():
	var c = Vector2(rect_size.x*0.5,rect_size.y*0.36)
	var radius = min(rect_size.x,rect_size.y)*0.2
	draw_circle(c,radius+6,Color(accent.r,accent.g,accent.b,0.22 if active else 0.1))
	draw_arc(c,radius+6,0,TAU,48,Color(accent.r,accent.g,accent.b,0.9 if active else 0.35),2,true)
	var ink = accent.lightened(0.2) if active else Color("dfe6e1")
	var k = radius/26.0
	var paths = []
	match symbol:
		"optimizer":
			draw_arc(c,20*k,PI,TAU,32,ink,3,true)
			paths = [[-23,6,23,6],[0,0,11,-13]]
		"boost":
			paths = [[-14,-10,0,4],[0,4,-14,18],[2,-10,16,4],[16,4,2,18]]
		"dash":
			paths = [[5,-22,-9,1],[-9,1,7,1],[7,1,-4,22],[-23,-4,-15,-4],[-25,7,-17,7]]
		"local":
			draw_colored_polygon(PoolVector2Array([c+Vector2(-10,-17)*k,c+Vector2(17,0)*k,c+Vector2(-10,17)*k]),ink)
		"accounts", "name":
			draw_circle(c+Vector2(0,-10)*k,7*k,ink)
			draw_arc(c+Vector2(0,16)*k,15*k,PI,TAU,24,ink,3,true)
			if symbol == "name":
				paths = [[12,-18,22,-18],[17,-18,17,-8]]
		"emotes":
			draw_arc(c,19*k,0,TAU,36,ink,3,true)
			draw_circle(c+Vector2(-7,-5)*k,2,ink)
			draw_circle(c+Vector2(7,-5)*k,2,ink)
			draw_arc(c,10*k,0.2,PI-0.2,20,ink,3,true)
		"themes":
			paths = [[-22,14,-8,-6],[-8,-6,2,6],[2,6,10,-4],[10,-4,22,14],[-22,14,22,14]]
			draw_circle(c+Vector2(12,-16)*k,5*k,ink)
		"readout":
			draw_rect(Rect2(c+Vector2(-21,-14)*k,Vector2(42,28)*k),ink,false,3)
			paths = [[-13,6,-6,-2],[-6,-2,2,4],[2,4,13,-7]]
		_:
			for i in range(3):
				paths.append([-19,-12+i*12,19,-12+i*12])
				draw_circle(c+Vector2(-9+i*9,-12+i*12)*k,3.5*k,ink)
	for line in paths:
		draw_line(c+Vector2(line[0],line[1])*k,c+Vector2(line[2],line[3])*k,ink,3,true)
