extends Node

# The compiled player renderer caches its native palette, then writes the dash
# tints every frame. Recolour its final result, keeping native white flashes.
# Never touch cooldown value, visibility, animations, input or player state.
var _bar: TextureProgress
var _renderer: Node
var _goober: Node
var _player
var _game_data
var _source_primary := Color.white
var _source_dark := Color(0.25, 0.25, 0.25)
var _primary := Color.white
var _dark := Color(0.25, 0.25, 0.25)
var _source_ready := false
var _has_sample := false
var _progress_input := Color.white
var _progress_output := Color.white
var _under_input := Color.white
var _under_output := Color.white


func _ready() -> void:
	process_priority = 1000001
	set_process(false)


func configure(renderer: Node, goober: Node, primary: Color, dark: Color) -> void:
	_renderer = renderer
	_goober = goober
	_bar = renderer.get_node_or_null("UIHolder/UI/DashCooldown") as TextureProgress
	if _bar == null:
		set_process(false)
		return
	_primary = primary
	_dark = dark
	if not _source_ready:
		_read_native_palette(renderer, goober)
	if not _source_ready:
		set_process(true)
		return
	if _same_colour(_primary, _source_primary) and _same_colour(_dark, _source_dark):
		restore_native()
		return
	set_process(true)
	_apply_tints()


func _read_native_palette(renderer: Node, goober: Node) -> void:
	# Metadata is the native renderer's original skin, not Studio's modified skin.
	_player = renderer.call("get_network_object")
	var game = renderer.call("get_network_game")
	if _player == null or game == null:
		return
	if not game.call("has_metadata_for_player", _player.object_id):
		return
	_game_data = game.get("wp_game_data")
	var metadata = game.call("get_metadata_for_player", _player.object_id)
	var skin = metadata.get("skin", {}) if typeof(metadata) == TYPE_DICTIONARY else {}
	if typeof(skin) != TYPE_DICTIONARY:
		skin = {}
	var gradient_name := ""
	var cosmetic_id: String = str(skin.get("color", "color_default" if goober.get("apply_defaults") else ""))
	if not cosmetic_id.empty():
		var cosmetic = CosmeticsCollection.lookup_cosmetic_id(cosmetic_id)
		if typeof(cosmetic) == TYPE_DICTIONARY and cosmetic.has("color"):
			gradient_name = str(cosmetic.get("color", ""))
		elif goober.get("apply_defaults"):
			gradient_name = "blue"
	elif goober.get("apply_defaults"):
		gradient_name = "blue"
	var gradient = goober.call("load_gradient", gradient_name)
	if gradient is Gradient and gradient.colors.size() > 0:
		_source_primary = gradient.colors[-1]
		_source_dark = gradient.colors[0]
	_source_ready = true


func _process(_delta: float) -> void:
	if not is_instance_valid(_bar):
		set_process(false)
		return
	if not _source_ready:
		if not is_instance_valid(_renderer) or not is_instance_valid(_goober):
			set_process(false)
			return
		_read_native_palette(_renderer, _goober)
		if not _source_ready:
			return
	if _bar.is_visible_in_tree():
		_apply_tints()


func _apply_tints() -> void:
	# Under-tint can persist while charging; don't recolour our previous output
	# again. On a new palette, reuse the last native sample instead.
	var progress: Color = _bar.tint_progress
	var under: Color = _bar.tint_under
	if not _has_sample or not _same_colour(progress, _progress_output):
		_progress_input = progress
	if not _has_sample or not _same_colour(under, _under_output):
		_under_input = under
	_progress_output = _replace_palette(_progress_input, _source_primary, _primary)
	# A native white body has no distinguishable ready pulse. Still preserve its
	# white pre-dash flash, using the existing timer (read-only).
	if _same_colour(_source_primary, Color.white) and is_instance_valid(_player) and _game_data != null:
		if _player.dash_timer > _game_data.player_dash_ticks - _game_data.player_dash_charge_ticks:
			_progress_output = _progress_input
	_under_output = _replace_palette(_under_input, _source_dark, _dark)
	_bar.tint_progress = _progress_output
	_bar.tint_under = _under_output
	_has_sample = true


func restore_native() -> void:
	set_process(false)
	if is_instance_valid(_bar) and _has_sample:
		_bar.tint_progress = _progress_input
		_bar.tint_under = _under_input
	_has_sample = false


func _replace_palette(value: Color, source: Color, target: Color) -> Color:
	var towards_white := Vector3(1.0 - source.r, 1.0 - source.g, 1.0 - source.b)
	var distance := towards_white.length_squared()
	var white_amount := 0.0
	if distance > 0.000001:
		var offset := Vector3(value.r - source.r, value.g - source.g, value.b - source.b)
		white_amount = clamp(offset.dot(towards_white) / distance, 0.0, 1.0)
	var result := target.linear_interpolate(Color.white, white_amount)
	result.a = value.a
	return result


func _same_colour(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.000001 and abs(a.g - b.g) < 0.000001 and abs(a.b - b.b) < 0.000001 and abs(a.a - b.a) < 0.000001
