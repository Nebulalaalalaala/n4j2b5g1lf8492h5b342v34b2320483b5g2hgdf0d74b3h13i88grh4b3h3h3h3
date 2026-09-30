extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")

const MAX_GROUPS = 64
const MAX_LAYOUTS = 256
const MAX_MEMBERS = 4096
var host
var store
var groups = []
var active = -1
var has_state = false
var list: ItemList
var title_input: LineEdit
var info: Label
var hidden_ids = {}
var locked_ids = {}
var visibility = {}
var suspended = false
var access_pending = false
var hide_button: Button
var lock_button: Button
var manager: AcceptDialog
var saved_list: ItemList
var forget_confirm: ConfirmationDialog
var forget_hash = ""

func build(owner) -> void:
	host = owner
	name = "Groups"
	store = load(get_script().resource_path.get_base_dir().plus_file("EditorRecovery.gd")).new()
	store.directory = ModPaths.EDITOR_PLUS_GROUPS
	add_constant_override("separation", 8)
	var row = host._row(self)
	title_input = LineEdit.new()
	title_input.placeholder_text = "Group name"
	title_input.max_length = 48
	title_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_input)
	_button(row, "Create", "create")
	list = ItemList.new()
	list.rect_min_size = Vector2(360, 145)
	list.connect("item_selected", self, "_pick")
	list.connect("item_activated", self, "_recall")
	add_child(list)
	row = host._row(self)
	_button(row, "Select", "select")
	_button(row, "Rename", "rename")
	_button(row, "Ungroup", "delete")
	row = host._row(self)
	_button(row, "+ Selection", "add")
	_button(row, "− Selection", "remove")
	_button(row, "Save groups", "save")
	row = host._row(self)
	hide_button = _button(row, "Hide group", "hidden")
	lock_button = _button(row, "Lock group", "locked")
	_button(row, "Saved layouts", "manage")
	info = host._label("", 12, Color("9ba8ad"))
	info.autowrap = true
	info.rect_min_size = Vector2(360, 54)
	add_child(info)
	manager = AcceptDialog.new()
	manager.window_title = "Saved group layouts"
	manager.theme = host.panel.theme
	var box = VBoxContainer.new()
	manager.add_child(box)
	box.add_child(host._label("Remove unused layouts to free space. Level files stay untouched.", 12))
	saved_list = ItemList.new()
	saved_list.rect_min_size = Vector2(460, 230)
	box.add_child(saved_list)
	_button(box, "Remove selected saved layout…", "forget")
	add_child(manager)
	forget_confirm = ConfirmationDialog.new()
	forget_confirm.dialog_text = "Remove this saved group layout? Level objects are unchanged. Previous library snapshots are retained as backups."
	forget_confirm.connect("confirmed", self, "forget_saved")
	add_child(forget_confirm)

func _button(parent, text: String, action: String) -> Button:
	var button = host._button(parent, text, "_refresh")
	button.disconnect("pressed", host, "_refresh")
	button.connect("pressed", self, "act", [action])
	return button

func _pick(index: int) -> void:
	active = index
	title_input.text = groups[index].name
	refresh()

func _recall(index: int) -> void:
	active = index
	act("select")

func _ids() -> Array:
	var result = []
	for node in host.selected():
		result.append(node.level_node_index)
	return result

func _nodes(ids: Array) -> Array:
	var result = []
	if not host.available():
		return result
	for id in ids:
		var node = host.editor.level.get_level_node(id)
		if node != null:
			result.append(node)
	return result

