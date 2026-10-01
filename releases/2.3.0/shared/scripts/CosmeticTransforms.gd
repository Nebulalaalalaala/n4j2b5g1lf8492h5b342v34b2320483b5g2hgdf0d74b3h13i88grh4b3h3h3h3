extends Node

# Render-only slot materials. Never writes bones, attachments, player or physics state.
const DEFAULT = {"x": 0.0, "y": 0.0, "rotation": 0.0, "scale": 1.0}
const VERTEX_CODE = """
uniform vec2 cosmetic_basis_x = vec2(1.0, 0.0);
uniform vec2 cosmetic_basis_y = vec2(0.0, 1.0);
uniform vec2 cosmetic_translation = vec2(0.0);
uniform bool cosmetic_active = false;
void vertex() {
    if (cosmetic_active) {
        VERTEX = cosmetic_basis_x * VERTEX.x + cosmetic_basis_y * VERTEX.y + cosmetic_translation;
    }
}
"""
var target
var bindings = []
var shaders = {}
var setup_frames = []
var setup_signature = ""

# Spine vertices are already Y-down in this build. Preserve the full affine
# basis (including squash/shear), not the decomposed global bone transform.
static func bone_frame(bone) -> Transform2D:
	return Transform2D(Vector2(bone.get_a(), bone.get_c()), Vector2(bone.get_b(), bone.get_d()), Vector2(bone.get_world_x(), bone.get_world_y()))

func _cache_setup_frames() -> void:
	var next = str([target.skeleton_data_res.get_instance_id(), target.goober_skin_data.hash()])
	if next == setup_signature: return
	setup_frames.clear()
	# A detached reference skeleton: never rewind or write the live Goober.
	var reference = ClassDB.instance("SpineSprite")
	reference.skeleton_data_res = target.skeleton_data_res
	var skeleton = reference.get_skeleton()
	skeleton.set_skin(target.get_skeleton().get_skin())
	skeleton.set_to_setup_pose()
	skeleton.update_world_transform()
	for bone in skeleton.get_bones(): setup_frames.append(bone_frame(bone))
	reference.free()
	setup_signature = next

func item_frame(id: String) -> Dictionary:
	for binding in bindings:
		if binding.id != id: continue
		var current = bone_frame(binding.pivot)
		var setup: Transform2D = binding.setup
		if abs(setup.x.cross(setup.y)) < 0.000001: return {}
		var frame = current * setup.affine_inverse()
		var state: Dictionary = binding.state
		var edit = Transform2D(deg2rad(state.get("rotation", 0)), Vector2.ZERO).scaled(Vector2.ONE * float(state.get("scale", 1)))
		edit.origin = setup.origin + Vector2(state.get("x", 0), state.get("y", 0)) * 10.0 - edit.basis_xform(setup.origin)
		return {"frame": frame, "warp": frame * edit, "pivot": (frame * edit).xform(setup.origin)}
	return {}

func update_item(id: String, state: Dictionary) -> void:
	if not valid({id: state}): return
	for binding in bindings:
		if binding.id == id: binding.state = state.duplicate(true)
	_update()

static func valid(value) -> bool:
	if not value is Dictionary or value.size() > 64:
		return false
	for id in value:
		if not id is String or id.length() > 160 or not value[id] is Dictionary:
			return false
		for key in value[id]:
			if not DEFAULT.has(key):
				return false
			var number = value[id][key]
			if not typeof(number) in [TYPE_INT, TYPE_REAL] or is_nan(float(number)) or is_inf(float(number)):
				return false
			if key == "scale":
				if number < 0.1 or number > 4.0:
					return false
			elif abs(number) > (360.0 if key == "rotation" else 100.0):
				return false
	return true

func clear(_unused = null) -> void:
	if has_meta("studio_selection_binding"): remove_meta("studio_selection_binding")
	for binding in bindings:
		var node = binding.node
		if is_instance_valid(node):
			node.normal_material = null
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	bindings.clear()

func configure(avatar, settings: Dictionary, catalog: Dictionary) -> void:
	clear()
	target = avatar
	if not target.is_connected("skin_data_changed", self, "clear"):
		target.connect("skin_data_changed", self, "clear")
	if not target.is_connected("world_transforms_changed", self, "_update"):
		target.connect("world_transforms_changed", self, "_update")
	if settings.empty() or not valid(settings):
		return
	var base = target.normal_material
	if not base is ShaderMaterial or base.shader == null:
		return
	var skeleton = target.get_skeleton()
	var slots = skeleton.get_slots()
	_cache_setup_frames()
	# Match skin composition order. A later skin owns a conflicting attachment.
	var owners = {}
	var skin_data = target.goober_skin_data
	var keys = skin_data.keys()
	keys.sort()
	for key in keys:
		var id = str(skin_data[key])
		var data = catalog.get(id, {})
		var skin = target.skeleton_data_res.find_skin(str(data.get("spine", "")))
		if skin == null:
			continue
		for entry in skin.get_attachments():
			var index = entry.get_slot_index()
			var name = entry.get_attachment().get_attachment_name()
			owners[str(index) + ":" + name] = id
	var pivots = {}
	for index in range(slots.size()):
		var slot = slots[index]
		var attachment = slot.get_attachment()
		if attachment == null:
			continue
		var id = owners.get(str(index) + ":" + attachment.get_attachment_name(), "")
		if not settings.has(id) or not catalog.get(id, {}).get("type", "") in ["hat", "suit", "hand"]:
			continue
		if not pivots.has(id) or slot.get_data().get_name() in ["BODY", "SUIT", "HEADS", "HANDS"]:
			var bone = slot.get_bone()
			pivots[id] = {"bone": bone, "setup": setup_frames[bone.get_data().get_index()]}
		var node = ClassDB.instance("SpineSlotNode")
		target.add_child(node)
		node.slot_name = slot.get_data().get_name()
		var material = base.duplicate()
		var code = base.shader.code
		if not shaders.has(code):
			var shader = Shader.new()
			shader.code = code + VERTEX_CODE
			shaders[code] = shader
		material.shader = shaders[code]
		var state = settings[id]
		node.normal_material = material
		bindings.append({"node": node, "slot": slot, "material": material, "id": id, "state": state.duplicate(true), "attachment": attachment.get_attachment_name()})
	for binding in bindings:
		binding["pivot"] = pivots[binding.id].bone
		binding["setup"] = pivots[binding.id].setup
	_update()

func _update(_sprite = null) -> void:
	var edits = {}
	for binding in bindings:
		var attachment = binding.slot.get_attachment()
		binding.material.set_shader_param("cosmetic_active", attachment != null and attachment.get_attachment_name() == binding.attachment)
		if not edits.has(binding.id):
			var geometry = item_frame(binding.id)
			var state: Dictionary = binding.state
			var identity = state.get("x",0)==0 and state.get("y",0)==0 and state.get("rotation",0)==0 and state.get("scale",1)==1
			if identity or geometry.empty() or abs(geometry.frame.x.cross(geometry.frame.y)) < 0.000001:
				edits[binding.id] = Transform2D.IDENTITY
			else:
				# Conjugate the saved setup-space edit by the live animation pose.
				edits[binding.id] = geometry.warp * geometry.frame.affine_inverse()
		var edit: Transform2D = edits[binding.id]
		binding.material.set_shader_param("cosmetic_basis_x", edit.x)
		binding.material.set_shader_param("cosmetic_basis_y", edit.y)
		binding.material.set_shader_param("cosmetic_translation", edit.origin)
