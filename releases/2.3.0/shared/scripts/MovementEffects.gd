extends Node2D

# Renderer-only effects. Never writes to a player, game clock, or network API.
const DASH = ["default", "none", "sparks", "stars"]
var settings = {}
var dash_particles: Particles2D
var trail_particles: Particles2D
var renderer = null
var _signature = ""
var _was_alive = true
var _previous_point = Vector2.ZERO
var _sampled = false
var _native_material
var _native_texture
var _preview_line: Line2D
var _settings_elapsed = 1.0

func _ready() -> void:
	set_process_priority(1000002)
	var source = load("res://renderers/WPPlayer.tscn").instance()
	dash_particles = source.get_node("Position/DashTrailParticles").duplicate()
	trail_particles = source.get_node("Position/DashTrailParticles").duplicate()
	_native_material = dash_particles.process_material.duplicate(true)
	_native_texture = dash_particles.texture
	if renderer == null:
		_preview_line = source.get_node("DashTrail").duplicate()
		_preview_line.clear_points()
		_preview_line.visible = false
		add_child(_preview_line)
	source.free()
	for particle in [dash_particles, trail_particles]:
		particle.process_material = particle.process_material.duplicate(true)
		particle.amount = 18
		particle.lifetime = 0.3
		particle.emitting = false
		particle.local_coords = false
		particle.visibility_rect = Rect2(-2000, -2000, 4000, 4000)
		add_child(particle)

func configure(value: Dictionary) -> void:
	var signature = str(value.get("dash", "default")) + ":" + str(value.get("trail", "default")) + ":" + str(value.get("color", "9dd6bd"))
	if signature == _signature or dash_particles == null:
		return
	settings = value.duplicate(true)
	_signature = signature
	var color = Color(str(settings.get("color", "9dd6bd")))
	for pair in [[dash_particles, str(settings.get("dash", "default"))], [trail_particles, str(settings.get("trail", "default"))]]:
		var particle = pair[0]
		particle.emitting = false
		particle.restart()
		if pair[1] == "default":
			particle.texture = _native_texture
			particle.process_material = _native_material.duplicate(true)
			continue
		particle.process_material = _native_material.duplicate(true)
		particle.texture = load("res://project_specific/gfx/particle-starsharp.png" if pair[1] == "stars" else "res://project_specific/gfx/particle-cloud.png")
		particle.process_material.color_ramp = null
		particle.process_material.color = color
		particle.process_material.scale = 0.08 if pair[1] == "sparks" else (0.12 if pair[1] == "stars" else 0.22)

func sample(point: Vector2, dashing: bool, moving: bool, alive: bool = true) -> void:
	position = point
	if (not alive and _was_alive) or (_sampled and _previous_point.distance_squared_to(point) > 90000):
		clear()
	_sampled = true
	_previous_point = point
	_was_alive = alive
	dash_particles.emitting = alive and dashing and (str(settings.get("dash", "default")) in ["sparks", "stars"] or (renderer == null and str(settings.get("dash", "default")) == "default"))
	trail_particles.emitting = alive and moving and str(settings.get("trail", "default")) in ["soft", "stars"]
	if _preview_line != null:
		_preview_line.position = -point
		_preview_line.visible = alive and dashing and str(settings.get("trail", "default")) == "default"
		if _preview_line.visible:
			_preview_line.add_point(point)
			if _preview_line.get_point_count() > 10:
				_preview_line.remove_point(0)
		else:
			_preview_line.clear_points()

func clear() -> void:
	if _preview_line != null:
		_preview_line.clear_points()
		_preview_line.hide()
	for particle in [dash_particles, trail_particles]:
		if particle != null:
			particle.emitting = false
			particle.restart()

func _process(_delta: float) -> void:
	if renderer == null or not is_instance_valid(renderer):
		return
	var player = renderer.get_network_object()
	if player == null:
		clear()
		return
	_settings_elapsed += _delta
	if _settings_elapsed >= 0.25 or not bool(SavedSettings.get_value("ping_optimizer_enabled",true)):
		_settings_elapsed = 0.0
		var value = SavedSettings.get_value("studio_movement_effects", {})
		if not bool(SavedSettings.get_value("studio_movement_effects_enabled", true)):
			value = {}
		configure(value if value is Dictionary else {})
	var origin = renderer.get_node("Position")
	sample(origin.position, player.dash_timer > 0, player.linear_velocity.length_squared() > 625, player.alive)
	var native_dash = renderer.get_node("Position/DashTrailParticles")
	var native_trail = renderer.get_node("DashTrail")
	native_dash.visible = not str(settings.get("dash", "default")) in ["none", "sparks", "stars"]
	# Default visibility belongs to the native renderer (only during a dash).
	# Never force it on: that leaves an old trail visible while standing still.
	if str(settings.get("trail", "default")) in ["none", "soft", "stars"]:
		native_trail.visible = false
