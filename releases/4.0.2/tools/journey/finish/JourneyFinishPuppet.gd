extends Node2D
# A cosmetic Goober for Journey finish animations: a copy of the native Goober
# rig (project_specific/gfx/spine/upguy/upguy.tscn) with its own animation
# state, never the player's own sprite. Choreographies set a few high-level
# pose values every frame; this node turns them into the rig:
#   anim / anim_loop / mix  native animation on track 0 (Idle, Run, floss …)
#   arm_l, arm_r            degrees added to each arm, + = away from the body
#   elbow                   degrees added to both forearms (+ = open)
#   feet                    Vector2 offset of both feet IK targets, in units of
#                           the Goober's height (+y = towards the body)
#   feet_spread             pushes the feet apart (units of height)
#   lean                    degrees added to the body (+ = tip right)
#   squash                  scale.y multiplier (x compensates)
#   scale_mul               depth / barrel-roll scale
#   face                    "normal", "wince" (both eyes squeezed, the rig's
#                           own EYES-wince) or "wink" (one eye, plain face only)
# Offsets are added after the animation is applied each frame and the bones
# are reset to the setup pose first, so nothing accumulates.
#
# Without the Spine runtime (tests outside the game) a flat stand-in with the
# same pose values is drawn instead.
const HEIGHT = 700.0

var skin = {}
var tint = Color("40b8ff")
var anim = "Idle"
var anim_loop = true
var mix = 0.18
var arm_l = 0.0
var arm_r = 0.0
var elbow = 0.0
var feet = Vector2.ZERO
var feet_spread = 0.0
var lean = 0.0
var squash = 1.0
var face = "normal"
var facing = 1.0
var size = 60.0
var scale_mul = Vector2.ONE
# Extra per-bone offsets for full poses (sitting, riding), in skeleton units:
# {"Body": Vector3(rotation, x, y)}. Poses were built against the real rig.
var bones_extra = {}

var spine = null
var _bones = {}
var _pose_ok = false
var _eye_slot = null
var _eye_normal = null
var _eye_wince = null
var _wink_material = null
var _face_node = null
var _playing = ""
var _plain_face = true

func _ready():
	if ClassDB.class_exists("SpineSprite") and ResourceLoader.exists("res://project_specific/gfx/spine/upguy/upguy.tscn"):
		spine = load("res://project_specific/gfx/spine/upguy/upguy.tscn").instance()
		spine.enable_sounds = false
		spine.enable_blink = false
		spine.apply_defaults = true
		add_child(spine)
		spine.set_goober_skin_data(skin if not skin.empty() else {"color": "color_default"})
		spine.set_update_mode(2)
		_play(anim, true)
		spine.update_skeleton(0.0)
		_bind()
	apply_size()

func apply_size():
	if spine != null:
		spine.scale = Vector2.ONE * size / HEIGHT
	update()

func _bind():
	_bones.clear()
	var skeleton = spine.get_skeleton()
	for name in ["Body", "bone4", "Arm-left", "bone9b", "Arm-right", "bone12b", "Leg-left2", "Leg-right2"]:
		var bone = skeleton.find_bone(name)
		if bone != null:
			_bones[name] = bone
	_pose_ok = spine.has_signal("before_animation_state_apply") and spine.has_signal("before_world_transforms_change") and _bones.has("Body")
	if _pose_ok and not spine.is_connected("before_animation_state_apply", self, "_reset_pose"):
		spine.connect("before_animation_state_apply", self, "_reset_pose")
		spine.connect("before_world_transforms_change", self, "_apply_pose")
	_eye_slot = skeleton.find_slot("eyes")
	_eye_normal = null
	_eye_wince = null
	_plain_face = false
	if _eye_slot != null and _eye_slot.get_attachment() != null:
		_eye_normal = _eye_slot.get_attachment()
		_plain_face = _eye_normal.get_attachment_name().begins_with("eyes/EYES-")
		if _plain_face:
			_eye_wince = skeleton.get_attachment_by_slot_name("eyes", "eyes/EYES-wince")
	# Face-covering hats keep the plain eyes but hide them: no expressions then.
	for key in skin:
		if str(key) in ["hat", "face", "eyes", "mask", "head"] and not str(skin[key]).ends_with("_default") and str(skin[key]) != "":
			_plain_face = false
	if _plain_face and _face_node == null:
		_face_node = ClassDB.instance("SpineSlotNode")
		spine.add_child(_face_node)
		_face_node.slot_name = "eyes"
		var shader = Shader.new()
		# Wink: one eye replaced by the dash face's closed eye (bundled UPGUY-3
		# atlas coordinates, as in the approved prototype).
		shader.code = """shader_type canvas_item;
uniform bool wink = false;
void fragment() {
 vec2 px = UV / TEXTURE_PIXEL_SIZE;
 vec2 sample_uv = UV;
 if (wink && px.x > 3902.0 && px.x < 3953.0 && px.y >= 384.0 && px.y <= 413.0) {
   sample_uv = vec2(clamp(3870.0 + (px.x - 3852.0) * .86,3913.5,3955.5), clamp(464.0 + px.y - 385.0,464.5,490.5)) * TEXTURE_PIXEL_SIZE;
 }
 COLOR = texture(TEXTURE, sample_uv) * COLOR;
 if (wink && px.x > 3895.0 && px.x < 3910.0) { COLOR.a = 0.0; }
}"""
		_wink_material = ShaderMaterial.new()
		_wink_material.shader = shader
		_face_node.normal_material = _wink_material

