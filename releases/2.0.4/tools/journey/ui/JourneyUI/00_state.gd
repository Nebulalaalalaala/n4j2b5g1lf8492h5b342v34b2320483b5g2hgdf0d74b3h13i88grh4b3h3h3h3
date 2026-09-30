extends Reference

# JourneyUI: shared state (variables, constants, signals, inner classes), in the original order.
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Journey design system: tokens, fonts, surfaces and small drawn components.
# Sizes are HomeScene logical units (1080x1920 base, stretch "expand"): a 1080p
# landscape screen shows ~3413x1920 units, so type starts at 26 units, not 17.

const INK = Color("002b57")
const NAVY = Color("062f5e")
const NAVY_2 = Color("0d3c72")
const NAVY_3 = Color("16528f")
const NAVY_DEEP = Color("021c3b")
const SKY_LIGHT = Color("b1deff")
const WHITE = Color("ffffff")
const MUTED = Color("a9cdf2")
const FAINT = Color("7099c7")
const PINK = Color("ff3896")
const PINK_LIGHT = Color("ff7ed3")
const YELLOW = Color("ffc40f")
const ORANGE = Color("ff9231")
const GREEN = Color("22c275")
const GREEN_LIGHT = Color("8af0b4")
const RED = Color("ff6b7d")

# Ribbon centre shared by every rank badge (see art/badges.py viewBox).
const RIBBON = Vector2(0.5, 0.7253)

const LEAGUES = {
	"bronze": {"base": Color("df8d52"), "light": Color("ffc796"), "deep": Color("6b3417")},
	"silver": {"base": Color("cfdbe8"), "light": Color("ffffff"), "deep": Color("3b4f6b")},
	"gold": {"base": Color("ffc629"), "light": Color("fff1a3"), "deep": Color("7a4d00")},
	"ruby": {"base": Color("ec3a57"), "light": Color("ff9aa9"), "deep": Color("6e0a24")},
	"sapphire": {"base": Color("3f82ee"), "light": Color("a9ceff"), "deep": Color("10286e")},
	"master": {"base": Color("9b5cf0"), "light": Color("dcc2ff"), "deep": Color("3a1575")},
	"king": {"base": Color("ffc629"), "light": Color("ffd0ec"), "deep": Color("0a2450")},
}

const TIERS = ["Silver", "Gold", "Ruby", "Sapphire", "Master", "Kingly"]
const TIER_ART = ["silver", "gold", "ruby", "sapphire", "master", "kingly"]
const CATEGORY = {
	"win": {"name": "Win XP", "icon": "crown", "color": Color("ffc40f")},
	"placement": {"name": "Placement XP", "icon": "podium", "color": Color("7fb4ff")},
	"exploration": {"name": "Exploration XP", "icon": "compass", "color": Color("5ee0c8")},
	"challenge": {"name": "Challenge XP", "icon": "target", "color": Color("ff7ed3")},
	"activity": {"name": "Activity XP", "icon": "clock", "color": Color("8af0b4")},
	"record": {"name": "Record XP", "icon": "stopwatch", "color": Color("ffb86b")},
}

var art
var reduced_motion = false
var _fonts = {}
var _inter_data = null
var _baloo_data = null

const ROLES = {
	"title": ["title", 64, 6], "hero": ["display", 92, 0], "h1": ["display", 52, 0],
	"h2": ["display", 42, 0], "h3": ["display", 34, 0], "num_xl": ["display", 76, 0],
	"num_l": ["display", 54, 0], "num_m": ["display", 40, 0], "caps": ["caps", 26, 0],
	"body": ["text", 29, 0], "small": ["text", 25, 0], "button": ["display", 32, 0],
}

class PBChart extends Control:
	var times = []
	var labels = []
	var color = Color.white
	var ui

	func _draw():
		var n = times.size()
		if n == 0:
			return
		var lo = times[0]
		var hi = times[0]
		for t in times:
			lo = min(lo, t)
			hi = max(hi, t)
		var pad = max((hi - lo) * 0.18, 0.05)
		lo -= pad
		hi += pad
		var f = ui.font("text", 24)
		var fb = ui.font("display", 28)
		var top = 44.0
		var bottom = rect_size.y - 44.0
		var left = 20.0
		var right = rect_size.x - 20.0
		for i in 4:
			var y = top + (bottom - top) * i / 3.0
			draw_line(Vector2(left, y), Vector2(right, y), Color(1, 1, 1, 0.06), 2.0)
		var points = PoolVector2Array()
		for i in n:
			var x = left + (right - left) * (0.5 if n == 1 else float(i) / (n - 1))
			var y = top + (bottom - top) * (hi - times[i]) / (hi - lo)
			points.append(Vector2(x, bottom - (y - top)))
		if n > 1:
			var fill = PoolVector2Array(points)
			fill.append(Vector2(points[n - 1].x, bottom))
			fill.append(Vector2(points[0].x, bottom))
			draw_colored_polygon(fill, Color(color.r, color.g, color.b, 0.10))
			draw_polyline(points, color, 5.0, true)
		for i in n:
			var last = i == n - 1
			draw_circle(points[i], 11.0 if last else 7.0, color if last else Color(1, 1, 1, 0.85))
			if last:
				draw_circle(points[i], 5.0, ui.NAVY)
			if i == 0 or last:
				var t = "%.3fs" % times[i]
				var m = fb.get_string_size(t)
				var x = clamp(points[i].x - m.x * 0.5, 0, rect_size.x - m.x)
				draw_string(fb, Vector2(x, points[i].y - 18), t, Color.white if last else Color(1, 1, 1, 0.6))
			if i < labels.size() and (n <= 8 or i == 0 or last or i % int(ceil(n / 6.0)) == 0):
				var lt = str(labels[i])
				var ml = f.get_string_size(lt)
				draw_string(f, Vector2(clamp(points[i].x - ml.x * 0.5, 0, rect_size.x - ml.x), rect_size.y - 8), lt, Color(1, 1, 1, 0.45))

