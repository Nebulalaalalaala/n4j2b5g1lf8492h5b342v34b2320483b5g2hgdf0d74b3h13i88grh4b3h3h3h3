extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")
var host
var store
var title_field
var list
var delete_pending = ""
var placement
var preview_buttons = []

func build(owner):
	host = owner
	store = load(ModPaths.path("EditorStampStore.gd")).new()
	store.load_local()
	add_constant_override("separation",8)
	add_child(host._label("EDITOR STAMPS",14))
	title_field = LineEdit.new()
	title_field.placeholder_text = "Stamp name"
	title_field.max_length = 60
	add_child(title_field)
	var actions = host._row(self)
	_button(actions,"Save selection","save_selection")
	_button(actions,"Refresh stamps","refresh")
	list = ItemList.new()
	list.rect_min_size = Vector2(0,180)
	add_child(list)
	actions = host._row(self)
	_button(actions,"Place stamp","place_selected")
	_button(actions,"Delete stamp","remove_selected")
	actions = host._row(self)
	preview_buttons = [_button(actions,"Rotate shapes","rotate_preview"),_button(actions,"Flip H","flip_preview_h"),_button(actions,"Flip V","flip_preview_v"),_button(actions,"Cancel","cancel_preview")]
	var note = host._label("Place stamp previews at your cursor. Click to place · Esc cancels · Undo removes the whole stamp. Share from Goober Hub → Profile → Creations.",12)
	note.autowrap = true
	add_child(note)
	refresh()

func _button(parent, text, method):
	var button = host._button(parent,text,"_refresh")
	button.disconnect("pressed",host,"_refresh")
	button.connect("pressed",self,method)
	return button

func _refresh_preview_buttons():
	for button in preview_buttons:
		if is_instance_valid(button): button.disabled = not is_instance_valid(placement) or not placement.active

func refresh():
	if list == null: return
	var index = list.get_selected_items()[0] if not list.get_selected_items().empty() else -1
	store.load_local()
	list.clear()
	for entry in store.entries:
		list.add_item("%s · %d objects" % [entry.name,entry.payload.nodes.size()])
	if index >= 0 and index < list.get_item_count(): list.select(index)
	delete_pending = ""
	_refresh_preview_buttons()

func save_selection():
	if not host.available() or host.selected().empty():
		host.message.text = "Select objects in the editor first."
		return
	var nodes = []
	for node in host.selected():
		var data = node.serialize_level_node().duplicate(true)
		data.erase("level_node_index")
		nodes.append(data)
	store.load_local()
	host.message.text = store.add(title_field.text,{"version":1,"nodes":nodes})
	refresh()

func place_selected():
	if list.get_selected_items().empty():
		host.message.text = "Select a saved stamp first."
		return
	cancel_preview()
	placement = load(ModPaths.path("EditorStampPlacement.gd")).new()
	placement.stamps = self
	add_child(placement)
	if not placement.begin(store.entries[list.get_selected_items()[0]].payload):
		cancel_preview()
		host.message.text = "Open an editable level first."
	_refresh_preview_buttons()

func rotate_preview():
	if is_instance_valid(placement): placement.transform_preview("rotate")

func flip_preview_h():
	if is_instance_valid(placement): placement.transform_preview("horizontal")

func flip_preview_v():
	if is_instance_valid(placement): placement.transform_preview("vertical")

func cancel_preview():
	if is_instance_valid(placement): placement.cancel()
	placement = null

func place(payload, target = null) -> bool:
	var rules = load(ModPaths.path("EditorStampStore.gd"))
	if not host.available() or not rules.valid(payload): return false
	var selection = host.editor.tool_select
	if not selection.has_method("_restore_paste"): return false
	var temporary = []
	for data in payload.nodes:
		if not data.type in host.editor.node_factory.node_types:
			for node in temporary: node.free()
			return false
		var node = LevelJson.deserialize_level_node(data.duplicate(true),host.editor.node_factory)
		if node == null:
			for prior in temporary: prior.free()
			return false
		node.level_node_index = -1
		# Native construction normalizes small blocks. Reapply their serialized
		# geometry through the same Editor+ repair path before native cloning.
		if is_instance_valid(selection.editor_geometry): selection.editor_geometry.restore(node,data)
		temporary.append(node)
	var before = selection.copied_nodes
	selection.copied_nodes = temporary
	# Exactly the current editor's native paste + Editor+ Undo path. Never change clipboard contents.
	var centre = host.editor.level_editor_camera.get_camera_screen_center()
	selection._paste_at_grid_location(LevelGrid2.world_to_grid_rounded_2d(centre) if target==null else target,true)
	selection.copied_nodes = before
	for node in temporary: node.free()
	host.message.text = "Stamp placed. Undo removes the whole stamp."
	return true

func remove_selected():
	if list.get_selected_items().empty(): return
	# Confirm by repeating the action on the same selection; no off-theme OS dialog.
	var index = list.get_selected_items()[0]
	if delete_pending != store.entries[index].id:
		delete_pending = store.entries[index].id
		host.message.text = "Press Delete stamp again to remove %s. Placed level objects stay unchanged." % store.entries[index].name
		return
	store.remove(store.entries[index].id)
	refresh()
