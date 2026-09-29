extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Certified levels, read with the same query the Level Explorer's CERTIFIED tab
# uses (levels_query_curated). Read-only, at most once every REFRESH seconds.
# Cached in journey/certified-levels.json so the Maps page has a card for every
# certified level (lobby levels excluded). Also writes journey/thumbnail-report.json: certified levels
# without a map_<name>.png, and thumbnails that match no certified level.
const REFRESH = 21600
# 2: lobby levels (game_mode "Lobby", where players wait before a match) are left out.
const FORMAT = 2
const DIRECTORY = "user://goobplayability/journey"
var busy = false
var checked = 0.0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS

func _process(delta):
	checked += delta
	if checked < 10.0 or busy:
		return
	checked = 0.0
	var moonlight = get_node_or_null("/root/Moonlight")
	var cache = load_cache()
	if moonlight == null or moonlight.session == null or (int(cache.get("format",0)) == FORMAT and OS.get_unix_time()-int(cache.get("fetched_at",0)) < REFRESH):
		return
	busy = true
	_fetch(moonlight)

func _fetch(moonlight):
	var response = yield(moonlight.call_rpc("levels_query_curated",{},false,true),"completed")
	busy = false
	if not response is Dictionary or response.has("error") or not response.get("levels") is Array:
		checked = -290.0
		return
	var levels = []
	for level in response.levels:
		if level is Dictionary and not str(level.get("id","")).empty():
			var mode = str(level.get("game_mode",""))
			if mode.to_lower() == "lobby":
				continue
			if mode.to_lower().find("elim") < 0 and int(level.get("player_count",0)) > 0:
				mode = "%dP" % int(level.player_count)
			levels.append({"id":str(level.id),"name":str(level.get("name","")).strip_edges(),"author":str(level.get("author_name","")),"mode":mode})
	if levels.empty():
		return
	_write("certified-levels.json",{"format":FORMAT,"fetched_at":OS.get_unix_time(),"levels":levels})
	_report(levels)

static func load_cache() -> Dictionary:
	var file = File.new()
	if file.open(DIRECTORY.plus_file("certified-levels.json"),File.READ) != OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	var data = parsed.result if parsed.error == OK and parsed.result is Dictionary else {}
	# Older caches still list lobbies; hide them by name until the refetch.
	if int(data.get("format",0)) != FORMAT and data.get("levels") is Array:
		var kept = []
		for level in data.levels:
			if level is Dictionary and str(level.get("name","")).to_lower().find("lobby") < 0:
				kept.append(level)
		data.levels = kept
	return data

func _report(levels):
	var assets = ModPaths.JOURNEY_ASSETS_DIR
	var pages = load(ModPaths.path("JourneyPages.gd"))
	var keys = {}
	var missing = []
	for level in levels:
		var key = pages.map_key(level.name)
		keys[key] = true
		if not File.new().file_exists(assets.plus_file(key+".png")):
			missing.append(level.name)
	var unused = []
	var dir = Directory.new()
	if dir.open(assets) == OK:
		dir.list_dir_begin(true,true)
		var name = dir.get_next()
		while name != "":
			if name.begins_with("map_") and name.ends_with(".png") and not keys.has(name.get_basename()):
				unused.append(name)
			name = dir.get_next()
	missing.sort()
	unused.sort()
	_write("thumbnail-report.json",{"certified":levels.size(),"missing_thumbnail":missing,"unmatched_thumbnail":unused})

func _write(name,data):
	Directory.new().make_dir_recursive(DIRECTORY)
	var file = File.new()
	if file.open(DIRECTORY.plus_file(name),File.WRITE) == OK:
		file.store_string(JSON.print(data,"\t"))
		file.close()
