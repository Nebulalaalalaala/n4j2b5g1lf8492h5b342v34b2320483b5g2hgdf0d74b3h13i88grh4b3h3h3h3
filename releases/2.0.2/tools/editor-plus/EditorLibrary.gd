extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")

var host
var store
var directory = "user://levels"
var labels = {}
var files = []
var selected_file = ""
var search: LineEdit
var folder_filter: OptionButton
var list: ItemList
var folder: LineEdit
var tags: LineEdit
var confirm: ConfirmationDialog
var healthy = true

func build(owner) -> void:
	host = owner
	name = "Library"
	store = load(get_script().resource_path.get_base_dir().plus_file("EditorRecovery.gd")).new()
	store.directory = ModPaths.EDITOR_PLUS_LIBRARY
	var row = host._row(self)
	search = LineEdit.new()
	search.placeholder_text = "Search names, folders or tags"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.connect("text_changed", self, "_filter")
	row.add_child(search)
	button(row, "Refresh", "scan")
	folder_filter = OptionButton.new()
	host.properties._style_choice(folder_filter)
	folder_filter.connect("item_selected", self, "_filter")
	add_child(folder_filter)
	list = ItemList.new()
	list.rect_min_size = Vector2(380, 170)
	list.connect("item_selected", self, "pick")
	list.connect("item_activated", self, "ask_open")
	add_child(list)
	folder = LineEdit.new()
	folder.placeholder_text = "Folder · e.g. Projects / Racing"
	folder.max_length = 120
	add_child(folder)
	tags = LineEdit.new()
	tags.placeholder_text = "Tags · comma-separated"
	tags.max_length = 400
	add_child(tags)
	row = host._row(self)
	button(row, "Save labels", "save_labels")
	button(row, "Open selected", "ask_open")
	var note = host._label("Local level files · Virtual folders; files stay in place.\nOpening backs up the current level and starts new undo history.", 12, Color("9ba8ad"))
	note.autowrap = true
	note.rect_min_size = Vector2(380, 44)
	add_child(note)
	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Open this local level? Your current level will be backed up first. Undo history will reset."
	confirm.connect("confirmed", self, "open_selected")
	add_child(confirm)
	load_labels()
	scan()

func button(parent, text: String, method: String) -> void:
	var control = host._button(parent, text, "_refresh")
	control.disconnect("pressed", host, "_refresh")
	control.connect("pressed", self, method)

func valid(data: Dictionary) -> bool:
	if not data.get("metadata", null) is Dictionary or data.metadata.get("version", 0) != 1 or not data.get("nodes", null) is Dictionary or data.nodes.size() > 2000:
		return false
	for key in data.nodes:
		var value = data.nodes[key]
		if not key is String or key.get_file() != key or not key.ends_with(".json") or not value is Dictionary:
			return false
		if not value.get("folder", null) is String or value.folder.length() > 120 or not value.get("tags", null) is Array or value.tags.size() > 16:
			return false
		for tag in value.tags:
			if not tag is String or tag.empty() or tag.length() > 32:
				return false
	return true

func load_labels() -> void:
	labels = {}
	healthy = store._files().empty()
	for file in store._files():
		var data = store.read(file)
		if valid(data):
			labels = data.nodes.duplicate(true)
			healthy = true
			break

func scan() -> void:
	files.clear()
	var dir = Directory.new()
	if dir.open(directory) == OK:
		dir.list_dir_begin(true, true)
		var file = dir.get_next()
		while not file.empty():
			if not dir.current_is_dir() and file.ends_with(".json"):
				files.append(file)
			file = dir.get_next()
		dir.list_dir_end()
	files.sort()
	refresh_folders()
	_filter()

func refresh_folders() -> void:
	var previous = folder_filter.get_item_text(folder_filter.selected) if folder_filter.selected >= 0 else "All folders"
	folder_filter.clear()
	folder_filter.add_item("All folders")
	folder_filter.add_item("Unfiled")
	var folders = []
	for file in files:
		var name_value = str(labels.get(file, {}).get("folder", ""))
		if not name_value.empty() and not folders.has(name_value):
			folders.append(name_value)
	folders.sort()
	for value in folders:
		folder_filter.add_item(value)
	for index in range(folder_filter.get_item_count()):
		if folder_filter.get_item_text(index) == previous:
			folder_filter.select(index)

