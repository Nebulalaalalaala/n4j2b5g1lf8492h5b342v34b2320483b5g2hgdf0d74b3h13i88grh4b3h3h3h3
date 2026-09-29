extends "user://mod/tools/journey/ui/JourneyScreen/02_nav_toggle.gd"

func _style_scrollbar(target):
	var bar = target.get_v_scrollbar()
	var track = ui.flat(Color(0, 0.1, 0.25, 0.35), 8, 0, 0, ui.INK, false)
	var grab = ui.flat(Color(1, 1, 1, 0.55), 8, 0, 0, ui.INK, false)
	bar.add_stylebox_override("scroll", track)
	bar.add_stylebox_override("grabber", grab)
	bar.add_stylebox_override("grabber_highlight", grab)
	bar.add_stylebox_override("grabber_pressed", grab)
	bar.rect_min_size.x = 14

func _banners(parent):
	if model.preview:
		var p = ui.card(parent, ui.PINK.darkened(0.25), 22, 32)
		var row = ui.box(p, false, 16)
		ui.icon(row, "sparkle", 40)
		ui.label(row, "DESIGN PREVIEW", "caps")
		ui.grow(ui.label(row, "Sample data for reviewing layouts. None of this is your progress, and nothing is saved.", "small"))
		ui.button(row, "Exit preview", "small", self, "_toggle_design_preview")
	if not model.preview and journey_store.writable and not journey_store.test.empty():
		var p = ui.card(parent, Color("3b2a78"), 22, 32)
		var row = ui.box(p, false, 16)
		ui.icon(row, "target", 40, ui.YELLOW)
		ui.label(row, "TEST MODE", "caps", ui.YELLOW)
		ui.grow(ui.label(row, "Test XP and completions are shown. Your real progress is unchanged.", "small"))
		ui.button(row, "Test tools", "small", self, "_open_tools")
		ui.button(row, "Reset to normal", "small", self, "test_reset")
	if not model.signed_in or str(model.error) != "":
		var p = ui.card(parent, Color("5a3a07"), 22, 32)
		var row = ui.box(p, false, 16)
		ui.icon(row, "lock", 40, ui.YELLOW)
		ui.grow(ui.label(row, str(model.error) if str(model.error) != "" else "Sign in to save Journey progress.", "body", Color("ffe7a8")))

func _strip(parent):
	var p = PanelContainer.new()
	var s = ui.flat(Color(0, 0.13, 0.28, 0.72), 36, 24, 0, ui.INK, false)
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	p.add_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return ui.box(p, false, 20)

# Detail views: back button, title and context on one strip. Returns the row
# so callers can append actions on the right.
func back_row(parent, title, subtitle = ""):
	var row = _strip(parent)
	ui.button(row, "Back", "small", self, "back", null, "back")
	var col = ui.grow(ui.box(row, true, 0))
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(col, title, "h1")
	if subtitle != "":
		ui.label(col, subtitle, "small", ui.MUTED)
	return row

# Section intro: icon, one line of context, and room for actions.
func section_intro(parent, subtitle):
	var row = _strip(parent)
	ui.tile_icon(row, SECTION_ICONS.get(section, "overview"), ui.SKY_LIGHT, 72)
	var col = ui.grow(ui.box(row, true, 0))
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(col, section, "h2")
	ui.label(col, subtitle, "small", ui.MUTED)
	_rank_chip(row)
	return row

# Current rank and XP on every section header, so progress is always in view.
func _rank_chip(parent):
	if model.get("rank") == null:
		return
	var rank = model.rank
	var lg = ui.league(rank)
	var chip = PanelContainer.new()
	chip.add_stylebox_override("panel", ui.flat(Color(1, 1, 1, 0.05), 30, 14, 0, ui.INK, false))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(chip)
	ui.clickable(chip, self, "open", "roadmap")
	chip.hint_tooltip = "Rank roadmap"
	var row = ui.box(chip, false, 14)
	ui.badge(row, rank, 72)
	var col = ui.box(row, true, 4)
	col.alignment = BoxContainer.ALIGN_CENTER
	var top = ui.box(col, false, 12)
	ui.label(top, str(rank.name), "h3", ui.WHITE).autowrap = false
	ui.label(top, ui.thousands(model.xp) + " XP", "small", lg.light).autowrap = false
	if wide():
		var span = max(1, int(rank.next_xp) - int(rank.xp))
		var b = _xp_bar(ui.bar(col, float(int(model.xp) - int(rank.xp)) / span, lg.base, 14, Color(0, 0.04, 0.12, 0.5)), rank)
		b.rect_min_size.x = 260

