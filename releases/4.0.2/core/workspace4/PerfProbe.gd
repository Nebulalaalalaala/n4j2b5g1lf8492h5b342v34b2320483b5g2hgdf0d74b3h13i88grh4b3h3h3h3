extends Node

# "Find what's slowing the game": switches each Goobplayability part off for a
# moment and measures how much faster frames get. Everything is put back as it
# was. Results go to godot.log ([PerfProbe] lines) and
# user://goobplayability/perf_report.json.

signal finished(lines)

const Unloader = preload("user://mod/core/workspace4/Unloader.gd")
const REPORT = "user://goobplayability/perf_report.json"
const SETTLE_FRAMES = 10
const MEASURE_USEC = 450000

var tas_tool
var groups = []          # [{name, nodes:[node...], watchers:bool}]
var index = -2           # -2 = baseline before, -1 = all off, 0.. = groups, size = baseline after
var phase = "settle"
var settle = 0
var started = 0
var last = 0
var results = []
var steps = []
var step_index = 0
var samples = []
var pending_base = 0.0
var bases = []
var saved = []
var saved_watchers = []
var label: Label
var layer: CanvasLayer

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	process_priority = -100000
	layer = CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	label = Label.new()
	label.rect_position = Vector2(24, 24)
	label.add_color_override("font_color", Color(1, 1, 1))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	layer.add_child(label)
	_collect()
	last = OS.get_ticks_usec()

func _collect() -> void:
	var by_script = {}
	var order = []
	for root in Unloader.mod_roots(get_tree()):
		var stack = [[root, ""]]
		while not stack.empty():
			var entry = stack.pop_back()
			var node = entry[0]
			if node == self or not is_instance_valid(node):
				continue
			var key = entry[1]
			if Unloader.is_mod_object(node):
				key = str(node.get_script().resource_path).trim_prefix("user://mod/")
			if not by_script.has(key):
				by_script[key] = []
				order.append(key)
			by_script[key].append(node)
			for child in node.get_children():
				stack.append([child, key])
	for key in order:
		var busy = false
		for node in by_script[key]:
			if node.is_processing() or node.is_physics_processing() or (node is CanvasItem and node.visible) or (node is CanvasLayer and node.visible):
				busy = true
				break
		if busy:
			groups.append({"name": key, "nodes": by_script[key], "watchers": false})
	groups.append({"name": "scene watchers (node_added)", "nodes": [], "watchers": true})

func _process(_delta):
	var now = OS.get_ticks_usec()
	var frame = now - last
	last = now
	if steps.empty():
		_build_steps()
		_begin_step()
		return
	if phase == "settle":
		settle += 1
		if settle >= SETTLE_FRAMES:
			phase = "measure"
			started = now
			samples = []
		return
	samples.append(frame)
	if now - started < MEASURE_USEC:
		return
	samples.sort()
	var median = float(samples[samples.size() / 2])
	var step = steps[step_index]
	if step[0] == "base":
		pending_base = median
	else:
		results.append({"name": "In-game Goobplayability work" if step[1] == -1 else groups[step[1]].name, "base": pending_base, "usec": median})
		bases.append(pending_base)
	_restore()
	step_index += 1
	if step_index >= steps.size():
		_finish()
		return
	_begin_step()

# A plain baseline before every test, so slow drift (heat, background apps)
# doesn't pile up into the result.
func _build_steps() -> void:
	steps = [["base", -2], ["test", -1]]
	for i in range(groups.size()):
		steps.append(["base", -2])
		steps.append(["test", i])

func _begin_step() -> void:
	var step = steps[step_index]
	index = step[1]
	if step[0] == "test":
		_apply()
	phase = "settle"
	settle = 0
	label.text = "Checking performance %d / %d" % [step_index / 2 + 1, steps.size() / 2]

func _targets() -> Array:
	if index == -1:
		var all = []
		for group in groups:
			all += group.nodes
		return all
	if index >= 0 and index < groups.size():
		return groups[index].nodes
	return []

func _watchers_off() -> bool:
	return index == -1 or (index >= 0 and index < groups.size() and groups[index].watchers)

