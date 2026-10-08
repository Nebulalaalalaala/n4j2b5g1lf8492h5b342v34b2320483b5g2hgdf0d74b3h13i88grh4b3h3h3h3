extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Local observations only. Never merges with the game's authoritative profile.
const VERSION = 1
const LIMIT = 2000
const MAX_BYTES = 4194304
var account_id := ""
var path := ""
var records := []
var session := []
var since := 0
var writable := true
var last_error := ""

func configure(owner_id: String, directory: String = ModPaths.PROFILE_HISTORY_DIR) -> bool:
	account_id = owner_id
	path = directory.plus_file(owner_id.sha256_text() + ".json")
	records = []
	session = []
	since = int(OS.get_unix_time())
	writable = not owner_id.empty()
	last_error = ""
	if not writable:
		last_error = "Sign in before recording profile history."
		return false
	if not File.new().file_exists(path):
		if not File.new().file_exists(path + ".bak"):
			return true
	var data = _read(path)
	if data.empty():
		data = _read(path + ".bak")
		if not data.empty():
			last_error = "Recovered local history from its backup."
	if data.empty():
		writable = false
		last_error = "Local history could not be read. Files preserved; import or reset explicitly to recover."
		return false
	records = data.records
	since = data.since
	return true

func _read(source: String) -> Dictionary:
	var file := File.new()
	if file.open(source, File.READ) != OK:
		return {}
	if file.get_len() > MAX_BYTES:
		file.close()
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK:
		return {}
	return validate_document(parsed.result)

