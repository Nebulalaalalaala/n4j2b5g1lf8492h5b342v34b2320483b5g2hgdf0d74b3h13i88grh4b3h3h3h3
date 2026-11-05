extends "user://mod/tools/journey/ui/JourneyPages/01_placeholders.gd"

func _m():
	return screen.model

# ================================================================== shared rows
func quest_row(parent, quest, compact = false):
	var color = QUEST_COLORS.get(str(quest.category), ui.MUTED)
	var done = int(quest.value) >= int(quest.target)
	var p = ui.well(parent, ui.NAVY_2, 20, 30)
	var row = ui.box(p, false, 22)
	ui.tile_icon(row, str(quest.icon), color, (84 if compact else 96) if screen.wide() else 72)
	var col = ui.grow(ui.box(row, true, 8))
	col.alignment = BoxContainer.ALIGN_CENTER
	var top = _flow(col, 12)
	ui.label(top, str(quest.title), "h3")
	_pin_toggle(top, "quest", str(quest.id))
	if not compact:
		var diff = DIFFICULTY.get(str(quest.difficulty), DIFFICULTY.medium)
		ui.pill(top, diff[0], ui.INK, diff[1])
		ui.label(col, str(quest.detail), "small", ui.MUTED)
	var line = ui.box(col, false, 16)
	var b = ui.bar(line, float(quest.value) / max(1, int(quest.target)), ui.GREEN if done else color, 20)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.label(line, "%d / %d" % [int(quest.value), int(quest.target)], "button", ui.WHITE if done else ui.MUTED)
	var side = ui.box(row, true, 8) if screen.wide() else ui.box(col, false, 12)
	side.alignment = BoxContainer.ALIGN_CENTER if screen.wide() else BoxContainer.ALIGN_BEGIN
	if bool(quest.get("claimable", false)):
		ui.button(side, "Claim " + ui.xp_text(quest.xp), "primary", self, "_claim_quest", {"quest": quest, "row": p}, "check")
	elif bool(quest.get("claimed", false)):
		ui.pill(side, "CLAIMED", ui.INK, ui.GREEN_LIGHT, "check")
	elif done:
		ui.pill(side, "COMPLETE · " + ui.xp_text(quest.xp), ui.INK, ui.GREEN_LIGHT, "check")
	else:
		ui.pill(side, ui.xp_text(quest.xp), ui.INK, ui.YELLOW, "xp")
	return p

func pin_row(parent, pin):
	var color = Color(str(pin.get("color", "ffc40f")))
	var p = ui.well(parent, ui.NAVY_2, 18, 30)
	var row = ui.box(p, false, 20)
	var ringholder = Control.new()
	ringholder.rect_min_size = Vector2(88, 88)
	ringholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ringholder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ringholder)
	var ratio = float(pin.value) / max(1, int(pin.target))
	var r = ui.ring_progress(ringholder, ratio, 88, color, 10)
	r.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var i = ui.icon(ringholder, str(pin.icon), 38, color)
	i.set_anchors_and_margins_preset(Control.PRESET_CENTER)
	i.margin_left = -19
	i.margin_top = -19
	i.margin_right = 19
	i.margin_bottom = 19
	var col = ui.grow(ui.box(row, true, 2))
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(col, str(pin.name), "h3")
	ui.label(col, str(pin.next), "small", ui.MUTED)
	ui.label(row, "%d%%" % int(round(ratio * 100)), "num_m", color)
	if pin.get("spec") is Dictionary:
		if pin.get("target_view") is Dictionary:
			ui.clickable(p, screen, "open_item", pin.target_view)
		var unpin = ui.button(row, "", "quiet", screen, "toggle_pin", pin.spec, "close")
		unpin.hint_tooltip = "Unpin"
		unpin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

