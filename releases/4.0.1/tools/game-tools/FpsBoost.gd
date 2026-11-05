extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")

# FPS Boost: skips work nobody can see. Other players and level particles
# that are far off screen stop updating and drawing until they come back.
# Your own Goober, physics, inputs and network traffic are never touched.

const CHECK_EVERY = 0.12
const OPTIONS = [
	["players", "Pause off-screen players", "Other players more than half a screen away stop animating and drawing until they come back into view."],
	["particles", "Pause off-screen particles", "Level particle effects more than a screen away stop simulating and drawing until they come back into view."],
	["vsync", "Turn off VSync", "Frames are shown as soon as they are ready instead of waiting for the monitor. Lowest input delay; may tear."],
	["report", "Frame reports in the game log", "Every 15 seconds, write frame times and node counts to godot.log. Useful when tracking down lag."],
]
const OVERRIDE_MARK = "; Goobplayability FPS Boost (delete this file to undo)"

var tool
var enabled = false
var options = {}
var meter
var paused_players = {}     # instance id -> [weakref, had_internal_process]
var paused_particles = {}   # instance id -> [weakref, was_visible, had_internal_process]
var particles = []          # weakrefs to level particle nodes
var vsync_before = null
var _timer = 0.0
var _report_timer = 5
var _reports = 0
var _collect_timer = 0.0
var _players_game = 0
var _frames = 0
var _elapsed = 0.0
var _worst = 0.0
var _spikes = 0
signal settings_changed

func build(owner):
	pause_mode = Node.PAUSE_MODE_PROCESS
	tool = owner
	enabled = bool(SavedSettings.get_value("fps_boost_enabled", false))
	for entry in OPTIONS:
		options[entry[0]] = bool(SavedSettings.get_value("fps_boost_" + entry[0], entry[0] in ["players", "particles", "engine"]))
	add_constant_override("separation", 8)
	add_child(tool._make_label("FPS BOOST", tool._make_font(24), Color.white))
	var toggle = CheckButton.new()
	toggle.name = "Enabled"
	toggle.text = "Enable FPS Boost"
	toggle.pressed = enabled
	toggle.add_font_override("font", tool._make_font(19))
	toggle.connect("toggled", self, "set_enabled")
	add_child(toggle)
	for entry in OPTIONS:
		var box = CheckBox.new()
		box.text = entry[1]
		box.hint_tooltip = entry[2]
		box.pressed = options[entry[0]]
		box.add_font_override("font", tool._make_font(18))
		box.connect("toggled", self, "_option_toggled", [entry[0]])
		add_child(box)
		var note = tool._make_label(entry[2], tool._make_font(15), Color(0.72, 0.8, 0.95))
		note.autowrap = true
		add_child(note)
	meter = tool._make_label("Measuring…", tool._make_font(18), Color.white)
	add_child(meter)
	var notice = tool._make_label("Your Goober, physics, controls and network traffic stay unchanged.\nServer ping depends on your connection; higher FPS lowers input delay.", tool._make_font(16), Color(0.72, 0.8, 0.95))
	notice.autowrap = true
	add_child(notice)
	get_tree().connect("node_added", self, "_node_added")
	_scan(get_tree().root)
	_apply_vsync()
	_write_override()

func set_enabled(value):
	enabled = bool(value)
	SavedSettings.set_value("fps_boost_enabled", enabled)
	var toggle = get_node_or_null("Enabled")
	if toggle != null and toggle.pressed != enabled:
		toggle.set_block_signals(true)
		toggle.pressed = enabled
		toggle.set_block_signals(false)
	if not enabled:
		_restore_all()
	_apply_vsync()
	_write_override()
	emit_signal("settings_changed")

func _option_toggled(value, key):
	options[key] = bool(value)
	SavedSettings.set_value("fps_boost_" + key, options[key])
	if not options.players:
		_restore_players()
	if not options.particles:
		_restore_particles()
	_apply_vsync()
	_write_override()
	emit_signal("settings_changed")

