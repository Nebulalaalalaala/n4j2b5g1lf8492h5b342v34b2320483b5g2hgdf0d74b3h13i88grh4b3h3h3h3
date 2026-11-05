extends Node2D

# Avatar Studio effects (local only): animated VFX drawn around the Goober.
# This node draws the layers behind the Goober; a sibling ("...Front") draws
# the layers in front. Each has an additive child for light.
# Positions are in the Goober's setup pose (skeleton units, y down) and ride
# the chest, head and feet bones.

# "hue": main hue, used to move the effect onto another colour; "mono": no
# single hue (rainbow, black/white), so another colour tints it instead.
const ITEMS = {
	"studio_fx_wings_small": {"name": "Black Wings S", "wings": "small"},
	"studio_fx_wings_medium": {"name": "Black Wings M", "wings": "medium"},
	"studio_fx_wings_large": {"name": "Black Wings L", "wings": "large"},
	"studio_fx_cursed_horns": {"name": "Cursed Horns", "hue": 0.61},
	"studio_fx_halley": {"name": "Halley's Comet", "hue": 0.76},
	"studio_fx_selene": {"name": "Selene's Grace", "hue": 0.71},
	"studio_fx_abyssal": {"name": "Abyssal Rapture", "hue": 0.79},
	"studio_fx_bfly_eclipse": {"name": "Eclipse Butterfly", "mono": true, "wing": ["050508", "15151c", "f4f6ff", "ffffff"]},
	"studio_fx_bfly_azure": {"name": "Azure Butterfly", "hue": 0.58, "wing": ["041a52", "1a86ff", "9ff0ff", "5fd2ff"]},
	"studio_fx_bfly_crimson": {"name": "Crimson Butterfly", "hue": 0.99, "wing": ["240003", "d80f1c", "ffb38a", "ff4a3a"]},
	"studio_fx_bfly_orchid": {"name": "Orchid Butterfly", "hue": 0.78, "wing": ["1c053a", "a23aff", "ffc6f4", "e07cff"]},
	"studio_fx_refractions": {"name": "Refractions", "mono": true},
	"studio_fx_falling_star": {"name": "Falling Star", "hue": 0.77},
	"studio_fx_bolt_skaters": {"name": "Bolt Skaters", "hue": 0.55},
	"studio_fx_star_eruption": {"name": "Orange Star Eruption", "hue": 0.08},
	"studio_fx_headphones": {"name": "Headphone Resonance", "mono": true},
}
const RECOLOR = """shader_type canvas_item;
%s
uniform float mode = 0.0;
uniform float shift = 0.0;
uniform float sat = 1.0;
uniform vec3 tint = vec3(1.0);
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (mode > 1.5) {
		float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		c.rgb = mix(tint * l * 1.7, vec3(1.0), smoothstep(0.7, 1.0, l));
	} else if (mode > 0.5) {
		vec3 h = rgb2hsv(c.rgb);
		h.x = fract(h.x + shift);
		h.y = clamp(h.y * sat, 0.0, 1.0);
		c.rgb = hsv2rgb(h);
	}
	COLOR = c;
}
"""

# Live bone frames in setup pose (UPGUY.skel, in the runtime's y-down convention).
const SETUP = {
	"bone4": [Vector2(-0.002, -1.0), Vector2(-1.0, 0.002), Vector2(-1.16, -816.64)],
	"bone7": [Vector2(-0.002, -1.0), Vector2(-1.0, 0.002), Vector2(-2.53, -1512.2)],
	"bone11": [Vector2(0.947, 0.3212), Vector2(0.3212, -0.947), Vector2(334.43, -25.05)],
	"bone14": [Vector2(-0.974, 0.2266), Vector2(0.2266, 0.974), Vector2(-345.13, -29.38)],
}
const TAU2 = PI * 2.0
const DEFAULTS = {"rot": 0.0, "v": Vector2.ZERO, "g": Vector2.ZERO, "drag": 0.0, "wave": 0.0, "wamp": 200.0, "spin": 0.0, "fin": 0.12, "fout": 1.0, "cm": null, "tw": 0.0, "depth": 1.0, "orbit": null, "add": true, "world": false, "layer": 1, "aspect": Vector2.ONE, "stretch": 0.0}
const ORBIT_DEFAULTS = {"dr": 0.0, "dy": 0.0, "lean": 0.0}
# Goober shape in setup pose: head is a circle on top of the capsule.
const HEAD = Vector2(-20, -1354)
const HEAD_R = 556.0
const TOP = Vector2(-20, -1910)

# Fixed fields let the hot simulation/draw loops use indexed script members
# instead of hashing dozens of Dictionary keys for every particle every tick.
class Particle:
	extends Reference
	var tex: String = ""
	var id: String = ""
	var p: Vector2 = Vector2.ZERO
	var v: Vector2 = Vector2.ZERO
	var g: Vector2 = Vector2.ZERO
	var age: float = 0.0
	var life: float = 1.0
	var rot: float = 0.0
	var spin: float = 0.0
	var drag: float = 0.0
	var wave: float = 0.0
	var wamp: float = 200.0
	var fin: float = 0.12
	var fout: float = 1.0
	var tw: float = 0.0
	var ph: float = 0.0
	var depth: float = 1.0
	var s0: float = 1.0
	var s1: float = 1.0
	var stretch: float = 0.0
	var aspect: Vector2 = Vector2.ONE
	var c0: Color = Color.white
	var c1: Color = Color.white
	var cm = null
	var orbit = null
	var add: bool = true
	var world: bool = false
	var land: bool = false
	var double: bool = false
	var layer: int = 1
	func _init(data: Dictionary):
		for key in data: set(key,data[key])

var target = null
var ids = []
var t = 0.0
var front = null
var layers = []           # [back, back_add, front, front_add]
var parts = []
var trails = {}
var bolts = {}
var _bones = {}
var _delta = {}
var _last = null
var _vel = Vector2.ZERO
var _emit = {}
var _beat_prev = 0.0
var _raise = 0.0
var _px = 1.0
var _inv = Transform2D.IDENTITY
var _mp = []
var _mc = []
var _mi = []
var _wing_mesh = {}
var _wing_gpu = {}
var _shape_meshes = {}
var _buckets = [[], [], [], []]
var _sprites = {}
var _textures = {}
var _quad_tables = {}
var _canvas = Transform2D.IDENTITY
var _acc = 0.0
var _refresh = 0.0
var _emitters = {}
var _quad_uv = PoolVector2Array()
var _quad_index = PoolIntArray()
var _options = {}
var _tint = Color("49a8ff")

static func catalog_entries() -> Dictionary:
	var out = {}
	for id in ITEMS:
		out[id] = {"type": "effect", "name": ITEMS[id].name, "rarity": "legendary", "studio_local": true}
	return out

static func is_effect(id) -> bool:
	return ITEMS.has(str(id))

static func wing_size(selected: Array) -> String:
	var size = "none"
	for id in selected:
		if ITEMS.has(str(id)) and ITEMS[str(id)].has("wings"):
			size = ITEMS[str(id)].wings
	return size

func configure(goober, selected: Array, options: Dictionary = {}, tint: Color = Color("49a8ff")) -> void:
	target = goober
	var next = []
	for id in selected:
		if ITEMS.has(str(id)) and not ITEMS[str(id)].has("wings"):
			next.append(str(id))
	if next != ids:
		parts.clear()
		trails.clear()
	ids = next
	_emitters = {}
	for id in ids:
		_emitters[id] = "_emit_" + id.trim_prefix("studio_fx_").split("_")[0]
	_options = options.duplicate()
	_tint = tint
	_recolor()
	set_process(not ids.empty())
	if ids.empty(): _redraw()

# Original colours, the Goober's colour or a picked one (Effects "..." menu).
func _recolor() -> void:
	if layers.empty() or ids.empty():
		return
	var mode = str(_options.get("mode", "original"))
	var color = _tint if mode == "goober" else Color(str(_options.get("hex", "ff5ad2")))
	var item = ITEMS[ids[0]]
	for layer in layers:
		var m = layer.material
		if mode == "original":
			m.set_shader_param("mode", 0.0)
		elif item.get("mono", false):
			m.set_shader_param("mode", 2.0)
			m.set_shader_param("tint", Vector3(color.r, color.g, color.b))
		else:
			m.set_shader_param("mode", 1.0)
			m.set_shader_param("shift", color.h - float(item.get("hue", 0.0)))
			m.set_shader_param("sat", clamp(color.s / 0.55, 0.0, 1.25))

func _material(add: bool) -> ShaderMaterial:
	var key = "goob_fx_recolor_add" if add else "goob_fx_recolor"
	var tree = Engine.get_main_loop()
	if not tree.has_meta(key):
		var shader = Shader.new()
		shader.code = RECOLOR % ("render_mode blend_add;" if add else "")
		tree.set_meta(key, shader)
	var m = ShaderMaterial.new()
	m.shader = tree.get_meta(key)
	return m

func _ready():
	show_behind_parent = true
	if get_parent() != null:
		get_parent().call_deferred("move_child", self, 0)
	material = _material(false)
	var back_add = Node2D.new()
	back_add.material = _material(true)
	add_child(back_add)
	front = Node2D.new()
	front.name = name + "Front"
	front.material = _material(false)
	var front_add = Node2D.new()
	front_add.material = _material(true)
	front.add_child(front_add)
	get_parent().call_deferred("add_child", front)
	layers = [self, back_add, front, front_add]
	for i in layers.size():
		layers[i].connect("draw", self, "_paint", [layers[i], i])
	_recolor()

func _exit_tree():
	if is_instance_valid(front):
		front.queue_free()

# ---------------------------------------------------------------- textures

func _tex(kind: String):
	if _textures.has(kind): return _textures[kind]
	var value = _shared_tex(kind)
	_textures[kind] = value
	return value

