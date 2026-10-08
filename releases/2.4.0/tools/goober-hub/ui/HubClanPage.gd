extends "user://mod/tools/goober-hub/ui/HubPage.gd"
const TABS = ["Overview", "Members", "Activity", "Records"]
var create_open = false
var form = {}
var form_emblem = "crown"
var form_color = 0
var form_open = true
var edit_open = false

func build(content):
	if offline_note(content):
		return
	if hub.clans.status == "missing":
		ui.empty(content, "Clans aren't set up yet", "Run docs/sql/GOOBER_HUB.sql in Supabase.", "crown", ui.LILAC)
		return
	var id = screen.clan_id if not screen.clan_id.empty() else hub.clans.mine
	if id.empty() or not hub.clans.clans.has(id):
		_browse(content)
	else:
		_clan(content, id)

# ------------------------------------------------------------------ browse
func _browse(parent):
	var cols = columns(parent, 1.5)
	var head = ui.section(cols[0], "Clans", "crown", "%d clans" % hub.clans.clans.size(), ui.LILAC)
	var search = ui.field(cols[0], "Search by name or tag", screen.query, 24)
	search.connect("text_entered", self, "_search")
	var list = hub.clans.listing(screen.query)
	if hub.clans.status == "loading" and list.empty():
		ui.empty(cols[0], "Loading clans", "", "session", ui.SKY)
	elif list.empty():
		ui.empty(cols[0], "No clans yet" if screen.query.empty() else "No clans found", "", "crown", ui.LILAC)
	for c in list.slice(0, min(40, list.size()) - 1):
		var card = ui.surface(cols[0], ui.PANEL, 16, 22)
		ui.clickable(card, screen, "show_clan", str(c.id), ui.INSET)
		var row = ui.box(card, false, 14)
		ui.medal(row, int(c.color) % 6, str(c.emblem), 64)
		var words = ui.box(row, true, 2)
		ui.grow(words)
		var top = ui.box(words, false, 8)
		ui.title(top, str(c.name), 24)
		ui.tag(top, str(c.tag), ui.CLAN_COLORS[int(c.color) % 8])
		if not str(c.motto).empty():
			ui.text(words, str(c.motto), 16, ui.SOFT)
		ui.text(row, "%d / 50" % int(c.count), 16, ui.DIM)
		ui.tag(row, "Open" if bool(c.open) else "Request", ui.MINT if bool(c.open) else ui.GOLD)
	var side = ui.surface(cols[1], ui.PANEL, 20)
	var col = ui.box(side, true, 12)
	ui.section(col, "Found a clan", "sparkle", "", ui.HUB_PINK)
	if not hub.clans.mine.empty():
		ui.text(col, "You're already in a clan", 17, ui.DIM)
		ui.action(col, "Your clan", screen, "show_clan", hub.clans.mine, "quiet", "chevron_right", ui.LILAC)
		return
	if not create_open:
		ui.action(col, "Found a clan", self, "_toggle_create", null, "accent", "sparkle")
		return
	form.name = ui.field(col, "Clan name", form.get("name_text", ""), 24)
	form.tag = ui.field(col, "Tag (2-5)", form.get("tag_text", ""), 5)
	form.motto = ui.field(col, "Motto", form.get("motto_text", ""), 80)
	_style_picker(col)
	var open_row = ui.box(col, false, 10)
	ui.text(open_row, "Anyone can join", 18, ui.SOFT)
	ui.spacer(open_row)
	ui.switch(open_row, form_open, self, "_toggle_open")
	var buttons = ui.box(col, false, 10)
	ui.action(buttons, "Found clan", self, "_create", null, "primary", "check", ui.GOLD)
	ui.action(buttons, "Cancel", self, "_toggle_create", null, "quiet", "close")

