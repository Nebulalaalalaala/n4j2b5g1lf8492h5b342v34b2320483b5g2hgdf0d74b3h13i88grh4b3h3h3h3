extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Look = preload("user://mod/tools/avatar-studio/StudioPublicLook.gd")
var transport
var sandbox
var renderers = []
var icon
var elapsed = 0.0
var state_signature = ""
var appearance = {}
var startup_age = 0.0
var rejected = {}

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	transport = load(ModPaths.path("StudioPublicTransport.gd")).new()
	add_child(transport)
	transport.connect("changed",self,"_refresh")
	var image = Image.new()
	if image.load(ModPaths.ICONS_DIR+"goob_bean.png")==OK:
		icon = ImageTexture.new()
		icon.create_from_image(image,Texture.FLAG_FILTER)
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
	if Look.valid_id(owner) and is_instance_valid(sandbox) and is_instance_valid(sandbox._studio):
		var signature = owner+str(sandbox._studio.capture().hash())+str(storage.storage_get("player.profile.skin",{}).hash())
		if signature != state_signature:
			var next = Look.capture(sandbox)
			if not next.empty():
				appearance = next
				state_signature = signature
		if state_signature.begins_with(owner): transport.publish(owner,appearance)
	elif Look.valid_id(owner) and startup_age>10.0:
		# Clients without an active Studio still announce the GP name logo.
		transport.publish(owner,{"version":1,"enabled":false})
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
	_refresh()

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
		_mark(renderer,present)
		if identity.local: continue # Never overwrite the actual local Studio.
		if not ModPaths.has("CosmeticSandbox.gd") or not ModPaths.has("AvatarStudio.gd"): continue
		var target = renderer.get("spine")
		if not is_instance_valid(target): continue
		var binding = target.get_node_or_null("PublicStudioLook")
		var raw = row.get("look",{}) if present else {}
		var signature = str(raw.hash())
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

func _mark(renderer,present):
	var box = renderer.get_node_or_null("UIHolder/UI/Username/HBoxContainer")
	if box==null or icon==null: return
	var logo = box.get_node_or_null("GoobplayabilityLogo")
	if logo==null and present:
		logo = TextureRect.new()
		logo.name = "GoobplayabilityLogo"
		logo.texture = icon
		logo.expand = true
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.rect_min_size = Vector2(40,40)
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(logo)
	if logo!=null: logo.visible = present

func _exit_tree():
	if get_tree().is_connected("node_added",self,"_consider"): get_tree().disconnect("node_added",self,"_consider")
	for reference in renderers:
		var renderer = reference.get_ref()
		if not is_instance_valid(renderer): continue
		var logo = renderer.get_node_or_null("UIHolder/UI/Username/HBoxContainer/GoobplayabilityLogo")
		if logo!=null: logo.queue_free()
		var target = renderer.get("spine")
		var binding = target.get_node_or_null("PublicStudioLook") if is_instance_valid(target) else null
		if binding!=null:
			binding.clear()
			target.remove_child(binding)
			binding.queue_free()
