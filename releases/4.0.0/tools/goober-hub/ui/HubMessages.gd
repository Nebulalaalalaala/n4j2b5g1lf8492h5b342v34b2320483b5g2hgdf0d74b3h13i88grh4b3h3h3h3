extends "user://mod/tools/goober-hub/ui/HubPage.gd"
var input
var draft = ""
var tray = ""   # "", "emotes" or "share" under the message box
var emotes = null
var as_test = false   # admin: writing as the test account
var choosing = false
var picker
var drafts = {}
var draft_thread = ""
var draft_owner = ""

func build(content):
	if draft_owner != hub.store.account:
		draft_owner = hub.store.account
		drafts = {}
		draft = ""
		draft_thread = ""
		as_test = false
		choosing = false
		input = null
	if emotes == null:
		emotes = load(ModPaths.path("HubEmote.gd")).catalog()
	if offline_note(content):
		return
	if hub.chat.status == "missing":
		ui.empty(content, "Messages aren't set up yet", "Run docs/sql/GOOBER_HUB.sql in Supabase.", "inbox", ui.SKY)
		return
	var friends = hub.friends()
	if screen.thread.empty() or not hub.is_friend(screen.thread):
		screen.thread = _first_thread(friends)
	var row = ui.box(content, false, 20)
	ui.grow(row, true, true)
	var side = ui.surface(row, ui.PANEL, 14, 22)
	side.rect_min_size = Vector2(440, 560)
	var list = ui.box(side, true, 8)
	var head = ui.section(list, "Messages", "inbox", "", ui.SKY)
	var plus = ui.action(head, "+", self, "_new_message", null, "secondary")
	plus.hint_tooltip = "New message — choose a friend"
	plus.rect_min_size = Vector2(48, 44)
	var shown = 0
	for f in _sorted(friends):
		if hub.chat.last(f.id) != null or f.id == screen.thread:
			_friend(list, f)
			shown += 1
	if shown == 0: ui.wrap(list, "No conversations yet. Press + to choose a friend.", 18, ui.DIM)
	if friends.empty(): ui.action(list, "Add friend", screen, "friend_requests", null, "quiet", "goober", ui.SKY)
	if choosing:
		if picker == null:
			picker = load(ModPaths.path("HubMessagePicker.gd")).new()
			picker.hub = hub
			picker.ui = ui
			picker.screen = screen
		picker.build(row)
	elif not screen.thread.empty():
		_thread(row, screen.thread)
	else:
		var empty = ui.empty(row, "Start a conversation", "Press + and choose one of your friends.", "inbox", ui.SKY)
		ui.grow(empty.get_parent(), true, true)

func _first_thread(friends) -> String:
	var sorted = _sorted(friends)
	return sorted[0].id if not sorted.empty() and hub.chat.last(sorted[0].id) != null else ""

# Latest conversation first, then online friends.
func _sorted(friends) -> Array:
	var list = friends.duplicate()
	for f in list:
		var last = hub.chat.last(f.id)
		f["last_at"] = int(last.at) if last != null else 0
	list.sort_custom(self, "_recent")
	return list

func _recent(a, b):
	if a.last_at != b.last_at:
		return a.last_at > b.last_at
	if a.online != b.online:
		return a.online
	return a.name.to_lower() < b.name.to_lower()

func _friend(parent, f):
	var selected = f.id == screen.thread
	var panel = ui.inset(parent, 12, 18, ui.EDGE if selected else ui.INSET)
	ui.clickable(panel, self, "_open", f.id, ui.EDGE)
	var row = ui.box(panel, false, 12)
	ui.goober(row, hub.profiles.look_for(f.id), 46, f.id)
	var col = ui.box(row, true, 0)
	ui.grow(col)
	var top = ui.box(col, false, 8)
	var name = ui.title(top, f.name, 21)
	name.clip_text = true
	ui.grow(name)
	if hub.store.data.muted.has(f.id):
		ui.icon(top, "bell", 18, ui.DIM)
	var last = hub.chat.last(f.id)
	var preview = ("You: " if last.mine else "") + hub.chat.preview(last.body, emotes) if last != null else ("Online" if f.online else "Offline")
	var l = ui.text(col, preview, 15, ui.DIM)
	l.clip_text = true
	var unread = int(hub.chat.unread.get(f.id, 0))
	if unread > 0 and not hub.store.data.muted.has(f.id):
		ui.tag(row, str(unread), ui.HUB_PINK)

