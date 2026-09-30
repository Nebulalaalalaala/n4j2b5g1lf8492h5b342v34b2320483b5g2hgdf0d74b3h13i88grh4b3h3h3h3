extends Node

# Render-only slot materials. Never writes bones, attachments, player or physics state.
const DEFAULT = {"x": 0.0, "y": 0.0, "rotation": 0.0, "scale": 1.0}
const VERTEX_CODE = """
uniform vec2 cosmetic_offset = vec2(0.0);
uniform vec2 cosmetic_pivot = vec2(0.0);
uniform float cosmetic_rotation = 0.0;
uniform float cosmetic_scale = 1.0;
uniform bool cosmetic_active = false;
void vertex() {
    if (cosmetic_active) {
        vec2 p = (VERTEX - cosmetic_pivot) * cosmetic_scale;
        float c = cos(cosmetic_rotation);
        float s = sin(cosmetic_rotation);
        VERTEX = vec2(c*p.x-s*p.y, s*p.x+c*p.y) + cosmetic_pivot + cosmetic_offset;
    }
}
"""
var target
var bindings = []
var shaders = {}

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
			pivots[id] = slot.get_bone()
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
		material.set_shader_param("cosmetic_offset", Vector2(state.get("x", 0), state.get("y", 0)) * 10.0)
		material.set_shader_param("cosmetic_rotation", deg2rad(state.get("rotation", 0)))
		material.set_shader_param("cosmetic_scale", float(state.get("scale", 1)))
		node.normal_material = material
		bindings.append({"node": node, "slot": slot, "material": material, "id": id, "attachment": attachment.get_attachment_name()})
	for binding in bindings:
		binding["pivot"] = pivots[binding.id]
	_update()

func _update(_sprite = null) -> void:
	for binding in bindings:
		var attachment = binding.slot.get_attachment()
		binding.material.set_shader_param("cosmetic_active", attachment != null and attachment.get_attachment_name() == binding.attachment)
		var pivot = binding.pivot
		binding.material.set_shader_param("cosmetic_pivot", Vector2(pivot.get_world_x(), -pivot.get_world_y()))
