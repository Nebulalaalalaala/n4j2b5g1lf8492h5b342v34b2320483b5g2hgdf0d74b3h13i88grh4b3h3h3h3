extends Node

var tool = null
var journey = null
var store = null
var game = null
var pending := {}
var round_key := ""
var was_alive := true
var serial := 0
var last_error := ""
var dialog_script
var excluded_round := ""

func _ready() -> void:
	store = load(get_script().resource_path.get_base_dir().plus_file("ProfileHistoryStore.gd")).new()
	dialog_script = load(get_script().resource_path.get_base_dir().plus_file("ProfileDialog.gd"))
	get_tree().connect("node_added", self, "_consider_profile")
	set_process_priority(1000002)

func _consider_profile(node: Node) -> void:
	if not node is UIPlayerProfileDialog or node.get_script() == dialog_script:
		return
	# node_added precedes _ready: retain scene-exported paths before extending
	# its script, then allow native initialization and its RPC to run normally.
	var paths := {}
	for property in node.get_property_list():
		if property.type == TYPE_NODE_PATH:
			paths[property.name] = node.get(property.name)
	node.set_script(dialog_script)
	for key in paths:
		node.set(key, paths[key])
	node.profile_service = self

func _physics_process(delta: float) -> void:
	if tool == null or not is_instance_valid(tool):
		return
	var owner_id := ""
	if Moonlight.local_account != null and Moonlight.local_account.user != null:
		owner_id = str(Moonlight.local_account.user.id)
	if owner_id != store.account_id:
		_flush()
		store.configure(owner_id)
	if owner_id.empty() or not store.writable:
		return
	_sample_game(tool._find_game(), delta)

func _sample_game(current, delta: float) -> void:
	if current != game:
		_flush()
		_disconnect_game()
		game = current
		if game != null:
			game.connect("player_hit_finish_line", self, "_finish")
			game.connect("player_eliminated", self, "_eliminated")
			game.connect("game_over", self, "_game_over")
			game.connect("reset_players", self, "_reset")
	if game == null or not is_instance_valid(game):
		return
	if game.level.loaded_level == null:
		return
	var level = game.level.loaded_level
	var key := str(game.get_instance_id()) + ":" + str(level.get_instance_id()) + ":" + str(game.wp_game_data.gameplay_round_counter)
	# Do not turn synthetic runs or paused previews into observed profile records.
	if _synthetic() or get_tree().paused or game.wp_game_data.is_replay or game.wp_game_data.is_level_editor or game.wp_game_data.is_tutorial:
		excluded_round = key
		pending = {}
		round_key = ""
		return
	if key == excluded_round:
		return
	var player = game.get_local_player()
	if player == null or game.level.loaded_level == null:
		return
	if key != round_key:
		_flush()
		round_key = key
	if pending.empty() and game.is_in_regular_play() and not str(level.level_id).empty():
		serial += 1
		pending = {"id": str(OS.get_unix_time()) + "-" + str(OS.get_ticks_usec()) + "-" + str(serial), "map_id": str(level.level_id), "map_name": str(level.level_name), "mode": "time_trial" if game.wp_game_data.is_time_trial else "match_round", "result": "unknown", "date": int(OS.get_unix_time()), "play_seconds": 0.0, "deaths": 0, "placement": 0, "players": int(game.get_player_count()), "finish_time": -1.0, "win": false, "custom": bool(game.is_custom_game)}
		was_alive = player.alive
	if not pending.empty() and game.is_in_regular_play():
		pending.play_seconds += max(0.0, delta)
		if was_alive and not player.alive:
			pending.deaths += 1
		was_alive = player.alive
	if game.is_game_over():
		_flush()

func _finish(player_id, rank, _out_of, _line, _position) -> void:
	if not _synthetic() and not pending.empty() and game != null and game.is_local_player(player_id):
		pending.result = "finish"
		pending.placement = int(rank)
		pending.finish_time = max(0.0, float(game.wp_game_data.play_time))

func _eliminated(player_id) -> void:
	if not pending.empty() and game != null and game.is_local_player(player_id) and pending.result != "finish":
		pending.result = "dnf"

func _game_over(winner_id) -> void:
	if not pending.empty() and game != null:
		# Only the reported match winner counts, not a qualifying round's rank 1.
		pending.win = pending.mode == "match_round" and game.is_local_player(winner_id)
		_flush()

func _reset() -> void:
	_flush()
	round_key = ""
	excluded_round = ""

func _flush() -> void:
	if _synthetic():
		pending = {}
	if pending.empty():
		return
	# A round that never ran (0 s, no result) is a state flicker after a round
	# ends, not a played round; recording it inflated round counts.
	if pending.result == "unknown" and float(pending.play_seconds) < 1.0:
		pending = {}
		return
	if store != null and not store.append(pending):
		last_error = store.last_error
	pending = {}

func _synthetic() -> bool:
	if tool == null or not is_instance_valid(tool):
		return false
	var autoplay = tool.get("_autoplay_bot")
	return tool._practice_active or tool._practice_playback or tool._macro_editor_preview_active or (autoplay != null and is_instance_valid(autoplay) and autoplay.is_active())

func _disconnect_game() -> void:
	if game != null and is_instance_valid(game):
		for pair in [["player_hit_finish_line", "_finish"], ["player_eliminated", "_eliminated"], ["game_over", "_game_over"], ["reset_players", "_reset"]]:
			if game.is_connected(pair[0], self, pair[1]):
				game.disconnect(pair[0], self, pair[1])

func _exit_tree() -> void:
	_flush()
	_disconnect_game()
