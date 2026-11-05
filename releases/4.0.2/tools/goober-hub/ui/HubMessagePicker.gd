extends "user://mod/tools/goober-hub/ui/HubPage.gd"
var search = ""
var list

func build(parent):
	var panel = ui.surface(parent, ui.PANEL, 18, 22)
	ui.grow(panel, true, true)
	panel.rect_min_size.y = 560
	var col = ui.box(panel, true, 12)
	var head = ui.section(col, "New message", "inbox", "", ui.SKY)
	ui.action(head, "Cancel", screen.builders.Messages, "_cancel_picker", null, "quiet", "close", ui.DIM)
	var field = ui.field(col, "Find a friend", search, 80)
	field.connect("text_changed", self, "_search")
	list = ui.box(col, true, 8)
	_fill()

func _search(value):
	search = str(value)
	_fill()

func _fill():
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var count = 0
	for friend in hub.friends():
		if not search.empty() and (friend.name + " " + friend.id).to_lower().find(search.to_lower()) < 0: continue
		count += 1
		var panel = ui.inset(list, 12, 18)
		var row = ui.box(panel, false, 12)
		ui.goober(row, hub.profiles.look_for(friend.id), 46, friend.id)
		var name = ui.title(row, friend.name, 22)
		name.clip_text = true
		ui.grow(name)
		ui.text(row, "Online" if friend.online else "Offline", 16, ui.MINT if friend.online else ui.DIM)
		ui.action(row, "Chat", screen.builders.Messages, "_open", friend.id, "accent", "inbox")
	if count == 0:
		ui.text(list, "No matching friends" if not hub.friends().empty() else "Add a friend to start chatting", 18, ui.DIM)
		if hub.friends().empty(): ui.action(list, "Add friend", screen, "friend_requests", null, "quiet", "goober", ui.SKY)
