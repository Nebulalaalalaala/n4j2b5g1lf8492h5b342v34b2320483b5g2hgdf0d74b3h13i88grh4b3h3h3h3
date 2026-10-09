extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Local work only: no packet rewriting, simulation changes or graphics reduction.
var tool
var toggle
var meter
var notice
var samples = []
var elapsed = 0.0
var previous_usec = 0
var network_meter
var history = []
var online_history = []
var session_number = 0
var game_id = 0
var frame_count = 0
var worst_frame_ms = 0.0
var level = 1
var level_picker
var level_description
var renderer_states = {}
const LEVELS = ["Small", "Medium", "Large", "Very large"]
const ANIMATION_RATES = [0.0, 1.0/60.0, 1.0/45.0, 1.0/30.0]
signal settings_changed

func build(owner):
	pause_mode = Node.PAUSE_MODE_PROCESS
	tool = owner
	level = int(clamp(int(SavedSettings.get_value("ping_optimizer_level",1)),1,4))
	get_tree().connect("node_added",self,"_track_renderer")
	_scan_renderers(get_tree().root)
	add_constant_override("separation",8)
	add_child(tool._make_label("PERFORMANCE OPTIMIZER",tool._make_font(24),Color.white))
	toggle = CheckButton.new()
	toggle.text = "Enable optimizer"
	toggle.pressed = tool._ping_optimizer_enabled
	toggle.add_font_override("font",tool._make_font(19))
	toggle.hint_tooltip = "Skip unused tool lookups and editor-only callbacks; poll status and cosmetic settings less often. Graphics, controls and physics stay unchanged."
	toggle.connect("toggled",self,"set_enabled")
	add_child(toggle)
	level_picker = OptionButton.new()
	level_picker.add_font_override("font",tool._make_font(20))
	for title in LEVELS:
		level_picker.add_item(title)
	level_picker.selected = level-1
	level_picker.connect("item_selected",self,"_level_selected")
	add_child(level_picker)
	level_description = tool._make_label("",tool._make_font(18),Color(0.72,0.8,0.95))
	level_description.autowrap = true
	add_child(level_description)
	_update_description()
	meter = tool._make_label("Measuring frame times…",tool._make_font(18),Color.white)
	add_child(meter)
	network_meter = tool._make_label("Game RTT: waiting for an online match",tool._make_font(18),Color.white)
	network_meter.autowrap = true
	add_child(network_meter)
	# Reports and council controls are for Developer installs (Logs & diagnostics installed).
	if ModPaths.has("DiagnosticsHandler.gd"):
		var report = tool._make_button("SAVE LAG REPORT",Color(0.21,0.54,0.85),260)
		report.hint_tooltip = "Saves recent diagnostics and the last 120 valid online RTT samples, retained after leaving a match. Local only; no credentials or extra ping packets."
		report.connect("pressed",self,"save_report")
		add_child(report)
		var stop = tool._make_button("STOP COUNCIL RECORDING",Color(0.21,0.54,0.85),300)
		stop.hint_tooltip = "Stops your scout and recorder sessions through the normal stop flow. They are not restarted automatically. Frees recording CPU and bandwidth."
		stop.connect("pressed",self,"stop_recording")
		add_child(stop)
	notice = tool._make_label("Original graphics • No physics changes\nInternet/server ping is not controlled by this tool.",tool._make_font(17),Color(0.72,0.8,0.95))
	notice.autowrap = true
	add_child(notice)
	connect("visibility_changed",self,"reset_samples")

func set_enabled(value):
	tool._ping_optimizer_enabled = value
	if toggle != null:
		toggle.set_block_signals(true)
		toggle.pressed = value
		toggle.set_block_signals(false)
	SavedSettings.set_value("ping_optimizer_enabled",value)
	_update_renderers()
	emit_signal("settings_changed")
	reset_samples()

