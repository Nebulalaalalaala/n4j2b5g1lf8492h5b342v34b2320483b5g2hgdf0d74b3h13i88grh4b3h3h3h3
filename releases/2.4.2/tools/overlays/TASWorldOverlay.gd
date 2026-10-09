extends Node2D
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Read-only native fixture overlay. Geometry/classification are cached; native
# transforms/enabled state stay live. No physics, inputs, or replay writes.
const PLAYER_COLOR = Color(0.22, 0.92, 1.0, 0.92)
const SOLID_COLOR = Color(0.28, 1.0, 0.54, 0.72)
const SENSOR_COLOR = Color(1.0, 0.76, 0.18, 0.82)
const HAZARD_COLOR = Color(1.0, 0.22, 0.42, 0.9)
const DYNAMIC_COLOR = Color(0.72, 0.45, 1.0, 0.86)
const TRAJECTORY_COLOR = Color(0.36, 0.84, 1.0, 0.95)
const TRAJECTORY_HORIZON_SECONDS = 1.8
const TRAJECTORY_STEPS = 90
const COLORS = {"player": PLAYER_COLOR, "solids": SOLID_COLOR, "sensors": SENSOR_COLOR, "hazards": HAZARD_COLOR, "dynamic": DYNAMIC_COLOR}
var tas_tool = null
var show_hitboxes = false
var show_trajectory = false
var hitbox_categories = {"player": true, "solids": false, "hazards": false, "sensors": false, "dynamic": false}
var _fixtures = {}
var _pending = []
var _scene_id = 0
var _last_refresh = 0
var _last_prediction = 0
var _prediction = {"points": PoolVector2Array(), "death": false}
var _predictor = null
var _shape_properties = {}
var _shape_versions = {}
var scan_count = 0
var geometry_build_count = 0

func _ready() -> void:
	z_index = 4095
	z_as_relative = false
	set_as_toplevel(true)
	set_process(false)
	_predictor = load(ModPaths.path("TASTrajectoryPrediction.gd")).new()

func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool

func set_show_hitboxes(value: bool) -> void:
	show_hitboxes = value
	_refresh_activity()

func set_show_trajectory(value: bool) -> void:
	show_trajectory = value
	_refresh_activity()

func set_hitbox_category(category: String, value: bool) -> void:
	if hitbox_categories.has(category):
		hitbox_categories[category] = value
		update()

func _refresh_activity() -> void:
	var active = show_hitboxes or show_trajectory
	set_process(active)
	if active:
		if not get_tree().is_connected("node_added", self, "_node_added"):
			get_tree().connect("node_added", self, "_node_added")
			get_tree().connect("node_removed", self, "_node_removed")
		_scan_fixtures()
	else:
		if get_tree().is_connected("node_added", self, "_node_added"):
			get_tree().disconnect("node_added", self, "_node_added")
			get_tree().disconnect("node_removed", self, "_node_removed")
		_fixtures.clear()
		_pending.clear()
		_shape_versions.clear()
		_prediction = {"points": PoolVector2Array(), "death": false}
	_last_prediction = 0
	update()

func _node_added(node: Node) -> void:
	if node is Box2DFixture: _pending.append(weakref(node))

func _node_removed(node: Node) -> void:
	_fixtures.erase(node.get_instance_id())

func _process(_delta: float) -> void:
	var scene = get_tree().current_scene
	var next_id = scene.get_instance_id() if scene != null else 0
	if next_id != _scene_id:
		_scan_fixtures()
	for ref in _pending:
		var fixture = ref.get_ref()
		if fixture != null and scene != null and scene.is_a_parent_of(fixture): _cache_fixture(fixture)
	_pending.clear()
	# Wall time also works while TAS time_scale=0. Cap just the diagnostic
	# drawing, not the game, input capture, or physics clock.
	var now = OS.get_ticks_msec()
	if now - _last_refresh < 16: return
	_last_refresh = now
	if show_trajectory and now - _last_prediction >= 33:
		_last_prediction = now
		_update_prediction()
	update()

func _scan_fixtures() -> void:
	_fixtures.clear()
	_shape_versions.clear()
	scan_count += 1
	var scene = get_tree().current_scene
	_scene_id = scene.get_instance_id() if scene != null else 0
	if scene != null: _collect_fixtures(scene)

func _collect_fixtures(node: Node) -> void:
	if node is Box2DFixture: _cache_fixture(node)
	for child in node.get_children(): _collect_fixtures(child)

func _cache_fixture(fixture) -> void:
	if fixture.shape == null: return
	var ancestor = fixture.get_parent()
	var level_node = null
	var player = null
	while ancestor != null:
		if ancestor is WPPlayer:
			player = ancestor
			break
		if ancestor is LevelNode:
			level_node = ancestor
			break
		ancestor = ancestor.get_parent()
	var body = fixture.get_collision_object()
	var category = "solids"
	if player != null: category = "player"
	elif level_node != null and level_node.collision_type == 2: category = "hazards"
	elif fixture.sensor: category = "sensors"
	elif level_node != null and (level_node.rigid_body or level_node.animation != null): category = "dynamic"
	elif body is Box2DPhysicsBody and body.type != 0: category = "dynamic"
	var record = {"fixture": fixture, "body": body, "level_node": level_node, "category": category, "shape_id": 0, "shape_version":0, "points": PoolVector2Array(), "bounds": Rect2(), "world_points": PoolVector2Array(), "transform": Transform2D()}
	_update_geometry(record)
	_fixtures[fixture.get_instance_id()] = record