func _shared_tex(kind: String):
	var tree = Engine.get_main_loop()
	var key = "goob_fx2_" + kind
	if tree.has_meta(key):
		return tree.get_meta(key)
	var w = 64
	var h = 64
	if kind == "flame":
		h = 128
	if kind == "cloud":
		return _cloud_tex(tree, key)
	var noise = OpenSimplexNoise.new()
	noise.seed = kind.hash() & 0xffff
	noise.octaves = 4
	noise.period = 18.0
	var image = Image.new()
	image.create(w, h, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in h:
		for x in w:
			var p = Vector2((x + 0.5) / w, (y + 0.5) / h) * 2.0 - Vector2.ONE
			var r = p.length()
			var a = 0.0
			match kind:
				"soft":
					a = pow(max(0.0, 1.0 - r), 2.2)
				"core":
					a = clamp(exp(-r * 6.0) * 1.2 - 0.02, 0.0, 1.0)
				"spark":
					var rays = exp(-abs(p.x) * 22.0) * pow(max(0.0, 1.0 - abs(p.y)), 1.5) + exp(-abs(p.y) * 22.0) * pow(max(0.0, 1.0 - abs(p.x)), 1.5)
					var q = p.rotated(PI / 4.0)
					var diag = (exp(-abs(q.x) * 30.0) * max(0.0, 1.0 - abs(q.y) * 1.8) + exp(-abs(q.y) * 30.0) * max(0.0, 1.0 - abs(q.x) * 1.8)) * 0.45
					a = clamp(rays + diag + exp(-r * 9.0), 0.0, 1.0)
				"flame":
					# Teardrop: round base low down, tongue licking up to the top.
					var up = clamp((0.45 - p.y) / 1.45, 0.0, 1.0)
					var wx = p.x + noise.get_noise_2d(x * 1.5, y * 0.7) * 0.35 * up
					if p.y > 0.45:
						a = 1.0 - Vector2(wx, p.y - 0.45).length() / 0.5
					else:
						a = 1.0 - abs(wx) / max(0.001, 0.5 * pow(1.0 - up, 1.2))
					a = clamp(a * 1.8, 0.0, 1.0) * (1.0 - up * 0.35)
				"smoke":
					var n = noise.get_noise_2d(x * 1.4, y * 1.4) * 0.5 + 0.5
					a = clamp(pow(max(0.0, 1.0 - r), 1.4) * (n * 1.6 - 0.2), 0.0, 1.0)
				"ring":
					a = exp(-pow((r - 0.82) * 16.0, 2.0))
				"streak":
					a = exp(-abs(p.y) * 9.0) * pow(max(0.0, 1.0 - abs(p.x)), 0.7)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	image.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	tree.set_meta(key, tex)
	return tex

# Billowy cloud puff: overlapping round lobes, lit from above.
func _cloud_tex(tree, key):
	var n = 96
	var lobes = [[Vector2(0.0, 0.12), 0.5], [Vector2(-0.38, 0.22), 0.36], [Vector2(0.4, 0.2), 0.38], [Vector2(-0.18, -0.22), 0.4], [Vector2(0.22, -0.28), 0.36], [Vector2(0.02, -0.5), 0.28]]
	var image = Image.new()
	image.create(n, n, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in n:
		for x in n:
			var p = Vector2((x + 0.5) / n, (y + 0.5) / n) * 2.0 - Vector2.ONE
			var a = 0.0
			var shade = 0.0
			for lobe in lobes:
				var d = (p - lobe[0]).length() / lobe[1]
				var inside = clamp((1.0 - d) * 4.0, 0.0, 1.0)
				if inside > a:
					a = inside
					# lit top-left of each lobe, darker towards its bottom
					shade = clamp(0.55 + (lobe[0].y - p.y) / lobe[1] * 0.35 + (lobe[0].x - p.x) / lobe[1] * 0.1, 0.35, 1.0)
			image.set_pixel(x, y, Color(shade, shade, shade, a * clamp((1.0 - p.length()) * 3.0, 0.0, 1.0)))
	image.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	tree.set_meta(key, tex)
	return tex

# ---------------------------------------------------------------- update

func _process(delta):
	if delta <= 0.0:
		return
	if ids.empty():
		if not parts.empty():
			parts.clear()
			_redraw()
		return
	var sprite = get_parent()
	# No work while the Goober is hidden (closed Studio, cards out of view)
	# or far off screen.
	if not sprite.is_visible_in_tree():
		_acc = 0.0
		return
	# Step at up to 60 updates a second (the game's own tick); faster frames
	# reuse the last drawing, which still follows the Goober every frame.
	_acc += delta
	if _acc < 1.0 / _rate():
		return
	if not _on_screen(sprite):
		_acc = 0.0
		return
	delta = min(_acc, 0.05)
	_acc = 0.0
	t += delta
	_follow()
	var gt = sprite.get_global_transform()
	_px = Vector2(gt.y).length()
	var pos = gt.origin
	if _last != null and (pos - _last).length() > 4000.0 * _px * max(delta, 0.016):
		_last = null
		trails.clear()
	if _last != null:
		_vel = _vel.linear_interpolate((pos - _last) / delta, min(1.0, delta * 10.0))
	_last = pos
	for id in ids:
		call(_emitters[id], delta, id)
	_step(delta)
	_bucket()
	_raise -= delta
	if _raise <= 0.0 and is_instance_valid(front) and front.get_parent() == sprite:
		_raise = 0.5
		if front.get_index() != sprite.get_child_count() - 1:
			front.raise()
	_redraw()

func _rate() -> float:
	if _refresh <= 0.0:
		_refresh = 144.0
		if OS.has_method("get_screen_refresh_rate"):
			var hz = float(OS.call("get_screen_refresh_rate"))
			if hz > 0.0:
				_refresh = hz
		# The race simulates at 60 ticks a second; effects match that.
		_refresh = clamp(_refresh, 30.0, 60.0)
	return _refresh

func _on_screen(sprite) -> bool:
	var view = sprite.get_viewport_rect()
	view = view.grow(view.size.x * 0.25)
	return view.has_point(sprite.get_global_transform_with_canvas().origin)

func _redraw():
	for layer in layers:
		if is_instance_valid(layer):
			layer.update()

func _step(delta: float) -> void:
	var i = parts.size() - 1
	while i >= 0:
		var p: Particle = parts[i]
		p.age += delta
		if p.age >= p.life:
			parts.remove(i)
			i -= 1
			continue
		if p.orbit != null:
			# Circles the Goober; depth decides front or back.
			var o = p.orbit
			o.a += o.w * delta
			o.r = max(60.0, o.r + o.dr * delta)
			o.y += o.dy * delta
			var local = Vector2(o.cx, o.y) + Vector2(cos(o.a) * o.r, sin(o.a) * o.r * o.tilt).rotated(o.lean)
			p.p = _at(o.bone).xform(local)
			var behind = sin(o.a) < 0.0
			p.layer = (1 if p.add else 0) if behind else (3 if p.add else 2)
			p.depth = 0.75 if behind else 1.0
		else:
			p.v += p.g * delta
			if p.drag > 0.0:
				p.v *= max(0.0, 1.0 - p.drag * delta)
			if p.wave > 0.0:
				p.v.x += sin(t * p.wave + p.ph) * p.wamp * delta
			p.p += p.v * delta
		p.rot += p.spin * delta
		i -= 1

func _bucket() -> void:
	_buckets = [[], [], [], []]
	for index in parts.size():
		var p: Particle = parts[index]
		var k = p.age / p.life
		var fade = min(1.0, k / p.fin) * (1.0 - k if p.fout == 1.0 else pow(1.0 - k, p.fout))
		var color = p.c0.linear_interpolate(p.c1, k) if p.cm == null else (p.c0.linear_interpolate(p.cm, k * 2.0) if k < 0.5 else p.cm.linear_interpolate(p.c1, k * 2.0 - 1.0))
		if p.tw > 0.0:
			fade *= 0.55 + 0.45 * sin(t * p.tw + p.ph)
		color.a *= fade * p.depth
		if color.a > 0.003:
			_buckets[p.layer].append([p, color, lerp(p.s0, p.s1, k) * p.depth])

func _add(data: Dictionary) -> void:
	if parts.size() > 1400:
		return
	# Every field present, so the per-frame loops read them directly.
	for key in DEFAULTS:
		if not data.has(key):
			data[key] = DEFAULTS[key]
	data["age"] = 0.0
	data["ph"] = data.get("ph", randf() * TAU2)
	var o = data.orbit
	if o != null:
		for key in ORBIT_DEFAULTS:
			if not o.has(key):
				o[key] = ORBIT_DEFAULTS[key]
		if not data.has("layer"):
			data["layer"] = 1
	parts.append(Particle.new(data))

func _count(key: String, rate: float, delta: float) -> int:
	var v = _emit.get(key, randf()) + rate * delta
	var n = int(v)
	_emit[key] = v - n
	return n

# ---------------------------------------------------------------- bones

func _follow():
	var sprite = get_parent()
	if sprite == null or not sprite.has_method("get_skeleton"):
		return
	var skeleton = sprite.get_skeleton()
	if skeleton == null:
		return
	for name in SETUP:
		if not _bones.has(name):
			_bones[name] = skeleton.find_bone(name)
		var bone = _bones[name]
		var setup = Transform2D(SETUP[name][0], SETUP[name][1], SETUP[name][2])
		var d = Transform2D.IDENTITY
		if bone != null:
			var f = Transform2D(Vector2(bone.get_a(), bone.get_c()), Vector2(bone.get_b(), bone.get_d()), Vector2(bone.get_world_x(), bone.get_world_y()))
			# Skip frames that never animated (identity) or inactive bones (zero).
			var fresh = is_equal_approx(f.x.x, 1.0) and is_equal_approx(f.y.y, 1.0) and f.origin == Vector2.ZERO
			if not fresh and abs(f.x.x * f.y.y - f.x.y * f.y.x) > 0.05:
				d = f * setup.affine_inverse()
				if d.origin.length() > 900.0 or abs(d.get_rotation()) > 1.3:
					d = Transform2D.IDENTITY
		_delta[name] = d

func _at(bone: String) -> Transform2D:
	return _delta.get(bone, Transform2D.IDENTITY)

func _to_world(local: Vector2) -> Vector2:
	return get_parent().get_global_transform().xform(local)

# ---------------------------------------------------------------- drawing

# Sets the drawing frame; sprites are placed in it and restore it after.
# Build with mutable Arrays: appending to Godot 3 PoolArrays repeatedly copies
# their growing buffers. Convert once at the native submission boundary.
# Shapes are collected into one vertex-coloured mesh and sent as a single
# draw call (flushed whenever the frame or draw order needs it).
func _flush(c) -> void:
	if _mi.size() > 0:
		VisualServer.canvas_item_add_triangle_array(c.get_canvas_item(), PoolIntArray(_mi), PoolVector2Array(_mp), PoolColorArray(_mc))
		_mp = []
		_mc = []
		_mi = []
	if not _sprites.empty():
		var ci = c.get_canvas_item()
		for tex in _sprites:
			_submit(ci, tex, _sprites[tex])
		_sprites = {}

func _use(c, m: Transform2D) -> void:
	_flush(c)
	_inv = m
	if _canvas != m:
		_canvas = m
		c.draw_set_transform_matrix(m)

func _line(c, a: Vector2, b: Vector2, color: Color, width: float = 1.0, aa: bool = false) -> void:
	_flush(c)
	c.draw_line(a, b, color, width, aa)

func _pline(c, points: PoolVector2Array, color: Color, width: float = 1.0, aa: bool = false) -> void:
	_flush(c)
	c.draw_polyline(points, color, width, aa)

func _plinec(c, points: PoolVector2Array, colors: PoolColorArray, width: float = 1.0, aa: bool = false) -> void:
	_flush(c)
	c.draw_polyline_colors(points, colors, width, aa)

func _cpoly(c, points: PoolVector2Array, color: Color) -> void:
	_flush(c)
	c.draw_colored_polygon(points, color)

# A line as a quad in the shared mesh.
func _seg(c, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var n = (b - a).normalized().rotated(PI / 2.0) * width * 0.5
	_quad(c, a + n, b + n, b - n, a - n, color, color, color, color)

# Sprites placed in the _inv frame, collected per texture into the canvas frame.
func _sprite(_c, tex: String, pos: Vector2, size: Vector2, rot: float, color: Color) -> void:
	var m = Transform2D(rot, pos)
	if _inv != _canvas:
		m = _canvas.affine_inverse() * _inv * m
	_batch(_sprites, tex, m.origin, Vector2(Vector2(m.x).length() * size.x, Vector2(m.y).length() * size.y), Vector2(m.x).angle(), color)

func _glow(c, pos: Vector2, r: float, color: Color) -> void:
	_sprite(c, "soft", pos, Vector2(r, r), 0.0, color)

func _flare(c, pos: Vector2, r: float, rot: float, color: Color) -> void:
	_sprite(c, "spark", pos, Vector2(r, r), rot, color)

func _tri(_c, a: Vector2, b: Vector2, d: Vector2, ca: Color, cb: Color, cd: Color) -> void:
	var n = _mp.size()
	_mp.append(a)
	_mp.append(b)
	_mp.append(d)
	_mc.append(ca)
	_mc.append(cb)
	_mc.append(cd)
	_mi.append(n)
	_mi.append(n + 1)
	_mi.append(n + 2)

func _quad(_c, a: Vector2, b: Vector2, d: Vector2, e: Vector2, ca: Color, cb: Color, cd: Color, ce: Color) -> void:
	var n = _mp.size()
	_mp.append(a)
	_mp.append(b)
	_mp.append(d)
	_mp.append(e)
	_mc.append(ca)
	_mc.append(cb)
	_mc.append(cd)
	_mc.append(ce)
	for k in [0, 1, 2, 0, 2, 3]:
		_mi.append(n + k)

func _fan(c, center: Vector2, radius: Vector2, rot: float, inner: Color, outer: Color, key: String, edge: PoolVector2Array) -> void:
	var frame = Transform2D(rot,center)
	frame.x *= radius.x
	frame.y *= radius.y
	var at = _mp.size()
	_mp.append(center)
	_mp.append_array(Array(frame.xform(edge)))
	_mc.append(inner)
	for _i in edge.size(): _mc.append(outer)
	for i in edge.size():
		_mi.append_array([at,at+1+i,at+1+(i+1)%edge.size()])

func _star(c, center: Vector2, r: float, rot: float, inner: Color, outer: Color, points: int = 5, depth: float = 0.45) -> void:
	var key = "star:"+str(points)+":"+str(depth)
	if not _shape_meshes.has(key):
		var edge = PoolVector2Array()
		for i in points*2:
			var a = i*PI/points-PI/2.0
			edge.append(Vector2(cos(a),sin(a))*(1.0 if i%2==0 else depth))
		_shape_meshes[key] = edge
	_fan(c,center,Vector2(r,r),rot,inner,outer,key,_shape_meshes[key])

func _ellipse(c, center: Vector2, radius: Vector2, inner: Color, outer: Color, segments: int = 28) -> void:
	var key = "ellipse:"+str(segments)
	if not _shape_meshes.has(key):
		var edge = PoolVector2Array()
		for i in segments:
			var a = TAU2*i/segments
			edge.append(Vector2(cos(a),sin(a)))
		_shape_meshes[key] = edge
	_fan(c,center,radius,0.0,inner,outer,key,_shape_meshes[key])


func _ring(c, center: Vector2, radius: Vector2, width: float, color: Color, from: float = 0.0, to: float = TAU2, segments: int = 40) -> void:
	var pts = PoolVector2Array()
	for i in segments + 1:
		var a = lerp(from, to, float(i) / segments)
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	_pline(c, pts, color, width, true)

# Tapered ribbon through points (start -> end).
func _ribbon(c, points: Array, w0: float, w1: float, c0: Color, c1: Color) -> void:
	var n = points.size()
	if n < 2:
		return
	var left = []
	var right = []
	for i in n:
		var a = points[max(0, i - 1)]
		var b = points[min(n - 1, i + 1)]
		var dir = (b - a).normalized()
		var normal = Vector2(-dir.y, dir.x) * lerp(w0, w1, float(i) / (n - 1)) * 0.5
		left.append(points[i] + normal)
		right.append(points[i] - normal)
	for i in n - 1:
		var a = c0.linear_interpolate(c1, float(i) / (n - 1))
		var b = c0.linear_interpolate(c1, float(i + 1) / (n - 1))
		_quad(c, left[i], left[i + 1], right[i + 1], right[i], a, b, b, a)

func _bolt(a: Vector2, b: Vector2, jag: float, steps: int = 8) -> PoolVector2Array:
	var out = PoolVector2Array([a])
	var normal = (b - a).normalized().rotated(PI / 2.0)
	for i in range(1, steps):
		var k = float(i) / steps
		out.append(a.linear_interpolate(b, k) + normal * rand_range(-jag, jag) * sin(k * PI))
	out.append(b)
	return out

func _paint(c, layer: int) -> void:
	if ids.empty():
		return
	_inv = Transform2D.IDENTITY
	_canvas = Transform2D.IDENTITY
	for id in ids:
		_use(c, Transform2D.IDENTITY)
		call("_draw_" + id.trim_prefix("studio_fx_").split("_")[0], c, layer, id)
	_use(c, Transform2D.IDENTITY)
	# Particles: one draw call per texture, then the shape mesh, then the few
	# that draw themselves (notes, little butterflies).
	var world_inv = c.get_global_transform().affine_inverse()
	var world_scale = Vector2(world_inv.x).length()
	var batches = {}
	var own = []
	for entry in _buckets[layer]:
		var p: Particle = entry[0]
		var color = entry[1]
		var size = entry[2]
		var rot = p.rot
		var world = p.world
		var pos = world_inv.xform(p.p) if world else p.p
		if world:
			size *= world_scale
		match p.tex:
			"star":
				_batch(batches, "soft", pos, Vector2(size, size) * 2.6, 0.0, Color(color.r, color.g * 0.75, color.b * 0.5, color.a * 0.45))
				_star(c, pos, size, rot, Color(1, 1, 0.9, color.a), color)
			"diamond":
				var a = Vector2(cos(rot), sin(rot)) * size
				var b = Vector2(-a.y, a.x) * 0.45
				var core = color.linear_interpolate(Color(1, 1, 1, color.a), 0.7)
				_quad(c, pos + a, pos + b, pos - a, pos - b, color, core, color, Color(color.r, color.g, color.b, color.a * 0.5))
			"note", "mini":
				own.append([p, size, rot, color])
			_:
				var scale = Vector2(size, size) * p.aspect
				if p.stretch > 0.0:
					rot = p.v.angle()
					scale.x *= 1.0 + p.v.length() / max(1.0, p.stretch)
				_batch(batches, p.tex, pos, scale, rot, color)
	var mesh = [_mp, _mc, _mi]
	_mp = []
	_mc = []
	_mi = []
	var ci = c.get_canvas_item()
	for tex in batches:
		_submit(ci, tex, batches[tex])
	_mp = mesh[0]
	_mc = mesh[1]
	_mi = mesh[2]
	_flush(c)
	for entry in own:
		var p: Particle = entry[0]
		if p.tex == "note":
			_note(c, p.p, entry[1], entry[2], entry[3], p.double)
		else:
			_mini(c, p, entry[1], entry[3])
	_use(c, Transform2D.IDENTITY)

func _batch(batches: Dictionary, tex: String, pos: Vector2, size: Vector2, rot: float, color: Color) -> void:
	var b = batches.get(tex)
	if b == null:
		b = [[], []]
		batches[tex] = b
	var x = Vector2(cos(rot), sin(rot)) * size.x
	var y = Vector2(-x.y / max(0.0001, size.x) * size.y, x.x / max(0.0001, size.x) * size.y)
	var pts = b[0]
	pts.append(pos - x - y)
	pts.append(pos + x - y)
	pts.append(pos + x + y)
	pts.append(pos - x + y)
	var cols = b[1]
	cols.append(color)
	cols.append(color)
	cols.append(color)
	cols.append(color)

# Submits one texture's quads; uvs and indices come from shared tables.
func _submit(ci, tex: String, b: Array) -> void:
	var quads = b[0].size() / 4
	if quads == 0:
		return
	if not _quad_tables.has(quads):
		var uv = []
		var index = []
		for q in quads:
			uv.append_array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
			for k in [0,1,2,0,2,3]: index.append(q*4+k)
		if _quad_tables.size()>=128: _quad_tables.clear()
		_quad_tables[quads] = [PoolVector2Array(uv),PoolIntArray(index)]
	var table = _quad_tables[quads]
	VisualServer.canvas_item_add_triangle_array(ci,table[1],PoolVector2Array(b[0]),PoolColorArray(b[1]),table[0],PoolIntArray(),PoolRealArray(),_tex(tex).get_rid())


func _horn(side: float) -> Array:
	# Rooted in the top of the head, rising and hooking inwards at the tip.
	var p0 = Vector2(-20 + side * 360, -1720)
	var p1 = Vector2(-20 + side * 560, -1930)
	var p2 = Vector2(-20 + side * 600, -2200)
	var p3 = Vector2(-20 + side * 470, -2390)
	var out = []
	for i in 18:
		var s = i / 17.0
		var u = 1.0 - s
		out.append(p0 * u * u * u + p1 * 3 * u * u * s + p2 * 3 * u * s * s + p3 * s * s * s)
	return out

func _horn_width(i: int) -> float:
	return 150.0 * pow(1.0 - i / 17.0, 0.7) + 5.0

func _emit_cursed(delta, _id):
	var head = _at("bone7")
	for side in [-1.0, 1.0]:
		var horn = _horn(side)
		# Fire wrapping the horn: big overlapping tongues, white-cyan at the core.
		for i in _count("flame" + str(side), 95.0, delta):
			var j = int(rand_range(5, 18))
			var at = horn[j] + Vector2(rand_range(-1, 1), rand_range(-0.5, 0.5)) * _horn_width(j) * 0.7
			var size = lerp(230.0, 150.0, j / 17.0) * rand_range(0.8, 1.2)
			_add({"tex": "flame", "layer": 3, "p": head.xform(at), "v": Vector2(rand_range(-40, 40), rand_range(-650, -420)), "drag": 1.5,
				"life": rand_range(0.28, 0.5), "s0": size, "s1": size * 0.25, "aspect": Vector2(0.62, 1.35), "rot": rand_range(-0.12, 0.12), "fin": 0.2,
				"c0": Color(0.55, 0.85, 1.0, 0.55), "cm": Color(0.15, 0.45, 1.0, 0.5), "c1": Color(0.1, 0.1, 0.8, 0.0)})
		for i in _count("core" + str(side), 45.0, delta):
			var j = int(rand_range(10, 18))
			_add({"tex": "flame", "layer": 3, "p": head.xform(horn[j] + Vector2(rand_range(-30, 30), 0)), "v": Vector2(rand_range(-20, 20), rand_range(-800, -520)), "drag": 2.0,
				"life": rand_range(0.2, 0.36), "s0": rand_range(130, 180), "s1": 30.0, "aspect": Vector2(0.5, 1.5), "fin": 0.15,
				"c0": Color(0.95, 1.0, 1.0, 0.9), "cm": Color(0.45, 0.8, 1.0, 0.7), "c1": Color(0.2, 0.3, 1.0, 0.0)})
		for i in _count("ember" + str(side), 12.0, delta):
			_add({"tex": "core", "layer": 3, "p": head.xform(horn[int(rand_range(8, 18))]), "v": Vector2(rand_range(-160, 160), rand_range(-1000, -600)), "g": Vector2(0, 400), "drag": 0.8,
				"life": rand_range(0.6, 1.1), "s0": rand_range(16, 28), "s1": 6.0, "c0": Color(0.8, 0.95, 1.0, 1.0), "c1": Color(0.2, 0.4, 1.0, 0.0), "wave": 7.0, "wamp": 400.0})
		for i in _count("smoke" + str(side), 6.0, delta):
			_add({"tex": "smoke", "layer": 1, "p": head.xform(horn[17] + Vector2(0, -80)), "v": Vector2(rand_range(-60, 60), rand_range(-420, -260)), "life": rand_range(0.8, 1.2), "s0": 120.0, "s1": 320.0,
				"rot": randf() * TAU2, "spin": rand_range(-1, 1), "c0": Color(0.1, 0.25, 0.8, 0.25), "c1": Color(0.05, 0.05, 0.4, 0.0), "fin": 0.3})

func _draw_cursed(c, layer, _id):
	var head = _at("bone7")
	if layer == 1:
		_inv = head
		_glow(c, TOP + Vector2(0, 80), 1000.0, Color(0.1, 0.3, 1.0, 0.2 + 0.05 * sin(t * 5.0)))
		_inv = Transform2D.IDENTITY
		return
	if layer == 0:
		return
	for side in [-1.0, 1.0]:
		var horn = _horn(side)
		var left = []
		var right = []
		for i in horn.size():
			var a = horn[max(0, i - 1)]
			var b = horn[min(horn.size() - 1, i + 1)]
			var dir = (b - a).normalized()
			var n = Vector2(-dir.y, dir.x) * _horn_width(i)
			left.append(horn[i] + n)
			right.append(horn[i] - n)
		var outer = left if side > 0 else right
		var inner = right if side > 0 else left
		_use(c, head)
		if layer == 2:
			# Contact shadow where the horn meets the head.
			_ellipse(c, horn[0] + Vector2(0, 30), Vector2(170, 60), Color(0, 0, 0.05, 0.45), Color(0, 0, 0.05, 0.0), 20)
			for i in horn.size() - 1:
				var groove = 0.6 if i % 3 == 1 else 1.0
				var lit = Color(0.15 * groove, 0.16 * groove, 0.22 * groove)
				var mid = Color(0.045 * groove, 0.045 * groove, 0.07 * groove)
				var dark = Color(0.015, 0.015, 0.03)
				_quad(c, outer[i], outer[i + 1], horn[i + 1], horn[i], lit, lit, mid, mid)
				_quad(c, horn[i], horn[i + 1], inner[i + 1], inner[i], mid, mid, dark, dark)
			var gloss = PoolVector2Array()
			for i in range(2, 15):
				gloss.append(horn[i].linear_interpolate(outer[i], 0.5))
			_pline(c, gloss, Color(0.6, 0.7, 1.0, 0.4), 12.0, true)
		else:
			var pulse = 0.8 + 0.2 * sin(t * 7.0 + side * 2.0)
			_inv = head
			for i in range(5, 18, 3):
				_glow(c, horn[i], 300.0, Color(0.1, 0.35, 1.0, 0.25 * pulse))
			_glow(c, horn[17], 420.0 * pulse, Color(0.2, 0.55, 1.0, 0.5))
			_glow(c, horn[16], 150.0, Color(0.85, 0.97, 1.0, 0.7))
			_inv = Transform2D.IDENTITY
			_use(c, head)
			var rim = PoolVector2Array()
			for i in range(1, 18):
				rim.append(outer[i])
			_pline(c, rim, Color(0.35, 0.7, 1.0, 0.65 * pulse), 14.0, true)
	_use(c, Transform2D.IDENTITY)

# ---------------------------------------------------------------- Halley's Comet

# Comets circling the Goober on tilted orbits: [speed, radius x, radius y, lean, height, phase].
const COMETS = [[2.3, 1000.0, 300.0, 0.0, -900.0, 0.0], [-1.7, 900.0, 240.0, 0.42, -1150.0, 2.1], [1.4, 1150.0, 260.0, -0.38, -700.0, 4.2]]

func _comet_at(k: int, a: float) -> Vector2:
	var o = COMETS[k]
	return Vector2(-20, o[4]) + Vector2(cos(a) * o[1], sin(a) * o[2]).rotated(o[3])

func _emit_halley(delta, _id):
	var chest = _at("bone4")
	var speed = _vel.length()
	var moving = clamp((speed / max(_px, 0.0001) - 300.0) / 1000.0, 0.0, 1.0)
	var center = _to_world(chest.xform(Vector2(-20, -900)))
	var tail = trails.get("halley", [])
	tail.push_front({"p": center, "age": 0.0})
	for p in tail:
		p.age += delta
	while tail.size() > 2 and tail[tail.size() - 1].age > 0.7:
		tail.pop_back()
	trails["halley"] = tail
	trails["halley_on"] = lerp(trails.get("halley_on", 0.0), moving, min(1.0, delta * 6.0))
	var px = _px
	for i in _count("halley_trail", 170.0 * moving, delta):
		var off = Vector2(rand_range(-1, 1), rand_range(-1, 1)) * 560.0 * px
		var back = -_vel * rand_range(0.0, 0.08)
		var roll = randf()
		if roll < 0.35:
			_add({"tex": "smoke", "world": true, "layer": 1, "p": center + off * 0.6 + back, "v": -_vel * 0.05, "drag": 2.0, "life": rand_range(0.5, 0.9), "s0": rand_range(220, 340) * px, "s1": rand_range(420, 560) * px,
				"rot": randf() * TAU2, "spin": rand_range(-1, 1), "c0": Color(0.55, 0.3, 1.0, 0.5), "c1": Color(0.2, 0.05, 0.6, 0.0)})
		elif roll < 0.75:
			_add({"tex": "spark", "world": true, "layer": 1, "p": center + off + back, "v": Vector2(rand_range(-60, 60), rand_range(-80, 40)) * px, "life": rand_range(0.5, 1.2), "s0": rand_range(90, 200) * px, "s1": 20.0 * px,
				"c0": Color(1.0, 0.95, 1.0, 1.0), "c1": Color(0.7, 0.4, 1.0, 0.6), "tw": 30.0})
		else:
			_add({"tex": "diamond", "world": true, "layer": 1, "p": center + off + back, "v": Vector2(rand_range(-200, 200), rand_range(-200, 200)) * px, "drag": 1.5, "life": rand_range(0.6, 1.1), "s0": rand_range(55, 100) * px, "s1": 10.0 * px,
				"spin": rand_range(-6, 6), "rot": randf() * TAU2, "c0": Color(0.85, 0.7, 1.0, 1.0), "c1": Color(0.45, 0.2, 1.0, 0.0)})
	# Comet tails and sparkles shed along each orbit.
	for k in COMETS.size():
		var a = t * COMETS[k][0] + COMETS[k][5]
		var key = "comet%d" % k
		var hist = trails.get(key, [])
		hist.push_front(a)
		while hist.size() > 30:
			hist.pop_back()
		trails[key] = hist
		var head = _comet_at(k, a)
		var front = sin(a) > 0.0
		for i in _count(key, 34.0, delta):
			var back = _comet_at(k, a - sign(COMETS[k][0]) * rand_range(0.05, 0.7))
			_add({"tex": "spark" if randf() < 0.6 else "diamond", "layer": 3 if front else 1, "p": chest.xform(back + Vector2(rand_range(-70, 70), rand_range(-70, 70))), "v": Vector2(rand_range(-60, 60), rand_range(-120, 60)),
				"life": rand_range(0.5, 1.0), "s0": rand_range(60, 130), "s1": 10.0, "spin": rand_range(-5, 5), "rot": randf() * TAU2, "c0": Color(0.95, 0.88, 1.0, 1.0), "c1": Color(0.55, 0.25, 1.0, 0.0), "tw": 26.0})
	# Nebula haze and star dust around the Goober.
	for i in _count("halley_neb", 9.0, delta):
		_add({"tex": "smoke", "p": Vector2.ZERO, "life": rand_range(2.0, 3.0), "s0": rand_range(380, 520), "s1": rand_range(600, 760), "rot": randf() * TAU2, "spin": rand_range(-0.4, 0.4), "fin": 0.3,
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": 0.7, "r": rand_range(600, 900), "y": rand_range(-1500, -300), "dy": -60.0, "tilt": 0.35},
			"c0": Color(0.45, 0.2, 1.0, 0.34) if randf() < 0.6 else Color(0.2, 0.35, 1.0, 0.3), "c1": Color(0.3, 0.1, 0.8, 0.0)})
	for i in _count("halley_amb", 16.0, delta):
		_add({"tex": "spark", "layer": 3 if randf() < 0.5 else 1, "p": chest.xform(Vector2(rand_range(-1100, 1100), rand_range(-2100, -100))), "v": Vector2(0, -50), "life": rand_range(0.8, 1.4), "s0": rand_range(40, 100), "s1": 15.0,
			"c0": Color(0.92, 0.85, 1.0, 1.0), "c1": Color(0.6, 0.35, 1.0, 0.0), "tw": 20.0})

func _draw_halley(c, layer, _id):
	var chest = _at("bone4")
	var on = trails.get("halley_on", 0.0)
	var tail = trails.get("halley", [])
	if layer == 1:
		_inv = chest
		_glow(c, Vector2(-20, -900), 1300.0, Color(0.35, 0.15, 0.9, 0.18 + 0.04 * sin(t * 2.0)))
		_use(c, Transform2D.IDENTITY)
	if layer == 1 and on > 0.02 and tail.size() > 2:
		var points = []
		for p in tail:
			points.append(p.p)
		_use(c, c.get_global_transform().affine_inverse())
		var px = _px
		_ribbon(c, points, 1000.0 * px, 0.0, Color(0.4, 0.15, 1.0, 0.3 * on), Color(0.2, 0.05, 0.7, 0.0))
		_ribbon(c, points, 520.0 * px, 0.0, Color(0.7, 0.45, 1.0, 0.55 * on), Color(0.4, 0.15, 1.0, 0.0))
		_ribbon(c, points, 160.0 * px, 0.0, Color(1.0, 0.95, 1.0, 0.9 * on), Color(0.7, 0.5, 1.0, 0.0))
		_use(c, Transform2D.IDENTITY)
	if layer != 1 and layer != 3:
		return
	for k in COMETS.size():
		var a = t * COMETS[k][0] + COMETS[k][5]
		var in_front = sin(a) > 0.0
		if (layer == 3) != in_front:
			continue
		var depth = 1.0 if in_front else 0.72
		var points = []
		for b in trails.get("comet%d" % k, []):
			points.append(_comet_at(k, b))
		_use(c, chest)
		_ribbon(c, points, 200.0 * depth, 0.0, Color(0.55, 0.3, 1.0, 0.45), Color(0.3, 0.1, 1.0, 0.0))
		_ribbon(c, points, 64.0 * depth, 0.0, Color(1.0, 0.95, 1.0, 0.9), Color(0.7, 0.4, 1.0, 0.0))
		var head = _comet_at(k, a)
		_glow(c, head, 460.0 * depth, Color(0.5, 0.25, 1.0, 0.55))
		_glow(c, head, 150.0 * depth, Color(1, 1, 1, 0.95))
		_flare(c, head, (340.0 + 70.0 * sin(t * 17.0 + k)) * depth, t * 0.8 + k, Color(1, 0.95, 1, 0.95))
	_use(c, Transform2D.IDENTITY)

# ---------------------------------------------------------------- Selene's Grace

# A thin white crescent above the head over a billowing cloud of dark
# violet and blue smoke behind the head and shoulders.
func _moon_pos() -> Vector2:
	return Vector2(-20 + sin(t * 0.8) * 50.0, -2330 + sin(t * 1.6) * 55.0)

func _moon_rot() -> float:
	return -0.25 + sin(t * 1.1) * 0.14

func _emit_selene(delta, _id):
	var head = _at("bone7")
	# Dense smoke behind the head: dark body...
	for i in _count("smoke_dark", 46.0, delta):
		var x = rand_range(-700, 660)
		var y = rand_range(-2150, -1150) + abs(x) * 0.25
		var blue = randf() < 0.4
		_add({"tex": "cloud", "layer": 0, "p": head.xform(Vector2(x, y)), "v": Vector2(x * 0.12 + rand_range(-40, 40), rand_range(-170, -80)), "drag": 0.3,
			"life": rand_range(2.2, 3.2), "s0": rand_range(300, 420), "s1": rand_range(520, 700), "rot": randf() * TAU2, "spin": rand_range(-0.6, 0.6), "fin": 0.3, "fout": 1.2,
			"c0": Color(0.42, 0.5, 0.95, 0.9) if blue else Color(0.55, 0.4, 0.95, 0.9), "c1": Color(0.3, 0.22, 0.65, 0.0)})
	# ...lit violet and blue billows on top of it.
	for i in _count("smoke_lit", 30.0, delta):
		var x = rand_range(-640, 600)
		var y = rand_range(-2200, -1300) + abs(x) * 0.2
		var blue = randf() < 0.45
		_add({"tex": "smoke", "layer": 1, "p": head.xform(Vector2(x, y)), "v": Vector2(x * 0.1 + rand_range(-30, 30), rand_range(-160, -70)), "drag": 0.3,
			"life": rand_range(1.8, 2.8), "s0": rand_range(200, 320), "s1": rand_range(420, 560), "rot": randf() * TAU2, "spin": rand_range(-0.7, 0.7), "fin": 0.35, "fout": 1.3,
			"c0": Color(0.4, 0.5, 1.0, 0.4) if blue else Color(0.65, 0.42, 1.0, 0.4), "c1": Color(0.3, 0.2, 0.8, 0.0)})
	# Wisps curling round the sides, in front of the Goober.
	for i in _count("smoke_front", 6.0, delta):
		var side = -1.0 if randf() < 0.5 else 1.0
		_add({"tex": "cloud", "layer": 2, "p": head.xform(Vector2(-20 + side * rand_range(680, 820), rand_range(-1600, -1000))), "v": Vector2(side * rand_range(20, 70), rand_range(-140, -60)),
			"life": rand_range(1.6, 2.4), "s0": rand_range(160, 240), "s1": rand_range(320, 420), "rot": randf() * TAU2, "spin": rand_range(-0.8, 0.8), "fin": 0.35,
			"c0": Color(0.55, 0.45, 0.95, 0.42), "c1": Color(0.35, 0.28, 0.8, 0.0)})
	# Moonlight glints and dust drifting down from the crescent.
	var moon = head.xform(_moon_pos())
	for i in _count("moondust", 10.0, delta):
		_add({"tex": "core", "layer": 3, "p": moon + Vector2(rand_range(-220, 220), rand_range(-40, 160)), "v": Vector2(rand_range(-50, 50), rand_range(110, 220)), "life": rand_range(1.0, 1.6), "s0": rand_range(16, 30), "s1": 5.0,
			"c0": Color(0.92, 0.92, 1.0, 1.0), "c1": Color(0.55, 0.5, 1.0, 0.0), "wave": 3.0, "wamp": 100.0})
	for i in _count("smoke_star", 5.0, delta):
		_add({"tex": "spark", "layer": 1, "p": head.xform(Vector2(rand_range(-650, 620), rand_range(-2250, -1300))), "life": rand_range(0.6, 1.1), "s0": rand_range(40, 80), "s1": 10.0,
			"c0": Color(0.95, 0.95, 1.0, 1.0), "c1": Color(0.7, 0.65, 1.0, 0.0), "tw": 22.0})

func _crescent(c, center: Vector2, r: float, rot: float, lit: Color, rim: Color) -> void:
	# Thin crescent, open to the right: outer arc minus a larger offset disc.
	var outer = []
	var inner = []
	for i in 33:
		var k = i / 32.0
		var a = lerp(PI * 0.42, PI * 1.58, k)
		outer.append(center + Vector2(cos(a), sin(a)).rotated(rot) * r)
		# Inner edge: a circle of radius 0.92r shifted right, meeting the outer at the tips.
		var b = lerp(PI * 0.56, PI * 1.44, k)
		inner.append(center + (Vector2(0.36, 0.0) + Vector2(cos(b), sin(b)) * 0.88).rotated(rot) * r)
	for i in 32:
		var e = abs(i - 16) / 16.0
		var cr = rim
		var cl = lit
		cr.a *= 1.0 - pow(e, 4.0) * 0.6
		cl.a *= 1.0 - pow(e, 3.0) * 0.8
		_quad(c, outer[i], outer[i + 1], inner[i + 1], inner[i], cr, cr, cl, cl)

func _draw_selene(c, layer, _id):
	var head = _at("bone7")
	var moon = _moon_pos()
	var rot = _moon_rot()
	var pulse = 0.85 + 0.15 * sin(t * 2.3)
	if layer == 1:
		# Moonlight on the smoke.
		_use(c, head)
		_glow(c, moon + Vector2(0, 250), 900.0 * pulse, Color(0.55, 0.5, 1.0, 0.28))
		_glow(c, Vector2(-20, -1650), 1000.0, Color(0.3, 0.25, 0.85, 0.18 + 0.04 * sin(t * 1.7)))
	elif layer == 2:
		_use(c, head)
		_crescent(c, moon, 330.0, rot, Color(0.9, 0.9, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0))
	elif layer == 3:
		_use(c, head)
		_glow(c, moon + Vector2(-140, 0).rotated(rot), 620.0 * pulse, Color(0.75, 0.72, 1.0, 0.45))
		_glow(c, moon + Vector2(-200, 0).rotated(rot), 260.0, Color(1.0, 1.0, 1.0, 0.4))
		var tip_a = moon + Vector2(cos(PI * 0.42), sin(PI * 0.42)).rotated(rot) * 330.0
		var tip_b = moon + Vector2(cos(PI * 1.58), sin(PI * 1.58)).rotated(rot) * 330.0
		_flare(c, tip_a, 150.0 * (0.7 + 0.3 * sin(t * 5.0)), t * 0.7, Color(1, 1, 1, 0.8))
		_flare(c, tip_b, 150.0 * (0.7 + 0.3 * sin(t * 5.0 + 2.0)), -t * 0.6, Color(1, 1, 1, 0.8))
	_use(c, Transform2D.IDENTITY)

# ---------------------------------------------------------------- Abyssal Rapture

func _emit_abyssal(delta, _id):
	# Dark smoke and violet wisps spiral into the void and up the Goober.
	for i in _count("abyss_smoke", 20.0, delta):
		_add({"tex": "smoke", "add": false, "layer": 0, "p": Vector2.ZERO, "life": rand_range(1.2, 1.8), "s0": rand_range(220, 320), "s1": rand_range(420, 560), "rot": randf() * TAU2, "spin": rand_range(-1.5, 1.5),
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": 2.2, "r": rand_range(700, 950), "dr": -380.0, "y": 40.0, "dy": rand_range(-500, -300), "tilt": 0.28},
			"c0": Color(0.12, 0.0, 0.22, 0.75), "c1": Color(0.05, 0.0, 0.12, 0.0), "fin": 0.3})
	for i in _count("abyss_wisp", 46.0, delta):
		_add({"tex": "spark" if randf() < 0.35 else "soft", "layer": 1, "p": Vector2.ZERO, "life": rand_range(0.9, 1.5), "s0": rand_range(60, 150), "s1": 20.0,
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": 2.6, "r": rand_range(700, 950), "dr": -420.0, "y": 40.0, "dy": rand_range(-1000, -600), "tilt": 0.28},
			"c0": Color(0.85, 0.4, 1.0, 0.9), "cm": Color(0.6, 0.15, 1.0, 0.7), "c1": Color(0.3, 0.0, 0.7, 0.0), "tw": 18.0})
	if not _emit.has("abyss_pulse") or t >= _emit.abyss_pulse:
		_emit["abyss_pulse"] = t + 1.1
		_add({"tex": "ring", "layer": 1, "p": Vector2(-20, 40), "life": 1.0, "s0": 300.0, "s1": 1300.0, "aspect": Vector2(1.0, 0.28), "c0": Color(0.8, 0.4, 1.0, 0.7), "c1": Color(0.4, 0.0, 1.0, 0.0), "fin": 0.05})

func _draw_abyssal(c, layer, _id):
	if layer > 1:
		return
	var feet = Vector2(-20, 40)
	var squash = 0.28
	if layer == 0:
		_ellipse(c, feet, Vector2(1050, 1050 * squash), Color(0.04, 0.0, 0.1, 0.95), Color(0.12, 0.0, 0.25, 0.0), 40)
		_ellipse(c, feet, Vector2(560, 560 * squash), Color(0.0, 0.0, 0.0, 0.95), Color(0.05, 0.0, 0.12, 0.0), 32)
	else:
		_glow(c, feet + Vector2(0, -260), 1100.0, Color(0.45, 0.1, 0.85, 0.28 + 0.08 * sin(t * 3.0)))
		_inv = Transform2D(0.0, feet)
		_inv.y *= squash
		_glow(c, Vector2.ZERO, 560.0, Color(0.7, 0.2, 1.0, 0.4))
		_inv = Transform2D.IDENTITY
		_use(c, Transform2D.IDENTITY)
		for arm in 6:
			var pts = PoolVector2Array()
			var cols = PoolColorArray()
			var thin = PoolColorArray()
			for i in 24:
				var k = i / 23.0
				var r = lerp(1020.0, 70.0, k)
				var a = arm * TAU2 / 6.0 + t * 2.0 + k * 3.6
				pts.append(feet + Vector2(cos(a) * r, sin(a) * r * squash))
				var alpha = sin(k * PI) * 0.8
				cols.append(Color(0.55, 0.12, 1.0, alpha))
				thin.append(Color(1.0, 0.75, 1.0, alpha * 0.7))
			_plinec(c, pts, cols, 40.0, true)
			_plinec(c, pts, thin, 10.0, true)

# ---------------------------------------------------------------- Butterfly wings

# Wing outlines in polar form around the wing root: [angle in degrees (y down,
# -90 = up, 0 = outwards), radius]. Forewing has a pointed tip, the hindwing
# a scalloped edge and a swallow tail.
const FORE = [[-90, 90], [-80, 470], [-68, 880], [-56, 1150], [-47, 1220], [-40, 1150], [-31, 990], [-21, 850], [-11, 730], [-1, 600], [8, 420], [16, 200], [22, 80]]
const HIND = [[8, 110], [16, 480], [27, 720], [38, 830], [49, 840], [58, 790], [64, 820], [68, 1120], [71, 1250], [74, 1170], [78, 830], [89, 660], [102, 450], [114, 90]]

func _outline(ctrl: Array, scallop: Vector2) -> Array:
	var key = str(ctrl[0]) + str(ctrl.size())
	var tree = Engine.get_main_loop()
	var cache = tree.get_meta("goob_fx_wing") if tree.has_meta("goob_fx_wing") else {}
	if cache.has(key):
		return cache[key]
	var out = []
	var a0 = float(ctrl[0][0])
	var a1 = float(ctrl[ctrl.size() - 1][0])
	var steps = int((a1 - a0) / 1.5)
	for i in steps + 1:
		var a = lerp(a0, a1, float(i) / steps)
		var j = 0
		while j < ctrl.size() - 2 and ctrl[j + 1][0] < a:
			j += 1
		var p0 = ctrl[max(0, j - 1)][1]
		var p1 = ctrl[j][1]
		var p2 = ctrl[j + 1][1]
		var p3 = ctrl[min(ctrl.size() - 1, j + 2)][1]
		var u = clamp((a - ctrl[j][0]) / max(0.001, ctrl[j + 1][0] - ctrl[j][0]), 0.0, 1.0)
		var r = 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)
		if a > scallop.x and a < scallop.y:
			r -= 38.0 * pow(abs(sin(deg2rad(a) * 13.0)), 0.6)
		out.append(Vector2(cos(deg2rad(a)), sin(deg2rad(a))) * r)
	cache[key] = out
	tree.set_meta("goob_fx_wing", cache)
	return out

func _flap_speed() -> float:
	return clamp(_vel.length() / max(_px, 0.0001) / 4000.0, 0.0, 1.0)

func _flap() -> float:
	return 0.5 + 0.5 * sin(trails.get("flap", 0.0))

func _wing_frame(side: float) -> Transform2D:
	var chest = _at("bone4")
	var f = _flap()
	var open = lerp(0.7, 1.0, f)
	var root = Vector2(-20 + side * 240.0, -1150.0)
	return chest * Transform2D(Vector2(open * side * 1.2, 0), Vector2(0, 1.2 + (1.0 - f) * 0.05), root) * Transform2D(0.2 - (1.0 - f) * 0.1, Vector2.ZERO)

func _emit_bfly(delta, id):
	trails["flap"] = trails.get("flap", 0.0) + delta * lerp(3.4, 10.0, _flap_speed())
	var colors = ITEMS[id].wing
	var fore = _outline(FORE, Vector2(-50, 10))
	var hind = _outline(HIND, Vector2(14, 64))
	for side in [-1.0, 1.0]:
		var frame = _wing_frame(side)
		# Glitter shed from the wing edges.
		for i in _count(id + str(side), 26.0, delta):
			var edge = fore if randf() < 0.6 else hind
			var at = edge[int(rand_range(0, edge.size()))] * rand_range(0.8, 1.0)
			_add({"tex": "spark", "layer": 3 if randf() < 0.35 else 1, "p": frame.xform(at), "v": Vector2(rand_range(-80, 80), rand_range(40, 240)), "life": rand_range(0.8, 1.6),
				"s0": rand_range(60, 140), "s1": 10.0, "c0": Color(colors[3]), "c1": Color(colors[2]).linear_interpolate(Color(0, 0, 0, 0), 0.6), "tw": 22.0, "wave": 3.0, "wamp": 160.0})
		for i in _count(id + "dust" + str(side), 18.0, delta):
			var edge = fore if randf() < 0.6 else hind
			_add({"tex": "core", "layer": 1, "p": frame.xform(edge[int(rand_range(0, edge.size()))] * rand_range(0.3, 0.95)), "v": Vector2(rand_range(-40, 40), rand_range(30, 120)), "life": rand_range(0.6, 1.2),
				"s0": rand_range(14, 26), "s1": 4.0, "c0": Color(colors[2]), "c1": Color(colors[3]).linear_interpolate(Color(0, 0, 0, 0), 0.7)})
	for i in _count(id + "mini", 0.9, delta):
		_add({"tex": "mini", "id": id, "layer": 3, "p": Vector2.ZERO, "life": rand_range(2.4, 3.4), "s0": 190.0, "s1": 150.0, "fin": 0.15,
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": rand_range(1.2, 1.8) * (1 if randf() < 0.5 else -1), "r": rand_range(900, 1150), "y": rand_range(-1600, -500), "dy": rand_range(-200, 100), "tilt": 0.35},
			"c0": Color(colors[3]), "c1": Color(colors[2])})

func _wing_fill(c, edge: Array, ring: Array, cols: Array) -> void:
	# Fan from the root in bands: ring = band radii, cols = band colours.
	var n = edge.size()
	for i in n - 1:
		var a = edge[i]
		var b = edge[i + 1]
		_tri(c, Vector2.ZERO, a * ring[0], b * ring[0], cols[0], cols[1], cols[1])
		for k in ring.size() - 1:
			_quad(c, a * ring[k], a * ring[k + 1], b * ring[k + 1], b * ring[k], cols[k + 1], cols[k + 2], cols[k + 2], cols[k + 1])

func _draw_wing(c, layer: int, edge: Array, id: String, hind: bool, side: float) -> void:
	var colors = ITEMS[id].wing
	var deep = Color(colors[0])
	var main = Color(colors[1])
	var pale = Color(colors[2])
	var glow = Color(colors[3])
	var n = edge.size()
	if layer == 0:
		# The wing never changes shape, so its mesh is built once and reused.
		var key = id + ("_hind" if hind else "_fore")
		if _wing_mesh.has(key):
			_flush(c)
			_draw_cached_mesh(c,key)
			_pline(c, PoolVector2Array([Vector2.ZERO] + edge + [Vector2.ZERO]), Color(0.0, 0.0, 0.0, 0.6), 14.0, true)
			return
		_flush(c)
		var bright = main.linear_interpolate(pale, 0.35)
		_wing_fill(c, edge, [0.18, 0.55, 0.8, 0.86, 1.0], [deep, deep.linear_interpolate(main, 0.6), main, bright, deep, deep])
		# Veins out from the root.
		for i in range(3, n - 2, 7):
			_seg(c, Vector2.ZERO, edge[i] * 0.86, 9.0, Color(deep.r, deep.g, deep.b, 0.8))
		# Spots in the dark margin and a white band near the forewing tip.
		for i in range(2, n - 1, 3):
			_ellipse(c, edge[i] * 0.93, Vector2(26, 26), Color(pale.r, pale.g, pale.b, 1.0), Color(pale.r, pale.g, pale.b, 0.6), 10)
		if not hind:
			for k in 3:
				var at = edge[int(n * (0.28 + k * 0.07))] * 0.72
				_ellipse(c, at, Vector2(70, 46), pale, Color(pale.r, pale.g, pale.b, 0.0), 16)
		else:
			var eye = edge[int(n * 0.42)] * 0.6
			_ellipse(c, eye, Vector2(120, 100), deep, deep, 20)
			_ellipse(c, eye, Vector2(80, 66), pale, main, 20)
			_ellipse(c, eye, Vector2(36, 30), deep, deep, 14)
		_wing_mesh[key] = [_mp, _mc, _mi]
		var outline = PoolVector2Array([Vector2.ZERO] + edge + [Vector2.ZERO])
		_pline(c, outline, Color(0.0, 0.0, 0.0, 0.6), 14.0, true)
	else:
		var shimmer = 0.6 + 0.4 * sin(t * 3.0 + side * 2.0 + (1.0 if hind else 0.0))
		var sweep = fmod(t * 0.5 + (0.5 if side < 0 else 0.0), 1.0)
		_inv = _wing_frame(side)
		_glow(c, edge[int(n * 0.45)] * 0.55, 820.0, Color(glow.r, glow.g, glow.b, 0.2 * shimmer))
		_glow(c, edge[int(n * sweep) % n] * 0.8, 360.0, Color(pale.r, pale.g, pale.b, 0.35))
		for i in range(2, n - 1, 6):
			_glow(c, edge[i] * 0.93, 70.0, Color(pale.r, pale.g, pale.b, 0.5 * shimmer))
		_use(c, _wing_frame(side))
		var rim = PoolVector2Array(edge)
		_pline(c, rim, Color(glow.r, glow.g, glow.b, 0.8 * shimmer), 16.0, true)
		for i in range(3, n - 2, 7):
			_seg(c, edge[i] * 0.2, edge[i] * 0.84, 6.0, Color(glow.r, glow.g, glow.b, 0.25 * shimmer))

func _draw_bfly(c, layer, id):
	if layer > 1:
		return
	var fore = _outline(FORE, Vector2(-50, 10))
	var hind = _outline(HIND, Vector2(14, 64))
	for side in [1.0, -1.0]:
		_use(c, _wing_frame(side))
		_draw_wing(c, layer, hind, id, true, side)
		_use(c, _wing_frame(side))
		_draw_wing(c, layer, fore, id, false, side)
	_use(c, Transform2D.IDENTITY)

func _mini(c, p: Particle, size: float, color: Color) -> void:
	var colors = ITEMS[p.id].wing
	var flap = abs(sin(t * 18.0 + p.ph))
	var key = p.id + "_mini"
	if not _wing_mesh.has(key):
		_flush(c)
		var fore = _outline(FORE, Vector2(-50, 10))
		var hind = _outline(HIND, Vector2(14, 64))
		var a = Color(colors[0])
		var b = Color(colors[1])
		var r = Color(colors[2])
		var fore_small = []
		var hind_small = []
		for i in range(0, fore.size(), 3):
			fore_small.append(fore[i])
		for i in range(0, hind.size(), 3):
			hind_small.append(hind[i])
		_wing_fill(c, hind_small, [0.3, 0.85, 1.0], [a, b, r, a])
		_wing_fill(c, fore_small, [0.3, 0.85, 1.0], [a, b, r, a])
		_wing_mesh[key] = [_mp, _mc, _mi]
		_mp = []
		_mc = []
		_mi = []
	var mesh = _wing_mesh[key]
	var fade = PoolColorArray()
	if color.a < 0.99:
		for col in mesh[1]:
			fade.append(Color(col.r, col.g, col.b, col.a * color.a))
	for side in [-1.0, 1.0]:
		var m = Transform2D(0.0, p.p)
		m.x *= side * size * (0.25 + 0.75 * flap) / 1100.0
		m.y *= size / 1100.0
		_use(c, m)
		VisualServer.canvas_item_add_triangle_array(c.get_canvas_item(), mesh[2], mesh[0], mesh[1] if color.a >= 0.99 else fade)
	_use(c, Transform2D.IDENTITY)
	var g = Color(colors[3])
	g.a = color.a * 0.4
	_glow(c, p.p, size * 1.6, g)

# ---------------------------------------------------------------- Refractions

func _gem_pos() -> Vector2:
	return Vector2(-20, -2330 + sin(t * 1.8) * 55.0)

func _emit_refractions(delta, _id):
	var head = _at("bone7")
	var center = head.xform(_gem_pos())
	for i in _count("prism_glint", 34.0, delta):
		var a = randf() * TAU2
		var dir = Vector2(cos(a), sin(a))
		_add({"tex": "spark", "layer": 3 if randf() < 0.6 else 1, "p": center + dir * rand_range(160, 600), "v": dir * rand_range(150, 420), "life": rand_range(0.5, 1.0), "s0": rand_range(60, 130), "s1": 10.0,
			"c0": Color.from_hsv(randf(), 0.5, 1.0, 1.0), "c1": Color.from_hsv(randf(), 0.8, 1.0, 0.0), "tw": 28.0})
	# Prism shards circling the Goober.
	for i in _count("prism_shard", 7.0, delta):
		_add({"tex": "diamond", "p": Vector2.ZERO, "life": rand_range(1.6, 2.4), "s0": rand_range(60, 100), "s1": 30.0, "spin": rand_range(-4, 4), "rot": randf() * TAU2,
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": 1.6, "r": rand_range(800, 1000), "y": rand_range(-1600, -300), "dy": rand_range(-150, 150), "tilt": 0.3},
			"c0": Color.from_hsv(randf(), 0.45, 1.0, 1.0), "c1": Color.from_hsv(randf(), 0.6, 1.0, 0.0)})
	# Caustic flecks of colour drifting over the Goober.
	for i in _count("prism_caustic", 12.0, delta):
		_add({"tex": "soft", "layer": 3, "p": head.xform(Vector2(rand_range(-600, 560), rand_range(-1800, -200))), "v": Vector2(rand_range(-60, 60), rand_range(-60, 60)), "life": rand_range(0.5, 0.9),
			"s0": rand_range(40, 90), "s1": 120.0, "c0": Color.from_hsv(randf(), 0.7, 1.0, 0.35), "c1": Color.from_hsv(randf(), 0.7, 1.0, 0.0)})

func _gem_points(spin: float) -> Array:
	# Octahedral crystal turning about its vertical axis: [top, bottom, ring...]
	var r = 210.0
	var out = [Vector2(0, -330), Vector2(0, 380)]
	for i in 4:
		var a = spin + i * PI / 2.0
		out.append(Vector2(cos(a) * r, sin(a) * r * 0.3 - 20.0))
	return out

func _draw_refractions(c, layer, _id):
	var head = _at("bone7")
	var center = _gem_pos()
	var spin = t * 1.2
	if layer == 1:
		# Rainbow rays turning around the crystal, behind the Goober.
		_use(c, head * Transform2D(0.0, center))
		for i in 12:
			var ang = t * 0.25 + i * TAU2 / 12.0
			var dir = Vector2(cos(ang), sin(ang))
			var side = Vector2(-dir.y, dir.x)
			var length = 1900.0 + 400.0 * sin(t * 1.7 + i * 1.3)
			var col = Color.from_hsv(fmod(i / 12.0 + t * 0.05, 1.0), 0.8, 1.0, 0.3)
			_quad(c, side * 30.0, dir * length + side * 170.0, dir * length - side * 170.0, -side * 30.0, col, Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0), col)
		_glow(c, Vector2.ZERO, 900.0, Color(0.8, 0.85, 1.0, 0.25))
		# Spectrum fanning out below it.
		for i in 7:
			var ang = PI * 0.5 + (i - 3) * 0.11 + sin(t * 1.1) * 0.25
			var dir = Vector2(cos(ang), sin(ang))
			var side = Vector2(-dir.y, dir.x)
			var col = Color.from_hsv(i / 7.0, 0.9, 1.0, 0.55)
			_quad(c, dir * 300.0 + side * 12.0, dir * 1400.0 + side * 60.0, dir * 1400.0 - side * 60.0, dir * 300.0 - side * 12.0, col, Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0), col)
		# Prismatic halo ring.
		for i in 36:
			var a0 = i * TAU2 / 36.0 + t * 0.6
			var col = Color.from_hsv(fmod(i / 36.0 + t * 0.1, 1.0), 0.7, 1.0, 0.55)
			_seg(c, Vector2(cos(a0), sin(a0) * 0.34) * 520.0, Vector2(cos(a0 + TAU2 / 36.0), sin(a0 + TAU2 / 36.0) * 0.34) * 520.0, 18.0, col)
		_use(c, Transform2D.IDENTITY)
		# Spectrum light pool at the feet.
		_use(c, _at("bone4"))
		for i in 6:
			var col = Color.from_hsv(fmod(i / 6.0 + t * 0.08, 1.0), 0.7, 1.0, 0.18)
			_ellipse(c, Vector2(-20 + (i - 2.5) * 120.0, 40), Vector2(520, 140), col, Color(col.r, col.g, col.b, 0.0), 24)
		_use(c, Transform2D.IDENTITY)
		return
	if layer < 2:
		return
	_use(c, head * Transform2D(0.0, center))
	var g = _gem_points(spin)
	var top = g[0]
	var bottom = g[1]
	if layer == 2:
		# Facets: those facing the viewer, lit by angle, with a moving sheen.
		for i in 4:
			var a = g[2 + i]
			var b = g[2 + (i + 1) % 4]
			var facing = (a.y + b.y) * 0.5 + 20.0
			if facing < -5.0:
				continue
			var light = clamp(0.5 + (b.x - a.x) / 420.0 * 0.5, 0.15, 1.0)
			var hue = Color.from_hsv(fmod(t * 0.12 + i * 0.25, 1.0), 0.35, 1.0, 0.85)
			var glass = Color(0.55 + 0.45 * light, 0.75 + 0.25 * light, 1.0, 0.8)
			_tri(c, top, a, b, Color(1, 1, 1, 0.95), glass, glass.linear_interpolate(hue, 0.5))
			_tri(c, bottom, a, b, hue.darkened(0.25), glass.darkened(0.2), glass.darkened(0.1))
	else:
		var pulse = 0.85 + 0.15 * sin(t * 5.0)
		var edges = PoolVector2Array([top, g[2], bottom, g[4], top, g[3], bottom, g[5], top])
		_pline(c, edges, Color(1, 1, 1, 0.55), 7.0, true)
		_glow(c, Vector2.ZERO, 560.0 * pulse, Color(0.75, 0.85, 1.0, 0.4))
		_flare(c, top, 380.0 * pulse, t * 0.6, Color(1, 1, 1, 0.9))
		_flare(c, g[2 + int(t * 2.0) % 4], 220.0, -t, Color(1, 1, 1, 0.7))
		# Light beam from above into the crystal.
		_quad(c, Vector2(-60, -2400), Vector2(60, -2400), Vector2(20, -300), Vector2(-20, -300), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.35))
	_use(c, Transform2D.IDENTITY)

