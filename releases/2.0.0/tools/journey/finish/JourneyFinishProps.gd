extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Props for Journey finish animations, drawn in GooberDash's flat style: bright
# fills, a dark navy outline and one soft highlight. Sizes are in pixels and
# set from the Goober's height by the choreography.

# Pre-rendered prop art (journey-assets/finish_*.png), loaded once per node.
static func sheet(base_dir, key):
	var image = Image.new()
	if image.load(ModPaths.JOURNEY_ASSETS_DIR + key + ".png") != OK:
		return null
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return texture

# The ride-on star (Star Ride): a plump star seen from the front, like a warp
# star. It is drawn over the rider, who sits behind its top point.
class RideStar extends Node2D:
	const PX_PER_RADIUS = 250.0      # finish_star.png: plump star seen from the front
	const ART_DY = -10.0             # image centre relative to the star centre
	var radius = 60.0
	var glow = 0.0
	var trail = []
	var phase = 0.0
	var back
	func setup(base_dir):
		var props = load(ModPaths.path("JourneyFinishProps.gd"))
		back = Sprite.new()
		back.texture = props.sheet(base_dir, "finish_star")
		back.offset = Vector2(0, ART_DY)
		add_child(back)
		return null
	func seat():
		return Vector2.ZERO
	func _process(_delta):
		if back != null:
			sync()
	func push_trail(point):
		trail.push_front(point)
		if trail.size() > 18:
			trail.pop_back()
	func sync():
		back.scale = Vector2.ONE * radius / PX_PER_RADIUS
		back.modulate = Color(1, 1, 1).linear_interpolate(Color(1.2, 1.16, 1.05), glow)
		update()
	func _draw():
		for i in range(trail.size()):
			var k = 1.0 - float(i) / 18.0
			var p = to_local(trail[i])
			_sparkle(p + Vector2(sin(i * 2.3) * radius * 0.4, radius * 0.3 + cos(i * 1.7) * radius * 0.15), radius * 0.13 * k, Color(1, 0.95, 0.65, 0.75 * k))
		for i in range(3):
			var a = phase * 1.6 + i * TAU / 3.0
			_sparkle(Vector2(cos(a) * radius * 1.15, sin(a) * radius * 0.5 + radius * 0.1), radius * 0.1, Color(1, 1, 0.9, 0.5 + 0.5 * sin(phase * 5.0 + i)))
	func _sparkle(at, size, color):
		if size < 0.6:
			return
		draw_colored_polygon(PoolVector2Array([at + Vector2(0, -size), at + Vector2(size * 0.28, 0), at + Vector2(0, size), at + Vector2(-size * 0.28, 0)]), color)
		draw_colored_polygon(PoolVector2Array([at + Vector2(-size, 0), at + Vector2(0, size * 0.28), at + Vector2(size, 0), at + Vector2(0, -size * 0.28)]), color)

# The rider's hands clasping the star (Star Ride): two white nubs drawn over
# the star at the arm tips. Follows the rider's transform; positions are in
# skeleton units (y up), measured on the real rig for the seated pose.
class RideHands extends Node2D:
	const TIPS = [Vector2(219, 578), Vector2(-243, 563)]
	const WIDTH = 72.0
	const REACH = 46.0
	var k = 0.1                   # skeleton units -> px
	var alpha = [1.0, 1.0]
	func _draw():
		for i in range(2):
			if alpha[i] <= 0.01:
				continue
			var a = Vector2(TIPS[i].x, -TIPS[i].y) * k
			var s = 1.0 if TIPS[i].x > 0.0 else -1.0
			var b = a + Vector2(-s, 1.0) * REACH * k
			var c = Color(1, 1, 1, alpha[i])
			draw_line(a, b, c, WIDTH * k)
			draw_circle(a, WIDTH * k * 0.5, c)
			draw_circle(b, WIDTH * k * 0.5, c)

# The ride-on rocket (Rocket Ride), side view, nose along local +x. A barrel
# roll flips it through its width; the rider goes behind it on the far side.
class Rocket extends Node2D:
	const PX_PER_UNIT = 620.0
	const ART_X0 = 420.0 - 450.0     # image x of the rocket's x = 0, from centre
	const BODY_R = 0.15
	const SEAT_X = -0.08
	var length = 120.0            # on-screen length, nozzle to nose
	var thrust = 0.5
	var phase = 0.0
	var roll = 0.0
	var back
	var flame
	func setup(base_dir):
		var props = load(ModPaths.path("JourneyFinishProps.gd"))
		flame = Sprite.new()
		flame.texture = props.sheet(base_dir, "finish_flame")
		flame.centered = false
		add_child(flame)
		back = Sprite.new()
		back.texture = props.sheet(base_dir, "finish_rocket")
		back.offset = Vector2(-ART_X0, 0)
		add_child(back)
		return null
	func unit():
		return length / 1.2
	func _process(_delta):
		if back != null:
			sync()
	# Seat on the rocket's back for the current roll, in local pixels.
	func seat():
		return Vector2(SEAT_X, -BODY_R * _roll_scale()) * unit()
	func _roll_scale():
		var c = cos(roll)
		return c if abs(c) > 0.04 else (0.04 if c >= 0.0 else -0.04)
	func rider_behind():
		return sin(roll) < -0.35
	func sync():
		var k = unit() / PX_PER_UNIT
		back.scale = Vector2(k, k * _roll_scale())
		var flick = 0.85 + 0.1 * sin(phase * 43.0) + 0.05 * sin(phase * 27.0)
		var fl = unit() * (0.25 + 0.55 * thrust) * flick
		var fw = unit() * (0.15 + 0.04 * thrust) * max(0.3, abs(cos(roll)))
		flame.position = Vector2(-0.58 * unit() - fl, -fw * 0.5)
		flame.scale = Vector2(fl / 256.0, fw / 128.0)

