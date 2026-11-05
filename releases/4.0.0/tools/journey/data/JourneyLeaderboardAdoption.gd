extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Persistent controller child, independent of Journey being open or XP > 0.
# No ledger, claim, password, refresh-token or native-account writes.
signal adopted(player)
const FUNCTION = "journey-adopt"
var account_id = ""
var status = "idle"
var _url = ""
var _key = ""
var _http
var _phase = ""
var _request_owner = ""
var _confirmed = {}
var _member_checked = {}
var _ready_endpoint = false
var _missing = false
var _next = 0
var _failures = 0
var _elapsed = 0.0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var config = ModPaths.try_load(ModPaths.path("OnlineConfig.gd"))
	if config != null:
		_url = str(config.SUPABASE_URL).rstrip("/")
		_key = config.anon_key()
	_http = HTTPRequest.new()
	_http.timeout = 18
	_http.body_size_limit = 8192
	# Avoid following an unexpected redirect with the session credential.
	_http.max_redirects = 0
	add_child(_http)
	_http.connect("request_completed", self, "_completed")

func configure(id):
	var next_owner = str(id)
	if next_owner == account_id: return
	account_id = next_owner
	_failures = 0
	_next = 0
	status = "idle"
	if not _phase.empty():
		_http.cancel_request()
		_phase = ""
		_request_owner = ""

func _process(delta):
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	if _http == null or _missing or _confirmed.has(account_id) or not _phase.empty() or OS.get_unix_time() < _next: return
	var moonlight = get_node_or_null("/root/Moonlight")
	if not eligible(moonlight, account_id) or not _url.begins_with("https://") or _key.empty(): return
	_request_owner = account_id
	_phase = ("adopt" if _member_checked.has(account_id) else "member") if _ready_endpoint else "probe"
	var headers = PoolStringArray(["apikey: " + _key, "Authorization: Bearer " + _key, "Content-Type: application/json"])
	var url = _url + "/rest/v1/rpc/journey_seed_status"
	var body = ""
	if _phase == "member":
		url = _url + "/rest/v1/rpc/journey_existing_players"
		body = JSON.print({"p_players": [account_id.sha256_text().substr(0, 32)]})
	if _phase == "adopt":
		url = _url + "/functions/v1/" + FUNCTION
		# Only the current access token, in memory; never persist or log it.
		headers.append("X-Goober-Session: " + str(moonlight.session.token))
		body = JSON.print({"user_id": account_id})
	status = "checking"
	if _http.request(url, headers, true, HTTPClient.METHOD_POST, body if not body.empty() else "{}") != OK:
		_phase = ""
		_retry()

static func eligible(moonlight, id) -> bool:
	if moonlight == null or str(id).empty() or not moonlight.has_method("is_logged_in") or not moonlight.is_logged_in(): return false
	var session = moonlight.get("session")
	var storage = moonlight.get("storage")
	return session != null and session.is_valid() and not session.is_expired() and not str(session.token).empty() and str(session.user_id) == str(id) and storage != null and str(storage.storage_get("account.user.id", "")) == str(id)

func _completed(result, code, _headers, bytes):
	var phase = _phase
	var id = _request_owner
	_phase = ""
	_request_owner = ""
	if phase.empty() or account_id != id: return
	if code == 404:
		_missing = true
		status = "setup_needed"
		return
	var parsed = JSON.parse(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or parsed.error != OK:
		_retry()
		return
	if phase == "member":
		if not parsed.result is Array:
			_retry()
			return
		if parsed.result.has(id.sha256_text().substr(0, 32)):
			_confirmed[id] = true
			status = "ready"
			emit_signal("adopted", id.sha256_text().substr(0, 32))
		else:
			_member_checked[id] = true
			_next = 0
			status = "idle"
		return
	if not parsed.result is Dictionary:
		_retry()
		return
	if phase == "probe":
		_ready_endpoint = int(parsed.result.get("version", 0)) == 1 and str(parsed.result.get("activation", "")) == "nakama-account-v1"
		_next = 0 if _ready_endpoint else OS.get_unix_time() + 600
		status = "idle" if _ready_endpoint else "setup_needed"
	elif bool(parsed.result.get("adopted", false)) and str(parsed.result.get("player", "")) == id.sha256_text().substr(0, 32):
		_confirmed[id] = true
		status = "ready"
		emit_signal("adopted", str(parsed.result.player))
	else:
		_retry()

func _retry():
	_failures += 1
	_next = OS.get_unix_time() + int(min(600, 30 * pow(2, min(_failures - 1, 5))))
	status = "retry_later"