func act(action: String) -> void:
	if not host.available():
		return
	if action == "manage":
		show_saved()
		return
	if action == "forget":
		if not saved_list.get_selected_items().empty():
			forget_hash = saved_list.get_item_metadata(saved_list.get_selected_items()[0])
			if forget_hash == _layout().get("hash", ""):
				host.message.text = "The open layout cannot be removed. Choose an unused layout."
			else:
				forget_confirm.popup_centered(Vector2(480, 160))
		return
	if action == "save":
		save_groups()
		return
	if action != "create" and (active < 0 or active >= groups.size()):
		host.message.text = "Choose a group first."
		return
	if action == "select":
		host.editor.select_tool(LevelEditor.Tool.Select, true)
		host.editor.tool_select.set_selected_nodes(_nodes(groups[active].members))
		return
	var changed = groups.duplicate(true)
	var ids = _ids()
	var next_active = active
	if action in ["create", "rename"]:
		var title = title_input.text.strip_edges()
		if title.empty() or title.length() > 48:
			host.message.text = "Enter a group name (1–48 characters)."
			return
		for i in range(groups.size()):
			if (action == "create" or i != active) and groups[i].name.to_lower() == title.to_lower():
				host.message.text = "That group name is already used."
				return
		if action == "create":
			if ids.empty() or ids.size() > MAX_MEMBERS or groups.size() >= MAX_GROUPS:
				host.message.text = "Select 1–4096 objects; up to 64 groups per layout."
				return
			changed.append({"name": title, "members": ids})
			next_active = changed.size() - 1
		else:
			changed[active].name = title
	elif action == "delete":
		changed.remove(active)
		next_active = min(active, changed.size() - 1)
	elif action in ["hidden", "locked"]:
		changed[active][action] = not bool(changed[active].get(action, false))
	elif action in ["add", "remove"]:
		for id in ids:
			if action == "add" and not changed[active].members.has(id):
				changed[active].members.append(id)
			elif action == "remove":
				changed[active].members.erase(id)
		if changed[active].members.size() > MAX_MEMBERS:
			host.message.text = "Group limit: 4096 objects."
			return
	else:
		return
	if var2str(changed) == var2str(groups):
		return
	host.editor.undo.create_action("Editor+ Group " + action)
	host.editor.undo.add_do_method(self, "_apply", changed, next_active)
	host.editor.undo.add_undo_method(self, "_apply", groups.duplicate(true), active)
	host.editor.undo.commit_action()

func _apply(value: Array, index: int) -> void:
	has_state = true
	groups = value.duplicate(true)
	active = index
	apply_access()
	refresh()
	host.message.text = "Groups updated. Undo/Redo supported."
	save_groups()

func refresh() -> void:
	if list == null:
		return
	list.clear()
	for group in groups:
		var live = _nodes(group.members).size()
		var flags = (" · Hidden" if group.get("hidden", false) else "") + (" · Locked" if group.get("locked", false) else "")
		list.add_item("%s  ·  %d objects%s%s" % [group.name, live, " (some deleted)" if live < group.members.size() else "", flags])
	if active >= 0 and active < groups.size():
		list.select(active)
	var chosen = active >= 0 and active < groups.size()
	hide_button.disabled = not chosen or not host.available()
	lock_button.disabled = hide_button.disabled
	hide_button.text = "Show group" if chosen and groups[active].get("hidden", false) else "Hide group"
	lock_button.text = "Unlock group" if chosen and groups[active].get("locked", false) else "Lock group"
	info.text = "Local selection groups · Double-click to select.\nSaved on group edits, level save and exit. Restores matching layouts only; not included in shared levels."

func _layout() -> Dictionary:
	if not is_instance_valid(host.editor) or host.editor.level.loaded_level == null:
		return {}
	var nodes = []
	var ids = []
	for node in host.editor.level.loaded_level.get_children():
		if node is LevelNode:
			nodes.append(node.serialize_level_node())
			ids.append(node.level_node_index)
	return {"hash": JSON.print(nodes).sha256_text(), "ids": ids, "count": ids.size()}

func save_groups() -> void:
	if groups.empty() and not has_state:
		return
	var layout = _layout()
	if layout.empty():
		return
	var entries = []
	for group in groups:
		var indices = []
		for id in group.members:
			var index = layout.ids.find(id)
			if index >= 0:
				indices.append(index)
		entries.append({"name": group.name, "members": indices, "hidden": group.get("hidden", false), "locked": group.get("locked", false)})
	var library = _read_library()
	if library == null:
		host.message.text = "Groups: saved library is invalid; existing files left untouched."
		return
	var record = {"metadata": {"name": host.editor.level.loaded_level.level_name, "layout": layout.hash, "count": layout.count, "version": 1}, "nodes": entries}
	var found = false
	for i in range(library.size()):
		if library[i].metadata.layout == layout.hash:
			library[i] = record
			found = true
			break
	if not found:
		if library.size() >= MAX_LAYOUTS:
			host.message.text = "Groups: saved-layout limit reached. Use Saved layouts to free a slot; existing groups are preserved."
			return
		library.append(record)
	var result = store.save({"metadata": {"name": "Group library", "version": 2}, "nodes": library}, "Group library", true)
	if not result.begins_with("Saved") and not result.begins_with("No changes"):
		host.message.text = "Groups: " + result
	elif list.is_visible_in_tree():
		host.message.text = "Groups saved locally. Undo/Redo supported."

func load_groups() -> void:
	restore_visibility()
	groups = []
	has_state = false
	active = -1
	store.last_hash = ""
	var layout = _layout()
	if not layout.empty():
		var library = _read_library()
		if library != null:
			for data in library:
				if not _valid(data, layout):
					continue
				has_state = true
				for group in data.nodes:
					var ids = []
					for index in group.members:
						ids.append(layout.ids[int(index)])
					groups.append({"name": group.name, "members": ids, "hidden": group.get("hidden", false), "locked": group.get("locked", false)})
				break
	apply_access()
	refresh()

