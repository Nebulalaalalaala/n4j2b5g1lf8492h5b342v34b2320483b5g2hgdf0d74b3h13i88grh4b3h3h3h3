extends "user://mod/tools/goober-hub/ui/HubPage.gd"
var code = ""
var field

func build(parent):
	var card = ui.surface(parent, ui.PANEL, 22)
	var col = ui.box(card, true, 14)
	var head = ui.section(col, "Friend requests", "goober", "", ui.SKY)
	ui.action(head, "Refresh", self, "_refresh", null, "quiet", "session", ui.SKY).disabled = hub.friend_service.refreshing
	var add = ui.box(col, false, 10)
	field = ui.field(add, "Friend code or player ID", code, 80)
	field.connect("text_changed", self, "_draft")
	field.connect("text_entered", self, "_send")
	ui.action(add, "Add friend", self, "_send_button", null, "accent", "goober").disabled = hub.friend_service.busy
	var own = ui.box(col, false, 10)
	ui.text(own, "Your code", 16, ui.DIM)
	var label = ui.text(own, "GP-" + hub.store.account, 16, ui.SOFT)
	ui.grow(label)
	ui.action(own, "Copy", self, "_copy", null, "quiet", "", ui.SKY)
	if not hub.friend_service.error.empty(): ui.wrap(col, hub.friend_service.error, 17, ui.GOLD)
	var incoming = hub.friend_service.requests()
	ui.section(col, "Received", "inbox", str(incoming.size()), ui.HUB_PINK)
	if incoming.empty(): ui.text(col, "No incoming requests" if not hub.friend_service.refreshing else "Loading requests…", 18, ui.DIM)
	for request in incoming: _request(col, request, true)
	var outgoing = hub.friend_service.requests(hub.friend_service.SENT)
	if not outgoing.empty():
		ui.section(col, "Sent", "chevron_right", str(outgoing.size()), ui.SKY)
		for request in outgoing: _request(col, request, false)

func _request(parent, request, incoming):
	var panel = ui.inset(parent, 12, 18)
	var row = ui.box(panel, false, 12)
	ui.goober(row, hub.profiles.look_for(request.id), 48, request.id)
	var words = ui.box(row, true, 2)
	ui.grow(words)
	var name = ui.title(words, request.name, 23)
	name.clip_text = true
	ui.text(words, "Wants to be friends" if incoming else "Request pending", 16, ui.DIM)
	ui.action(row, "Profile", screen, "show_profile", request.id, "quiet", "eye", ui.SKY)
	if incoming:
		ui.action(row, "Accept", self, "_act", [request.id, "accept"], "accent", "check").disabled = hub.friend_service.busy
		ui.action(row, "Decline", self, "_act", [request.id, "decline"], "quiet", "close", ui.DIM).disabled = hub.friend_service.busy
	else:
		ui.action(row, "Cancel", self, "_act", [request.id, "cancel"], "quiet", "close", ui.DIM).disabled = hub.friend_service.busy

func _act(pair): hub.friend_service.act(pair[0], pair[1])
func _draft(value): code = str(value)
func _send(value): hub.friend_service.add(value)
func _send_button():
	if is_instance_valid(field): _send(field.text)
func _refresh(): hub.friend_service.refresh(true)
func _copy():
	OS.clipboard = "GP-" + hub.store.account
	screen.show_notice("Friend code copied.")
