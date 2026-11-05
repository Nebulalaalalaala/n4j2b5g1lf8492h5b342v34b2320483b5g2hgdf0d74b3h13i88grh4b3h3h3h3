extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Look = preload("user://mod/core/workspace4/identity/ClientLookDocument.gd")
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Roles = preload("user://mod/core/workspace4/ClientRoles.gd")
const NameGradient = preload("user://mod/core/workspace4/NameGradient.gd")
var transport
var role_service
var sandbox
var renderers = []
var icon
var elapsed = 0.0
var state_signature = ""
var appearance = {}
var startup_age = 0.0
var rejected = {}
var publication_note = ""

func _ready():
	for existing in get_tree().get_nodes_in_group("goob_public_avatars"):
		if existing!=self and is_instance_valid(existing):
			queue_free()
			return
	load("user://mod/core/workspace4/EffectRuntime.gd").ensure(get_parent())
	pause_mode = Node.PAUSE_MODE_PROCESS
	add_to_group("goob_public_avatars")
	role_service = load("user://mod/core/workspace4/ClientRoleService.gd").new()
	add_child(role_service)
	role_service.connect("changed",self,"_refresh")
	transport = load("user://mod/core/workspace4/identity/ClientLookTransport.gd").new()
	add_child(transport)
	transport.connect("changed",self,"_refresh")
	icon = Galaxy.texture("fox-head.png")
	get_tree().connect("node_added",self,"_consider")
	call_deferred("_scan",get_tree().root)

func _scan(node):
	_consider(node)
	for child in node.get_children(): _scan(child)

func _consider(node):
	if node.get_script()!=null and node.get_script().resource_path.ends_with("/CosmeticSandbox.gd"):
		# Headless remote painters never enter the tree and cannot be selected here.
		sandbox = node
	if node is UpGuys_PlayerRenderer:
		call_deferred("_watch",weakref(node))

func _watch(reference):
	var renderer = reference.get_ref()
	if not is_instance_valid(renderer): return
	for known in renderers:
		if known.get_ref()==renderer: return
	renderers.append(reference)

func _process(delta):
	elapsed += delta
	startup_age += delta
	if elapsed < 1.0: return
	elapsed = 0.0
	var moonlight = get_node_or_null("/root/Moonlight")
	var storage = moonlight.storage if moonlight!=null else null
	var owner = str(storage.storage_get("account.user.id","")) if storage!=null else ""
	var runtime = _effect_runtime()
	var effect = runtime.shared_document() if runtime!=null else {}
	if Look.valid_id(owner) and is_instance_valid(sandbox) and is_instance_valid(sandbox._studio):
		var signature = owner+str(sandbox._studio.capture().hash())+str(storage.storage_get("player.profile.skin",{}).hash())+str(effect.hash())
		if signature != state_signature:
			var next = Look.capture(sandbox)
			if not next.empty():
				appearance = _with_effect(next,effect)
				state_signature = signature
		if state_signature.begins_with(owner): transport.publish(owner,appearance)
	elif Look.valid_id(owner) and startup_age>10.0:
		# Clients without an active Studio still announce the GP name logo.
		transport.publish(owner,_with_effect({"version":1,"enabled":false},effect))
	var ids = []
	var alive = []
	for reference in renderers:
		var renderer = reference.get_ref()
		if not is_instance_valid(renderer) or not renderer.is_inside_tree(): continue
		alive.append(reference)
		var identity = _identity(renderer)
		if not identity.empty() and not identity.local and not ids.has(identity.id): ids.append(identity.id)
	renderers = alive
	transport.lookup(ids)
	var badge_ids = ids.duplicate()
	if Look.valid_id(owner) and not owner in badge_ids: badge_ids.append(owner)
	role_service.lookup(badge_ids)
	_refresh()

