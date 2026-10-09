extends "user://mod/tools/goober-hub/ui/HubPage.gd"
const TABS = ["Overview", "Journey", "Matches", "Creations", "Passport"]
var editing = false
var bio_field
var picked = []
var creation_shelf
var friends_page

func _id():
	return hub.store.account if screen.profile_id.empty() else screen.profile_id

func _own():
	return _id() == hub.store.account

func build(content):
	var id = _id()
	if id.empty():
		ui.empty(content, "Sign in to GooberDash", "", "goober", ui.GOLD)
		return
	_hero(content, id)
	var tabs = TABS.duplicate()
	if _own(): tabs.append("Friend requests")
	if not screen.profile_tab in tabs: screen.profile_tab = "Overview"
	ui.choice(content, tabs, screen.profile_tab, self, "_tab")
	if screen.profile_tab == "Friend requests":
		if friends_page == null:
			friends_page = load(ModPaths.path("HubFriendsPage.gd")).new()
			friends_page.hub = hub
			friends_page.ui = ui
			friends_page.screen = screen
		friends_page.build(content)
	else:
		call("_" + screen.profile_tab.to_lower(), content, id)

func _tab(value):
	screen.profile_tab = value
	editing = false
	if value == "Friend requests": hub.friend_service.refresh()
	screen.render()

func _hero(parent, id):
	var r = hub.profiles.row(id)
	var native = hub.profiles.native.get(id, {})
	var card = ui.surface(parent, ui.PANEL, 22, 28)
	var outer = ui.box(card, true, 16)
	var row = ui.box(outer, false, 26)
	var stage = ui.inset(row, 0, 24, ui.INSET)
	var avatar = load(ModPaths.path("HubAvatar.gd")).new(Vector2(230, 270))
	avatar.own_tool = hub.tool if _own() else null
	stage.add_child(avatar)
	if native.has("skin"):
		avatar.skin = native.skin
	var col = ui.box(row, true, 12)
	ui.grow(col)
	var top = ui.box(col, false, 12)
	ui.title(top, hub.profiles.name_for(id), 46)
	var clan = hub.clans.clans.get(hub.clans.clan_of(id), {})
	if not clan.empty():
		var tag = ui.tag(top, "[%s] %s" % [str(clan.tag), str(clan.name)], ui.CLAN_COLORS[int(clan.get("color", 0)) % 8])
		ui.clickable(tag, screen, "show_clan", hub.clans.clan_of(id), ui.LILAC)
	var rank = rank_text(id)
	var line = ui.box(col, false, 12)
	if not rank.empty():
		var defs = load(ModPaths.path("JourneyDefinitions.gd")).new()
		var xp = int(hub.journey_model().get("xp", 0)) if _own() else int(r.get("journey_xp", r.get("xp", 0)))
		ui.badge(line, defs.rank_at(xp), 64)
		ui.title(line, rank, 28, ui.GOLD)
	var bio = str(hub.store.data.profile.get("bio", "")) if _own() else str(r.get("bio", ""))
	if not bio.empty() and not editing:
		ui.wrap(col, bio, 19, ui.SOFT)
	var stats = ui.box(col, false, 10)
	var wins = hub.profiles.stat(id, hub.profiles.stat_key("Stat_GamesWon"))
	var games = hub.profiles.stat(id, hub.profiles.stat_key("Stat_GamesPlayed"))
	wins = wins if wins > 0 else int(r.get("wins", 0))
	ui.stat(stats, ui.thousands(wins) if wins > 0 else "-", "Wins", ui.GOLD, "crown")
	games = games if games > 0 else int(r.get("games", 0))
	ui.stat(stats, ui.thousands(games) if games > 0 else "-", "Games", ui.WHITE, "play")
	var streak = hub.profiles.stat(id, hub.profiles.stat_key("Stat_BestWinstreak"))
	ui.stat(stats, ui.thousands(streak) if streak > 0 else "-", "Best streak", ui.HUB_PINK, "sparkle")
	var since = load(ModPaths.path("HubFeed.gd")).unix(r.get("member_since", "")) if r.get("member_since") != null else 0
	ui.stat(stats, ui.month_year(since) if since > 0 else "-", "Member since", ui.MINT, "calendar")
	var actions = ui.box(col, false, 10)
	if _own():
		ui.action(actions, "Done" if editing else "Edit profile", self, "_edit", null, "secondary" if editing else "quiet", "palette", ui.GOLD)
		ui.action(actions, "Journey", hub, "open_journey", null, "quiet", "xp", ui.GOLD)
		ui.action(actions, "Add friend", screen, "friend_requests", null, "quiet", "goober", ui.SKY)
	else:
		if hub.is_friend(id):
			ui.action(actions, "Message", screen, "message", id, "accent", "inbox")
		else:
			var state = hub.friend_service.state_for(id)
			var add = ui.action(actions, "Accept request" if state == 2 else ("Request sent" if state == 1 else "Add friend"), self, "_add_friend", id, "quiet", "goober", ui.SKY)
			add.disabled = state == 1 or hub.friend_service.busy
		var blocked = hub.chat.blocked.has(id)
		ui.action(actions, "Unblock" if blocked else "Block", self, "_block", id, "danger", "lock")
	ui.action(actions, "GooberDash profile", hub, "open_native_profile", id, "quiet", "eye", ui.SKY)
	if editing:
		_editor(outer)

