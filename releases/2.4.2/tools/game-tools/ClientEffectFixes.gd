extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

var _emote_script
var _renderers = []

func _ready() -> void:
	_emote_script = load(get_script().resource_path.get_base_dir().plus_file("ClientEmote.gd"))
	set_process_priority(1000001)
	get_tree().connect("node_added", self, "_consider")
	_scan(get_tree().root)

func _scan(node: Node) -> void:
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _consider(node: Node) -> void:
	if node.has_method("show_single_animation_and_hide") and node.get_script() != _emote_script:
		node.set_script(_emote_script)
	if node is UpGuys_PlayerRenderer and not _renderers.has(node):
		_renderers.append(node)

func _process(_delta: float) -> void:
	var live = []
	for renderer in _renderers:
		if not is_instance_valid(renderer) or not renderer.is_inside_tree():
			continue
		live.append(renderer)
		var game = renderer.get_network_game()
		if game != null and game.is_local_player(renderer.get_object_id()) and renderer.get_node_or_null("StudioMovementEffects") == null:
			var effects = load(ModPaths.path("MovementEffects.gd")).new()
			effects.name = "StudioMovementEffects"
			effects.renderer = renderer
			renderer.add_child(effects)
		var dust = renderer.floor_dust_particles
		var player = renderer.get_network_object()
		if not is_instance_valid(dust) or player == null:
			continue
		# Native regression: +251 emits, +250 and every negative speed do not.
		# Preserve the grounded/alive/non-dash gates; change only signed speed.
		dust.emitting = player.alive and player.stick_to_ground_timer > 0 and player.dash_timer <= 0 and abs(player.ground_tangent_speed) > 250.0
		if dust.emitting:
			# Spine facing can reflect the parent vertically. Keep the emitter at
			# the feet and its upward plume aligned with the surface on both sides.
			var normal: Vector2 = player.ground_normal.normalized()
			if normal.length_squared() > 0.5:
				dust.global_transform = Transform2D(normal.angle() + PI * 0.5, dust.get_parent().global_position - normal * 35.0)
	_renderers = live
