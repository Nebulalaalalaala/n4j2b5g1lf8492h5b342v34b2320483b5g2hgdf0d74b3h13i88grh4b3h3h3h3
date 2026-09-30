extends Button

var symbol = "settings"
var active = false

func _draw():
	var c = Vector2(rect_size.x*0.5,rect_size.y*0.34)
	var ink = Color("65d5bc") if active else Color("cad9e4")
	var paths = []
	match symbol:
		"optimizer":
			draw_arc(c,22,PI,TAU,32,ink,3,true)
			paths = [[-25,6,25,6],[0,0,12,-14]]
		"dash":
			paths = [[5,-24,-10,1],[-10,1,8,1],[8,1,-5,24],[-25,-4,-16,-4],[-28,7,-19,7]]
		"local":
			draw_colored_polygon(PoolVector2Array([c+Vector2(-12,-20),c+Vector2(20,0),c+Vector2(-12,20)]),ink)
		"accounts", "name":
			draw_circle(c+Vector2(0,-12),8,ink)
			draw_arc(c+Vector2(0,18),17,PI,TAU,24,ink,3,true)
			if symbol == "name":
				paths = [[13,-20,25,-20],[19,-20,19,-9]]
		"emotes":
			draw_arc(c,22,0,TAU,36,ink,3,true)
			draw_circle(c+Vector2(-8,-6),2,ink)
			draw_circle(c+Vector2(8,-6),2,ink)
			draw_arc(c,12,0.2,PI-0.2,20,ink,3,true)
		_:
			for i in range(3):
				paths.append([-22,-14+i*14,22,-14+i*14])
				draw_circle(c+Vector2(-10+i*10,-14+i*14),4,ink)
	for line in paths:
		draw_line(c+Vector2(line[0],line[1]),c+Vector2(line[2],line[3]),ink,3,true)
