extends Reference

# Rig skins that no catalog cosmetic uses (e.g. hand/LaserBlade). Avatar Studio
# lists them as "Unavailable"; they render as local layers only.

const RIG = "res://project_specific/gfx/spine/upguy/upguy-data.tres"
const KINDS = {"head/": "hat", "suit/": "suit", "hand/": "hand"}
const SHARED = "goob_studio_secrets"

static func entries(_native_catalog: Dictionary) -> Dictionary:
	return {}


static func is_secret(id) -> bool:
	return str(id).begins_with("studio_secret_")

# Puts a secret skin on a Goober (on top of whatever it already wears).
static func wear(sprite, spine: String) -> bool:
	if sprite == null or not sprite.has_method("get_skeleton"):
		return false
	var skin = sprite.skeleton_data_res.find_skin(spine)
	if skin == null:
		return false
	var worn = sprite.new_skin("studio_secret")
	var current = sprite.get_skeleton().get_skin()
	if current != null:
		worn.copy_skin(current)
	worn.copy_skin(skin)
	sprite.get_skeleton().set_skin(worn)
	sprite.get_skeleton().set_slots_to_setup_pose()
	return true