# The star portal (approved prototype look): star silhouette, dark swirling
# centre, cyan rim and orbiting sparkles. Radius 100 in local space.
class StarPortal extends Node2D:
	var open = 0.0
	var phase = 0.0
	var fill
	func _ready():
		fill = Polygon2D.new()
		var vertices = PoolVector2Array()
		var uv = PoolVector2Array()
		for i in range(10):
			var a = -PI * .5 + i * PI / 5.0
			var point = Vector2(cos(a), sin(a)) * (100.0 if i % 2 == 0 else 52.0)
			vertices.append(point)
			uv.append(point / 200.0 + Vector2(.5, .5))
		fill.polygon = vertices
		fill.uv = uv
		var white = Image.new()
		white.create(1, 1, false, Image.FORMAT_RGBA8)
		white.fill(Color.white)
		var texture = ImageTexture.new()
		texture.create_from_image(white)
		fill.texture = texture
		var shader = Shader.new()
		shader.code = """shader_type canvas_item;
uniform float phase = 0.0;
void fragment() {
 vec2 p = UV * 2.0 - 1.0;
 float r = length(p);
 float a = atan(p.y,p.x);
 float spiral = pow(max(0.0, sin(a * 4.0 + r * 15.0 - phase * 5.0)), 5.0);
 float haze = .5 + .5 * sin(a * 7.0 - r * 21.0 + phase * 2.0);
 vec3 col = mix(vec3(.005,.018,.08),vec3(.015,.18,.43), smoothstep(.04,.75,r));
 col += vec3(.02,.43,.63) * spiral * smoothstep(.12,.65,r);
 col += vec3(.01,.04,.08) * haze;
 COLOR = vec4(col,1.0) * COLOR;
}"""
		fill.material = ShaderMaterial.new()
		fill.material.shader = shader
		fill.show_behind_parent = true
		fill.scale = Vector2.ONE * 0.001
		add_child(fill)
	func refresh():
		if fill != null:
			fill.scale = Vector2.ONE * max(0.001, open)
			fill.material.set_shader_param("phase", phase)
		update()
	func _draw():
		if open <= 0.001:
			return
		var points = PoolVector2Array()
		for i in range(10):
			var a = -PI * .5 + i * PI / 5.0
			points.append(Vector2(cos(a), sin(a)) * (100.0 if i % 2 == 0 else 52.0) * open)
		points.append(points[0])
		for spec in [[16, Color(.05,.7,1,.06)], [9, Color(.1,.8,1,.15)], [4, Color(.2,.9,1,.85)], [1.5, Color(.85,1,1,1)]]:
			draw_polyline(points, spec[1], spec[0] * open, true)
		for i in range(12):
			var angle = i * TAU / 12.0 + phase * .65
			var radius = 108.0 + sin(phase * 3 + i) * 8.0
			var p = Vector2(cos(angle), sin(angle)) * radius * open
			var s = (2.0 + float(i % 3)) * open
			draw_line(p - Vector2(s,0), p + Vector2(s,0), Color(.55,.95,1,.65), 1.0, true)
			draw_line(p - Vector2(0,s), p + Vector2(0,s), Color(.55,.95,1,.65), 1.0, true)

# Short-lived sparkle/confetti burst in local space.
class Burst extends Node2D:
	var life = 0.0
	var parts = []
	var size = 8.0
	func start(count, speed, colors):
		for i in range(count):
			var a = randf() * TAU
			parts.append({"v": Vector2(cos(a), sin(a)) * speed * rand_range(0.5, 1.0), "c": colors[i % colors.size()]})
	func advance(delta):
		life += delta
		update()
		return life < 0.9
	func _draw():
		for p in parts:
			var pos = p.v * life + Vector2(0, 25.0 * size * life * life)
			var k = 1.0 - life / 0.9
			var s = size * k
			if s < 0.6:
				continue
			draw_colored_polygon(PoolVector2Array([pos + Vector2(0, -s), pos + Vector2(s * 0.3, 0), pos + Vector2(0, s), pos + Vector2(-s * 0.3, 0)]), Color(p.c.r, p.c.g, p.c.b, k))