# ---------------------------------------------------------------- Falling Star

func _star_pos() -> Vector2:
	return Vector2(-20 + sin(t * 1.1) * 60.0, -2380 + sin(t * 2.0) * 60.0)

func _emit_falling(delta, _id):
	var head = _at("bone7")
	var chest = _at("bone4")
	var center = head.xform(_star_pos())
	for i in _count("fstar_glitter", 56.0, delta):
		_add({"tex": "spark", "layer": 3 if randf() < 0.6 else 1, "p": center + Vector2(rand_range(-280, 280), rand_range(-120, 160)), "v": Vector2(rand_range(-280, 280), rand_range(80, 320)), "g": Vector2(0, 300), "drag": 0.6,
			"life": rand_range(0.9, 1.6), "s0": rand_range(70, 150), "s1": 12.0, "c0": Color(0.95, 0.8, 1.0, 1.0), "cm": Color(0.75, 0.4, 1.0, 0.9), "c1": Color(0.5, 0.15, 1.0, 0.0), "tw": 26.0, "wave": 4.0, "wamp": 220.0})
	# Star rain down the whole Goober.
	for i in _count("fstar_rain", 60.0, delta):
		_add({"tex": "spark" if randf() < 0.7 else "star", "layer": 3 if randf() < 0.5 else 1, "p": chest.xform(Vector2(rand_range(-1000, 1000), rand_range(-2500, -1900))), "v": Vector2(rand_range(-40, 40), rand_range(500, 900)),
			"life": rand_range(1.6, 2.4), "s0": rand_range(60, 130), "s1": 20.0, "spin": rand_range(-3, 3), "c0": Color(0.95, 0.85, 1.0, 1.0), "c1": Color(0.6, 0.3, 1.0, 0.0), "tw": 20.0, "fout": 0.6})
	# Ring of little stars around the waist.
	for i in _count("fstar_ring", 14.0, delta):
		_add({"tex": "star", "p": Vector2.ZERO, "life": rand_range(1.2, 1.8), "s0": rand_range(70, 120), "s1": 30.0, "spin": 3.0,
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": 2.0, "r": rand_range(900, 1000), "y": -800.0, "tilt": 0.28, "lean": 0.12},
			"c0": Color(1.0, 0.88, 1.0, 1.0), "c1": Color(0.6, 0.3, 1.0, 0.0)})
	for i in _count("fstar_orbit", 12.0, delta):
		_add({"tex": "star", "p": Vector2.ZERO, "life": rand_range(1.2, 1.8), "s0": rand_range(40, 70), "s1": 20.0, "spin": 3.0,
			"orbit": {"bone": "bone7", "cx": -20.0, "a": randf() * TAU2, "w": 2.6, "r": rand_range(440, 560), "y": _star_pos().y + 60.0, "tilt": 0.3},
			"c0": Color(1.0, 0.85, 1.0, 1.0), "c1": Color(0.6, 0.3, 1.0, 0.0)})
	if not _emit.has("shoot") or t >= _emit.shoot:
		_emit["shoot"] = t + rand_range(0.7, 1.4)
		var side = -1.0 if randf() < 0.5 else 1.0
		var from = Vector2(side * rand_range(-1300, -700), rand_range(-3000, -2400))
		_add({"tex": "streak", "layer": 3, "p": chest.xform(from), "v": Vector2(-side * 2600, 1500), "stretch": 900.0, "life": 0.5, "s0": 140.0, "s1": 60.0, "aspect": Vector2(1.0, 0.16), "c0": Color(1, 0.92, 1, 1), "c1": Color(0.6, 0.3, 1.0, 0.0), "fin": 0.05})