# ------------------------------------------------------------------ overview
func _overview(parent):
	_claim_banner(parent)
	var top = ui.box(parent, not wide(), 28)
	_hero(top)
	var side = ui.box(top, true, 28)
	ui.grow(side, true, false, 1.0)
	_today(side)
	_next_unlock(side)
	var middle = ui.box(parent, not wide(), 28)
	_quests_card(middle)
	_pins_card(middle)
	_quick_links(parent)

func _claim_banner(parent):
	var claimable = claimables()
	if claimable.empty():
		return
	var total = 0
	for item in claimable:
		total += int(item.get("xp", 0))
	var p = ui.card(parent, ui.NAVY, 20, 36)
	var row = ui.box(p, false, 18)
	ui.tile_icon(row, "sparkle", ui.YELLOW, 72)
	var col = ui.grow(ui.box(row, true, 0))
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(col, "%d reward%s ready to claim" % [claimable.size(), "" if claimable.size() == 1 else "s"], "h3", ui.WHITE)
	ui.label(col, ui.xp_text(total) + " waiting in your inbox", "small", ui.YELLOW)
	var actions = row if wide() else ui.box(col, false, 14)
	if not wide():
		ui.spacer(col, 0, 6)
		col.move_child(actions, col.get_child_count() - 1)
	ui.button(actions, "Open inbox", "secondary", self, "_open_inbox")
	ui.button(actions, "Claim all", "primary", self, "claim_all", null, "check")

func _hero(parent):
	var rank = model.rank
	var lg = ui.league(rank)
	var card = ui.card(parent, ui.NAVY.linear_interpolate(lg.deep, 0.22), 40, 52)
	ui.grow(card, true, false, 1.7)
	var col = ui.box(card, true, 30)
	var top = ui.box(col, false, 36)
	ui.badge(top, rank, 400 if wide() else 280, true, true)
	var info = ui.grow(ui.box(top, true, 12))
	info.alignment = BoxContainer.ALIGN_CENTER
	ui.label(info, "JOURNEY RANK", "caps", lg.light)
	var name = ui.label(info, str(rank.name).to_upper(), "hero")
	if not wide() or str(rank.name).length() > 12:
		name.add_font_override("font", ui.font("display", 72))
	var xp_row = ui.box(info, false, 12)
	ui.icon(xp_row, "xp", 34, lg.base)
	ui.label(xp_row, ui.thousands(model.xp), "num_m")
	ui.label(xp_row, "Journey XP", "small", ui.MUTED)
	var span = max(1, int(rank.next_xp) - int(rank.xp))
	var into = int(model.xp) - int(rank.xp)
	_xp_bar(ui.bar(info, float(into) / span, lg.base, 40, Color(0, 0.04, 0.12, 0.5)), rank)
	var captions = ui.box(info, false, 12)
	ui.label(captions, "%s / %s XP" % [ui.thousands(into), ui.thousands(span)], "small", ui.MUTED)
	ui.spacer(captions)
	ui.label(captions, "%s XP to %s" % [ui.thousands(int(rank.next_xp) - int(model.xp)), model.next.name], "small", lg.light, Label.ALIGN_RIGHT)
	var divider = ColorRect.new()
	divider.color = Color(1, 1, 1, 0.08)
	divider.rect_min_size.y = 3
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(divider)
	var path_row = ui.box(col, not wide(), 24)
	_division_path(path_row)
	var actions = ui.box(path_row, true, 12)
	actions.alignment = BoxContainer.ALIGN_CENTER
	ui.button(actions, "Rank roadmap", "secondary", self, "open", "roadmap", "chevron_right")

