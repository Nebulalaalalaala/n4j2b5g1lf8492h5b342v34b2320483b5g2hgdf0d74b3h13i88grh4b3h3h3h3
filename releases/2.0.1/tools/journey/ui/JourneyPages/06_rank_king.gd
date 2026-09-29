extends "user://mod/tools/journey/ui/JourneyPages/05_finish_watch.gd"

# ================================================================== session
func session(parent):
	var m = _m()
	screen.back_row(parent, "Session summary", "Latest session")
	var layout = ui.box(parent, not screen.wide(), 28)
	var left = ui.card(layout)
	ui.grow(left, true, false, 1.0)
	var lcol = ui.box(left, true, 16)
	var latest = m.sessions[0] if m.sessions != null and not m.sessions.empty() else null
	ui.heading(lcol, "XP earned", "xp", "Today" if latest == null else ui.date_text(latest.start, true))
	var from = screen.models._local_day_start(OS.get_unix_time()) if latest == null else int(latest.start)
	var to = OS.get_unix_time() + 1 if latest == null else int(latest.get("end", OS.get_unix_time())) + 300
	var today = []
	for entry in m.transactions:
		if int(entry.timestamp) >= from and int(entry.timestamp) <= to:
			today.append(entry)
	if today.empty():
		screen.empty_state(lcol, "xp", "No Journey XP this session" if latest != null else "No Journey XP yet today", "")
	else:
		xp_breakdown(lcol, today, "session")
	var right = ui.card(layout)
	ui.grow(right, true, false, 1.0)
	var rcol = ui.box(right, true, 16)
	var s = m.sessions[0] if m.sessions != null and not m.sessions.empty() else null
	var rh = ui.heading(rcol, "This session", "session")
	ui.spacer(rh)
	if s == null:
		_observed_tag(rh)
	var grid = _columns(rcol, 2, 2, 16)
	if s != null:
		ui.kpi(grid, ui.duration(s.active), "Round time", "", ui.GREEN_LIGHT, "clock")
		ui.kpi(grid, str(s.get("rounds", s.get("matches", 0))), "Rounds played", "", ui.WHITE, "flag")
		ui.kpi(grid, str(s.wins), "Overall wins", "", ui.YELLOW, "crown")
		ui.kpi(grid, str(s.firsts), "Race firsts", "", ui.WHITE, "podium")
		ui.kpi(grid, str(s.maps), "New maps", "", ui.WHITE, "compass")
		ui.kpi(grid, str(s.pbs), "New PBs", "", ui.WHITE, "stopwatch")
	elif m.stats != null:
		var st = m.stats.session
		ui.kpi(grid, "—", "Active time", "Not tracked yet", ui.GREEN_LIGHT, "clock")
		ui.kpi(grid, str(st.observed), "Rounds recorded", "", ui.WHITE, "flag")
		ui.kpi(grid, str(st.wins), "Confirmed wins", "", ui.YELLOW, "crown")
		ui.kpi(grid, str(st.finishes), "Finishes", "", ui.WHITE, "podium")
		ui.kpi(grid, str(st.deaths), "Deaths", "", ui.WHITE, "target")
		ui.kpi(grid, ui.duration(st.play_seconds), "Round time", "Observed, not verified", ui.WHITE, "stopwatch")
	else:
		screen.empty_state(rcol, "session", "Nothing recorded this session", "")
	if m.pins != null:
		var pins = ui.card(parent)
		var pcol = ui.box(pins, true, 14)
		ui.heading(pcol, "Pinned goal progress", "pin")
		for pin in m.pins:
			pin_row(pcol, pin)

func history(parent):
	var m = _m()
	screen.back_row(parent, "XP history", "All Journey XP")
	var card = ui.card(parent)
	var col = ui.box(card, true, 14)
	if m.transactions.empty():
		screen.empty_state(col, "xp", "No Journey XP yet", "")
		return
	var last_day = ""
	for entry in m.transactions:
		var d = ui.date_text(entry.timestamp)
		if d != last_day:
			last_day = d
			ui.label(col, d.to_upper(), "caps", ui.MUTED)
		tx_row(col, entry)

