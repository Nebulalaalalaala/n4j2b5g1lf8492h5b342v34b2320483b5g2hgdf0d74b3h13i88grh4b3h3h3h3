extends VBoxContainer

const KEY = "_goobplayability_laser"
const FIELDS = ["lasing_duration_ticks", "pause_duration_ticks", "timing_offset"]
var host
var inputs = {}
var status: Label

func build(owner) -> void:
	host = owner
	name = "Lasers"
	add_constant_override("separation", 10)
	status = host._label("Select lasers to edit their cycle.", 14)
	status.autowrap = true
	status.rect_min_size = Vector2(380, 45)
	add_child(status)
	for pair in [[FIELDS[0], "Active ticks", 120], [FIELDS[1], "Pause ticks", 120], [FIELDS[2], "Offset ticks", 0]]:
		var row = host._row(self)
		var label = host._label(pair[1], 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var field = SpinBox.new()
		field.rect_min_size.x = 110
		field.min_value = 1 if pair[0] == FIELDS[0] else 0
		field.max_value = 3600
		field.value = pair[2]
		row.add_child(field)
		inputs[pair[0]] = field
	var row = host._row(self)
	for pair in [["Apply cycle", false], ["Reset native cycle", true]]:
		var button = host._button(row, pair[0], "_refresh")
		button.disconnect("pressed", host, "_refresh")
		button.connect("pressed", self, "change", [pair[1]])
	var note = host._label("Modded local playtests only. Native charge time is retained; active duration is at least charge time + 1 tick. Pause 0 means always on.\n\nUnmodified clients and official servers do not apply these custom settings.", 13, Color("9ba8ad"))
	note.autowrap = true
	note.rect_min_size = Vector2(380, 105)
	add_child(note)

func _ready() -> void:
	get_tree().connect("node_added", self, "observe")

func observe(node) -> void:
	if node is LevelNode and node.node_type == "laser" and valid(node.properties.get(KEY)):
		call_deferred("apply_runtime", node)

func valid(value) -> bool:
	if not value is Dictionary:
		return false
	for key in FIELDS:
		var number = value.get(key)
		if not typeof(number) in [TYPE_INT, TYPE_REAL] or is_nan(float(number)) or is_inf(float(number)) or int(number) != number or number < (1 if key == FIELDS[0] else 0) or number > 3600:
			return false
	return true

func apply_runtime(node) -> void:
	if not is_instance_valid(node) or not valid(node.properties.get(KEY)):
		return
	var game = Utilities.find_game(node, false)
	# Never replace server-owned values on an online client.
	if game == null or not game.is_server():
		return
	var laser = game.get_object_for_object_id(node.network_object_id)
	if not laser is Laser_NetworkObject:
		return
	var values = node.properties[KEY]
	laser.lasing_duration_ticks = max(int(values[FIELDS[0]]), int(game.wp_game_data.laser_charge_ticks) + 1)
	laser.pause_duration_ticks = int(values[FIELDS[1]])
	laser.timing_offset = int(values[FIELDS[2]])

func change(reset: bool) -> void:
	var nodes = host.selected()
	if nodes.empty():
		return
	for node in nodes:
		if node.node_type != "laser":
			status.text = "Select only lasers. Nothing changed."
			return
	var value = {}
	for key in FIELDS:
		value[key] = int(inputs[key].value)
	var before = []
	var after = []
	for node in nodes:
		var original = node.properties.get(KEY)
		before.append({"id": node.level_node_index, "value": original.duplicate(true) if original is Dictionary else original})
		after.append({"id": node.level_node_index, "value": null if reset else value.duplicate(true)})
	if var2str(before) == var2str(after):
		return
	host.editor.undo.create_action("Editor+ Laser cycle")
	host.editor.undo.add_do_method(self, "apply_states", after)
	host.editor.undo.add_undo_method(self, "apply_states", before)
	host.editor.undo.commit_action()

func apply_states(states: Array) -> void:
	if not host.available():
		return
	for state in states:
		var node = host.editor.level.get_level_node(state.id)
		if node == null:
			continue
		if state.value == null:
			node.properties.erase(KEY)
		else:
			node.properties[KEY] = state.value.duplicate(true) if state.value is Dictionary else state.value
	refresh()

func refresh() -> void:
	if status == null:
		return
	var values = []
	for node in host.selected():
		if node.node_type != "laser":
			status.text = "Select only lasers to edit their cycle."
			return
		var data = node.properties.get(KEY, {})
		if not values.has(var2str(data)):
			values.append(var2str(data))
	status.text = "Select lasers to edit their cycle." if values.empty() else ("Mixed cycles · Apply replaces all selected cycles." if values.size() > 1 else "Native cycle" if values[0] == var2str({}) else "Custom cycle · Local playtest only")
	if values.size() == 1:
		var data = host.selected()[0].properties.get(KEY, {})
		for key in FIELDS:
			if not inputs[key].get_line_edit().has_focus():
				inputs[key].value = data.get(key, 0 if key == FIELDS[2] else 120)
