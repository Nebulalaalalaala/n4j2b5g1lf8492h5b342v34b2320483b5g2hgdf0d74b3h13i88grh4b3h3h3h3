extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Goobplayability -- Cosmetic Loadouts
#
# Saves named snapshots of the player's legitimately equipped skin and emote
# slots. Equipping a snapshot goes through Goober Dash's normal set_skin and
# equip_emote RPCs, so the result follows the player into public matches.

const SETTINGS_PATH: = ModPaths.COSMETIC_LOADOUTS_CFG
const SLOT_COUNT: = 6

const COLOR_PANEL_BG: = Color(0, 0.129412, 0.262745, 0.98)
const COLOR_CARD_BG: = Color(0.0, 0.18, 0.34, 0.86)
const COLOR_PANEL_BORDER: = Color(0, 0, 0, 0.64)
const COLOR_BLUE: = Color(0.211765, 0.541176, 0.854902)
const COLOR_GREEN: = Color(0.117647, 0.690196, 0.423529)
const COLOR_PINK: = Color(0.8, 0.117647, 0.439216)
const COLOR_ORANGE: = Color(0.95, 0.48, 0.12)
const COLOR_WHITE: = Color.white
const COLOR_TEXT_DIM: = Color(0.72, 0.82, 0.95)

var tas_tool = null
var gui_enabled: = true
var _busy: = false
var _skin_selector: Node = null
var _access_button: Button = null
var _modal_root: Control = null
var _status_label: Label = null
var _slot_rows: = []
var _loadouts: = []


func _ready() -> void:
	layer = 156
	pause_mode = Node.PAUSE_MODE_PROCESS
	for _i in SLOT_COUNT:
		_loadouts.append({})
	_load_settings()
	if not get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().connect("node_added", self, "_on_tree_node_added")


func _exit_tree() -> void:
	if get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().disconnect("node_added", self, "_on_tree_node_added")


func configure(owner_tool) -> void:
	tas_tool = owner_tool
	_build_ui()
	call_deferred("_scan_current_scene")


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if _access_button != null and is_instance_valid(_access_button):
		_access_button.visible = false
	if not value:
		close_window()
	else:
		call_deferred("_scan_current_scene")


func set_claude_experimental_icons_enabled(_value: bool) -> void:
	pass


func is_open() -> bool:
	return _modal_root != null and is_instance_valid(_modal_root) and _modal_root.visible


func open_window() -> void:
	if tas_tool != null and tas_tool.has_method("_open_module_page") and tas_tool._open_module_page("loadouts"):
		return
	if tas_tool != null:
		var studio = tas_tool.get("_cosmetic_sandbox")
		if studio != null and studio.has_method("open_studio"):
			studio.open_studio(1)
			return
	if _modal_root == null or not is_instance_valid(_modal_root):
		return
	_modal_root.visible = true
	_refresh_rows()
	_set_status("Save the outfit you are wearing now, then equip it again with one click.")


func close_window() -> void:
	if _modal_root != null and is_instance_valid(_modal_root):
		_modal_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close_window()
		get_tree().set_input_as_handled()


func _on_tree_node_added(node: Node) -> void:
	if node != null and (node.name == "CustomizeGoober" or _is_skin_selector(node)):
		call_deferred("_consider_node", node)


func _consider_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if _is_skin_selector(node):
		_attach_to_skin_selector(node)
	else:
		_scan_node(node)


func _scan_current_scene() -> void:
	var scene = get_tree().current_scene
	if scene != null:
		_scan_node(scene)


func _scan_node(node: Node) -> bool:
	if _is_skin_selector(node):
		_attach_to_skin_selector(node)
		return true
	for child in node.get_children():
		if _scan_node(child):
			return true
	return false


func _is_skin_selector(node: Node) -> bool:
	return node != null and node.has_method("show_cosmetic_type") and node.has_method("on_cosmetics_button_pressed") and node.has_method("equip_cosmetic")


func _attach_to_skin_selector(selector: Node) -> void:
	if selector == null or not is_instance_valid(selector):
		return
	_skin_selector = selector
	# Looks lives inside Avatar Studio and is opened by Workspace.
	var existing = selector.get_node_or_null("CosmeticLoadoutsButton")
	if existing != null:
		existing.hide()
		_access_button = existing


