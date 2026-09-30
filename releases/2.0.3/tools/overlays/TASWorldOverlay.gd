extends Node2D

# World-space debugging overlay for TASTool. It only reads native fixture and
# player state; nothing here modifies physics, input, or replay data.

const PLAYER_COLOR := Color(0.22, 0.92, 1.0, 0.92)
const SOLID_COLOR := Color(0.28, 1.0, 0.54, 0.72)
const SENSOR_COLOR := Color(1.0, 0.76, 0.18, 0.82)
const HAZARD_COLOR := Color(1.0, 0.22, 0.42, 0.9)
const DYNAMIC_COLOR := Color(0.72, 0.45, 1.0, 0.86)
const TRAJECTORY_COLOR := Color(0.36, 0.84, 1.0, 0.95)
const TRAJECTORY_HORIZON_SECONDS := 1.8
const TRAJECTORY_STEPS := 90

var tas_tool: Node = null
var show_hitboxes := false
var show_trajectory := false
var hitbox_categories := {
	"player": true,
	"solids": false,
	"hazards": false,
	"sensors": false,
	"dynamic": false,
}
var _fixtures := []
var _scan_elapsed := 0.0
var _scene_id := 0


func _ready() -> void:
	z_index = 4095
	z_as_relative = false
	set_as_toplevel(true)
	set_process(true)


func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool


func set_show_hitboxes(value: bool) -> void:
	show_hitboxes = value
	if value:
		_scan_fixtures()
	else:
		_fixtures.clear()
	update()


func set_show_trajectory(value: bool) -> void:
	show_trajectory = value
	update()


func set_hitbox_category(category: String, value: bool) -> void:
	if not hitbox_categories.has(category):
		return
	hitbox_categories[category] = value
	update()


func _process(delta: float) -> void:
	if not show_hitboxes and not show_trajectory:
		return
	var scene = get_tree().current_scene
	var next_scene_id: int = scene.get_instance_id() if scene != null else 0
	_scan_elapsed += delta
	if next_scene_id != _scene_id or (show_hitboxes and _scan_elapsed >= 0.75):
		_scene_id = next_scene_id
		_scan_elapsed = 0.0
		_scan_fixtures()
	update()


func _scan_fixtures() -> void:
	_fixtures.clear()
	if not show_hitboxes:
		return
	var scene = get_tree().current_scene
	if scene != null:
		_collect_fixtures(scene)


func _collect_fixtures(node: Node) -> void:
	if node is Node2D and _has_property(node, "shape"):
		var shape = node.get("shape")
		if shape != null:
			_fixtures.append(node)
	for child in node.get_children():
		_collect_fixtures(child)


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for info in object.get_property_list():
		if str(info.get("name", "")) == property_name:
			return true
	return false


func _draw() -> void:
	if show_hitboxes:
		for fixture in _fixtures:
			if fixture != null and is_instance_valid(fixture) and fixture.is_inside_tree():
				var category := _fixture_category(fixture)
				if bool(hitbox_categories.get(category, false)):
					_draw_fixture(fixture, category)
	if show_trajectory:
		_draw_trajectory()


func _fixture_category(fixture: Node) -> String:
	var ancestor: Node = fixture
	for _i in range(8):
		if ancestor == null:
			break
		if ancestor is WPPlayer:
			return "player"
		var ancestor_name := str(ancestor.name).to_lower()
		if ancestor_name.find("player") >= 0 or ancestor_name.find("goober") >= 0:
			return "player"
		if _has_property(ancestor, "collision_type") and int(ancestor.get("collision_type")) == 2:
			return "hazards"
		if ancestor_name.find("saw") >= 0 or ancestor_name.find("spike") >= 0 or ancestor_name.find("pit") >= 0 or ancestor_name.find("laser") >= 0:
			return "hazards"
		ancestor = ancestor.get_parent()
	if _has_property(fixture, "sensor") and bool(fixture.get("sensor")):
		return "sensors"
	ancestor = fixture
	for _i in range(8):
		if ancestor == null:
			break
		if ancestor is RigidBody2D or ancestor is KinematicBody2D:
			return "dynamic"
		var dynamic_name := str(ancestor.name).to_lower()
		if dynamic_name.find("moving") >= 0 or dynamic_name.find("bouncy") >= 0 or dynamic_name.find("physics") >= 0 or dynamic_name.find("disappearing") >= 0:
			return "dynamic"
		ancestor = ancestor.get_parent()
	return "solids"


