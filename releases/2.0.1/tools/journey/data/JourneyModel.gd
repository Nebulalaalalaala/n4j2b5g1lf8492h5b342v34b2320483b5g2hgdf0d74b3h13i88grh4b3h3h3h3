extends Reference

# Assembles what Journey displays from recorded sources only. A key left null
# means its system is not connected yet; the UI renders an explicit
# "not connected" state for it and never substitutes zeros or estimates.
#
# Connected today: Journey ledger + rank definitions, and the locally observed
# Profile Plus history (ProfileHistoryStore). Not connected yet: quests,
# achievements, cosmetics, pinned goals, inbox, verified activity, sessions,
# and the official eligible-map catalog.
# Shapes for every key: JOURNEY_UI_HANDOFF.md (and JourneyPreview.gd).

func build(ledger, definitions, profile_service) -> Dictionary:
	var m = {"preview": false}
	m.signed_in = not str(ledger.account_id).empty()
	m.writable = ledger.writable
	m.error = str(ledger.error)
	m.xp = int(ledger.total_xp)
	m.rank = definitions.rank_at(m.xp)
	m.next = definitions.rank_at(int(m.rank.next_xp))
	m.roadmap = definitions.roadmap(m.xp)
	m.next_league = _next_league(definitions, m.rank)
	m.rewards_table = definitions.REWARDS.duplicate()
	m.activity_milestones = []
	for i in definitions.ACTIVITY_SECONDS.size():
		m.activity_milestones.append({"seconds": int(definitions.ACTIVITY_SECONDS[i]), "xp": int(definitions.ACTIVITY_XP[i])})
	m.transactions = _newest_first(ledger.entries)
	m.promotions = _promotions(ledger.entries, m.roadmap)
	var day = _local_day_start(OS.get_unix_time())
	m.today_xp = _sum(ledger.category_totals(day, day + 86400))
	m.today_categories = ledger.category_totals(day, day + 86400)
	m.days = []
	for i in range(6, -1, -1):
		var start = day - i * 86400
		m.days.append({"start": start, "xp": _sum(ledger.category_totals(start, start + 86400))})
	m.tracking_since = _first_timestamp(ledger.entries)
	m.stats = _observed(profile_service)
	for key in ["activity", "quests", "achievements", "milestones", "cosmetics", "pins", "inbox", "sessions", "catalog"]:
		m[key] = null
	return m

func _next_league(definitions, rank) -> Dictionary:
	if str(rank.league) == "King League":
		return {}
	for candidate in definitions.roadmap(int(rank.xp)):
		if str(candidate.league) != str(rank.league) and int(candidate.xp) > int(rank.xp):
			return candidate
	return {}

func _sum(totals: Dictionary) -> int:
	var total = 0
	for key in totals:
		total += int(totals[key])
	return total

func _newest_first(entries: Array) -> Array:
	var out = entries.duplicate()
	out.sort_custom(self, "_later")
	return out

func _later(a, b) -> bool:
	return int(a.timestamp) > int(b.timestamp)

func _first_timestamp(entries: Array) -> int:
	var first = 0
	for entry in entries:
		if first == 0 or int(entry.timestamp) < first:
			first = int(entry.timestamp)
	return first

# Promotion dates come from the ledger itself: the timestamp of the award
# that first carried cumulative XP past each rank threshold.
func _promotions(entries: Array, ranks: Array) -> Dictionary:
	var ordered = entries.duplicate()
	ordered.sort_custom(self, "_earlier")
	var result = {}
	var total = 0
	var index = 0
	var thresholds = []
	for rank in ranks:
		if int(rank.xp) > 0:
			thresholds.append([int(rank.xp), int(rank.id)])
	for entry in ordered:
		total += int(entry.amount)
		while index < thresholds.size() and total >= thresholds[index][0]:
			result[thresholds[index][1]] = int(entry.timestamp)
			index += 1
	return result

func _earlier(a, b) -> bool:
	return int(a.timestamp) < int(b.timestamp)

func _local_day_start(utc: int) -> int:
	var offset = int(OS.get_time_zone_info().get("bias", 0)) * 60
	return int(floor(float(utc + offset) / 86400.0)) * 86400 - offset

# Locally observed history (formerly Profile Plus). Distinct from account
# lifetime stats; covers only what this client recorded since tracking began.
func _observed(service):
	if service == null or service.store == null or str(service.store.account_id).empty():
		return null
	var store = service.store
	var stats = store.statistics(store.records)
	var session = store.statistics(store.session)
	var progression = store.progression(store.records)
	var highlights = store.highlights(store.records)
	var maps = []
	for key in stats.maps:
		var map = stats.maps[key]
		var entry = map.duplicate()
		entry.key = key
		entry.best_placement = 0
		entry.players = 0
		entry.pb_steps = progression.maps[key].steps if progression.maps.has(key) else []
		maps.append(entry)
	for record in store.records:
		for entry in maps:
			if entry.key == record.mode + ":" + record.map_id and record.mode == "match_round":
				entry.players = max(entry.players, int(record.get("players", 0)))
			if entry.key == record.mode + ":" + record.map_id and int(record.placement) > 0:
				if entry.best_placement == 0 or int(record.placement) < entry.best_placement:
					entry.best_placement = int(record.placement)
	var recent = store.records.duplicate()
	recent.invert()
	return {
		"all": stats, "session": session, "since": int(store.since), "limit": int(store.LIMIT),
		"maps": maps, "highlights": highlights, "recent": recent.slice(0, min(recent.size(), 40) - 1) if recent.size() > 0 else [],
		"pb_events": progression.events, "error": str(store.last_error), "store": store,
	}