# Pinned goals are stored as {kind, key}; progress is recomputed from live
# data on every render so a pin never shows stale numbers.
func resolve_pins(m, specs) -> Array:
	var out = []
	for spec in specs:
		var pin = null
		match str(spec.kind):
			"quest":
				if m.quests != null:
					for q in m.quests.daily + m.quests.weekly:
						if str(q.id) == str(spec.key):
							pin = {"name":q.title,"next":"Claimed" if q.claimed else ("Ready to claim" if q.done else "%d / %d" % [q.value,q.target]),
								"value":q.value,"target":q.target,"icon":q.icon,"color":"5ee0c8","target_view":{"section":"Quests","view":""}}
				if pin == null:
					pin = {"name":"Previous quest","next":"Expired or replaced · unpin to choose another","value":0,"target":1,"icon":"quests","color":"7099c7","target_view":{"section":"Quests","view":""}}
			"milestone":
				if m.milestones != null:
					for item in m.milestones:
						if str(item.get("key",item.name)) == str(spec.key):
							pin = {"name":item.name,"next":"Completed" if item.done else item.detail,
								"value":100 if item.done else int(float(item.get("progress",0))*100),"target":100,"icon":"flag","color":"ffc40f","target_view":bonus_target(str(spec.key))}
			"achievement":
				if m.achievements != null:
					for c in m.achievements.collections:
						if c.key == spec.key and not c.get("unsupported", false):
							var tier = int(c.tier)
							var goal = _thr(c, tier)
							pin = {"name": "%s · %s" % [c.name, _tname(c, tier)], "next": "%s more to go" % ui.thousands(max(0, goal - int(c.value))),
								"value": int(c.value), "target": goal}
							pin.icon = "achievements"
							pin.color = "ffc40f"
							pin.target_view = {"view": "achievement", "key": c.key}
			"map":
				for item in _map_items():
					if str(item.key).split(":", true, 1)[-1] == spec.key:
						var next = "All objectives complete"
						for o in item.objectives:
							if not o.done and not o.get("unsupported", false):
								next = "Next: " + str(o.label)
								break
						pin = {"name": str(item.name), "next": next, "value": int(item.done), "target": max(1, int(item.supported)),
							"icon": "maps", "color": "5ee0c8", "target_view": {"view": "map", "key": item.key}}
			"rank":
				for rank in m.roadmap:
					if str(int(rank.id)) == str(spec.key):
						var reached = int(m.xp) >= int(rank.xp)
						pin = {"name": str(rank.name), "next": "Reached" if reached else "%s XP to go" % ui.thousands(int(rank.xp) - int(m.xp)),
							"value": min(int(m.xp), int(rank.xp)), "target": max(1, int(rank.xp)), "icon": "overview",
							"color": ui.league(rank).base.to_html(false), "target_view": {"view": "roadmap"}}
		if pin == null:
			# Keep an unresolved pin visible so it can still be removed.
			pin = {"name": "Unavailable goal", "next": "No longer tracked", "value": 0, "target": 1, "icon": "pin", "color": "7099c7"}
		pin.spec = {"kind": str(spec.kind), "key": str(spec.key)}
		out.append(pin)
	return out

func _pin_button(parent, kind, key, label):
	var pinned = screen.journey_store != null and screen.journey_store.has_pin(kind, str(key))
	var b = ui.button(parent, "Unpin" if pinned else label, "secondary", screen, "toggle_pin", {"kind": kind, "key": str(key)}, "pin")
	return b

# Small pin toggle for cards; yellow when the goal is pinned.
func _pin_toggle(parent, kind, key):
	var pinned = screen.journey_store != null and screen.journey_store.has_pin(kind, str(key))
	var b = ui.button(parent, "", "primary" if pinned else "small", screen, "toggle_pin", {"kind": kind, "key": str(key)}, "pin")
	b.hint_tooltip = "Unpin" if pinned else "Pin to Overview"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

func _kind_icon(kind) -> String:
	return {"achievement": "achievements", "quest": "quests", "rank": "overview", "map": "maps", "cosmetic": "rewards", "record": "stopwatch"}.get(kind, "sparkle")

func _chip_row(parent, options, current, method):
	var row = _flow(parent, 12)
	for option in options:
		var key = option[0]
		var active = key == current
		var b = ui.button(row, option[1], "secondary" if active else "small", self, method, key)
		if active:
			b.add_font_override("font", ui.font("display", 27))
			for state in ["normal", "hover", "pressed", "focus"]:
				var s = b.get_stylebox(state).duplicate()
				s.content_margin_top = 12
				s.content_margin_bottom = 12
				s.content_margin_left = 18
				s.content_margin_right = 18
				s.set_corner_radius_all(26)
				b.add_stylebox_override(state, s)
	return row

# Wrapping row (HFlowContainer ships with 3.5; plain HBox if a build lacks it).
func _flow(parent, gap):
	if not ClassDB.class_exists("HFlowContainer"):
		return ui.box(parent, false, gap)
	var row = ClassDB.instance("HFlowContainer")
	row.add_constant_override("hseparation", gap)
	row.add_constant_override("vseparation", gap)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row

