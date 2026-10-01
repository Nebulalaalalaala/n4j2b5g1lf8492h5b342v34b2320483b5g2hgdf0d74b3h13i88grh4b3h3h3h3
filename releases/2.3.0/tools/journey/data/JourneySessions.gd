extends Reference

# Play sessions from the recorded rounds: consecutive rounds with less than
# GAP seconds between them. Custom-lobby rounds and empty 0 s records (a state
# flicker older versions of the recorder saved) are left out.
const GAP = 1800
const MAX_SESSIONS = 30

static func valid(r) -> bool:
	if r.get("custom",false):
		return false
	return not (str(r.result)=="unknown" and float(r.play_seconds)<1.0)

func build(records:Array,transactions:Array) -> Array:
	var ordered = []
	for r in records:
		if valid(r):
			ordered.append(r)
	ordered.sort_custom(self,"_earlier")
	var sessions = []
	var current = null
	var seen_maps = {}
	var best = {}
	for r in ordered:
		var start = int(r.date)
		if current==null or start-int(current.end)>GAP:
			current = {"id":"s%d" % start,"start":start,"end":start,"active":0.0,"rounds":0,"matches":0,"wins":0,"firsts":0,"maps":0,"pbs":0,"quests":0,"xp":0,"categories":{}}
			sessions.append(current)
		current.end = max(int(current.end),start+int(ceil(float(r.play_seconds))))
		current.active += float(r.play_seconds)
		current.rounds += 1
		current.matches = current.rounds
		current.wins += int(bool(r.win))
		if str(r.mode)=="match_round" and str(r.result)=="finish" and int(r.placement)==1:
			current.firsts += 1
		if not seen_maps.has(r.map_id):
			seen_maps[r.map_id] = true
			current.maps += 1
		if str(r.mode)=="time_trial" and str(r.result)=="finish":
			var previous = float(best.get(r.map_id,-1.0))
			if previous>=0 and float(r.finish_time)<previous-0.000001:
				current.pbs += 1
			if previous<0 or float(r.finish_time)<previous:
				best[r.map_id] = float(r.finish_time)
	# Journey XP awarded during a session (small grace for post-match awards).
	for entry in transactions:
		var t = int(entry.timestamp)
		for s in sessions:
			if t>=int(s.start) and t<=int(s.end)+300:
				s.xp += int(entry.amount)
				s.categories[entry.category] = int(s.categories.get(entry.category,0))+int(entry.amount)
				break
	sessions.invert()
	if sessions.size()>MAX_SESSIONS:
		sessions.resize(MAX_SESSIONS)
	return sessions

# Day streaks: consecutive local days with a recorded round or active time.
# The current streak stays alive through today until the day ends.
func streaks(records:Array,active_days = {},now = -1) -> Dictionary:
	if now < 0:
		now = OS.get_unix_time()
	var days = {}
	for key in active_days:
		days[key] = true
	for r in records:
		if valid(r):
			days[_day_key(int(r.date))] = true
	var keys = days.keys()
	keys.sort()
	var best = 0
	var run = 0
	var previous = ""
	for key in keys:
		run = run+1 if not previous.empty() and _next_day(previous)==key else 1
		best = max(best,run)
		previous = key
	var current = 0
	var cursor = _day_key(now)
	if not days.has(cursor):
		cursor = _day_key(now-86400)
	var start = ""
	while days.has(cursor):
		current += 1
		start = cursor
		cursor = _prev_day(cursor)
	return {"current":current,"best":best,"today":days.has(_day_key(now)),"start":start}

static func _day_key(unix:int) -> String:
	var d = OS.get_datetime_from_unix_time(unix+int(OS.get_time_zone_info().get("bias",0))*60)
	return "%04d-%02d-%02d" % [d.year,d.month,d.day]

static func _unix(key:String) -> int:
	var p = key.split("-")
	return OS.get_unix_time_from_datetime({"year":int(p[0]),"month":int(p[1]),"day":int(p[2]),"hour":12,"minute":0,"second":0})

static func _next_day(key:String) -> String:
	var d = OS.get_datetime_from_unix_time(_unix(key)+86400)
	return "%04d-%02d-%02d" % [d.year,d.month,d.day]

static func _prev_day(key:String) -> String:
	var d = OS.get_datetime_from_unix_time(_unix(key)-86400)
	return "%04d-%02d-%02d" % [d.year,d.month,d.day]

func _earlier(a,b) -> bool:
	return int(a.date)<int(b.date)