func _apply() -> void:
	saved = []
	for node in _targets():
		if not is_instance_valid(node) or node == self or node == layer or node == label:
			continue
		var state = [node, node.is_processing(), node.is_physics_processing(), node.is_processing_input(), node.is_processing_unhandled_input(), null, null, null, null]
		if node is SpineSprite:
			state[6] = node.update_mode
			node.update_mode = SpineConstant.UpdateMode_Manual
		if node is CPUParticles2D or node is Particles2D:
			state[7] = node.speed_scale
			node.speed_scale = 0.0
		if node is Viewport:
			state[8] = node.render_target_update_mode
			node.render_target_update_mode = Viewport.UPDATE_DISABLED
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		node.set_process_unhandled_input(false)
		if node is CanvasItem or node is CanvasLayer:
			state[5] = node.visible
			node.visible = false
		saved.append(state)
	saved_watchers = []
	if _watchers_off():
		for connection in get_tree().get_signal_connection_list("node_added"):
			var target = connection.get("target")
			if target != null and target != self and Unloader.is_mod_object(target):
				get_tree().disconnect("node_added", target, connection.method)
				saved_watchers.append([target, connection.method, connection.get("binds", []), connection.get("flags", 0)])

func _restore() -> void:
	for state in saved:
		var node = state[0]
		if not is_instance_valid(node):
			continue
		# Visibility listeners may restore their own animation/process state.
		# Replay them first, then restore the exact captured state last.
		if state[5] != null:
			node.visible = state[5]
		node.set_process(state[1])
		node.set_physics_process(state[2])
		node.set_process_input(state[3])
		node.set_process_unhandled_input(state[4])
		if state[6] != null: node.update_mode = state[6]
		if state[7] != null: node.speed_scale = state[7]
		if state[8] != null: node.render_target_update_mode = state[8]
	saved = []
	for entry in saved_watchers:
		if is_instance_valid(entry[0]) and not get_tree().is_connected("node_added", entry[0], entry[1]):
			get_tree().connect("node_added", entry[0], entry[1], entry[2], entry[3])
	saved_watchers = []

func _finish() -> void:
	var rows = []
	for result in results:
		rows.append({"name": result.name, "saves_ms": (float(result.base) - float(result.usec)) / 1000.0})
	rows.sort_custom(self, "_by_saving")
	bases.sort()
	var baseline = float(bases[bases.size() / 2]) if not bases.empty() else 1.0
	var fps = 1000000.0 / max(1.0, baseline)
	var lines = ["Frame time %.2f ms (%d FPS). Biggest costs:" % [baseline / 1000.0, int(round(fps))]]
	print("[PerfProbe] baseline %.3f ms (%d FPS), %d parts checked" % [baseline / 1000.0, int(round(fps)), groups.size()])
	for row in rows:
		print("[PerfProbe] %7.3f ms  %s" % [row.saves_ms, row.name])
	for row in rows:
		if lines.size() >= 9:
			break
		if row.saves_ms >= 0.05:
			var shown = str(row.name)
			if shown.ends_with(".gd"):
				shown = shown.get_file().get_basename()
			lines.append("%.2f ms · %s" % [row.saves_ms, shown])
	if lines.size() == 1:
		lines.append("No clear result in this scene. Try again during a match.")
	var recorder = tas_tool.get_node_or_null("GoobClipStudio") if is_instance_valid(tas_tool) else null
	var buffer_running = is_instance_valid(recorder) and recorder.active()
	if buffer_running:
		lines.append("Replay buffer is running. External capture cost is not included in this test.")
	var file = File.new()
	Directory.new().make_dir_recursive(REPORT.get_base_dir())
	if file.open(REPORT, File.WRITE) == OK:
		file.store_string(to_json({"baseline_ms": baseline / 1000.0, "rows": rows, "time": OS.get_unix_time(), "external_capture_included":false, "replay_buffer_running":buffer_running}))
		file.close()
	emit_signal("finished", lines)
	queue_free()

func _by_saving(a, b) -> bool:
	return a.saves_ms > b.saves_ms

func _exit_tree():
	_restore()
