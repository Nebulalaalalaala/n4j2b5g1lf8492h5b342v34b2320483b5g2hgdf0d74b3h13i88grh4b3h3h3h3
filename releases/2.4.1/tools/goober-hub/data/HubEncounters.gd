extends Node
# Notes who was in each online match you play (not time trials, replays,
# custom lobbies or the editor) and who won it. Local only.
var hub
var game = null
var others = {}
var map_name = ""
var elapsed = 0.0
var ended = false

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS

func _process(delta):
	elapsed += delta
	if elapsed < 0.5:
		return
	elapsed = 0.0
	var tool = hub.tool
	var current = tool._find_game() if tool != null and is_instance_valid(tool) else null
	if current != game:
		_finish("")
		_disconnect()
		game = current
		ended = false
		if game != null and game.has_signal("game_over"):
			game.connect("game_over", self, "_game_over")
	if game == null or not is_instance_valid(game) or hub.store.account.empty() or ended:
		return
	var d = game.wp_game_data
	if d.is_replay or d.is_level_editor or d.is_tutorial or d.is_time_trial or bool(game.get("is_custom_game")):
		others = {}
		return
	if game.level != null and game.level.loaded_level != null:
		map_name = str(game.level.loaded_level.level_name)
	for i in game.get_player_count():
		var player = game.get_player_at_index(i)
		if player == null or game.is_local_player(player.object_id):
			continue
		var meta = game.get_metadata_for_player(player.object_id)
		var id = str(meta.get("uuid", "")) if meta is Dictionary else ""
		if id.length() == 36 and id != hub.store.account:
			others[id] = str(meta.get("name", others.get(id, "")))

func _game_over(winner_id):
	var winner = ""
	if game != null and is_instance_valid(game):
		if game.is_local_player(winner_id):
			winner = hub.store.account
		else:
			var meta = game.get_metadata_for_player(winner_id)
			winner = str(meta.get("uuid", "")) if meta is Dictionary else ""
	_finish(winner)
	ended = true

func _finish(winner):
	if not others.empty() and not hub.store.account.empty():
		hub.store.add_match(OS.get_unix_time(), map_name, others, winner)
		hub.encounters_changed()
	others = {}

func _disconnect():
	if game != null and is_instance_valid(game) and game.is_connected("game_over", self, "_game_over"):
		game.disconnect("game_over", self, "_game_over")

func _exit_tree():
	_disconnect()
