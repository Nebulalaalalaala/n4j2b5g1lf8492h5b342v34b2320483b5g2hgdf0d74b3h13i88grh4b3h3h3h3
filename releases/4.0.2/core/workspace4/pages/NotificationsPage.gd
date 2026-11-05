extends Reference

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const Notices = preload("user://mod/core/workspace4/Notices.gd")

var menu
var list: VBoxContainer

func build(owner_menu, content: VBoxContainer) -> void:
	menu = owner_menu
	var actions = Kit.row(content)
	Kit.action(menu, actions, "Mark all read", "check", self, "_mark_read")
	Kit.action(menu, actions, "Clear", "trash", self, "_clear")
	list = Kit.column(content, 8)
	refresh()

func refresh() -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var entries = Notices.all()
	if entries.empty():
		Kit.hint(menu, list, "No notifications.")
		return
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var panel = PanelContainer.new()
		var unread = not bool(entry.get("read", false))
		panel.add_stylebox_override("panel", Galaxy.box(Galaxy.color("surface"), Galaxy.color("accent") if unread else Galaxy.color("border"), 14, 12))
		list.add_child(panel)
		var line = Kit.row(panel, 12)
		var words = Kit.column(line, 2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(menu.label(str(entry.get("title", "")), 16))
		Kit.hint(menu, words, str(entry.get("body", "")))
		words.add_child(menu.label(Notices.age(int(entry.get("time", 0))), 13, Galaxy.color("dim")))
		var route = str(entry.get("route", ""))
		if not route.empty():
			Kit.action(menu, line, "Open", "chev-right", menu, "select", [route])

func _mark_read() -> void:
	Notices.mark_all_read()
	refresh()
	menu.call("_sync_bell")

func _clear() -> void:
	Notices.clear()
	refresh()
	menu.call("_sync_bell")
