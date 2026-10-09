extends Control
# A small drawn Goober for player lists: the player's body colour and a simple
# version of their hat. Art, not the real render.
const INK = Color("0e1c3c")
# head/<spine skin> keyword -> [shape, colour]. First match wins.
const HATS = [
	["king", "crown", "ffcf3a"], ["pharaoh", "crown", "3a7bd5"], ["top hat", "top", "2b2b3a"], ["wizard", "cone", "7b4dff"],
	["santa", "santa", "e53945"], ["sombrero", "brim", "e9c46a"], ["cowboy", "brim", "9c6b3e"], ["fedora", "brim", "6b6f7a"],
	["sherlock", "cap", "8d7a5a"], ["golf", "cap", "f4f1e8"], ["baseball", "cap", "2f6fdb"], ["cap stache", "cap", "e53945"],
	["police", "cap", "1f3a7a"], ["plumber", "cap", "e53945"], ["firefighter", "helmet", "e53945"], ["hard hat", "helmet", "ffc93c"],
	["football", "helmet", "3f7de0"], ["hockey", "helmet", "f4f1e8"], ["goalie", "helmet", "f4f1e8"], ["space", "helmet", "dfe8f5"],
	["robot", "helmet", "a7b4c6"], ["dark knight", "helmet", "3a3f55"], ["light knight", "helmet", "e7ecf3"], ["viking", "viking", "a7b4c6"],
	["devil", "horns", "e53945"], ["angel", "halo", "ffe066"], ["antennae", "antennae", "7bd88f"], ["flyhead", "antennae", "3a3f55"],
	["bunny", "bunny", "f7f2f7"], ["unicorn", "unicorn", "f7f2f7"], ["cat", "ears", "f2a65a"], ["dog", "ears", "9c6b3e"],
	["koala", "ears", "a7aab3"], ["lion", "mane", "e9a23b"], ["monkey", "ears", "8a5a3b"], ["panda", "ears", "2b2b3a"],
	["polar", "ears", "f4f1e8"], ["beaver", "ears", "8a5a3b"], ["horse", "ears", "9c6b3e"], ["dino", "spikes", "5fbf6a"],
	["toucan", "beak", "ff9f1c"], ["chicken", "comb", "e53945"], ["chef", "chef", "ffffff"], ["shower", "chef", "8fd3ff"],
	["headband", "band", "e53945"], ["sweatband", "band", "ffffff"], ["glasses", "glasses", "2b2b3a"], ["moustache", "stache", "5a3b2b"],
	["rainbow", "rainbow", "ff5f6d"], ["wig", "hair", "f5d36b"], ["perm", "hair", "8a5a3b"], ["pompadour", "hair", "2b2b3a"],
	["flower", "flower", "ff7eb6"], ["fairy", "flower", "b9a6ff"], ["pumpkin", "pumpkin", "ff8c1a"], ["skull", "hood", "3a3f55"],
	["clown", "clown", "ff3d3d"], ["scuba", "mask", "ffc93c"], ["aviator", "mask", "9c6b3e"], ["pirate", "pirate", "2b2b3a"],
	["feather", "cap", "3fa34d"], ["pencil", "pencil", "ffc93c"], ["baby", "band", "8fd3ff"],
]
var body = Color("ff69b4")
var dark = Color("c23b85")
var hat = ""
var hat_color = Color.white
var mouth = 0

static func hat_for(spine_name) -> Array:
	var key = str(spine_name).to_lower()
	for entry in HATS:
		if key.find(entry[0]) >= 0:
			return [entry[1], Color(entry[2])]
	return ["", Color.white]

