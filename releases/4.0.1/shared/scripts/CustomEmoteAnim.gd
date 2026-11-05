extends Node2D

# Level 15 emotes: their own animation, drawn inside the native emote bubble.
# Layers are 4x PNGs of the 218x157 bubble; this node's origin is the bubble
# centre. Presentation only.

const DIR = "user://mod/tools/avatar-studio/assets/custom/emotes/"
const CENTRE = Vector2(109, 80)
const LAYERS = {
	"emote_world_record": {"watch": Vector2(109, 80), "hand": Vector2(109, 80), "badge": Vector2(160, 40), "spark": Vector2(109, 80)},
	"emote_salute": {"face": Vector2(109, 80), "arm": Vector2(150, 92), "spark": Vector2(109, 80)},
	"emote_dead": {"skull": Vector2(109, 80), "tear": Vector2(109, 80)},
	"emote_yawn": {"face": Vector2(109, 80), "mouth": Vector2(109, 102), "tear": Vector2(109, 80), "z": Vector2(150, 34)},
}

var id = ""
var still = false
var t = 0.0
var parts = {}
var _textures = {}
var _bone = null
var _setup = null

func setup(emote_id: String, static_pose = false) -> void:
	id = emote_id
	still = static_pose

func _ready():
	for layer in LAYERS.get(id, {}):
		var copies = 3 if layer in ["spark", "tear", "z"] else 1
		parts[layer] = []
		for i in copies:
			parts[layer].append(_part(layer))
	_pose(99.0 if still else 0.0)

func _part(layer):
	var pivot = Node2D.new()
	pivot.position = LAYERS[id][layer] - CENTRE
	add_child(pivot)
	var sprite = Sprite.new()
	sprite.texture = _texture(layer)
	sprite.scale = Vector2(0.25, 0.25)
	sprite.position = CENTRE - LAYERS[id][layer]
	pivot.add_child(sprite)
	return pivot

func _texture(layer):
	var path = DIR + id + "_" + layer + ".png"
	if not _textures.has(path):
		var image = Image.new()
		var tex = ImageTexture.new()
		if image.load(path) == OK:
			tex.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		_textures[path] = tex
	return _textures[path]

func _process(delta):
	_follow()
	if still:
		return
	t += delta
	_pose(t)

# Rides the emote rig's "base" bone (the bubble's pop and wobble). The icon
# sits at the base bone's setup position, so only the change from setup moves it.
func _follow():
	var sprite = get_parent()
	if sprite == null or not sprite.has_method("get_skeleton"):
		return
	if _bone == null:
		var skeleton = sprite.get_skeleton()
		_bone = skeleton.find_bone("base") if skeleton != null else null
		if _bone == null:
			return
		# base bone in setup pose, y-down (from the emote skeleton); a detached reference skeleton reports no world pose.
		_setup = Transform2D(Vector2(-0.0085, -1.0), Vector2(-1.0, 0.0085), Vector2(-0.066, 113.25))
	var delta = _frame(_bone) * _setup.affine_inverse()
	# If the bone values don't line up with the sprite, stay put rather than fly off.
	if delta.origin.length() > 150.0 or abs(delta.get_rotation()) > 0.8:
		delta = Transform2D.IDENTITY
	transform = delta

func _frame(bone) -> Transform2D:
	var f = Transform2D(Vector2(bone.get_a(), bone.get_c()), Vector2(bone.get_b(), bone.get_d()), Vector2(bone.get_world_x(), bone.get_world_y()))
	# The bone points up. If its values come y-up, mirror them into the
	# sprite's y-down space.
	if f.x.y > 0.0:
		var s = Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2.ZERO)
		f = s * f * s
	return f

static func _pop(x, at, length = 0.3):
	# ease-out-back: 0 -> a little past 1 -> 1
	var k = clamp((x - at) / length, 0.0, 1.0)
	if k <= 0.0:
		return 0.0
	var u = k - 1.0
	return 1.0 + 2.70158 * u * u * u + 1.70158 * u * u

func _place(layer, i, pos, rot, scale, alpha):
	var p = parts[layer][i]
	p.position = LAYERS[id][layer] - CENTRE + pos
	p.rotation_degrees = rot
	p.scale = Vector2(scale, scale)
	p.modulate.a = clamp(alpha, 0.0, 1.0)