# Startup settings live in override.cfg next to the game's executable; Godot
# reads it before the game starts. Only a file this tool wrote is changed.
func _override_path() -> String:
	return OS.get_executable_path().get_base_dir().plus_file("override.cfg")

func _write_override():
	var path = _override_path()
	var file = File.new()
	if file.file_exists(path):
		if file.open(path, File.READ) != OK:
			return
		var ours = file.get_line() == OVERRIDE_MARK
		file.close()
		if not ours:
			return
	# Startup engine settings are no longer written (threaded rendering
	# stopped the game starting; the frame limit misbehaved after the other
	# tweaks); an override.cfg this tool wrote earlier is removed or emptied.
	var lines = []
	if lines.empty():
		if file.file_exists(path) and Directory.new().remove(path) != OK and file.open(path, File.WRITE) == OK:
			file.store_line(OVERRIDE_MARK)
			file.close()
		return
	if file.open(path, File.WRITE) != OK:
		return
	file.store_line(OVERRIDE_MARK)
	file.store_line("[rendering]")
	for line in lines:
		file.store_line(line)
	file.close()

func _apply_vsync():
	var want_off = enabled and options.get("vsync", false)
	if want_off:
		if vsync_before == null:
			vsync_before = OS.vsync_enabled
		OS.vsync_enabled = false
	elif vsync_before != null:
		OS.vsync_enabled = vsync_before
		vsync_before = null

# ---------------------------------------------------------------- tracking

func _scan(node):
	_node_added(node)
	for child in node.get_children():
		_scan(child)

func _node_added(node):
	if node is CPUParticles2D or node is Particles2D:
		particles.append(weakref(node))

func _process(delta):
	_frames += 1
	_elapsed += delta
	_worst = max(_worst, delta)
	if delta > 0.05:
		_spikes += 1
	if _elapsed >= 1.0:
		_report_timer -= 1
		if _report_timer <= 0:
			_report_timer = 15
			if options.get("report", false):
				_report(int(_frames / _elapsed))
		if meter != null and is_visible_in_tree():
			meter.text = "%d FPS   •   %.2f ms per frame   •   %d players / %d particle effects paused" % [int(_frames / _elapsed), _elapsed * 1000.0 / max(1, _frames), paused_players.size(), paused_particles.size()]
		_frames = 0
		_elapsed = 0.0
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_EVERY
	var game = tool._find_game() if tool.has_method("_find_game") else null
	if options.players:
		_update_players(game)
	if options.particles:
		_update_particles(game)

