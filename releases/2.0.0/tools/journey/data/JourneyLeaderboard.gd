extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Journey XP leaderboard for everyone using the tool, stored in the
# Goobplayability Supabase project. The project address and public key are read
# at runtime from ReplayHub.gd, so no second copy of the key exists. Talks only
# to Supabase over HTTPS, never to the Goober Dash servers. Light by design: the
# list is fetched only while the leaderboard is open (at most once a minute) and
# your score is sent at most every 2 minutes, only when your XP changed.
# Writes go through the submit_journey_xp database function only (the table
# itself is read-only to the public key); setup SQL is in JOURNEY_UI_HANDOFF.md.
signal updated

const TABLE = "journey_leaderboard"
const SUBMIT_FN = "submit_journey_xp"
const FETCH_EVERY = 60
const SUBMIT_EVERY = 120

var rows = []
var status = "idle"
var fetched_at = 0
var _submitted = {"xp": -1, "at": 0}
var _pending = null
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
	set_process(false)

func _request(method):
	var http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.connect("request_completed", self, method)
	return http

func _headers(extra = []) -> PoolStringArray:
	return PoolStringArray(["apikey: " + _key, "Authorization: Bearer " + _key, "Content-Type: application/json"] + extra)

static func player_key(account_id) -> String:
	return str(account_id).sha256_text().substr(0, 32)

func fetch(force = false) -> void:
	if _get == null or status == "loading" or (not force and OS.get_unix_time() - fetched_at < FETCH_EVERY):
		return
	if _url.empty() or _key.empty():
		fetched_at = OS.get_unix_time()
		if status != "unavailable":
			status = "unavailable"
			call_deferred("emit_signal", "updated")
		return
	status = "loading"
	var url = "%s/rest/v1/%s?select=player,display_name,xp,rank_name&order=xp.desc&limit=100" % [_url, TABLE]
	if _get.request(url, _headers(), true, HTTPClient.METHOD_GET) != OK:
		status = "error"
		fetched_at = OS.get_unix_time()
		call_deferred("emit_signal", "updated")

func _on_fetched(result, code, _headers_in, body) -> void:
	fetched_at = OS.get_unix_time()
	var text = body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		status = "error"
	elif code == 404 or text.find("PGRST205") >= 0 or text.find("does not exist") >= 0:
		status = "missing"
	elif code != 200:
		status = "error"
	else:
		var parsed = JSON.parse(text)
		rows = []
		if parsed.error == OK and parsed.result is Array:
			for row in parsed.result:
				if row is Dictionary:
					rows.append({"player": str(row.get("player", "")), "name": str(row.get("display_name", "")).substr(0, 40),
						"xp": int(row.get("xp", 0)), "rank": str(row.get("rank_name", "")).substr(0, 40)})
		status = "ready"
	emit_signal("updated")

# Called after renders; sends only when XP changed and not too often.
func submit(account_id, display_name, xp, rank_name) -> void:
	if _post == null or _key.empty() or str(account_id).empty() or int(xp) <= 0 or int(xp) == int(_submitted.xp):
		return
	_pending = {"player": player_key(account_id), "display_name": str(display_name).strip_edges().substr(0, 40),
		"xp": int(xp), "rank_name": str(rank_name).substr(0, 40)}
	if OS.get_unix_time() - int(_submitted.at) < SUBMIT_EVERY or _post.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		set_process(true)
		return
	_send()

func _process(_delta):
	if _pending != null and OS.get_unix_time() - int(_submitted.at) >= SUBMIT_EVERY and _post.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_send()

func _send() -> void:
	set_process(false)
	var row = _pending
	_pending = null
	if row.display_name.empty():
		row.display_name = "Goober"
	_submitted = {"xp": int(row.xp), "at": OS.get_unix_time()}
	var url = "%s/rest/v1/rpc/%s" % [_url, SUBMIT_FN]
	var body = {"p_player": row.player, "p_name": row.display_name, "p_xp": row.xp, "p_rank": row.rank_name}
	_post.request(url, _headers(), true, HTTPClient.METHOD_POST, JSON.print(body))

func _on_submitted(result, code, _headers_in, _body) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		_submitted.xp = -1
		if code == 404:
			status = "missing"
	elif status == "ready":
		fetched_at = 0