func _pose(x):
	match id:
		"emote_world_record":
			var pop = _pop(x, 0.0)
			_place("watch", 0, Vector2.ZERO, 0, pop * (1.0 + 0.12 * _bump(x, 1.1)), 1)
			# the hand races round, then stops dead on the record
			var spin = 1.0 - pow(1.0 - clamp((x - 0.15) / 0.95, 0.0, 1.0), 3)
			_place("hand", 0, Vector2.ZERO, spin * 360.0 * 5.0, pop, 1)
			var stamp = clamp((x - 1.15) / 0.18, 0.0, 1.0)
			_place("badge", 0, Vector2.ZERO, -25 * (1.0 - stamp), lerp(2.6, 1.0, stamp) if stamp > 0 else 0.0, stamp * 4.0)
			for i in 3:
				var k = clamp((x - 1.2 - i * 0.08) / 0.45, 0.0, 1.0)
				var dir = [Vector2(-52, -30), Vector2(48, 30), Vector2(-40, 34)][i]
				_place("spark", i, dir * (0.5 + k * 0.6), k * 90.0, sin(k * PI) * 1.3, 1)
		"emote_salute":
			_place("face", 0, Vector2(0, _bump(x, 0.42, 0.2) * 2.0), 0, _pop(x, 0.0), 1)
			# the arm snaps up to the brow, holds, and the tip glints
			var up = 1.0 - pow(1.0 - clamp((x - 0.2) / 0.22, 0.0, 1.0), 3)
			_place("arm", 0, Vector2(lerp(10.0, -6.0, up), lerp(26.0, 6.0, up)), lerp(70.0, -28.0, up) + _bump(x, 0.42, 0.18) * -10.0, 1.0, 1.0 if x > 0.18 else 0.0)
			for i in 3:
				var k = clamp((x - 0.45 - i * 0.07) / 0.4, 0.0, 1.0)
				var dir = [Vector2(28, -46), Vector2(48, -30), Vector2(40, -58)][i]
				_place("spark", i, dir, k * 90.0, sin(k * PI) * 0.8, 1)
		"emote_dead":
			var shake = sin(x * 42.0) * 9.0 * (0.55 + 0.45 * abs(sin(x * 3.2)))
			_place("skull", 0, Vector2(0, -abs(sin(x * 21.0)) * 4.0), shake, _pop(x, 0.0), 1)
			for i in 3:
				var k = fmod(max(0.0, x - 0.25 - i * 0.22), 0.66) / 0.66
				var side = -1.0 if i % 2 == 0 else 1.0
				_place("tear", i, Vector2(side * (26 + k * 34), -6 - sin(k * PI) * 26 + k * 30), 0, 1.0, (1.0 - k) * (1.0 if x > 0.25 else 0.0))
		"emote_yawn":
			# a big lazy yawn, a sleepy tear, a couple of z's
			var open = _bump(x, 0.2, 1.1)
			_place("face", 0, Vector2(0, -open * 3.0), -open * 6.0, _pop(x, 0.0), 1)
			_place("mouth", 0, Vector2(0, -open * 3.0), 0, 1.0, 1)
			parts["mouth"][0].scale = Vector2(0.7 + open * 0.5, 0.25 + open * 1.25)
			var tk = clamp((x - 0.8) / 0.8, 0.0, 1.0)
			_place("tear", 0, Vector2(-22, -4 + tk * 18), 0, 0.8, sin(tk * PI))
			_place("tear", 1, Vector2.ZERO, 0, 0, 0)
			_place("tear", 2, Vector2.ZERO, 0, 0, 0)
			for i in 3:
				var k = fmod(max(0.0, x - 0.9 - i * 0.35), 1.05) / 1.05
				_place("z", i, Vector2(k * 18.0 + i * 4, -k * 34.0), sin(k * 6.0) * 12.0, 0.6 + k * 0.7, sin(k * PI) if x > 0.9 + i * 0.35 else 0.0)

static func _bump(x, at, width = 0.16):
	var k = (x - at) / width
	if k < 0.0 or k > 1.0:
		return 0.0
	return sin(k * PI)