func _style_picker(col):
	ui.text(col, "Emblem", 18, ui.SOFT)
	var emblems = ui.box(col, false, 6)
	for e in hub.clans.EMBLEMS:
		var b = ui.action(emblems, "", self, "_emblem", e, "selected" if e == form_emblem else "quiet")
		b.rect_min_size = Vector2(58, 58)
		var mark = ui.image(null, "emblem_" + e, 40)
		mark.set_anchors_and_margins_preset(Control.PRESET_CENTER)
		mark.margin_left = -20
		mark.margin_top = -20
		mark.margin_right = 20
		mark.margin_bottom = 20
		b.add_child(mark)
	ui.text(col, "Colour", 18, ui.SOFT)
	var colors = ui.box(col, false, 6)
	for i in ui.CLAN_COLORS.size():
		var swatch = ui.action(colors, "", self, "_color", i, "selected" if i == form_color else "quiet")
		swatch.rect_min_size = Vector2(46, 46)
		var dot = ColorRect.new()
		dot.color = ui.CLAN_COLORS[i]
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_anchors_and_margins_preset(Control.PRESET_CENTER)
		dot.margin_left = -12
		dot.margin_top = -12
		dot.margin_right = 12
		dot.margin_bottom = 12
		swatch.add_child(dot)

func _remember_form():
	for k in ["name", "tag", "motto"]:
		if form.has(k) and is_instance_valid(form[k]):
			form[k + "_text"] = form[k].text

func _toggle_create():
	_remember_form()
	create_open = not create_open
	screen.render()

func _toggle_open(value = null):
	_remember_form()
	form_open = bool(value) if value != null else not form_open
	screen.render()

func _emblem(value):
	_remember_form()
	form_emblem = value
	screen.render()

func _color(value):
	_remember_form()
	form_color = int(value)
	screen.render()

func _search(value):
	screen.query = str(value)
	screen.render()

func _create():
	_remember_form()
	var data = {"name": str(form.get("name_text", "")).strip_edges(), "tag": str(form.get("tag_text", "")).strip_edges(),
		"motto": str(form.get("motto_text", "")).strip_edges(), "emblem": form_emblem, "color": form_color, "open": form_open}
	hub.clans.pending_post = {"kind": "clan_found", "clan": data.name, "tag": data.tag.to_upper()}
	hub.clans.act("create", "", "", data)
	create_open = false
	form = {}

# ------------------------------------------------------------------ one clan
func _clan(parent, id):
	var c = hub.clans.clans[id]
	var color = ui.CLAN_COLORS[int(c.color) % 8]
	var banner = ui.surface(parent, color.darkened(0.55), 24, 28)
	var row = ui.box(banner, false, 22)
	ui.medal(row, int(c.color) % 6, str(c.emblem), 120)
	var words = ui.box(row, true, 6)
	ui.grow(words)
	var top = ui.box(words, false, 12)
	ui.title(top, str(c.name).to_upper(), 44)
	ui.tag(top, str(c.tag), color)
	ui.text(words, "%d members · founded %s" % [hub.clans.members.get(id, []).size(), ui.month_year(load(ModPaths.path("HubFeed.gd")).unix(c.created_at))], 18, ui.SOFT)
	if not str(c.motto).empty():
		ui.text(words, "\"%s\"" % str(c.motto), 19, ui.WHITE)
	var actions = ui.box(row, true, 8)
	var my_role = hub.clans.role_of(hub.store.account, id)
	if my_role.empty():
		if hub.clans.mine.empty():
			var requested = hub.clans.requests.get(id, []).has(hub.store.account)
			if requested:
				ui.action(actions, "Cancel request", self, "_do", ["leave", id, ""], "quiet", "close")
			else:
				ui.action(actions, "Join" if bool(c.open) else "Ask to join", self, "_join", id, "accent", "check")
		ui.action(actions, "All clans", self, "_all", null, "quiet", "back")
	else:
		ui.tag(actions, my_role.capitalize(), ui.GOLD)
		if my_role == "leader":
			ui.action(actions, "Close" if edit_open else "Edit", self, "_toggle_edit", null, "quiet", "palette", ui.LILAC)
		ui.action(actions, "Leave", self, "_do", ["leave", id, ""], "danger", "back")
		ui.action(actions, "All clans", self, "_all", null, "quiet", "maps")
	if edit_open and my_role == "leader":
		_editor(parent, c)
	ui.choice(parent, TABS, screen.clan_tab, self, "_tab")
	call("_" + screen.clan_tab.to_lower(), parent, id)

