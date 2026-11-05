extends Node
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")

# TAS Studio: works on the live Macro Bot run.
#  - Instant seek: every recorded native frame keeps its beginning-of-tick
#    state, so any recorded frame can be restored directly, no re-simulation.
#  - Jobs: feed a list of inputs into the live recorder at high speed, then
#    stop at a frame. Used for re-play after edits, fast-forward to a marker,
#    exact path preview and the optimiser. Preview and optimiser trials run
#    with drawing switched off and are rewound afterwards.
#  - Input list rows, reference ghost, frame info and section times live in
#    TASStudioWindow.gd, which calls into this node.

const STATE_KEY = "__tas_recorded_state"
const EDITED_KEY = "__tas_input_unverified"
const DASH_DIR_KEY = "__tas_dash_direction"
const LEFT = "player_left"
const RIGHT = "player_right"
const JUMP = "player_up"
const DASH = "player_dash"
const INPUTS = [LEFT, RIGHT, JUMP, DASH]
const FAST = 6.0
const FAST_PROBE = 20.0
const APPROACH = 10
const JOB_TIMEOUT_MS = 120000
const SKIP_STATE_KEYS = ["native_tick_clock", "tas_playback_speed", "state_time", "time_remaining", "object_states"]

var tool = null
var window = null

# Timeline of the working run. The tool's own segments/checkpoints always hold
# full[0, cursor); frames after the cursor are kept here for seeking forward.
var full = []
var bounds = [0]        # frame index of each checkpoint
var snaps = []          # checkpoint snapshot per bound
var verified = 0        # full[i] for i <= verified has a trusted start state
var cursor = 0
var end_snap = {}
var end_snap_frame = -1
var markers = {}        # frame index -> true
var undo_stack = []

var job = {}
var held = {}
var render_off = false
var restore_fps = false
var path_points = PoolVector2Array()
var path_node = null
var reference = {}
var ghost_node = null
var optimiser = {}
var message = ""
var hold_render = false # bots keep drawing off between their runs
var practice = {}       # section practice loop: {section, started}
var sections = []       # {start, end, takes: [{inputs, frames, died, at}], best}
var route_node = null
var records = null      # TASStudioRecords.gd: autosave + gold splits
var bots = null         # TASStudioBots.gd: jump window, stitching, route finder
var revision = 0        # goes up on every committed change (autosave, caches)
var next_id = 1         # stable ids for sections and takes
var mark_mode = 0       # 0 off, 1 waiting for the start click, 2 for the end click
var mark_first = -1
var compare_view = null
var _compare_window_hidden = false
var pending_restore = {}
# Segmented run: boxes made from a normal playthrough (the guide), then a
# fresh run is built one segment at a time. Each segment starts from the
# real end of the kept segment before it, so nothing ever needs joining.
var segmented = false
var workflow_mode = "checkpoints"
var segment_pending_start = false
var segment_commit = -1
var segment_commit_target = -1
var segment_original = {}
var segment_next = -1
var loaded_slot = 0
var guide_points = PoolVector2Array()   # route of the guide run, for the map
var zone_editor = null
var replay_boxes = null
var pending_practice_id = 0
var pending_practice_level = ""
var pending_practice_revision = 0
var pending_practice_began = 0
var source_revision = -1
const TAKES_KEPT = 0    # keep all successful takes; pruning is always deliberate
const ZONE_SIZE = Vector2(72, 96)   # stop block at a section's end
const SECTION_TARGET = 180          # preferred section length (frames)
const SECTION_MIN = 90
const SECTION_MAX = 300
var show_jobs = false   # probes keep drawing (the screen shows them sped up)
var replay_speed = FAST
const GATE_HALF = 72.0  # half-width of a section's finish line
const GATE_CONTINUE = 8 # frames to survive after crossing it

signal changed


func setup(owner) -> void:
	tool = owner
	add_to_group("goob_f1_windows")
	_compare_window_hidden = bool(tool._overlay_hidden) or not bool(tool._tas_gui_enabled)
	workflow_mode = str(SavedSettings.get_value("tas_workflow_mode","checkpoints"))
	if not workflow_mode in ["checkpoints","sections"]: workflow_mode = "checkpoints"
	set_process(true)
	var base = get_script().resource_path.get_base_dir()
	records = load(base.plus_file("TASStudioRecords.gd")).new()
	records.setup(self)
	bots = load(base.plus_file("TASStudioBots.gd")).new()
	bots.setup(self)

func set_workflow_mode(value: String) -> bool:
	if not value in ["checkpoints","sections"]: return false
	if workflow_mode==value: return true
	if not job.empty() or is_instance_valid(zone_editor) or (is_instance_valid(replay_boxes) and (replay_boxes.pending or replay_boxes.browser_owned)) or (bots!=null and bots.busy()) or tool._practice_playback:
		message = "Finish the current attempt or stop playback before changing modes."
		emit_signal("changed")
		return false
	cancel_practice_request()
	segment_pending_start = false
	stop_practice()
	if is_instance_valid(window):
		window.close()
		window.bar.hide()
		window._show_markers(-1)
	# Mode selection never converts, clears or restarts a run. Recording must
	# be stopped before changing its authoring workflow; the prefix is retained.
	if tool._practice_active or tool._practice_start_waiting:
		tool._practice_start_waiting = false
		tool._stop_practice_mode()
	workflow_mode = value
	SavedSettings.set_value("tas_workflow_mode",value)
	message = ""
	touch()
	emit_signal("changed")
	return true


func _exit_tree() -> void:
	if is_instance_valid(zone_editor):
		zone_editor.finish(false, false)
	if window != null and is_instance_valid(window):
		for node in [window.panel, window.bar, window.info_panel]:
			if node != null and is_instance_valid(node):
				node.queue_free()
		window.queue_free()


func touch() -> void:
	revision += 1


func new_id() -> int:
	next_id += 1
	return next_id - 1


func _window():
	if window == null or not is_instance_valid(window):
		window = load(get_script().resource_path.get_base_dir().plus_file("TASStudioWindow.gd")).new()
		# Straight under the root viewport, so nothing the tool's own nodes do
		# (hiding, scaling, layers) can keep the menu from drawing.
		get_tree().root.add_child(window)
		window.setup(self)
	return window

func leaderboard_boxes():
	if not is_instance_valid(replay_boxes):
		replay_boxes = load(get_script().resource_path.get_base_dir().plus_file("TASLeaderboardSections.gd")).new()
		add_child(replay_boxes)
		replay_boxes.setup(self)
	return replay_boxes


func open_window() -> void:
	if set_workflow_mode("sections"): _window().open()


func toggle_window() -> void:
	if window != null and is_instance_valid(window) and window.panel.is_visible_in_tree():
		window.close()
	else:
		open_window()


func set_info_visible(value: bool) -> void:
	_window().set_info_visible(value)


func info_visible() -> bool:
	return window != null and is_instance_valid(window) and window.info_panel.visible


# ---------------------------------------------------------------- timeline

func _range(source: Array, first: int, last: int) -> Array:
	var result = []
	for index in range(max(first, 0), min(last, source.size())):
		result.append(source[index])
	return result


func tool_frames() -> Array:
	var frames = []
	for segment in tool._practice_segments:
		frames += segment
	frames += tool._practice_current_segment
	return frames


func _frame_ok(frame) -> bool:
	if typeof(frame) != TYPE_DICTIONARY or frame.has(EDITED_KEY):
		return false
	var state = frame.get(STATE_KEY)
	return typeof(state) == TYPE_DICTIONARY and bool(state.get("native_tick_clock", false))


# Bring the timeline in line with the tool. The suffix after the cursor is
# kept only while the tool still holds exactly the prefix this node left it.
func sync() -> void:
	if tool == null or not job.empty() or not practice.empty():
		return
	var frames = tool_frames()
	var count = frames.size()
	# An empty prefix at cursor zero cannot prove identity after Clear/Load.
	# Only seeks within the same recording may preserve their cached suffix.
	var same_source = source_revision == int(tool._practice_data_revision)
	source_revision = int(tool._practice_data_revision)
	var keep = same_source and count == cursor and count <= full.size() and (count == 0 or (frames[0] == full[0] and frames[count - 1] == full[count - 1]))
	var tool_bounds = [0]
	var total = 0
	for segment in tool._practice_segments:
		total += segment.size()
		tool_bounds.append(total)
	var tool_snaps = tool._practice_checkpoints.duplicate()
	while tool_bounds.size() > tool_snaps.size() and tool_bounds.size() > 1:
		tool_bounds.pop_back()
	if keep:
		# Same prefix; keep later checkpoints past the cursor.
		var later_bounds = []
		var later_snaps = []
		for index in bounds.size():
			if bounds[index] > count and index < snaps.size():
				later_bounds.append(bounds[index])
				later_snaps.append(snaps[index])
		bounds = tool_bounds + later_bounds
		snaps = tool_snaps + later_snaps
		return
	if full.size() != frames.size() or (count > 0 and full[count - 1] != frames[count - 1]):
		touch()
	full = frames
	bounds = tool_bounds
	snaps = tool_snaps
	cursor = count
	verified = count
	for index in count:
		if not _frame_ok(frames[index]):
			verified = index
			break
	end_snap = {}
	end_snap_frame = -1
	for key in markers.keys():
		if int(key) > count:
			markers.erase(key)
	if not segmented:
		var previous_count = sections.size()
		for index in range(sections.size() - 1, -1, -1):
			if sections[index].end > count:
				sections.remove(index)
		if previous_count != sections.size():
			normalize_section_order()


func ready_for_studio() -> String:
	if tool == null:
		return "Not ready"
	var game = tool._find_game()
	var player = tool._get_local_player()
	if game == null or player == null:
		return "Open a level first"
	if not game.is_server() or tool._tool_restricted():
		return "Only works in solo levels"
	if game.is_game_over():
		return "The level is finished. Save the run, or restart the level and load it to keep editing"
	if tool._practice_playback or tool._saved_macro_autoplay_slot > 0:
		return "Wait for playback to finish"
	if tool._practice_checkpoints.empty() and snaps.empty():
		return "Start a recording first"
	if not tool._ensure_practice_native_tick_hooks(game):
		return "This level does not support frame control"
	return ""


func _bound_index(frame_index: int) -> int:
	var found = 0
	for index in bounds.size():
		if bounds[index] <= frame_index and index < snaps.size():
			found = index
	return found


# Snapshot that puts the world at the start of `frame_index`.
func snap_for(frame_index: int):
	if frame_index < 0 or snaps.empty():
		return null
	var k = _bound_index(frame_index)
	if bounds[k] == frame_index:
		return snaps[k]
	if frame_index == end_snap_frame and not end_snap.empty():
		return end_snap
	if frame_index > verified or frame_index >= full.size():
		return null
	var frame = full[frame_index]
	var state = frame.get(STATE_KEY) if typeof(frame) == TYPE_DICTIONARY else null
	if typeof(state) != TYPE_DICTIONARY or not bool(state.get("native_tick_clock", false)):
		return null
	var snap = snaps[k].duplicate()
	snap.erase("moving_world_state")
	for key in state:
		if not key in SKIP_STATE_KEYS:
			snap[key] = state[key]
	snap["alive"] = true
	snap["body_enabled"] = true
	snap["dead_counter"] = 0
	for index in range(frame_index, bounds[k] - 1, -1):
		var earlier = full[index].get(STATE_KEY) if typeof(full[index]) == TYPE_DICTIONARY else null
		if typeof(earlier) == TYPE_DICTIONARY and earlier.has("object_states"):
			snap["object_states"] = earlier["object_states"]
			break
	return snap