# Frame-time report in the game log every 15 s (numbers only, no account
# data), so slowdowns can be traced to scripts, physics, drawing or nodes.
func _report(fps: int) -> void:
	_reports += 1
	var scene = get_tree().current_scene
	print("[FpsBoost] %d FPS | worst frame %.1f ms | %d frames over 50 ms | scene %s | target %d | vsync %s | scripts %.2f ms | physics %.2f ms | draw calls %d | nodes %d | orphans %d" % [
		fps, _worst * 1000.0, _spikes, scene.name if scene != null else "-", Engine.target_fps, str(OS.vsync_enabled),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_2D_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	_worst = 0.0
	_spikes = 0
	# Every minute: which parts of the scene hold the most nodes.
	if _reports % 4 != 1:
		return
	var sizes = []
	for top in get_tree().root.get_children():
		for child in ([top] if top.get_child_count() == 0 else top.get_children()):
			sizes.append([_count_nodes(child), _describe(top) + "/" + _describe(child)])
	sizes.sort_custom(self, "_bigger")
	var parts = []
	for entry in sizes.slice(0, min(7, sizes.size() - 1)):
		parts.append("%s %d" % [entry[1], entry[0]])
	print("[FpsBoost] biggest: " + PoolStringArray(parts).join(", "))

# Unnamed nodes show as @@123; the script file or class says what they are.
func _describe(node) -> String:
	var text = str(node.name)
	if not text.begins_with("@@"):
		return text
	var script = node.get_script()
	if script != null and not script.resource_path.empty():
		return script.resource_path.get_file().get_basename()
	return node.get_class()

func _count_nodes(node) -> int:
	var total = 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total

func _bigger(a, b) -> bool:
	return a[0] > b[0]

func _screen_rect(node, margin: float) -> Rect2:
	var view = node.get_viewport_rect()
	return view.grow(view.size.x * margin)

func _on_screen(node, margin: float) -> bool:
	return _screen_rect(node, margin).has_point(node.get_global_transform_with_canvas().origin)

func _update_players(game):
	if not is_instance_valid(game) or not game.has_method("is_local_player") or game.is_server():
		_restore_players()
		return # Solo levels keep every player visible, so there is nothing to collect.
	# Renderers are collected when the game changes and every 2 s (joins).
	_collect_timer -= CHECK_EVERY
	if _collect_timer <= 0.0 or _players_game != game.get_instance_id():
		_collect_timer = 2.0
		_players_game = game.get_instance_id()
		_collect_renderers(game)
	for renderer in get_tree().get_nodes_in_group("goob_fps_players"):
		var spine = renderer.get("spine")
		if not is_instance_valid(spine):
			continue
		var id = spine.get_instance_id()
		var local = game.is_local_player(renderer.get_object_id()) if renderer.has_method("get_object_id") else true
		var show = local or game.is_server() or _on_screen(spine, 0.5)
		if show and paused_players.has(id):
			_resume_player(id)
		elif not show and not paused_players.has(id) and spine.visible:
			paused_players[id] = [weakref(spine), spine.is_processing_internal()]
			spine.set_process_internal(false)
			spine.visible = false

func _collect_renderers(game):
	# Ask the client renderer for each player instead of walking the whole
	# level tree (thousands of nodes) every 2 s.
	var client = game.get("client_renderer")
	if client != null and client.has_method("get_renderer_for_object_id"):
		for index in game.get_player_count():
			var player = game.get_player_at_index(index)
			var renderer = client.get_renderer_for_object_id(player.object_id) if player != null else null
			if renderer != null:
				renderer.add_to_group("goob_fps_players")
		return
	var stack = [game]
	while not stack.empty():
		var node = stack.pop_back()
		if node is UpGuys_PlayerRenderer:
			node.add_to_group("goob_fps_players")
			continue
		for child in node.get_children():
			stack.append(child)

func _resume_player(id):
	var entry = paused_players[id]
	paused_players.erase(id)
	var spine = entry[0].get_ref()
	if is_instance_valid(spine):
		spine.visible = true
		spine.set_process_internal(entry[1])

func _restore_players():
	for id in paused_players.keys():
		_resume_player(id)

func _update_particles(game):
	if not is_instance_valid(game):
		_restore_particles()
		return
	var alive = []
	for reference in particles:
		var node = reference.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		alive.append(reference)
		# Only the race level's own particles; menus and mod UI stay as they are.
		if not game.is_a_parent_of(node):
			continue
		var id = node.get_instance_id()
		var show = _on_screen(node, 1.0)
		if show and paused_particles.has(id):
			_resume_particles(id)
		elif not show and not paused_particles.has(id) and node.visible:
			paused_particles[id] = [reference, node.visible, node.is_processing_internal()]
			node.set_process_internal(false)
			node.visible = false
	particles = alive

func _resume_particles(id):
	var entry = paused_particles[id]
	paused_particles.erase(id)
	var node = entry[0].get_ref()
	if is_instance_valid(node):
		node.visible = entry[1]
		node.set_process_internal(entry[2])

func _restore_particles():
	for id in paused_particles.keys():
		_resume_particles(id)

func _restore_all():
	_restore_players()
	_restore_particles()

func _exit_tree():
	_restore_all()
	if vsync_before != null:
		OS.vsync_enabled = vsync_before
