extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# What other Goobplayability players see of you: up to three featured badges and
# the equipped finish, stored on your journey_leaderboard row (submit_journey_look).
# Sent only when it changed, at most once a minute. Other players' rows are
# looked up in one request per profile / match and kept for 10 minutes.
signal looked_up

const TABLE = "journey_leaderboard"
const SUBMIT_FN = "submit_journey_look"
const SUBMIT_EVERY = 60
const KEEP = 600

var status = "idle"
var _cache = {}        # player key -> {"xp", "badges": [{"key", "tier"}], "finish", "at"}
var _sent = {"body": "", "at": 0}
var _queue = []
var _get = null
var _post = null
var _url = ""
var _key = ""

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var config = ModPaths.try_load(ModPaths.path("OnlineConfig.gd"))
	if config != null:
		_url = config.SUPABASE_URL
		_key = config.anon_key()
	_get = _request("_on_fetched")
	_post = _request("_on_submitted")

func _request(method):
	var http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.connect("request_completed", self, method)
	return http

func _headers() -> PoolStringArray:
	return PoolStringArray(["apikey: " + _key, "Authorization: Bearer " + _key, "Content-Type: application/json"])

static func player_key(user_id) -> String:
	return str(user_id).sha256_text().substr(0, 32)

# badges: [{"key", "tier"}] (featured, up to 3); finish: equipped finish key or "".
func publish(user_id, badges: Array, finish: String) -> void:
	if _key.empty() or status == "missing" or str(user_id).empty():
		return
	var parts = []
	for i in min(3, badges.size()):
		parts.append("%s:%d" % [str(badges[i].key), int(badges[i].tier)])
	var body = JSON.print({"p_player": player_key(user_id), "p_user_id": str(user_id), "p_badges": PoolStringArray(parts).join(","), "p_finish": finish})
	if body == _sent.body or OS.get_unix_time() - int(_sent.at) < SUBMIT_EVERY or _post.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_sent = {"body": body, "at": OS.get_unix_time()}
	_post.request("%s/rest/v1/rpc/%s" % [_url, SUBMIT_FN], _headers(), true, HTTPClient.METHOD_POST, body)

func _on_submitted(result, code, _h, _body) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		_sent.body = ""
		if code == 404:
			status = "missing"

# Cached look for a user id, or null when unknown / not a Goobplayability player.
func look(user_id):
	var row = _cache.get(player_key(user_id))
	return row if row != null and row.has("xp") else null

func has_fresh(user_id) -> bool:
	var row = _cache.get(player_key(user_id))
	return row != null and not row.get("pending", false) and OS.get_unix_time() - int(row.at) < KEEP

# Fetches the rows for these user ids that aren't cached yet (one request).
func lookup(user_ids: Array) -> void:
	if _key.empty() or status == "missing":
		return
	for id in user_ids:
		var k = player_key(id)
		if not str(id).empty() and not has_fresh(id) and not _queue.has(k) and not _cache.get(k, {}).get("pending", false):
			_queue.append(k)
	_next()

func _next() -> void:
	if _queue.empty() or _get.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var keys = _queue.slice(0, min(40, _queue.size()) - 1)
	_queue = _queue.slice(keys.size(), _queue.size() - 1) if _queue.size() > keys.size() else []
	var now = OS.get_unix_time()
	for k in keys:
		_cache[k] = {"at": now, "pending": true}   # misses are remembered too
	var url = "%s/rest/v1/%s?select=player,xp,badges,finish&player=in.(%s)" % [_url, TABLE, PoolStringArray(keys).join(",")]
	if _get.request(url, _headers(), true, HTTPClient.METHOD_GET) != OK:
		call_deferred("_next")

func _on_fetched(result, code, _h, body) -> void:
	var text = body.get_string_from_utf8()
	for k in _cache:
		_cache[k].erase("pending")
	if result == HTTPRequest.RESULT_SUCCESS and code == 400 and text.find("42703") >= 0:
		status = "missing"   # the database doesn't have the badges / finish columns yet
	elif result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed = JSON.parse(text)
		if parsed.error == OK and parsed.result is Array:
			for row in parsed.result:
				if row is Dictionary and _cache.has(str(row.get("player", ""))):
					_cache[str(row.player)] = {"at": OS.get_unix_time(), "xp": int(row.get("xp", 0)),
						"badges": _badges(row.get("badges")), "finish": str(row.get("finish", "")) if row.get("finish") != null else ""}
		status = "ready"
	emit_signal("looked_up")
	_next()

static func _badges(text) -> Array:
	var list = []
	if text == null:
		return list
	for part in str(text).split(",", false):
		var bits = part.split(":")
		if bits.size() == 2 and int(bits[1]) > 0 and list.size() < 3:
			list.append({"key": bits[0], "tier": int(bits[1])})
	return list