func _level_selected(index):
	level = int(clamp(index+1,1,4))
	if level_picker != null:
		level_picker.selected = level-1
	SavedSettings.set_value("ping_optimizer_level",level)
	_update_description()
	_update_renderers()
	emit_signal("settings_changed")

func _update_description():
	if level_description == null:
		return
	level_description.text = [
		"Small · Reduce unused mod work. Original animation quality.",
		"Medium · Small + other players’ skeleton animations at up to 60 updates/sec.",
		"Large · Small + other players’ skeleton animations at up to 45 updates/sec.",
		"Very large · Small + other players’ skeleton animations at up to 30 updates/sec. Animation may look less fluid."
	][level-1] + "\nYour player, movement interpolation, physics, map visuals and network traffic stay unchanged."

func _scan_renderers(node):
	_track_renderer(node)
	for child in node.get_children():
		_scan_renderers(child)

func _track_renderer(node):
	if node is UpGuys_PlayerRenderer:
		# Native _ready selects its own update mode. Capture only afterwards.
		call_deferred("_register_renderer",weakref(node))

func _register_renderer(reference):
	var renderer = reference.get_ref()
	if not is_instance_valid(renderer) or not renderer.is_inside_tree():
		return
	var id = renderer.get_instance_id()
	if renderer_states.has(id) or not is_instance_valid(renderer.spine):
		return
	renderer_states[id] = {"ref":reference,"enabled":renderer.enable_spine_manual_update,"rate":renderer.manual_spine_update_rate,"timer":renderer.manual_spine_update_timer,"mode":renderer.spine.update_mode,"applied":false}

func _restore_renderer(renderer,state):
	if not state.applied:
		return
	renderer.enable_spine_manual_update = state.enabled
	renderer.manual_spine_update_rate = state.rate
	renderer.manual_spine_update_timer = state.timer
	if is_instance_valid(renderer.spine):
		renderer.spine.update_mode = state.mode
	state.applied = false

func _update_renderers():
	# Bounded registry, once per second; no per-frame scene searches.
	var current_game = tool._find_game() if tool._ping_optimizer_enabled and level > 1 else null
	for id in renderer_states.keys():
		var state = renderer_states[id]
		var renderer = state.ref.get_ref()
		if not is_instance_valid(renderer) or not renderer.is_inside_tree():
			renderer_states.erase(id)
			continue
		var game = renderer.get_network_game()
		# Never throttle local, replay/editor or local-simulation renderers.
		var eligible = tool._ping_optimizer_enabled and level > 1 and is_instance_valid(game) and game == current_game and not game.is_server() and not game.is_local_player(renderer.get_object_id())
		if not eligible or not is_instance_valid(renderer.spine):
			_restore_renderer(renderer,state)
			continue
		var rate = ANIMATION_RATES[level-1]
		if state.enabled:
			rate = max(rate,state.rate)
		if not state.applied or renderer.manual_spine_update_rate != rate:
			renderer.manual_spine_update_rate = rate
			renderer.manual_spine_update_timer = rate * float(int(id)%32)/32.0
			renderer.spine.update_mode = SpineConstant.UpdateMode_Manual
			renderer.enable_spine_manual_update = true
			state.applied = true

func _exit_tree():
	for state in renderer_states.values():
		var renderer = state.ref.get_ref()
		if is_instance_valid(renderer):
			_restore_renderer(renderer,state)

func reset_samples():
	samples.clear()
	elapsed = 0.0
	previous_usec = 0
	frame_count = 0
	worst_frame_ms = 0.0