func _draw():
	var s = min(rect_size.x, rect_size.y)
	var o = (rect_size - Vector2.ONE * s) * 0.5
	# Body: a bean in the lower part, leaving room for the hat.
	var bw = s * 0.64
	var bh = s * 0.74
	var bx = o.x + (s - bw) * 0.5
	var by = o.y + s * 0.22
	var top = Vector2(o.x + s * 0.5, by)
	_capsule(Rect2(bx - s * 0.035, by - s * 0.035, bw + s * 0.07, bh + s * 0.07), INK)
	_capsule(Rect2(bx, by + s * 0.05, bw, bh - s * 0.05), dark)
	_capsule(Rect2(bx, by, bw, bh - s * 0.07), body)
	_capsule(Rect2(bx + bw * 0.14, by + bh * 0.08, bw * 0.16, bh * 0.22), Color(1, 1, 1, 0.3))
	var eye_y = by + bh * 0.36
	if hat != "mask":
		for side in [-1, 1]:
			var eye = Vector2(top.x + side * bw * 0.2, eye_y)
			_oval(eye, Vector2(bw * 0.15, bh * 0.14), Color.white)
			_oval(eye + Vector2(bw * 0.03, bh * 0.025), Vector2(bw * 0.085, bh * 0.085), INK)
			draw_circle(eye + Vector2(bw * 0.06, -bh * 0.02), bw * 0.025, Color.white)
	var m = Vector2(top.x, by + bh * 0.6)
	if mouth == 0:
		draw_arc(m, bw * 0.12, 0.25, PI - 0.25, 12, INK, max(1.5, s * 0.04), true)
	elif mouth == 1:
		_oval(m + Vector2(0, bh * 0.03), Vector2(bw * 0.09, bh * 0.06), INK)
	else:
		draw_line(m + Vector2(-bw * 0.09, bh * 0.03), m + Vector2(bw * 0.09, bh * 0.03), INK, max(1.5, s * 0.04), true)
	_hat(top, bw, bh, s, eye_y)