func _draw_falling(c, layer, _id):
	var head = _at("bone7")
	var center = _star_pos()
	var pulse = 0.88 + 0.12 * sin(t * 4.5)
	if layer == 1:
		_use(c, _at("bone4"))
		_glow(c, Vector2(-20, -1100), 1400.0, Color(0.45, 0.15, 0.95, 0.2 + 0.05 * sin(t * 2.4)))
		_use(c, Transform2D.IDENTITY)
		return
	if layer < 2:
		return
	_use(c, head)
	if layer == 3:
		_glow(c, center, 1200.0 * pulse, Color(0.5, 0.2, 1.0, 0.45))
		_glow(c, center, 500.0, Color(1.0, 0.88, 1.0, 0.5))
		_flare(c, center, 1000.0 * pulse, t * 0.3, Color(0.95, 0.85, 1.0, 0.7))
		_flare(c, center, 560.0, -t * 0.5 + 0.4, Color(1, 1, 1, 0.6))
		_sprite(c, "ring", center, Vector2(520, 520) * (1.0 + 0.08 * sin(t * 3.0)), 0.0, Color(0.85, 0.7, 1.0, 0.45))
	else:
		var rot = sin(t * 1.3) * 0.3
		_star(c, center, 350.0 * pulse, rot, Color(1, 1, 1, 1), Color(0.95, 0.72, 1.0, 1.0), 5, 0.46)
		_star(c, center, 210.0 * pulse, rot, Color(1, 1, 1, 1), Color(1, 0.95, 1.0, 1.0), 5, 0.46)
	_use(c, Transform2D.IDENTITY)