func _overview(parent, id):
	var cols = columns(parent, 1.4)
	var badges = hub.featured_badges() if _own() else hub.profiles.row(id).get("badges", [])
	var shelf = ui.surface(cols[0], ui.PANEL, 20)
	var col = ui.box(shelf, true, 12)
	ui.section(col, "Featured badges", "achievements", "", ui.LILAC)
	if badges.empty():
		ui.text(col, "No featured badges yet", 17, ui.DIM)
	else:
		var grid = ui.box(col, false, 14)
		for b in badges:
			var cell = ui.box(grid, true, 4)
			ui.medal(cell, int(clamp(int(b.tier) - 1, 0, 5)), badge_emblem(b.key), 110)
			ui.text(cell, badge_name(b.key), 15, ui.SOFT).align = Label.ALIGN_CENTER
	var favorites = hub.store.data.profile.get("favorites", []) if _own() else hub.profiles.row(id).get("favorites", [])
	if favorites is Array and not favorites.empty():
		var fav = ui.surface(cols[0], ui.PANEL, 20)
		var fcol = ui.box(fav, true, 12)
		ui.section(fcol, "Favorite levels", "star", "", ui.GOLD)
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_constant_override("hseparation", 12)
		grid.add_constant_override("vseparation", 12)
		ui.grow(grid)
		fcol.add_child(grid)
		for f in favorites:
			var shot = ui.shot(grid, str(f.get("name", "")) if f is Dictionary else str(f), 130)
			ui.grow(shot)
	_records(cols[0], id)
	var recent = ui.surface(cols[1], ui.PANEL, 20)
	var rcol = ui.box(recent, true, 12)
	ui.section(rcol, "Recent activity", "activity", "", ui.HUB_PINK)
	var list = hub.feed.events.player if hub.feed.player_shown == id else []
	if list.empty():
		ui.text(rcol, "No activity yet", 17, ui.DIM)
	for e in list.slice(0, min(6, list.size()) - 1):
		var info = describe(e)
		var line = ui.box(rcol, false, 10)
		ui.icon(line, info[2], 24, info[3])
		ui.wrap(line, info[0], 17, ui.WHITE)
		ui.text(line, ui.ago(e.at), 14, ui.DIM)
	var finish = hub.profiles.row(id).get("journey_finish", hub.profiles.row(id).get("finish", ""))
	if _own() and is_instance_valid(hub.journey) and hub.journey.get("hud") != null:
		finish = str(hub.journey.hud.equipped_finish().get("name", hub.journey.hud.equipped_finish().get("key", "")))
	if not str(finish).empty():
		var f = ui.surface(cols[1], ui.PANEL, 20)
		var fc = ui.box(f, true, 8)
		ui.section(fc, "Finish animation", "flag", "", ui.MINT)
		ui.title(fc, str(finish).capitalize(), 24)