# ================================================================== calendar
# Journey XP leaderboard (everyone using the tool). Fetched while open.
func leaderboard(parent):
	screen.back_row(parent, "Leaderboard", "Journey XP · everyone using Goobplayability")
	var board = screen.leaderboard
	board.fetch()
	var card = ui.card(parent)
	var col = ui.box(card, true, 10)
	var head = ui.heading(col, "Top 100", "podium")
	ui.spacer(head)
	ui.button(head, "Refresh", "small", board, "fetch", true, "sparkle")
	if board.status in ["missing", "unavailable"]:
		screen.empty_state(col, "podium", "The leaderboard isn't set up yet", "")
		return
	if board.rows.empty():
		screen.empty_state(col, "podium", "Loading…" if board.status in ["loading", "idle"] else ("Couldn't reach the leaderboard" if board.status == "error" else "No players yet"), "")
		return
	var me = board.player_key(screen.ledger.account_id)
	var found = false
	for i in board.rows.size():
		var row = board.rows[i]
		var own = str(row.player) == me
		found = found or own
		_leader_row(col, i + 1, row, own)
	if not found and int(screen.ledger.total_xp) > 0:
		ui.label(col, "You'll appear here once your XP is sent (every couple of minutes).", "small", ui.FAINT)

func _leader_row(parent, place, row, own):
	var p = ui.well(parent, ui.YELLOW.darkened(0.55) if own else ui.NAVY_2, 16, 24)
	var line = ui.box(p, false, 18)
	var pos = ui.label(line, str(place), "num_m", [ui.YELLOW, Color("d6e2f0"), Color("e0a36b")][place - 1] if place <= 3 else ui.MUTED, Label.ALIGN_CENTER)
	pos.rect_min_size.x = 70
	ui.badge(line, screen.definitions.rank_at(int(row.xp)), 64)
	var name = ui.label(line, str(row.name) + ("  (you)" if own else ""), "h3", ui.WHITE)
	name.clip_text = true
	ui.grow(name)
	ui.label(line, str(row.rank), "small", ui.MUTED)
	var xp = ui.label(line, ui.thousands(row.xp) + " XP", "h3", ui.YELLOW, Label.ALIGN_RIGHT)
	xp.rect_min_size.x = 220

func calendar(parent):
	var m = _m()
	screen.back_row(parent, "Activity calendar", "Your weekly activity")
	var card = ui.card(parent)
	var col = ui.box(card, true, 20)
	var nav = ui.box(col, false, 16)
	ui.button(nav, "", "small", self, "_calendar_week", -1, "back")
	var today = screen.models._local_day_start(OS.get_unix_time())
	var start = today - 6 * 86400 + calendar_week * 7 * 86400
	ui.grow(ui.label(nav, "%s – %s" % [ui.date_text(start), ui.date_text(start + 6 * 86400)], "h2", ui.WHITE, Label.ALIGN_CENTER))
	var fwd = ui.button(nav, "", "small", self, "_calendar_week", 1, "chevron_right")
	fwd.disabled = calendar_week >= 0
	var row = ui.box(col, false, 14)
	for i in 7:
		var day = start + i * 86400
		var xp = _day_xp(day)
		var known = m.preview or int(m.tracking_since) == 0 or day + 86400 >= int(m.tracking_since)
		var is_today = day == today
		var cell = ui.well(row, ui.PINK.darkened(0.35) if is_today else (ui.NAVY_2 if known else Color(1, 1, 1, 0.03)), 18, 28 if screen.wide() else 6)
		ui.grow(cell)
		var c = ui.box(cell, true, 4)
		c.alignment = BoxContainer.ALIGN_CENTER
		ui.label(c, _weekday(day), "caps", ui.WHITE if is_today else ui.MUTED, Label.ALIGN_CENTER)
		var d = OS.get_datetime_from_unix_time(day + ui._utc_offset())
		ui.label(c, str(d.day), "num_l" if screen.wide() else "num_m", ui.WHITE if known else ui.FAINT, Label.ALIGN_CENTER)
		if not known:
			ui.label(c, "No data", "small", ui.FAINT, Label.ALIGN_CENTER)
			continue
		if screen.wide():
			ui.label(c, ui.xp_text(xp) if xp > 0 else "No XP", "button", ui.YELLOW if xp > 0 else ui.FAINT, Label.ALIGN_CENTER)
		else:
			ui.label(c, ("+" + _compact(xp)) if xp > 0 else "0", "button", ui.YELLOW if xp > 0 else ui.FAINT, Label.ALIGN_CENTER)
		var active = "—"
		if m.activity != null and calendar_week == 0:
			active = ui.duration(m.activity.days[i]) if int(m.activity.days[i]) > 0 else "0 min"
		if screen.wide() or active == "—":
			ui.label(c, active, "small", ui.MUTED, Label.ALIGN_CENTER)
		else:
			ui.label(c, active.replace(" min", "m").replace("h ", "h\n"), "small", ui.MUTED, Label.ALIGN_CENTER)
	var tx = ui.card(parent)
	var tcol = ui.box(tx, true, 14)
	ui.heading(tcol, "Awards this week", "xp")
	var any = false
	for entry in m.transactions:
		if int(entry.timestamp) >= start and int(entry.timestamp) < start + 7 * 86400:
			tx_row(tcol, entry)
			any = true
	if not any:
		ui.label(tcol, "No Journey XP was awarded this week.", "small", ui.MUTED)

