extends Reference

# Level objects whose state is not part of a player snapshot.
# Lasers run off the race clock (play_time + timing_offset). The race clock is
# never rewound, so a checkpoint restore shifts each laser's offset instead,
# the same way moving platforms are re-phased. Disappearing blocks/rechargers
# keep counters; free physics blocks keep body pose/momentum. These values are
# stored at checkpoints and as sparse native-frame updates for seeks/playback.

const BLOCK_FIELDS = ["is_disappearing", "disappearing_counter", "reappear"]
const RECHARGER_FIELDS = ["recharge_counter"]
const RIGID_FIELDS = ["position", "rotation", "velocity", "angular_velocity"]

var level_id = 0
var child_count = -1
var lasers = []    # [object, period]
var stateful = []  # [object_id, object, fields, optional physical body]
var block_nodes = {}
var shift_ticks = 0
var shift_level = 0

func _refresh(game) -> void:
	var loaded = game.level.loaded_level if game != null and game.level != null else null
	if loaded == null:
		level_id = 0
		lasers.clear()
		stateful.clear()
		block_nodes.clear()
		return
	if loaded.get_instance_id() == level_id and loaded.get_child_count() == child_count:
		return
	level_id = loaded.get_instance_id()
	child_count = loaded.get_child_count()
	lasers.clear()
	stateful.clear()
	block_nodes.clear()
	for child in loaded.get_children():
		if not ("network_object_id" in child):
			continue
		var object = game.get_object_for_object_id(child.network_object_id)
		if object == null:
			continue
		if "timing_offset" in object and "pause_duration_ticks" in object and "lasing_duration_ticks" in object:
			lasers.append(object)
		elif "disappearing_counter" in object:
			stateful.append([int(child.network_object_id), object, BLOCK_FIELDS])
			block_nodes[int(child.network_object_id)] = child
		elif "recharge_counter" in object:
			stateful.append([int(child.network_object_id), object, RECHARGER_FIELDS])
		elif child.get("node_type") == "physics_block" and child.get("body") != null:
			stateful.append([int(child.network_object_id), object, RIGID_FIELDS, child.body])

# Shift every laser so it behaves as if the race clock read `world_time`.
func shift_lasers(game, world_time: float) -> void:
	if game == null or game.wp_game_data == null or not game.is_server():
		return
	_refresh(game)
	if lasers.empty():
		return
	var tick_rate = float(game.tick_rate) if "tick_rate" in game else 1.0 / 60.0
	var shift = int(round((world_time - float(game.wp_game_data.play_time)) / max(tick_rate, 0.0001)))
	shift_ticks = shift
	shift_level = level_id
	var charge = int(game.wp_game_data.laser_charge_ticks) if "laser_charge_ticks" in game.wp_game_data else 0
	for laser in lasers:
		if not is_instance_valid(laser):
			continue
		var pause = int(laser.pause_duration_ticks)
		if pause <= 0:
			continue
		var period = max(int(laser.lasing_duration_ticks), charge) + pause
		if period <= 0:
			continue
		if not laser.has_meta("tas_original_timing_offset"):
			laser.set_meta("tas_original_timing_offset", int(laser.timing_offset))
		var offset = posmod(int(laser.get_meta("tas_original_timing_offset")) + shift, period)
		if int(laser.timing_offset) != offset:
			laser.timing_offset = offset

# The race clock as the lasers currently see it.
func world_time(game) -> float:
	if game == null or game.wp_game_data == null:
		return 0.0
	var tick_rate = float(game.tick_rate) if "tick_rate" in game else 1.0 / 60.0
	var loaded = game.level.loaded_level if game.level != null else null
	var shifted = loaded != null and loaded.get_instance_id() == shift_level
	return float(game.wp_game_data.play_time) + (shift_ticks * tick_rate if shifted else 0.0)

func capture(game, include_rigid := true) -> Dictionary:
	var result = {}
	if game == null or not game.is_server():
		return result
	_refresh(game)
	for entry in stateful:
		if not is_instance_valid(entry[1]):
			continue
		if entry.size() > 3 and not include_rigid:
			continue
		var values = []
		if entry.size() > 3 and is_instance_valid(entry[3]):
			# Body state is already current at a native tick boundary; network
			# properties can still contain the preceding render-batch sample.
			var body = entry[3]
			values = [body.global_position, body.global_rotation, body.linear_velocity, body.angular_velocity, body.enabled]
		else:
			for field in entry[2]:
				values.append(entry[1].get(field))
		result[entry[0]] = values
	return result

func restore(game, states, include_rigid := true, reset_visuals := false) -> void:
	if game == null or not game.is_server() or typeof(states) != TYPE_DICTIONARY or states.empty():
		return
	_refresh(game)
	for entry in stateful:
		if entry.size() > 3 and not include_rigid:
			continue
		if not states.has(entry[0]) or not is_instance_valid(entry[1]):
			continue
		var values = states[entry[0]]
		if typeof(values) != TYPE_ARRAY:
			continue
		var changed = false
		for index in min(values.size(), entry[2].size()):
			if entry[1].get(entry[2][index]) != values[index]:
				changed = true
				entry[1].set(entry[2][index], values[index])
		if reset_visuals and block_nodes.has(entry[0]):
			var node = block_nodes[entry[0]]
			var renderer = _block_renderer(node) if is_instance_valid(node) else null
			if is_instance_valid(renderer) and (changed or (values.size()>0 and not bool(values[0]) and renderer.modulate.a < 0.9)):
				# Native fade tweens cannot seek backwards. Rebuild only this
				# visual on the scene thread; keep its native object/body intact.
				call_deferred("_reset_block_visual",game,node,level_id)
		if entry.size() > 3 and is_instance_valid(entry[3]) and values.size() >= 4:
			var body = entry[3]
			body.global_position = values[0]
			body.global_rotation = values[1]
			body.linear_velocity = values[2]
			body.angular_velocity = values[3]
			if values.size() > 4:
				body.enabled = bool(values[4])

func _block_renderer(node):
	var renderer = node.get_renderer()
	# Local native server nodes can contain the visual child without filling
	# LevelNode's optional renderer pointer.
	return renderer if is_instance_valid(renderer) else node.get_node_or_null("DisappearingBlockRenderer")

func _reset_block_visual(game, node, expected_level: int) -> void:
	if not is_instance_valid(game) or not game.is_server() or not is_instance_valid(node) or not node.is_inside_tree() or game.level == null or game.level.loaded_level == null or game.level.loaded_level.get_instance_id() != expected_level:
		return
	var object = game.get_object_for_object_id(node.network_object_id)
	if object == null:
		return
	# Align to the CURRENT native state, including ticks since the request.
	# This callback never writes counters or rewinds a newer restore.
	var old = _block_renderer(node)
	if not is_instance_valid(old) or old.get_parent() != node:
		return
	var packed = load("res://project_specific/level_editor/nodes/disappearing_block/Renderer.tscn")
	if not packed is PackedScene:
		return
	var fresh = packed.instance()
	var native_pointer = node.get_renderer() == old
	fresh.name = old.name
	fresh.visible = old.visible
	node.remove_child(old)
	# The native renderer destructor clears the parent's renderer pointer.
	# Finish it before assigning the replacement (already on the idle thread).
	old.free()
	node.add_child(fresh)
	if native_pointer:
		node.set_renderer(fresh)
	if node.body != null and not node.body.enabled and object.is_disappearing:
		fresh.modulate = fresh.not_there_color

func has_stateful(game) -> bool:
	_refresh(game)
	return not stateful.empty()