# ---------------------------------------------------------------- Bolt Skaters

func _foot(name: String) -> Vector2:
	return _at(name).xform(SETUP[name][2]) + Vector2(0, 60)

func _emit_bolt(delta, _id):
	if not bolts.has("next") or t >= bolts.next:
		bolts["next"] = t + 0.05
		var lines = []
		for name in ["bone11", "bone14"]:
			var f = _foot(name)
			for j in 3:
				var a = f + Vector2(rand_range(-230, 230), 0)
				var b = a + Vector2(rand_range(-300, 300), -rand_range(150, 520))
				lines.append(_bolt(a, b, 90.0, 7))
			lines.append(_bolt(f + Vector2(-240, 0), f + Vector2(240, 0), 50.0, 9))
		bolts["lines"] = lines
	var px = _px
	var speed = abs(_vel.x) / max(px, 0.0001)
	for name in ["bone11", "bone14"]:
		var f = _foot(name)
		var tail = trails.get(name, [])
		tail.push_front({"p": _to_world(f), "age": 0.0})
		for p in tail:
			p.age += delta
		while tail.size() > 2 and tail[tail.size() - 1].age > 0.25:
			tail.pop_back()
		trails[name] = tail
		for i in _count(name, 10.0 + clamp(speed / 60.0, 0.0, 90.0), delta):
			_add({"tex": "streak", "world": true, "layer": 1, "p": _to_world(f + Vector2(rand_range(-200, 200), 0)), "v": Vector2(rand_range(-900, 900) - sign(_vel.x) * speed * 0.4, rand_range(-1600, -400)) * px,
				"g": Vector2(0, 5200) * px, "stretch": 1500.0 * px, "life": rand_range(0.2, 0.45), "s0": rand_range(40, 70) * px, "s1": 15.0 * px, "aspect": Vector2(1.0, 0.35), "c0": Color(0.9, 1.0, 1.0, 1.0), "c1": Color(1.0, 0.9, 0.3, 0.0)})