func _day_xp(day) -> int:
	var total = 0
	for entry in _m().transactions:
		if int(entry.timestamp) >= day and int(entry.timestamp) < day + 86400:
			total += int(entry.amount)
	if _m().preview:
		for d in _m().days:
			if abs(int(d.start) - day) < 86400 and total == 0:
				return int(d.xp)
	return total

func _calendar_week(delta):
	calendar_week = min(0, calendar_week + int(delta))
	screen.refresh()

# ================================================================== roadmap
func roadmap(parent):
	var m = _m()
	screen.back_row(parent, "Rank roadmap", "Bronze to King League")
	if selected_rank < 0:
		selected_rank = int(m.rank.id)
	var layout = ui.box(parent, not screen.wide(), 28)
	var track = ui.box(layout, true, 20)
	ui.grow(track, true, false, 1.7)
	var leagues = {}
	var order = []
	for rank in m.roadmap:
		if str(rank.league) == "King League":
			continue
		if not leagues.has(rank.league):
			leagues[rank.league] = []
			order.append(rank.league)
		leagues[rank.league].append(rank)
	for league_name in order:
		_league_row(track, league_name, leagues[league_name])
	_king_row(track)
	var detail = ui.card(layout, ui.NAVY)
	ui.grow(detail, true, false, 1.0)
	_rank_detail(detail)

func _league_row(parent, league_name, ranks):
	var m = _m()
	var lg = ui.league(ranks[0])
	var current_league = str(m.rank.league) == league_name
	var card = ui.card(parent, ui.NAVY.linear_interpolate(lg.deep, 0.3 if current_league else 0.0), 24, 40)
	var stack = ui.box(card, not screen.wide(), 14)
	var name_col = ui.box(stack, screen.wide(), 2 if screen.wide() else 16)
	var row = stack if screen.wide() else ui.box(stack, false, 10)
	name_col.rect_min_size.x = 220 if screen.wide() else 0
	name_col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(name_col, league_name.to_upper(), "h2", lg.light if int(m.xp) >= int(ranks[0].xp) else ui.MUTED)
	ui.label(name_col, "%s XP" % ui.thousands(ranks[0].xp), "small", ui.MUTED)
	for i in ranks.size():
		var rank = ranks[i]
		if i > 0:
			var line = ui.bar(row, 1.0 if int(m.xp) >= int(rank.xp) else 0.0, lg.base, 10, Color(1, 1, 1, 0.1))
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.rect_min_size.x = 20
		_rank_node(row, rank)

func _rank_node(parent, rank):
	var m = _m()
	var done = int(m.xp) >= int(rank.next_xp)
	var current = int(rank.id) == int(m.rank.id)
	var selected = int(rank.id) == selected_rank
	var p = PanelContainer.new()
	var s = ui.flat(ui.NAVY_3 if selected else Color(0, 0, 0, 0), 30, 12, 0, ui.INK, false)
	if current:
		s.border_width_left = 5
		s.border_width_right = 5
		s.border_width_top = 5
		s.border_width_bottom = 5
		s.border_color = ui.YELLOW
	p.add_stylebox_override("panel", s)
	parent.add_child(p)
	ui.clickable(p, self, "_select_rank", int(rank.id))
	var col = ui.box(p, true, 2)
	col.alignment = BoxContainer.ALIGN_CENTER
	var b = ui.badge(col, rank, 132 if screen.wide() else 100)
	if not done and not current:
		b.modulate = Color(1, 1, 1, 0.45)
	ui.label(col, str(rank.division), "h3", ui.WHITE if done or current else ui.FAINT, Label.ALIGN_CENTER)
	var tag = "YOU" if current else (_short_date(m.promotions[int(rank.id)]) if done and m.promotions.has(int(rank.id)) else ("DONE" if done else ui.thousands(rank.xp)))
	ui.label(col, tag, "caps", ui.YELLOW if current else (ui.GREEN_LIGHT if done else ui.FAINT), Label.ALIGN_CENTER)

func _short_date(t):
	var text = ui.date_text(t)
	if screen.wide():
		return text
	var parts = text.split(" ")
	return (parts[0] + " " + parts[1]) if parts.size() >= 2 else text

