extends Reference

# Progress over time from recorded match rounds: wins per week, win streaks,
# a weekly goal, and best / worst maps. Shared by Journey and Goober Hub.

const WEEK = 604800
const GOAL_SETTING = "journey_weekly_win_goal"


func _week_start(utc: int) -> int:
	var offset = int(OS.get_time_zone_info().get("bias", 0)) * 60
	var local = utc + offset
	var day = int(floor(float(local) / 86400.0))
	# 1970-01-01 was a Thursday; weeks start on Monday.
	var weekday = posmod(day + 3, 7)
	return (day - weekday) * 86400 - offset


func _rounds(records: Array) -> Array:
	var out = []
	for r in records:
		if r is Dictionary and not bool(r.get("custom", false)) and str(r.get("mode", "")) == "match_round":
			out.append(r)
	out.sort_custom(self, "_earlier")
	return out


func _earlier(a, b) -> bool:
	return int(a.get("date", 0)) < int(b.get("date", 0))


# [{start, wins, rounds}] oldest first, `weeks` long, ending this week.
func weekly(records: Array, weeks: int = 12) -> Array:
	var now = _week_start(OS.get_unix_time())
	var result = []
	for index in range(weeks - 1, -1, -1):
		result.append({"start": now - index * WEEK, "wins": 0, "rounds": 0})
	for r in _rounds(records):
		var start = _week_start(int(r.get("date", 0)))
		var slot = weeks - 1 - int(round(float(now - start) / WEEK))
		if slot < 0 or slot >= weeks:
			continue
		result[slot].rounds += 1
		if bool(r.get("win", false)):
			result[slot].wins += 1
	return result


func streaks(records: Array) -> Dictionary:
	var current = 0
	var longest = 0
	var longest_at = 0
	for r in _rounds(records):
		if bool(r.get("win", false)):
			current += 1
			if current > longest:
				longest = current
				longest_at = int(r.get("date", 0))
		elif str(r.get("result", "")) != "unknown":
			current = 0
	return {"current": current, "longest": longest, "longest_at": longest_at}


func goal() -> int:
	return int(max(1, int(SavedSettings.get_value(GOAL_SETTING, 25))))


func set_goal(value: int) -> void:
	SavedSettings.set_value(GOAL_SETTING, int(clamp(value, 1, 999)))


# Best and worst maps by win rate, over maps with at least `minimum` rounds.
func maps(records: Array, names: Dictionary, minimum: int = 5) -> Dictionary:
	var by_map = {}
	for r in _rounds(records):
		var key = str(r.get("map_id", ""))
		if key.empty():
			continue
		if not by_map.has(key):
			by_map[key] = {"key": key, "name": str(names.get(key, r.get("map_name", key))), "rounds": 0, "wins": 0}
		by_map[key].rounds += 1
		if bool(r.get("win", false)):
			by_map[key].wins += 1
	var list = []
	for entry in by_map.values():
		if entry.rounds >= minimum:
			entry["rate"] = float(entry.wins) / entry.rounds
			list.append(entry)
	list.sort_custom(self, "_better")
	var best = list.slice(0, min(3, list.size()) - 1) if not list.empty() else []
	var worst = []
	for index in range(list.size() - 1, max(-1, list.size() - 4), -1):
		if not list[index] in best:
			worst.append(list[index])
	return {"best": best, "worst": worst}


func _better(a, b) -> bool:
	return a.rate > b.rate


# Weekly wins for another player from snapshots of their total wins.
func weekly_from_snapshots(snapshots: Array, weeks: int = 8) -> Array:
	var now = _week_start(OS.get_unix_time())
	var result = []
	for index in range(weeks - 1, -1, -1):
		var start = now - index * WEEK
		var first = null
		var last = null
		for snap in snapshots:
			var at = int(snap[0])
			if at >= start and at < start + WEEK:
				if first == null:
					first = snap
				last = snap
		var wins = int(last[1]) - int(first[1]) if first != null and last != null else -1
		result.append({"start": start, "wins": wins, "rounds": 0})
	return result


class WeekBars extends Control:
	var weeks = []
	var goal = 0
	var colour = Color("ffc40f")
	var font = null

	func _draw() -> void:
		if weeks.empty():
			return
		if font == null:
			font = get_font("font", "Label")
		var top = max(1, goal)
		for week in weeks:
			top = max(top, int(week.wins))
		var gap = 8.0
		var width = (rect_size.x - gap * (weeks.size() - 1)) / weeks.size()
		var base = rect_size.y - 22
		for index in weeks.size():
			var week = weeks[index]
			var x = index * (width + gap)
			draw_rect(Rect2(x, 0, width, base), Color(1, 1, 1, 0.04))
			if int(week.wins) >= 0:
				var height = base * float(week.wins) / top
				var fill = colour if index == weeks.size() - 1 else Color(colour.r, colour.g, colour.b, 0.6)
				draw_rect(Rect2(x, base - height, width, height), fill)
				if font != null and int(week.wins) > 0:
					var text = str(week.wins)
					draw_string(font, Vector2(x + width * 0.5 - font.get_string_size(text).x * 0.5, base - height - 4), text, Color.white)
			if font != null and (index % 2 == 1 or index == weeks.size() - 1):
				var date = OS.get_datetime_from_unix_time(int(week.start))
				var label = "%d/%d" % [date.day, date.month]
				draw_string(font, Vector2(x, rect_size.y - 4), label, Color(1, 1, 1, 0.55))
		if goal > 0:
			var y = base - base * float(goal) / top
			draw_line(Vector2(0, y), Vector2(rect_size.x, y), Color("7fe0b4"), 2.0)
