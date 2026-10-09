extends "user://mod/tools/tas/TASTool/25_macro_bot_2.gd"

# THE SIXTEENTH-PASS FIX (2026-08-31) -- at the user's explicit request after
# item 8 turned up a genuine, unfixable-from-GDScript race condition between
# this file's input injection and the native tick driver's own read of it
# (see item 8's comment, and THE FIFTEENTH-PASS FIX's comment above): rather
# than keep chasing that race's timing indefinitely, Macro Bot Mode playback
# now computes horizontal (left/right) velocity itself, in pure GDScript,
# and assigns it to player.linear_velocity.x directly every tick -- bypassing
# GooberDash's native input-to-movement conversion, and the race against it,
# for that one axis entirely. Gravity, jump, dash, landing, and all
# collision are untouched and still fully native -- this whole investigation
# has never once found a divergence in any of those systems, only in
# horizontal movement's timing, so there's no reason to touch them.
#   Originally GROUNDED only (this pass's first ship). THE SEVENTEENTH-PASS
# FIX (2026-08-31, later the same day) extended this to AIRBORNE horizontal
# movement too, using real engine constants but a guessed combining formula.
# THE NINETEENTH-PASS FIX (2026-08-31, later again) replaced that guess with
# the actual decompiled airborne formula -- see PLAYBACK_AIR_ACCEL_MAX's own
# comment for the full mechanism and how it was recovered.
#   Scope notes that still apply to BOTH branches:
#   - Only while a direction is actively HELD (move != 0.0), for the
#     ACCELERATION step -- release/friction back to a stop past that point
#     has never been reverse-engineered on the ground, so grounded release
#     is left to native physics untouched, same as always. Airborne release
#     is a partial exception as of THE NINETEENTH-PASS FIX: the real
#     friction-decay step applies unconditionally while airborne regardless
#     of whether a direction is held, but this function still only runs at
#     all while move != 0.0 (see the early-return below), so a release
#     still hands off to native immediately, same as grounded.
#   - A direction REVERSAL while GROUNDED and still holding (the other way)
#     is handled by THE EIGHTEENTH-PASS FIX's dedicated braking branch --
#     see PLAYBACK_GROUND_BRAKE_LAMBDA's own comment for the real-data
#     evidence behind it (real friction constant, not a guess, though the
#     exact crossover-through-zero moment is still an engineering estimate).
#     An AIRBORNE reversal has no dedicated branch -- the real decompiled
#     airborne formula doesn't appear to need one (the ramped-accel step
#     just points at the new signed target every tick, and the counter
#     driving the ramp resets on a direction change per
#     _practice_playback_air_hold_ticks' own comment), but this hasn't been
#     separately checked against a real airborne-reversal recording either.
#   One real risk this can't be checked from a stub project alone: whether
# directly assigning player.linear_velocity.x here actually survives the
# native tick driver's own pass afterward, or gets silently overwritten by
# it (WPGame.local_pre_tick() reads the continuous-input array and calls
# add_input_event() unconditionally, every tick, regardless of whether
# anything changed -- see item 8 -- and it's not visible from GDScript
# whether that path ever independently recomputes linear_velocity.x itself
# downstream of that, since the actual movement math is fully native). If
# the very next real Divergence Diagnostics report on a simple grounded
# hold (re-running test 1's exact scenario is the cleanest check) still
# shows a horizontal divergence, that's the answer, and it means this
# needs a different hook point, not just a formula tweak.
func _apply_practice_playback_computed_horizontal_velocity(player: WPPlayer, at_fresh_boundary: bool) -> void:
	# Consume the latest collision-resolved (or restored) velocity, never the
	# previous estimate. Otherwise a wall/saw impact is undone on the next tick.
	_practice_playback_computed_vx = player.linear_velocity.x
	if not player.alive or player.dash_timer > 0.0:
		return
	if at_fresh_boundary:
		# A checkpoint/segment boundary just restored a snapshot velocity
		# this function must not stomp on the very tick it lands. Stay
		# caught up so the next tick picks up from the real restored speed,
		# and don't touch the airborne-tick counter either -- the restore
		# already set it to whatever the checkpoint snapshot itself held
		# (see THE TWENTY-FIRST-PASS FIX), which is exactly right under
		# THE TWENTY-SEVENTH-PASS FIX's model too (see below): it's just a
		# ticks-airborne clock, and the checkpoint's own value already
		# reflects however long the player had been airborne at that
		# instant, regardless of what was or wasn't held at the time.
		_practice_playback_computed_vx = player.linear_velocity.x
		return
	var tick_rate: = 1.0 / Engine.iterations_per_second
	var grounded: = player.stick_to_ground_timer > 0.0
	# THE TWENTY-SEVENTH-PASS FIX (2026-08-31, later still) -- a real
	# Divergence Diagnostics report (a midair LEFT press well into a long
	# fall) showed a small but real, steadily-growing horizontal velocity
	# divergence starting the tick the press took effect: replay was
	# consistently ~0.95-0.98% too strong every tick. Working the actual
	# recorded live velocities backwards through THE NINETEENTH-PASS FIX's
	# own formula (accel_mag = MAX + (MIN-MAX)*ratio, ratio = hold_ticks /
	# (DURATION * physics_fps)) recovers the exact per-tick accel_mag the
	# real game used -- and its tick-over-tick SLOPE matches the formula's
	# constants exactly (confirming MAX/MIN/DURATION were always right),
	# but its STARTING VALUE only lines up if the real hold-ticks counter
	# was already at ~30 the moment the press first took effect -- even
	# though the player had been holding no direction at all for at least
	# the preceding 27 ticks of straight fall. That's the two-flags mystery
	# THE NINETEENTH-PASS FIX's own comment flagged as never fully traced:
	# the real counter isn't "ticks holding the same direction" (this
	# file's guess, reset on release/direction-change) -- it's ticks spent
	# CONTINUOUSLY AIRBORNE, full stop, counting the whole time you're in
	# the air whether or not any direction is held, and reset only by
	# landing. The ramped-acceleration STEP is still correctly gated on
	# holding a direction (nothing changes there) -- it's only the clock
	# feeding its ratio that was wrongly tied to input at all. Approximated
	# here as "increment every tick this function runs while airborne,
	# reset to 0 the moment `grounded` reads true" -- runs unconditionally
	# now, ahead of the move==0 early-return below, so a no-input airborne
	# stretch keeps the clock running exactly like the real game's does.
	#   `_practice_playback_air_hold_dir` is no longer used to gate
	# anything as of this pass (direction never resets or gates the
	# counter now) -- left in place, still captured/restored by checkpoint
	# snapshots for backward format compatibility, but purely vestigial
	# for the ramp itself now.
	if grounded:
		_practice_playback_air_hold_ticks = 0
	else:
		_practice_playback_air_hold_ticks += 1
	var move: float = sign(Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT))
	if move == 0.0:
		# No direction held this tick -- out of scope for this pass (see
		# the big comment above _apply_practice_playback_computed_horizontal_velocity's
		# very first big comment). Stay caught up here too. The airborne
		# clock above keeps running regardless -- it's no longer reset by a
		# release, only by landing (THE TWENTY-SEVENTH-PASS FIX).
		_practice_playback_computed_vx = player.linear_velocity.x
		return
	if grounded:
		# THE SIXTEENTH-PASS FIX's original grounded model: flat linear
		# acceleration toward a hard cap, no drag term -- test 1's real
		# data showed zero measurable decay over 5 ticks when accelerating
		# from rest or continuing the same direction, so there's nothing
		# to model there beyond accelerate-then-clamp. THE NINETEENTH-PASS
		# FIX's decompile confirmed this is exactly right (see item 12).
		#   THE EIGHTEENTH-PASS FIX added a decay branch for when the held
		# direction OPPOSES the current velocity's sign. THE TWENTIETH-PASS
		# FIX confirmed that model from the actual decompiled code (no
		# hidden "combined" formula after all -- see PLAYBACK_GROUND_
		# OVERCAP_LAMBDA's comment) and added the one real case it was
		# missing: decaying back down to the cap when current speed is
		# already ABOVE it while still holding the same direction (speed
		# carried in from something other than this file's own accel
		# model, e.g. a dash or wall jump). Both cases share the same
		# decay-with-exact-snap shape, just a different target/lambda.
		var current_sign: = sign(_practice_playback_computed_vx)
		var opposing: = current_sign != 0.0 and current_sign != move
		var over_cap: = not opposing and abs(_practice_playback_computed_vx) > PLAYBACK_GROUND_MAX_SPEED
		if opposing or over_cap:
			var target: = 0.0 if opposing else (move * PLAYBACK_GROUND_MAX_SPEED)
			var lambda: = PLAYBACK_GROUND_BRAKE_LAMBDA if opposing else PLAYBACK_GROUND_OVERCAP_LAMBDA
			var decayed: = target + (_practice_playback_computed_vx - target) * exp(-lambda * tick_rate)
			# Real decompiled behavior: snap EXACTLY to the target once
			# within PLAYBACK_GROUND_BRAKE_CROSSOVER_EPSILON of it, rather
			# than leaving a fractional residual to decay away forever.
			if abs(decayed - target) < PLAYBACK_GROUND_BRAKE_CROSSOVER_EPSILON:
				decayed = target
			_practice_playback_computed_vx = decayed
		else:
			var target: = move * PLAYBACK_GROUND_MAX_SPEED
			if _practice_playback_computed_vx < target:
				_practice_playback_computed_vx = min(_practice_playback_computed_vx + PLAYBACK_GROUND_ACCEL * tick_rate, target)
			elif _practice_playback_computed_vx > target:
				_practice_playback_computed_vx = max(_practice_playback_computed_vx - PLAYBACK_GROUND_ACCEL * tick_rate, target)
	else:
		# THE NINETEENTH-PASS FIX's airborne model -- the actual decompiled
		# formula (see PLAYBACK_AIR_ACCEL_MAX's own comment for how this was
		# recovered and the full reasoning), applied as two discrete steps
		# every airborne tick, in this order. The counter itself is now
		# maintained unconditionally above (THE TWENTY-SEVENTH-PASS FIX) --
		# nothing left to do with it here except read its current value.
		# Step 1: friction decay, same exponential shape as the grounded
		# braking branch, using the real player_air_friction_lambda.
		_practice_playback_computed_vx *= exp(-PLAYBACK_AIR_FRICTION_LAMBDA * tick_rate)
		# Step 2: ramped acceleration -- linearly interpolates the
		# acceleration MAGNITUDE from PLAYBACK_AIR_ACCEL_MAX down to
		# PLAYBACK_AIR_ACCEL_MIN as the same-direction airborne hold
		# approaches PLAYBACK_AIR_ACCEL_DURATION seconds, then holds at
		# the minimum past that (ratio clamped to 1.0).
		var duration_ticks: = PLAYBACK_AIR_ACCEL_DURATION * Engine.iterations_per_second
		var ratio: = clamp(_practice_playback_air_hold_ticks / duration_ticks, 0.0, 1.0)
		var accel_mag: = PLAYBACK_AIR_ACCEL_MAX + (PLAYBACK_AIR_ACCEL_MIN - PLAYBACK_AIR_ACCEL_MAX) * ratio
		_practice_playback_computed_vx += move * accel_mag * tick_rate
		# Hard-clamp to the real cap -- numerically identical to the
		# decompiled "scale back this tick's increment so it lands exactly
		# on the cap" approach for a constant per-tick accel (same
		# reasoning as the grounded branch's clamp, see the big comment
		# above this function).
		_practice_playback_computed_vx = clamp(_practice_playback_computed_vx, -PLAYBACK_AIR_MAX_SPEED, PLAYBACK_AIR_MAX_SPEED)
	player.linear_velocity.x = _practice_playback_computed_vx


