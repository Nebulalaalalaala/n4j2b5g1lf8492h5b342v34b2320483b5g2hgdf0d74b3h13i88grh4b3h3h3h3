extends Control

# The welcome banner: a rounded night-sky gradient with stars, two small
# planets and twinkling sparkles. Drawn in code, so it stays sharp at any size.
# Twinkling runs only while the banner is visible and Reduced motion is off.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const CORNER = 14.0

var stars = []
var sparkles = []
var animate = true

func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_clip_content = true
	var rng = RandomNumberGenerator.new()
	rng.seed = 11
	for i in range(46):
		stars.append([Vector2(rng.randf_range(0.32, 1.0), rng.randf_range(0.04, 0.96)), rng.randf_range(0.8, 1.9), rng.randf_range(0.4, 1.0)])
	# x, y (0..1), radius, colour key, phase
	for entry in [[0.45, 0.2, 7.0, "gold", 0.0], [0.6, 0.78, 5.0, "white", 1.2], [0.68, 0.17, 8.0, "gold", 2.4], [0.745, 0.5, 4.0, "pink", 0.6], [0.985, 0.29, 7.0, "gold", 1.8], [0.96, 0.84, 5.0, "pink", 3.0], [0.54, 0.41, 3.5, "white", 2.0], [0.715, 0.89, 4.0, "gold", 0.9]]:
		sparkles.append(entry)

func _ready():
	connect("visibility_changed", self, "_sync_process")
	connect("resized", self, "update")
	_sync_process()

func _sync_process():
	set_process(animate and is_visible_in_tree() and not bool(SavedSettings.get_value("workspace_reduced_motion", false)))

func _process(_delta):
	update()

func _rounded(rect: Rect2, radius: float) -> PoolVector2Array:
	var points = PoolVector2Array()
	var r = min(radius, min(rect.size.x, rect.size.y) * 0.5)
	var corners = [[rect.position + Vector2(rect.size.x - r, r), -PI / 2], [rect.position + rect.size - Vector2(r, r), 0.0], [rect.position + Vector2(r, rect.size.y - r), PI / 2], [rect.position + Vector2(r, r), PI]]
	for corner in corners:
		for step in range(7):
			var angle = corner[1] + step * (PI / 2) / 6.0
			points.append(corner[0] + Vector2(cos(angle), sin(angle)) * r)
	return points

func _band_color(x: float) -> Color:
	var a = Galaxy.color("band_a")
	var b = Galaxy.color("band_b")
	var c = Galaxy.color("band_c")
	return a.linear_interpolate(b, x * 2.0) if x < 0.5 else b.linear_interpolate(c, (x - 0.5) * 2.0)

func _sparkle(center: Vector2, radius: float, color: Color) -> void:
	var points = PoolVector2Array()
	for i in range(8):
		var angle = i * PI / 4.0 - PI / 2
		var length = radius if i % 2 == 0 else radius * 0.24
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)

func _draw():
	var size = rect_size
	if size.x < 4 or size.y < 4:
		return
	var outline = _rounded(Rect2(Vector2.ZERO, size), CORNER)
	var colors = PoolColorArray()
	for point in outline:
		colors.append(_band_color(point.x / size.x))
	draw_polygon(outline, colors)
	var light = Galaxy.is_light()
	# Soft glows: pink on the right, cyan near the top middle.
	for glow in [[Vector2(0.86, 0.55), 0.3, Color(1.0, 0.72, 0.91, 0.16 if not light else 0.3)], [Vector2(0.6, 0.15), 0.2, Color(0.62, 0.89, 1.0, 0.12 if not light else 0.25)]]:
		for ring in range(6):
			var t = 1.0 - ring / 6.0
			draw_circle(Vector2(glow[0].x * size.x, glow[0].y * size.y), glow[1] * size.y * 2.2 * t, Color(glow[2].r, glow[2].g, glow[2].b, glow[2].a / 6.0))
	var dot = Galaxy.color("dot")
	for star in stars:
		draw_circle(Vector2(star[0].x * size.x, star[0].y * size.y), star[1], Color(dot.r, dot.g, dot.b, star[2] * (0.75 if light else 1.0)))
	# Ringed pink planet and a small blue one.
	var planet = Vector2(0.64 * size.x, 0.66 * size.y)
	# Ring as a tilted ellipse: back half, planet, then front half.
	draw_set_transform(planet, -0.25, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, 24, PI, TAU, 28, Color("ffe4a8"), 6.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(planet, 11, Color("c46bdd"))
	draw_circle(planet + Vector2(-3, -3), 7, Color("f08ccb"))
	draw_circle(planet + Vector2(-4, -4), 2.5, Color(1, 1, 1, 0.6))
	draw_set_transform(planet, -0.25, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, 24, 0.0, PI, 28, Color("fff0c8"), 6.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var moon = Vector2(0.972 * size.x, 0.74 * size.y)
	draw_circle(moon, 7, Color("3b6cc8"))
	draw_circle(moon + Vector2(-1.5, -1.5), 5, Color("7ccdf5"))
	draw_circle(moon + Vector2(-2.5, -2.5), 1.6, Color(1, 1, 1, 0.7))
	var time = OS.get_ticks_msec() / 1000.0
	var palette = {"gold": Color("ffe38a"), "white": Color(1, 1, 1) if not light else Color("c9b6ff"), "pink": Color("ffc2e6")}
	for spark in sparkles:
		var pulse = 0.65 + 0.35 * sin(time * 1.75 + spark[4]) if is_processing() else 1.0
		var tint = palette[spark[3]]
		_sparkle(Vector2(spark[0] * size.x, spark[1] * size.y), spark[2] * (0.7 + 0.3 * pulse), Color(tint.r, tint.g, tint.b, pulse))
	# Thin light rim on the top edge so the banner reads as a ledge.
	draw_line(Vector2(CORNER, 0.5), Vector2(size.x - CORNER, 0.5), Color(1, 1, 1, 0.3), 1.0)
