extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Players as Goober Hub shows them: their hub row, Journey leaderboard row and
# (only when a profile is opened) the game's own profile with wins and skin.
signal changed

const KEEP = 300
const NATIVE_KEEP = 600
var api
var rows = {}       # user id -> merged row
var native = {}     # user id -> {"stats", "skin", "name", "level", "at"}
var names = {}      # user id -> name seen anywhere (friends, matches)
var _asked = {}
var _native_busy = false
var _native_queue = []

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	api.connect("done", self, "_done")

static func player_key(user_id) -> String:
	return str(user_id).sha256_text().substr(0, 32)

func row(user_id) -> Dictionary:
	return rows.get(str(user_id), {})

func name_for(user_id) -> String:
	var r = rows.get(str(user_id), {})
	for value in [r.get("name", ""), r.get("journey_name", ""), native.get(str(user_id), {}).get("name", ""), names.get(str(user_id), "")]:
		if not str(value).strip_edges().empty():
			return str(value).strip_edges()
	return "Goober"

func remember(user_id, value):
	if str(user_id).length() == 36 and not str(value).strip_edges().empty():
		names[str(user_id)] = str(value).strip_edges().substr(0, 40)

func lookup(ids: Array, force = false):
	var wanted = []
	var now = OS.get_unix_time()
	for id in ids:
		id = str(id)
		if id.length() == 36 and not wanted.has(id) and (force or now - int(_asked.get(id, 0)) > KEEP):
			wanted.append(id)
			_asked[id] = now
	while not wanted.empty():
		var part = wanted.slice(0, min(40, wanted.size()) - 1)
		wanted = wanted.slice(part.size(), wanted.size() - 1) if wanted.size() > part.size() else []
		api.select("hub_players?select=*&user_id=in.(%s)" % PoolStringArray(part).join(","), "players")
		var keys = []
		for id in part:
			keys.append(player_key(id))
		api.select("journey_leaderboard?select=player,display_name,xp,rank_name,badges,finish&player=in.(%s)" % PoolStringArray(keys).join(","), "journey_rows")

func _done(tag, ok, data, _message):
	if not ok or not data is Array:
		return
	if tag == "players":
		for r in data:
			if r is Dictionary:
				var merged = rows.get(str(r.user_id), {})
				for k in r:
					merged[k] = r[k]
				merged["hub"] = true
				rows[str(r.user_id)] = merged
		emit_signal("changed")
	elif tag == "journey_rows":
		var by_key = {}
		for id in _asked:
			by_key[player_key(id)] = id
		for r in data:
			if r is Dictionary and by_key.has(str(r.get("player", ""))):
				var id = by_key[str(r.player)]
				var merged = rows.get(id, {})
				merged["journey_name"] = str(r.get("display_name", ""))
				merged["journey_xp"] = int(r.get("xp", 0))
				merged["journey_rank"] = str(r.get("rank_name", ""))
				merged["badges"] = load(ModPaths.path("JourneyLooks.gd"))._badges(r.get("badges"))
				merged["journey_finish"] = str(r.get("finish", "")) if r.get("finish") != null else ""
				rows[id] = merged
		emit_signal("changed")

# The game's own profile (same request as opening a profile in the game).
func load_native(user_id):
	user_id = str(user_id)
	if user_id.length() != 36 or (native.has(user_id) and OS.get_unix_time() - int(native[user_id].at) < NATIVE_KEEP) or _native_queue.has(user_id):
		return
	_native_queue.append(user_id)
	if not _native_busy:
		_next_native()

func _next_native():
	var moonlight = get_node_or_null("/root/Moonlight")
	if _native_queue.empty() or moonlight == null or moonlight.get("session") == null:
		_native_busy = false
		return
	_native_busy = true
	var user_id = _native_queue.pop_front()
	var state = moonlight.call_rpc("query_player_profile", {"user_id": user_id}, false)
	var response = yield(state, "completed") if state is GDScriptFunctionState else state
	if response is Dictionary and not response.has("error"):
		_looks.erase(user_id)
		native[user_id] = {"stats": response.get("stats", {}), "skin": response.get("skin", {}), "name": str(response.get("display_name", "")),
			"level": int(response.get("level", 1)), "awards": response.get("awards", {}), "at": OS.get_unix_time()}
		emit_signal("changed")
	_next_native()

# Body colours and hat for a player's mini Goober, once their profile is loaded.
var _looks = {}
func look_for(user_id):
	user_id = str(user_id)
	if _looks.has(user_id):
		return _looks[user_id]
	var skin = native.get(user_id, {}).get("skin", {})
	if not native.has(user_id) or not skin is Dictionary:
		return null
	var cosmetics = load("res://project_specific/data/CosmeticsCollection.gd")
	var color = cosmetics.lookup_cosmetic_id(str(skin.get("color", "color_default"))) if cosmetics != null else {}
	var gradient_name = str(color.get("color", "blue")) if color is Dictionary else "blue"
	var path = "res://project_specific/gfx/player_gradients/%s.tres" % gradient_name
	var gradient = load(path) if ResourceLoader.exists(path) else null
	if not gradient is Gradient or gradient.colors.size() == 0:
		gradient = load("res://project_specific/gfx/player_gradients/blue.tres") if ResourceLoader.exists("res://project_specific/gfx/player_gradients/blue.tres") else null
	var result = {"body": Color("7cc4ff"), "dark": Color("3a6ec2"), "hat": "", "hat_color": Color.white}
	if gradient is Gradient and gradient.colors.size() > 0:
		result.body = gradient.colors[gradient.colors.size() - 1]
		result.dark = gradient.colors[0]
	var hat = cosmetics.lookup_cosmetic_id(str(skin.get("hat", ""))) if cosmetics != null and not str(skin.get("hat", "")).empty() else {}
	if hat is Dictionary and hat.has("spine"):
		var shape = load(ModPaths.path("HubMiniGoober.gd")).hat_for(hat.spine)
		result.hat = shape[0]
		result.hat_color = shape[1]
	_looks[user_id] = result
	return result

func stat(user_id, key) -> int:
	var stats = native.get(str(user_id), {}).get("stats", {})
	return int(stats.get(key, 0)) if stats is Dictionary else 0

# Native stat keys live on the game's WPGame script (Stat_GamesWon, ...).
static func stat_key(name) -> String:
	var game_script = load("res://scripts/WPGame.gd")
	var value = game_script.get(name) if game_script != null else null
	if value == null and game_script != null:
		value = game_script.get_script_constant_map().get(name)
	return str(value) if value != null else name
