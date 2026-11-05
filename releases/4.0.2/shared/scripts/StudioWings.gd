extends Node2D

# Avatar Studio wings (local only): a pair of folded black wings behind the
# Goober. They ride the body bone, breathe while idle and react to movement:
# lift when falling, beat down on a jump, fold back a little at speed.

const TEXTURE = "user://mod/tools/avatar-studio/assets/custom/wing_black.png"
const ROOT_PX = Vector2(20, 260)          # wing root inside the texture
const SIZES = {"small": 0.75, "medium": 1.0, "large": 1.3}
# Wing roots on the Goober's back, setup pose (y down, skeleton units).
const ROOTS = [Vector2(230, -1080), Vector2(-270, -1080)]
const REST = -0.4                        # radians; spread out from the back, tips low

var target = null
var size = "medium"
var wings = []
var angle = REST
var spin = 0.0
var fold = 0.0
var t = 0.0
var _last = null
var _vel = Vector2.ZERO
var _bone = null
var _setup = null
var _flapped = false

var colour_mode = "original"
var colour = Color.white

# options: the effect's colour option ("original", "goober" or "custom" + hex).
func configure(goober, wing_size: String, options: Dictionary = {}, tint: Color = Color("49a8ff")) -> void:
	target = goober
	size = wing_size if SIZES.has(wing_size) else "medium"
	colour_mode = str(options.get("mode", "original"))
	colour = tint if colour_mode == "goober" else Color(str(options.get("hex", "ff5ad2")))
	for w in wings:
		w.get_child(0).scale = Vector2.ONE * SIZES[size]
	_apply_colour()


# The wing art is black, so a tint can't simply multiply it: shade the chosen
# colour by the texture's brightness instead (dark base, lighter feathers).
func _apply_colour() -> void:
	for i in wings.size():
		var sprite = wings[i].get_child(0)
		if colour_mode == "original":
			sprite.material = null
			continue
		var material = sprite.material as ShaderMaterial
		if material == null:
			material = ShaderMaterial.new()
			material.shader = _wing_shader()
			sprite.material = material
		material.set_shader_param("tint", colour.darkened(0.12) if i == 1 else colour)

func _ready():
	show_behind_parent = true
	if get_parent() != null:
		get_parent().call_deferred("move_child", self, 0)
	for i in 2:
		var pivot = Node2D.new()
		pivot.position = ROOTS[i]
		add_child(pivot)
		var sprite = Sprite.new()
		sprite.texture = _tex()
		sprite.centered = false
		sprite.offset = -ROOT_PX
		sprite.scale = Vector2.ONE * SIZES[size]
		if i == 1:
			# far wing: mirrored and a touch darker
			pivot.scale.x = -1
			sprite.modulate = Color(0.82, 0.82, 0.88)
		pivot.add_child(sprite)
		wings.append(pivot)
	_apply_colour()

func _wing_shader() -> Shader:
	var tree = Engine.get_main_loop()
	if not tree.has_meta("goob_wing_shader"):
		var shader = Shader.new()
		shader.code = "shader_type canvas_item; uniform vec4 tint : hint_color = vec4(1.0); void fragment(){ vec4 t = texture(TEXTURE, UV); float l = clamp(dot(t.rgb, vec3(0.299, 0.587, 0.114)) * 2.2, 0.0, 1.0); COLOR = vec4(mix(tint.rgb * 0.42, mix(tint.rgb, vec3(1.0), 0.45), l), t.a * COLOR.a); }"
		tree.set_meta("goob_wing_shader", shader)
	return tree.get_meta("goob_wing_shader")


func _tex():
	var tree = Engine.get_main_loop()
	if not tree.has_meta("goob_wing_texture"):
		var image = Image.new()
		var tex = ImageTexture.new()
		if image.load(TEXTURE) == OK:
			tex.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		tree.set_meta("goob_wing_texture", tex)
	return tree.get_meta("goob_wing_texture")

func _process(delta):
	if delta <= 0.0:
		return
	# Nothing to do while the Goober is hidden (closed Studio, cards out of view).
	var sprite = get_parent()
	if sprite == null or not sprite.is_visible_in_tree():
		return
	_follow()
	t += delta
	# movement in screen space, smoothed
	var pos = get_parent().global_position if get_parent() is Node2D else Vector2.ZERO
	if _last != null:
		_vel = _vel.linear_interpolate((pos - _last) / delta, min(1.0, delta * 12.0))
	_last = pos
	var fall = clamp(_vel.y / 1400.0, -1.0, 1.0)
	var speed = clamp(abs(_vel.x) / 1200.0, 0.0, 1.0)
	# a sharp upward change is a jump: beat the wings down
	if _vel.y < -700.0 and not _flapped:
		spin += 9.0
		_flapped = true
	elif _vel.y > -200.0:
		_flapped = false
	var breathe = sin(t * 2.4) * 0.07 + sin(t * 5.1) * 0.015
	var goal = REST + breathe - fall * 0.45 - speed * 0.18
	spin += ((goal - angle) * 130.0 - spin * 11.0) * delta
	angle += spin * delta
	angle = clamp(angle, -0.9, 0.9)
	fold = lerp(fold, speed * 0.22, min(1.0, delta * 6.0))
	for i in wings.size():
		var w = wings[i]
		w.rotation = angle if i == 0 else -angle
		w.scale = Vector2((1.0 - fold) * (1 if i == 0 else -1), 1.0 + fold * 0.1)

# Rides the Goober's body bone (squash, lean and bounce of the animations).
func _follow():
	var sprite = get_parent()
	if sprite == null or not sprite.has_method("get_skeleton"):
		return
	if _bone == null:
		var skeleton = sprite.get_skeleton()
		_bone = skeleton.find_bone("bone4") if skeleton != null else null
		if _bone == null:
			return
		# Chest bone in setup pose, in the runtime's y-down convention (UPGUY.skel).
		_setup = Transform2D(Vector2(-0.002, -1.0), Vector2(-1.0, 0.002), Vector2(-1.16, -816.64))
	var frame = _frame(_bone)
	var delta = Transform2D.IDENTITY
	# A Goober that never animated reports an identity frame.
	if not (is_equal_approx(frame.x.x, 1.0) and is_equal_approx(frame.y.y, 1.0) and frame.origin == Vector2.ZERO):
		delta = frame * _setup.affine_inverse()
		# If the bone values don't line up with the sprite, stay put rather than fly off.
		if delta.origin.length() > 700.0 or abs(delta.get_rotation()) > 1.2:
			delta = Transform2D.IDENTITY
	transform = delta

func _frame(bone) -> Transform2D:
	return Transform2D(Vector2(bone.get_a(), bone.get_c()), Vector2(bone.get_b(), bone.get_d()), Vector2(bone.get_world_x(), bone.get_world_y()))