func _records(parent, id):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 10)
	ui.section(col, "Personal records", "stopwatch", "", ui.MINT)
	if not _own():
		var shown = 0
		for e in hub.feed.events.player if hub.feed.player_shown == id else []:
			if str(e.kind) == "pb" and shown < 5:
				shown += 1
				var line = ui.box(col, false, 10)
				ui.text(line, str(e.data.get("map", "")), 18, ui.WHITE)
				ui.spacer(line)
				ui.title(line, clock(e.data.get("time", 0)), 20, ui.MINT)
		if shown == 0:
			ui.text(col, "No records shared yet", 17, ui.DIM)
		return
	var history = hub.history_store()
	if history == null or history.records.empty():
		ui.text(col, "Play a few rounds to set records", 17, ui.DIM)
		return
	var best = []
	var maps = history.statistics(history.records).maps
	for key in maps:
		if float(maps[key].best) >= 0 and str(key).begins_with("time_trial:"):
			best.append([maps[key].name, float(maps[key].best), int(maps[key].plays)])
	best.sort_custom(self, "_most_played")
	if best.empty():
		ui.text(col, "Time trial records show here", 17, ui.DIM)
	for b in best.slice(0, min(6, best.size()) - 1):
		var line = ui.box(col, false, 10)
		ui.text(line, str(b[0]), 18, ui.WHITE)
		ui.spacer(line)
		ui.title(line, clock(b[1]), 20, ui.MINT)

func _most_played(a, b):
	return a[2] > b[2]

func _journey(parent, id):
	var card = ui.surface(parent, ui.PANEL, 22)
	var col = ui.box(card, true, 16)
	var model = hub.journey_model()
	var defs = load(ModPaths.path("JourneyDefinitions.gd")).new()
	var xp = int(model.get("xp", 0)) if _own() else int(hub.profiles.row(id).get("journey_xp", 0))
	var top = ui.box(col, false, 20)
	ui.badge(top, defs.rank_at(xp), 150)
	var words = ui.box(top, true, 4)
	ui.grow(words)
	var rank = rank_text(id)
	ui.title(words, rank if not rank.empty() else "No Journey rank yet", 38, ui.GOLD)
	ui.text(words, ui.thousands(xp) + " XP", 20, ui.SOFT)
	if _own():
		ui.action(words, "Open Journey", hub, "open_journey", null, "primary", "xp", ui.GOLD)
	ui.section(col, "Badges", "achievements", "", ui.LILAC)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_constant_override("hseparation", 14)
	grid.add_constant_override("vseparation", 14)
	col.add_child(grid)
	var list = []
	if _own() and model.get("achievements") != null:
		for c in model.achievements.collections:
			list.append({"key": c.key, "tier": int(c.tier)})
	else:
		list = hub.profiles.row(id).get("badges", [])
	if list.empty():
		ui.text(col, "No badges to show", 17, ui.DIM)
	var tiers = load(ModPaths.path("JourneyAchievements.gd"))
	for b in list:
		var cell = ui.box(grid, true, 4)
		ui.medal(cell, int(clamp(int(b.tier) - 1, 0, 5)), badge_emblem(b.key), 112, int(b.tier) <= 0)
		ui.text(cell, badge_name(b.key), 15, ui.SOFT).align = Label.ALIGN_CENTER
		ui.text(cell, tiers.tier_name(int(b.tier)), 13, ui.DIM).align = Label.ALIGN_CENTER