func _build_ui() -> void:
	if tas_tool == null or not is_instance_valid(tas_tool):
		return
	var root: = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	_modal_root = root

	var shade: = ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.78)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)

	var panel: = PanelContainer.new()
	panel.anchor_left = 0.10
	panel.anchor_top = 0.07
	panel.anchor_right = 0.90
	panel.anchor_bottom = 0.93
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_PANEL_BG, COLOR_PANEL_BORDER, 4, 24))
	root.add_child(panel)

	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)

	var column: = VBoxContainer.new()
	column.add_constant_override("separation", 12)
	margin.add_child(column)

	var header: = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	column.add_child(header)
	var title: Label = _make_label("COSMETIC LOADOUTS", 36, COLOR_WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = _make_button("CLOSE", COLOR_PINK, 140)
	close_button.connect("pressed", self, "close_window")
	header.add_child(close_button)

	_status_label = _make_label("", 18, COLOR_TEXT_DIM)
	_status_label.autowrap = true
	column.add_child(_status_label)

	var note: Label = _make_label("Each slot stores body colour, suit, hat, hand item and all four emotes. Only cosmetics already owned by this account can be equipped.", 17, COLOR_TEXT_DIM)
	note.autowrap = true
	column.add_child(note)

	var scroll: = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var rows: = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_constant_override("separation", 10)
	scroll.add_child(rows)

	for slot_index in SLOT_COUNT:
		var row_data: Dictionary = _build_slot_row(rows, slot_index)
		_slot_rows.append(row_data)
	_refresh_rows()


func _build_slot_row(parent: VBoxContainer, slot_index: int) -> Dictionary:
	var card: = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_CARD_BG, COLOR_PANEL_BORDER, 2, 14))
	parent.add_child(card)
	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 12)
	card.add_child(margin)
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	margin.add_child(row)

	var number: Label = _make_label(str(slot_index + 1), 26, COLOR_WHITE)
	number.rect_min_size = Vector2(34, 0)
	number.valign = Label.VALIGN_CENTER
	row.add_child(number)

	var info: = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_constant_override("separation", 4)
	row.add_child(info)
	var name_field: = LineEdit.new()
	name_field.placeholder_text = "Loadout name"
	name_field.rect_min_size = Vector2(260, 46)
	name_field.add_font_override("font", tas_tool.call("_make_font", 20))
	name_field.connect("text_entered", self, "_on_name_entered", [slot_index])
	info.add_child(name_field)
	var summary: Label = _make_label("Empty slot", 16, COLOR_TEXT_DIM)
	summary.autowrap = true
	info.add_child(summary)

	var equip: Button = _make_button("EQUIP", COLOR_GREEN, 130)
	equip.connect("pressed", self, "_equip_slot", [slot_index])
	row.add_child(equip)
	var save: Button = _make_button("SAVE CURRENT", COLOR_BLUE, 190)
	save.connect("pressed", self, "_save_current_to_slot", [slot_index])
	row.add_child(save)
	var clear: Button = _make_button("CLEAR", COLOR_PINK, 110)
	clear.connect("pressed", self, "_clear_slot", [slot_index])
	row.add_child(clear)

	return {
		"name": name_field,
		"summary": summary,
		"equip": equip,
		"save": save,
		"clear": clear,
	}


func _moonlight():
	return get_node_or_null("/root/Moonlight")


func _storage_get(path: String, default_value):
	var moonlight = _moonlight()
	if moonlight == null or moonlight.get("storage") == null:
		return default_value
	return moonlight.get("storage").call("storage_get", path, default_value)


func _is_logged_in() -> bool:
	var moonlight = _moonlight()
	return moonlight != null and bool(moonlight.call("is_logged_in"))


func _save_current_to_slot(slot_index: int) -> void:
	if _busy or not _valid_slot(slot_index):
		return
	if not _is_logged_in():
		_set_status("Sign in before saving a loadout.", true)
		return
	var skin = _storage_get("player.profile.skin", {})
	var emotes = _storage_get("player.profile.emotes", [])
	if typeof(skin) != TYPE_DICTIONARY:
		skin = {}
	if typeof(emotes) != TYPE_ARRAY:
		emotes = []
	var name_field: LineEdit = _slot_rows[slot_index]["name"]
	var loadout_name: String = name_field.text.strip_edges()
	if loadout_name.empty():
		loadout_name = "Loadout %d" % (slot_index + 1)
	_loadouts[slot_index] = {
		"name": loadout_name,
		"skin": skin.duplicate(true),
		"emotes": emotes.duplicate(true),
	}
	_save_settings()
	_refresh_rows()
	_set_status("Saved %s." % loadout_name)