func _king_row(parent):
	var m = _m()
	var lg = ui.LEAGUES.king
	var card = ui.card(parent, ui.NAVY.linear_interpolate(lg.deep, 0.5), 24, 40)
	var stack = ui.box(card, not screen.wide(), 14)
	var name_col = ui.box(stack, screen.wide(), 2 if screen.wide() else 16)
	var row = stack if screen.wide() else ui.box(stack, false, 10)
	name_col.rect_min_size.x = 220 if screen.wide() else 0
	name_col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(name_col, "KING LEAGUE", "h2", ui.YELLOW)
	ui.label(name_col, "Numbered, never-ending", "small", ui.MUTED)
	var left = ui.button(row, "", "small", self, "_king_shift", -1, "back")
	var ranks = _king_window()
	left.disabled = int(ranks[0].division) <= 1
	for i in ranks.size():
		if i > 0:
			var line = ui.bar(row, 1.0 if int(m.xp) >= int(ranks[i].xp) else 0.0, lg.base, 10, Color(1, 1, 1, 0.1))
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.rect_min_size.x = 16
		_rank_node(row, ranks[i])
	ui.button(row, "", "small", self, "_king_shift", 1, "chevron_right")

func _king_window() -> Array:
	var m = _m()
	var defs = screen.definitions
	var center = 1
	if str(m.rank.league) == "King League":
		center = int(m.rank.division)
	center = max(1, center + king_shift)
	var first = max(1, center - 1)
	var out = []
	for number in range(first, first + 4):
		out.append(defs.king_rank(number))
	return out

func _king_shift(delta):
	king_shift += int(delta) * 3
	if king_shift < 0 and _king_window()[0].division == "1":
		king_shift = 0
	screen.refresh()

func _select_rank(id):
	selected_rank = int(id)
	screen.refresh()

func _find_rank(id):
	var m = _m()
	for rank in m.roadmap + _king_window():
		if int(rank.id) == int(id):
			return rank
	return m.rank

func _rank_detail(parent):
	var m = _m()
	var rank = _find_rank(selected_rank)
	var lg = ui.league(rank)
	var col = ui.box(parent, true, 18)
	var holder = ui.box(col, true, 0)
	holder.alignment = BoxContainer.ALIGN_CENTER
	ui.badge(holder, rank, 300, true, true)
	ui.label(col, str(rank.name).to_upper(), "h1", ui.WHITE, Label.ALIGN_CENTER)
	var done = int(m.xp) >= int(rank.next_xp)
	var current = int(rank.id) == int(m.rank.id)
	var state = "COMPLETED" if done else ("CURRENT RANK" if current else "UPCOMING")
	var chip_row = ui.box(col, false, 0)
	chip_row.alignment = BoxContainer.ALIGN_CENTER
	ui.pill(chip_row, state, ui.INK, ui.GREEN_LIGHT if done else (ui.YELLOW if current else ui.SKY_LIGHT))
	var facts = ui.well(col, ui.NAVY_2, 22, 30)
	var fcol = ui.box(facts, true, 10)
	_fact(fcol, "Reached at", "%s XP" % ui.thousands(rank.xp))
	_fact(fcol, "Next rank at", "%s XP" % ui.thousands(rank.next_xp))
	if done or current:
		_fact(fcol, "Promoted", ui.date_text(m.promotions.get(int(rank.id), 0), true) if int(rank.xp) > 0 else "Starting rank")
	if not done:
		var target = int(rank.xp) if not current else int(rank.next_xp)
		_fact(fcol, "To go", "%s XP" % ui.thousands(max(0, target - int(m.xp))))
		var from = int(m.rank.xp)
		ui.bar(fcol, float(int(m.xp) - from) / max(1, target - from) if not current else float(int(m.xp) - int(rank.xp)) / max(1, int(rank.next_xp) - int(rank.xp)), lg.base, 22)
	if not done and not current:
		var pin_row = ui.box(col, false, 0)
		pin_row.alignment = BoxContainer.ALIGN_CENTER
		_pin_button(pin_row, "rank", int(rank.id), "Pin this rank")
	var rewards = ui.box(col, true, 10)
	ui.label(rewards, "UNLOCKS AT THIS RANK", "caps", ui.MUTED)
	var any = false
	if m.cosmetics != null:
		for list in [m.cosmetics.themes, m.cosmetics.finishes]:
			for item in list:
				if str(item.requirement) == "Reach " + str(rank.name):
					var r = ui.well(rewards, ui.NAVY_2, 16, 26)
					var row = ui.box(r, false, 14)
					ui.tile_icon(row, "palette" if list == m.cosmetics.themes else "flag", ui.PINK_LIGHT, 64)
					ui.grow(ui.label(row, str(item.name), "h3"))
					if list == m.cosmetics.themes:
						ui.button(row, "Preview", "small", self, "_preview_theme", item, "play")
					else:
						ui.button(row, "", "small", self, "_watch_finish_anim", item, "eye").hint_tooltip = "Preview"
					if not done and not current:
						_pin_button(row, "rank", int(rank.id), "Pin")
					any = true
	if not any:
		ui.label(rewards, "No rewards at this rank" if m.cosmetics != null else "Rank rewards aren't connected yet", "small", ui.FAINT)