func _tab(value):
	screen.clan_tab = value
	screen.render()

func _all():
	screen.clan_id = "__browse__"
	screen.render()

func _join(id):
	var c = hub.clans.clans.get(id, {})
	hub.clans.pending_post = {"kind": "clan_join", "clan": str(c.get("name", "")), "tag": str(c.get("tag", ""))} if bool(c.get("open", false)) else {}
	hub.clans.act("join", id)

func _do(args):
	hub.clans.act(args[0], args[1], args[2])

func _toggle_edit():
	edit_open = not edit_open
	form_emblem = str(hub.clans.clans.get(hub.clans.mine, {}).get("emblem", "crown"))
	form_color = int(hub.clans.clans.get(hub.clans.mine, {}).get("color", 0))
	form_open = bool(hub.clans.clans.get(hub.clans.mine, {}).get("open", true))
	screen.render()

func _editor(parent, c):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 12)
	form.motto = ui.field(col, "Motto", form.get("motto_text", str(c.motto)), 80)
	_style_picker(col)
	var open_row = ui.box(col, false, 10)
	ui.text(open_row, "Anyone can join", 18, ui.SOFT)
	ui.spacer(open_row)
	ui.switch(open_row, form_open, self, "_toggle_open")
	ui.action(col, "Save", self, "_save_edit", str(c.id), "primary", "check", ui.GOLD)

func _save_edit(id):
	_remember_form()
	hub.clans.act("edit", id, "", {"motto": str(form.get("motto_text", "")), "emblem": form_emblem, "color": form_color, "open": form_open})
	edit_open = false
	form = {}

func _members_sorted(id) -> Array:
	var order = {"leader": 0, "officer": 1, "member": 2}
	var list = hub.clans.members.get(id, []).duplicate()
	for m in list:
		m["_order"] = order.get(str(m.role), 3)
		m["_xp"] = int(hub.profiles.row(m.user_id).get("journey_xp", hub.profiles.row(m.user_id).get("xp", 0)))
	list.sort_custom(self, "_by_role")
	return list

func _by_role(a, b):
	return a._order < b._order if a._order != b._order else a._xp > b._xp

func _overview(parent, id):
	var cols = columns(parent, 1.3)
	var ids = hub.clans.member_ids(id)
	var wins = 0
	var games = 0
	var xp = 0
	for uid in ids:
		var r = hub.profiles.row(uid)
		wins += int(r.get("wins", 0))
		games += int(r.get("games", 0))
		xp += int(r.get("journey_xp", r.get("xp", 0)))
	var stats = ui.box(cols[0], false, 10)
	ui.stat(stats, ids.size(), "Members", ui.WHITE, "goober")
	ui.stat(stats, ui.thousands(wins), "Combined wins", ui.GOLD, "crown")
	ui.stat(stats, ui.thousands(games), "Games", ui.SKY, "play")
	var defs = load(ModPaths.path("JourneyDefinitions.gd")).new()
	ui.stat(stats, defs.rank_at(xp / max(1, ids.size())).name if xp > 0 else "-", "Average rank", ui.LILAC, "xp")
	var feat = ui.surface(cols[0], ui.PANEL, 20)
	var fcol = ui.box(feat, true, 10)
	ui.section(fcol, "Featured members", "star", "", ui.GOLD)
	var top = _members_sorted(id)
	top.sort_custom(self, "_by_xp")
	for m in top.slice(0, min(3, top.size()) - 1):
		player_row(fcol, m.user_id, _member_detail(m))
	var recent = ui.surface(cols[1], ui.PANEL, 20)
	var rcol = ui.box(recent, true, 10)
	ui.section(rcol, "Clan activity", "activity", "", ui.HUB_PINK)
	var list = hub.feed.events.get("clan", [])
	if list.empty():
		ui.text(rcol, "No activity yet", 17, ui.DIM)
	for e in list.slice(0, min(5, list.size()) - 1):
		var info = describe(e)
		var line = ui.box(rcol, false, 10)
		ui.icon(line, info[2], 24, info[3])
		ui.wrap(line, hub.profiles.name_for(e.user_id) + " " + info[0], 17, ui.WHITE)
	var reqs = hub.clans.requests.get(id, [])
	var my_role = hub.clans.role_of(hub.store.account, id)
	if my_role in ["leader", "officer"] and not reqs.empty():
		var card = ui.surface(cols[1], ui.PANEL, 20)
		var col = ui.box(card, true, 10)
		ui.section(col, "Join requests", "bell", "%d" % reqs.size(), ui.GOLD)
		for uid in reqs:
			player_row(col, uid, rank_text(uid), [["", self, "_do", ["accept", id, uid], "primary", "check"], ["", self, "_do", ["decline", id, uid], "quiet", "close"]])