func _draw_bolt(c, layer, _id):
	var speed = _vel.length() / max(_px, 0.0001)
	if layer == 1 and speed > 600.0:
		_use(c, c.get_global_transform().affine_inverse())
		for name in ["bone11", "bone14"]:
			var points = []
			for p in trails.get(name, []):
				points.append(p.p)
			_ribbon(c, points, 160.0 * _px, 0.0, Color(0.4, 0.85, 1.0, 0.6), Color(0.2, 0.4, 1.0, 0.0))
		_use(c, Transform2D.IDENTITY)
	if layer < 2:
		return
	var flicker = 0.7 + 0.3 * sin(t * 47.0)
	for name in ["bone11", "bone14"]:
		var f = _foot(name)
		var a = f + Vector2(-250, 0)
		var b = f + Vector2(250, 0)
		if layer == 2:
			_line(c, a, b, Color(0.1, 0.12, 0.18), 50.0, true)
			_line(c, a + Vector2(0, -26), b + Vector2(0, -26), Color(0.25, 0.3, 0.42), 14.0, true)
		else:
			_glow(c, f, 620.0, Color(0.2, 0.55, 1.0, 0.42 * flicker))
			_glow(c, f, 260.0, Color(0.7, 0.95, 1.0, 0.45 * flicker))
			_line(c, a, b, Color(0.35, 0.85, 1.0, 0.95), 42.0, true)
			_line(c, a, b, Color(1, 1, 1, 1), 14.0, true)
	if layer == 3 and bolts.has("lines"):
		for line in bolts.lines:
			_pline(c, line, Color(0.25, 0.6, 1.0, 0.45 * flicker), 60.0, true)
			_pline(c, line, Color(0.6, 0.95, 1.0, 0.9), 22.0, true)
			_pline(c, line, Color(1, 1, 0.9, 1.0), 8.0, true)