func can_seek_instantly(frame_index: int) -> bool:
	return snap_for(frame_index) != null


# Restore frame `frame_index` and make the tool's run end there.
func instant_seek(frame_index: int, pause := true, do_sync := true, light := false) -> bool:
	if do_sync and job.empty():
		sync()
	frame_index = int(clamp(frame_index, 0, full.size()))
	var player = tool._get_local_player()
	if player == null:
		return false
	if do_sync and job.empty() and cursor == full.size() and cursor == verified and end_snap_frame != cursor and player.alive and tool._practice_active and not tool._practice_awaiting_native_respawn:
		end_snap = tool._snapshot_player(player)
		end_snap_frame = cursor
	var snap = snap_for(frame_index)
	if snap == null:
		return false
	var flow = tool._tas_run_options()
	_release_inputs()
	tool._pending_frame_step = false
	flow.native_step_remaining = 0
	flow.retry_queued = false
	tool._practice_awaiting_native_respawn = false
	tool._practice_place_pending = false
	tool._practice_start_waiting = false
	if pause and not tool._is_paused:
		tool._toggle_pause()
	tool._restore_player(player, snap)
	_apply_prefix(frame_index, light)
	cursor = frame_index
	clear_path()
	if pause:
		flow.pause_boundary.draw_paused(tool)
	emit_signal("changed")
	return true


func _apply_prefix(frame_index: int, light := false) -> void:
	var count = 0
	for index in bounds.size():
		if bounds[index] <= frame_index and index < snaps.size():
			count = index + 1
	count = max(count, 1)
	var segments = []
	for k in range(count - 1):
		segments.append(_range(full, bounds[k], bounds[k + 1]))
	tool._practice_segments = segments
	tool._practice_checkpoints = _range(snaps, 0, count)
	tool._practice_current_segment = _range(full, bounds[count - 1], frame_index)
	var player = tool._get_local_player()
	if not light or tool._practice_markers.size() != tool._practice_checkpoints.size():
		for marker in tool._practice_markers:
			if is_instance_valid(marker):
				marker.queue_free()
		tool._practice_markers.clear()
		for snap in tool._practice_checkpoints:
			if player != null and typeof(snap) == TYPE_DICTIONARY and snap.has("position"):
				tool._practice_markers.append(tool._spawn_checkpoint_marker(player, snap["position"]))
		tool._restyle_practice_markers()
	tool._diag_live_committed.clear()
	for _segment in segments:
		tool._diag_live_committed.append([])
	tool._diag_live_current.clear()
	tool._practice_active = true
	tool._practice_prev_alive = true
	tool._practice_deaths_this_segment = 0
	tool._last_frame_object_states_hash = 0
	if not light:
		tool._refresh_practice_ui()


func seek_relative(delta: int):
	if not job.empty():
		return true
	if ready_for_studio() != "":
		return null
	sync()
	var target = int(clamp(cursor + delta, 0, full.size()))
	if target == cursor:
		return null # past the end: the tool's own frame step records new input
	if instant_seek(target):
		return true
	if target > verified:
		return replay_to(target)
	return null


func seek_to(frame_index: int) -> bool:
	if not job.empty() or ready_for_studio() != "":
		return false
	sync()
	frame_index = int(clamp(frame_index, 0, full.size()))
	if instant_seek(frame_index):
		return true
	return replay_to(frame_index)


# ---------------------------------------------------------------- jobs

func busy() -> bool:
	return pending_practice_id != 0 or not job.empty() or not practice.empty() or is_instance_valid(zone_editor) or (is_instance_valid(replay_boxes) and replay_boxes.pending)


func _render_free() -> bool:
	return optimiser.empty() and not hold_render


func _save_timeline() -> Dictionary:
	return {"full": full.duplicate(), "bounds": bounds.duplicate(), "snaps": snaps.duplicate(), "verified": verified, "cursor": cursor, "end_snap": end_snap, "end_snap_frame": end_snap_frame}


func _load_timeline(saved: Dictionary) -> void:
	full = saved.full
	bounds = saved.bounds
	snaps = saved.snaps
	verified = saved.verified
	end_snap = saved.end_snap
	end_snap_frame = saved.end_snap_frame


# Feed `inputs` from frame `start` until frame `stop`, then call `done`.
func start_job(mode: String, start: int, inputs: Array, stop: int, extra := {}) -> bool:
	if not job.empty() or ready_for_studio() != "":
		return false
	_leave_timeline_preview()
	sync()
	var saved = _save_timeline()
	var light = mode == "probe" or mode == "trial"
	if not instant_seek(start, true, true, light):
		message = "Can't start from frame %d" % start
		emit_signal("changed")
		return false
	if extra.has("from_snap") and tool._get_local_player() != null:
		tool._restore_player(tool._get_local_player(), extra.from_snap)
	job = {"mode": mode, "start": start, "stop": stop, "inputs": inputs, "saved": saved, "dead": false, "dead_frame": -1, "positions": PoolVector2Array(), "reached": -1, "best_distance": INF, "began": OS.get_ticks_msec(), "finishing": false}
	for key in extra:
		job[key] = extra[key]
	held.clear()
	if mode != "replay" and not show_jobs:
		VisualServer.render_loop_enabled = false
		render_off = true
	restore_fps = true
	Engine.target_fps = 0
	tool._saved_time_scale = 1.0
	if tool._is_paused:
		tool._toggle_pause()
	if mode == "replay":
		Engine.time_scale = replay_speed if stop - start > APPROACH else 0.15
	else:
		Engine.time_scale = FAST_PROBE
	if not light:
		emit_signal("changed")
	return true


# Called by the tool right before it records a live native frame.
func before_live_tick(player) -> void:
	if not practice.empty():
		_practice_tick(player)
		return
	if job.empty() or job.finishing:
		return
	if not player.alive:
		on_death()
		return
	var frame_index = tool._practice_recorded_frame_count() + tool._practice_current_segment.size()
	# The body has finished the previous tick; the node pose can lag a batch.
	var at = player.body.global_position if player.body != null else player.position
	job.positions.append(at)
	if job.has("ground"):
		var normal = player.get("ground_normal")
		job.ground.append(normal is Vector2 and normal != Vector2.ZERO)
	if job.has("zone"):
		if enters_zone(job.zone, job.get("last_at", at), at):
			job.reached = frame_index
			_end_job()
			return
		job.last_at = at
	elif job.has("gate"):
		# Reaching a gate counts once the run has survived a few more frames.
		if job.reached >= 0:
			job.gate_left -= 1
			if job.gate_left <= 0:
				_end_job()
				return
		elif gate_crossed(job.gate, job.get("last_at", at), at):
			job.reached = frame_index
			job.gate_left = GATE_CONTINUE
		job.last_at = at
	elif job.has("target"):
		# Distance from the target to the path since the last tick, so a fast
		# Goober can't skip past it between two samples.
		var from = job.get("last_at", at)
		job.last_at = at
		var closest = Geometry.get_closest_point_to_segment_2d(job.target, from, at)
		var distance = closest.distance_to(job.target)
		job.best_distance = min(job.best_distance, distance)
		if distance <= job.radius and job.reached < 0:
			job.reached = frame_index
			_end_job()
			return
	var offset = frame_index - job.start
	if frame_index >= job.stop or offset >= job.inputs.size() or offset < 0:
		_end_job()
		return
	_feed(job.inputs[offset], player)
	if job.mode == "replay" and job.stop - frame_index <= APPROACH:
		Engine.time_scale = 0.15


func on_death() -> void:
	if not practice.empty():
		_practice_end_take(true)
		return
	# A death while a bot is between its own runs: stop it and put the run
	# back, instead of letting the normal respawn loop.
	if job.empty() and bots != null and bots.busy():
		bots.cancel()
		return
	if job.empty() or job.finishing:
		return
	job.dead = true
	job.dead_frame = tool._practice_recorded_frame_count() + tool._practice_current_segment.size()
	_end_job()


func _end_job() -> void:
	# This callback sees the exact beginning-of-tick boundary. The already
	# latched native batch may still advance before the deferred finish runs.
	# Keep a FULL snapshot here, including world phase and motion timers.
	var player = tool._get_local_player()
	if player != null and player.alive and not job.get("dead", false):
		job["boundary_snap"] = tool._snapshot_player(player)
		if player.body != null:
			# WPPlayer's display pose can lag Box2D within a native batch,
			# exactly as in _capture_practice_frame_state().
			job.boundary_snap.position = player.body.global_position
			job.boundary_snap.linear_velocity = player.body.linear_velocity
		job["boundary_frame"] = tool._practice_recorded_frame_count() + tool._practice_current_segment.size()
	job.finishing = true
	_release_inputs()
	Engine.time_scale = 0.0
	tool._is_paused = true
	call_deferred("_finish_job")


func _feed(frame: Dictionary, player) -> void:
	var move_left = bool(frame.get(LEFT, false))
	var move_right = bool(frame.get(RIGHT, false))
	for entry in [[LEFT, move_left], [RIGHT, move_right], [JUMP, bool(frame.get(JUMP, false))]]:
		if bool(held.get(entry[0], false)) != entry[1]:
			tool._inject_action(entry[0], entry[1])
			held[entry[0]] = entry[1]
	var dash = bool(frame.get(DASH, false))
	if dash and not bool(held.get(DASH, false)):
		if move_left == move_right and frame.has(DASH_DIR_KEY):
			player.facing_dir = bool(frame[DASH_DIR_KEY])
		tool._inject_action(DASH, true)
		held[DASH] = true
	elif not dash and bool(held.get(DASH, false)):
		tool._inject_action(DASH, false)
		held[DASH] = false


func _release_inputs() -> void:
	for action in held:
		if held[action]:
			tool._inject_action(action, false)
	held.clear()


func _restore_render() -> void:
	if render_off:
		VisualServer.render_loop_enabled = true
		render_off = false
	if restore_fps:
		restore_fps = false
		tool._apply_fps_limit()


