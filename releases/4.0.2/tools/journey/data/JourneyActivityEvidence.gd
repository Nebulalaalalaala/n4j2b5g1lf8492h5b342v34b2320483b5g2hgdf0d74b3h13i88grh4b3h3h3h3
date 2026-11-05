extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Bounded sampling of existing local state. No RPCs, input injection or physics writes.
var service
var editor_ref
var last_game
var last_position = null
var editor_version = -1
var editor_high_water = -1
var editor_elapsed = 0.0
var had_edit = false
var coast = 0.0
var certified = {}
var cache_age = 60.0

func _ready():
	get_tree().connect("node_added", self, "_consider")
	_scan(get_tree().root)

func _scan(node):
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _consider(node):
	if node is LevelEditor:
		editor_ref = weakref(node)
		editor_version = -1
		editor_high_water = -1
		had_edit = false

func reset():
	last_game = null
	last_position = null
	coast = 0.0
	had_edit = false
	editor_elapsed = 0.0
	editor_version = -1
	editor_high_water = -1

func sample(delta, account):
	cache_age += delta
	if service == null or service._synthetic():
		reset()
		return 0.0
	var editor = editor_ref.get_ref() if editor_ref != null else null
	if is_instance_valid(editor) and editor.is_visible_in_tree() and not editor.is_playing and editor.undo != null:
		last_game = null
		last_position = null
		coast = 0.0
		var version = editor.undo.get_version()
		return editor_credit(delta, version)
	had_edit = false
	editor_elapsed = 0.0
	var game = service.game
	if not is_instance_valid(game) or game.level.loaded_level == null:
		reset()
		return 0.0
	if game != last_game:
		last_game = game
		last_position = null
		coast = 0.0
	var data = game.wp_game_data
	var player = game.get_local_player()
	var eligible = not (data.is_replay or data.is_tutorial or data.is_level_editor or game.is_in_lobby())
	if data.is_time_trial:
		if cache_age >= 30.0:
			cache_age = 0.0
			certified.clear()
			for level in load(ModPaths.path("JourneyCertified.gd")).load_cache().get("levels", []):
				certified[str(level.get("id", ""))] = true
		eligible = eligible and certified.has(str(game.level.loaded_level.level_id))
	else:
		eligible = eligible and not game.is_server() and not game.is_custom_game
	eligible = eligible and player != null
	if eligible:
		eligible = str(player.uuid) == account and player.type == NetworkPlayer.REAL and player.alive and not player.eliminated and game.is_in_regular_play()
	if not eligible:
		last_position = null
		coast = 0.0
		return 0.0
	var distance = player.position.distance_to(last_position) if last_position != null else 0.0
	last_position = player.position
	var inputs = game.local_client_continuous_input
	var intent = (inputs.size() > 0 and inputs[0] != null and abs(float(inputs[0])) > 0.0) or (inputs.size() > 1 and bool(inputs[1]))
	return movement_credit(delta, distance, intent)

func editor_credit(delta, version):
	editor_elapsed += delta
	if editor_version < 0:
		editor_version = version
		editor_high_water = version
		return 0.0
	if version != editor_version:
		editor_version = version
		if version > editor_high_water:
			editor_high_water = version
			var earned = editor_elapsed if had_edit and editor_elapsed <= 30.0 else 0.0
			editor_elapsed = 0.0
			had_edit = true
			return earned
	return 0.0

func movement_credit(delta, distance, intent):
	# Reject teleports and stationary input spam; briefly retain legitimate
	# airborne/coasting motion after releasing input.
	if distance <= 0.1 or distance >= 800.0:
		coast = 0.0
		return 0.0
	if intent:
		coast = 3.0
	else:
		coast = max(0.0, coast - delta)
	return delta if coast > 0.0 else 0.0
