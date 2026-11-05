extends Node2D
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
const Scene = preload("user://mod/core/workspace4/effects/EffectScene.gd")
var studio
var source
var effect_scene
var signature = ""
var elapsed = 0.0

func _ready():
	z_index = 10
	effect_scene = Scene.new()
	add_child(effect_scene)

func _process(delta):
	if not is_instance_valid(studio) or not is_instance_valid(source):
		queue_free()
		return
	visible = source.is_visible_in_tree()
	if not visible: return
	global_position = source.global_position
	elapsed+=delta
	if elapsed<0.25: return
	elapsed = 0
	var state = studio.preview_skin_override if not studio.preview_skin_override.empty() else studio.capture()
	var effects = state.get("effects",{})
	var document = effects.get("custom_effect",{})
	if not effects.has("custom_effect"):
		for runtime in get_tree().get_nodes_in_group("goob_effect_runtime"):
			document = runtime.worn
			break
	var color = Color(str(state.get("color","7cc4ff"))) if bool(state.get("custom",false)) else Color("7cc4ff")
	var key = str(document.hash())+color.to_html()
	if key==signature: return
	signature = key
	effect_scene.configure(document,color)
