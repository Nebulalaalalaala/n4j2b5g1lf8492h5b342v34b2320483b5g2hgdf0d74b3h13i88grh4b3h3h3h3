extends Node

const SMALL_META = "_goobplayability_small_geometry"
const TYPES = ["block", "ice_block", "ramp"]

func _ready() -> void:
	get_tree().connect("node_added", self, "observe")

func small(node) -> bool:
	return is_instance_valid(node) and node is LevelNode and node.node_type in TYPES and (node.grid_rect.size.x < 1 or node.grid_rect.size.y < 1)

func observe(node) -> void:
	if small(node) and node.animation == null:
		node.set_meta(SMALL_META, node.serialize_level_node().duplicate(true))
		call_deferred("repair", node)

func repair(node) -> void:
	if is_instance_valid(node) and node.has_meta(SMALL_META):
		var data = node.get_meta(SMALL_META)
		node.remove_meta(SMALL_META)
		restore(node, data)

func repair_level(level) -> void:
	for node in level.get_children():
		repair(node)

func restore(node, data: Dictionary) -> void:
	var id = node.level_node_index
	node.deserialize_level_node(data.duplicate(true))
	node.level_node_index = id
	node.update_transform()
	if node.body != null:
		node.body.global_transform = node.global_transform
	node.force_update_transform()
	if is_inside_tree():
		get_tree().flush_transform_notifications()

func set_rect(node, rect: Rect2) -> void:
	if node.node_type in TYPES and (small(node) or rect.size.x < 1 or rect.size.y < 1):
		var data = node.serialize_level_node().duplicate(true)
		data.x = rect.position.x
		data.y = rect.position.y
		data.width = rect.size.x
		data.height = rect.size.y
		restore(node, data)
	else:
		node.grid_rect = rect