func _by_xp(a, b):
	return a._xp > b._xp

func _member_detail(m) -> String:
	var parts = [str(m.role).capitalize()]
	var rank = rank_text(m.user_id)
	if not rank.empty(): parts.append(rank)
	var wins = int(hub.profiles.row(m.user_id).get("wins", 0))
	if wins > 0: parts.append("%s wins" % ui.thousands(wins))
	return PoolStringArray(parts).join(" · ")

func _members(parent, id):
	var card = ui.surface(parent, ui.PANEL, 20)
	var col = ui.box(card, true, 10)
	var mine = hub.clans.role_of(hub.store.account, id)
	for m in _members_sorted(id):
		var actions = []
		var theirs = str(m.role)
		var uid = str(m.user_id)
		if uid != hub.store.account:
			if mine == "leader":
				if theirs == "member":
					actions.append(["Promote", self, "_do", ["promote", id, uid], "quiet", "chevron_down"])
				elif theirs == "officer":
					actions.append(["Demote", self, "_do", ["demote", id, uid], "quiet", "chevron_down"])
					actions.append(["Make leader", self, "_do", ["lead", id, uid], "quiet", "crown"])
			if (mine == "leader" and theirs != "leader") or (mine == "officer" and theirs == "member"):
				actions.append(["Remove", self, "_do", ["kick", id, uid], "danger", "close"])
		player_row(col, uid, _member_detail(m), actions)

func _activity(parent, _id):
	var list = hub.feed.events.get("clan", [])
	if list.empty():
		ui.empty(parent, "No activity yet", "", "activity", ui.HUB_PINK)
	for e in list:
		event_card(parent, e)

func _records(parent, id):
	var card = ui.surface(parent, ui.PANEL, 22)
	var col = ui.box(card, true, 12)
	ui.section(col, "Clan records", "podium", "", ui.GOLD)
	for spec in [["wins", "Most wins", "crown"], ["games", "Most games", "play"], ["journey_xp", "Highest Journey XP", "xp"], ["maps", "Most maps played", "maps"]]:
		var best = ""
		var value = 0
		for uid in hub.clans.member_ids(id):
			var v = int(hub.profiles.row(uid).get(spec[0], 0))
			if v > value:
				value = v
				best = uid
		var line = ui.box(col, false, 12)
		ui.icon(line, spec[2], 30, ui.GOLD)
		ui.text(line, spec[1], 19, ui.SOFT)
		ui.spacer(line)
		if best.empty():
			ui.text(line, "-", 19, ui.DIM)
		else:
			ui.title(line, hub.profiles.name_for(best), 22)
			ui.title(line, ui.thousands(value), 22, ui.GOLD)
