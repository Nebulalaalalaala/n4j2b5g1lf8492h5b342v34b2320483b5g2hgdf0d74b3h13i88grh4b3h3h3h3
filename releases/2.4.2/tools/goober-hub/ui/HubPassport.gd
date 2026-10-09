extends "user://mod/tools/goober-hub/ui/HubPage.gd"
const TABS = ["Overview", "Seasons", "Encounters"]
const STAMP_COLORS = {"winter": Color("7cc4ff"), "spring": Color("9be15d"), "summer": Color("ffd34d"), "autumn": Color("ff8a5c")}

func build(content):
	if hub.store.account.empty():
		ui.empty(content, "Sign in to GooberDash", "", "compass", ui.MINT)
		return
	ui.choice(content, TABS, screen.passport_tab, self, "_tab")
	if screen.passport_tab == "Overview":
		overview(content)
		_latest_season(content)
	elif screen.passport_tab == "Seasons":
		_seasons(content)
	else:
		_encounters(content)

func _tab(value):
	screen.passport_tab = value
	screen._load_page()
	screen.render()

func _since() -> int:
	var r = hub.profiles.row(hub.store.account)
	var since = load(ModPaths.path("HubFeed.gd")).unix(r.get("member_since", "")) if r.get("member_since") != null else 0
	if since <= 0:
		for record in hub.history_records():
			since = int(record.date) if since <= 0 else min(since, int(record.date))
	return since

func overview(parent):
	var me = hub.store.account
	var book = ui.surface(parent, Color("123d5c"), 26, 30)
	var col = ui.box(book, true, 18)
	var head = ui.box(col, false, 14)
	ui.tile_icon(head, "compass", ui.MINT, 64)
	var words = ui.box(head, true, 0)
	ui.grow(words)
	var title = ui.title(words, hub.profiles.name_for(me).to_upper() + "'S PASSPORT", 40)
	title.add_color_override("font_color_shadow", ui.BASE)
	title.add_constant_override("shadow_offset_y", 3)
	ui.text(words, "GooberDash history", 17, ui.SOFT)
	var records = hub.history_records()
	var maps = {}
	var seconds = 0.0
	for r in records:
		maps[str(r.map_id)] = true
		seconds += float(r.play_seconds)
	var games = hub.profiles.stat(me, hub.profiles.stat_key("Stat_GamesPlayed"))
	var wins = hub.profiles.stat(me, hub.profiles.stat_key("Stat_GamesWon"))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_constant_override("hseparation", 12)
	grid.add_constant_override("vseparation", 12)
	ui.grow(grid)
	col.add_child(grid)
	var since = _since()
	# Active time: Journey play/editor time (nothing after 5 idle minutes) plus earlier play from Calculate XP.
	var activity = hub.journey.activity.snapshot() if is_instance_valid(hub.journey) and hub.journey.get("activity") != null and str(hub.journey.activity.account_id) == me else {}
	grid.columns = 4
	for item in [[ui.month_year(since) if since > 0 else "-", "Playing since", ui.MINT, "calendar"],
			[ui.thousands(games) if games > 0 else "-", "Matches", ui.WHITE, "play"],
			[ui.thousands(wins) if wins > 0 else "-", "Wins", ui.GOLD, "crown"],
			[ui.thousands(maps.size()), "Unique maps", ui.SKY, "maps"],
			[ui.thousands(hub.store.data.players.size()), "Players encountered", ui.HUB_PINK, "goober"],
			[ui.duration(seconds), "Round time", ui.LILAC, "stopwatch"],
			[ui.duration(int(activity.get("lifetime_seconds", 0))) if not activity.empty() else "-", "Active time", ui.MINT, "clock"],
			[ui.duration(int(activity.get("today_seconds", 0))) if not activity.empty() else "-", "Active today", ui.SKY, "session"]]:
		var tile = ui.stat(grid, item[0], item[1], item[2], item[3])
		tile.rect_min_size.x = 200
	var oldest = int(hub.store.data.get("since", 0))
	ui.text(col, "Encounters and seasons recorded since %s" % ui.date_text(oldest), 15, ui.DIM)

# Rounds and wins per season from Profile+ history; players and Journey peak from the Hub's notes.
func season_list() -> Array:
	var by = {}
	var store_class = load(ModPaths.path("HubStore.gd"))
	for r in hub.history_records():
		var key = store_class.season_key(int(r.date))
		var s = by.get(key, {"key": key, "rounds": 0, "wins": 0, "maps": {}, "seconds": 0.0})
		s.rounds += 1
		s.wins += int(r.win)
		s.seconds += float(r.play_seconds)
		s.maps[str(r.map_name)] = int(s.maps.get(str(r.map_name), 0)) + 1
		by[key] = s
	for key in hub.store.data.seasons:
		if not by.has(key):
			by[key] = {"key": key, "rounds": 0, "wins": 0, "maps": {}, "seconds": 0.0}
	var list = []
	for key in by:
		var s = by[key]
		var notes = hub.store.data.seasons.get(key, {})
		s.peak = str(notes.get("peak_rank", ""))
		s.peak_xp = int(notes.get("peak_xp", 0))
		s.most_map = _top(s.maps)
		s.most_with = _top(notes.get("with", {}))
		s.most_with_count = int(notes.get("with", {}).get(s.most_with, 0)) if not s.most_with.empty() else 0
		list.append(s)
	list.sort_custom(self, "_newer")
	return list