# The current league's three divisions and the next step beyond them.
func _division_path(parent):
	var rank = model.rank
	var steps = []
	var roadmap = model.roadmap
	var index = 0
	for i in roadmap.size():
		if int(roadmap[i].id) == int(rank.id):
			index = i
	var start = index
	if str(rank.league) != "King League":
		start = index - int(rank.id) % 3
	else:
		start = max(0, index - 1)
	for i in range(start, min(roadmap.size(), start + 4)):
		steps.append(roadmap[i])
	var row = ui.grow(ui.box(parent, false, 0))
	for i in steps.size():
		var step = steps[i]
		var done = int(model.xp) >= int(step.next_xp)
		var current = int(step.id) == int(rank.id)
		if i > 0:
			var line = ui.bar(row, 1.0 if done or current else 0.0, ui.league(step).base, 10, Color(1, 1, 1, 0.12))
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.rect_min_size.x = 24
		var node = ui.box(row, true, 4)
		node.alignment = BoxContainer.ALIGN_CENTER
		var badge = ui.badge(node, step, 132 if current else 104)
		if not done and not current:
			badge.modulate = Color(1, 1, 1, 0.5)
		var caption = ui.label(node, str(step.name), "small", ui.WHITE if current else ui.MUTED, Label.ALIGN_CENTER)
		caption.autowrap = false
		if current:
			caption.add_font_override("font", ui.font("display", 28))

func _today(parent):
	var card = ui.card(parent)
	var col = ui.box(card, true, 22)
	ui.heading(col, "Today", "clock", ui.xp_text(model.today_xp) + " today" if model.today_xp > 0 else "No Journey XP yet today", ui.YELLOW if model.today_xp > 0 else ui.MUTED)
	var activity = model.activity
	var row = ui.box(col, false, 22)
	ui.label(row, ui.duration(activity.today_seconds) if activity != null else "—", "num_xl")
	var captions = ui.grow(ui.box(row, true, 2))
	captions.alignment = BoxContainer.ALIGN_CENTER
	ui.label(captions, "ACTIVE TIME", "caps", ui.MUTED)
	if activity == null:
		ui.label(captions, "Not tracked yet", "small", ui.FAINT)
	elif bool(activity.get("inactive", false)):
		ui.pill(captions, "Idle", ui.WHITE, ui.NAVY_3, "clock")
	elif activity.get("open_seconds") != null:
		ui.label(captions, "App open " + ui.duration(activity.open_seconds), "small", ui.FAINT)
	if activity != null and int(activity.get("legacy_seconds",0))>0:
		var legacy_label = ui.label(captions, "Earlier tracked time: " + ui.duration(activity.legacy_seconds), "small", ui.FAINT)
		legacy_label.hint_tooltip = "Preserved input-based history. New Activity XP uses verified gameplay/editor time; previously earned XP is unchanged."
	var streak = model.get("streak")
	if streak != null and int(streak.current) > 0:
		var srow = ui.box(row, true, 0)
		srow.alignment = BoxContainer.ALIGN_CENTER
		var top = ui.box(srow, false, 8)
		ui.icon(top, "sparkle", 36, ui.YELLOW if streak.today else ui.MUTED)
		ui.label(top, str(streak.current), "num_m", ui.YELLOW if streak.today else ui.WHITE)
		ui.label(srow, "DAY STREAK", "caps", ui.MUTED, Label.ALIGN_RIGHT)
		ui.label(srow, "Best %d" % int(streak.best), "small", ui.FAINT, Label.ALIGN_RIGHT)
	_milestones(col, activity)

func _milestones(parent, activity):
	var seconds = int(activity.today_seconds) if activity != null else -1
	var row = ui.box(parent, false, 0)
	var next_text = ""
	var steps = model.activity_milestones
	for i in steps.size():
		var step = steps[i]
		var done = seconds >= int(step.seconds)
		var is_next = seconds >= 0 and not done and (i == 0 or seconds >= int(steps[i - 1].seconds))
		if i > 0:
			var line = ui.bar(row, 1.0 if done else 0.0, ui.GREEN, 8, Color(1, 1, 1, 0.1))
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.rect_min_size.x = 18
			line.rect_min_size.y = 8
			line.size_flags_vertical = 0
		var node = ui.box(row, true, 6)
		node.alignment = BoxContainer.ALIGN_CENTER
		var dot = PanelContainer.new()
		var color = ui.GREEN if done else (ui.YELLOW if is_next else ui.NAVY_2)
		var s = ui.flat(color, 30, 0, 0, ui.INK, false)
		if is_next:
			s.bg_color = ui.NAVY_2
			s.border_color = ui.YELLOW
			s.border_width_left = 5
			s.border_width_right = 5
			s.border_width_top = 5
			s.border_width_bottom = 5
		dot.add_stylebox_override("panel", s)
		dot.rect_min_size = Vector2(60, 60)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		node.add_child(dot)
		var c = CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_child(c)
		if done:
			ui.icon(c, "check", 30, ui.INK)
		var mins = int(step.seconds) / 60
		ui.label(node, ("%dh" % (mins / 60)) if mins >= 60 else ("%dm" % mins), "button", ui.WHITE if done or is_next else ui.MUTED, Label.ALIGN_CENTER)
		ui.label(node, "+" + ui.thousands(step.xp), "small", ui.YELLOW if is_next else ui.FAINT, Label.ALIGN_CENTER).autowrap = false
		if is_next:
			next_text = "Next: %s active · +%s XP" % [ui.duration(step.seconds), ui.thousands(step.xp)]
	var total = 0
	for step in steps:
		total += int(step.xp)
	var ready = 0
	for reward in playtime_rewards():
		ready += int(reward.xp) if reward.claimable else 0
	if ready > 0:
		var claim = ui.button(parent, "Claim " + ui.xp_text(ready), "primary", self, "claim_playtime", null, "check")
		claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.label(parent, next_text if next_text != "" else "Daily playtime rewards · up to %s XP" % ui.thousands(total), "small", ui.MUTED)