func _equip_slot(slot_index: int) -> void:
	if _busy or not _valid_slot(slot_index):
		return
	var loadout: Dictionary = _loadouts[slot_index]
	if loadout.empty():
		_set_status("That loadout slot is empty.", true)
		return
	if not _is_logged_in():
		_set_status("Sign in before equipping a loadout.", true)
		return
	var skin = loadout.get("skin", {})
	if typeof(skin) != TYPE_DICTIONARY or skin.empty():
		_set_status("This loadout has no wearable cosmetics.", true)
		return
	_busy = true
	_set_buttons_disabled(true)
	_set_status("Equipping %s…" % str(loadout.get("name", "Loadout")))
	var moonlight = _moonlight()
	var skin_result = yield(moonlight.call("call_rpc", "set_skin", {"cosmetic_ids": skin.values()}), "completed")
	if typeof(skin_result) != TYPE_DICTIONARY or skin_result.has("error"):
		_busy = false
		_set_buttons_disabled(false)
		_set_status("The game server did not accept that loadout. Check that every item is still owned.", true)
		return
	var emotes = loadout.get("emotes", [])
	if typeof(emotes) == TYPE_ARRAY:
		var emote_result = yield(moonlight.call("call_rpc", "equip_emote", {"emote_ids": emotes}), "completed")
		if typeof(emote_result) != TYPE_DICTIONARY or emote_result.has("error"):
			_busy = false
			_set_buttons_disabled(false)
			_set_status("The outfit was equipped, but its emote set could not be applied.", true)
			return
	_busy = false
	_set_buttons_disabled(false)
	_set_status("Equipped %s." % str(loadout.get("name", "Loadout")))


func _clear_slot(slot_index: int) -> void:
	if _busy or not _valid_slot(slot_index):
		return
	_loadouts[slot_index] = {}
	_save_settings()
	_refresh_rows()
	_set_status("Cleared loadout slot %d." % (slot_index + 1))


func _on_name_entered(new_name: String, slot_index: int) -> void:
	if not _valid_slot(slot_index) or _loadouts[slot_index].empty():
		return
	var clean_name: String = new_name.strip_edges()
	if clean_name.empty():
		clean_name = "Loadout %d" % (slot_index + 1)
	_loadouts[slot_index]["name"] = clean_name
	_save_settings()
	_refresh_rows()


func _valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _loadouts.size() and slot_index < _slot_rows.size()


func _refresh_rows() -> void:
	for slot_index in min(_loadouts.size(), _slot_rows.size()):
		var row: Dictionary = _slot_rows[slot_index]
		var loadout: Dictionary = _loadouts[slot_index]
		var name_field: LineEdit = row["name"]
		var summary: Label = row["summary"]
		var equip: Button = row["equip"]
		var clear: Button = row["clear"]
		if loadout.empty():
			name_field.text = ""
			summary.text = "Empty slot"
			equip.disabled = true
			clear.disabled = true
		else:
			name_field.text = str(loadout.get("name", "Loadout %d" % (slot_index + 1)))
			summary.text = _loadout_summary(loadout)
			equip.disabled = _busy
			clear.disabled = _busy


func _loadout_summary(loadout: Dictionary) -> String:
	var skin = loadout.get("skin", {})
	var names: = []
	if typeof(skin) == TYPE_DICTIONARY:
		for key in ["color", "suit", "hat", "hand"]:
			if skin.has(key) and not str(skin[key]).empty():
				names.append(_cosmetic_name(str(skin[key])))
	var emotes = loadout.get("emotes", [])
	var emote_count: int = 0
	if typeof(emotes) == TYPE_ARRAY:
		for emote_id in emotes:
			if not str(emote_id).empty():
				emote_count += 1
	var text: String = ", ".join(names)
	if text.empty():
		text = "Default outfit"
	return "%s  •  %d emote%s" % [text, emote_count, "" if emote_count == 1 else "s"]


func _cosmetic_name(cosmetic_id: String) -> String:
	var data = _storage_get("cosmetics." + cosmetic_id, {})
	if typeof(data) == TYPE_DICTIONARY and not data.empty():
		return str(data.get("name", cosmetic_id))
	return cosmetic_id.replace("_", " ").capitalize()


func _set_buttons_disabled(value: bool) -> void:
	for row in _slot_rows:
		row["equip"].disabled = value or _loadouts[_slot_rows.find(row)].empty()
		row["save"].disabled = value
		row["clear"].disabled = value or _loadouts[_slot_rows.find(row)].empty()


func _set_status(message: String, is_error: bool = false) -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	_status_label.text = message
	_status_label.modulate = COLOR_ORANGE if is_error else COLOR_TEXT_DIM


func _load_settings() -> void:
	var config: = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for slot_index in SLOT_COUNT:
		var value = config.get_value("loadouts", "slot_%d" % slot_index, {})
		if typeof(value) == TYPE_DICTIONARY:
			_loadouts[slot_index] = value.duplicate(true)


func _save_settings() -> void:
	var config: = ConfigFile.new()
	for slot_index in SLOT_COUNT:
		config.set_value("loadouts", "slot_%d" % slot_index, _loadouts[slot_index])
	config.save(SETTINGS_PATH)


func _make_label(text: String, size: int, color: Color) -> Label:
	return tas_tool.call("_make_label", text, tas_tool.call("_make_font", size), color) as Label


func _make_button(text: String, color: Color, width: int) -> Button:
	var button: Button = tas_tool.call("_make_button", text, color, width) as Button
	button.add_font_override("font", tas_tool.call("_make_font", 20))
	return button
