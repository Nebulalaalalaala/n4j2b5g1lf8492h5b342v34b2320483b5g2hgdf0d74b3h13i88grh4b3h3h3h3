extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Custom Journey badges: designed in the admin tools (Ctrl+M) and awarded to
# players by user id. Stored in the Goobplayability Supabase project
# (journey_custom_badges, journey_badge_awards); every write goes through
# admin_* database functions that need the admin passphrase, which is only kept
# in memory for this session. Reads are one request per profile.
signal changed
signal admin_done(ok, message)

const EMBLEMS = ["crown", "podium", "exploration", "clock", "builder", "conqueror", "streak"]
const KEEP = 600

var catalog = {}       # badge id -> {"id", "name", "detail", "emblem", "frame"}
var _awards = {}       # player key -> {"at", "ids": [badge ids]}
var _catalog_at = 0
var _jobs = []
var _job = null
var _get = null
var _post = null
var _url = ""
var _key = ""
var _pass = ""

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var config = ModPaths.try_load(ModPaths.path("OnlineConfig.gd"))
	if config != null:
		_url = config.SUPABASE_URL
		_key = config.anon_key()
	_get = _request("_on_fetched")
	_post = _request("_on_admin_result")

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

# ---------------------------------------------------------------- reading
func badges_for(user_id) -> Array:
	var out = []
	var row = _awards.get(player_key(user_id))
	for id in (row.ids if row != null else []):
		if catalog.has(id):
			out.append(catalog[id])
	return out

func has_fresh(user_id) -> bool:
	var row = _awards.get(player_key(user_id))
	return row != null and row.has("ids") and OS.get_unix_time() - int(row.at) < KEEP and OS.get_unix_time() - _catalog_at < KEEP

func lookup(user_ids: Array) -> void:
	if _key.empty():
		return
	if OS.get_unix_time() - _catalog_at >= KEEP:
		_add_job({"kind": "catalog"})
	var keys = []
	for id in user_ids:
		if not str(id).empty() and not has_fresh(id):
			keys.append(player_key(id))
	if not keys.empty():
		_add_job({"kind": "awards", "keys": keys})
	_next()

func refresh_catalog() -> void:
	_catalog_at = 0
	lookup([])

func _add_job(job) -> void:
	for j in _jobs:
		if j.hash() == job.hash():
			return
	_jobs.append(job)

func _next() -> void:
	if _job != null or _jobs.empty() or _get.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_job = _jobs.pop_front()
	var url = "%s/rest/v1/journey_custom_badges?select=id,name,detail,emblem,frame&order=created_at.asc" % _url
	if _job.kind == "awards":
		url = "%s/rest/v1/journey_badge_awards?select=player,badge_id&player=in.(%s)" % [_url, PoolStringArray(_job.keys).join(",")]
	if _get.request(url, _headers(), true, HTTPClient.METHOD_GET) != OK:
		_job = null

func _on_fetched(result, code, _h, body) -> void:
	var job = _job
	_job = null
	var parsed = JSON.parse(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	var rows = parsed.result if parsed != null and parsed.error == OK and parsed.result is Array else null
	if job.kind == "catalog":
		_catalog_at = OS.get_unix_time()
		if rows != null:
			catalog = {}
			for r in rows:
				if r is Dictionary and r.get("id") != null:
					catalog[str(r.id)] = {"id": str(r.id), "name": str(r.get("name", "")), "detail": str(r.get("detail", "")) if r.get("detail") != null else "",
						"emblem": str(r.get("emblem", "crown")), "frame": int(clamp(int(r.get("frame", 0)), 0, 5))}
	else:
		var now = OS.get_unix_time()
		for k in job.keys:
			_awards[k] = {"at": now, "ids": []}   # no row = no custom badges
		for r in (rows if rows != null else []):
			if r is Dictionary and _awards.has(str(r.get("player", ""))):
				_awards[str(r.player)].ids.append(str(r.get("badge_id", "")))
	emit_signal("changed")
	_next()

# ---------------------------------------------------------------- admin
func set_pass(value) -> void:
	_pass = str(value).strip_edges()

func has_pass() -> bool:
	return not _pass.empty()

func save_badge(id, name, detail, emblem, frame) -> void:
	_admin("admin_save_badge", {"p_pass": _pass, "p_id": str(id), "p_name": str(name), "p_detail": str(detail), "p_emblem": str(emblem), "p_frame": int(frame)})

func delete_badge(id) -> void:
	_admin("admin_delete_badge", {"p_pass": _pass, "p_id": str(id)})

func award(badge_id, user_id, on) -> void:
	_awards.erase(player_key(user_id))
	_admin("admin_award_badge", {"p_pass": _pass, "p_badge": str(badge_id), "p_user_id": str(user_id).strip_edges(), "p_award": bool(on)})

func _admin(fn, body) -> void:
	if _key.empty() or _pass.empty():
		emit_signal("admin_done", false, "Enter the admin passphrase first.")
		return
	if _post.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		emit_signal("admin_done", false, "Still sending the last change.")
		return
	_post.request("%s/rest/v1/rpc/%s" % [_url, fn], _headers(), true, HTTPClient.METHOD_POST, JSON.print(body))

func _on_admin_result(result, code, _h, body) -> void:
	var text = body.get_string_from_utf8()
	if result == HTTPRequest.RESULT_SUCCESS and code < 300:
		refresh_catalog()
		emit_signal("admin_done", true, "Saved.")
	elif text.find("not allowed") >= 0:
		emit_signal("admin_done", false, "Wrong admin passphrase.")
	elif code == 404:
		emit_signal("admin_done", false, "Run journey-v5.sql in Supabase first.")
	else:
		emit_signal("admin_done", false, "Could not save (%d)." % int(code))
