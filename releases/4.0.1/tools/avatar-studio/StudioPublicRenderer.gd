extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
var target
var painter
var studio
var original_skin = {}
var original_material
var appearance = {}
var applying = false
var scheduled = false

# Headless reuse of Avatar Studio: no GUI, account writes or animation replacement.
func configure(goober, look):
	if not is_instance_valid(target):
		target = goober
		original_skin = goober.goober_skin_data.duplicate(true)
		original_material = goober.normal_material
		painter = load(ModPaths.COSMETIC_SANDBOX).new()
		studio = load(ModPaths.AVATAR_STUDIO).new()
		painter._studio = studio
		studio.sandbox = painter
		studio.shader = Shader.new()
		studio.shader.code = studio.SHADER_CODE
		if target.has_signal("skin_data_changed"): target.connect("skin_data_changed",self,"_skin_changed")
	appearance = look
	painter.selected_cosmetics = look.selected
	painter.custom_color_enabled = look.custom
	painter.custom_color = Color("#"+look.color)
	studio.item_transforms = look.transforms
	studio.avatar_size = look.avatar_size
	studio.current_texture = look.texture
	studio.shader_cache.clear()
	studio.texture_cache.clear()
	if look.texture == "import_public":
		var texture = ImageTexture.new()
		texture.create_from_image(load(ModPaths.path("StudioPublicLook.gd")).png_image(look.png),Texture.FLAG_FILTER|Texture.FLAG_REPEAT)
		studio.texture_cache["import_public"] = texture
	_apply()

func _skin_changed():
	if applying or scheduled: return
	# Keep a new server-supplied base for restoration, not our previous override.
	if target.goober_skin_data.hash() != appearance.skin.hash():
		original_skin = target.goober_skin_data.duplicate(true)
	scheduled = true
	call_deferred("_apply")

func _apply():
	scheduled = false
	if not is_instance_valid(target) or appearance.empty(): return
	applying = true
	painter._applied_signatures.clear()
	painter._apply_to_goober(target,appearance.skin)
	# Refresh native mesh materials after Studio applies its palette/pattern.
	# Zero delta keeps the animation clock and player state exactly unchanged.
	target.update_skeleton(0.0)
	applying = false

func clear(restore = true):
	appearance = {}
	if is_instance_valid(target):
		if target.is_connected("skin_data_changed",self,"_skin_changed"): target.disconnect("skin_data_changed",self,"_skin_changed")
	if restore and is_instance_valid(target):
		for name in ["LocalCosmeticTransforms","LocalCosmeticLayers"]:
			var effect = target.get_node_or_null(name)
			if effect != null:
				effect.clear()
				target.remove_child(effect)
				effect.queue_free()
		var size = float(target.get_meta("studio_size")) if target.has_meta("studio_size") else 1.0
		target.scale /= max(0.1,size)
		if target.has_meta("studio_size"): target.remove_meta("studio_size")
		target.normal_material = original_material
		target.gradient_material = original_material
		target.set_goober_skin_data(original_skin)
		target.apply_skin_data()
		target.update_skeleton(0.0)
	if is_instance_valid(studio): studio.free()
	if is_instance_valid(painter):
		painter._studio = null
		painter.free()
	studio = null
	painter = null
	target = null

func _exit_tree(): clear(false)
