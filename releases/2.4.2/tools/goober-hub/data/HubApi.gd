extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Goober Hub's Supabase requests: one queue, two connections, results by tag.
signal done(tag, ok, data, error)

var url = ""
var key = ""
var _queue = []
var _http = []
var _busy = {}

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var config = ModPaths.try_load(ModPaths.path("OnlineConfig.gd"))
	if config != null:
		url = config.SUPABASE_URL
		key = config.anon_key()
	for i in 2:
		var http = HTTPRequest.new()
		http.timeout = 15.0
		http.body_size_limit = 5 * 1024 * 1024
		add_child(http)
		http.connect("request_completed", self, "_completed", [http])
		_http.append(http)

func available() -> bool:
	return not key.empty() and not url.empty()

func _headers() -> PoolStringArray:
	return PoolStringArray(["apikey: " + key, "Authorization: Bearer " + key, "Content-Type: application/json"])

func call_fn(fn, args: Dictionary, tag) -> void:
	_add(tag, "/rest/v1/rpc/" + fn, HTTPClient.METHOD_POST, JSON.print(args))

func select(path, tag) -> void:
	_add(tag, "/rest/v1/" + path, HTTPClient.METHOD_GET, "")

func edge(fn, args: Dictionary, tag) -> void:
	_add(tag, "/functions/v1/" + fn, HTTPClient.METHOD_POST, JSON.print(args))

func pending(tag) -> bool:
	for item in _queue:
		if item.tag == tag: return true
	for http in _busy:
		if _busy[http].tag == tag: return true
	return false

func _add(tag, path, method, body):
	if not available():
		call_deferred("emit_signal", "done", tag, false, null, "offline")
		return
	_queue.append({"tag": tag, "path": path, "method": method, "body": body})
	_next()

func _next():
	for http in _http:
		if _queue.empty(): return
		if _busy.has(http): continue
		var item = _queue.pop_front()
		_busy[http] = item
		if http.request(url + item.path, _headers(), true, item.method, item.body) != OK:
			_busy.erase(http)
			call_deferred("emit_signal", "done", item.tag, false, null, "request failed")

func _completed(result, code, _headers_in, body, http):
	var item = _busy.get(http, {"tag": ""})
	_busy.erase(http)
	var text = body.get_string_from_utf8()
	var parsed = JSON.parse(text) if not text.empty() else null
	var data = parsed.result if parsed != null and parsed.error == OK else null
	if result == HTTPRequest.RESULT_SUCCESS and code < 300:
		emit_signal("done", item.tag, true, data, "")
	else:
		var message = "offline" if result != HTTPRequest.RESULT_SUCCESS else str(data.get("message", data.get("error", code))) if data is Dictionary else str(code)
		if code == 404 or text.find("PGRST202") >= 0 or text.find("PGRST205") >= 0:
			message = "missing"
		# Request bodies are never logged (the sign-in check carries a session token).
		# Moderation evidence and credentials must never enter runtime logs.
		var detail = "moderation request refused" if str(item.get("tag", "")).begins_with("hubmod:") else text.left(200).replace("\n", " ")
		print("[GooberHub] %s failed (%d, %d): %s" % [item.get("path", "?").split("?")[0], result, code, detail])
		emit_signal("done", item.tag, false, data, message)
	_next()
