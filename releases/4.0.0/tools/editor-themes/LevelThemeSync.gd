extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Theme pack themes chosen for published levels, shared through the
# Goobplayability Supabase project (table level_themes) so everyone using
# Goobplayability sees them. The whole list is small: fetched once at start and
# every 15 minutes. Only a level's author sets its theme (set_level_theme; the
# first account to set a level's theme owns it).
signal updated

const TABLE = "level_themes"
const SUBMIT_FN = "set_level_theme"
const FETCH_EVERY = 900

var themes = {}      # level id -> theme key
var _fetched_at = 0
var _get = null
var _post = null
var _url = ""
var _key = ""
var _wanted = {}     # level id -> body still to send (latest choice wins)
var _sent_at = {}    # level id -> unix time of the last send
var _sent_body = {}  # level id -> last body sent
var _fetched = false
var _last_count = -1

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var config = ModPaths.try_load(ModPaths.path("OnlineConfig.gd"))
	if config != null:
		_url = config.SUPABASE_URL
		_key = config.anon_key()
	_get = _request("_on_fetched")
	_post = _request("_on_submitted")
	fetch()

func _request(method):
	var http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.connect("request_completed", self, method)
	return http

func _headers() -> PoolStringArray:
	return PoolStringArray(["apikey: " + _key, "Authorization: Bearer " + _key, "Content-Type: application/json"])

func theme_for(level_id) -> String:
	return str(themes.get(str(level_id), ""))

func fetch() -> void:
	if _key.empty() or _get.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_fetched_at = OS.get_unix_time()
	_get.request("%s/rest/v1/%s?select=level_id,theme&limit=20000" % [_url, TABLE], _headers(), true, HTTPClient.METHOD_GET)

func _process(_delta):
	if OS.get_unix_time() - _fetched_at >= FETCH_EVERY:
		fetch()
	# The server ignores a second change to the same level within 5 seconds, so a
	# quick re-pick waits here and the latest choice is what gets sent.
	if not _wanted.empty() and _post.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		var now = OS.get_unix_time()
		for level_id in _wanted.keys():
			if now - int(_sent_at.get(level_id, 0)) >= 6:
				var body = _wanted[level_id]
				_wanted.erase(level_id)
				_sent_at[level_id] = now
				_sent_body[level_id] = body
				_post.request("%s/rest/v1/rpc/%s" % [_url, SUBMIT_FN], _headers(), true, HTTPClient.METHOD_POST, body)
				break

func _on_fetched(result, code, _h, body) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[ThemePack] could not load shared level themes (%d, %d)" % [result, code])
		return
	var parsed = JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or not parsed.result is Array:
		return
	var fresh = {}
	for row in parsed.result:
		if row is Dictionary and row.get("level_id") != null and row.get("theme") != null:
			fresh[str(row.level_id)] = str(row.theme)
	themes = fresh
	_fetched = true
	if themes.size() != _last_count:
		_last_count = themes.size()
		print("[ThemePack] shared level themes: %d" % themes.size())
	emit_signal("updated")

# theme "" puts the level back on its normal theme.
func publish(level_id, theme, user_id) -> void:
	if _key.empty() or str(level_id).empty() or str(user_id).empty():
		return
	var body = JSON.print({"p_level": str(level_id), "p_theme": theme,
		"p_player": str(user_id).sha256_text().substr(0, 32), "p_user_id": str(user_id)})
	var id = str(level_id)
	if _wanted.get(id, "") == body or (not _wanted.has(id) and (_sent_body.get(id, "") == body or (theme_for(id) == theme and _fetched))):
		return
	if theme.empty():
		themes.erase(id)
	else:
		themes[id] = theme
	_wanted[id] = body

func _on_submitted(result, code, _h, body) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code < 300:
		print("[ThemePack] shared a level theme")
	else:
		_sent_body.clear()   # let the next pick try again
		print("[ThemePack] sharing a level theme failed (%d, %d): %s" % [result, code, body.get_string_from_utf8().left(160)])
