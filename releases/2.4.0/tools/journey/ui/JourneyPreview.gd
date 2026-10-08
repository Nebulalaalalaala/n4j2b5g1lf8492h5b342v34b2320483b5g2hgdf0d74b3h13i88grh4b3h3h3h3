extends Reference

# SAMPLE DATA for evaluating Journey's layouts. Never persisted, never mixed
# with real progress: JourneyScreen only uses it while Debug Mode's
# "Design preview" toggle is on, and shows a banner the whole time.

func apply(m: Dictionary, definitions) -> Dictionary:
	var now = OS.get_unix_time()
	var day = 86400
	m = m.duplicate(true)
	m.preview = true
	m.signed_in = true
	m.writable = true
	m.error = ""
	m.xp = 70450
	m.rank = definitions.rank_at(m.xp)
	m.next = definitions.rank_at(int(m.rank.next_xp))
	m.roadmap = definitions.roadmap(m.xp)
	for candidate in m.roadmap:
		if str(candidate.league) != str(m.rank.league) and int(candidate.xp) > int(m.rank.xp):
			m.next_league = candidate
			break
	m.promotions = {}
	var t = now - 26 * day
	for rank in m.roadmap:
		if int(rank.xp) > 0 and int(rank.xp) <= m.xp:
			m.promotions[int(rank.id)] = t
			t += int(2.4 * day)
	m.today_xp = 3850
	m.today_categories = {"win": 1300, "placement": 1500, "activity": 1000, "exploration": 50}
	m.days = []
	var series = [2150, 0, 4300, 1850, 5200, 2700, 3850]
	for i in 7:
		m.days.append({"start": now - (6 - i) * day, "xp": series[i]})
	m.transactions = [
		_tx("win", "Won the overall public match", 800, now - 1200, "Sunny Slopes · 32-player"),
		_tx("win", "First overall victory of the day", 500, now - 1200, "Daily bonus"),
		_tx("placement", "Finished first in a race round", 100, now - 1500, "Pyramid Dash"),
		_tx("placement", "Finished an individual race", 500, now - 1500, "Pyramid Dash"),
		_tx("placement", "Legitimate participation", 200, now - 1900, "32-player race"),
		_tx("activity", "1 active hour reached", 750, now - 2400, "Daily activity"),
		_tx("activity", "30 active minutes reached", 250, now - 5200, "Daily activity"),
		_tx("exploration", "Discovered a new map", 200, now - 6100, "Cloud Castle"),
		_tx("challenge", "Daily quest: Qualify three times", 800, now - day - 900, "Daily quest"),
		_tx("record", "New verified personal best", 300, now - 2 * day, "Frosty Heights"),
	]
	m.activity = {"today_seconds": 5400, "open_seconds": 7900, "lifetime_seconds": 212000, "inactive": false,
		"days": [2600, 0, 9100, 3300, 11800, 4700, 5400]}
	m.quests = {
		"rerolls": 2, "reset_in": 26100, "weekly_reset_in": 3 * day + 18000,
		"daily": [
			_quest("Public Matches", "Qualify in three public races", "Reach the qualifying cut in any race size.", 2, 3, 800, "medium", "podium"),
			_quest("Speedrunning", "Beat a personal best", "Improve any verified time on an eligible map.", 0, 1, 1200, "hard", "stopwatch"),
			_quest("Level Creation", "Spend 10 minutes building", "Meaningful editor work counts; idle time doesn't.", 10, 10, 600, "easy", "hammer", true),
		],
		"choices": [
			_quest("Optional Challenges", "Win a knockout final", "Be the last survivor of a four-player knockout.", 0, 1, 1500, "hard", "crown"),
			_quest("Public Matches", "Finish five races", "Any public race size counts.", 0, 5, 500, "easy", "flag"),
		],
		"weekly": [
			_quest("Public Matches", "Win on 3 different maps", "Overall wins on distinct eligible maps.", 1, 3, 4000, "hard", "crown"),
			_quest("Public Matches", "Qualify in every race size", "32-, 16- and 8-player races.", 2, 3, 3000, "medium", "podium"),
			_quest("Speedrunning", "Set 5 personal bests", "Verified PBs on eligible official maps.", 5, 5, 3500, "medium", "stopwatch", true),
		],
	}
	m.achievements = {
		"featured": ["crown", "podium", "exploration"],
		"collections": [
			_collection("exploration", "Map Explorer", "Discover eligible public maps.", 3, 38, [5, 15, 30, 60, 100, 150], "exploration"),
			_collection("crown", "Crown Collector", "Win public matches overall.", 2, 31, [5, 25, 75, 200, 500, 1000], "crown"),
			_collection("podium", "Placement Fanatic", "Exceptional results for each match size.", 3, 88, [10, 30, 75, 150, 300, 600], "podium", true),
			_collection("clock", "Against the Clock", "Verified personal bests and world records.", 1, 7, [3, 10, 25, 50, 100, 200], "clock"),
			_collection("builder", "Goob Builder", "Publish eligible levels.", 1, 2, [1, 3, 7, 15, 30, 50], "builder"),
			_collection("conqueror", "Map Conqueror", "Finish first on eligible public maps.", 0, 3, [5, 15, 30, 60, 100, 150], "conqueror"),
		],
	}
	m.milestones = [
		{"name": "First public match", "detail": "Completed your first public match.", "date": now - 26 * day, "done": true},
		{"name": "First overall victory", "detail": "Won a public match overall.", "date": now - 24 * day, "done": true},
		{"name": "First Clean Sweep", "detail": "Win every race round and the match.", "date": 0, "done": false},
		{"name": "50 verified active hours", "detail": "Lifetime verified active time.", "date": 0, "done": false, "progress": 0.59},
	]
	m.cosmetics = {
		"themes": [
			{"key": "classic", "name": "Classic Sky", "requirement": "Always available", "state": "equipped",
				"colors": {"bg": "0092ff", "surface": "062f5e", "accent": "ffc40f", "text": "ffffff", "alt": "ff3896"}},
			{"key": "sunset", "name": "Sunset Rally", "requirement": "Reach Gold I", "state": "unlocked",
				"colors": {"bg": "ff7a59", "surface": "4a1631", "accent": "ffd166", "text": "fff4e8", "alt": "ff4f8b"}},
			{"key": "deepsea", "name": "Deep Sea", "requirement": "Reach Sapphire I", "state": "locked",
				"colors": {"bg": "0a6f8f", "surface": "03263a", "accent": "5ee0c8", "text": "e9fbff", "alt": "7fb4ff"}},
			{"key": "royal", "name": "Royal Court", "requirement": "Reach King League 1", "state": "locked",
				"colors": {"bg": "4b2a8f", "surface": "1b0f3d", "accent": "ffc629", "text": "fff6de", "alt": "ff7ed3"}},
		],
		"finishes": [
			{"key": "classic", "name": "Classic Finish", "requirement": "Always available", "state": "equipped", "icon": "flag"},
			{"key": "confetti", "name": "Confetti Pop", "requirement": "Reach Silver I", "state": "unlocked", "icon": "sparkle"},
			{"key": "crown", "name": "Crowned", "requirement": "Crown Collector · Ruby", "state": "locked", "icon": "crown"},
		],
	}
	m.pins = [
		{"kind": "achievement", "name": "Crown Collector · Ruby", "next": "Win 44 more public matches", "value": 31, "target": 75, "icon": "crown", "color": "ffc40f"},
		{"kind": "map", "name": "Frosty Heights", "next": "Set a verified world record", "value": 4, "target": 5, "icon": "flag", "color": "5ee0c8"},
		{"kind": "rank", "name": "Deep Sea theme", "next": "Reach Sapphire I", "value": 70450, "target": 256500, "icon": "palette", "color": "5ee0c8"},
	]
	m.inbox = [
		{"id": "a", "title": "Placement Fanatic · Sapphire", "detail": "88 exceptional results", "kind": "achievement", "state": "claimable", "xp": 10000, "time": now - 900},
		{"id": "b", "title": "Daily quest complete", "detail": "Spend 10 minutes building", "kind": "quest", "state": "claimable", "xp": 600, "time": now - 3000},
		{"id": "c", "title": "Promoted to Silver I", "detail": "New league reached", "kind": "rank", "state": "unread", "xp": 0, "time": now - 7000},
		{"id": "d", "title": "New map discovered", "detail": "Cloud Castle", "kind": "map", "state": "read", "xp": 200, "time": now - day},
	]
	m.sessions = [
		{"id": "s1", "start": now - 5400, "active": 4800, "xp": 3850, "matches": 6, "wins": 1, "firsts": 3, "maps": 1, "pbs": 1, "quests": 1,
			"categories": {"win": 1300, "placement": 1500, "activity": 1000, "exploration": 50}},
		{"id": "s2", "start": now - day - 7200, "active": 3600, "xp": 2700, "matches": 5, "wins": 0, "firsts": 2, "maps": 0, "pbs": 0, "quests": 1,
			"categories": {"placement": 1100, "activity": 1000, "challenge": 600}},
		{"id": "s3", "start": now - 2 * day - 3600, "active": 7200, "xp": 5200, "matches": 9, "wins": 2, "firsts": 5, "maps": 2, "pbs": 1, "quests": 2,
			"categories": {"win": 1600, "placement": 1800, "activity": 1500, "record": 300}},
	]
	m.catalog = {"size": 64}
	m.stats = _stats(now)
	m.tracking_since = now - 30 * day
	return m