func _read_library():
	var files = store._files()
	if files.empty():
		return []
	for file in files:
		var data = store.read(file)
		if not data.get("metadata", null) is Dictionary or data.metadata.get("version", 0) != 2 or not data.get("nodes", null) is Array or data.nodes.size() > MAX_LAYOUTS:
			continue
		var valid = true
		var seen = []
		for record in data.nodes:
			if not record is Dictionary or not record.get("metadata", null) is Dictionary:
				valid = false
				break
			var hash_value = record.metadata.get("layout", null)
			var count = record.metadata.get("count", null)
			if not hash_value is String or hash_value.length() != 64 or seen.has(hash_value) or not typeof(count) in [TYPE_INT, TYPE_REAL]:
				valid = false
				break
			if is_nan(float(count)) or is_inf(float(count)) or count < 0 or count > 1000000 or count != int(count) or not _valid(record, {"hash": hash_value, "count": int(count)}):
				valid = false
				break
			seen.append(hash_value)
		if valid:
			return data.nodes
	return null

func _valid(data: Dictionary, layout: Dictionary) -> bool:
	if not data.get("metadata", null) is Dictionary or data.metadata.get("version", 0) != 1 or data.metadata.get("layout", "") != layout.hash:
		return false
	if not data.get("nodes", null) is Array or data.nodes.size() > MAX_GROUPS:
		return false
	var names = []
	for group in data.nodes:
		if not group is Dictionary or not group.get("name", null) is String or not group.get("members", null) is Array:
			return false
		if group.name.strip_edges().empty() or group.name.length() > 48 or names.has(group.name.to_lower()) or group.members.size() > MAX_MEMBERS:
			return false
		if not group.get("hidden", false) is bool or not group.get("locked", false) is bool:
			return false
		names.append(group.name.to_lower())
		var seen = []
		for index in group.members:
			if not typeof(index) in [TYPE_INT, TYPE_REAL] or is_nan(float(index)) or is_inf(float(index)) or index != int(index) or index < 0 or index >= layout.count or seen.has(int(index)):
				return false
			seen.append(int(index))
	return true

func blocked(id: int) -> bool:
	return not suspended and (hidden_ids.has(id) or locked_ids.has(id))

func restore_visibility() -> void:
	for state in visibility.values():
		if is_instance_valid(state.node):
			state.node.visible = state.visible
	visibility.clear()

func apply_access() -> void:
	restore_visibility()
	hidden_ids.clear()
	locked_ids.clear()
	if not is_instance_valid(host.editor):
		return
	suspended = host.editor.is_playing
	for group in groups:
		for id in group.members:
			if group.get("hidden", false):
				hidden_ids[id] = true
			if group.get("locked", false):
				locked_ids[id] = true
	if not suspended:
		for id in hidden_ids:
			var node = host.editor.level.get_level_node(id)
			if node != null:
				visibility[node.get_instance_id()] = {"node": node, "visible": node.visible}
				node.visible = false
	if host.editor.tool_select.has_method("refresh_group_access"):
		host.editor.tool_select.refresh_group_access()

func node_added(_node) -> void:
	if not access_pending:
		access_pending = true
		call_deferred("_deferred_access")

func _deferred_access() -> void:
	access_pending = false
	apply_access()

func leave_level() -> void:
	save_groups()
	restore_visibility()

func _exit_tree() -> void:
	restore_visibility()

func show_saved() -> void:
	var library = _read_library()
	if library == null:
		host.message.text = "Group library could not be read. Existing files left untouched."
		return
	saved_list.clear()
	for record in library:
		saved_list.add_item("%s · %d groups · %s" % [record.metadata.get("name", "Layout"), record.nodes.size(), record.metadata.layout.substr(0, 8)])
		saved_list.set_item_metadata(saved_list.get_item_count() - 1, record.metadata.layout)
	manager.window_title = "Saved group layouts · %d / %d" % [library.size(), MAX_LAYOUTS]
	manager.popup_centered(Vector2(520, 340))

func forget_saved() -> void:
	if forget_hash.empty() or forget_hash == _layout().get("hash", ""):
		return
	var library = _read_library()
	if library == null:
		return
	var next = []
	for record in library:
		if record.metadata.layout != forget_hash:
			next.append(record)
	if next.size() == library.size():
		return
	var result = store.save({"metadata": {"name": "Group library", "version": 2}, "nodes": next}, "Removed saved group layout", false)
	host.message.text = "Saved layout removed; original level unchanged." if result.begins_with("Saved") else result
	forget_hash = ""
	show_saved()