func _finish_job() -> void:
	if job.empty():
		return
	var finished = job
	job = {}
	if _render_free():
		_restore_render()
	tool._saved_time_scale = 1.0
	tool._practice_awaiting_native_respawn = false
	tool._tas_run_options().retry_queued = false
	var recorded = tool_frames()
	if finished.mode == "replay":
		var upto = min(recorded.size(), finished.stop)
		if finished.dead:
			upto = int(clamp(finished.dead_frame - 1, finished.start, upto))
		var old_full = finished.saved.full
		var new_full = _range(recorded, 0, upto)
		var tail = _range(old_full, upto, old_full.size())
		if not tail.empty() and recorded.size() > upto and typeof(recorded[upto].get(STATE_KEY)) == TYPE_DICTIONARY:
			# The recorder already saw the start of the next frame: give the
			# kept input its true start state.
			var first = tail[0].duplicate()
			first[STATE_KEY] = recorded[upto][STATE_KEY]
			first.erase(EDITED_KEY)
			tail[0] = first
		full = new_full + tail
		var keep_bounds = [0]
		var keep_snaps = [finished.saved.snaps[0]] if not finished.saved.snaps.empty() else []
		for index in range(1, finished.saved.bounds.size()):
			if finished.saved.bounds[index] <= finished.start and index < finished.saved.snaps.size():
				keep_bounds.append(finished.saved.bounds[index])
				keep_snaps.append(finished.saved.snaps[index])
		bounds = keep_bounds
		snaps = keep_snaps
		verified = upto
		end_snap = {}
		end_snap_frame = -1
		var player = tool._get_local_player()
		if not finished.dead and int(finished.get("boundary_frame", -1)) == upto and finished.get("boundary_snap") is Dictionary:
			end_snap = finished.boundary_snap
			end_snap_frame = upto
		elif recorded.size() == upto and player != null and player.alive:
			end_snap = tool._snapshot_player(player)
			end_snap_frame = upto
		cursor = upto
		instant_seek(upto, true, false)
		if finished.dead:
			message = "Died at frame %d -- stopped one frame before" % finished.dead_frame
	else:
		var result = _probe_result(finished, recorded)
		_load_timeline(finished.saved)
		_apply_saved_prefix(finished)
		if finished.mode == "probe" and finished.has("callback"):
			finished.callback[0].call_deferred(finished.callback[1], result)
	if finished.mode == "preview":
		path_points = finished.positions
		_draw_path()
	elif finished.mode == "trial":
		_trial_done(finished)
	emit_signal("changed")
	if not pending_restore.empty():
		var saved_project = pending_restore
		pending_restore = {}
		restore_project(saved_project)
		return
	if segment_commit >= 0 and finished.mode == "replay":
		_segment_committed()
		return
	if bots != null and finished.mode == "replay":
		bots.on_job_finished()


func _apply_saved_prefix(finished: Dictionary) -> void:
	var player = tool._get_local_player()
	var snap = snap_for(finished.start)
	if player != null and snap != null:
		tool._restore_player(player, snap)
	_apply_prefix(finished.start, finished.mode == "probe" or finished.mode == "trial")
	cursor = finished.start
	if not tool._is_paused:
		tool._toggle_pause()
	tool._tas_run_options().pause_boundary.draw_paused(tool)


func cancel_job() -> void:
	if bots != null:
		bots.cancel()
	if not practice.empty():
		stop_practice()
	if job.empty():
		return
	optimiser = {}
	if not job.finishing:
		_end_job()


func _process(_delta: float) -> void:
	var current_game = tool._find_game() if tool != null else null
	if current_game != null and not current_game.is_server() and (pending_practice_id != 0 or not practice.empty() or not job.empty() or segment_pending_start or is_instance_valid(zone_editor) or tool._macro_editor_preview_active or (bots != null and bots.busy())):
		_abandon_public_session()
	if pending_practice_id != 0:
		_watch_pending_practice()
	if not job.empty() and not job.finishing and OS.get_ticks_msec() - int(job.began) > JOB_TIMEOUT_MS:
		message = "Stopped: took too long"
		optimiser = {}
		_end_job()
	if job.empty() and render_off and _render_free():
		_restore_render()
	if records != null:
		records.tick(_delta)
	if segment_pending_start:
		_watch_segment_start()
	if not job.empty() and not job.finishing:
		var game = tool._find_game()
		if not tool._practice_active or game == null or game.is_game_over():
			message = "Stopped: the level ended"
			optimiser = {}
			_end_job()
	if ghost_node != null and is_instance_valid(ghost_node):
		ghost_node.update()
	if compare_view != null and is_instance_valid(compare_view) and not _compare_window_hidden:
		_update_compare()


# Leaving solo practice must not complete an old deferred job against a new
# public game's body. Keep the project data; abandon only live ownership.
func _abandon_public_session() -> void:
	pending_practice_id = 0
	if is_instance_valid(zone_editor):
		zone_editor.finish(false, false)
	if tool._macro_editor_preview_active:
		_leave_timeline_preview()
	practice = {}
	job = {}
	pending_restore = {}
	optimiser = {}
	segment_pending_start = false
	segment_commit = -1
	segment_commit_target = -1
	segment_next = -1
	segment_original = {}
	if bots != null:
		bots.task = {}
		bots.candidate = {}
	hold_render = false
	_release_inputs()
	_restore_render()
	tool._is_paused = false
	tool._saved_time_scale = 1.0
	Engine.time_scale = 1.0
	if is_instance_valid(window):
		window.waiting_finish = false
		window.bar.visible = false
		window.close()


# ---------------------------------------------------------------- re-play

func replay_to(target: int) -> bool:
	sync()
	target = int(clamp(target, 0, full.size()))
	var start = min(verified, target)
	while start > 0 and snap_for(start) == null:
		start -= 1
	if snap_for(start) == null:
		return false
	return start_job("replay", start, _range(full, start, target), target)


# ---------------------------------------------------------------- path preview

func preview_path(frames: int) -> bool:
	sync()
	var inputs = _range(full, cursor, cursor + frames)
	var hold = {}
	for entry in tool.BUFFERABLE_ACTIONS:
		hold[entry[1]] = bool(tool._buffered_actions.get(entry[1], false))
	while inputs.size() < frames:
		inputs.append(hold)
	return start_job("preview", cursor, inputs, cursor + frames)


func clear_path() -> void:
	path_points = PoolVector2Array()
	if path_node != null and is_instance_valid(path_node):
		path_node.points = path_points
		path_node.update()


func _draw_path() -> void:
	var player = tool._get_local_player()
	if player == null or player.get_parent() == null:
		return
	if path_node == null or not is_instance_valid(path_node):
		path_node = PathLine.new()
		player.get_parent().add_child(path_node)
	path_node.points = path_points
	path_node.update()


class PathLine extends Node2D:
	var points = PoolVector2Array()

	func _ready() -> void:
		z_index = 4000

	func _draw() -> void:
		if points.size() < 2:
			return
		var colour = Color("7fe0b4")
		for index in range(1, points.size()):
			var fade = 0.35 + 0.65 * (1.0 - float(index) / points.size())
			draw_line(points[index - 1], points[index], Color(colour.r, colour.g, colour.b, fade), 3.0, true)
			if index % 10 == 0:
				draw_circle(points[index], 4.0, Color(1, 1, 1, fade))
		draw_circle(points[points.size() - 1], 7.0, Color("ffc46b"))


# ---------------------------------------------------------------- input rows

static func signature(frame) -> String:
	if typeof(frame) != TYPE_DICTIONARY:
		return ""
	var text = ""
	if frame.get(LEFT, false): text += "L"
	if frame.get(RIGHT, false): text += "R"
	if frame.get(JUMP, false): text += "J"
	if frame.get(DASH, false): text += "D" + (">" if bool(frame.get(DASH_DIR_KEY, true)) else "<")
	return text


func rows() -> Array:
	var result = []
	var index = 0
	while index < full.size():
		var sig = signature(full[index])
		var start = index
		while index < full.size() and signature(full[index]) == sig:
			index += 1
		result.append({"start": start, "count": index - start, "sig": sig})
	return result


func inputs_frame(sig: String) -> Dictionary:
	var frame = {LEFT: "L" in sig, RIGHT: "R" in sig, JUMP: "J" in sig, DASH: "D" in sig}
	if "D" in sig:
		frame[DASH_DIR_KEY] = not "D<" in sig
	return frame


func _push_undo(first_changed: int) -> void:
	undo_stack.append({"full": full.duplicate(), "first": first_changed, "markers": markers.duplicate(), "sections": sections.duplicate(true), "segmented":segmented,"guide_points":guide_points})
	if undo_stack.size() > 40:
		undo_stack.pop_front()


# Replace full[first, last) with `frames`. Keeps the start state of the first
# frame (it depends only on earlier frames), so seeking there stays instant.
func replace_frames(first: int, last: int, frames: Array) -> void:
	_push_undo(first)
	var entry_snap = snap_for(first)
	var state = full[first].get(STATE_KEY) if first < full.size() and typeof(full[first]) == TYPE_DICTIONARY else null
	var marked = []
	for frame in frames:
		var copy = frame.duplicate()
		copy.erase(STATE_KEY)
		copy[EDITED_KEY] = true
		marked.append(copy)
	touch()
	full = _range(full, 0, first) + marked + _range(full, last, full.size())
	if first < full.size() and state != null:
		var head = full[first].duplicate()
		head[STATE_KEY] = state
		full[first] = head
	verified = min(verified, first)
	if end_snap_frame >= first:
		end_snap = {}
		end_snap_frame = -1
	var keep_bounds = []
	var keep_snaps = []
	for index in bounds.size():
		if bounds[index] <= first and index < snaps.size():
			keep_bounds.append(bounds[index])
			keep_snaps.append(snaps[index])
	bounds = keep_bounds
	snaps = keep_snaps
	# Appending a new segment invalidates the old terminal cache, but that
	# exact state is still the unchanged entry of the replacement inputs.
	if entry_snap != null and (bounds.empty() or int(bounds.back()) != first):
		bounds.append(first)
		snaps.append(entry_snap)
	var shift = frames.size() - (last - first)
	_shift_sections(last, shift)
	var moved = {}
	for key in markers:
		var at = int(key)
		moved[at + shift if at >= last else at] = true
	markers = moved
	emit_signal("changed")


func undo() -> bool:
	if undo_stack.empty() or not job.empty():
		return false
	var entry = undo_stack.pop_back()
	full = entry.full
	markers = entry.markers
	if entry.has("sections"):
		sections = entry.sections
		normalize_section_order()
	if bool(entry.get("box_import",false)):
		segmented = bool(entry.get("segmented",segmented))
		guide_points = entry.get("guide_points",guide_points)
		touch()
		emit_signal("changed")
		return true
	touch()
	verified = min(verified, entry.first)
	if end_snap_frame >= entry.first:
		end_snap = {}
		end_snap_frame = -1
	emit_signal("changed")
	return true


# ---------------------------------------------------------------- reference

func set_reference(name: String, frames: Array, ref_bounds: Array) -> bool:
	var points = PoolVector2Array()
	for frame in frames:
		var state = frame.get(STATE_KEY) if typeof(frame) == TYPE_DICTIONARY else null
		if typeof(state) != TYPE_DICTIONARY or not state.has("position"):
			if points.empty():
				continue
			points.append(points[points.size() - 1])
		else:
			points.append(state["position"])
	if points.size() < 2:
		return false
	reference = {"name": name, "points": points, "bounds": ref_bounds.duplicate()}
	return true


func current_frame() -> int:
	if tool._practice_playback:
		return tool._practice_playback_index
	return tool._practice_recorded_frame_count() + tool._practice_current_segment.size()


# Frames behind (+) or ahead (-) of the reference at the player's position.
func reference_delta():
	if reference.empty():
		return null
	var player = tool._get_local_player()
	if player == null:
		return null
	var frame_index = current_frame()
	var points: PoolVector2Array = reference.points
	var best = -1
	var best_distance = 80.0
	for index in range(max(0, frame_index - 600), min(points.size(), frame_index + 600)):
		var distance = points[index].distance_to(player.position)
		if distance < best_distance:
			best_distance = distance
			best = index
	return null if best < 0 else frame_index - best


func show_ghost(value: bool) -> void:
	if not value:
		if ghost_node != null and is_instance_valid(ghost_node):
			ghost_node.queue_free()
		ghost_node = null
		return
	var player = tool._get_local_player()
	if player == null or player.get_parent() == null:
		return
	if ghost_node == null or not is_instance_valid(ghost_node):
		ghost_node = Ghost.new()
		ghost_node.studio = self
		player.get_parent().add_child(ghost_node)