func _hat(top, bw, bh, s, eye_y):
	var c = hat_color
	var line = max(1.5, s * 0.035)
	# Sit hats on the rounded crown instead of above it.
	if hat in ["crown", "top", "cone", "santa", "brim", "cap", "horns", "pirate", "chef", "comb", "spikes", "ears", "bunny", "unicorn", "flower", "pencil", "antennae"]:
		top += Vector2(0, s * 0.045)
	match hat:
		"crown":
			var pts = PoolVector2Array([top + Vector2(-bw * 0.32, s * 0.05), top + Vector2(-bw * 0.32, -s * 0.12), top + Vector2(-bw * 0.16, -s * 0.03),
				top + Vector2(0, -s * 0.17), top + Vector2(bw * 0.16, -s * 0.03), top + Vector2(bw * 0.32, -s * 0.12), top + Vector2(bw * 0.32, s * 0.05)])
			_shape(pts, c)
		"top":
			_box(Rect2(top + Vector2(-bw * 0.46, s * 0.0), Vector2(bw * 0.92, s * 0.06)), c)
			_box(Rect2(top + Vector2(-bw * 0.3, -s * 0.2), Vector2(bw * 0.6, s * 0.22)), c)
			_box(Rect2(top + Vector2(-bw * 0.3, -s * 0.06), Vector2(bw * 0.6, s * 0.04)), Color("e53945"))
		"cone", "santa":
			_shape(PoolVector2Array([top + Vector2(-bw * 0.4, s * 0.06), top + Vector2(bw * 0.12, -s * 0.22), top + Vector2(bw * 0.4, s * 0.06)]), c)
			if hat == "santa":
				_box(Rect2(top + Vector2(-bw * 0.44, s * 0.02), Vector2(bw * 0.88, s * 0.07)), Color.white)
				draw_circle(top + Vector2(bw * 0.12, -s * 0.22), s * 0.05, Color.white)
			else:
				draw_circle(top + Vector2(-bw * 0.02, -s * 0.05), s * 0.03, Color("ffe066"))
		"brim":
			_oval(top + Vector2(0, s * 0.04), Vector2(bw * 0.62, s * 0.05), c.darkened(0.15))
			_capsule(Rect2(top + Vector2(-bw * 0.28, -s * 0.12), Vector2(bw * 0.56, s * 0.17)), c)
		"cap":
			_capsule(Rect2(top + Vector2(-bw * 0.42, -s * 0.06), Vector2(bw * 0.84, s * 0.2)), c)
			_box(Rect2(top + Vector2(bw * 0.1, s * 0.06), Vector2(bw * 0.5, s * 0.05)), c.darkened(0.2))
		"helmet", "viking":
			_capsule(Rect2(top + Vector2(-bw * 0.52, -s * 0.06), Vector2(bw * 1.04, bh * 0.36)), c)
			_box(Rect2(top + Vector2(-bw * 0.5, bh * 0.2), Vector2(bw, s * 0.04)), c.darkened(0.25))
			if hat == "viking":
				for side in [-1, 1]:
					_shape(PoolVector2Array([top + Vector2(side * bw * 0.42, s * 0.04), top + Vector2(side * bw * 0.7, -s * 0.16), top + Vector2(side * bw * 0.48, -s * 0.02)]), Color("f4f1e8"))
		"horns":
			for side in [-1, 1]:
				_shape(PoolVector2Array([top + Vector2(side * bw * 0.12, s * 0.04), top + Vector2(side * bw * 0.34, -s * 0.13), top + Vector2(side * bw * 0.34, s * 0.06)]), c)
		"halo":
			draw_arc(top + Vector2(0, -s * 0.1), bw * 0.3, 0, TAU, 24, c, line * 1.4, true)
		"antennae":
			for side in [-1, 1]:
				draw_line(top + Vector2(side * bw * 0.12, s * 0.02), top + Vector2(side * bw * 0.26, -s * 0.16), INK, line, true)
				draw_circle(top + Vector2(side * bw * 0.26, -s * 0.16), s * 0.045, c)
		"bunny", "unicorn":
			if hat == "bunny":
				for side in [-1, 1]:
					_capsule(Rect2(top + Vector2(side * bw * 0.2 - bw * 0.09, -s * 0.22), Vector2(bw * 0.18, s * 0.28)), c)
					_capsule(Rect2(top + Vector2(side * bw * 0.2 - bw * 0.04, -s * 0.17), Vector2(bw * 0.08, s * 0.18)), Color("ffb3c6"))
			else:
				_shape(PoolVector2Array([top + Vector2(-bw * 0.08, s * 0.03), top + Vector2(0, -s * 0.2), top + Vector2(bw * 0.08, s * 0.03)]), Color("ffe066"))
		"ears":
			for side in [-1, 1]:
				draw_circle(top + Vector2(side * bw * 0.34, s * 0.03), s * 0.09, c)
				draw_circle(top + Vector2(side * bw * 0.34, s * 0.03), s * 0.045, c.lightened(0.3))
		"mane":
			for i in 7:
				var a = PI + PI * i / 6.0
				draw_circle(top + Vector2(cos(a) * bw * 0.5, s * 0.1 + sin(a) * bh * 0.2), s * 0.09, c)
		"spikes":
			for i in 3:
				var x = -bw * 0.2 + bw * 0.2 * i
				_shape(PoolVector2Array([top + Vector2(x - bw * 0.08, s * 0.03), top + Vector2(x, -s * 0.1), top + Vector2(x + bw * 0.08, s * 0.03)]), c)
		"beak":
			_oval(Vector2(top.x, eye_y + bh * 0.16), Vector2(bw * 0.2, bh * 0.09), c)
		"comb":
			for i in 3:
				draw_circle(top + Vector2(-bw * 0.1 + bw * 0.1 * i, -s * 0.03), s * 0.05, c)
		"chef":
			for p in [Vector2(-bw * 0.22, -s * 0.06), Vector2(0, -s * 0.12), Vector2(bw * 0.22, -s * 0.06)]:
				draw_circle(top + p, s * 0.1, c)
			_box(Rect2(top + Vector2(-bw * 0.32, -s * 0.03), Vector2(bw * 0.64, s * 0.08)), c)
		"band":
			_box(Rect2(top + Vector2(-bw * 0.48, bh * 0.12), Vector2(bw * 0.96, s * 0.07)), c)
		"glasses":
			for side in [-1, 1]:
				draw_arc(Vector2(top.x + side * bw * 0.2, eye_y), bw * 0.17, 0, TAU, 20, c, line, true)
			draw_line(Vector2(top.x - bw * 0.04, eye_y), Vector2(top.x + bw * 0.04, eye_y), c, line, true)
		"stache":
			for side in [-1, 1]:
				_oval(Vector2(top.x + side * bw * 0.1, eye_y + bh * 0.16), Vector2(bw * 0.12, bh * 0.05), c)
		"hair", "rainbow":
			var colors = [Color("ff5f6d"), Color("ffc93c"), Color("5fe3b8"), Color("7cc4ff"), Color("b9a6ff")] if hat == "rainbow" else [c, c, c, c, c]
			for i in 5:
				draw_circle(top + Vector2(-bw * 0.3 + bw * 0.15 * i, s * 0.02 - abs(i - 2) * -s * 0.01), s * 0.09, colors[i])
		"flower":
			var center = top + Vector2(bw * 0.24, -s * 0.02)
			for i in 5:
				draw_circle(center + Vector2(cos(TAU * i / 5.0), sin(TAU * i / 5.0)) * s * 0.06, s * 0.045, c)
			draw_circle(center, s * 0.035, Color("ffe066"))
		"pumpkin":
			_capsule(Rect2(top + Vector2(-bw * 0.5, -s * 0.06), Vector2(bw, bh * 0.4)), c)
			_box(Rect2(top + Vector2(-bw * 0.04, -s * 0.12), Vector2(bw * 0.08, s * 0.08)), Color("3fa34d"))
		"hood":
			_capsule(Rect2(top + Vector2(-bw * 0.56, -s * 0.06), Vector2(bw * 1.12, bh * 0.62)), c)
			_capsule(Rect2(top + Vector2(-bw * 0.38, bh * 0.12), Vector2(bw * 0.76, bh * 0.5)), body)
		"clown":
			for side in [-1, 1]:
				draw_circle(top + Vector2(side * bw * 0.42, s * 0.06), s * 0.1, Color("ff7eb6"))
			draw_circle(Vector2(top.x, eye_y + bh * 0.14), s * 0.05, c)
		"mask":
			_capsule(Rect2(Vector2(top.x - bw * 0.42, eye_y - bh * 0.13), Vector2(bw * 0.84, bh * 0.26)), c)
			_capsule(Rect2(Vector2(top.x - bw * 0.34, eye_y - bh * 0.08), Vector2(bw * 0.68, bh * 0.16)), Color("8fd3ff"))
		"pirate":
			_shape(PoolVector2Array([top + Vector2(-bw * 0.56, s * 0.05), top + Vector2(0, -s * 0.16), top + Vector2(bw * 0.56, s * 0.05)]), c)
			draw_circle(top + Vector2(0, -s * 0.04), s * 0.035, Color.white)
		"pencil":
			_box(Rect2(top + Vector2(-bw * 0.06, -s * 0.2), Vector2(bw * 0.12, s * 0.2)), c)

func _capsule(rect, color):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(min(rect.size.x, rect.size.y) * 0.5))
	style.corner_detail = 10
	style.anti_aliasing = true
	draw_style_box(style, rect)

func _box(rect, color):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(min(rect.size.x, rect.size.y) * 0.3))
	style.anti_aliasing = true
	draw_style_box(style, rect)

func _shape(points, color):
	draw_colored_polygon(points, color, PoolVector2Array(), null, null, true)
	var closed = PoolVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, INK, max(1.0, rect_size.y * 0.025), true)

func _oval(center, radius, color):
	draw_set_transform(center, 0, Vector2(1, radius.y / max(0.01, radius.x)))
	draw_circle(Vector2.ZERO, radius.x, color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