func _filter(_unused = null) -> void:
	list.clear()
	for file in files:
		var value = labels.get(file, {"folder": "", "tags": []})
		var wanted = folder_filter.get_item_text(folder_filter.selected)
		if folder_filter.selected == 1 and not value.folder.empty():
			continue
		if folder_filter.selected > 1 and value.folder != wanted:
			continue
		var text = file.trim_suffix(".json") + " · " + ("Unfiled" if value.folder.empty() else value.folder)
		if not value.tags.empty():
			text += " · #" + PoolStringArray(value.tags).join(" #")
		if not search.text.strip_edges().empty() and not search.text.strip_edges().to_lower() in text.to_lower():
			continue
		list.add_item(text)
		list.set_item_metadata(list.get_item_count() - 1, file)
		if file == selected_file:
			list.select(list.get_item_count() - 1)

func pick(index: int) -> void:
	selected_file = list.get_item_metadata(index)
	var value = labels.get(selected_file, {"folder": "", "tags": []})
	folder.text = value.folder
	tags.text = PoolStringArray(value.tags).join(", ")

func save_labels() -> void:
	if not healthy or not files.has(selected_file):
		host.message.text = "Choose a local level; an invalid label library will not be overwritten."
		return
	var parsed = []
	for part in tags.text.split(",", false):
		var tag = part.strip_edges().to_lower()
		if tag.empty():
			continue
		if tag.length() > 32:
			host.message.text = "Each tag must be 32 characters or fewer."
			return
		if not parsed.has(tag):
			parsed.append(tag)
	if parsed.size() > 16 or (not labels.has(selected_file) and labels.size() >= 2000):
		host.message.text = "Limit: 16 tags per level, 2000 labeled files."
		return
	var next = labels.duplicate(true)
	next[selected_file] = {"folder": folder.text.strip_edges(), "tags": parsed}
	if next[selected_file].folder.empty() and parsed.empty():
		next.erase(selected_file)
	var payload = {"metadata": {"name": "Level folders and tags", "version": 1}, "nodes": next}
	if not valid(payload):
		return
	var result = store.save(payload, "Level labels", false)
	if result.begins_with("Saved"):
		labels = next
		refresh_folders()
		_filter()
		host.message.text = "Folder and tags saved locally. Level file unchanged."
	else:
		host.message.text = result

func ask_open(index: int = -1) -> void:
	if index >= 0:
		pick(index)
	if host.available() and files.has(selected_file):
		confirm.popup_centered(Vector2(460, 150))

func open_selected() -> void:
	if not host.available() or not files.has(selected_file) or selected_file.get_file() != selected_file:
		return
	var file = File.new()
	if file.open(directory.plus_file(selected_file), File.READ) != OK:
		host.message.text = "Level file is no longer available. Refresh the library."
		return
	if file.get_len() > 2 * 1024 * 1024:
		file.close()
		host.message.text = "Level exceeds the 2 MB library load limit."
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error == OK and parsed.result is Dictionary and parsed.result.get("nodes", null) is Array:
		for node in parsed.result.nodes:
			if node is Dictionary:
				for key in ["rotation", "shape_rotation", "pivot_x", "pivot_y"]:
					if not node.has(key):
						node[key] = 0.5 if key.begins_with("pivot") else 0
	if parsed.error != OK or not parsed.result is Dictionary or not host.recovery.valid_level(parsed.result, host.editor.node_factory.node_types):
		host.message.text = "Level is invalid or uses unsupported objects. Nothing changed."
		return
	if not host.recovery.save(LevelJson.serialize_level(host.editor.level.loaded_level), "Before library load", false).begins_with("Saved"):
		host.message.text = "Open cancelled: current level could not be backed up."
		return
	host.groups_panel.save_groups()
	host.editor.level.load_level(LevelJson.deserialize_level(parsed.result, host.editor.node_factory), LevelLoader.LevelLoadLocation.Local)
	host.message.text = "Opened local level. Use the game's normal Save when ready."