func _matches(parent, id):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 8)
	if not _own():
		var list = hub.store.together(id)
		ui.section(col, "Your matches together", "play", "%d" % list.size(), ui.SKY)
		if list.empty():
			ui.text(col, "You haven't played together yet", 17, ui.DIM)
		for m in list.slice(0, min(20, list.size()) - 1):
			var line = ui.box(col, false, 12)
			ui.icon(line, "maps", 24, ui.SKY)
			ui.text(line, str(m.map) if not str(m.map).empty() else "Match", 18, ui.WHITE)
			ui.spacer(line)
			var result = "You won" if str(m.winner) == hub.store.account else ("They won" if str(m.winner) == id else "")
			if not result.empty():
				ui.tag(line, result, ui.GOLD if result == "You won" else ui.HUB_PINK)
			ui.text(line, ui.ago(m.at), 15, ui.DIM)
		return
	ui.section(col, "Recent rounds", "play", "", ui.SKY)
	var records = hub.history_records()
	if records.empty():
		ui.text(col, "No rounds recorded yet", 17, ui.DIM)
	var shown = 0
	for i in range(records.size() - 1, -1, -1):
		if shown >= 25:
			break
		shown += 1
		var r = records[i]
		var line = ui.box(col, false, 12)
		ui.icon(line, "stopwatch" if r.mode == "time_trial" else "maps", 24, ui.MINT if r.mode == "time_trial" else ui.SKY)
		ui.text(line, str(r.map_name), 18, ui.WHITE)
		ui.spacer(line)
		if bool(r.win):
			ui.tag(line, "Win", ui.GOLD)
		elif r.result == "finish" and int(r.placement) > 0:
			ui.tag(line, "#%d" % int(r.placement), ui.INSET, ui.WHITE)
		elif r.result == "dnf":
			ui.tag(line, "Out", ui.EDGE, ui.WHITE)
		if r.result == "finish" and float(r.finish_time) >= 0:
			ui.title(line, clock(r.finish_time), 18, ui.MINT)
		ui.text(line, ui.ago(r.date), 15, ui.DIM)

func _creations(parent, id):
	if creation_shelf == null:
		creation_shelf = load(ModPaths.path("HubCreationShelf.gd")).new()
		creation_shelf.hub = hub
		creation_shelf.screen = screen
		creation_shelf.ui = ui
	if creation_shelf.build(parent,id): return
	_levels(parent,id)

func _levels(parent, id):
	var list = hub.creations(id)
	if list.empty():
		ui.empty(parent, "No certified levels", "", "hammer", ui.SKY)
		return
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_constant_override("hseparation", 16)
	grid.add_constant_override("vseparation", 16)
	ui.grow(grid)
	parent.add_child(grid)
	for level in list:
		var shot = ui.shot(grid, level.name, 170)
		ui.grow(shot)
		shot.mouse_filter = Control.MOUSE_FILTER_STOP
		shot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		shot.hint_tooltip = "Play " + level.name
		shot.connect("mouse_entered", shot, "set_modulate", [Color(1.15, 1.15, 1.2)])
		shot.connect("mouse_exited", shot, "set_modulate", [Color.white])
		shot.connect("gui_input", self, "_shot_input", [level.id])

func _shot_input(event, level_id):
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		screen.play_level(level_id)