func _open(id):
	_save_draft()
	tray = ""
	choosing = false
	screen.thread = str(id)
	draft = str(drafts.get(str(id), ""))
	draft_thread = str(id)
	input = null
	screen.render()

func _new_message():
	_save_draft()
	choosing = true
	input = null
	hub.friend_service.refresh()
	screen.render()

func _cancel_picker():
	choosing = false
	screen.render()

func _thread(parent, id):
	var card = ui.surface(parent, ui.PANEL, 18, 22)
	ui.grow(card, true, true)
	card.rect_min_size.y = 560
	var col = ui.box(card, true, 12)
	var head = ui.box(col, false, 12)
	ui.goober(head, hub.profiles.look_for(id), 50, id)
	ui.title(head, hub.profiles.name_for(id), 28)
	ui.spacer(head)
	var test = id == hub.TEST_ID
	if test:
		ui.action(head, "Writing as test account" if as_test else "Writing as you", self, "_toggle_test", null, "accent" if as_test else "quiet", "goober", ui.GOLD).hint_tooltip = "Only you can see this account"
	else:
		ui.action(head, "Profile", screen, "show_profile", id, "quiet", "goober", ui.GOLD)
	var muted = hub.store.data.muted.has(id)
	ui.action(head, "Unmute" if muted else "Mute", self, "_mute", id, "quiet", "bell", ui.SKY).hint_tooltip = "Muted chats don't show the unread dot"
	var blocked = hub.chat.blocked.has(id)
	if not test:
		ui.action(head, "Unblock" if blocked else "Block", self, "_block", id, "danger", "lock")
	var lines = ui.box(col, true, 8)
	ui.grow(lines, true, true)
	var messages = hub.chat.threads.get(id, [])
	if messages.empty():
		ui.text(lines, "Say hi to " + hub.profiles.name_for(id), 18, ui.DIM).align = Label.ALIGN_CENTER
	for i in range(max(0, messages.size() - 60), messages.size()):
		_bubble(lines, messages[i], id)
	hub.chat.mark_read(id)
	if blocked:
		ui.text(col, "You blocked this player. Unblock to send messages.", 17, ui.GOLD)
		return
	if hub.moderation.muted():
		ui.wrap(col, "Messaging is muted until " + hub.moderation.until_text(hub.moderation.self_state.get("muted_until", "")) + ".", 17, ui.GOLD)
		return
	var send = ui.box(col, false, 10)
	ui.action(send, "", self, "_tray", "emotes", "quiet" if tray != "emotes" else "accent", "goober", ui.GOLD).hint_tooltip = "Emotes"
	ui.action(send, "", self, "_tray", "share", "quiet" if tray != "share" else "accent", "maps", ui.SKY).hint_tooltip = "Share a level or invite"
	if draft_thread != str(id): draft = str(drafts.get(str(id), ""))
	draft_thread = str(id)
	input = ui.field(send, "Message " + hub.profiles.name_for(id), draft, 300)
	input.connect("text_entered", self, "_send")
	ui.action(send, "Send", self, "_send_button", null, "accent", "chevron_right")
	if tray == "emotes":
		_emote_tray(col)
	elif tray == "share":
		_share_tray(col)
	input.caret_position = draft.length()
	call_deferred("_focus_composer")

func _focus_composer():
	if is_instance_valid(input) and input.is_inside_tree() and screen.is_open() and screen.page == "Messages" and not choosing:
		input.grab_focus()

func _bubble(parent, m, friend):
	var row = ui.box(parent, false, 8)
	if m.mine:
		ui.spacer(row)
	var panel = ui.inset(row, 12, 18, Color("ff69b4").darkened(0.35) if m.mine else ui.INSET)
	panel.size_flags_horizontal = 0
	var col = ui.box(panel, true, 2)
	_body(col, m, friend)
	ui.text(col, ui.ago(m.at), 13, ui.SOFT)
	if not m.mine:
		var flag = ui.action(row, "", self, "_report", [friend, m.id], "tab", "flag", ui.DIM)
		flag.hint_tooltip = "Report this message"
		flag.rect_min_size = Vector2(36, 36)
		flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ui.spacer(row)

