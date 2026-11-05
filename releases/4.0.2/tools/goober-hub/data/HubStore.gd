extends Reference
# Goober Hub's local record for one account: players you met (Encounters),
# season notes for Passport and what the feed has already announced.
const VERSION = 1
const DIRECTORY = "user://goobplayability/hub"
const KEEP_MATCHES = 400
var account = ""
var path = ""
var data = {}

func configure(owner):
	account = str(owner)
	path = DIRECTORY.plus_file(account.sha256_text().substr(0, 24) + ".json") if not account.empty() else ""
	data = _blank()
	if path.empty():
		return
	var file = File.new()
	if file.open(path, File.READ) == OK:
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and parsed.result is Dictionary and int(parsed.result.get("version", 0)) == VERSION:
			for k in data:
				if parsed.result.has(k) and typeof(parsed.result[k]) == typeof(data[k]):
					data[k] = parsed.result[k]

func _blank():
	return {"version": VERSION, "since": OS.get_unix_time(), "players": {}, "seasons": {}, "matches": [], "posted": {}, "muted": {}, "profile": {"bio": "", "favorites": []}}

func save():
	if path.empty():
		return
	Directory.new().make_dir_recursive(DIRECTORY)
	var file = File.new()
	if file.open(path + ".tmp", File.WRITE) != OK:
		return
	file.store_string(JSON.print(data))
	file.close()
	Directory.new().rename(path + ".tmp", path)

static func season_key(timestamp) -> String:
	var d = OS.get_datetime_from_unix_time(int(timestamp))
	var m = int(d.month)
	var year = int(d.year) + (1 if m == 12 else 0)
	var name = "winter" if m in [12, 1, 2] else "spring" if m <= 5 else "summer" if m <= 8 else "autumn"
	return "%d-%d-%s" % [year, ["winter", "spring", "summer", "autumn"].find(name), name]

static func season_title(key) -> String:
	var parts = str(key).split("-")
	return "%s %s" % [parts[2].to_upper(), parts[0]] if parts.size() == 3 else str(key)

func season(key):
	if not data.seasons.has(key):
		data.seasons[key] = {"with": {}, "peak_xp": 0, "peak_rank": ""}
	return data.seasons[key]

# One finished match with other players (uuid -> name), and who won it.
func add_match(at, map_name, others: Dictionary, winner):
	var s = season(season_key(at))
	for id in others:
		var p = data.players.get(id, {"name": "", "first": at, "last": at, "matches": 0, "you_won": 0, "they_won": 0})
		p.name = str(others[id]).substr(0, 40)
		p.last = at
		p.matches = int(p.matches) + 1
		if winner == account:
			p.you_won = int(p.you_won) + 1
		elif winner == id:
			p.they_won = int(p.they_won) + 1
		data.players[id] = p
		s.with[id] = int(s.with.get(id, 0)) + 1
	data.matches.append({"at": at, "map": str(map_name), "with": others.keys(), "winner": str(winner)})
	if data.matches.size() > KEEP_MATCHES:
		data.matches = data.matches.slice(data.matches.size() - KEEP_MATCHES, data.matches.size() - 1)
	save()

func note_rank(xp, rank_name):
	var s = season(season_key(OS.get_unix_time()))
	if int(xp) > int(s.peak_xp):
		s.peak_xp = int(xp)
		s.peak_rank = str(rank_name)
		save()

func encounters() -> Array:
	var list = []
	for id in data.players:
		var p = data.players[id].duplicate()
		p.id = id
		list.append(p)
	list.sort_custom(self, "_more_matches")
	return list

func _more_matches(a, b):
	return int(a.matches) > int(b.matches) if int(a.matches) != int(b.matches) else int(a.last) > int(b.last)

func together(id) -> Array:
	var list = []
	for m in data.matches:
		if m.with.has(id):
			list.append(m)
	list.invert()
	return list