func _tx(category, reason, amount, time, related):
	return {"id": reason + str(time), "category": category, "reason": reason, "amount": amount, "timestamp": time, "related_id": related, "source": "server_event"}

func _quest(category, title, detail, value, target, xp, difficulty, icon, claimable = false):
	return {"category": category, "title": title, "detail": detail, "value": value, "target": target, "xp": xp,
		"difficulty": difficulty, "icon": icon, "claimable": claimable, "claimed": false}

func _collection(key, name, detail, tier, value, thresholds, emblem, claimable = false):
	var dates = []
	for i in 6:
		dates.append(OS.get_unix_time() - (20 - i * 3) * 86400 if i < tier else 0)
	return {"key": key, "name": name, "detail": detail, "tier": tier, "value": value, "thresholds": thresholds,
		"xp": [1000, 2500, 5000, 10000, 20000, 40000], "emblem": emblem, "claimable": claimable, "dates": dates}

func _stats(now):
	var names = [["Pyramid Dash", "32-player"], ["Cloud Castle", "16-player"], ["Frosty Heights", "Time trial"],
		["Sunny Slopes", "32-player"], ["Lava Leap", "8-player"], ["Knockout Arena", "Knockout"],
		["Neon Nights", "16-player"], ["Candy Cliffs", "32-player"]]
	var maps = []
	var i = 0
	for pair in names:
		i += 1
		maps.append({"key": pair[1] + ":" + pair[0], "name": pair[0], "mode": pair[1], "plays": 3 + i * 2, "completions": 2 + i,
			"dnfs": i % 3, "wins": i % 4, "best": 38.2 + i * 4.7, "total_time": (40.0 + i * 5) * (2 + i), "deaths": i * 2,
			"last_played": now - i * 40000, "best_placement": 1 + i % 5, "pb_steps": []})
	return {"all": {"observed": 142, "finishes": 97, "wins": 11, "dnfs": 31, "unknown": 14, "deaths": 208,
			"play_seconds": 61200.0, "placed": 120, "placement_sum": 780, "maps": {}},
		"session": {"observed": 6, "finishes": 5, "wins": 1, "dnfs": 1, "unknown": 0, "deaths": 7, "play_seconds": 1840.0,
			"placed": 6, "placement_sum": 21, "maps": {}},
		"since": now - 30 * 86400, "limit": 2000, "maps": maps, "firsts": 19,
		"highlights": {"most_played": maps[7].key, "strongest": maps[2].key, "nemesis": maps[4].key},
		"recent": [], "pb_events": {}, "error": "", "store": null}
