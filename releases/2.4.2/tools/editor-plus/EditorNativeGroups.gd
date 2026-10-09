extends Reference

# Native presentation only. EditorGroups still owns persistence, group access
# and transactions; grouping must never change level object geometry.
var ui
var name_field
var choice
var create_button
var select_button
var remove_button
var names = []

func build(owner, parent) -> void:
	ui = owner
	ui.controls.label(parent,"Groups",true)
	var row = ui.controls.row(parent)
	name_field = ui.controls.field(row,"Optional name for the new selection group")
	name_field.max_length = 48
	name_field.placeholder_text = "New group name"
	name_field.connect("text_entered",self,"_create")
	create_button = ui.controls.button(row,"Group",self,"_create",[""])
	create_button.hint_tooltip = "Group the selected objects. A name is optional. Undo supported."
	create_button.size_flags_horizontal = Control.SIZE_FILL
	create_button.rect_min_size.x = 144
	row = ui.controls.row(parent)
	choice = OptionButton.new()
	choice.theme = ui.controls.NATIVE_THEME
	choice.add_font_override("font",ui.controls.number_font)
	choice.get_popup().add_font_override("font",ui.controls.number_font)
	choice.rect_min_size = Vector2(0,76)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.clip_text = true
	choice.align = Button.ALIGN_CENTER
	choice.hint_tooltip = "Choose a saved selection group"
	choice.connect("item_selected",self,"_pick")
	row.add_child(choice)
	select_button = ui.controls.button(row,"Select",self,"_act",["select"])
	select_button.size_flags_horizontal = Control.SIZE_FILL
	select_button.rect_min_size.x = 144
	row = ui.controls.row(parent)
	remove_button = ui.controls.button(row,"Ungroup",self,"_act",["delete"])
	remove_button.hint_tooltip = "Remove the selected group; its level objects stay unchanged. Undo supported."
	ui.controls.button(row,"Manage groups",self,"_manage").hint_tooltip = "Rename, add/remove members, hide/lock groups and manage saved layouts"

func _create(_text: String) -> void:
	var groups = ui.host.groups_panel
	var title = name_field.text.strip_edges()
	if title.empty():
		var number = 1
		var existing = []
		for group in groups.groups: existing.append(group.name.to_lower())
		while existing.has("group "+str(number)): number += 1
		title = "Group "+str(number)
	groups.title_input.text = title
	var previous_count = groups.groups.size()
	_act("create")
	if groups.groups.size() > previous_count:
		name_field.text = ""

func _pick(index: int) -> void:
	if index >= 0 and index < ui.host.groups_panel.groups.size():
		ui.host.groups_panel._pick(index)
		refresh()

func _act(action: String) -> void:
	ui.host.groups_panel.act(action)
	ui.status.text = ui.host.message.text
	ui.refresh()

func _manage() -> void:
	ui.show_section(3)

func refresh() -> void:
	var groups = ui.host.groups_panel
	var current = []
	for group in groups.groups: current.append(group.name)
	if current != names:
		names = current
		choice.clear()
		for title in names: choice.add_item(title)
	if names.empty() and choice.get_item_count() == 0:
		choice.add_item("No groups yet")
	choice.disabled = names.empty() or not ui.host.available()
	if groups.active >= 0 and groups.active < names.size(): choice.select(groups.active)
	var chosen = not choice.disabled and groups.active >= 0 and groups.active < names.size()
	create_button.disabled = ui.host.selected().empty()
	select_button.disabled = not chosen
	remove_button.disabled = not chosen