class Ghost extends Node2D:
	var studio = null

	func _ready() -> void:
		z_index = 3990

	func _draw() -> void:
		if studio == null or studio.reference.empty():
			return
		var points: PoolVector2Array = studio.reference.points
		var at = int(clamp(studio.current_frame(), 0, points.size() - 1))
		var tint = Color("b49cff")
		for back in range(12, 0, -3):
			var index = at - back
			if index >= 0:
				draw_circle(points[index], 10.0, Color(tint.r, tint.g, tint.b, 0.08))
		draw_circle(points[at], 22.0, Color(tint.r, tint.g, tint.b, 0.28))
		draw_arc(points[at], 22.0, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.8), 2.5, true)


# Side-by-side: a second view of the same loaded level that follows the
# reference run at the current frame (time alignment).
func show_compare(value: bool) -> void:
	if compare_view != null and is_instance_valid(compare_view):
		compare_view.queue_free()
	compare_view = null
	if not value:
		return
	var layer = CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	compare_view = layer
	var frame = PanelContainer.new()
	frame.add_stylebox_override("panel", GoobStyle.box(Color(0.05, 0.07, 0.08, 0.92), GoobStyle.VIOLET, 4, 8))
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.margin_left = -500
	frame.margin_top = -320
	frame.margin_right = -16
	frame.margin_bottom = -16
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(frame)
	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	var label = Label.new()
	label.name = "Caption"
	label.add_color_override("font_color", GoobStyle.INK)
	box.add_child(label)
	var container = ViewportContainer.new()
	container.stretch = true
	container.rect_min_size = Vector2(476, 268)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(container)
	var viewport = Viewport.new()
	viewport.size = Vector2(476, 268)
	viewport.world_2d = get_viewport().world_2d
	viewport.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	var camera = Camera2D.new()
	camera.name = "Camera"
	viewport.add_child(camera)
	camera.current = true
	layer.set_meta("camera", camera)
	layer.set_meta("caption", label)
	layer.set_meta("viewport", viewport)
	layer.set_meta("frame", frame)
	_sync_compare_visibility()
	if not _compare_window_hidden: _update_compare()


func set_f1_hidden(value: bool) -> void:
	_compare_window_hidden = value
	_sync_compare_visibility()

func _sync_compare_visibility() -> void:
	if not is_instance_valid(compare_view): return
	var frame = compare_view.get_meta("frame")
	var viewport = compare_view.get_meta("viewport")
	if is_instance_valid(frame): frame.visible = not _compare_window_hidden
	if is_instance_valid(viewport): viewport.render_target_update_mode = Viewport.UPDATE_DISABLED if _compare_window_hidden else Viewport.UPDATE_WHEN_VISIBLE

func _update_compare() -> void:
	var camera = compare_view.get_meta("camera")
	var caption = compare_view.get_meta("caption")
	if reference.empty():
		caption.text = "Pick a reference run to compare"
		return
	var points: PoolVector2Array = reference.points
	var at = int(clamp(current_frame(), 0, points.size() - 1))
	camera.position = points[at]
	var main = compare_view.get_meta("main") if compare_view.has_meta("main") else null
	if main == null or not is_instance_valid(main):
		main = tool.call("_find_playback_camera") if tool.has_method("_find_playback_camera") else null
		compare_view.set_meta("main", main)
	camera.zoom = main.zoom if main != null and main is Camera2D else Vector2.ONE
	var delta = reference_delta()
	var text = "Reference at frame %d%s" % [at, ("   ·   you are %+d frames (approx.)" % delta) if delta != null else ""]
	if caption.text != text: caption.text = text


# ---------------------------------------------------------------- optimiser

# Tries moving one input row's start and length by up to `reach` frames and
# keeps whichever version reaches the target spot soonest without dying.
func optimise(row_index: int, target_frame: int, reach: int) -> bool:
	sync()
	var list = rows()
	if row_index < 0 or row_index >= list.size() or not job.empty():
		return false
	var row = list[row_index]
	target_frame = int(clamp(target_frame, row.start + row.count, full.size()))
	if target_frame > verified:
		message = "Re-play up to the target before optimising"
		emit_signal("changed")
		return false
	var target_snap = snap_for(target_frame)
	if target_snap == null or not target_snap.has("position"):
		message = "Pick a target frame that has been played"
		emit_signal("changed")
		return false
	var start = max(0, row.start - reach - 1)
	while start > 0 and snap_for(start) == null:
		start -= 1
	var before = list[row_index - 1].sig if row_index > 0 else ""
	var after = list[row_index + 1].sig if row_index + 1 < list.size() else ""
	var variants = [[0, 0]] # baseline first: the time to beat
	for shift in range(-reach, reach + 1):
		for grow in range(-reach, reach + 1):
			if row.count + grow < 1 or (shift == 0 and grow == 0):
				continue
			variants.append([shift, grow])
	optimiser = {"row": row, "start": start, "target": target_snap["position"], "target_frame": target_frame, "before": before, "after": after, "variants": variants, "index": 0, "best": null, "best_frame": target_frame, "baseline": target_frame, "tried": 0}
	message = "Optimising: 0/%d" % variants.size()
	call_deferred("_next_trial")
	return true


func _variant_inputs(variant: Array) -> Array:
	var row = optimiser.row
	var start = optimiser.start
	var new_first = row.start + variant[0]
	var new_last = new_first + row.count + variant[1]
	var limit = optimiser.target_frame + 40
	var result = []
	for index in range(start, limit):
		var sig = signature(full[index]) if index < full.size() else ""
		var inside_old = index >= row.start and index < row.start + row.count
		var inside_new = index >= new_first and index < new_last
		if inside_new:
			sig = row.sig
		elif inside_old:
			sig = optimiser.before if index < new_first else optimiser.after
		result.append(inputs_frame(sig))
	return result


func _next_trial() -> void:
	if optimiser.empty():
		return
	if optimiser.index >= optimiser.variants.size():
		_apply_best()
		return
	var variant = optimiser.variants[optimiser.index]
	var inputs = _variant_inputs(variant)
	var radius = 10.0
	if not start_job("trial", optimiser.start, inputs, optimiser.start + inputs.size(), {"target": optimiser.target, "radius": radius, "variant": variant, "trial_inputs": inputs}):
		message = "Optimiser stopped"
		optimiser = {}
		emit_signal("changed")


func _trial_done(finished: Dictionary) -> void:
	if optimiser.empty():
		return
	optimiser.tried += 1
	if optimiser.tried == 1:
		if finished.dead or finished.reached < 0:
			message = "The current inputs don't reach the target -- re-play first"
			optimiser = {}
			emit_signal("changed")
			return
		optimiser.baseline = finished.reached
		optimiser.best_frame = finished.reached
	elif not finished.dead and finished.reached >= 0 and finished.reached < optimiser.best_frame:
		optimiser.best_frame = finished.reached
		optimiser.best = {"variant": finished.variant, "inputs": finished.trial_inputs}
	optimiser.index += 1
	message = "Optimising: %d/%d" % [optimiser.index, optimiser.variants.size()]
	call_deferred("_next_trial")


func _apply_best() -> void:
	var result = optimiser
	optimiser = {}
	_restore_render()
	if result.best == null:
		message = "No faster version found in that range"
		emit_signal("changed")
		return
	var saved = result.baseline - result.best_frame
	var used = _range(result.best.inputs, 0, result.best_frame - result.start)
	replace_frames(result.start, result.target_frame, used)
	var variant = result.best.variant
	message = "%d frame%s faster (start %+d, length %+d)" % [saved, "" if saved == 1 else "s", variant[0], variant[1]]
	replay_to(result.best_frame)


# ---------------------------------------------------------------- sections

func section_frames() -> Array:
	var result = []
	for index in range(bounds.size()):
		var last = bounds[index + 1] if index + 1 < bounds.size() else full.size()
		result.append(last - bounds[index])
	return result


# ---------------------------------------------------------------- probes

# Snapshot from a recorded frame's start state on top of a checkpoint.
func snap_from_state(state: Dictionary, base: Dictionary) -> Dictionary:
	var snap = base.duplicate()
	snap.erase("moving_world_state")
	for key in state:
		if not key in SKIP_STATE_KEYS:
			snap[key] = state[key]
	if state.has("object_states"):
		snap["object_states"] = state["object_states"]
	snap["alive"] = true
	snap["body_enabled"] = true
	snap["dead_counter"] = 0
	return snap


func _probe_result(finished: Dictionary, recorded: Array) -> Dictionary:
	var result = {"dead": finished.dead, "reached": finished.reached, "best_distance": finished.best_distance, "positions": finished.positions, "ground": finished.get("ground", []), "end_offset": -1, "end_snap": {}, "end_position": Vector2.ZERO, "end_velocity": Vector2.ZERO}
	if finished.reached >= 0:
		result.reached = finished.reached - finished.start
	if finished.dead or recorded.size() <= finished.start:
		return result
	var last = recorded.size() - 1
	var state = recorded[last].get(STATE_KEY) if typeof(recorded[last]) == TYPE_DICTIONARY else null
	if typeof(state) != TYPE_DICTIONARY:
		return result
	var base = finished.get("from_snap", snaps[_bound_index(finished.start)] if not snaps.empty() else {})
	var snap = snap_from_state(state, base)
	if not snap.has("object_states"):
		for index in range(last, finished.start - 1, -1):
			var earlier = recorded[index].get(STATE_KEY) if typeof(recorded[index]) == TYPE_DICTIONARY else null
			if typeof(earlier) == TYPE_DICTIONARY and earlier.has("object_states"):
				snap["object_states"] = earlier["object_states"]
				break
	result.end_offset = last - finished.start
	result.end_snap = snap
	result.end_position = state.get("position", Vector2.ZERO)
	result.end_velocity = state.get("linear_velocity", Vector2.ZERO)
	return result


# Runs `inputs` from frame `start` (or from `from_snap` placed there) and
# sends the result dictionary to target.method.
func probe(start: int, inputs: Array, target_object, method: String, extra := {}) -> bool:
	extra = extra.duplicate()
	extra["callback"] = [target_object, method]
	return start_job("probe", start, inputs, start + inputs.size(), extra)


func position_at(frame_index: int):
	var snap = snap_for(frame_index)
	return snap.get("position") if snap != null else null


# ---------------------------------------------------------------- project

# Everything the format-3 macro can't hold, as plain data: the run after
# `prefix_count`, later checkpoints, sections with takes, markers, draft text.
func project_data(prefix_count: int) -> Dictionary:
	var later_bounds = []
	var later_snaps = []
	for index in bounds.size():
		if bounds[index] > prefix_count and index < snaps.size():
			later_bounds.append(bounds[index])
			later_snaps.append(snaps[index])
	var draft = ""
	if window != null and is_instance_valid(window):
		draft = window.draft_text()
	return {"version": 1, "tail": _range(full, prefix_count, full.size()).duplicate(true), "verified": verified, "later_bounds": later_bounds, "later_snaps": later_snaps.duplicate(true), "sections": sections.duplicate(true), "markers": markers.keys(), "draft": draft, "next_id": next_id, "segmented": segmented, "workflow_mode": workflow_mode, "guide_points": guide_points, "end_snap": end_snap.duplicate(true), "end_snap_frame": end_snap_frame}


