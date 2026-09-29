extends Node

signal status_changed(text)

var server = null
var client = null
var control = WebSocketClient.new()
var control_id = ""
var control_token = ""
var player_id = ""
var player_token = ""
var elapsed = 0.0
var playing = false
var stopping = false
var status_text = "Starting local mode..."
var port = 0
var matchmaking = false
var allocation_id = ""
var assigned_levels = {}

func prepare_match(data) -> String:
	matchmaking = true
	allocation_id = str(data.get("match_id", ""))
	player_id = str(data.get("player_id", ""))
	player_token = str(data.get("player_token", ""))
	assigned_levels = data.get("levels", {})
	if allocation_id.empty() or player_id.empty() or player_token.empty() or data.get("capacity") != 1:
		return "Invalid solo allocation."
	return prepare()

func prepare() -> String:
	var base = get_script().resource_path.get_base_dir()
	var client_pack = load("res://scenes/ClientScene.tscn")
	var server_pack = load("res://nodes/WPGame.tscn")
	var local_client = load(base.plus_file("LocalClient.gd"))
	if client_pack == null or server_pack == null or local_client == null:
		return "Required local gameplay resources are missing."
	var level_file = File.new()
	if level_file.open("res://project_specific/levels/claws.json", File.READ) != OK:
		return "The bundled Claws map is missing."
	var level_text = level_file.get_as_text()
	level_file.close()
	var parsed = JSON.parse(level_text)
	if parsed.error != OK or not parsed.result is Dictionary:
		return "The bundled map could not be read."
	var crypto = Crypto.new()
	control_id = crypto.generate_random_bytes(16).hex_encode()
	control_token = crypto.generate_random_bytes(32).hex_encode()
	if not matchmaking:
		player_id = crypto.generate_random_bytes(16).hex_encode()
		player_token = crypto.generate_random_bytes(32).hex_encode()
	# Reserve an unused local port. Native listener binding is checked separately.
	var reservation = TCP_Server.new()
	for candidate in range(27120, 27140):
		if reservation.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			reservation.stop()
			break
	if port == 0:
		return "No local test port is available."
	var view = client_pack.instance()
	view.set_script(local_client)
	view.set("_game", NodePath("WPGame"))
	_localize_info_panels(view, base)
	var party = view.get_node_or_null("Moonlight_SetPartyStatusOnReady")
	if party != null:
		view.remove_child(party)
		party.free()
	client = view.get_node("WPGame")
	client.type = NetworkGame.CLIENT
	client.server_type = NetworkGame.NONE
	client.server_address = "127.0.0.1"
	client.server_fallback_address = "127.0.0.1"
	client.server_websocket_port = port
	client.server_websocket_ssl = false
	client.client_uuid = player_id
	client.client_auth_token = player_token
	client.client_use_webrtc_if_available = false
	# Client first so existing mod discovery selects the visible player.
	add_child(view)
	server = server_pack.instance()
	server.name = "LocalServer"
	server.type = NetworkGame.SERVER
	server.server_type = NetworkGame.NONE
	server.server_address = "127.0.0.1"
	server.server_websocket_port = port
	server.server_enet_port = 0
	server.server_webrtc_port = 0
	server.server_websocket_ssl = false
	server.server_control_uuid = control_id
	server.server_control_auth_token = control_token
	server.game_metadata = {"lobby_type": "custom", "game_mode": "SingleMapRace", "lobby_mode": "Lobby", "level_data": {"0": level_text, "1": level_text}}
	if matchmaking:
		var maps = {}
		var allowed = ["special/lobby.json", "big_betty.json", "contained.json", "claws.json", "eliminating.json"]
		for key in ["0", "32", "16", "8", "4"]:
			var filename = str(assigned_levels.get(key, ""))
			if not filename in allowed:
				server.free()
				server = null
				return "Invalid matchmaking map selection."
			var file = File.new()
			if file.open("res://project_specific/levels/" + filename, File.READ) != OK:
				server.free()
				server = null
				return "A matchmaking map is missing."
			maps[key] = file.get_as_text()
			file.close()
		# Normal Solo/RaceRoyale rules, but no official result submission.
		server.game_metadata = {"lobby_type": "custom", "game_mode": "Solo", "lobby_mode": "Lobby", "local_match_id": allocation_id, "level_data": maps}
	add_child(server)
	return ""

func _localize_info_panels(node, base):
	if node.get_script() != null and node.get_script().resource_path == "res://project_specific/ui/LevelInfoPanel.gd":
		var saved_exports = {}
		for property in node.get_script().get_script_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				saved_exports[property.name] = node.get(property.name)
		node.set_script(load(base.plus_file("LocalLevelInfo.gd")))
		for key in saved_exports:
			node.set(key, saved_exports[key])
	for child in node.get_children():
		_localize_info_panels(child, base)

func _ready():
	if server == null or client == null:
		_fail("Local mode was not prepared.")
		return
	if matchmaking:
		server.wp_game_data.match_id = allocation_id
	server.mark_server_as_loaded()
	server.start_game()
	client.connect("client_connection_error", self, "_connection_failed", [], CONNECT_DEFERRED)
	control.connect("connection_established", self, "_control_connected")
	control.connect("connection_error", self, "_connection_failed")
	if control.connect_to_url("ws://127.0.0.1:%d" % port) != OK:
		_fail("Could not connect to the local server.")

func _control_connected(_protocol):
	var message = NetworkMessage.new()
	message.type = NetworkMessage.SERVER_CONTROL_ADD_PLAYER_REQUEST
	message.raw_data = to_json({"serverControlUUID": control_id, "serverControlAuthToken": control_token, "serverLobbyCountdown": 60.0, "player": {"PlayerID": player_id, "PlayerGameAuth": player_token, "PlayerName": "Local player", "PlayerType": "REAL", "PlayerData": {"match_type": "regular"}}}).to_utf8()
	var error = control.get_peer(1).put_packet(message.serialize_to_new_buffer())
	if error != OK:
		_fail("Local player registration failed.")
		return
	# Wait for the control reply before starting authentication.
	control.connect("data_received", self, "_control_reply", [], CONNECT_ONESHOT)

func _control_reply():
	control.get_peer(1).get_packet()
	client.client_connection_type = NetworkGame.WEBSOCKET
	client.client_use_webrtc_if_available = false
	client.start_game()

func retry():
	if playing and not stopping:
		server._reset_players()

func _process(delta):
	if stopping:
		return
	control.poll()
	elapsed += delta
	if not playing and client != null and client.get_local_player() != null:
		playing = true
		if matchmaking:
			server.server_trigger_lobby_countdown()
			_set_status("Solo matchmaking — connected (1/1)")
		else:
			server._reset_players()
			_set_status("Local mode — Claws")
		var hud = get_node_or_null("ClientScene/UI/HUD/GameHUD")
		if hud != null and not matchmaking:
			hud.retry_button.visible = true
			hud.connect("retry_button_pressed", self, "retry")
	if not playing and elapsed > 12.0:
		_fail("Local player could not join. Stop and try again.")

func _connection_failed():
	call_deferred("_fail", "Local server connection failed.")

func _set_status(text):
	status_text = text
	emit_signal("status_changed", text)

func _fail(text):
	stop()
	_set_status(text)

func stop():
	if stopping:
		return
	stopping = true
	control.disconnect_from_host()
	if is_instance_valid(client):
		client.stop_game()
	if is_instance_valid(server):
		server.stop_game()

func _exit_tree():
	stop()