func _shape_changed(id: int) -> void:
	if not show_hitboxes and not show_trajectory: return
	_shape_versions[id] = int(_shape_versions.get(id, 0)) + 1

func _update_geometry(record: Dictionary) -> void:
	var shape = record.fixture.shape
	if shape == null:
		record.points = PoolVector2Array()
		return
	var id = shape.get_instance_id()
	var cls = shape.get_class()
	if not _shape_properties.has(cls):
		var props = {}
		for info in shape.get_property_list(): props[str(info.name)] = true
		_shape_properties[cls] = props
	var props = _shape_properties[cls]
	var points = PoolVector2Array()
	if props.has("points"):
		points = PoolVector2Array(shape.get("points"))
	elif props.has("extents") or props.has("size"):
		var e: Vector2 = shape.get("extents") if props.has("extents") else shape.get("size") * 0.5
		points = PoolVector2Array([Vector2(-e.x,-e.y), Vector2(e.x,-e.y), Vector2(e.x,e.y), Vector2(-e.x,e.y)])
	elif props.has("radius"):
		var radius = float(shape.get("radius"))
		var half_height = float(shape.get("height")) * 0.5 if props.has("height") else 0.0
		for i in range(32):
			var a = TAU * i / 32.0
			points.append(Vector2(cos(a) * radius, sin(a) * radius + (half_height if sin(a) >= 0 else -half_height)))
	if points.size() > 1: points.append(points[0])
	record.points = points
	record.shape_id = id
	record.world_points = PoolVector2Array()
	record.shape_version = int(_shape_versions.get(id, 0))
	geometry_build_count += 1
	if shape.has_signal("changed") and not shape.is_connected("changed", self, "_shape_changed"):
		shape.connect("changed", self, "_shape_changed", [id])

func _active(record: Dictionary) -> bool:
	var fixture = record.fixture
	return is_instance_valid(fixture) and fixture.is_inside_tree() and fixture.enabled and is_instance_valid(record.body) and record.body.enabled

func _world_geometry(record: Dictionary) -> void:
	var fixture = record.fixture
	if fixture.shape == null: return
	if record.shape_id != fixture.shape.get_instance_id() or record.shape_version != int(_shape_versions.get(record.shape_id, 0)): _update_geometry(record)
	var transform: Transform2D = fixture.global_transform
	if transform == record.transform and not record.world_points.empty(): return
	record.transform = transform
	var points = PoolVector2Array()
	var bounds = Rect2()
	for point in record.points:
		var p = transform.xform(point)
		if points.empty(): bounds = Rect2(p, Vector2.ZERO)
		else: bounds = bounds.expand(p)
		points.append(p)
	record.world_points = points
	record.bounds = bounds

func _draw() -> void:
	if show_hitboxes:
		var inverse = get_canvas_transform().affine_inverse()
		var viewport = get_viewport_rect()
		var visible_rect = Rect2(inverse.xform(viewport.position), Vector2.ZERO)
		for corner in [Vector2(viewport.end.x,viewport.position.y), viewport.end, Vector2(viewport.position.x,viewport.end.y)]: visible_rect = visible_rect.expand(inverse.xform(corner))
		for record in _fixtures.values():
			if not bool(hitbox_categories.get(record.category, false)) or not _active(record): continue
			_world_geometry(record)
			if record.points.size() < 2 or not visible_rect.grow(4).intersects(record.bounds, true): continue
			draw_set_transform_matrix(global_transform.affine_inverse() * record.transform)
			draw_polyline(record.points, COLORS[record.category], 2.0, true)
		draw_set_transform_matrix(Transform2D())
	if show_trajectory:
		var points = _prediction.points
		var inverse = global_transform.affine_inverse()
		for i in range(points.size() - 1):
			if i % 2 == 0: draw_line(inverse.xform(points[i]), inverse.xform(points[i+1]), TRAJECTORY_COLOR, 2.5, true)
		if _prediction.death:
			var p = inverse.xform(_prediction.contact)
			draw_circle(p, 9, Color(0.18,0.03,0.08,0.9))
			draw_line(p + Vector2(-5,-5), p + Vector2(5,5), HAZARD_COLOR, 3, true)
			draw_line(p + Vector2(-5,5), p + Vector2(5,-5), HAZARD_COLOR, 3, true)

func _update_prediction() -> void:
	_prediction = {"points": PoolVector2Array(), "death": false}
	if not is_instance_valid(tas_tool): return
	var player = tas_tool.call("_get_local_player")
	var game = tas_tool.call("_find_game")
	if player == null or not player.alive or player.body == null or game == null: return
	var candidates = []
	var player_polygon = PoolVector2Array()
	for record in _fixtures.values():
		if not _active(record): continue
		_world_geometry(record)
		if record.category == "player":
			if record.fixture == player.fixture:
				for p in record.world_points: player_polygon.append(p - player.body.global_position)
			continue
		if record.fixture.sensor and record.category != "hazards": continue
		candidates.append(record)
	if player_polygon.empty(): return
	_prediction = _predictor.predict(player.body.global_position, player.body.linear_velocity, float(game.wp_game_data.world_gravity), player_polygon, candidates, TRAJECTORY_HORIZON_SECONDS, TRAJECTORY_STEPS)