func _columns(parent, wide_cols, narrow_cols, gap = 26):
	var grid = GridContainer.new()
	grid.columns = wide_cols if screen.wide() else narrow_cols
	grid.add_constant_override("hseparation", gap)
	grid.add_constant_override("vseparation", gap)
	ui.grow(grid)
	parent.add_child(grid)
	return grid

func _observed_tag(parent):
	ui.pill(parent, "RECORDED LOCALLY", ui.WHITE, ui.NAVY_3)

# ================================================================== quests
# Day streak and its rewards (3 / 7 / 14 / 30 days in a row).
func _streak_card(parent):
	var streak = _m().get("streak")
	if streak == null:
		return
	var card = ui.card(parent)
	var row = ui.box(card, not screen.wide(), 26)
	var lead = ui.box(row, false, 16)
	ui.tile_icon(lead, "sparkle", ui.YELLOW if streak.today else ui.MUTED, 88)
	var info = ui.box(lead, true, 0)
	info.alignment = BoxContainer.ALIGN_CENTER
	info.rect_min_size.x = 230
	ui.label(info, "%d day%s" % [int(streak.current), "" if int(streak.current) == 1 else "s"], "h2", ui.YELLOW if streak.today else ui.WHITE)
	ui.label(info, "DAY STREAK", "caps", ui.MUTED)
	ui.label(info, "Played today" if streak.today else ("Play today to keep it" if int(streak.current) > 0 else "Play a round to start one"), "small", ui.GREEN_LIGHT if streak.today else ui.FAINT)
	var steps = ui.grow(ui.box(row, false, 16))
	for reward in screen.streak_rewards():
		var p = ui.well(steps, ui.NAVY_2, 18, 26)
		ui.grow(p)
		var col = ui.box(p, true, 8)
		var top = ui.box(col, false, 8)
		ui.label(top, "%d DAYS" % int(reward.days), "caps", ui.GREEN_LIGHT if reward.done else ui.MUTED)
		ui.spacer(top)
		if reward.claimed:
			ui.icon(top, "check", 28, ui.GREEN_LIGHT)
		ui.bar(col, min(1.0, float(streak.current) / float(reward.days)), ui.GREEN if reward.done else ui.YELLOW, 12)
		if reward.claimable:
			ui.button(col, "Claim " + ui.xp_text(reward.xp), "primary", screen, "claim_streak", reward, "check")
		else:
			ui.label(col, ui.xp_text(reward.xp), "h3", ui.YELLOW if not reward.claimed else ui.FAINT)

