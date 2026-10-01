extends "user://mod/tools/journey/ui/JourneyPages/04_theme_claim.gd"

func _finish_reward_card(parent, finish):
	var locked = str(finish.state) == "locked"
	var card = ui.card(parent, ui.NAVY, 0, 38)
	ui.grow(card)
	ui.clickable(card, self, "_watch_finish_anim", finish)
	var outer = ui.box(card, true, 0)
	var stage = FinishStage.new()
	stage.setup(ui.art.base_dir, finish, _finish_skin(), 260)
	outer.add_child(stage)
	if locked:
		stage.modulate = Color(0.62, 0.66, 0.8, 1)
		var lock = CenterContainer.new()
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		stage.add_child(lock)
		ui.tile_icon(lock, "lock", ui.WHITE, 64)
	var body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		body.add_constant_override("margin_" + side, 22)
	outer.add_child(body)
	var col = ui.box(body, true, 10)
	var row = ui.box(col, false, 12)
	ui.grow(ui.label(row, str(finish.name), "h3"))
	_state_pill(row, finish.state)
	ui.label(col, str(finish.get("text", "")), "small", ui.MUTED)
	var actions = ui.box(col, false, 12)
	ui.button(actions, "", "small", self, "_watch_finish_anim", finish, "eye").hint_tooltip = "Preview"
	if locked:
		ui.label(col, "%s · %s XP to go" % [finish.requirement, ui.thousands(max(0, int(finish.rank_xp) - int(screen._finish_xp())))], "small", ui.FAINT)
	else:
		ui.grow(ui.button(actions, "Unequip" if finish.state == "equipped" else "Equip", "primary", screen, "equip_finish", finish, "check"))

func _finish_skin():
	var profile = screen.profile_service
	var look = profile.get("skin") if profile != null else null
	return look if look is Dictionary else {}

# Preview window: a small level where the Goober crosses the finish line, does
# the finish, then the next-round countdown and transition play out.
func _watch_finish_anim(finish):
	var body = screen._overlay("Preview", "eye")
	ui.label(body, str(finish.name), "h3")
	var stage = FinishPreview.new()
	stage.setup(ui.art.base_dir, finish, _finish_skin(), 520, ui.font("display", 44, 5), ui.font("display", 30, 4))
	stage.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(stage)
	var row = ui.box(body, false, 14)
	ui.button(row, "Replay", "small", stage, "restart", null, "play")
	ui.button(row, "Skip to countdown", "small", stage, "skip")
	ui.spacer(row)
	if str(finish.state) == "locked":
		ui.label(row, str(finish.requirement), "body", ui.MUTED)
	else:
		ui.button(row, "Unequip" if finish.state == "equipped" else "Equip", "primary", screen, "equip_finish", finish, "check")

