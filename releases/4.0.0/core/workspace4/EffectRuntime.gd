extends Node
# Cosmetic presentation on native renderers; never writes game simulation state.
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
const Scene = preload("user://mod/core/workspace4/effects/EffectScene.gd")
const Follower = preload("user://mod/core/workspace4/effects/EffectFollower.gd")
const PlayerCards = preload("user://mod/core/workspace4/PlayerCards.gd")
const DIR = "user://goobplayability/effects/"
const WORN = DIR+"worn.json"
signal changed
signal sharing_changed
var tas_tool
var worn = {}
var remote = {}
var remote_colors = {}
var renderers = []
var bindings = {}
var tick = 0.0
var registrations = 0

static func ensure(owner):
	for runtime in owner.get_tree().get_nodes_in_group("goob_effect_runtime"):
		if is_instance_valid(runtime): return runtime
	var runtime = load("user://mod/core/workspace4/EffectRuntime.gd").new()
	runtime.name = "GoobEffectRuntime"
	runtime.tas_tool = owner
	owner.add_child(runtime)
	return runtime

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	add_to_group("goob_effect_runtime")
	worn = Document.clean(Kit.read_json(WORN,{}))
	get_tree().connect("node_added",self,"_consider")
	call_deferred("_scan",get_tree().root)
	_sync_activity()

static func presets() -> Dictionary: return Document.presets()
static func dot_texture() -> Texture: return Scene.texture("dot")

# Earlier single-emitter previews retain their entry point and saved files.
static func configure(target: CPUParticles2D, effect: Dictionary, scale: float = 1.0):
	var clean = Document.clean(effect)
	if clean.empty():
		target.emitting = false
		return
	var selected = clean.layers[0]
	for item in clean.layers:
		if item.type=="emitter":
			selected = item
			break
	Scene.configure_emitter(target,selected,Color.white,scale)

func wear(effect: Dictionary) -> bool:
	var clean = Document.clean(effect)
	if clean.empty(): return false
	if not Kit.write_json(WORN,Document.export_data(clean)): return false
	worn = clean
	_sync_activity()
	_detach()
	emit_signal("changed")
	return true

func take_off():
	if not Kit.write_json(WORN,{}): return false
	worn = {}
	_sync_activity()
	_detach()
	emit_signal("changed")
	return true

func set_sharing(value: bool):
	SavedSettings.set_value("custom_effects_sharing",value)
	emit_signal("sharing_changed")

func shared_document() -> Dictionary:
	return {}


func set_remote(user_id: String, effect, color = null):
	var clean = Document.clean(effect)
	if clean.empty():
		remote.erase(user_id)
		remote_colors.erase(user_id)
	else:
		remote[user_id] = clean
		if color is Color: remote_colors[user_id] = color
		else: remote_colors.erase(user_id)
	if remote.size()>64:
		remote.clear()
		remote_colors.clear()
	_sync_activity()

func _sync_activity():
	var active=not worn.empty() or not remote.empty()
	set_process(active)
	if not active: _detach()

func _consider(node):
	if not node is UpGuys_PlayerRenderer: return
	renderers.append(weakref(node))
	registrations+=1
	if registrations%128==0:
		# With processing asleep, bound stale weak references by join events,
		# rather than waking a polling loop or retaining old game objects.
		var live=[]
		for reference in renderers:
			if is_instance_valid(reference.get_ref()): live.append(reference)
		renderers=live

func _scan(node):
	if node is UpGuys_PlayerRenderer:
		var found = false
		for reference in renderers:
			if reference.get_ref()==node: found = true
		if not found: renderers.append(weakref(node))
	for child in node.get_children(): _scan(child)

func _identity(renderer) -> Dictionary:
	var game = renderer.get_network_game()
	if not is_instance_valid(game): return {}
	var object_id = renderer.get_object_id()
	var metadata = game.get_metadata_for_player(object_id)
	if not metadata is Dictionary: return {}
	return {"id":str(metadata.get("uuid","")),"local":game.is_local_player(object_id),"skin":metadata.get("skin",{})}

func _body_color(identity: Dictionary) -> Color:
	if identity.local and is_instance_valid(tas_tool):
		var sandbox = tas_tool.get("_cosmetic_sandbox")
		if is_instance_valid(sandbox) and sandbox.sandbox_enabled and sandbox.custom_color_enabled: return sandbox.custom_color
	if remote_colors.has(identity.id): return remote_colors[identity.id]
	return PlayerCards.look_for(identity.skin).body

func _process(delta):
	tick += delta
	if tick<0.25: return
	tick = 0
	var shown = {}
	var alive = []
	var seen = {}
	var remote_count = 0
	var setting = str(SavedSettings.get_value("remote_effects_quality","balanced"))
	for reference in renderers:
		var renderer = reference.get_ref()
		if not is_instance_valid(renderer): continue
		alive.append(reference)
		if not renderer.is_inside_tree(): continue
		var visual = renderer.get("spine")
		if not visual is Node2D or not visual.is_visible_in_tree() or visual.get_parent()==null: continue
		# No cosmetic metadata is needed for actors with no effect to draw.
		# In an ordinary crowded match this avoids repeated native dictionary
		# retrieval for every remote actor when only the local effect is worn.
		var game=renderer.get_network_game()
		if not is_instance_valid(game): continue
		var local=game.is_local_player(renderer.get_object_id())
		if local and worn.empty(): continue
		if not local and (remote.empty() or setting=="off"): continue
		var identity = _identity(renderer)
		if identity.empty(): continue
		var unique = identity.id if not identity.id.empty() else str(renderer.get_instance_id())
		if seen.has(unique): continue
		seen[unique] = true
		var effect = worn if identity.local else remote.get(identity.id,{})
		if effect.empty(): continue
		if not identity.local:
			if setting=="off" or remote_count>=8: continue
			var at = visual.get_global_transform_with_canvas().origin
			if not get_viewport().get_visible_rect().grow(160).has_point(at): continue
			remote_count += 1
		var quality = 1.0 if identity.local else (0.35 if setting=="reduced" else 0.65)
		var color = _body_color(identity)
		var signature = str(effect.hash())+color.to_html()+str(quality)
		var id = renderer.get_instance_id()
		var binding = bindings.get(id,{})
		if binding.empty() or not is_instance_valid(binding.scene) or not is_instance_valid(binding.actor):
			var actor = Follower.new()
			actor.name = "GoobCustomEffectFollower"
			actor.source = weakref(visual)
			visual.get_parent().add_child(actor)
			actor.global_position = visual.global_position
			actor.z_index = visual.z_index
			var scene = Scene.new()
			scene.name = "GoobCustomEffects"
			actor.add_child(scene)
			binding = {"source":weakref(renderer),"actor":actor,"scene":scene,"signature":""}
			bindings[id] = binding
		if signature!=binding.signature:
			binding.scene.configure(effect,color,quality)
			binding.signature = signature
		shown[id] = true
	renderers = alive
	for id in bindings.keys():
		if not shown.has(id):
			if is_instance_valid(bindings[id].actor): bindings[id].actor.queue_free()
			bindings.erase(id)

func _detach():
	for binding in bindings.values():
		if is_instance_valid(binding.actor): binding.actor.queue_free()
	bindings.clear()

func _exit_tree():
	if get_tree()!=null and get_tree().is_connected("node_added",self,"_consider"):
		get_tree().disconnect("node_added",self,"_consider")
	_detach()
