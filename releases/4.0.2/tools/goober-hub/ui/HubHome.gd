extends "user://mod/tools/goober-hub/ui/HubPage.gd"

func build(content):
	var cols = columns(content)
	_activity(cols[0])
	_week(cols[1])
	_friends(cols[1])
	_clan(cols[1])

func _activity(parent):
	var head = ui.section(parent, "Activity", "activity", "", ui.HUB_PINK)
	ui.choice(head, ["Friends & clan", "Everyone"], screen.feed_scope, self, "_scope")
	if offline_note(parent):
		return
	var scope = "friends" if screen.feed_scope == "Friends & clan" else "everyone"
	var list = hub.feed.events[scope]
	if hub.feed.status[scope] == "loading" and list.empty():
		ui.empty(parent, "Loading activity", "", "session", ui.SKY)
		return
	if list.empty():
		if scope == "friends":
			ui.empty(parent, "Nothing here yet", "Rank-ups, new badges, records and milestones from you, your friends and your clan show up here.", "activity")
		else:
			ui.empty(parent, "Nothing here yet", "", "activity")
		return
	for e in list.slice(0, min(30, list.size()) - 1):
		event_card(parent, e)

func _scope(value):
	screen.feed_scope = value
	if value == "Everyone":
		hub.feed.fetch("everyone")
	screen.render()

func _week(parent):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 14)
	ui.section(col, "This week", "calendar", "", ui.MINT)
	var since = OS.get_unix_time() - 7 * 86400
	var rounds = 0
	var wins = 0
	for r in hub.history_records():
		if int(r.date) >= since:
			rounds += 1
			wins += int(r.win)
	var met = 0
	for e in hub.store.encounters():
		if int(e.first) >= since:
			met += 1
	var stats = ui.box(col, false, 10)
	ui.stat(stats, rounds, "Rounds", ui.WHITE)
	ui.stat(stats, wins, "Wins", ui.GOLD)
	ui.stat(stats, met, "New faces", ui.MINT)
	ui.action(col, "Open Passport", screen, "select", "Passport", "quiet", "compass", ui.MINT)

func _friends(parent):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 10)
	var list = hub.friends()
	var online = 0
	for f in list:
		online += int(f.online)
	ui.section(col, "Friends", "goober", "%d online" % online if not list.empty() else "", ui.SKY)
	if list.empty():
		ui.wrap(col, "Add friends in Friends & party (F1) to see them here.", 17, ui.DIM)
		return
	for f in list.slice(0, min(8, list.size()) - 1):
		var detail = ("Online" + (" · " + f.status if not f.status.empty() else "")) if f.online else "Offline"
		player_row(col, f.id, detail, [["", screen, "message", f.id, "quiet", "inbox"]])
	if list.size() > 8:
		ui.action(col, "All friends", screen, "select", "Messages", "quiet", "chevron_right", ui.SKY)

func _clan(parent):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 12)
	ui.section(col, "Clan", "crown", "", ui.LILAC)
	var clan = hub.clans.clans.get(hub.clans.mine, {})
	if clan.empty():
		ui.wrap(col, "Play under a clan tag, see your clan's activity and records.", 17, ui.DIM)
		ui.action(col, "Find a clan", screen, "select", "Clans", "accent", "search", ui.LILAC)
		return
	var row = ui.box(col, false, 14)
	ui.medal(row, int(clan.get("color", 0)) % 6, str(clan.get("emblem", "crown")), 70)
	var words = ui.box(row, true, 2)
	ui.grow(words)
	ui.title(words, str(clan.name), 26)
	ui.text(words, "[%s] · %d members" % [str(clan.tag), hub.clans.members.get(hub.clans.mine, []).size()], 16, ui.DIM)
	ui.action(col, "Open clan", screen, "show_clan", hub.clans.mine, "quiet", "chevron_right", ui.LILAC)