# Simulated finish-line stage. The real animation will come from the game's
# existing animation architecture; this stage stands in until it's wired.
func _finish_stage(parent, finish, height, animate):
	var stage = PanelContainer.new()
	stage.add_stylebox_override("panel", ui.flat(Color("2f7fe0"), 26, 0, 0, ui.INK, false))
	stage.rect_min_size = Vector2(0, height)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.rect_clip_content = true
	ui.grow(stage)
	parent.add_child(stage)
	var layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(layer)
	var ground = ColorRect.new()
	ground.color = Color("f0c27a")
	ground.anchor_right = 1
	ground.anchor_top = 0.74
	ground.anchor_bottom = 1
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ground)
	var line = HBoxContainer.new()
	line.add_constant_override("separation", 0)
	line.anchor_left = 0.62
	line.anchor_right = 0.62
	line.anchor_bottom = 0.74
	line.margin_right = 28
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(line)
	var checks = VBoxContainer.new()
	checks.add_constant_override("separation", 0)
	checks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.grow(checks, true, true)
	line.add_child(checks)
	for i in 12:
		var r = ColorRect.new()
		r.color = Color.white if i % 2 == 0 else ui.INK
		r.rect_min_size = Vector2(28, height * 0.74 / 12)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		checks.add_child(r)
	var goober = ui.icon(layer, "goober", int(height * 0.34), ui.PINK_LIGHT)
	goober.rect_position = Vector2(-10, height * 0.74 - height * 0.34)
	var burst = ui.icon(layer, str(finish.get("icon", "sparkle")), int(height * 0.3), ui.YELLOW)
	burst.anchor_left = 0.62
	burst.anchor_right = 0.62
	burst.margin_left = 36
	burst.margin_top = height * 0.14
	if animate and not ui.reduced_motion:
		goober.rect_position.x = -height * 0.4
		burst.modulate.a = 0.0
		burst.rect_pivot_offset = Vector2(height * 0.15, height * 0.15)
		var t = screen._tween()
		t.interpolate_property(goober, "rect_position:x", -height * 0.4, height * 1.8, 1.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
		t.interpolate_property(burst, "modulate:a", 0.0, 1.0, 0.25, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.7)
		t.interpolate_property(burst, "rect_scale", Vector2(0.3, 0.3), Vector2.ONE, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT, 0.7)
		t.start()
	else:
		goober.rect_position.x = height * 0.9
	return stage

func _watch_finish(finish):
	var body = screen._overlay("Finish preview · " + str(finish.name), "flag")
	_finish_stage(body, finish, 460, true)
	var row = ui.box(body, false, 14)
	ui.button(row, "Replay", "small", self, "_watch_finish", finish, "play")
	ui.spacer(row)
	var equip = ui.button(row, "Equip", "primary", screen, "request", "equip", "check")
	equip.disabled = str(finish.state) != "unlocked"

func _upcoming(parent):
	var m = _m()
	var card = ui.card(parent)
	var col = ui.box(card, true, 18)
	ui.heading(col, "Upcoming rank rewards", "overview")
	var row = ui.box(col, not screen.wide(), 18)
	var found = 0
	for rank in m.roadmap:
		if int(rank.xp) <= int(m.xp):
			continue
		for list in [m.cosmetics.themes, m.cosmetics.finishes]:
			for item in list:
				if str(item.requirement) == "Reach " + str(rank.name) and found < 3:
					var p = ui.well(row, ui.NAVY_2, 18, 28)
					ui.grow(p)
					var r = ui.box(p, false, 16)
					ui.badge(r, rank, 110)
					var c = ui.grow(ui.box(r, true, 2))
					c.alignment = BoxContainer.ALIGN_CENTER
					ui.label(c, str(item.name), "h3")
					ui.label(c, "%s · %s XP to go" % [rank.name, ui.thousands(int(rank.xp) - int(m.xp))], "small", ui.MUTED)
					found += 1
	if found == 0:
		ui.label(col, "No rank rewards are scheduled beyond your current rank yet.", "small", ui.MUTED)

# ================================================================== activity
func _range_bounds() -> Array:
	var now = OS.get_unix_time()
	var day = screen.models._local_day_start(now)
	match activity_range:
		"today":
			return [day, day + 86400]
		"week":
			return [day - 6 * 86400, day + 86400]
		"month":
			return [day - 29 * 86400, day + 86400]
	return [0, day + 86400]

func activity(parent):
	var m = _m()
	var head = screen.section_intro(parent, "Your GooberDash Career")
	ui.button(head, "Playtime rewards", "small", self, "_playtime_details", null, "clock")
	var career = m.get("career")
	ui.segmented(head if screen.wide() else parent, [["today", "Today"], ["week", "This week"], ["month", "This month"], ["all", "All time"]], activity_range, self, "_activity_range")
	var bounds = _range_bounds()
	var xp = 0
	for entry in m.transactions:
		if int(entry.timestamp) >= bounds[0] and int(entry.timestamp) < bounds[1]:
			xp += int(entry.amount)
	var observed = _observed_in(bounds)
	var kpis = _columns(parent, 6, 2, 20)
	var active = "—"
	var active_note = "Not tracked yet"
	var time_source = career if career != null else m.activity
	if time_source != null:
		active = ui.duration(time_source.today_seconds) if activity_range == "today" else ui.duration(time_source.lifetime_seconds if activity_range == "all" else _sum(time_source.get("days", [])))
		active_note = "All accounts" if career != null and int(career.accounts) > 1 else "Verified · earns XP"
	if m.activity != null and m.activity.get("open_seconds") != null and activity_range == "today":
		active_note = "App open " + ui.duration(m.activity.open_seconds)
	ui.kpi(kpis, active, "Active time", active_note, ui.GREEN_LIGHT, "clock")
	ui.kpi(kpis, ui.thousands(xp), "Journey XP", "This account", ui.YELLOW, "xp")
	ui.kpi(kpis, str(observed.matches) if observed != null else "—", "Rounds", "%d accounts" % int(career.accounts) if career != null and int(career.accounts) > 1 else "", ui.WHITE, "flag")
	ui.kpi(kpis, str(observed.wins) if observed != null else "—", "Overall wins", "", ui.WHITE, "crown")
	ui.kpi(kpis, str(observed.firsts) if observed != null else "—", "Race firsts", "", ui.WHITE, "podium")
	ui.kpi(kpis, str(observed.maps) if observed != null else "—", "Maps played", "", ui.WHITE, "maps")
	var charts = ui.box(parent, not screen.wide(), 26)
	var xp_card = ui.card(charts)
	ui.grow(xp_card)
	var xcol = ui.box(xp_card, true, 12)
	ui.heading(xcol, "Journey XP", "xp", "Last 7 days")
	var values = []
	var labels = []
	var missing = []
	for i in m.days.size():
		values.append(int(m.days[i].xp))
		labels.append(_weekday(m.days[i].start))
		if int(m.tracking_since) > 0 and int(m.days[i].start) + 86400 < int(m.tracking_since) and not m.preview:
			missing.append(i)
	ui.chart(xcol, values, labels, ui.YELLOW, values.size() - 1, 280, missing)
	var time_card = ui.card(charts)
	ui.grow(time_card)
	var tcol = ui.box(time_card, true, 12)
	ui.heading(tcol, "Active time", "clock", "Last 7 days")
	if time_source == null:
		screen.empty_state(tcol, "clock", "Verified activity isn't connected yet", "")
	else:
		var minutes = []
		for s in time_source.get("days", []):
			minutes.append(int(s) / 60)
		ui.chart(tcol, minutes, labels, ui.GREEN_LIGHT, minutes.size() - 1, 280)
	var lower = ui.box(parent, not screen.wide(), 26)
	var days_card = ui.card(lower)
	ui.grow(days_card, true, false, 1.5)
	var dcol = ui.box(days_card, true, 14)
	var dh = ui.heading(dcol, "Days", "calendar")
	ui.spacer(dh)
	ui.button(dh, "Calendar", "small", screen, "open", "calendar", "calendar")
	_days_list(dcol, bounds)
	var src = ui.card(lower)
	ui.grow(src, true, false, 1.0)
	src.size_flags_vertical = 0
	var hcol = ui.box(src, true, 16)
	var hh = ui.heading(hcol, "XP by source", "xp")
	ui.spacer(hh)
	ui.button(hh, "All", "small", screen, "open", "history", "chevron_right")
	_xp_sources(hcol, bounds)

# Rounds grouped by local day (newest first), each with a 24-hour strip.
func _days_list(parent, bounds):
	var m = _m()
	var records = m.career.records if m.get("career") != null else []
	if records.empty() and m.stats != null and m.stats.get("store") != null:
		records = m.stats.get("records", m.stats.store.records)
	var offset = ui._utc_offset()
	var days = {}
	for r in records:
		if int(r.date) < bounds[0] or int(r.date) >= bounds[1] or r.get("custom", false):
			continue
		if str(r.result) == "unknown" and float(r.play_seconds) < 1.0:
			continue
		var day = int(floor(float(int(r.date) + offset) / 86400.0))
		if not days.has(day):
			days[day] = []
		days[day].append(r)
	if days.empty():
		screen.empty_state(parent, "calendar", "No rounds recorded in this range", "")
		return
	var keys = days.keys()
	keys.sort()
	keys.invert()
	for i in min(10, keys.size()):
		_day_row(parent, keys[i], days[keys[i]], offset)

func _day_row(parent, day, rounds, offset):
	rounds.sort_custom(self, "_by_date")
	var start = day * 86400 - offset
	var p = ui.well(parent, ui.NAVY_2, 20, 22)
	var col = ui.box(p, true, 12)
	var row = ui.box(col, false, 20)
	var date = ui.box(row, true, 0)
	date.rect_min_size.x = 90
	date.alignment = BoxContainer.ALIGN_CENTER
	ui.label(date, _weekday(start), "caps", ui.MUTED, Label.ALIGN_CENTER)
	ui.label(date, str(OS.get_datetime_from_unix_time(start + offset).day), "num_m", ui.WHITE, Label.ALIGN_CENTER)
	var info = ui.grow(ui.box(row, true, 8))
	var played = 0.0
	var wins = 0
	for r in rounds:
		played += float(r.play_seconds)
		wins += int(bool(r.win))
	var last = rounds[rounds.size() - 1]
	ui.label(info, "%d round%s · %s · %s – %s" % [rounds.size(), "" if rounds.size() == 1 else "s", ui.duration(int(played)),
		_clock(int(rounds[0].date)), _clock(int(last.date) + int(float(last.play_seconds)))], "h3")
	var strip = DayStrip.new()
	strip.day_start = start
	strip.rounds = rounds
	strip.rect_min_size = Vector2(0, 50)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.font = ui.font("text", 20)
	strip.colors = [Color(0, 0.05, 0.14, 0.45), ui.GREEN_LIGHT, ui.YELLOW, ui.MUTED]
	info.add_child(strip)
	if wins > 0:
		ui.pill(row, "%d win%s" % [wins, "" if wins == 1 else "s"], ui.INK, ui.YELLOW, "crown")
	var open = day == open_day
	ui.button(row, "Hide" if open else "Rounds", "small", self, "_toggle_day", day, "chevron_down")
	if open:
		for r in rounds:
			var line = ui.box(col, false, 16)
			var t = ui.label(line, _clock(int(r.date)), "small", ui.MUTED)
			t.rect_min_size.x = 130
			var name = ui.label(line, str(r.get("map_name", r.map_id)), "body", ui.WHITE)
			name.clip_text = true
			ui.grow(name)
			ui.label(line, "TIME TRIAL" if str(r.mode) == "time_trial" else "ROUND", "caps", ui.MUTED)
			var res = ui.label(line, _round_result(r), "h3", ui.YELLOW if bool(r.win) or int(r.placement) == 1 else ui.WHITE, Label.ALIGN_RIGHT)
			res.rect_min_size.x = 150

func _toggle_day(day):
	open_day = -1 if open_day == day else day
	screen.refresh()

func _by_date(a, b) -> bool:
	return int(a.date) < int(b.date)

func _round_result(r) -> String:
	if str(r.mode) == "time_trial":
		return "%.3fs" % float(r.finish_time) if str(r.result) == "finish" and float(r.finish_time) > 0 else "DNF"
	var n = int(r.placement)
	if n > 0:
		var suffix = "th" if n % 100 in [11, 12, 13] else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
		return "%d%s" % [n, suffix]
	if bool(r.win):
		return "Won"
	return "DNF" if str(r.result) == "dnf" else str(r.result).capitalize()

func _clock(unix) -> String:
	var d = OS.get_datetime_from_unix_time(int(unix) + ui._utc_offset())
	var h = int(d.hour) % 12
	return "%d:%02d %s" % [12 if h == 0 else h, int(d.minute), "AM" if int(d.hour) < 12 else "PM"]

# Where this account's Journey XP came from in the selected range.
func _xp_sources(parent, bounds):
	var totals = {}
	var total = 0
	for entry in _m().transactions:
		if int(entry.timestamp) >= bounds[0] and int(entry.timestamp) < bounds[1]:
			totals[str(entry.category)] = int(totals.get(str(entry.category), 0)) + int(entry.amount)
			total += int(entry.amount)
	if total <= 0:
		screen.empty_state(parent, "xp", "No Journey XP in this range", "")
		return
	var sorter = ValueSort.new()
	sorter.values = totals
	var keys = totals.keys()
	keys.sort_custom(sorter, "desc")
	var big = ui.box(parent, false, 10)
	ui.icon(big, "xp", 44, ui.YELLOW)
	ui.label(big, ui.thousands(total) + " XP", "num_m", ui.YELLOW)
	for key in keys:
		var info = ui.CATEGORY.get(key, {"name": key.capitalize(), "icon": "xp", "color": ui.MUTED})
		var col = ui.box(parent, true, 6)
		var top = ui.box(col, false, 10)
		ui.icon(top, info.icon, 30, info.color)
		ui.grow(ui.label(top, str(info.name).replace(" XP", ""), "body", ui.WHITE))
		ui.label(top, ui.thousands(totals[key]), "h3", ui.WHITE)
		ui.bar(col, float(totals[key]) / float(total), info.color, 14)

func _activity_range(key):
	activity_range = key
	screen.refresh()

func _sum(values) -> int:
	var total = 0
	for v in values:
		total += int(v)
	return total

func _observed_in(bounds):
	var m = _m()
	if m.stats == null:
		return null
	if m.stats.get("store") == null:
		return {"matches": int(m.stats.session.observed) if activity_range == "today" else int(m.stats.all.observed), "wins": int(m.stats.all.wins), "firsts": int(m.stats.get("firsts", 0)), "maps": m.stats.maps.size()}
	var result = {"matches": 0, "wins": 0, "firsts": 0, "maps": 0}
	var seen = {}
	var source = m.career.records if m.get("career") != null else []
	if source.empty():
		source = m.stats.get("records", m.stats.store.records)
	for record in source:
		if int(record.date) < bounds[0] or int(record.date) >= bounds[1]:
			continue
		if record.get("custom", false) or (str(record.result) == "unknown" and float(record.play_seconds) < 1.0):
			continue
		result.matches += 1
		result.wins += int(bool(record.win))
		result.firsts += int(str(record.mode) == "match_round" and int(record.placement) == 1)
		seen[record.mode + ":" + record.map_id] = true
	result.maps = seen.size()
	return result

func tx_row(parent, entry):
	var info = ui.CATEGORY.get(str(entry.category), {"name": str(entry.category), "icon": "xp", "color": ui.MUTED})
	var row = ui.box(parent, false, 16)
	ui.tile_icon(row, info.icon, info.color, 60)
	var col = ui.grow(ui.box(row, true, 0))
	ui.label(col, str(entry.reason), "button")
	ui.label(col, "%s · %s" % [str(entry.get("related_id", "")), ui.date_text(entry.timestamp, true)], "small", ui.MUTED)
	ui.label(row, ui.xp_text(entry.amount), "button", ui.YELLOW)

# ================================================================== xp breakdown
# The grouped, expandable XP breakdown used by session summaries and (via
# Codex) the match results screen. Only categories that awarded XP appear;
# the headline total is the sum of the listed, deduplicated transactions.
func xp_breakdown(parent, transactions, key_prefix = "bd"):
	# Display-only grouping: keep the ledger and original receipt unchanged.
	var display = []
	var base_rows = {}
	for entry in transactions:
		if not str(entry.id).begins_with("daily-double:") and not base_rows.has(entry.id):
			var row = entry.duplicate(true)
			base_rows[entry.id] = row
			display.append(row)
	var bonus_seen = {}
	for entry in transactions:
		if not str(entry.id).begins_with("daily-double:") or bonus_seen.has(entry.id):
			continue
		bonus_seen[entry.id] = true
		var base_id = str(entry.id).trim_prefix("daily-double:")
		if base_rows.has(base_id):
			var row = base_rows[base_id]
			row.reason = "%s · %s ×2" % [row.reason, ui.thousands(row.amount)]
			row.amount += int(entry.amount)
		else:
			display.append(entry)
	transactions = display
	var groups = {}
	var ids = {}
	var total = 0
	for entry in transactions:
		if ids.has(entry.id):
			continue
		ids[entry.id] = true
		if not groups.has(entry.category):
			groups[entry.category] = []
		groups[entry.category].append(entry)
		total += int(entry.amount)
	var head = ui.box(parent, false, 16)
	ui.label(head, "TOTAL", "caps", ui.MUTED)
	ui.spacer(head)
	ui.label(head, ui.xp_text(total), "num_l", ui.YELLOW)
	for category in ["win", "placement", "exploration", "challenge", "activity", "record"]:
		if not groups.has(category):
			continue
		var info = ui.CATEGORY[category]
		var subtotal = 0
		for entry in groups[category]:
			subtotal += int(entry.amount)
		var key = key_prefix + category
		var open = bool(expanded.get(key, false))
		var p = ui.well(parent, ui.NAVY_2, 18, 26)
		ui.clickable(p, self, "_toggle_group", key)
		var col = ui.box(p, true, 10)
		var row = ui.box(col, false, 16)
		ui.tile_icon(row, info.icon, info.color, 62)
		ui.grow(ui.label(row, info.name.to_upper(), "h3"))
		ui.label(row, ui.xp_text(subtotal), "num_m", info.color)
		ui.icon(row, "chevron_down" if open else "chevron_right", 30, ui.MUTED)
		if open:
			for entry in groups[category]:
				var line = ui.box(col, false, 12)
				ui.spacer(line, 78, 0)
				ui.grow(ui.label(line, str(entry.reason), "small", ui.WHITE))
				ui.label(line, "+" + ui.thousands(entry.amount), "button", ui.MUTED)
	return total

func _toggle_group(key):
	expanded[key] = not bool(expanded.get(key, false))
	screen.refresh()