func _save_draft():
	if input != null and is_instance_valid(input) and draft_owner == hub.store.account:
		draft = input.text
		drafts[draft_thread] = draft

func _send(text):
	if str(text).strip_edges().empty():
		return
	_post(text)
	draft = ""
	drafts[draft_thread] = ""
	if input != null and is_instance_valid(input):
		input.text = ""

func _send_button():
	if input != null and is_instance_valid(input):
		_send(input.text)

func _post(text):
	if as_test and screen.thread == hub.TEST_ID:
		hub.chat.send_as_test(text)
	else:
		hub.chat.send(screen.thread, text)

func _toggle_test():
	_save_draft()
	as_test = not as_test
	screen.render()

func _mute(id):
	if hub.store.data.muted.has(id):
		hub.store.data.muted.erase(id)
	else:
		hub.store.data.muted[id] = true
	hub.store.save()
	screen.render()

func _block(id):
	_save_draft()
	hub.chat.set_blocked(id, not hub.chat.blocked.has(id))
	screen.render()

func _report(pair):
	hub.chat.report(pair[0], pair[1])

# ------------------------------------------------------------ message parts
func _body(col, m, friend):
	var parts = hub.chat.parts(m.body, _emote_names())
	var only_emotes = true
	for p in parts:
		if not p.has("emote") and not (p.has("text") and p.text.strip_edges().empty()):
			only_emotes = false
	var line = null
	for p in parts:
		if p.has("kind"):
			line = null
			_attachment(col, p.kind, p.data, m.mine, friend)
			continue
		if line == null:
			line = ui.box(col, false, 4)
		if p.has("emote"):
			_emote(line, p.emote, 96 if only_emotes else 40, only_emotes)
		elif not p.text.strip_edges().empty():
			var label = ui.text(line, p.text.strip_edges(), 19, ui.WHITE)
			label.autowrap = p.text.length() > 48
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if label.autowrap:
				label.rect_min_size.x = 560

func _emote(parent, id, size, animated = false):
	var e = load(ModPaths.path("HubEmote.gd")).new()
	e.spine = emotes.get(id, {}).get("spine", "")
	e.animated = animated
	e.rect_min_size = Vector2.ONE * size
	parent.add_child(e)
	return e

func _emote_names() -> Dictionary:
	return emotes

func _attachment(parent, kind, data, mine, friend):
	var card = ui.inset(parent, 12, 16, ui.BASE)
	card.rect_min_size.x = 420
	var row = ui.box(card, false, 14)
	var glyph = {"lv": "maps", "py": "goober", "lb": "play"}.get(kind, "maps")
	ui.tile_icon(row, glyph, ui.SKY if kind == "lv" else ui.HUB_PINK, 52)
	var words = ui.box(row, true, 0)
	ui.grow(words)
	var title = {"lv": str(data.get("name", "Level")), "py": "Party invite", "lb": "Game invite"}.get(kind, "")
	var detail = {"lv": "Shared level", "py": "Join %s's party" % hub.profiles.name_for(friend) if not mine else "You invited them to your party",
		"lb": "Join %s's custom game" % hub.profiles.name_for(friend) if not mine else "You invited them to your game"}.get(kind, "")
	var t = ui.title(words, title, 22)
	t.clip_text = true
	ui.text(words, detail, 15, ui.DIM)
	if kind == "lv":
		ui.action(row, "Play", self, "_play_level", data, "accent", "play")
	elif not mine:
		ui.action(row, "Join", self, "_join_party" if kind == "py" else "_join_game", [friend, data], "accent", "chevron_right")

# ------------------------------------------------------------ compose trays
func _tray(which):
	_save_draft()
	tray = "" if tray == which else which
	screen.render()

func _emote_tray(parent):
	var panel = ui.inset(parent, 12, 18, ui.BASE)
	var grid = GridContainer.new()
	grid.columns = 10
	grid.add_constant_override("hseparation", 8)
	grid.add_constant_override("vseparation", 8)
	panel.add_child(grid)
	var mine = load(ModPaths.path("HubEmote.gd")).owned(emotes)
	if mine.empty():
		ui.text(grid, "Unlock emotes in the game to use them here.", 15, ui.DIM)
	for id in mine:
		var holder = ui.inset(grid, 4, 14, ui.INSET)
		ui.clickable(holder, self, "_add_emote", id, ui.EDGE)
		_emote(holder, id, 64)
		holder.hint_tooltip = str(emotes[id].name)