# Called right after the macro part was installed and synced.
func load_project_data(data: Dictionary) -> void:
	segmented = bool(data.get("segmented", false))
	_restore_workflow_mode(data)
	guide_points = data.get("guide_points", PoolVector2Array())
	var count = full.size()
	var tail = data.get("tail", [])
	if tail is Array and not tail.empty():
		full = full + tail
		if verified >= count:
			verified = int(clamp(int(data.get("verified", count)), count, full.size()))
		for index in data.get("later_bounds", []).size():
			if index < data.get("later_snaps", []).size():
				bounds.append(int(data.later_bounds[index]))
				snaps.append(data.later_snaps[index])
	if data.get("sections") is Array:
		sections = data.sections
		for section in sections:
			_fill_section(section)
		normalize_section_order()
	markers = {}
	for key in data.get("markers", []):
		markers[int(key)] = true
	next_id = max(next_id, int(data.get("next_id", 1)))
	if data.get("end_snap") is Dictionary and int(data.get("end_snap_frame", -1)) <= full.size():
		end_snap = data.end_snap
		end_snap_frame = int(data.get("end_snap_frame", -1))
	if window != null and is_instance_valid(window) and not str(data.get("draft", "")).empty():
		window.set_draft(str(data.draft))
	touch()
	if window != null and is_instance_valid(window):
		window.project_loaded()
	emit_signal("changed")


# A full copy of the working project, for bots that must be able to put
# everything back exactly as it was.
func snapshot_project() -> Dictionary:
	var saved = _save_timeline()
	saved["sections"] = sections.duplicate(true)
	saved["markers"] = markers.duplicate()
	saved["undo_size"] = undo_stack.size()
	return saved


func restore_project(saved: Dictionary) -> void:
	_load_timeline(saved)
	sections = saved.sections.duplicate(true)
	normalize_section_order()
	markers = saved.markers.duplicate()
	while undo_stack.size() > int(saved.undo_size):
		undo_stack.pop_back()
	touch()
	var target = int(clamp(int(saved.cursor), 0, full.size()))
	if not instant_seek(target, true, false):
		instant_seek(0, true, false)
	emit_signal("changed")


# Drop the per-step undo entries a bot made and leave one that returns to
# `saved`, so a whole bot result is a single undo.
func collapse_undo(saved: Dictionary, first_changed: int) -> void:
	while undo_stack.size() > int(saved.undo_size):
		undo_stack.pop_back()
	undo_stack.append({"full": saved.full.duplicate(), "first": first_changed, "markers": saved.markers.duplicate(), "sections": saved.sections.duplicate(true)})


# ---------------------------------------------------------------- sections

# Display ordinals follow goal order; IDs belong to sections/takes forever.
# Editing an unfinished route can remove or move a selected goal behind its
# source. Match the stored target to target_for()'s own-box fallback, keeping
# old takes and their original destinations available in the project.
func normalize_section_order() -> void:
	var positions = {}
	for index in sections.size():
		positions[int(sections[index].id)] = index
	for index in sections.size():
		var section = sections[index]
		section.name = "Section %d" % (index + 1)
		if int(positions.get(int(section.get("target_id",section.id)), -1)) < index:
			section["target_id"] = int(section.id)
			_pick_best(section)


func section_name(index: int) -> String:
	return "Section %d" % (index + 1)


# A box number is its route position, not its immutable ID or a cosmetic name.
# Preserve the recorded timeline and every take. Reopen affected progress so a
# newly ordered route cannot pretend its old kept spans satisfy the new goals.
func move_section(index: int, target: int) -> bool:
	if index < 0 or index >= sections.size() or target < 0 or target >= sections.size():
		return false
	if not job.empty() or not practice.empty() or pending_practice_id != 0 or (bots != null and bots.busy()):
		return false
	if index == target:
		return true
	var first = min(index, target)
	if segmented:
		# An already kept shortcut spanning the edit owns the earlier entry.
		# Reopen its source too, rather than treating a newly inserted goal as
		# though that historical take had visited it.
		for previous in range(first):
			if bool(sections[previous].get("done",false)) and target_for(previous) >= first:
				first = previous
				break
	var section = sections[index]
	sections.remove(index)
	sections.insert(target, section)
	normalize_section_order()
	if segmented:
		for later in range(first, sections.size()):
			var changed_section = sections[later]
			changed_section.done = false
			changed_section.start = -1
			changed_section.end = -1
			changed_section.used = 0
			changed_section.erase("skipped_by")
		_bind_open_segment_start()
	message = "Box moved to %d. Replay and takes kept." % (target + 1)
	touch()
	emit_signal("changed")
	return true


func _fill_section(section: Dictionary) -> void:
	for entry in [["id", 0], ["name", ""], ["takes", []], ["best", -1], ["used", 0], ["attempts", 0], ["clears", 0], ["streak", 0]]:
		if not section.has(entry[0]):
			section[entry[0]] = entry[1] if typeof(entry[1]) != TYPE_ARRAY else []
	if int(section.id) == 0:
		section.id = new_id()
	for take in section.takes:
		if not take.has("id") or int(take.id) == 0:
			take["id"] = new_id()
		if not take.has("pinned"):
			take["pinned"] = false
	# Older saves kept dead attempts as takes; they are only counted now.
	for index in range(section.takes.size() - 1, -1, -1):
		if bool(section.takes[index].get("died", false)):
			section.takes.remove(index)
	_pick_best(section)
	if not section.has("target_id"):
		section["target_id"] = int(section.id)


func add_section(first: int, last: int) -> int:
	first = int(clamp(first, 0, full.size()))
	last = int(clamp(last, first + 1, full.size()))
	for section in sections:
		if first < section.end and last > section.start:
			message = "Sections can't overlap"
			emit_signal("changed")
			return -1
	var section = {"start": first, "end": last, "target": position_at(last)}
	_fill_section(section)
	section.name = "Section %d" % (sections.size() + 1)
	sections.append(section)
	sections.sort_custom(self, "_section_order")
	normalize_section_order()
	touch()
	emit_signal("changed")
	for index in sections.size():
		if sections[index].start == first:
			return index
	return -1


func _section_order(a, b) -> bool:
	return a.start < b.start


func remove_section(index: int) -> void:
	if index >= 0 and index < sections.size():
		_push_undo(full.size())
		sections.remove(index)
		normalize_section_order()
		touch()
		emit_signal("changed")


func _shift_sections(first: int, shift: int) -> void:
	for section in sections:
		if section.start >= first:
			section.start += shift
			section.end += shift
		elif section.end > first:
			section.end = max(section.start + 1, section.end + shift)


# Finish line of a section: a line across the recorded path at its end,
# facing the way the run was moving there.
func gate_for(section: Dictionary):
	var at = position_at(section.end)
	if at == null:
		return null
	var direction = Vector2.ZERO
	var snap = snap_for(section.end)
	if snap != null and snap.get("linear_velocity", Vector2.ZERO).length() > 1.0:
		direction = snap.linear_velocity.normalized()
	else:
		var before = position_at(max(section.start, section.end - 4))
		if before != null and before.distance_to(at) > 0.5:
			direction = (at - before).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	return {"at": at, "dir": direction, "half": GATE_HALF}


# Did the path from `from` to `to` cross the gate in its direction? The
# small end-point radius stays as a fallback for exits that stop on the spot.
static func gate_crossed(gate: Dictionary, from: Vector2, to: Vector2) -> bool:
	var before = (from - gate.at).dot(gate.dir)
	var after = (to - gate.at).dot(gate.dir)
	if before < 0.0 and after >= 0.0:
		var t = before / (before - after) if before != after else 1.0
		var point = from.linear_interpolate(to, t)
		if abs((point - gate.at).dot(gate.dir.tangent())) <= float(gate.half):
			return true
	# Fallback: entering a small circle around the end point.
	if from.distance_to(gate.at) <= 16.0:
		return false
	var closest = Geometry.get_closest_point_to_segment_2d(gate.at, from, to)
	return closest.distance_to(gate.at) <= 16.0


# Stop block of a section: a box around where the run is at the section end.
func zone_for(section: Dictionary):
	if section.get("zone") is Rect2:
		return section.zone
	var at = position_at(section.end)
	if at == null:
		return null
	return Rect2(at - ZONE_SIZE * 0.5, ZONE_SIZE)


func start_marker_for(section: Dictionary):
	var at = position_at(section.start) if int(section.start) >= 0 else null
	if at == null and segmented:
		return section.get("start_pos")
	return at


