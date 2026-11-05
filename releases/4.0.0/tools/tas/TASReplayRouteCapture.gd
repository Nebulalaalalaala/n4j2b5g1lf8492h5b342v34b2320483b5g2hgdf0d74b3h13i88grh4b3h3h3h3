extends Node

# A private native replay client. The real scene is paused while this client
# owns a temporary native clock; speed and pause are restored on every exit.
signal completed(samples, error)
signal progress(value)
var view
var game
var samples = []
var rate = 60.0
var duration = 0.0
var last_tick = -1
var last_clock = -1.0
var began = 0
var last_advance = 0
var warm = 3
var closed = false
var game_started = false
var owns_clock = false
var saved_scale = 1.0
var saved_pause = false
var in_native_tick = false
var finish_pending = false
var pending_error = ""
var frame_samples = {}

func start(level: Dictionary, bytes: PoolByteArray, metadata: Dictionary) -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	saved_scale = Engine.time_scale
	saved_pause = get_tree().paused
	get_tree().paused = true
	Engine.time_scale = 1.0
	owns_clock = true
	view = Viewport.new()
	view.name = "SectionReplayWorld"
	view.size = Vector2(32,32)
	view.disable_3d = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = Viewport.UPDATE_DISABLED
	view.audio_listener_enable_2d = false
	view.gui_disable_input = true
	add_child(view)
	game = load("res://nodes/ReplayGhostGame.tscn").instance()
	game.set_script(load(get_script().resource_path.get_base_dir().plus_file("TASReplayCaptureGame.gd")))
	game.set_meta("goobplayability_review_only",true)
	game.get_node("WPGameData").is_replay = true
	game.get_node("WPGameData").is_replay_ghost = true
	view.add_child(game)
	game.connect("route_capture_tick",self,"_native_tick")
	game.game_metadata = {"level_data":{"0":to_json(level)}}
	for id in metadata.get("player_metadata",{}):
		game.set_metadata_for_player(int(id),metadata.player_metadata[id])
	game.play_replay(bytes)
	game.start_game()
	game_started = true
	game.set_process(false)
	game.set_physics_process(false)
	rate = 1.0/max(0.0001,float(game.get_tick_rate()))
	duration = float(metadata.get("time",0))
	began = OS.get_ticks_msec()
	last_advance = began
	set_process(true)

func _process(_delta: float) -> void:
	if closed: return
	if warm>0:
		warm -= 1
		return
	var deadline = OS.get_ticks_usec()+3000
	var calls = 0
	while calls<48 and OS.get_ticks_usec()<deadline and not closed:
		game.notification(Node.NOTIFICATION_PROCESS)
		if not finish_pending: _read_sample()
		calls += 1
		if finish_pending:
			finish_pending = false
			finish(pending_error)
			break
		if game.is_game_over():
			finish("")
	if closed: return
	if OS.get_ticks_msec()-began>120000:
		finish("Replay analysis timed out. Try another run.")
	elif OS.get_ticks_msec()-last_advance>2500:
		finish("" if samples.size()>2 and last_clock>=duration-0.1 else "The native replay stopped before its recorded finish. No boxes were applied.")
	emit_signal("progress",clamp(last_clock/max(0.001,duration),0,1))

func _native_tick() -> void:
	if closed or finish_pending: return
	in_native_tick = true
	_read_sample()
	in_native_tick = false

func _read_sample() -> void:
	var tick = int(game.get_tick_number())
	# get_tick_number() may stay constant inside a native render batch.
	# The race clock advances per physics tick; deduplicate by that below.
	if tick!=last_tick: last_advance = OS.get_ticks_msec()
	last_tick = tick
	var clock = float(game.wp_game_data.play_time)
	last_clock = clock
	if game.get_player_count()!=1:
		if game.get_player_count()>1: finish("This replay has multiple players; select a single-player time trial.")
		return
	var player = game.get_player_at_index(0)
	# Skip native countdown and the lobby/finish teleport. Keep positions from
	# the selected run, not body guesses from a local replacement simulation.
	if clock<0: return
	if not player.alive:
		finish("The replay dies before its recorded finish. Choose another run; no boxes were applied.")
		return
	if not player.body_enabled: return
	if player.rank>0 or game.is_game_over():
		finish("")
		return
	if clock+0.0001 < (float(samples.back().time) if not samples.empty() else 0.0) and not game.is_resimulating():
		finish("This replay resets its clock mid-run. Choose a clean run; your boxes are unchanged.")
		return
	var frame = int(round(clock*rate))
	if frame_samples.has(frame) and not game.is_resimulating(): return
	var at = player.position
	if is_nan(at.x) or is_nan(at.y) or is_inf(at.x) or is_inf(at.y):
		finish("The replay contains an invalid player position.")
		return
	var sample = {"frame":frame,"time":clock,"position":at,"grounded":player.ground_normal!=Vector2.ZERO,"dashing":player.dash_timer>0,"checkpoint":player.last_checkpoint}
	# Keep the existing box-generation flag unchanged. These additional fields
	# describe the native dash for display; facing_dir is not dash direction.
	sample["dash_timer"] = int(player.dash_timer)
	sample["dash_dir"] = bool(player.dash_dir)
	sample["dash_active"] = player.dash_timer>0 and player.dash_timer<=game.wp_game_data.player_dash_ticks-game.wp_game_data.player_dash_charge_ticks
	frame_samples[frame] = sample
	if samples.empty() or frame>int(samples.back().frame): samples.append(sample)
	# Native playback can keep simulating the last input after a truncated
	# recording. Metadata bounds this import to the actual selected run.
	if clock>=duration-0.5/rate:
		finish("")
		return
	if samples.size()>120000: finish("This replay is too long to analyze safely.")

func finish(error: String) -> void:
	if closed: return
	if in_native_tick:
		# Stopping a NetworkGame from inside its native tick is unsafe.
		# Finish only after notification() has returned to the caller.
		finish_pending = true
		pending_error = error
		return
	closed = true
	set_process(false)
	if game_started and is_instance_valid(game) and game.is_game_started(): game.stop_game()
	_restore_clock()
	var frames = frame_samples.keys()
	frames.sort()
	samples = []
	for frame in frames: samples.append(frame_samples[frame])
	if error.empty() and samples.size()<2: error = "No playable route was found in this replay. Your boxes are unchanged."
	emit_signal("completed",samples,error)

func cancel() -> void:
	closed = true
	set_process(false)
	if game_started and is_instance_valid(game) and game.is_game_started(): game.stop_game()
	_restore_clock()

func _restore_clock() -> void:
	if not owns_clock: return
	owns_clock = false
	Engine.time_scale = saved_scale
	if is_inside_tree(): get_tree().paused = saved_pause

func _exit_tree() -> void:
	cancel()
