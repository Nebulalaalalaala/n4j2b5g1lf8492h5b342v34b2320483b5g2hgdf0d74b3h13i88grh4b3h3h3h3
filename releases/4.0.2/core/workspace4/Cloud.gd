extends Node

# Supabase REST calls for the 4.0 Workshop and News pages. Uses the shared
# publishable key from OnlineConfig; what it can read or write is limited by
# row-level security on the server (see supabase/workshop_news.sql).

signal finished(tag, ok, data)

const OnlineConfig = preload("user://mod/shared/scripts/OnlineConfig.gd")
const MAX_RESPONSE_BYTES = 2097152
const MAX_UPLOAD_BYTES = 65536

var busy := {}


func get_rows(tag: String, path: String) -> void:
	_send(tag, HTTPClient.METHOD_GET, path, null)


func insert(tag: String, table: String, row: Dictionary) -> void:
	_send(tag, HTTPClient.METHOD_POST, table, row, ["Prefer: return=minimal"])


func call_function(tag: String, function_name: String, args: Dictionary) -> void:
	_send(tag, HTTPClient.METHOD_POST, "rpc/" + function_name, args)


func _send(tag: String, method: int, path: String, body, extra: Array = []) -> void:
	if busy.get(tag, false):
		return
	var payload = "" if body == null else to_json(body)
	if payload.length() > MAX_UPLOAD_BYTES + 4096:
		emit_signal("finished", tag, false, "That is too large to upload.")
		return
	var http = HTTPRequest.new()
	http.body_size_limit = MAX_RESPONSE_BYTES
	if "timeout" in http:
		http.timeout = 15
	add_child(http)
	http.connect("request_completed", self, "_done", [tag, http])
	var key = OnlineConfig.anon_key()
	var headers = PoolStringArray(["apikey: " + key, "Authorization: Bearer " + key, "Content-Type: application/json", "Accept: application/json"])
	for line in extra:
		headers.append(line)
	busy[tag] = true
	if http.request(OnlineConfig.SUPABASE_URL + "/rest/v1/" + path, headers, true, method, payload) != OK:
		busy[tag] = false
		http.queue_free()
		emit_signal("finished", tag, false, "Couldn't connect.")


func _done(result: int, code: int, _headers, body: PoolByteArray, tag: String, http: HTTPRequest) -> void:
	busy[tag] = false
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("finished", tag, false, "Couldn't reach the server.")
		return
	if code < 200 or code >= 300:
		emit_signal("finished", tag, false, "Server said no (HTTP %d)." % code)
		return
	var text = body.get_string_from_utf8()
	if text.strip_edges().empty():
		emit_signal("finished", tag, true, null)
		return
	var parsed = JSON.parse(text)
	if parsed.error != OK:
		emit_signal("finished", tag, false, "Unexpected reply.")
		return
	emit_signal("finished", tag, true, parsed.result)
