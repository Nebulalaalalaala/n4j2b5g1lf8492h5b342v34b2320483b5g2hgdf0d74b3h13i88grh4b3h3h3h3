extends Reference

# Calculate XP: one-time Journey XP for what an account played before
# Goobplayability, from its GooberDash stats (GamesPlayed, GamesWon, Deaths).
# Rounds this client already recorded are subtracted so nothing counts twice.
# Time trials can't be derived from these stats and give nothing here.
const WIN_XP = 3000      # match win + typical rounds, finishes and podiums of a winning run
const LOSS_XP = 600      # typical rounds and finishes of a match that wasn't won
const DEATH_XP = 20
const DEATHS_PER_GAME = 10
const ROUNDS_PER_WIN = 4.0
const ROUNDS_PER_LOSS = 1.7
const MAP_XP = 100       # half of a discovery: which maps were played isn't known
const MAX_ENTRY = 1000000

# Own GooberDash stats, or {} when they can't be loaded.
func fetch(moonlight, owner: String):
	if moonlight == null or owner.empty():
		return {}
	var response = yield(moonlight.call_rpc("query_player_profile", {"user_id": owner}, false), "completed")
	if not response is Dictionary or response.has("error") or not response.get("stats") is Dictionary:
		return {}
	var out = {}
	for key in ["GamesPlayed", "GamesWon", "Deaths"]:
		out[key] = int(max(0, int(response.stats.get(key, 0))))
	return out

# records: this account's recorded rounds. map_count: known public maps.
func plan(stats: Dictionary, records: Array, map_count: int) -> Dictionary:
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
	# Expected different maps after this many random rounds from the known pool.
	var rounds = wins * ROUNDS_PER_WIN + losses * ROUNDS_PER_LOSS
	var pool = max(1, map_count)
	var likely = int(round(pool * (1.0 - pow(1.0 - 1.0 / pool, rounds))))
	var maps = int(max(0, likely - seen_maps.size()))
	var lines = [
		{"key": "wins", "label": "Wins", "detail": "%d × %d XP" % [wins, WIN_XP], "category": "win", "xp": wins * WIN_XP},
		{"key": "games", "label": "Other games", "detail": "%d × %d XP" % [losses, LOSS_XP], "category": "placement", "xp": losses * LOSS_XP},
		{"key": "deaths", "label": "Deaths", "detail": "%d × %d XP" % [deaths, DEATH_XP], "category": "activity", "xp": deaths * DEATH_XP},
		{"key": "maps", "label": "Maps you've likely played", "detail": "about %d × %d XP" % [maps, MAP_XP], "category": "exploration", "xp": maps * MAP_XP},
	]
	var total = 0
	for line in lines:
		total += int(line.xp)
	return {"lines": lines, "total": total, "wins": wins, "maps": maps}

# Ledger entries for a plan (split so no entry passes the ledger's per-entry cap).
func entries(owner: String, result: Dictionary, now: int) -> Array:
	var out = []
	for line in result.lines:
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