func sample_network(fps,frame_peak):
	var game = tool._find_game()
	var current_id = game.get_instance_id() if is_instance_valid(game) else 0
	if current_id != game_id:
		session_number += 1
		game_id = current_id
	var rtt = null
	var backlog = null
	if is_instance_valid(game) and not game.is_server() and game.has_method("get_client_round_trip_time"):
		var seconds = float(game.get_client_round_trip_time())
		if seconds > 0 and not is_nan(seconds) and not is_inf(seconds):
			rtt = seconds*1000.0
		if game.has_method("get_client_available_packet_count"):
			backlog = game.get_client_available_packet_count()
	var recorder = "off"
	if is_instance_valid(tool._replay_hub) and is_instance_valid(tool._replay_hub._council_recorder):
		recorder = str(tool._replay_hub._council_recorder.state)
	var entry = {"utc_seconds":OS.get_unix_time(),"rtt_ms":rtt,"available_packets":backlog,"fps":fps,"worst_frame_ms":frame_peak,"focused":OS.is_window_focused(),"recorder":recorder,"optimizer":tool._ping_optimizer_enabled}
	entry["session"] = session_number
	entry["optimizer_level"] = level if tool._ping_optimizer_enabled else 0
	history.append(entry)
	if history.size()>120:
		history.pop_front()
	if rtt != null:
		online_history.append(entry)
		if online_history.size()>120:
			online_history.pop_front()
	if not is_visible_in_tree():
		return
	if rtt == null:
		network_meter.text = "Game RTT unavailable • %d online samples retained" % online_history.size()
	else:
		var maximum = rtt
		for sample in history:
			if sample.rtt_ms != null and sample.session == session_number:
				maximum = max(maximum,sample.rtt_ms)
		network_meter.text = "Game RTT: %.0f ms   •   Recent peak: %.0f ms\nNative RTT, not an ICMP test. Recorder: %s" % [rtt,maximum,recorder]

func save_report():
	var directory = "user://goobplayability"
	if Directory.new().make_dir_recursive(directory)!=OK:
		notice.text = "Could not create report folder."
		return
	var path = directory.plus_file("ping-diagnostics.json")
	var file = File.new()
	if file.open(path+".tmp",File.WRITE)!=OK:
		notice.text = "Could not save report."
		return
	file.store_string(JSON.print({"format":2,"note":"Local samples only; native game RTT may include application processing. Available packets is not packet loss. Samples are not a bandwidth measurement. online_samples retains historical valid RTT; inspect timestamps and session numbers.","samples":history,"online_samples":online_history}))
	file.close()
	if Directory.new().rename(path+".tmp",path)!=OK:
		notice.text = "Report replacement failed; previous report preserved."
		return
	notice.text = "Saved locally: goobplayability/ping-diagnostics.json\nNo report was uploaded."
	if online_history.empty():
		notice.text += "\nNo online RTT captured yet—play an online match, then save again."
	notice.hint_tooltip = ProjectSettings.globalize_path(path)

func stop_recording():
	var hub = tool._replay_hub
	if is_instance_valid(hub) and is_instance_valid(hub._council_recorder):
		hub._council_recorder.set_enabled(false)
		notice.text = "Recorder stop requested. Pending saves may still finish.\nGraphics unchanged. Internet/server ping cannot be guaranteed."
	else:
		notice.text = "No Council recorder is loaded.\nGraphics unchanged. Internet/server ping cannot be guaranteed."

func _process(_delta):
	if meter == null:
		previous_usec = 0
		return
	var now = OS.get_ticks_usec()
	if previous_usec > 0:
		var frame_ms = float(now-previous_usec)/1000.0
		frame_count += 1
		worst_frame_ms = max(worst_frame_ms,frame_ms)
		if is_visible_in_tree():
			samples.append(frame_ms)
		elapsed += frame_ms/1000.0
	previous_usec = now
	if elapsed < 1.0:
		return
	_update_renderers()
	sample_network(float(frame_count)/elapsed,worst_frame_ms)
	if not samples.empty() and is_visible_in_tree():
		var sorted = samples.duplicate()
		sorted.sort()
		var p95 = sorted[int(floor((sorted.size()-1)*0.95))]
		meter.text = "%d FPS   •   %.1f ms average   •   %.1f ms p95\n240 FPS needs frames around 4.2 ms." % [int(frame_count/elapsed),elapsed*1000.0/max(1,frame_count),p95]
	samples.clear()
	elapsed = 0.0
	frame_count = 0
	worst_frame_ms = 0.0