func _add_emote(name):
	if input == null or not is_instance_valid(input):
		return
	var token = ":%s:" % name
	if input.text.length() + token.length() > 300:
		return
	var at = input.caret_position
	input.text = input.text.substr(0, at) + token + input.text.substr(at)
	input.caret_position = at + token.length()
	draft = input.text
	input.grab_focus()

func _share_tray(parent):
	var panel = ui.inset(parent, 12, 18, ui.BASE)
	var col = ui.box(panel, true, 10)
	var invites = ui.box(col, false, 10)
	var party = _moonlight_part("party")
	var in_lobby = party != null and party.is_in_lobby()
	ui.action(invites, "Invite to party" if party != null and party.is_in_squad() else "Start a party and invite", self, "_invite_party", null, "quiet", "goober", ui.HUB_PINK)
	var game = ui.action(invites, "Invite to my game", self, "_invite_game", null, "quiet", "play", ui.SKY)
	if not in_lobby:
		game.hint_tooltip = "Open a custom lobby first"
	ui.text(col, "Recent levels", 15, ui.DIM)
	var levels = ui.box(col, false, 8)
	var shown = 0
	for level in _recent_levels():
		var b = ui.action(levels, str(level.name).left(22), self, "_share_level", level, "tab", "maps", ui.SKY)
		b.hint_tooltip = str(level.name)
		shown += 1
	if shown == 0:
		ui.text(levels, "Play a level and it shows up here.", 15, ui.DIM)

func _recent_levels() -> Array:
	var seen = {}
	var out = []
	var records = hub.history_records()
	for i in range(records.size() - 1, -1, -1):
		var r = records[i]
		var id = str(r.get("map_id", ""))
		if id.empty() or seen.has(id) or str(r.get("map_name", "")).empty():
			continue
		seen[id] = true
		out.append({"id": id, "name": str(r.map_name).left(40)})
		if out.size() >= 6:
			break
	return out

func _share_level(level):
	tray = ""
	_post(hub.chat.pack("lv", {"id": level.id, "name": level.name}))

func _moonlight_part(key):
	var moonlight = hub.get_node_or_null("/root/Moonlight")
	return moonlight.get(key) if moonlight != null else null

func _invite_party():
	var party = _moonlight_part("party")
	if party == null:
		return
	var friend = screen.thread
	if party.is_in_lobby():
		screen.show_notice("You're in a custom game. Use Invite to my game.")
		return
	if not party.is_in_party():
		var made = party.create_party(4)
		if made is GDScriptFunctionState:
			yield(made, "completed")
	if not party.is_in_squad():
		screen.show_notice("Couldn't start a party. Try again.")
		return
	tray = ""
	if friend != hub.TEST_ID:
		party.invite_player_to_party(friend)
	_post(hub.chat.pack("py", {"party": str(party.party_id)}))

func _invite_game():
	var party = _moonlight_part("party")
	var lobby = _moonlight_part("lobby")
	if party == null or lobby == null or not party.is_in_lobby() or str(lobby.lobby_code).empty():
		screen.show_notice("Open a custom lobby first, then invite from here.")
		return
	tray = ""
	_post(hub.chat.pack("lb", {"code": str(lobby.lobby_code)}))

func _join_party(pair):
	var party = _moonlight_part("party")
	if party == null:
		return
	if party.is_in_party():
		screen.show_notice("Leave your current party first.")
		return
	screen.show_notice("Joining the party…")
	party.accept_invite_to_party(str(pair[0]), str(pair[1].get("party", "")))

func _join_game(pair):
	var party = _moonlight_part("party")
	var lobby = _moonlight_part("lobby")
	if party == null or lobby == null:
		return
	if party.is_in_party():
		screen.show_notice("Leave your current party first.")
		return
	screen.show_notice("Joining the game…")
	var result = yield(lobby.join_lobby_code(str(pair[1].get("code", ""))), "completed")
	if result is Dictionary and result.has("error") and is_instance_valid(screen):
		screen.show_notice("That game isn't open anymore.")
	elif is_instance_valid(screen):
		screen.close()

func _play_level(data):
	screen.play_level(str(data.get("id", "")))
