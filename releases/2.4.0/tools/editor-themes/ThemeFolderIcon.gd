extends Control
var color := Color("8ec9ff")

const INK = Color("002b57")
const OUTLINE = 5.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized", self, "update")

# Rounded polygon: each corner is replaced by a short arc.
func _rounded(points: Array, radius: float) -> PoolVector2Array:
	var out := PoolVector2Array()
	var count: int = points.size()
	for i in count:
		var p: Vector2 = points[i]
		var a: Vector2 = (points[(i - 1 + count) % count] - p).normalized()
		var b: Vector2 = (points[(i + 1) % count] - p).normalized()
		var r: float = min(radius, min(p.distance_to(points[(i - 1 + count) % count]), p.distance_to(points[(i + 1) % count])) * 0.45)
		var start: Vector2 = p + a * r
		var end: Vector2 = p + b * r
		for s in 7:
			var t: float = s / 6.0
			out.append(start.linear_interpolate(p, t).linear_interpolate(p.linear_interpolate(end, t), t))
	return out

func _shape(points: Array, radius: float, fill: Color, outline := true) -> void:
	var shape: PoolVector2Array = _rounded(points, radius)
	if outline:
		for ring in Geometry.offset_polygon_2d(shape, OUTLINE, Geometry.JOIN_ROUND):
			draw_colored_polygon(ring, INK)
	draw_colored_polygon(shape, fill)

func _sheet(center: Vector2, size: Vector2, angle: float, fill: Color) -> void:
	var points := []
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(center + (corner * size * 0.5).rotated(angle))
	_shape(points, 6.0, fill)

func _draw() -> void:
	var unit: float = min(rect_size.x / 180.0, rect_size.y / 132.0)
	var offset: Vector2 = (rect_size - Vector2(180, 132) * unit) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * unit)
	# Soft shadow under the folder.
	_shape([Vector2(18, 118), Vector2(162, 118), Vector2(158, 128), Vector2(22, 128)], 6.0, Color(0, 0.1, 0.25, 0.35), false)
	# Back with its tab.
	_shape([Vector2(12, 12), Vector2(70, 12), Vector2(82, 26), Vector2(168, 26), Vector2(168, 114), Vector2(12, 114)], 12.0, color.darkened(0.3))
	# Sheets peeking out.
	_sheet(Vector2(84, 52), Vector2(104, 48), -0.06, Color("f5fbff"))
	_sheet(Vector2(100, 56), Vector2(100, 46), 0.06, color.lightened(0.62))
	# Front flap, slightly narrower at the bottom like an open folder.
	_shape([Vector2(6, 56), Vector2(174, 56), Vector2(165, 116), Vector2(15, 116)], 12.0, color)
	# Gloss along the top of the flap and a darker base.
	draw_colored_polygon(_rounded([Vector2(15, 62), Vector2(165, 62), Vector2(164, 74), Vector2(16, 74)], 6.0), color.lightened(0.3))
	draw_colored_polygon(_rounded([Vector2(19, 100), Vector2(161, 100), Vector2(160, 110), Vector2(20, 110)], 5.0), color.darkened(0.12))
	# Small shine in the corner.
	draw_circle(Vector2(26, 86), 4.5, Color(1, 1, 1, 0.75))
	draw_circle(Vector2(38, 84), 2.5, Color(1, 1, 1, 0.6))