func _with_effect(base: Dictionary, effect: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	result["custom_effect"] = effect
	publication_note = ""
	# Leave room for PostgreSQL jsonb's spaces. Preserve the avatar when an
	# unusually large imported image and effect would exceed the existing row.
	if JSON.print(result).to_utf8().size()>Look.MAX_BYTES-8192:
		result["custom_effect"] = {}
		publication_note = "This outfit is too large to share its effect. Try a simpler effect or a smaller imported image."
	return result

func _identity(renderer):
	var game = renderer.get_network_game()
	if not is_instance_valid(game): return {}
	var object_id = renderer.get_object_id()
	var metadata = game.get_metadata_for_player(object_id)
	var id = str(metadata.get("uuid","")) if metadata is Dictionary else ""
	return {"id":id,"local":game.is_local_player(object_id)} if Look.valid_id(id) else {}

func _refresh():
	var moonlight = get_node_or_null("/root/Moonlight")
	var catalog = moonlight.storage.storage_get("cosmetics",{}) if moonlight!=null else {}
	if not catalog is Dictionary: return
	if not catalog.has("color_default"):
		catalog = catalog.duplicate()
		catalog["color_default"] = CosmeticsCollection.lookup_cosmetic_id("color_default")
	var catalog_signature = str(catalog.hash())
	for reference in renderers:
		var renderer = reference.get_ref()
		if not is_instance_valid(renderer) or not renderer.is_inside_tree(): continue
		var identity = _identity(renderer)
		if identity.empty(): continue
		var row = transport.cache.get(identity.id,{})
		var present = identity.local or bool(row.get("present",false))
		var roles = role_service.roles_for(identity.id)
		_mark(renderer,present or not roles.empty(),roles)
		if not identity.local:
			var runtime = _effect_runtime()
			var wire = row.get("look",{}) if present else {}
			var color = Color(str(wire.get("color","7cc4ff"))) if bool(wire.get("custom",false)) and str(wire.get("color","")).length()==6 and str(wire.get("color","")).is_valid_hex_number(false) else null
			if runtime!=null: runtime.set_remote(identity.id,wire.get("custom_effect",{}),color)
		if identity.local: continue # Never overwrite the actual local Studio.
		if not ModPaths.has("CosmeticSandbox.gd") or not ModPaths.has("AvatarStudio.gd"): continue
		var target = renderer.get("spine")
		if not is_instance_valid(target): continue
		var binding = target.get_node_or_null("PublicStudioLook")
		var raw = row.get("look",{}) if present else {}
		var body_data = raw.duplicate()
		body_data.erase("custom_effect")
		var signature = str(body_data.hash())
		var validation_key = signature+catalog_signature
		if rejected.get(identity.id,"")==validation_key: continue
		if binding!=null and binding.get_meta("look_signature")==signature: continue
		if raw.empty() or not bool(raw.get("enabled",false)):
			if binding!=null:
				binding.clear()
				target.remove_child(binding)
				binding.queue_free()
			continue
		var look = Look.clean(raw,catalog)
		if look.empty():
			rejected[identity.id] = validation_key
			if rejected.size()>256: rejected.clear()
			continue
		if binding==null:
			binding = load(ModPaths.path("StudioPublicRenderer.gd")).new()
			binding.name = "PublicStudioLook"
			target.add_child(binding)
		binding.configure(target,look)
		binding.set_meta("look_signature",signature)

func _effect_runtime():
	for node in get_tree().get_nodes_in_group("goob_effect_runtime"):
		if is_instance_valid(node): return node
	return null

func _name_label(node):
	var result = null
	for child in node.get_children():
		if child.name in ["GoobplayabilityIdentity","GoobplayabilityLogo"]: continue
		if child is Label and not str(child.name).begins_with("__SDFLabelOutline"):
			if result==null or child.text.length()>result.text.length(): result = child
		else:
			var nested = _name_label(child)
			if nested!=null and (result==null or nested.text.length()>result.text.length()): result = nested
	return result

func _mark(renderer,present,codes = []):
	var box = renderer.get_node_or_null("UIHolder/UI/Username/HBoxContainer")
	if box==null or icon==null: return
	var enabled = present and bool(SavedSettings.get_value("client_identity_labels",true))
	var label = renderer.get("username_label")
	if not label is Label: label = _name_label(box)
	if label!=null:
		if enabled and bool(SavedSettings.get_value("client_name_gradients",true)): NameGradient.apply(label,Roles.tier(codes))
		else: NameGradient.restore(label)
	var identity = box.get_node_or_null("GoobplayabilityIdentity")
	var signature = str(codes)+str(enabled)
	if identity!=null and identity.get_meta("signature")==signature: return
	if identity!=null:
		box.remove_child(identity)
		identity.queue_free()
	if not enabled: return
	identity = HBoxContainer.new()
	identity.name = "GoobplayabilityIdentity"
	identity.set_meta("signature",signature)
	identity.add_constant_override("separation",5)
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(identity)
	var tooltip = "Goobplayability"
	for key in codes: tooltip+="\n"+str(Roles.DEFINITIONS[key].name)
	var logo = TextureRect.new()
	logo.name = "GoobplayabilityLogo"
	logo.texture = icon
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.rect_min_size = Vector2(40,40)
	logo.hint_tooltip = tooltip
	logo.mouse_filter = Control.MOUSE_FILTER_PASS
	identity.add_child(logo)
	var tier = Roles.tier(codes)
	var shown = 0
	for key in codes:
		if int(Roles.DEFINITIONS[key].tier)>0 and key!=tier: continue
		if shown>=3: break
		var badge = TextureRect.new()
		badge.texture = Galaxy.icon(Roles.DEFINITIONS[key].icon,Color(Roles.DEFINITIONS[key].color),28)
		badge.rect_min_size = Vector2(28,28)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.hint_tooltip = str(Roles.DEFINITIONS[key].name)
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		identity.add_child(badge)
		shown+=1

func _exit_tree():
	if get_tree().is_connected("node_added",self,"_consider"): get_tree().disconnect("node_added",self,"_consider")
	for reference in renderers:
		var renderer = reference.get_ref()
		if not is_instance_valid(renderer): continue
		var box = renderer.get_node_or_null("UIHolder/UI/Username/HBoxContainer")
		var label = renderer.get("username_label")
		if not label is Label: label = _name_label(box) if box!=null else null
		if label!=null: NameGradient.restore(label)
		var identity = box.get_node_or_null("GoobplayabilityIdentity") if box!=null else null
		if identity!=null: identity.queue_free()
		var target = renderer.get("spine")
		var binding = target.get_node_or_null("PublicStudioLook") if is_instance_valid(target) else null
		if binding!=null:
			binding.clear()
			target.remove_child(binding)
			binding.queue_free()