func _next_unlock(parent):
	var card = ui.card(parent)
	var col = ui.box(card, true, 18)
	ui.heading(col, "Next unlock", "sparkle")
	var target = model.next_league
	if target.empty():
		target = model.next
	var row = ui.box(col, false, 26)
	ui.badge(row, target, 150)
	var info = ui.grow(ui.box(row, true, 8))
	info.alignment = BoxContainer.ALIGN_CENTER
	ui.label(info, str(target.name), "h2", ui.league(target).light)
	var reward = _reward_for_rank(target)
	ui.label(info, (reward + " · " if reward != "" else "") + ("New league at %s XP" % ui.thousands(target.xp) if str(target.league) != str(model.rank.league) else "Next division at %s XP" % ui.thousands(target.xp)), "small", ui.MUTED)
	var from = int(model.rank.xp)
	ui.bar(info, float(int(model.xp) - from) / max(1, int(target.xp) - from), ui.league(target).base, 22)
	ui.label(info, "%s XP to go" % ui.thousands(int(target.xp) - int(model.xp)), "small", ui.WHITE)

func _reward_for_rank(rank) -> String:
	if model.cosmetics == null:
		return ""
	for list in [model.cosmetics.get("themes", []), model.cosmetics.get("finishes", [])]:
		for item in list:
			if str(item.get("requirement", "")) == "Reach " + str(rank.name):
				return str(item.name) + (" theme" if list == model.cosmetics.get("themes", []) else " finish")
	return ""

func _quests_card(parent):
	var card = ui.card(parent)
	ui.grow(card, true, false, 1.7)
	var col = ui.box(card, true, 20)
	var quests = model.quests
	var qh = ui.heading(col, "Daily challenges", "quests", "")
	if quests != null and quests.has("reset_in"):
		var label = ui.label(qh, "", "small", ui.MUTED)
		live(label, OS.get_unix_time() + int(quests.reset_in), ("Set %d of %d · " % [int(quests.get("set", 0)) + 1, int(quests.get("sets", 1))] if not quests.get("cleared", false) else "All done · ") + "resets in %s")
	if quests == null:
		empty_state(col, "quests", "Daily challenges aren't connected yet", "")
		return
	for quest in quests.daily:
		pages.quest_row(col, quest, true)
	var foot = ui.box(col, false, 12)
	ui.spacer(foot)
	ui.button(foot, "All quests", "small", self, "_select_section", "Quests", "chevron_right")

func _pins_card(parent):
	var card = ui.card(parent)
	ui.grow(card, true, false, 1.0)
	var col = ui.box(card, true, 18)
	var pins = model.pins
	ui.heading(col, "Pinned goals", "pin", ("%d / 3" % pins.size()) if pins != null else "")
	if pins == null:
		empty_state(col, "pin", "Pinning isn't connected yet", "")
		return
	for pin in pins:
		pages.pin_row(col, pin)
	for i in range(pins.size(), 3):
		var slot = ui.well(col, Color(1, 1, 1, 0.04))
		ui.clickable(slot, self, "_select_section", "Maps" if i % 2 == 0 else "Achievements")
		var row = ui.box(slot, false, 16)
		ui.icon(row, "pin", 36, ui.FAINT)
		var text = ui.grow(ui.box(row, true, 2))
		ui.label(text, "Empty slot", "small", ui.MUTED)
		ui.label(text, "Tap the pin on a map or achievement to track it here", "small", ui.FAINT)