class Bar extends Control:
	var ratio = 0.0 setget set_ratio
	var fill = Color.white
	var track = Color(0, 0, 0, 0.3)
	var ticks = 0

	func set_ratio(value):
		ratio = clamp(float(value), 0.0, 1.0)
		update()

	func _draw():
		var h = rect_size.y
		_pill(Rect2(Vector2.ZERO, rect_size), track, h * 0.5)
		if ratio > 0.0:
			var w = max(h, ratio * rect_size.x)
			_pill(Rect2(0, 0, w, h), fill, h * 0.5)
			_pill(Rect2(h * 0.3, h * 0.18, max(0, w - h * 0.6), h * 0.2), Color(1, 1, 1, 0.38), h * 0.1)
		for i in range(1, ticks):
			var x = rect_size.x * i / ticks
			draw_line(Vector2(x, h * 0.28), Vector2(x, h * 0.72), Color(0, 0.08, 0.2, 0.35), 3.0)

	func _pill(rect, color, radius):
		var s = StyleBoxFlat.new()
		s.bg_color = color
		s.set_corner_radius_all(int(radius))
		s.corner_detail = 10
		s.anti_aliasing = true
		draw_style_box(s, rect)

class Ring extends Control:
	var ratio = 0.0
	var color = Color.white
	var track = Color(1, 1, 1, 0.14)
	var width = 12.0

	func _draw():
		var c = rect_size * 0.5
		var r = min(rect_size.x, rect_size.y) * 0.5 - width * 0.5
		draw_arc(c, r, 0.0, TAU, 72, track, width, true)
		if ratio > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * ratio, 72, color, width, true)

class FlashRing extends Control:
	var progress = 0.0 setget set_progress
	var color = Color.white

	func set_progress(value):
		progress = value
		update()

	func _draw():
		if progress <= 0.0 or progress >= 1.0:
			return
		var c = rect_size * 0.5
		var radius = lerp(rect_size.x * 0.18, rect_size.x * 0.62, progress)
		var col = color
		col.a = 1.0 - progress
		draw_arc(c, radius, 0, TAU, 96, col, lerp(34.0, 4.0, progress), true)
		draw_circle(c, radius * 0.9, Color(1, 1, 1, 0.35 * (1.0 - progress) * (1.0 - progress)))

class Burst extends Control:
	# One-shot confetti burst from the centre; frees itself when done.
	var colors = [Color("ffc40f"), Color("ff3896"), Color("7fb4ff"), Color("22c275"), Color.white]
	var bits = []
	var age = 0.0
	var life = 1.6

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		for i in range(70):
			var a = rng.randf_range(-PI, 0.0) if i % 3 else rng.randf_range(-PI, PI)
			var speed = rng.randf_range(500, 1150)
			bits.append({"p": Vector2.ZERO, "v": Vector2(cos(a), sin(a)) * speed, "r": rng.randf() * TAU,
				"w": rng.randf_range(-9, 9), "s": Vector2(rng.randf_range(12, 22), rng.randf_range(7, 12)),
				"c": colors[i % colors.size()]})
		set_process(true)

	func _process(delta):
		age += delta
		for b in bits:
			b.v.y += 1500 * delta
			b.v *= 0.985
			b.p += b.v * delta
			b.r += b.w * delta
		update()
		if age >= life:
			queue_free()

	func _draw():
		var fade = clamp((life - age) / 0.5, 0.0, 1.0)
		var c0 = rect_size * 0.5
		for b in bits:
			draw_set_transform(c0 + b.p, b.r, Vector2.ONE)
			var col = b.c
			col.a = fade
			draw_rect(Rect2(-b.s * 0.5, b.s), col)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

class Glow extends Control:
	var texture
	var color = Color.white
	var scale_factor = 1.0

	func _draw():
		if texture == null:
			return
		var side = max(rect_size.x, rect_size.y) * scale_factor
		draw_texture_rect(texture, Rect2(rect_size * 0.5 - Vector2(side, side) * 0.5, Vector2(side, side)), false, color)