func _macro_level_is_current(data: Dictionary) -> bool:
	var wanted_id := _macro_slot_level_id(data)
	if wanted_id.empty():
		return false
	var scene := get_tree().current_scene
	if scene == null or not ("parameters" in scene):
		return false
	var parameters = scene.get("parameters")
	return parameters != null and ("level_id" in parameters) and str(parameters.get("level_id")) == wanted_id


func _reset_saved_macro_autoplay_state() -> void:
	_saved_macro_continue_slot = 0
	_saved_macro_autoplay_slot = 0
	_saved_macro_autoplay_level_id = ""
	_saved_macro_autoplay_source_game_id = 0
	_saved_macro_autoplay_elapsed = 0.0
	_saved_macro_autoplay_ready_ticks = 0
	_saved_macro_autoedit_slot = 0
	_saved_macro_editor_visual_signature = ""


func _cancel_saved_macro_autoplay(message: String) -> void:
	_reset_saved_macro_autoplay_state()
	_log_action(message, null)
	_refresh_practice_ui()


func _on_continue_saved_macro_pressed(slot: int) -> void:
	if not _practice_macro_slots.has(slot):
		return
	if _saved_macro_autoplay_slot > 0:
		_log_action("Wait for the pending level launch to finish first.",null)
		return
	if _macro_editor_preview_active:
		if is_instance_valid(_macro_editor):
			_macro_editor.close_editor()
		else:
			_end_macro_editor_preview()
	_saved_macro_autoedit_slot = 0
	var current_game = _find_game()
	if current_game != null and current_game.is_server() and not _tool_restricted():
		var data = _practice_macro_slots[slot]
		var count = 0
		for segment in data.get("segments", []):
			count += segment.size()
		_continue_macro_editor_data(data, count - 1, true)
		return
	_on_play_saved_practice_macro_slot_pressed(slot)
	if _saved_macro_autoplay_slot == slot:
		_saved_macro_continue_slot = slot


