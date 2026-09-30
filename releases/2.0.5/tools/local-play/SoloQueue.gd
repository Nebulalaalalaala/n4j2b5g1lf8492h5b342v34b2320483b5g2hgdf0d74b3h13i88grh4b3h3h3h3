extends Node

signal allocated(data)
signal failed(message)

const NODE_PATH = "E:/Program Files/nodejs/node.exe"
const ENDPOINT = "http://127.0.0.1:18080"
var process_id = -1
var owner_key = ""
var request_node
var waiting = false
var action = ""
var retry_at = 0
var deadline = 0
var match_id = ""
var heartbeat_at = 0

func _ready():
	request_node = HTTPRequest.new()
	request_node.timeout = 3.0
	add_child(request_node)
	request_node.connect("request_completed", self, "_response")

func join_queue():
	if waiting or action != "":
		return
	if process_id < 0:
		var server_path = get_script().resource_path.get_base_dir().plus_file("SoloMatchmaker.js")
		if not File.new().file_exists(NODE_PATH) or not File.new().file_exists(server_path):
			emit_signal("failed", "Local matchmaking runtime is missing.")
			return
		owner_key = Crypto.new().generate_random_bytes(32).hex_encode()
		process_id = OS.execute(NODE_PATH, [ProjectSettings.globalize_path(server_path), owner_key], false)
		if process_id <= 0:
			process_id = -1
			emit_signal("failed", "Could not start local matchmaking.")
			return
	waiting = true
	deadline = OS.get_ticks_msec() + 6000
	retry_at = OS.get_ticks_msec() + 300

func _send(operation):
	action = operation
	var error = request_node.request(ENDPOINT + "/" + operation, ["Authorization: Bearer " + owner_key, "Content-Type: application/json"], false, HTTPClient.METHOD_POST, to_json({"match_id": match_id}))
	if error != OK:
		action = ""
		_fail("Local matchmaking request failed.")

func _response(result, code, _headers, bytes):
	var operation = action
	action = ""
	if result != HTTPRequest.RESULT_SUCCESS and operation == "queue" and waiting and OS.get_ticks_msec() < deadline:
		retry_at = OS.get_ticks_msec() + 300
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Local matchmaking unavailable (%s). Stop and try again." % code)
		return
	var parsed = JSON.parse(bytes.get_string_from_utf8())
	if parsed.error != OK or not parsed.result is Dictionary:
		_fail("Invalid matchmaking response.")
		return
	if operation == "queue" and waiting:
		var data = parsed.result
		if not data.has("match_id") or not data.has("player_id") or not data.has("player_token") or data.get("capacity") != 1:
			_fail("Invalid solo match allocation.")
			return
		waiting = false
		match_id = data.match_id
		heartbeat_at = OS.get_ticks_msec() + 5000
		emit_signal("allocated", data)

func mark_ready():
	if action == "" and match_id != "":
		_send("ready")

func cancel():
	waiting = false
	request_node.cancel_request()
	action = ""
	match_id = ""
	# This process is private to this controller. Ending it also clears its queue.
	if process_id > 0:
		OS.kill(process_id)
		process_id = -1

func _fail(message):
	cancel()
	emit_signal("failed", message)

func _process(_delta):
	var now = OS.get_ticks_msec()
	if waiting and action == "" and now >= retry_at:
		_send("queue")
	elif not waiting and match_id != "" and action == "" and now >= heartbeat_at:
		heartbeat_at = now + 5000
		_send("heartbeat")

func _exit_tree():
	cancel()