func _passport(parent, id):
	if _own():
		screen.builders.Passport.overview(parent)
		return
	var r = hub.profiles.row(id)
	var card = ui.surface(parent, ui.PANEL, 22)
	var col = ui.box(card, true, 14)
	ui.section(col, hub.profiles.name_for(id).to_upper() + "'S PASSPORT", "compass", "", ui.MINT)
	var stats = ui.box(col, false, 10)
	var since = load(ModPaths.path("HubFeed.gd")).unix(r.get("member_since", "")) if r.get("member_since") != null else 0
	ui.stat(stats, ui.month_year(since) if since > 0 else "-", "Playing since", ui.MINT)
	ui.stat(stats, ui.thousands(int(r.get("games", 0))), "Games", ui.WHITE)
	ui.stat(stats, ui.thousands(int(r.get("wins", 0))), "Wins", ui.GOLD)
	ui.stat(stats, ui.thousands(int(r.get("maps", 0))), "Unique maps", ui.SKY)
	var met = hub.store.data.players.get(id, {})
	if not met.empty():
		ui.stat(stats, int(met.matches), "Matches with you", ui.HUB_PINK)

# ------------------------------------------------------------------ editing
func _edit():
	editing = not editing
	if not editing and bio_field != null and is_instance_valid(bio_field):
		hub.save_profile(bio_field.text, picked)
	elif editing:
		picked = hub.store.data.profile.get("favorites", []).duplicate()
	screen.render()

func _editor(parent):
	var edit = ui.inset(parent, 18, 20)
	var e = ui.box(edit, true, 12)
	ui.text(e, "Bio", 18, ui.SOFT)
	bio_field = ui.field(e, "A line about you", hub.store.data.profile.get("bio", ""), 120)
	ui.text(e, "Favorite levels (up to 5)", 18, ui.SOFT)
	var history = hub.history_store()
	var maps = history.statistics(history.records).maps if history != null else {}
	var names = []
	var seen = {}
	for key in maps:
		if not seen.has(maps[key].name):
			seen[maps[key].name] = true
			names.append([maps[key].name, int(maps[key].plays)])
	names.sort_custom(self, "_more_plays")
	var flow = GridContainer.new()
	flow.columns = 4
	flow.add_constant_override("hseparation", 8)
	flow.add_constant_override("vseparation", 8)
	e.add_child(flow)
	for n in names.slice(0, min(16, names.size()) - 1):
		var chosen = false
		for p in picked:
			if str(p.get("name", "")) == n[0]: chosen = true
		ui.action(flow, n[0], self, "_pick", n[0], "selected" if chosen else "quiet", "star", ui.GOLD)
	if names.empty():
		ui.text(e, "Play some maps first", 16, ui.DIM)
	ui.text(e, "Who sees your activity", 18, ui.SOFT)
	var shown = {"everyone": "Everyone", "friends": "Friends & clan", "nobody": "Nobody"}
	ui.choice(e, shown.values(), shown.get(str(hub.store.data.profile.get("activity", "everyone")), "Everyone"), self, "_activity_shown")
	ui.action(e,"Manage shared creations",self,"_manage_creations",null,"secondary","palette",ui.HUB_PINK)

func _manage_creations():
	if editing: _edit() # Save the bio/favorites before leaving the editor.
	screen.profile_tab = "Creations"
	screen.render()

func _activity_shown(label):
	var value = {"Everyone": "everyone", "Friends & clan": "friends", "Nobody": "nobody"}.get(label, "everyone")
	if bio_field != null and is_instance_valid(bio_field):
		hub.store.data.profile.bio = bio_field.text
	hub.set_activity_shown(value)
	screen.render()

func _more_plays(a, b):
	return a[1] > b[1]

func _pick(map_name):
	var found = -1
	for i in picked.size():
		if str(picked[i].get("name", "")) == map_name: found = i
	if found >= 0:
		picked.remove(found)
	elif picked.size() < 5:
		picked.append({"name": map_name})
	var bio = bio_field.text if bio_field != null and is_instance_valid(bio_field) else ""
	hub.store.data.profile.bio = bio
	screen.render()

func _add_friend(id):
	hub.friend_service.add(id)

func _block(id):
	hub.chat.set_blocked(id, not hub.chat.blocked.has(id))
	screen.show_notice(("Blocked " if hub.chat.blocked.has(id) else "Unblocked ") + hub.profiles.name_for(id) + ".")
	screen.render()