func _play(name, force = false):
	if spine == null or (name == _playing and not force):
		return
	var data = spine.get_skeleton().get_data()
	if data != null and data.find_animation(name) == null:
		name = "Idle"
	var entry = spine.get_animation_state().set_animation(name, anim_loop, 0)
	if entry != null and not force:
		entry.set_mix_duration(mix)
	_playing = name

# The Goober's own equipped dances (animation names), if any.
func dances():
	if spine != null and "dance_ids" in spine:
		return spine.dance_ids.duplicate()
	return []

# Resets the per-frame pose values; the choreography sets what it needs.
func clear_pose():
	arm_l = 0.0
	arm_r = 0.0
	elbow = 0.0
	feet = Vector2.ZERO
	feet_spread = 0.0
	lean = 0.0
	squash = 1.0
	face = "normal"
	rotation = 0.0
	scale_mul = Vector2.ONE
	bones_extra = {}

func step(delta):
	var fx = facing if abs(facing) > 0.06 else (0.06 if facing >= 0.0 else -0.06)
	scale = Vector2(fx / sqrt(max(0.2, squash)), squash) * scale_mul
	if abs(scale.y) < 0.02:
		scale.y = 0.02 if scale.y >= 0.0 else -0.02
	if spine == null:
		update()
		return
	_play(anim)
	spine.update_skeleton(delta)
	if _wink_material != null:
		_wink_material.set_shader_param("wink", face == "wink")

func _reset_pose(_sprite = null):
	spine.get_skeleton().set_bones_to_setup_pose()

# Spine space: y up, angles counter-clockwise. Arm-left hangs on the +x side,
# Arm-right on the -x side, so "away from the body" is + for the left arm and
# - for the right. Leg-left2 / Leg-right2 are the feet IK targets.
func _apply_pose(_sprite = null):
	_rot("Arm-left", arm_l)
	_rot("Arm-right", -arm_r)
	_rot("bone9b", elbow)
	_rot("bone12b", -elbow)
	var f = feet * HEIGHT
	var spread = feet_spread * HEIGHT
	_move("Leg-left2", Vector2(f.x + spread, f.y))
	_move("Leg-right2", Vector2(f.x - spread, f.y))
	_rot("Body", -lean)
	for name in bones_extra:
		var bone = _extra_bone(name)
		if bone != null:
			var v = bones_extra[name]
			bone.set_rotation(bone.get_rotation() + v.x)
			bone.set_x(bone.get_x() + v.y)
			bone.set_y(bone.get_y() + v.z)
	if _eye_slot != null and _plain_face:
		if face == "wince" and _eye_wince != null:
			_eye_slot.set_attachment(_eye_wince)
		elif _eye_normal != null and _eye_slot.get_attachment() != _eye_normal:
			_eye_slot.set_attachment(_eye_normal)

func _extra_bone(name):
	if not _bones.has(name):
		_bones[name] = spine.get_skeleton().find_bone(name)
	return _bones[name]

func _rot(name, degrees):
	if _bones.has(name) and degrees != 0.0:
		var bone = _bones[name]
		bone.set_rotation(bone.get_rotation() + degrees)

func _move(name, offset):
	if _bones.has(name) and offset != Vector2.ZERO:
		var bone = _bones[name]
		bone.set_x(bone.get_x() + offset.x)
		bone.set_y(bone.get_y() + offset.y)

# Stand-in drawing (no Spine runtime), in the real Goober's proportions: a
# tall capsule about 2.75x the puppet size, short legs, thin arms.
func _draw():
	if spine != null:
		return
	var u = size
	var w = 1.8 * u
	var leg = 0.28 * u
	var lean_off = Vector2(lean * 0.01 * u, 0)
	var bottom = Vector2(0, -leg) + lean_off
	var top = Vector2(0, -3.0 * u) + lean_off
	draw_circle(top + Vector2(0, w * 0.5), w * 0.5, tint)
	draw_circle(bottom - Vector2(0, w * 0.5), w * 0.5, tint)
	draw_rect(Rect2(top.x - w * 0.5, top.y + w * 0.5, w, (bottom.y - w * 0.5) - (top.y + w * 0.5)), tint)
	var shoulder_l = Vector2(w * 0.5, -1.5 * u) + lean_off
	var shoulder_r = Vector2(-w * 0.5, -1.5 * u) + lean_off
	draw_line(shoulder_l, shoulder_l + Vector2(sin(deg2rad(arm_l)), cos(deg2rad(arm_l))) * u * 0.7, Color.white, 4)
	draw_line(shoulder_r, shoulder_r + Vector2(-sin(deg2rad(arm_r)), cos(deg2rad(arm_r))) * u * 0.7, Color.white, 4)
	var hip_l = bottom + Vector2(w * 0.25, -0.1 * u)
	var hip_r = bottom + Vector2(-w * 0.25, -0.1 * u)
	draw_line(hip_l, Vector2(w * 0.25 + feet_spread * u + feet.x * u, -feet.y * u), Color.white, 4)
	draw_line(hip_r, Vector2(-w * 0.25 - feet_spread * u + feet.x * u, -feet.y * u), Color.white, 4)
	for side in [-1, 1]:
		var c = Vector2(side * w * 0.2, -2.2 * u) + lean_off
		if face == "wince":
			draw_line(c + Vector2(-6, -5) * side, c + Vector2(5, 0) * side, Color.black, 4)
			draw_line(c + Vector2(5, 0) * side, c + Vector2(-6, 5) * side, Color.black, 4)
		elif face == "wink" and side == 1:
			draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), Color.black, 4)
		else:
			draw_circle(c, u * 0.14, Color.black)
			draw_circle(c + Vector2(-0.04, -0.05) * u, u * 0.05, Color.white)