class Badge extends Control:
	var texture
	var text = ""
	var text_color = Color.white
	var pips = 0
	var pip_color = Color.white
	var ribbon = Vector2(0.5, 0.7253)
	var ui

	func _draw():
		if texture == null:
			return
		var side = min(rect_size.x, rect_size.y)
		var origin = (rect_size - Vector2(side, side)) * 0.5
		draw_texture_rect(texture, Rect2(origin, Vector2(side, side)), false)
		if text == "" or side < 88:
			return
		var f = ui.font("display", int(max(16, side * 0.074)))
		var measure = f.get_string_size(text)
		var centre = origin + ribbon * side
		var baseline = centre.y + (f.get_ascent() - f.get_descent()) * 0.5 - side * 0.004
		draw_string(f, Vector2(centre.x - measure.x * 0.5, baseline), text, text_color)
		if pips <= 0 or side < 170:
			return
		var d = side * 0.026
		var gap = side * 0.07
		for i in 3:
			var p = origin + Vector2(0.5 * side + (i - 1) * gap, 0.845 * side)
			var shape = PoolVector2Array([p + Vector2(0, -d * 1.3), p + Vector2(d, 0), p + Vector2(0, d * 1.3), p + Vector2(-d, 0)])
			var on = i < pips
			draw_colored_polygon(shape, pip_color if on else Color(0, 0.1, 0.25, 0.45))
			draw_polyline(shape + PoolVector2Array([shape[0]]), Color("002b57"), max(2.0, side * 0.007), true)

class Switch extends Control:
	signal toggled(on)
	var on = false
	var colors = []
	var _lit = false

	func _ready():
		connect("mouse_entered", self, "_set_lit", [true])
		connect("mouse_exited", self, "_set_lit", [false])
		connect("focus_entered", self, "_set_lit", [true])
		connect("focus_exited", self, "_set_lit", [false])

	func _set_lit(value):
		_lit = value
		update()

	func _gui_input(event):
		if (event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed) or event.is_action_pressed("ui_accept"):
			on = not on
			update()
			accept_event()
			emit_signal("toggled", on)

	func _draw():
		var h = rect_size.y
		var s = StyleBoxFlat.new()
		s.set_corner_radius_all(int(h * 0.5))
		s.anti_aliasing = true
		s.bg_color = colors[1] if on else colors[0]
		if _lit:
			s.border_width_left = 4
			s.border_width_right = 4
			s.border_width_top = 4
			s.border_width_bottom = 4
			s.border_color = colors[3]
		draw_style_box(s, Rect2(Vector2.ZERO, rect_size))
		var r = h * 0.5 - 7
		var x = rect_size.x - h * 0.5 if on else h * 0.5
		draw_circle(Vector2(x, h * 0.5 + 2), r, Color(0, 0.08, 0.2, 0.35))
		draw_circle(Vector2(x, h * 0.5), r, colors[2])

class Chart extends Control:
	var values = []
	var labels = []
	var missing = []
	var color = Color.white
	var highlight = -1
	var ui

	func _draw():
		var n = values.size()
		if n == 0:
			return
		var top = 0
		for v in values:
			top = max(top, int(v))
		var f = ui.font("text", 24)
		var fb = ui.font("display", 28)
		var label_h = 40.0
		var value_h = 40.0
		var plot_h = rect_size.y - label_h - value_h
		var slot = rect_size.x / n
		var w = min(72.0, slot * 0.58)
		for i in n:
			var x = slot * i + slot * 0.5
			var base = Rect2(x - w * 0.5, value_h, w, plot_h)
			var s = StyleBoxFlat.new()
			s.set_corner_radius_all(int(w * 0.32))
			s.anti_aliasing = true
			s.bg_color = Color(1, 1, 1, 0.06)
			draw_style_box(s, base)
			var is_missing = i in missing
			if not is_missing and top > 0 and int(values[i]) > 0:
				var h = max(w * 0.5, plot_h * float(values[i]) / top)
				s.bg_color = color if i == highlight or highlight < 0 else Color(0.36, 0.55, 0.8, 0.55)
				draw_style_box(s, Rect2(x - w * 0.5, value_h + plot_h - h, w, h))
				if i == highlight or highlight < 0:
					var t = ui.thousands(values[i])
					var m = fb.get_string_size(t)
					draw_string(fb, Vector2(x - m.x * 0.5, value_h + plot_h - h - 10), t, Color.white)
			elif is_missing:
				var q = "—"
				var mq = f.get_string_size(q)
				draw_string(f, Vector2(x - mq.x * 0.5, value_h + plot_h - 12), q, Color(1, 1, 1, 0.35))
			if i < labels.size():
				var lt = str(labels[i])
				var ml = f.get_string_size(lt)
				draw_string(f, Vector2(x - ml.x * 0.5, rect_size.y - 8), lt, Color.white if i == highlight else Color(0.66, 0.8, 0.95))