func _number(value, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and float(value) >= minimum and float(value) <= maximum

func validate_record(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	for key in ["id", "map_id", "map_name", "mode", "result"]:
		if typeof(value.get(key)) != TYPE_STRING or value[key].empty() or value[key].length() > 256:
			return {}
	if not value.result in ["finish", "dnf", "unknown"]:
		return {}
	for key in ["date", "play_seconds", "deaths"]:
		if not _number(value.get(key), 0, 10000000000.0 if key == "date" else 1000000.0):
			return {}
	if not _number(value.get("placement", 0), 0, 10000) or not _number(value.get("players", 0), 0, 10000):
		return {}
	var finish_time = value.get("finish_time", -1)
	if not _number(finish_time, -1, 1000000) or (value.result == "finish" and finish_time < 0):
		return {}
	if typeof(value.get("win", false)) != TYPE_BOOL or typeof(value.get("custom", false)) != TYPE_BOOL:
		return {}
	var clean := {}
	for key in ["id", "map_id", "map_name", "mode", "result", "date", "play_seconds", "deaths"]:
		clean[key] = value[key]
	clean["placement"] = int(value.get("placement", 0))
	clean["players"] = int(value.get("players", 0))
	clean["finish_time"] = float(finish_time)
	clean["win"] = bool(value.get("win", false))
	# Custom lobbies; older records have no flag and count as public.
	clean["custom"] = bool(value.get("custom", false))
	return clean

func validate_document(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.get("version") != VERSION or value.get("account_id") != account_id:
		return {}
	if not _number(value.get("since"), 0, 10000000000.0) or typeof(value.get("records")) != TYPE_ARRAY or value.records.size() > LIMIT:
		return {}
	var result := []
	var seen := {}
	for entry in value.records:
		var clean := validate_record(entry)
		if clean.empty() or seen.has(clean.id):
			return {}
		seen[clean.id] = true
		result.append(clean)
	return {"version": VERSION, "account_id": account_id, "since": int(value.since), "records": result}

func document() -> Dictionary:
	return {"version": VERSION, "account_id": account_id, "since": since, "records": records.duplicate(true)}

func append(value: Dictionary) -> bool:
	if not writable:
		return false
	var clean := validate_record(value)
	if clean.empty():
		last_error = "Invalid observation; nothing recorded."
		return false
	for entry in records:
		if entry.id == clean.id:
			return false
	var previous := records.duplicate(true)
	records.append(clean)
	while records.size() > LIMIT:
		records.pop_front()
	if not save():
		records = previous
		return false
	session.append(clean)
	while session.size() > LIMIT:
		session.pop_front()
	return true

func save() -> bool:
	if not writable:
		return false
	var directory := Directory.new()
	if directory.make_dir_recursive(path.get_base_dir()) != OK:
		last_error = "Could not create the profile data directory."
		return false
	var temporary := path + ".tmp"
	var file := File.new()
	if file.open(temporary, File.WRITE) != OK:
		last_error = "Could not write local history."
		return false
	file.store_string(JSON.print(document()))
	file.close()
	if _read(temporary).empty():
		last_error = "Written history failed validation; current file preserved."
		return false
	# Only rotate a valid primary; never overwrite a good recovery with corruption.
	if directory.file_exists(path) and not _read(path).empty():
		if directory.file_exists(path + ".bak") and directory.remove(path + ".bak") != OK:
			return false
		if directory.rename(path, path + ".bak") != OK:
			return false
	elif directory.file_exists(path):
		last_error = "Primary file is corrupt; explicit recovery required."
		return false
	if directory.rename(temporary, path) != OK:
		last_error = "Could not finalize local history; backup preserved."
		return false
	return true

func statistics(source: Array) -> Dictionary:
	var stats := {"observed": source.size(), "finishes": 0, "wins": 0, "dnfs": 0, "unknown": 0, "deaths": 0, "play_seconds": 0.0, "placed": 0, "placement_sum": 0, "maps": {}}
	for entry in source:
		stats.finishes += int(entry.result == "finish")
		stats.dnfs += int(entry.result == "dnf")
		stats.unknown += int(entry.result == "unknown")
		stats.wins += int(entry.win)
		stats.deaths += int(entry.deaths)
		stats.play_seconds += entry.play_seconds
		if entry.placement > 0:
			stats.placed += 1
			stats.placement_sum += entry.placement
		var key: String = entry.mode + ":" + entry.map_id
		if not stats.maps.has(key):
			stats.maps[key] = {"name": entry.map_name, "mode": entry.mode, "plays": 0, "completions": 0, "dnfs": 0, "wins": 0, "best": -1.0, "total_time": 0.0, "deaths": 0, "last_played": 0}
		var map: Dictionary = stats.maps[key]
		map.plays += 1
		map.dnfs += int(entry.result == "dnf")
		map.wins += int(entry.win)
		map.deaths += int(entry.deaths)
		map.last_played = max(map.last_played, entry.date)
		if entry.result == "finish":
			map.completions += 1
			map.total_time += entry.finish_time
			if map.best < 0 or entry.finish_time < map.best:
				map.best = entry.finish_time
	return stats

func progression(source: Array) -> Dictionary:
	var ordered := source.duplicate(true)
	ordered.sort_custom(self, "_earlier")
	var maps := {}
	var events := {}
	for entry in ordered:
		if entry.result != "finish":
			continue
		var key: String = entry.mode + ":" + entry.map_id
		if not maps.has(key):
			maps[key] = {"best": -1.0, "steps": []}
		var previous: float = maps[key].best
		if previous >= 0 and entry.finish_time >= previous - 0.000001:
			continue
		var event := {"id": entry.id, "date": entry.date, "time": entry.finish_time, "improvement": previous - entry.finish_time if previous >= 0 else 0.0, "baseline": previous < 0}
		maps[key].best = entry.finish_time
		maps[key].steps.append(event)
		events[entry.id] = event
	return {"maps": maps, "events": events}

func highlights(source: Array) -> Dictionary:
	var maps: Dictionary = statistics(source).maps
	var result := {"most_played": "", "strongest": "", "nemesis": ""}
	var most := 0
	var best_rate := -1.0
	var worst_rate := 2.0
	var keys := maps.keys()
	keys.sort()
	for key in keys:
		var map: Dictionary = maps[key]
		if map.plays > most:
			most = map.plays
			result.most_played = key
		var known: int = map.completions + map.dnfs
		if known < 5:
			continue
		var rate := float(map.completions) / known
		if map.completions > 0 and rate > best_rate:
			best_rate = rate
			result.strongest = key
		if map.dnfs > 0 and rate < worst_rate:
			worst_rate = rate
			result.nemesis = key
	return result

func export_text() -> String:
	return JSON.print(document(), "  ")

func import_text(text: String) -> bool:
	if not writable or text.length() > MAX_BYTES:
		last_error = "History is read-only or the import is too large."
		return false
	var parsed = JSON.parse(text)
	if parsed.error != OK:
		last_error = "Invalid JSON; nothing imported."
		return false
	var incoming := validate_document(parsed.result)
	if incoming.empty():
		last_error = "Wrong account, unsupported version, or invalid records."
		return false
	var combined := records.duplicate(true)
	var seen := {}
	for entry in combined:
		seen[entry.id] = entry
	for entry in incoming.records:
		if seen.has(entry.id):
			for key in entry:
				if seen[entry.id].get(key) != entry[key]:
					last_error = "Conflicting event IDs; nothing imported."
					return false
			continue
		combined.append(entry)
	combined.sort_custom(self, "_earlier")
	while combined.size() > LIMIT:
		combined.pop_front()
	var previous := records
	var old_since := since
	records = combined
	since = min(since, incoming.since)
	if not save():
		records = previous
		since = old_since
		return false
	return true

func _earlier(a: Dictionary, b: Dictionary) -> bool:
	return a.date < b.date if a.date != b.date else a.id < b.id

func reset() -> bool:
	if account_id.empty():
		return false
	# Preserve an unreadable primary for manual recovery. Never discard it merely
	# because the user has chosen to start a fresh tracked history.
	var directory := Directory.new()
	if directory.file_exists(path) and _read(path).empty():
		if directory.file_exists(path + ".rejected"):
			last_error = "A previous corrupt file is already preserved; export or move it before resetting again."
			return false
		if directory.rename(path, path + ".rejected") != OK:
			return false
	var old_records := records
	var old_since := since
	var old_writable := writable
	records = []
	since = int(OS.get_unix_time())
	writable = true
	if not save():
		records = old_records
		since = old_since
		writable = old_writable
		return false
	session = []
	return true
