extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Additional hats/suits need separate Spine sprites: one slot holds one attachment.
var target
var avatars = {}
var signature = ""
var bone_pairs = {}
var syncing = false

func clear() -> void:
	if is_instance_valid(target) and target.is_connected("world_transforms_changed", self, "_sync_pose"):
		target.disconnect("world_transforms_changed", self, "_sync_pose")
	for avatar in avatars.values():
		if is_instance_valid(avatar):
			avatar.hide()
			avatar.queue_free()
	avatars.clear()
	bone_pairs.clear()
	target = null
	signature = ""
	set_process(false)

func configure(owner, sandbox, selected: Array, transforms: Dictionary) -> void:
	var catalog: Dictionary = sandbox._all_cosmetics()
	var groups = {"hat":[],"suit":[]}
	for id in selected:
		var kind = str(catalog.get(id,{}).get("type",""))
		if groups.has(kind): groups[kind].append(id)
	var extra = []
	for group in groups.values():
		for i in range(max(0,group.size()-8),max(0,group.size()-1)): extra.append(group[i])
	var next = str([extra,owner.goober_skin_data,transforms,sandbox.custom_color_enabled,sandbox.custom_color].hash())
	if next == signature: return
	clear()
	target = owner
	for id in extra:
		var data: Dictionary = catalog[id]
		var skin = target.skeleton_data_res.find_skin(str(data.get("spine","")))
		if skin == null: continue
		var avatar = load("res://project_specific/gfx/spine/upguy/upguy.tscn").instance()
		avatar.set_meta("studio_layer",true)
		avatar.enable_sounds = false
		avatar.enable_blink = false
		target.add_child(avatar)
		avatar.scale = Vector2.ONE
		avatar.position = Vector2.ZERO
		avatar.set_update_mode(2)
		avatar.set_process(false)
		avatar.set_goober_skin_data({"color":target.goober_skin_data.get("color","color_default"),"sandbox_000":id})
		avatar.update_skeleton(0.0)
		var source_bones = target.get_skeleton().get_bones()
		var layer_bones = avatar.get_skeleton().get_bones()
		var pairs = []
		for index in range(min(source_bones.size(), layer_bones.size())):
			pairs.append([source_bones[index], layer_bones[index]])
		bone_pairs[avatar.get_instance_id()] = pairs
		# Copy the evaluated pose before the layer's transform materials/meshes
		# update. This includes native blends and render-only bone adjustments.
		avatar.connect("world_transforms_changed", self, "_copy_pose")
		if sandbox.custom_color_enabled:
			sandbox._original_materials[avatar.get_instance_id()] = avatar.normal_material
			sandbox._apply_custom_gradient(avatar)
		var owned_slots = {}
		for attachment in skin.get_attachments(): owned_slots[attachment.get_slot_index()] = true
		var invisible = ShaderMaterial.new()
		var shader = Shader.new()
		shader.code = "shader_type canvas_item; void fragment(){ COLOR=vec4(0.0); }"
		invisible.shader = shader
		var slots = avatar.get_skeleton().get_slots()
		for index in range(slots.size()):
			if owned_slots.has(index): continue
			var mask = ClassDB.instance("SpineSlotNode")
			avatar.add_child(mask)
			mask.slot_name = slots[index].get_data().get_name()
			mask.normal_material = invisible
		var transform = load(ModPaths.COSMETIC_TRANSFORMS).new()
		transform.name = "LocalCosmeticTransforms"
		avatar.add_child(transform)
		transform.configure(avatar,{id:transforms.get(id,{})},catalog)
		avatars[id] = avatar
	signature = next
	if not avatars.empty(): target.connect("world_transforms_changed", self, "_sync_pose")
	_sync_pose()

func _process(_delta: float) -> void:
	# Retained for callers that explicitly refresh a paused preview.
	_sync_pose()

func _sync_pose(_sprite = null) -> void:
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return
	if syncing: return
	syncing = true
	for avatar in avatars.values():
		var state = avatar.get_animation_state()
		for index in range(3):
			var source = target.get_animation_state().get_current(index)
			var current = state.get_current(index)
			if source == null:
				if current != null: state.clear_track(index)
				continue
			var name: String = source.get_animation().get_name()
			if current == null or current.get_animation().get_name() != name or current.get_track_time() > source.get_track_time():
				current = state.set_animation(name,source.get_loop(),index)
			_sync_track(current, source)
		avatar.update_skeleton(0.0)
	syncing = false

func _sync_track(current, source, depth: int = 0) -> void:
	current.set_track_time(source.get_track_time())
	current.set_loop(source.get_loop())
	current.set_alpha(source.get_alpha())
	current.set_reverse(source.get_reverse())
	current.set_animation_start(source.get_animation_start())
	current.set_animation_end(source.get_animation_end())
	current.set_mix_time(source.get_mix_time())
	current.set_mix_duration(source.get_mix_duration())
	current.set_attachment_threshold(source.get_attachment_threshold())
	current.set_draw_order_threshold(source.get_draw_order_threshold())
	var previous = current.get_mixing_from()
	var original = source.get_mixing_from()
	if depth < 8 and previous != null and original != null and previous.get_animation().get_name() == original.get_animation().get_name():
		_sync_track(previous, original, depth + 1)

func _copy_pose(avatar) -> void:
	for pair in bone_pairs.get(avatar.get_instance_id(), []):
		var source = pair[0]
		var bone = pair[1]
		if not bone.is_active(): continue
		if not source.is_active():
			# Skin-only bones keep their own animated locals but inherit the
			# already-copied parent pose. Native bone order is parent-first.
			bone.update_world_transform()
			continue
		bone.set_a(source.get_a())
		bone.set_b(source.get_b())
		bone.set_c(source.get_c())
		bone.set_d(source.get_d())
		bone.set_world_x(source.get_world_x())
		bone.set_world_y(source.get_world_y())