func _quick_links(parent):
	var stats = model.stats
	var links = [
		["Statistics", "session", "%s recorded matches" % ui.thousands(stats.all.observed) if stats != null else "Recorded match history", "stats", Color("7fb4ff")],
		["Session summary", "flag", _session_caption(), "session", Color("5ee0c8")],
		["Career", "activity", ui.xp_text(model.today_xp) + " today" if model.today_xp > 0 else "Playtime, stats and calendar", "Career", Color("8af0b4")],
		["Rank roadmap", "overview", "Every division to King League", "roadmap", ui.league(model.rank).base],
		["Leaderboard", "podium", "Top Journey XP", "leaderboard", Color("ffc40f")],
		["Preferences", "gear", "Sounds, motion, notifications", "prefs", Color("ff7ed3")],
	]
	var grid = GridContainer.new()
	grid.columns = 6 if wide() else 2
	grid.add_constant_override("hseparation", 24)
	grid.add_constant_override("vseparation", 24)
	ui.grow(grid)
	parent.add_child(grid)
	for link in links:
		var tile = ui.card(grid, ui.NAVY, 26, 36)
		ui.grow(tile)
		ui.clickable(tile, self, "_quick_link", link[3])
		var row = ui.box(tile, false, 18)
		ui.tile_icon(row, link[1], link[4], 76)
		var col = ui.grow(ui.box(row, true, 0))
		col.alignment = BoxContainer.ALIGN_CENTER
		ui.label(col, link[0], "h3")
		ui.label(col, link[2], "small", ui.MUTED)

# Latest session (rounds with no 30-minute gap), not just since the game opened.
func _session_caption() -> String:
	var sessions = model.get("sessions")
	if sessions == null or sessions.empty():
		return "Your latest session"
	var latest = sessions[0]
	var rounds = int(latest.get("rounds", latest.get("matches", 0)))
	var live = OS.get_unix_time() - int(latest.end) <= session_rules.GAP
	return "%d round%s · %s" % [rounds, "" if rounds == 1 else "s", "playing now" if live else ui.date_text(int(latest.end))]

func _quick_link(target):
	if target == "Career":
		_select_section("Career")
	elif target == "prefs":
		_open_prefs()
	else:
		open(target)

func empty_state(parent, icon_key, title, detail):
	var p = ui.well(parent, Color(1, 1, 1, 0.04), 30, 32)
	ui.grow(p, true, true)
	var row = ui.box(p, false, 26)
	ui.tile_icon(row, icon_key, ui.MUTED, 92)
	var col = ui.grow(ui.box(row, true, 4))
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(col, title, "h3", ui.WHITE)
	if detail != "":
		ui.label(col, detail, "small", ui.MUTED)
	return p

func claim_sections() -> Dictionary:
	var out = {}
	if model == null or model.empty() or model.get("preview", false) or journey_store == null or not journey_store.writable:
		return out
	var n = 0
	if model.get("quests") != null:
		for q in model.quests.daily + model.quests.weekly:
			if bool(q.get("done", false)) and not bool(q.get("claimed", false)):
				n += 1
	for r in streak_rewards():
		n += int(bool(r.claimable))
	out["Quests"] = int(out.get("Quests", 0)) + n
	n = 0
	for r in playtime_rewards():
		n += int(bool(r.get("claimable", false)))
	out["Overview"] = int(out.get("Overview", 0)) + n
	# Other inbox claims (milestones …) count towards the section they open.
	for item in claimables():
		if not str(item.get("kind", "")) in ["quest", "achievement"]:
			var target = item.get("target", {})
			var where = str(target.get("section", "Overview")) if target is Dictionary else "Overview"
			if not where in SECTIONS:
				where = "Overview"
			out[where] = int(out.get(where, 0)) + 1
	n = 0
	for item in pages._map_items():
		n += int(int(item.claim_xp) > 0)
	out["Maps"] = int(out.get("Maps", 0)) + n
	n = 0
	if model.get("achievements") != null:
		for c in model.achievements.collections:
			if bool(c.get("claimable", false)) and journey_store.claimed_tier(c.key) < int(c.get("tier", 0)):
				n += 1
	var built = model.get("builder")
	if built != null and built.get("levels") != null:
		for level in built.levels:
			if bool(level.get("certified", false)) and not journey_store.flag("certified:" + str(level.id)):
				n += 1
	out["Achievements"] = int(out.get("Achievements", 0)) + n
	return out

func claim_total() -> int:
	var total = 0
	for key in claim_counts:
		total += int(claim_counts[key])
	return total