# ---------------------------------------------------------------- Orange Star Eruption

func _emit_star(delta, _id):
	var head = _at("bone7")
	var chest = _at("bone4")
	var top = head.xform(TOP + Vector2(0, 40))
	var burst = 0
	if not _emit.has("star_next") or t >= _emit.star_next:
		_emit["star_next"] = t + 0.75
		_emit["star_flash"] = t
		burst = 18
		_add({"tex": "ring", "layer": 3, "p": top, "life": 0.5, "s0": 140.0, "s1": 1100.0, "aspect": Vector2(1.0, 0.45), "c0": Color(1.0, 0.8, 0.3, 0.9), "c1": Color(1.0, 0.3, 0.0, 0.0), "fin": 0.02})
		for i in 10:
			_add({"tex": "smoke", "layer": 3, "p": top + Vector2(rand_range(-220, 220), rand_range(-60, 40)), "v": Vector2(rand_range(-380, 380), rand_range(-700, -250)), "drag": 2.0, "life": rand_range(0.6, 1.0),
				"s0": rand_range(180, 260), "s1": rand_range(420, 560), "rot": randf() * TAU2, "spin": rand_range(-1, 1), "c0": Color(1.0, 0.55, 0.1, 0.55), "c1": Color(0.6, 0.15, 0.0, 0.0)})
	# A steady fountain of stars plus the bursts.
	for i in burst + _count("star", 22.0, delta):
		var big = i < burst
		var gold = randf() < 0.5
		_add({"tex": "star", "layer": 3, "land": true, "p": top + Vector2(rand_range(-160, 160), 0), "v": Vector2(rand_range(-1100, 1100), rand_range(-3200, -2100) if big else rand_range(-2300, -1500)), "g": Vector2(0, 3800), "drag": 0.2,
			"life": rand_range(1.2, 1.6), "s0": rand_range(120, 190) if big else rand_range(70, 120), "s1": 60.0, "spin": rand_range(-7, 7), "rot": randf() * TAU2,
			"c0": Color(1.0, 0.82, 0.2, 1.0) if gold else Color(1.0, 0.5, 0.08, 1.0), "c1": Color(1.0, 0.25, 0.0, 0.7)})
		if big or randf() < 0.4:
			_add({"tex": "streak", "layer": 3, "p": top, "v": Vector2(rand_range(-800, 800), rand_range(-2600, -1600)), "g": Vector2(0, 3800), "stretch": 500.0, "life": rand_range(0.35, 0.6), "s0": 70.0, "s1": 20.0, "aspect": Vector2(1.0, 0.3),
				"c0": Color(1.0, 0.85, 0.4, 0.9), "c1": Color(1.0, 0.3, 0.0, 0.0)})
	# Flame jet out of the head.
	for i in _count("star_flame", 50.0, delta):
		_add({"tex": "flame", "layer": 3, "p": top + Vector2(rand_range(-160, 160), 30), "v": Vector2(rand_range(-120, 120), rand_range(-1100, -700)), "drag": 2.0, "life": rand_range(0.25, 0.45),
			"s0": rand_range(160, 240), "s1": 40.0, "aspect": Vector2(0.6, 1.4), "fin": 0.15, "c0": Color(1.0, 0.95, 0.7, 0.8), "cm": Color(1.0, 0.55, 0.1, 0.7), "c1": Color(0.8, 0.15, 0.0, 0.0)})
	for i in _count("ember", 34.0, delta):
		_add({"tex": "core", "layer": 3, "p": top + Vector2(rand_range(-220, 220), rand_range(-60, 30)), "v": Vector2(rand_range(-300, 300), rand_range(-1300, -600)), "g": Vector2(0, 1400), "life": rand_range(0.5, 0.9),
			"s0": rand_range(22, 40), "s1": 8.0, "c0": Color(1.0, 0.85, 0.4, 1.0), "c1": Color(1.0, 0.25, 0.0, 0.0), "wave": 8.0, "wamp": 300.0})
	# Embers circling the body.
	for i in _count("star_orbit", 16.0, delta):
		_add({"tex": "spark" if randf() < 0.5 else "star", "p": Vector2.ZERO, "life": rand_range(1.0, 1.6), "s0": rand_range(40, 80), "s1": 15.0, "spin": 4.0,
			"orbit": {"bone": "bone4", "cx": -20.0, "a": randf() * TAU2, "w": 2.2, "r": rand_range(800, 950), "y": rand_range(-600, 0), "dy": rand_range(-900, -500), "tilt": 0.3},
			"c0": Color(1.0, 0.75, 0.25, 1.0), "c1": Color(1.0, 0.3, 0.0, 0.0), "tw": 20.0})
	# Stars that reach the floor burst into sparkles.
	for p in parts:
		if p.land and p.v.y > 0.0 and chest.affine_inverse().xform(p.p).y > 30.0:
			p.land = false
			p.age = p.life - 0.05
			for k in 5:
				var a = rand_range(PI * 1.05, PI * 1.95)
				_add({"tex": "spark", "layer": 3, "p": p.p, "v": Vector2(cos(a), sin(a)) * rand_range(300, 700), "g": Vector2(0, 1500), "life": rand_range(0.3, 0.5), "s0": rand_range(40, 80), "s1": 10.0,
					"c0": Color(1.0, 0.9, 0.5, 1.0), "c1": Color(1.0, 0.4, 0.0, 0.0)})