func _category_color(category: String) -> Color:
	match category:
		"player":
			return PLAYER_COLOR
		"hazards":
			return HAZARD_COLOR
		"sensors":
			return SENSOR_COLOR
		"dynamic":
			return DYNAMIC_COLOR
	return SOLID_COLOR


func _draw_fixture(fixture: Node2D, category: String) -> void:
	var shape = fixture.get("shape")
	if shape == null:
		return
	var fixture_to_overlay: Transform2D = global_transform.affine_inverse() * fixture.global_transform
	var color := _category_color(category)
	if _has_property(shape, "points"):
		var source_points = shape.get("points")
		if source_points != null and source_points.size() >= 2:
			var points := PoolVector2Array()
			for point in source_points:
				points.append(fixture_to_overlay.xform(point))
			points.append(points[0])
			draw_polyline(points, color, 3.0, true)
			return
	if _has_property(shape, "extents"):
		var extents: Vector2 = shape.get("extents")
		var corners := PoolVector2Array([
			fixture_to_overlay.xform(Vector2(-extents.x, -extents.y)),
			fixture_to_overlay.xform(Vector2(extents.x, -extents.y)),
			fixture_to_overlay.xform(Vector2(extents.x, extents.y)),
			fixture_to_overlay.xform(Vector2(-extents.x, extents.y)),
			fixture_to_overlay.xform(Vector2(-extents.x, -extents.y)),
		])
		draw_polyline(corners, color, 3.0, true)
		return
	if _has_property(shape, "radius"):
		var radius: float = float(shape.get("radius"))
		if _has_property(shape, "height"):
			_draw_capsule(fixture_to_overlay, radius, float(shape.get("height")), color)
		else:
			_draw_transformed_circle(fixture_to_overlay, Vector2.ZERO, radius, color)


func _draw_transformed_circle(xform: Transform2D, center: Vector2, radius: float, color: Color) -> void:
	var points := PoolVector2Array()
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		points.append(xform.xform(center + Vector2(cos(angle), sin(angle)) * radius))
	draw_polyline(points, color, 3.0, true)


func _draw_capsule(xform: Transform2D, radius: float, height: float, color: Color) -> void:
	var half_line := max(0.0, height * 0.5)
	var points := PoolVector2Array()
	for i in range(17):
		var angle := PI + PI * float(i) / 16.0
		points.append(xform.xform(Vector2(cos(angle) * radius, -half_line + sin(angle) * radius)))
	for i in range(17):
		var angle := PI * float(i) / 16.0
		points.append(xform.xform(Vector2(cos(angle) * radius, half_line + sin(angle) * radius)))
	points.append(points[0])
	draw_polyline(points, color, 3.0, true)


func _draw_trajectory() -> void:
	if tas_tool == null or not is_instance_valid(tas_tool) or not tas_tool.has_method("_get_local_player"):
		return
	var player = tas_tool.call("_get_local_player")
	if player == null or not ("position" in player) or not ("linear_velocity" in player):
		return
	var gravity := 980.0
	if tas_tool.has_method("_find_game"):
		var game = tas_tool.call("_find_game")
		if game != null and game.get("wp_game_data") != null and ("world_gravity" in game.get("wp_game_data")):
			gravity = float(game.get("wp_game_data").get("world_gravity"))
	var p: Vector2 = player.position
	var velocity: Vector2 = player.linear_velocity
	var dt := TRAJECTORY_HORIZON_SECONDS / float(TRAJECTORY_STEPS)
	var points := PoolVector2Array()
	points.append(global_transform.affine_inverse().xform(p))
	for i in range(TRAJECTORY_STEPS):
		velocity.y += gravity * dt
		p += velocity * dt
		if i % 2 == 1:
			points.append(global_transform.affine_inverse().xform(p))
	if points.size() >= 2:
		for i in range(points.size() - 1):
			if i % 2 == 0:
				draw_line(points[i], points[i + 1], TRAJECTORY_COLOR, 2.5, true)
		for i in range(0, points.size(), 5):
			draw_circle(points[i], 3.2, TRAJECTORY_COLOR)
