extends Node2D
# Native UpGuys_PlayerRenderer is a non-spatial Node. Follow its visible spine
# from a sibling, retaining world-sized FX instead of the spine's tiny scale.
var source
func _process(_delta):
	var target = source.get_ref() if source!=null else null
	if not is_instance_valid(target) or not target.is_inside_tree():
		queue_free()
		return
	visible = target.is_visible_in_tree()
	global_position = target.global_position
	z_index = target.z_index
	modulate.a = target.modulate.a*target.self_modulate.a
