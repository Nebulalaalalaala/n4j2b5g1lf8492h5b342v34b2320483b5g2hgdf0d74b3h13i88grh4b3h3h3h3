extends Reference

# Calculate XP: one-time Journey XP for what an account played before
# Goobplayability, from its GooberDash stats (GamesPlayed, GamesWon, Deaths).
# Rounds this client already recorded are subtracted so nothing counts twice.
# Time trials can't be derived from these stats and give nothing here.
const WIN_XP = 1000      # estimates count for less than XP earned live
const LOSS_XP = 250
const DEATH_XP = 5
const DEATHS_PER_GAME = 10
const ROUNDS_PER_WIN = 4.0
const ROUNDS_PER_LOSS = 1.7
const MAP_XP = 200       # same as a real discovery; awarded under the real discovery id
const MIN_CHANCE = 0.2
const DAY = 86400
const MAX_ENTRY = 1000000
# Bumped when the rates change; older calculations can be recalculated once.
const VERSION = 3

# Own GooberDash stats, or {} when they can't be loaded. Also when the account was
# created and when it last played (profile metadata), for the map estimate.
func fetch(moonlight, owner: String):
	if moonlight == null or owner.empty():
		return {}
	var response = yield(moonlight.call_rpc("query_player_profile", {"user_id": owner}, false), "completed")
	if not response is Dictionary or response.has("error") or not response.get("stats") is Dictionary:
		return {}
	var out = {}
	for key in ["GamesPlayed", "GamesWon", "Deaths", "Winstreak", "CurrentWinstreak"]:
		out[key] = int(max(0, int(response.stats.get(key, 0))))
	var metadata = response.get("metadata", {})
	out.last_game = int(metadata.get("lastgametime", 0)) if metadata is Dictionary else 0
	out.created = 0
	if moonlight.get("storage") != null:
		out.created = unix(moonlight.storage.storage_get("account.user.create_time", 0))
	return out

# Unix seconds from {seconds: n}, an ISO "2026-08-04T12:00:00Z" string or a number; 0 if unknown.
static func unix(value) -> int:
	if value is Dictionary:
		return int(value.get("seconds", 0))
	if typeof(value) in [TYPE_INT, TYPE_REAL]:
		return int(value)
	var text = str(value)
	if text.length() < 10 or text.substr(4, 1) != "-":
		return 0
	var time = text.substr(11, 8).split(":") if text.length() >= 19 else ["0", "0", "0"]
	return OS.get_unix_time_from_datetime({"year": int(text.substr(0, 4)), "month": int(text.substr(5, 2)), "day": int(text.substr(8, 2)),
		"hour": int(time[0]), "minute": int(time[1]), "second": int(time[2])})

# records: this account's recorded rounds. maps: known public maps ({id, certified_at}).
func plan(stats: Dictionary, records: Array, maps: Array) -> Dictionary:
	var seen_wins = 0
	var seen_losses = 0
	var seen_deaths = 0
	var seen_maps = {}
	for r in records:
		if str(r.get("mode", "")) != "match_round" or r.get("custom", false):
			continue
		seen_maps[str(r.get("map_id", ""))] = true
		seen_deaths += int(r.get("deaths", 0))
		if r.get("win", false):
			seen_wins += 1
		elif str(r.get("result", "")) != "finish":
			seen_losses += 1
	var games = int(stats.get("GamesPlayed", 0))
	var wins = int(max(0, int(stats.get("GamesWon", 0)) - seen_wins))
	var losses = int(max(0, games - int(stats.get("GamesWon", 0)) - seen_losses))
	var deaths = int(min(max(0, int(stats.get("Deaths", 0)) - seen_deaths), (wins + losses) * DEATHS_PER_GAME))
	var explored = likely_maps(stats, maps, seen_maps)
	var lines = [
		{"key": "wins", "label": "Wins", "detail": "%d × %d XP" % [wins, WIN_XP], "category": "win", "xp": wins * WIN_XP},
		{"key": "games", "label": "Other games", "detail": "%d × %d XP" % [losses, LOSS_XP], "category": "placement", "xp": losses * LOSS_XP},
		{"key": "deaths", "label": "Deaths", "detail": "%d × %d XP" % [deaths, DEATH_XP], "category": "activity", "xp": deaths * DEATH_XP},
	]
	var total = 0
	for line in lines:
		total += int(line.xp)
	var map_line = {"key": "maps", "label": "Maps you've likely played", "detail": "%d maps × %d XP" % [explored.size(), MAP_XP], "category": "exploration", "xp": explored.size() * MAP_XP}
	lines.append(map_line)
	total += int(map_line.xp)
	return {"lines": lines, "total": total, "wins": wins, "maps": explored.size(), "map_ids": explored}

# Maps this account has most likely played, oldest first. Games are spread evenly
# between account creation and the last game; a map can only have come up after it
# was certified, picked at random from the maps certified by then.
func likely_maps(stats: Dictionary, maps: Array, seen_maps: Dictionary) -> Array:
	var games = int(stats.get("GamesPlayed", 0))
	if games <= 0 or maps.empty():
		return []
	var wins = int(stats.get("GamesWon", 0))
	var rounds = wins * ROUNDS_PER_WIN + max(0, games - wins) * ROUNDS_PER_LOSS
	var end = int(stats.get("last_game", 0))
	if end <= 0:
		end = OS.get_unix_time()
	var start = int(stats.get("created", 0))
	if start <= 0 or start >= end:
		start = end - int(games * DAY / 5)   # unknown: about five games a day
	var span = float(max(DAY, end - start))
	var dates = []
	for map in maps:
		dates.append(int(map.get("certified_at", 0)))
	dates.sort()
	var chances = []
	var expected = 0.0
	for map in maps:
		var id = str(map.get("id", ""))
		if id.empty() or seen_maps.has(id):
			continue
		var from = max(start, int(map.get("certified_at", 0)))
		if from >= end:
			continue
		var share = rounds * (end - from) / span
		var pool = max(1, dates.bsearch(int((from + end) / 2), false))
		var chance = 1.0 - pow(1.0 - 1.0 / pool, share)
		expected += chance
		chances.append([chance, int(map.get("certified_at", 0)), id])
	chances.sort_custom(self, "_likelier")
	var out = []
	for entry in chances:
		if out.size() >= int(round(expected)) or entry[0] < MIN_CHANCE:
			break
		out.append(entry[2])
	return out

func _likelier(a, b) -> bool:
	return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1])

# Ledger entries for a plan (split so no entry passes the ledger's per-entry cap).
# Map discoveries use the real discovery ids, so playing the map later doesn't award it twice.
func entries(owner: String, result: Dictionary, now: int) -> Array:
	var out = []
	for line in result.lines:
		if line.key == "maps":
			continue
		var left = int(line.xp)
		var part = 1
		while left > 0:
			var amount = int(min(left, MAX_ENTRY))
			out.append({"id": "backfill:%s:%s:%d" % [owner, line.key, part], "player_id": owner, "category": line.category,
				"reason": "Calculated XP · " + str(line.label), "related_id": "backfill:" + str(line.key),
				"source": "server_event", "amount": amount, "timestamp": now})
			left -= amount
			part += 1
	return out

func map_entries(owner: String, result: Dictionary, now: int) -> Array:
	var out = []
	for id in result.get("map_ids", []):
		out.append({"id": "map:%s:discover:%s" % [id, owner], "player_id": owner, "category": "exploration",
			"reason": "Calculated XP · Map discovered", "related_id": str(id), "source": "server_event", "amount": MAP_XP, "timestamp": now})
	return out
