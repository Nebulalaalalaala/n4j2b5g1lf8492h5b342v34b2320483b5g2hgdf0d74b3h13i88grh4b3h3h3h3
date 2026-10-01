extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Additional hats/suits need separate Spine sprites: one slot holds one attachment.
var target
var avatars = {}
var signature = ""
var last_pose = []

func clear() -> void:
	for avatar in avatars.values():
		if is_instance_valid(avatar):
			avatar.hide()
			avatar.queue_free()
	avatars.clear()
	signature = ""
	last_pose = []
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
	set_process_priority(1000000)
	set_process(not avatars.empty())
	_process(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return
	var pose = []
	for index in range(3):
		var source = target.get_animation_state().get_current(index)
		pose.append([source.get_animation().get_name(),source.get_track_time()] if source != null else [])
	if pose == last_pose: return
	last_pose = pose
	for avatar in avatars.values():
		var state = avatar.get_animation_state()
		for index in range(3):
			var source = target.get_animation_state().get_current(index)
			var current = state.get_current(index)
			if source == null:
				if current != null: state.clear_track(index)
				continue
			var name: String = source.get_animation().get_name()
			if current == null or current.get_animation().get_name() != name:
				current = state.set_animation(name,true,index)
			current.set_track_time(source.get_track_time())
		avatar.update_skeleton(0.0)