func _watch_saved_macro_autoplay(delta: float) -> void:
	if _saved_macro_autoplay_slot <= 0:
		return
	_saved_macro_autoplay_elapsed += delta
	if _saved_macro_autoplay_elapsed > SAVED_MACRO_AUTOPLAY_TIMEOUT_SECONDS:
		_cancel_saved_macro_autoplay("Saved Macro Bot playback timed out while waiting for the level to become playable")
		return

	var scene: = get_tree().current_scene
	if scene == null or not ("parameters" in scene):
		return
	var parameters = scene.get("parameters")
	if parameters == null or not ("level_id" in parameters):
		return
	if str(parameters.get("level_id")) != _saved_macro_autoplay_level_id:
		return
	var game: = _find_game()
	if game == null or not scene.is_a_parent_of(game):
		return
	if _saved_macro_autoplay_source_game_id != 0 and game.get_instance_id() == _saved_macro_autoplay_source_game_id:
		return
	if not _game_ready_for_practice_start():
		_saved_macro_autoplay_ready_ticks = 0
		_saved_macro_editor_visual_signature = ""
		return
	var player: = _get_local_player()
	if player == null or not _player_ready_for_checkpoint(player):
		_saved_macro_autoplay_ready_ticks = 0
		_saved_macro_editor_visual_signature = ""
		return
	var waiting_for_editor_visuals: bool = _saved_macro_autoedit_slot == _saved_macro_autoplay_slot
	if waiting_for_editor_visuals and not _macro_editor_level_visuals_ready(game):
		_saved_macro_autoplay_ready_ticks = 0
		_saved_macro_editor_visual_signature = ""
		return
	if waiting_for_editor_visuals:
		# Level deserialization is synchronous, but several renderer/decor nodes
		# join the tree during following idle passes. Wait until both the loaded
		# level and renderer trees stop changing instead of sleeping for an
		# arbitrary 45 ticks and hoping every machine is finished by then.
		var visual_signature := _macro_editor_visual_signature(game)
		if visual_signature.empty() or visual_signature != _saved_macro_editor_visual_signature:
			_saved_macro_editor_visual_signature = visual_signature
			_saved_macro_autoplay_ready_ticks = 0
			return

	var slot: = _saved_macro_autoplay_slot
	if not _practice_macro_slots.has(slot):
		_cancel_saved_macro_autoplay("Saved Macro Bot slot disappeared while its level was opening")
		return
	var data: Dictionary = _practice_macro_slots[slot]
	var target_play_time: = 0.0
	var saved_checkpoints: Array = data.get("checkpoints", [])
	if not saved_checkpoints.empty() and typeof(saved_checkpoints[0]) == TYPE_DICTIONARY:
		target_play_time = max(0.0, float(saved_checkpoints[0].get("play_time", 0.0)))
	var current_play_time: = float(game.wp_game_data.play_time)
	var physics_tick: = 1.0 / max(1.0, float(Engine.iterations_per_second))
	if current_play_time + physics_tick * 0.25 < target_play_time:
		_saved_macro_autoplay_ready_ticks = 0
		return
	_saved_macro_autoplay_ready_ticks += 1
	var required_ready_ticks := PRACTICE_READY_STABLE_TICKS_REQUIRED
	if _saved_macro_autoplay_ready_ticks < required_ready_ticks:
		return

	# Clear the pending launch before calling the ordinary Play handler so a
	# failure cannot repeatedly re-enter it on every following physics tick.
	var open_editor_after_load := _saved_macro_autoedit_slot == slot
	var continue_after_load: bool = _saved_macro_continue_slot == slot
	_reset_saved_macro_autoplay_state()
	if continue_after_load:
		var count = 0
		for segment in data.get("segments",[]):
			count += segment.size()
		if not _continue_macro_editor_data(data,count-1,true):
			_log_action("Continue From End could not start this recording. Saved replay unchanged.",null)
		return
	if open_editor_after_load:
		_saved_macro_autoedit_slot = 0
		if _macro_editor == null or not is_instance_valid(_macro_editor):
			_log_action("Macro Timeline Editor failed to load after opening the level", null)
			return
		_log_action("Opened the linked level for Macro Slot %d editing" % slot, null)
		_macro_editor.call("open_editor", slot, data)
		_update_mouse_capture()
		return
	if not _install_practice_macro_slot_data(slot, player, false):
		_log_action("Couldn't load Macro Bot Slot %d after opening its level" % slot, null)
		_refresh_practice_ui()
		return
	_log_action("Macro Bot Slot %d level is ready at %.3fs (recorded start %.3fs) -- starting automatically" % [slot, current_play_time, target_play_time], null)
	_on_play_practice_macro_pressed()


