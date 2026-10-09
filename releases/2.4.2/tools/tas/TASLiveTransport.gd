extends Reference

# Transient live-attempt history. Never reads/writes a saved slot. Seeking uses
# the EXISTING native macro player (including its world phase and join restores),
# not a interpolated pose or a different physics engine.
var history = {}
var game_id = 0
var seeking = false
var cursor = 0
var held_direction = 0
var resume_speed = 1.0
var pending_checkpoint = -1
var restart_frame = 0
var restart_checkpoint = 0
var batch_blocked = false
var step_seed = {}
var step_needs_restore = false
var owner_ref = null
var status = null
var shortcut_buttons = {}

func clear_unless_seeking() -> void:
	if seeking: return
	_release()
	step_seed.clear()
	step_needs_restore = false
	batch_blocked = false
	history.clear()
	game_id = 0
	cursor = 0
	pending_checkpoint = -1
	held_direction = 0

func on_new_input() -> void:
	if seeking: return
	# First new tick after a rewind creates a new branch; old future is no
	# longer offered as redo. The working macro keeps its entire prefix.
	history.clear()

func seek(owner, delta_ticks: int) -> bool:
	if seeking and not owner._practice_playback and owner._practice_continue_frame < 0:
		cancel()
	var game = owner._find_game()
	var player = owner._get_local_player()
	if seeking or game == null or not game.is_server() or owner._tool_restricted() or not owner.enabled or not owner._practice_active or owner._practice_playback or owner._macro_editor_preview_active or owner._practice_awaiting_native_respawn or player == null or not player.alive:
		return false
	if not owner._is_paused:
		owner._toggle_pause()
	resume_speed = owner._saved_time_scale
	if not owner._ensure_practice_native_tick_hooks(game): return false
	var current = owner._practice_recorded_frame_count() + owner._practice_current_segment.size()
	if history.empty() or game_id != game.get_instance_id():
		history = {"segments": owner._practice_segments.duplicate(true), "checkpoints": owner._practice_checkpoints.duplicate(true)}
		if history.checkpoints.empty(): return false
		if not owner._practice_current_segment.empty():
			history.segments.append(owner._practice_current_segment.duplicate(true))
			history.checkpoints.append(owner._snapshot_player(player))
		game_id = game.get_instance_id()
	var total = 0
	for segment in history.segments:
		for frame in segment:
			if not bool(frame.get(owner.PRACTICE_FRAME_STATE_KEY, {}).get("native_tick_clock", false)) or bool(frame.get("__tas_input_unverified", false)):
				owner._set_status("Live rewind needs native-tick frames with unedited inputs. Working replay unchanged.")
				return false
		total += segment.size()
	var target = int(clamp(current + delta_ticks, 0, total))
	if target == current:
		if delta_ticks > 0 and current == total:
			# Beyond recorded history, advance the actual native controller with
			# current/buffered inputs, then return to pause. No invented frames.
			var previous_enabled = owner.enable_frame_step
			owner.enable_frame_step = true
			var previous_count = owner.frame_step_count
			owner.frame_step_count = min(delta_ticks, owner.FRAME_STEP_COUNT_MAX)
			owner._request_frame_step()
			owner.frame_step_count = previous_count
			owner.enable_frame_step = previous_enabled
			return true
		return false
	seeking = true
	cursor = target
	if not owner._install_editor_data_as_current(history):
		seeking = false
		return false
	if target == 0:
		owner._restore_player(player, history.checkpoints[0])
		for marker in owner._practice_markers:
			if is_instance_valid(marker): marker.queue_free()
		owner._practice_markers.clear()
		owner._practice_markers.append(owner._spawn_checkpoint_marker(player, history.checkpoints[0].position))
		owner._practice_segments.clear()
		owner._practice_checkpoints = [history.checkpoints[0].duplicate(true)]
		owner._practice_active = true
		owner._practice_prev_alive = player.alive
		finish_seek(owner)
		return true
	owner._on_play_practice_macro_pressed()
	if not owner._practice_playback:
		seeking = false
		return false
	owner._practice_continue_frame = target
	owner._practice_continue_auto_resume = false
	# Re-simulate only from the nearest saved native/world checkpoint BEFORE
	# the target. Long TAS attempts must not restart from frame zero per click.
	var boundary = 0
	for i in range(history.segments.size()):
		if boundary < target and i < history.checkpoints.size(): pending_checkpoint = i
		if boundary + history.segments[i].size() >= target: break
		boundary += history.segments[i].size()
	owner._practice_playback_index = boundary
	restart_frame = boundary
	restart_checkpoint = pending_checkpoint
	if target - boundary <= 16: Engine.time_scale = 0.15
	if status != null and is_instance_valid(status): status.text = "Seeking frame %d…" % target
	return true