func _fact(parent, name, value):
	var row = ui.box(parent, false, 12)
	ui.label(row, name, "small", ui.MUTED)
	ui.spacer(row)
	ui.label(row, value, "button", ui.WHITE, Label.ALIGN_RIGHT)

# ================================================================== statistics
func statistics(parent):
	var m = _m()
	var sub = ""
	if m.stats != null:
		sub = "Since %s · last %s rounds" % [ui.date_text(m.stats.since), ui.thousands(m.stats.limit)]
	var head = screen.back_row(parent, "Statistics & records", sub)
	_observed_tag(head)
	if m.stats == null:
		screen.empty_state(ui.card(parent), "session", "Sign in to view your recorded statistics", "")
		return
	var st = m.stats
	var all = st.all
	var grid = _columns(parent, 4, 2, 20)
	ui.kpi(grid, ui.thousands(all.observed), "Rounds recorded", "Matches and time trials", ui.WHITE, "flag")
	ui.kpi(grid, ui.thousands(all.finishes), "Finishes", "%d known DNFs" % int(all.dnfs), ui.WHITE, "podium")
	ui.kpi(grid, ui.thousands(all.wins), "Confirmed wins", "", ui.YELLOW, "crown")
	ui.kpi(grid, str(st.maps.size()), "Maps", "", ui.WHITE, "maps")
	ui.kpi(grid, ("%.2f" % (float(all.placement_sum) / all.placed)) if int(all.placed) > 0 else "—", "Avg. placement", "Known placements only", ui.WHITE, "podium")
	ui.kpi(grid, ui.duration(all.play_seconds), "Round time", "", ui.WHITE, "clock")
	ui.kpi(grid, ui.thousands(all.deaths), "Deaths", "", ui.WHITE, "target")
	ui.kpi(grid, ui.thousands(all.unknown), "Unknown outcomes", "Excluded from rates", ui.FAINT, "session")
	var hl = _columns(parent, 3, 1, 22)
	for pair in [["Most played", "most_played", "flag", Color("7fb4ff")], ["Strongest map", "strongest", "crown", Color("ffc40f")], ["Nemesis", "nemesis", "target", Color("ff7ed3")]]:
		var key = str(st.highlights.get(pair[1], ""))
		var card = ui.card(hl)
		ui.grow(card)
		var row = ui.box(card, false, 20)
		ui.tile_icon(row, pair[2], pair[3], 84)
		var col = ui.grow(ui.box(row, true, 2))
		ui.label(col, pair[0].to_upper(), "caps", ui.MUTED)
		var found = null
		for map in st.maps:
			if map.key == key:
				found = map
		ui.label(col, str(found.name) if found != null else "Not enough evidence", "h3", ui.WHITE if found != null else ui.FAINT)
		if found != null:
			ui.label(col, str(found.mode) + ("" if pair[1] == "most_played" else " · by completion rate"), "small", ui.MUTED)
		if pair[1] != "most_played":
			card.hint_tooltip = "Completion rate over at least five known outcomes. Unknown outcomes are excluded."
	var records = ui.card(parent)
	var rcol = ui.box(records, true, 16)
	var rh = ui.heading(rcol, "Map records", "stopwatch")
	ui.spacer(rh)
	var search = ui.search_field(rh, "Filter maps or mode", record_query, self, "_record_search")
	search.rect_min_size.x = 520
	record_list = ui.box(rcol, true, 10)
	_fill_records()
	var manage = ui.card(parent)
	var mcol = ui.box(manage, true, 14)
	ui.heading(mcol, "Manage recorded data", "gear")
	var actions = ui.box(mcol, false, 14)
	ui.button(actions, "Export", "small", self, "_export", null, "session")
	ui.button(actions, "Import", "small", self, "_import", null, "inbox")
	ui.button(actions, "Reset recorded history", "small", self, "_reset", null, "close")
	if str(st.error) != "":
		ui.label(mcol, str(st.error), "small", ui.RED)

func _record_search(text):
	record_query = text
	_fill_records()