func quests(parent):
	var m = _m()
	var head = screen.section_intro(parent, "Daily & Weekly Challenges")
	var cal = ui.button(head, "Activity calendar" if screen.wide() else "", "small", screen, "open", "calendar", "calendar")
	cal.hint_tooltip = "Activity calendar"
	if m.quests == null:
		var card = ui.card(parent)
		var col = ui.box(card, true, 24)
		screen.empty_state(col, "quests", "Quests aren't connected yet", "")
		var grid = _columns(col, 4, 2)
		for category in QUEST_COLORS:
			var tile = ui.well(grid, ui.NAVY_2, 24, 30)
			ui.grow(tile)
			var row = ui.box(tile, false, 16)
			ui.tile_icon(row, {"Public Matches": "flag", "Speedrunning": "stopwatch", "Level Creation": "hammer", "Optional Challenges": "target"}[category], QUEST_COLORS[category], 72)
			ui.label(row, category, "h3")
		return
	var q = m.quests
	_streak_card(parent)
	var top = ui.box(parent, not screen.wide(), 28)
	var daily = ui.card(top)
	ui.grow(daily, true, false, 1.7)
	var col = ui.box(daily, true, 20)
	var h = ui.heading(col, "Daily challenges", "quests")
	ui.spacer(h)
	if not screen.wide():
		h = _flow(col, 12)
	if not q.get("cleared", false):
		ui.pill(h, "%d REROLL%s LEFT" % [int(q.rerolls), "" if int(q.rerolls) == 1 else "S"], ui.WHITE, ui.NAVY_3, "sparkle")
	screen.live(ui.pill(h, "", ui.INK, ui.SKY_LIGHT, "clock"), OS.get_unix_time() + int(q.reset_in), "RESETS IN %s")
	_set_track(col, q)
	var filters = [["All", "All"]]
	for category in QUEST_COLORS:
		if category != "Level Creation":
			filters.append([category, category])
	_chip_row(col, filters, quest_filter, "_quest_filter")
	var shown = 0
	for slot in q.daily.size():
		var quest = q.daily[slot]
		if quest_filter == "All" or quest.category == quest_filter:
			var row = quest_row(col, quest, false)
			shown += 1
			if not bool(quest.get("claimable", false)) and int(quest.value) < int(quest.target) and int(q.rerolls) > 0:
				var inner = row.get_child(0)
				var actions = inner.get_child(inner.get_child_count() - 1) if screen.wide() else inner.get_child(1).get_child(inner.get_child(1).get_child_count() - 1)
				ui.button(actions, "Reroll", "small", self, "_reroll", slot, "sparkle").hint_tooltip = "Swap this quest"
	if shown == 0:
		ui.label(col, "No challenges in this group", "small", ui.MUTED)
	if q.get("cleared", false):
		var done = ui.well(col, ui.GREEN.darkened(0.55), 20, 28)
		var drow = ui.box(done, false, 16)
		ui.icon(drow, "check", 40, ui.GREEN_LIGHT)
		ui.label(drow, "All daily challenges done", "h3", ui.WHITE)
		ui.spacer(drow)
		screen.live(ui.label(drow, "", "small", ui.GREEN_LIGHT), OS.get_unix_time() + int(q.reset_in), "New challenges in %s")
	# "Choose another" only while there's an unfinished challenge to swap out;
	# when that stops being true it folds away and the daily card takes the row.
	var swappable = false
	for quest in q.daily:
		swappable = swappable or int(quest.value) < int(quest.target)
	swappable = swappable and int(q.rerolls) > 0 and not q.get("cleared", false) and not q.get("choices", []).empty()
	if not swappable and not choose_shown:
		return _weekly_section(parent, q)
	var choose = ui.card(top)
	ui.grow(choose, true, false, 1.0)
	var ccol = ui.box(choose, true, 18)
	ui.heading(ccol, "Choose another", "target")
	var choices = q.get("choices", [])
	for index in choices.size():
		var quest = choices[index]
		var p = ui.well(ccol, ui.NAVY_2, 20, 28)
		var row = ui.box(p, false, 18)
		ui.tile_icon(row, str(quest.icon), QUEST_COLORS.get(str(quest.category), ui.MUTED), 72)
		var c = ui.grow(ui.box(row, true, 2))
		ui.label(c, str(quest.title), "h3")
		var meta = ui.box(c, false, 10)
		ui.label(meta, str(quest.category), "small", ui.MUTED)
		ui.pill(meta, ui.xp_text(quest.xp), ui.INK, ui.YELLOW)
		if int(q.rerolls) > 0:
			ui.button(row, "Choose", "secondary", self, "_choose", index).hint_tooltip = "Replaces your first unfinished challenge"
	if not swappable:
		choose_shown = false
		if ui.reduced_motion:
			choose.hide()
		else:
			var t = screen._tween()
			t.interpolate_property(choose, "size_flags_stretch_ratio", 1.0, 0.001, 0.45, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
			t.interpolate_property(choose, "modulate:a", 1.0, 0.0, 0.3, Tween.TRANS_QUAD, Tween.EASE_OUT)
			t.interpolate_callback(choose, 0.45, "hide")
			t.start()
	else:
		choose_shown = true
	_weekly_section(parent, q)

# Four daily sets (easy, medium, hard, expert); clearing one unlocks the next.
func _set_track(parent, q):
	var row = ui.box(parent, false, 10)
	for i in int(q.get("sets", 1)):
		var cleared = i < int(q.get("set", 0)) or q.get("cleared", false)
		var current = i == int(q.get("set", 0)) and not q.get("cleared", false)
		var diff = DIFFICULTY.get(["easy", "medium", "hard", "expert"][min(i, 3)])
		var p = PanelContainer.new()
		var style = ui.flat(diff[1] if current else (ui.GREEN_LIGHT if cleared else Color(1, 1, 1, 0.06)), 22, 16, 0, ui.INK, false)
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		p.add_stylebox_override("panel", style)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.grow(p)
		row.add_child(p)
		var inner = ui.box(p, false, 8)
		inner.alignment = BoxContainer.ALIGN_CENTER
		if cleared:
			ui.icon(inner, "check", 26, ui.INK)
		elif not current:
			ui.icon(inner, "lock", 24, ui.FAINT)
		ui.label(inner, diff[0], "caps", ui.INK if current or cleared else ui.FAINT, Label.ALIGN_CENTER)

func _weekly_section(parent, q):
	var weekly = ui.card(parent)
	var wcol = ui.box(weekly, true, 22)
	var wh = ui.heading(wcol, "Weekly challenges", "crown")
	ui.spacer(wh)
	screen.live(ui.pill(wh, "", ui.INK, ui.SKY_LIGHT, "clock"), OS.get_unix_time() + int(q.weekly_reset_in), "%s LEFT")
	var grid = _columns(wcol, 3, 1)
	for quest in q.weekly:
		_challenge_card(grid, quest)
	_week_strip(parent)

# Quest claims carry {quest, xp}; the XP owner awards it, then calls
# journey_store.mark_quest(quest).
func _claim_quest(arg):
	screen.claim_quest(arg.quest, arg.row)

func _reroll(slot):
	screen.request("reroll", slot)

func _choose(index):
	screen.request("choose_quest", index)

func _quest_filter(key):
	quest_filter = key
	screen.refresh()

func _challenge_card(parent, quest):
	var color = QUEST_COLORS.get(str(quest.category), ui.MUTED)
	var done = int(quest.value) >= int(quest.target)
	var p = ui.well(parent, ui.NAVY_2, 28, 34)
	ui.grow(p)
	var col = ui.box(p, true, 14)
	var top = ui.box(col, false, 14)
	ui.tile_icon(top, str(quest.icon), color, 84)
	ui.spacer(top)
	_pin_toggle(top, "quest", str(quest.id))
	var diff = DIFFICULTY.get(str(quest.difficulty), DIFFICULTY.medium)
	ui.pill(top, diff[0], ui.INK, diff[1])
	ui.label(col, str(quest.title), "h2")
	ui.label(col, str(quest.detail), "small", ui.MUTED)
	var line = ui.box(col, false, 14)
	var b = ui.bar(line, float(quest.value) / max(1, int(quest.target)), ui.GREEN if done else color, 22)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.label(line, "%d / %d" % [int(quest.value), int(quest.target)], "button", ui.MUTED)
	var foot = ui.box(col, false, 12)
	ui.label(foot, ui.xp_text(quest.xp), "num_m", ui.YELLOW)
	ui.spacer(foot)
	if bool(quest.get("claimable", false)):
		ui.button(foot, "Claim " + ui.xp_text(quest.xp), "primary", self, "_claim_quest", {"quest": quest, "row": p}, "check")
	elif bool(quest.get("claimed", false)):
		ui.pill(foot, "CLAIMED", ui.INK, ui.GREEN_LIGHT, "check")
	elif done:
		ui.pill(foot, "COMPLETE", ui.INK, ui.GREEN_LIGHT, "check")

func _week_strip(parent):
	var m = _m()
	var card = ui.card(parent)
	var col = ui.box(card, true, 18)
	var h = ui.heading(col, "This week", "calendar")
	ui.spacer(h)
	ui.button(h, "Open calendar", "small", screen, "open", "calendar", "chevron_right")
	var row = ui.box(col, false, 16 if screen.wide() else 8)
	var today = m.days.size() - 1
	for i in m.days.size():
		var day = m.days[i]
		var cell = ui.well(row, ui.PINK.darkened(0.35) if i == today else ui.NAVY_2, 18, 26 if screen.wide() else 6)
		ui.grow(cell)
		var c = ui.box(cell, true, 2)
		c.alignment = BoxContainer.ALIGN_CENTER
		ui.label(c, _weekday(day.start), "caps", ui.WHITE if i == today else ui.MUTED, Label.ALIGN_CENTER)
		ui.label(c, (ui.thousands(day.xp) if screen.wide() else _compact(day.xp)) if int(day.xp) > 0 else "—", "num_m" if screen.wide() else "h3", ui.YELLOW if int(day.xp) > 0 else ui.FAINT, Label.ALIGN_CENTER)
		ui.label(c, "XP", "small", ui.MUTED, Label.ALIGN_CENTER)

func _compact(n) -> String:
	n = int(n)
	if n >= 10000:
		return "%dk" % int(n / 1000)
	if n >= 1000:
		return ("%.1fk" % (n / 1000.0)).replace(".0k", "k")
	return str(n)

func _weekday(timestamp) -> String:
	var d = OS.get_datetime_from_unix_time(int(timestamp) + ui._utc_offset())
	return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][int(d.weekday)]