func _draw_star(c, layer, _id):
	if layer == 1:
		_use(c, _at("bone4"))
		_glow(c, Vector2(-20, -1200), 1300.0, Color(1.0, 0.4, 0.05, 0.16 + 0.05 * sin(t * 3.0)))
		_use(c, Transform2D.IDENTITY)
		return
	if layer != 3:
		return
	var head = _at("bone7")
	var k = clamp((t - _emit.get("star_flash", -9.0)) / 0.4, 0.0, 1.0)
	_use(c, head)
	_glow(c, TOP + Vector2(0, 40), 420.0 + 700.0 * k, Color(1.0, 0.55, 0.1, 0.75 * (1.0 - k) + 0.2))
	_glow(c, TOP + Vector2(0, 40), 220.0, Color(1.0, 0.85, 0.5, 0.5 * (1.0 - k) + 0.18))
	_flare(c, TOP, 900.0 * (1.0 - k) + 120.0, t, Color(1.0, 0.9, 0.6, 0.9 * (1.0 - k) + 0.2))
	_use(c, Transform2D.IDENTITY)

# ---------------------------------------------------------------- Headphone Resonance

func _beat() -> float:
	return pow(max(0.0, cos(t * TAU2 * 2.0)), 12.0)

func _cup(side: float) -> Vector2:
	return HEAD + Vector2(side * (HEAD_R + 40.0), 40)

func _band() -> Array:
	var out = []
	for i in 25:
		var a = lerp(PI * 1.0, PI * 2.0, i / 24.0)
		out.append(HEAD + Vector2(cos(a) * (HEAD_R + 60.0), sin(a) * (HEAD_R + 120.0)))
	return out

func _emit_headphones(delta, _id):
	var head = _at("bone7")
	var beat = _beat()
	if beat > 0.5 and _beat_prev <= 0.5:
		var hue = fmod(t * 0.07, 1.0)
		for side in [-1.0, 1.0]:
			_add({"tex": "note", "layer": 3, "p": head.xform(_cup(side) + Vector2(side * 140, -160)), "v": Vector2(side * rand_range(200, 380), rand_range(-620, -420)), "drag": 0.7, "life": 1.6,
				"s0": rand_range(170, 220), "s1": 150.0, "rot": rand_range(-0.3, 0.3), "spin": side * 0.5, "double": randf() < 0.45, "wave": 5.0, "wamp": 500.0,
				"c0": Color.from_hsv(fmod(hue + 0.5 + rand_range(0, 0.3), 1.0), 0.65, 1.0, 1.0), "c1": Color.from_hsv(fmod(hue + 0.8, 1.0), 0.7, 1.0, 1.0)})
			_add({"tex": "ring", "layer": 3, "p": head.xform(_cup(side)), "life": 0.55, "s0": 220.0, "s1": 760.0, "aspect": Vector2(0.6, 1.0), "c0": Color.from_hsv(fmod(hue + 0.55, 1.0), 0.6, 1.0, 0.8), "c1": Color.from_hsv(fmod(hue + 0.75, 1.0), 0.7, 1.0, 0.0), "fin": 0.02})
	_beat_prev = beat
	for i in _count("hp_spark", 12.0, delta):
		var side = -1.0 if randf() < 0.5 else 1.0
		_add({"tex": "spark", "layer": 3, "p": head.xform(_cup(side) + Vector2(rand_range(-150, 150), rand_range(-250, 250))), "v": Vector2(side * rand_range(80, 220), rand_range(-260, -80)), "life": rand_range(0.5, 0.9),
			"s0": rand_range(50, 100), "s1": 10.0, "c0": Color.from_hsv(fmod(0.55 + t * 0.07, 1.0), 0.5, 1.0, 1.0), "c1": Color(1, 1, 1, 0), "tw": 24.0})

func _note(c, at: Vector2, size: float, rot: float, color: Color, double: bool) -> void:
	var m = Transform2D(rot, at)
	var heads = [Vector2(-0.3, 0.55)] if not double else [Vector2(-0.55, 0.62), Vector2(0.45, 0.42)]
	var glow = color
	glow.a *= 0.5
	_inv = Transform2D.IDENTITY
	_glow(c, at, size * 2.2, glow)
	_use(c, Transform2D.IDENTITY)
	for h in heads:
		var center = m.xform(h * size)
		var e = []
		for i in 14:
			var a = i * TAU2 / 14.0
			e.append(center + Vector2(cos(a) * size * 0.3, sin(a) * size * 0.21).rotated(rot - 0.4))
		for i in 14:
			_tri(c, center, e[i], e[(i + 1) % 14], Color(1, 1, 1, color.a), color, color)
		_line(c, center + Vector2(size * 0.26, 0).rotated(rot), center + Vector2(size * 0.26, -size * 1.05).rotated(rot), color, size * 0.1, true)
	if double:
		_line(c, m.xform(Vector2(-0.32, -0.45) * size), m.xform(Vector2(0.73, -0.65) * size), color, size * 0.18, true)
	else:
		var flag = PoolVector2Array([m.xform(Vector2(-0.04, -0.5) * size), m.xform(Vector2(0.25, -0.3) * size), m.xform(Vector2(0.32, 0.0) * size)])
		_pline(c, flag, color, size * 0.12, true)

func _draw_headphones(c, layer, _id):
	if layer < 2:
		return
	var head = _at("bone7")
	var beat = _beat()
	var hue = fmod(0.55 + t * 0.07, 1.0)
	var neon = Color.from_hsv(hue, 0.7, 1.0, 1.0)
	var neon2 = Color.from_hsv(fmod(hue + 0.25, 1.0), 0.7, 1.0, 1.0)
	_use(c, head)
	var band = PoolVector2Array(_band())
	if layer == 2:
		_pline(c, band, Color(0.07, 0.07, 0.09), 110.0, true)
		_pline(c, band, Color(0.2, 0.21, 0.26), 40.0, true)
		for side in [-1.0, 1.0]:
			var cup = _cup(side)
			var s = 1.0 + 0.05 * beat
			_ellipse(c, cup, Vector2(170, 300) * s, Color(0.2, 0.21, 0.26), Color(0.06, 0.06, 0.08), 26)
			_ellipse(c, cup + Vector2(side * 30, 0), Vector2(110, 220) * s, Color(0.1, 0.1, 0.13), Color(0.03, 0.03, 0.04), 22)
			# Equaliser bars on the cup.
			for i in 5:
				var level = 0.3 + 0.7 * abs(sin(t * (6.0 + i * 1.7) + i * 1.3)) * (0.5 + 0.5 * beat)
				var x = cup.x + side * 30 + (i - 2) * 36.0
				_line(c, Vector2(x, cup.y + 110), Vector2(x, cup.y + 110 - level * 200.0), neon.linear_interpolate(neon2, i / 4.0), 22.0)
	else:
		_pline(c, band, Color(neon.r, neon.g, neon.b, 0.6 + 0.4 * beat), 16.0, true)
		for side in [-1.0, 1.0]:
			var cup = _cup(side)
			_ring(c, cup + Vector2(side * 30, 0), Vector2(130, 240) * (1.0 + 0.05 * beat), 18.0, Color(neon2.r, neon2.g, neon2.b, 0.7 + 0.3 * beat))
			_inv = head
			_glow(c, cup, 520.0 + 260.0 * beat, Color(neon.r, neon.g, neon.b, 0.3 + 0.35 * beat))
			_inv = Transform2D.IDENTITY
			_use(c, head)
	_use(c, Transform2D.IDENTITY)

# Static coloured wing artwork remains in a native mesh between display frames.
func _draw_cached_mesh(c,key):
	if not _wing_gpu.has(key):
		var source = _wing_mesh[key]
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices = PoolVector3Array()
		for point in source[0]: vertices.append(Vector3(point.x,point.y,0))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = PoolColorArray(source[1])
		arrays[Mesh.ARRAY_INDEX] = PoolIntArray(source[2])
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_wing_gpu[key] = mesh
	c.draw_mesh(_wing_gpu[key],null)