func arm_frame_step(owner) -> void:
	step_seed = owner._snapshot_player(owner._get_local_player()) if owner._practice_active and owner._get_local_player() != null else {}
	step_needs_restore = false

func begin_batch(owner, ticks: int) -> void:
	batch_blocked = false
	if ticks <= 0: return
	if seeking:
		var remaining = owner._practice_continue_frame - owner._practice_playback_index
		if remaining > 0 and ticks > remaining:
			# A render delta may have been latched at the OLD speed before the
			# UI requested this seek. Drain it BEFORE restoring/replaying; never
			# land at a cursor inside an already precomputed multi-tick batch.
			batch_blocked = true
			owner._practice_playback_index = restart_frame
			pending_checkpoint = restart_checkpoint
			Engine.time_scale = 0.05
	elif owner._pending_frame_step and not step_seed.empty():
		if ticks > owner._tas_run_options().native_step_remaining:
			batch_blocked = true
			step_needs_restore = true
			Engine.time_scale = 0.05
		else:
			if step_needs_restore:
				owner._restore_player(owner._get_local_player(), step_seed)
				for action in owner._injected_actions_held:
					owner._inject_action(action, false)
					owner._inject_action(action, true)
			step_seed.clear()


func prime_seek(owner) -> void:
	if not seeking or pending_checkpoint < 0: return
	var index = pending_checkpoint
	pending_checkpoint = -1
	owner._restore_player(owner._get_local_player(), history.checkpoints[index])
	owner._practice_playback_pending_start = false
	owner._practice_playback_settled_boundary = index

func finish_seek(owner) -> void:
	if not seeking: return
	seeking = false
	# Slow cursor approach is pacing only; resume at the user's prior speed.
	owner._saved_time_scale = resume_speed
	if status != null and is_instance_valid(status): status.text = "Paused · frame %d" % cursor
	owner._set_status("Live TAS paused at frame %d · saved replay unchanged" % cursor)

func cancel() -> void:
	seeking = false
	clear_unless_seeking()

func build_controls(owner, parent: VBoxContainer) -> void:
	owner_ref = weakref(owner)
	shortcut_buttons.clear()
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	parent.add_child(row)
	for entry in [["◀◀ Rewind", -30], ["◀ 1 frame", -1], ["1 frame ▶", 1], ["Forward ▶▶", 30]]:
		var button = owner._make_button(entry[0], owner.COLOR_BLUE, 0)
		button.align = Button.ALIGN_CENTER
		button.hint_tooltip = "Local live TAS only. Replays native ticks, then pauses. Hold the double-arrow buttons to repeat; recording new input starts a new branch."
		if abs(entry[1]) > 1:
			button.connect("button_down", self, "_hold", [entry[1]])
			button.connect("button_up", self, "_release")
		else:
			button.connect("pressed", self, "_pressed", [entry[1]])
			shortcut_buttons["tas_rewind" if entry[1] < 0 else "tas_forward"] = button
		row.add_child(button)
	refresh_shortcuts(owner)
	status = owner._make_label("Live TAS · pause to inspect, step to refine", owner._small_font, owner.COLOR_TEXT_DIM)
	parent.add_child(status)

func refresh_shortcuts(owner) -> void:
	for id in shortcut_buttons:
		var button = shortcut_buttons[id]
		if not is_instance_valid(button): continue
		var caption = owner._keybinds.caption(id) if owner._keybinds != null else "Unbound"
		button.hint_tooltip = "Local live TAS only. Move one native frame, then pause. Shortcut: %s. Change in Settings → Keybinds." % caption

func _pressed(delta_ticks: int) -> void:
	var owner = owner_ref.get_ref() if owner_ref != null else null
	if owner != null: seek(owner, delta_ticks)

func _hold(direction: int) -> void:
	held_direction = direction
	_pressed(direction)
	# Use the menu's idle callback for wall-time repetition; timers stop at
	# time_scale=0. This signal is disconnected when the menu is destroyed.
	var owner = owner_ref.get_ref()
	if not owner.get_tree().is_connected("idle_frame", self, "_repeat"):
		owner.get_tree().connect("idle_frame", self, "_repeat")
	_last_repeat = OS.get_ticks_msec()

var _last_repeat = 0
func _repeat() -> void:
	if held_direction == 0 or seeking or OS.get_ticks_msec() - _last_repeat < 250: return
	var owner = owner_ref.get_ref()
	if owner == null or not is_instance_valid(status) or not status.is_visible_in_tree():
		_release()
		return
	_last_repeat = OS.get_ticks_msec()
	_pressed(held_direction)

func _release() -> void:
	held_direction = 0
	var owner = owner_ref.get_ref() if owner_ref != null else null
	if owner != null and owner.get_tree().is_connected("idle_frame", self, "_repeat"):
		owner.get_tree().disconnect("idle_frame", self, "_repeat")