# Synthesizes a real action press/release via Input.parse_input_event() --
# the same mechanism this game's OWN touch-screen buttons use to drive
# gameplay (see goodoh/ui/components/TouchableButton.gd /
# InputActionOnPress.gd, which do exactly this for player_up/left/right/
# dash), so the native player controller -- which reads these through
# Input.get_action_strength()/is_action_pressed()/is_action_just_pressed(),
# confirmed verbatim in project_specific/GameInput.gd -- can't tell an
# injected press from a real one, on ANY of the physical keys/joypad
# buttons/touch controls this game's InputMap actually binds to that action
# (see the ACTION_* constants above for why recording raw keycodes instead
# of actions was the real reason macros used to reproduce none of what was
# actually done). Used by Buffered Inputs (step feature) and Perfect
# Jumpzone mode, as well as Macro Bot Mode recording/playback below.
# Godot updates Input's tracked action state synchronously when this is
# called, so a step's physics tick(s) immediately after see it as held.
func _inject_action(action: String, pressed: bool) -> void:
	var ev: = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)
	# parse_input_event() alone only QUEUES the event -- Godot normally
	# flushes queued input once per frame, but that timing isn't
	# guaranteed to land before the very next physics tick (the one a
	# frame-step is about to run). Flushing explicitly makes the new
	# action state take effect immediately instead of a frame late.
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


# Safety net so an action TASTool synthetically pressed can never stay stuck
# held once the tool is disabled or becomes restricted (e.g. you were mid
# frame-step or had Perfect Jumpzone armed and then joined a live match).
func _release_all_injected_actions() -> void:
	_continue_resimulating = false
	_practice_continue_frame = -1
	_practice_continue_auto_resume = false
	for action in _injected_actions_held:
		_inject_action(action, false)
	_injected_actions_held.clear()
	_release_practice_playback_injected_input()
	_stop_jumpzone_key()
	if _practice_playback:
		_practice_playback = false
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1
		_practice_playback_frames = []
		_log_action("Macro Bot Mode: playback aborted (tool became inactive/restricted)", null)
		_refresh_practice_ui()


func _is_recording() -> bool:
	var g: = _find_game()
	if g == null:
		return false
	return g.get_replay_status() != NetworkGame.REPLAY_STATUS_NONE