# Did the path from `from` to `to` touch the box (fast moves included)?
static func enters_zone(zone: Rect2, from: Vector2, to: Vector2) -> bool:
	if zone.has_point(to):
		return true
	var corners = [zone.position, Vector2(zone.end.x, zone.position.y), zone.end, Vector2(zone.position.x, zone.end.y)]
	for index in 4:
		if Geometry.segment_intersects_segment_2d(from, to, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false


# Split the played run into sections of about three seconds, cutting where
# the Goober is on the ground so every section starts from a calm moment.
func make_sections() -> int:
	sync()
	var limit = min(verified, full.size())
	sections = []
	if limit < 2:
		return make_map_boxes()
	var start = 0
	while start < limit:
		var cut = -1
		var best_score = INF
		for index in range(start + SECTION_MIN, min(start + SECTION_MAX, limit - 1) + 1):
			if not _grounded(index) or not _grounded(index - 1) or not _grounded(index - 2):
				continue
			var score = abs(index - (start + SECTION_TARGET))
			if score < best_score:
				best_score = score
				cut = index
		if cut < 0:
			cut = min(start + SECTION_TARGET, limit)
		if limit - cut < SECTION_MIN:
			cut = limit
		var section = {"start": start, "end": cut}
		_fill_section(section)
		section["base"] = cut - start
		section.name = "Section %d" % (sections.size() + 1)
		sections.append(section)
		start = cut
	touch()
	emit_signal("changed")
	return sections.size()


func _grounded(frame_index: int) -> bool:
	if frame_index < 0 or frame_index >= full.size() or typeof(full[frame_index]) != TYPE_DICTIONARY:
		return false
	var state = full[frame_index].get(STATE_KEY)
	if typeof(state) != TYPE_DICTIONARY:
		return false
	var normal = state.get("ground_normal")
	return normal is Vector2 and normal != Vector2.ZERO


func section_frames_now(section: Dictionary) -> int:
	return int(section.end) - int(section.start)


# Timeline owns a scene-tree pause as well as a temporary player pose.
# End that ownership BEFORE restoring a live practice/job boundary.
func _leave_timeline_preview() -> void:
	if is_instance_valid(zone_editor):
		zone_editor.finish(true, false)
	if not tool._macro_editor_preview_active:
		return
	var editor = tool.get("_macro_editor")
	if editor != null and is_instance_valid(editor) and editor.has_method("close_editor"):
		editor.close_editor()
	else:
		tool._end_macro_editor_preview()


func section_index_for_id(section_id: int) -> int:
	for index in sections.size():
		if int(sections[index].id) == section_id:
			return index
	return -1


func target_for(index: int) -> int:
	if index < 0 or index >= sections.size():
		return -1
	return int(max(index, section_index_for_id(int(sections[index].get("target_id", sections[index].id)))))


func set_section_target(index: int, target: int) -> void:
	if index < 0 or target < index or target >= sections.size() or busy():
		return
	sections[index]["target_id"] = int(sections[target].id)
	_pick_best(sections[index])
	touch()
	emit_signal("changed")


func start_practice(index: int, at_native_entry := false) -> bool:
	if index < 0 or index >= sections.size() or busy():
		return false
	var game = tool._find_game()
	if game == null or not game.is_server() or tool._tool_restricted() or game.is_game_over():
		message = "Open an unfinished solo level first"
		return false
	_leave_timeline_preview()
	sync()
	if tool._practice_start_waiting or tool._practice_restart_from_game_id != 0 or not tool._game_ready_for_practice_start(at_native_entry):
		return _queue_practice(index, snaps.empty())
	if snaps.empty():
		return _queue_practice(index, true)
	if segmented:
		_bind_open_segment_start()
	var section = sections[index]
	var target = target_for(index) if segmented else index
	var zone = zone_for(sections[target])
	if zone == null or snap_for(section.start) == null:
		message = "This part of the run hasn't been played yet"
		emit_signal("changed")
		return false
	if not instant_seek(section.start, false):
		return false
	var player = tool._get_local_player()
	var at = player.body.global_position if player.body != null else player.position
	practice = {"section": index, "target": target, "zone": zone, "armed": not zone.has_point(at), "began": OS.get_ticks_msec(), "last_at": null, "entry_snapshot": snap_for(section.start).duplicate(true)}
	if tool._is_paused:
		tool._toggle_pause()
	message = ""
	emit_signal("changed")
	return true


func _queue_practice(index: int, need_recording: bool) -> bool:
	pending_practice_id = int(sections[index].id)
	pending_practice_level = str(tool._capture_current_time_trial_level_context().get("level_id",""))
	pending_practice_revision = int(tool._practice_data_revision)
	pending_practice_began = OS.get_ticks_msec()
	message = "Waiting for the level countdown"
	if need_recording and not tool._practice_start_waiting:
		if tool._practice_active:
			tool._stop_practice_mode()
		tool._on_toggle_practice_pressed(true)
		var game = tool._find_game()
		if game != null and game.wp_game_data.gameplay_state == WPGameData.GameplayState_LEVEL_PRE:
			tool._tas_run_options().pause_boundary.arm(tool)
	if tool._is_paused:
		tool._toggle_pause()
	if Engine.time_scale <= 0.0:
		Engine.time_scale = 1.0
	emit_signal("changed")
	return true


func cancel_practice_request() -> void:
	pending_practice_id = 0
	message = ""


func _watch_pending_practice() -> void:
	var context = tool._capture_current_time_trial_level_context()
	if OS.get_ticks_msec()-pending_practice_began > 30000 or (not pending_practice_level.empty() and str(context.get("level_id","")) != pending_practice_level):
		cancel_practice_request()
		message = "Practice cancelled: the level changed or did not become playable"
		emit_signal("changed")
		return
	if tool._practice_start_waiting or tool._practice_restart_from_game_id != 0:
		return
	# A fresh native-entry capture can already be paused at tick zero. Do not
	# wait for more simulated time after that verified handoff (it would stall).
	var trusted_entry = pending_practice_revision != int(tool._practice_data_revision)
	if not tool._game_ready_for_practice_start(trusted_entry):
		return
	var player = tool._get_local_player()
	if player == null or not tool._player_ready_for_checkpoint(player):
		return
	var index = section_index_for_id(pending_practice_id)
	pending_practice_id = 0
	if index >= 0:
		# Re-enter through the same checked path after the native handoff.
		start_practice(index, trusted_entry)
		if is_instance_valid(window):
			window.practice_ready(index)
	else:
		message = "The requested section was removed"
		emit_signal("changed")


func _practice_tick(player) -> void:
	if practice.get("ending", false):
		return
	var at = player.body.global_position if player.body != null else player.position
	var from = practice.last_at if practice.last_at != null else at
	practice.last_at = at
	# An overlapping start/stop box must be left before it can be entered.
	# Otherwise a zero-input clear/retry loop makes the player look frozen.
	if not bool(practice.get("armed", true)):
		practice.armed = not practice.zone.has_point(at)
		return
	if enters_zone(practice.zone, from, at):
		# Score the first arrival, not an arbitrary extra landing delay.
		# The next segment inherits its real native position AND momentum.
		_practice_end_take(false)


# Reaching the stop block saves the try; dying only counts it. Both go
# straight back to the section start.
func _practice_end_take(died: bool) -> void:
	if practice.empty() or practice.get("ending", false):
		return
	practice.ending = true
	var section = sections[practice.section]
	section.attempts += 1
	if died:
		section.streak = 0
		section["last"] = -1
	else:
		section.clears += 1
		section.streak += 1
		var frames = tool_frames()
		var inputs = []
		for index in range(section.start, frames.size()):
			var copy = {}
			for key in [LEFT, RIGHT, JUMP, DASH, DASH_DIR_KEY]:
				if frames[index].has(key):
					copy[key] = frames[index][key]
			inputs.append(copy)
		section["last"] = inputs.size()
		if not inputs.empty():
			var target_id = int(sections[int(practice.get("target", practice.section))].id)
			var take = {"id": new_id(), "inputs": inputs, "frames": inputs.size(), "at": OS.get_unix_time(), "pinned": false, "target_id": target_id}
			# Keep the actual successful native branch. Input-only reconstruction
			# can diverge from contact/animation state and stop at a different spot.
			var player = tool._get_local_player()
			if player != null and player.alive and player.body != null:
				var terminal = tool._snapshot_player(player)
				terminal.position = player.body.global_position
				terminal.linear_velocity = player.body.linear_velocity
				take["recorded_frames"] = _range(frames, int(section.start), frames.size())
				take["entry_snapshot"] = practice.entry_snapshot
				take["end_snapshot"] = terminal
			section.takes.append(take)
			_trim_takes(section)
			_pick_best(section)
			if records != null:
				records.on_take(section, inputs.size())
	touch()
	call_deferred("_practice_restart")


# Keep pinned, used and best takes; of the rest keep the fastest few.
func _trim_takes(section: Dictionary) -> void:
	if TAKES_KEPT <= 0:
		return
	_pick_best(section)
	var best_id = section.takes[section.best].id if section.best >= 0 else 0
	var loose = []
	for take in section.takes:
		if not take.pinned and int(take.id) != int(section.used) and int(take.id) != int(best_id):
			loose.append(take)
	loose.sort_custom(self, "_faster")
	for index in range(TAKES_KEPT - 1, loose.size()):
		section.takes.erase(loose[index])


func _faster(a, b) -> bool:
	return a.frames < b.frames


func _pick_best(section: Dictionary) -> void:
	section.best = -1
	var recorded_best = false
	for index in section.takes.size():
		var take = section.takes[index]
		if bool(take.get("died", false)) or bool(take.get("invalid", false)):
			continue
		if int(take.get("target_id", section.id)) != int(section.get("target_id", section.id)):
			continue
		# Old input-only takes remain available, but an unverified legacy time
		# must not outrank a newly captured successful branch for this entry.
		var recorded = _recorded_take_matches_entry(section, take)
		if section.best < 0 or (recorded and not recorded_best) or (recorded == recorded_best and take.frames < section.takes[section.best].frames):
			section.best = index
			recorded_best = recorded


func _recorded_take_matches_entry(section: Dictionary, take: Dictionary) -> bool:
	var frames = take.get("recorded_frames")
	var entry = snap_for(int(section.start))
	if not frames is Array or frames.empty() or frames.size() != take.inputs.size() or entry == null:
		return false
	if not take.get("entry_snapshot") is Dictionary or not take.get("end_snapshot") is Dictionary:
		return false
	# Godot 3 Dictionary equality compares container identity, including after
	# duplicate(true). Compare the exact serialized state instead.
	if var2bytes(take.entry_snapshot) != var2bytes(entry):
		return false
	for frame in frames:
		if not _frame_ok(frame):
			return false
	return true


# A surviving replay is not proof that it reached the selected destination.
# Include the last swept step, so a dash can legitimately cross a thin box.
func _section_boundary_reached(index: int, target: int) -> bool:
	var section = sections[index]
	var zone = zone_for(sections[target])
	var before = position_at(int(section.end)-1)
	var terminal = snap_for(int(section.end))
	return zone is Rect2 and before is Vector2 and terminal is Dictionary and terminal.get("position") is Vector2 and enters_zone(zone, before, terminal.position)


func take_index(section: Dictionary, take_id: int) -> int:
	for index in section.takes.size():
		if int(section.takes[index].id) == take_id:
			return index
	return -1


func pin_take(section_index: int, take_id: int) -> void:
	var section = sections[section_index]
	var index = take_index(section, take_id)
	if index >= 0:
		section.takes[index].pinned = not section.takes[index].pinned
		touch()
		emit_signal("changed")


func _practice_restart() -> void:
	if practice.empty():
		return
	var section = sections[practice.section]
	if not instant_seek(section.start, false, false, true):
		practice = {}
		message = "Couldn't restore the section start. Open the sections menu and replay to its start."
		emit_signal("changed")
		return
	practice.ending = false
	practice.last_at = null
	practice.inside = -1
	var player = tool._get_local_player()
	var at = player.body.global_position if player.body != null else player.position
	practice.armed = not practice.zone.has_point(at)
	if tool._is_paused:
		tool._toggle_pause()
	emit_signal("changed")


# Start the attempt again without counting it.
func retry_practice() -> void:
	if practice.empty() or practice.get("ending", false):
		return
	practice.ending = true
	call_deferred("_practice_restart")


func stop_practice() -> void:
	if practice.empty():
		return
	var index = int(practice.get("section",-1))
	practice = {}
	var game = tool._find_game()
	if game != null and game.is_server() and not game.is_game_over() and index >= 0 and index < sections.size() and source_revision == int(tool._practice_data_revision):
		instant_seek(sections[index].start, true, false)
	else:
		# Clear/Load already replaced the source. Never resurrect its old run.
		sync()
	message = ""
	emit_signal("changed")


# Explicit Clear abandons live callbacks without applying their old snapshots.
# Keep spatial goals and takes; the cleared run has no completed spans.
func recording_cleared() -> void:
	var was_job = not job.empty()
	cancel_practice_request()
	practice = {}
	job = {}
	pending_restore = {}
	optimiser = {}
	segment_pending_start = false
	segment_commit = -1
	segment_commit_target = -1
	segment_next = -1
	segment_original = {}
	if bots != null:
		bots.task = {}
		bots.candidate = {}
	hold_render = false
	_release_inputs()
	_restore_render()
	if was_job and not tool._is_paused:
		Engine.time_scale = tool._saved_time_scale
	full = []
	bounds = [0]
	snaps = []
	cursor = 0
	verified = 0
	end_snap = {}
	end_snap_frame = -1
	source_revision = int(tool._practice_data_revision)
	markers = {}
	undo_stack.clear()
	loaded_slot = 0
	for section in sections:
		section.done = false
		section.start = -1
		section.end = -1
		section.used = 0
		section.erase("skipped_by")
	if is_instance_valid(window):
		window.waiting_finish = false
		window.open_pending = false
		window.bar.visible = false
	touch()
	emit_signal("changed")


# Put a take into the run. One undo puts the old inputs (and section) back.
func use_take(section_index: int, take_id: int) -> void:
	var section = sections[section_index]
	var index = take_index(section, take_id)
	if index < 0:
		return
	var take = section.takes[index]
	var first = section.start
	replace_frames(first, section.end, take.inputs)
	section = sections[section_index]
	section.end = first + take.inputs.size()
	section.used = take.id
	replay_to(section.end)


# ---------------------------------------------------------------- marking

# Spatial stop boxes can be placed before any complete recording exists.
# They describe goals only; a segment still begins at a native recorded state.
func add_stop_box(zone: Rect2, source := "manual") -> int:
	if zone.size.x < 8.0 or zone.size.y < 8.0 or sections.size() >= 256:
		return -1
	var section = {"start": -1, "end": -1, "zone": zone, "guide": 0, "base": 0, "source": source, "done": false}
	_fill_section(section)
	section.name = "Section %d" % (sections.size() + 1)
	sections.append(section)
	touch()
	emit_signal("changed")
	return sections.size() - 1


func _native_box(node) -> Rect2:
	var at = node.global_transform.xform(Vector2(0, -70))
	return Rect2(at - Vector2(80, 80), Vector2(160, 160))


# Map landmarks are suggestions, not a claimed solved route. The user can
# move/remove/reorder them and aim at later boxes when a shortcut is faster.
func make_map_boxes() -> int:
	var game = tool._find_game()
	if game == null or not game.is_server() or game.level == null or tool._tool_restricted():
		return 0
	var checkpoints = game.level.get_nodes_of_type(LevelNodeFactory.checkpoint_key).duplicate()
	var finishes = game.level.get_finish_lines()
	if finishes.empty():
		message = "No map finish found. Draw stop boxes in freecam."
		return 0
	sections = []
	var player = tool._get_local_player()
	var at = player.body.global_position if player != null and player.body != null else Vector2.ZERO
	while not checkpoints.empty() and sections.size() < 255:
		var nearest = 0
		for index in range(1, checkpoints.size()):
			if at.distance_squared_to(checkpoints[index].global_position) < at.distance_squared_to(checkpoints[nearest].global_position):
				nearest = index
		var node = checkpoints[nearest]
		checkpoints.remove(nearest)
		add_stop_box(_native_box(node), "map")
		at = node.global_position
	var nearest_finish = finishes[0]
	for node in finishes:
		if at.distance_squared_to(node.global_position) < at.distance_squared_to(nearest_finish.global_position):
			nearest_finish = node
	add_stop_box(_native_box(nearest_finish), "finish")
	message = "Boxes suggested from map checkpoints and finish. Edit them in freecam."
	return sections.size()


func edit_stop_boxes() -> bool:
	if not job.empty() or is_instance_valid(zone_editor) or (bots != null and bots.busy()) or tool._practice_playback or (is_instance_valid(replay_boxes) and (replay_boxes.pending or replay_boxes.browser_owned)):
		message = "Finish the current action before previewing boxes"
		return false
	var game = tool._find_game()
	if game == null or not game.is_server() or tool._tool_restricted():
		message = "Open a solo level to place stop boxes"
		emit_signal("changed")
		return false
	cancel_practice_request()
	segment_pending_start = false
	stop_practice()
	_leave_timeline_preview()
	if not tool._begin_macro_editor_preview():
		return false
	zone_editor = load(get_script().resource_path.get_base_dir().plus_file("TASSectionZones.gd")).new()
	get_tree().root.add_child(zone_editor)
	zone_editor.setup(self)
	if is_instance_valid(window):
		window.panel.hide()
		window.bar.hide()
	return true


# Recorded passages near a world point: [{frame, distance}], one per visit.
func passages_near(point: Vector2, radius := 48.0) -> Array:
	var result = []
	var current = null
	for index in min(verified + 1, full.size()):
		var state = full[index].get(STATE_KEY) if typeof(full[index]) == TYPE_DICTIONARY else null
		if typeof(state) != TYPE_DICTIONARY or not state.has("position"):
			continue
		var distance = state.position.distance_to(point)
		if distance <= radius:
			if current == null or index - current.last > 2:
				current = {"frame": index, "distance": distance, "last": index}
				result.append(current)
			elif distance < current.distance:
				current.frame = index
				current.distance = distance
			current.last = index
	return result


func start_marking() -> void:
	mark_mode = 1
	mark_first = -1
	message = "Click where the section starts"
	emit_signal("changed")


func mark_frame(frame_index: int) -> void:
	if mark_mode == 1:
		mark_first = frame_index
		mark_mode = 2
		message = "Now click where it ends"
	elif mark_mode == 2:
		mark_mode = 0
		var first = min(mark_first, frame_index)
		var last = max(mark_first, frame_index)
		message = ""
		if last - first >= 4 and window != null and is_instance_valid(window):
			window.on_track_drag(first, last)
	emit_signal("changed")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	var viewport = get_viewport()
	if viewport == null:
		return
	var point = viewport.canvas_transform.affine_inverse().xform(event.position)
	if mark_mode != 0:
		var found = passages_near(point)
		if found.empty():
			message = "No recorded path there -- click on the route"
			emit_signal("changed")
		elif found.size() == 1 or window == null or not is_instance_valid(window):
			mark_frame(found[0].frame)
		else:
			window.pick_passage(found)
		viewport.set_input_as_handled()
	elif bots != null and bots.pick_jump(point):
		viewport.set_input_as_handled()


# ---------------------------------------------------------------- route overlay

func show_route(value: bool) -> void:
	if not value:
		if route_node != null and is_instance_valid(route_node):
			route_node.queue_free()
		route_node = null
		return
	var player = tool._get_local_player()
	if player == null or player.get_parent() == null:
		return
	if route_node == null or not is_instance_valid(route_node):
		route_node = RouteLine.new()
		player.get_parent().add_child(route_node)
	refresh_route()


func refresh_route() -> void:
	if route_node == null or not is_instance_valid(route_node):
		return
	var points = PoolVector2Array()
	var speeds = PoolRealArray()
	for index in min(verified + 1, full.size()):
		var state = full[index].get(STATE_KEY) if typeof(full[index]) == TYPE_DICTIONARY else null
		if typeof(state) != TYPE_DICTIONARY or not state.has("position"):
			continue
		points.append(state["position"])
		speeds.append(state.get("linear_velocity", Vector2.ZERO).length())
	route_node.points = points
	route_node.speeds = speeds
	route_node.update()


class RouteLine extends Node2D:
	var points = PoolVector2Array()
	var speeds = PoolRealArray()

	func _ready() -> void:
		z_index = 3980

	func _draw() -> void:
		if points.size() < 2:
			return
		var top = 1.0
		for speed in speeds:
			top = max(top, speed)
		var colours = PoolColorArray()
		for speed in speeds:
			var t = clamp(speed / top, 0.0, 1.0)
			var colour = Color("6fb8ff").linear_interpolate(Color("7fe0b4"), min(t * 2.0, 1.0))
			if t > 0.5:
				colour = Color("7fe0b4").linear_interpolate(Color("ffc46b"), (t - 0.5) * 2.0)
			colours.append(Color(colour.r, colour.g, colour.b, 0.85))
		# Drawn in pieces: one huge polyline overflows the renderer's buffer.
		var piece = 256
		var first = 0
		while first < points.size() - 1:
			var last = min(first + piece, points.size() - 1)
			# The shipped Godot 3 packed arrays have no subarray method.
			var piece_points = PoolVector2Array()
			var piece_colours = PoolColorArray()
			for index in range(first, last + 1):
				piece_points.append(points[index])
				piece_colours.append(colours[index])
			draw_polyline_colors(piece_points, piece_colours, 4.0, true)
			first = last
		for index in range(0, points.size(), 60):
			draw_circle(points[index], 4.0, Color(1, 1, 1, 0.8))


# Frames behind (+) / ahead (-) of the reference along this run, sampled every
# `step` frames: [[frame, delta], ...].
func compare_curve(step := 4) -> Array:
	var result = []
	if reference.empty():
		return result
	var points: PoolVector2Array = reference.points
	var last_match = 0
	for index in range(0, min(verified + 1, full.size()), step):
		var state = full[index].get(STATE_KEY) if typeof(full[index]) == TYPE_DICTIONARY else null
		if typeof(state) != TYPE_DICTIONARY or not state.has("position"):
			continue
		var best = -1
		var best_distance = 96.0
		for other in range(max(0, last_match - 120), min(points.size(), index + 600)):
			var distance = points[other].distance_to(state["position"])
			if distance < best_distance:
				best_distance = distance
				best = other
		if best >= 0:
			last_match = best
			result.append([index, index - best])
	return result


# ---------------------------------------------------------------- segmented run

func first_open_segment() -> int:
	for index in sections.size():
		if not bool(sections[index].get("done", false)):
			return index
	return -1


func _bind_open_segment_start() -> bool:
	if not segmented:
		return false
	var index = first_open_segment()
	if index < 0:
		return false
	if int(sections[index].start) >= 0:
		return true
	# Replacing/reordering boxes does not create entry states. The first open
	# goal starts at the actual kept prefix boundary, or checkpoint 0 when no
	# section has been kept. Old saves with start=-1 are repaired on demand.
	var boundary = 0
	for previous in range(index):
		var section = sections[previous]
		if bool(section.get("done",false)) and not section.has("skipped_by") and int(section.end) >= 0:
			boundary = int(section.end)
	if snap_for(boundary) == null:
		return false
	sections[index].start = boundary
	touch()
	return true


# Turn the current run's sections into guide boxes.
func make_guide() -> int:
	if sections.empty():
		make_sections()
	var has_replay_guide = false
	for section in sections:
		if section.get("source","")=="leaderboard":
			has_replay_guide = true
			continue # Foreign route times are guidance, never native save states.
		if not section.get("zone") is Rect2:
			section["zone"] = zone_for(section)
		section["start_pos"] = position_at(int(section.start))
		var snap = snap_for(int(section.end))
		section["motion"] = snap.get("linear_velocity", Vector2.ZERO) if snap != null else Vector2.ZERO
		section["guide"] = max(0, int(section.end) - int(section.start))
		section["base"] = section.guide
	var previous_guide = guide_points
	guide_points = PoolVector2Array()
	var step = int(max(1, ceil(min(verified + 1, full.size()) / 800.0)))
	for index in range(0, min(verified + 1, full.size()), step):
		var state = full[index].get(STATE_KEY) if typeof(full[index]) == TYPE_DICTIONARY else null
		if typeof(state) == TYPE_DICTIONARY and state.has("position"):
			guide_points.append(state.position)
	if has_replay_guide:
		guide_points = previous_guide
	var usable = 0
	for section in sections:
		if section.zone is Rect2:
			usable += 1
	return usable


# Restart the level and start a new recording; the boxes stay.
func start_segmented(backup_saved := false) -> bool:
	workflow_mode = "sections"
	SavedSettings.set_value("tas_workflow_mode",workflow_mode)
	if busy() or (bots != null and bots.busy()):
		return false
	var game = tool._find_game()
	if game==null or not game.is_server() or tool._tool_restricted() or tool._practice_playback:
		message = "Open a solo level to start recording sections"
		emit_signal("changed")
		return false
	_leave_timeline_preview()
	if not backup_saved and records!=null and not records.save_before_restart(records.capture_restart_data()):
		message = "Couldn't back up the previous run. Recording has not been restarted."
		emit_signal("changed")
		return false
	if make_guide() == 0:
		message = "Draw stop boxes in freecam, or record a route first"
		emit_signal("changed")
		return false
	segmented = true
	loaded_slot = 0
	for section in sections:
		section.done = false
		section.erase("skipped_by")
		section["target_id"] = int(section.id)
		section.start = -1
		section.end = -1
		section.takes = []
		section.best = -1
		section.attempts = 0
		section.clears = 0
		section.streak = 0
		section.used = 0
	sections[0].start = 0
	undo_stack.clear()
	if tool._practice_active or tool._practice_start_waiting:
		tool._on_toggle_practice_pressed(true)
	tool._on_toggle_practice_pressed(true)
	segment_pending_start = true
	message = "Starting a new run..."
	touch()
	emit_signal("changed")
	return true


# All user-facing record actions in Sections mode use the same native
# countdown path. Merely opening the section menu never starts a recording.
func start_section_recording(backup_saved := false) -> bool:
	if not start_segmented(backup_saved): return false
	var ui = _window()
	ui.opening = 0
	ui.open_pending = false
	ui.waiting_finish = false
	ui.panel.hide()
	ui.bar.show()
	ui.visible = true
	ui.bar_labels.section.text = "Waiting for the level countdown"
	for key in ["try","run","best","last"]: ui.bar_labels[key].text = ""
	tool._set_menu_open(false)
	return true


# Wait for the restarted level's recording to begin, then start segment 1.
func _watch_segment_start() -> void:
	if not tool._practice_active or tool._practice_start_waiting or tool._practice_checkpoints.empty():
		return
	if ready_for_studio() != "":
		return
	segment_pending_start = false
	full = []
	cursor = 0
	verified = 0
	sync()
	message = ""
	if window != null and is_instance_valid(window):
		window.start_segment(0)


# Keep the best try of segment `index`. Native captures retain their actual
# endpoint; legacy input-only takes must replay and reach the chosen box.
func commit_segment(index: int) -> bool:
	if index < 0 or index >= sections.size():
		return false
	var section = sections[index]
	if section.best < 0:
		message = "Reach the stop block at least once first"
		emit_signal("changed")
		return false
	segment_original = snapshot_project()
	segment_commit = index # set first: the window waits on it
	segment_commit_target = target_for(index)
	if not practice.empty():
		stop_practice()
	sync()
	var take = section.takes[section.best]
	var start = int(section.start)
	var use_recorded = _recorded_take_matches_entry(section, take)
	var old_end = int(section.end) if bool(section.get("done", false)) else full.size()
	if bool(section.get("done", false)):
		# Replacing an already built span must remove the intervening inputs,
		# not append the old skipped sections after the new shortcut.
		var destination = sections[segment_commit_target]
		var destination_end = int(destination.end)
		if destination.has("skipped_by"):
			var keeper = section_index_for_id(int(destination.skipped_by))
			if keeper >= 0:
				destination_end = int(sections[keeper].end)
		old_end = destination_end if destination_end >= start else full.size()
	replace_frames(start, old_end, take.inputs)
	section = sections[index]
	section.start = start # replace_frames shifts sections that start at the edit
	section.end = start + take.inputs.size()
	section.done = true
	section.used = take.id
	segment_commit = index
	if use_recorded:
		# These frames were already produced by the native engine, from this
		# exact entry, up to the first arrival. Preserve their physics samples.
		for offset in take.recorded_frames.size():
			full[start+offset] = take.recorded_frames[offset]
		verified = int(section.end)
		end_snap = take.end_snapshot
		end_snap_frame = int(section.end)
		_segment_committed()
		return bool(sections[index].get("done",false)) and int(sections[index].used) == int(take.id) and _section_boundary_reached(index,target_for(index))
	if not replay_to(full.size()):
		segment_commit = -1
		segment_commit_target = -1
		var original = segment_original
		segment_original = {}
		restore_project(original)
		message = "Couldn't play the run back"
		emit_signal("changed")
		return false
	return true


func _segment_committed() -> void:
	var index = segment_commit
	var target = max(index, segment_commit_target)
	segment_commit = -1
	segment_commit_target = -1
	var kept = sections[index]
	if int(kept.end) > verified or not _section_boundary_reached(index, target):
		# The kept try itself didn't play back (it should; it was recorded
		# from this exact start). Leave it open.
		segment_next = -1
		var original = segment_original
		segment_original = {}
		if not original.empty():
			restore_project(original)
		else:
			kept.done = false
		# Do not repeatedly select the same unproven input-only reconstruction.
		var used = int(kept.used)
		var rejected = take_index(sections[index], used)
		if rejected >= 0:
			sections[index].takes[rejected]["invalid"] = true
			_pick_best(sections[index])
		message = "That take did not reach its stop box during validation. Run unchanged; practise this section again."
		tool._show_responsive_popup("TAKE NOT KEPT",message)
		emit_signal("changed")
		return
	segment_original = {}
	# Later segments kept earlier stay only if they still reach their box.
	var next_start = int(kept.end)
	var cut = -1
	for skipped in range(index + 1, min(target + 1, sections.size())):
		sections[skipped]["done"] = true
		sections[skipped]["skipped_by"] = int(kept.id)
		sections[skipped].start = -1
		sections[skipped].end = -1
	for later in range(target + 1, sections.size()):
		var section = sections[later]
		if not bool(section.get("done", false)) or cut >= 0:
			section.done = false
			section.start = next_start if cut < 0 else -1
			section.end = -1
			if cut < 0:
				cut = later
			continue
		section.start = next_start
		var at = position_at(int(section.end))
		if int(section.end) > verified or at == null or not (section.zone is Rect2 and section.zone.grow(24.0).has_point(at)):
			section.done = false
			section.end = -1
			cut = later
			continue
		next_start = int(section.end)
	if cut >= 0 and int(sections[cut].start) < full.size():
		full = _range(full, 0, int(sections[cut].start))
		verified = min(verified, full.size())
	segment_next = first_open_segment()
	touch()
	instant_seek(full.size(), true, false)
	message = "Segment %d kept" % (index + 1) if segment_next >= 0 else "All segments done -- save the run"
	emit_signal("changed")


func segment_totals() -> Dictionary:
	var done = 0
	var ahead = 0
	for section in sections:
		if bool(section.get("done", false)):
			done += 1
			ahead += int(section.get("guide", 0)) - (0 if section.has("skipped_by") else int(section.end) - int(section.start))
	return {"done": done, "ahead": ahead}


# Data stored with a saved run so the sections, tries and progress come back
# when it is loaded again.
func project_for_slot() -> Dictionary:
	var kept = []
	for section in sections:
		var copy = section.duplicate(true)
		copy.erase("broken")
		kept.append(copy)
	return {"version": 1, "segmented": segmented, "workflow_mode": workflow_mode, "sections": kept, "markers": markers.keys(), "next_id": next_id, "guide_points": guide_points}


func load_saved_project(project: Dictionary, slot: int) -> void:
	if not project.get("sections") is Array:
		return
	sync()
	segmented = bool(project.get("segmented", false))
	_restore_workflow_mode(project)
	sections = project.sections.duplicate(true)
	for section in sections:
		_fill_section(section)
	normalize_section_order()
	markers = {}
	for key in project.get("markers", []):
		markers[int(key)] = true
	next_id = max(next_id, int(project.get("next_id", 1)))
	guide_points = project.get("guide_points", PoolVector2Array())
	loaded_slot = slot
	if segmented:
		var broken = -1
		for index in sections.size():
			var section = sections[index]
			# An old file may legitimately omit its terminal. Reopen only an
			# end that can be disproved by its actual saved native samples.
			var known_end = snap_for(int(section.end)) != null and position_at(int(section.end)-1) is Vector2
			if broken < 0 and known_end and bool(section.get("done",false)) and not section.has("skipped_by") and not _section_boundary_reached(index,target_for(index)):
				broken = index
			if broken >= 0:
				section.done = false
				section.erase("skipped_by")
				if index > broken:
					section.start = -1
					section.end = -1
		if broken >= 0:
			message = "Section %d was saved before reaching its stop box. Practise it again; your takes are kept." % (broken+1)
	undo_stack.clear()
	touch()
	if window != null and is_instance_valid(window):
		window.project_loaded()
	emit_signal("changed")


# Save the run built so far (with its sections and tries) to a Macro Slot.
func play_run() -> bool:
	if busy() or (bots != null and bots.busy()):
		return false
	var game = tool._find_game()
	if game == null or not game.is_server() or tool._tool_restricted() or game.is_game_over():
		message = "Open an unfinished solo level to play the run"
		return false
	_leave_timeline_preview()
	sync()
	if full.empty() or snaps.empty():
		message = "Nothing recorded yet"
		return false
	# End-of-file is not an internal checkpoint join. Playback can use an
	# exact recorded start without inventing an unavailable terminal state.
	var data = _working_macro_data()
	if tool._tas_run_options().needs_resimulation(data.segments):
		message = "Check edited inputs before playback"
		return false
	if not tool._install_editor_data_as_current(data):
		return false
	tool._on_play_practice_macro_pressed()
	return tool._practice_playback


func _working_macro_data() -> Dictionary:
	var checkpoints = []
	if not snaps.empty():
		checkpoints.append(snaps[0])
	if not full.empty():
		var terminal = snap_for(full.size())
		if terminal != null:
			checkpoints.append(terminal)
	return {"format_version":3,"checkpoints":checkpoints,"segments":[] if full.empty() else [full.duplicate()],"studio_project":project_for_slot()}


func can_save() -> bool:
	return job.empty() and (not full.empty() or not sections.empty())


func save_run() -> String:
	if not job.empty():
		return "Wait for the current job to finish"
	sync()
	if full.empty() and sections.empty():
		return "Nothing to save yet"
	var end = full.size()
	var slot = loaded_slot
	if slot <= 0 or slot > int(tool._practice_macro_slot_count):
		slot = 0
		for candidate in range(1, int(tool._practice_macro_slot_count) + 1):
			if not tool._practice_macro_slots.has(candidate):
				slot = candidate
				break
		if slot == 0:
			tool._on_add_practice_macro_slot_pressed()
			slot = int(tool._practice_macro_slot_count)
			if tool._practice_macro_slots.has(slot):
				return "No free Macro Slot"
	var context = tool._capture_current_time_trial_level_context()
	var name = str(context.get("level_name", "Run"))
	if name.empty():
		name = "Section project" if full.empty() else "Run"
	if tool._practice_macro_slots.has(slot):
		name = str(tool._practice_macro_slots[slot].get("name", name))
	elif segmented:
		name += " (segmented)"
	var data = _working_macro_data()
	data.name = name
	data.level_context = context
	if not tool._write_practice_macro_slot_to_disk(slot,data):
		return "Save failed. The previous file is unchanged; check free space and folder access."
	tool._practice_macro_slots[slot] = data
	tool._refresh_practice_macro_slot_ui(slot)
	loaded_slot = slot
	var progress = ""
	if segmented:
		var completed = 0
		for section in sections:
			if bool(section.get("done",false)) or section.has("skipped_by"):
				completed += 1
		progress = " · %d/%d sections" % [completed,sections.size()]
	return "Saved to Macro Slot %d (%s)%s" % [slot, "goals and takes" if end == 0 else "%.2fs" % (end / 60.0), progress]

func _restore_workflow_mode(data: Dictionary):
	message = ""
	var stored_sections = data.get("sections",[])
	var fallback = "sections" if segmented or (stored_sections is Array and not stored_sections.empty()) else "checkpoints"
	workflow_mode = str(data.get("workflow_mode",fallback))
	if not workflow_mode in ["checkpoints","sections"]: workflow_mode = fallback
	SavedSettings.set_value("tas_workflow_mode",workflow_mode)