func _top(counts) -> String:
	var best = ""
	var n = 0
	for k in counts:
		if int(counts[k]) > n:
			n = int(counts[k])
			best = str(k)
	return best

func _newer(a, b):
	return a.key > b.key

func _latest_season(parent):
	var list = season_list()
	if not list.empty():
		_season_card(parent, list[0], true)

func _seasons(parent):
	var list = season_list()
	if list.empty():
		ui.empty(parent, "No seasons yet", "", "calendar", ui.MINT)
		return
	for s in list:
		_season_card(parent, s, false)

func _season_card(parent, s, current):
	var season_name = str(s.key).split("-")[2] if str(s.key).split("-").size() == 3 else "winter"
	var color = STAMP_COLORS.get(season_name, ui.MINT)
	var card = ui.surface(parent, ui.PANEL, 22, 26)
	var row = ui.box(card, false, 22)
	var stamp = ui.inset(row, 14, 22, color.darkened(0.45))
	stamp.rect_min_size = Vector2(190, 0)
	var sc = ui.box(stamp, true, 2)
	sc.alignment = BoxContainer.ALIGN_CENTER
	var parts = load(ModPaths.path("HubStore.gd")).season_title(s.key).split(" ")
	ui.title(sc, parts[0], 30, color).align = Label.ALIGN_CENTER
	ui.title(sc, parts[1] if parts.size() > 1 else "", 38, ui.WHITE).align = Label.ALIGN_CENTER
	if current and s.key == load(ModPaths.path("HubStore.gd")).season_key(OS.get_unix_time()):
		ui.text(sc, "This season", 14, ui.SOFT).align = Label.ALIGN_CENTER
	var col = ui.box(row, true, 12)
	ui.grow(col)
	var stats = ui.box(col, false, 10)
	ui.stat(stats, ui.thousands(s.rounds), "Rounds", ui.WHITE)
	ui.stat(stats, ui.thousands(s.wins), "Wins", ui.GOLD)
	ui.stat(stats, ui.duration(s.seconds), "Playtime", ui.LILAC)
	var facts = ui.box(col, false, 10)
	for fact in [["Most played", s.most_map if not s.most_map.empty() else "-", "maps"],
			["Journey peak", s.peak if not s.peak.empty() else "-", "xp"],
			["Most played with", hub.profiles.name_for(s.most_with) + (" (%d)" % s.most_with_count) if not s.most_with.empty() else "-", "goober"]]:
		var f = ui.inset(facts, 14, 18)
		ui.grow(f)
		var fc = ui.box(f, true, 2)
		var top = ui.box(fc, false, 8)
		ui.icon(top, fact[2], 20, color)
		ui.text(top, fact[0], 15, ui.DIM)
		var value = ui.title(fc, str(fact[1]), 22)
		value.clip_text = true
		if fact[0] == "Most played with" and not s.most_with.empty():
			ui.clickable(f, screen, "show_profile", s.most_with, ui.EDGE)

func _encounters(parent):
	var list = hub.store.encounters()
	if list.empty():
		ui.empty(parent, "No encounters yet", "Players you meet in online matches show up here.", "goober", ui.HUB_PINK)
		return
	ui.section(parent, "Encounters", "goober", "%d players" % list.size(), ui.HUB_PINK)
	for e in list.slice(0, min(60, list.size()) - 1):
		hub.profiles.remember(e.id, e.name)
		var card = ui.surface(parent, ui.PANEL, 16, 22)
		ui.clickable(card, screen, "show_profile", e.id, ui.INSET)
		var row = ui.box(card, false, 16)
		ui.goober(row, hub.profiles.look_for(e.id), 56, e.id)
		var words = ui.box(row, true, 2)
		ui.grow(words)
		ui.title(words, hub.profiles.name_for(e.id), 24)
		ui.text(words, "First encountered %s · last %s" % [ui.month_year(e.first), ui.ago(e.last)], 15, ui.DIM)
		for item in [[e.matches, "Matches together", ui.WHITE], [e.you_won, "You won", ui.GOLD], [e.they_won, "They won", ui.HUB_PINK]]:
			var cell = ui.box(row, true, 0)
			cell.rect_min_size.x = 120
			ui.title(cell, str(int(item[0])), 30, item[2]).align = Label.ALIGN_CENTER
			ui.text(cell, item[1], 14, ui.DIM).align = Label.ALIGN_CENTER
