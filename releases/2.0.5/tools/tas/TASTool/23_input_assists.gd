extends "user://mod/tools/tas/TASTool/22_checkpoints_2.gd"

func _on_toggle_buffered_action_pressed(action: String) -> void:
	var armed: bool = not _buffered_actions.get(action, false)
	_buffered_actions[action] = armed
	var btn: Button = _buffer_action_buttons.get(action)
	if btn != null:
		_style_button(btn, COLOR_PINK if armed else COLOR_BLUE)


# Arms Macro Bot Mode the instant you enter a level (checkpoint 0 = your
# starting position) instead of you having to click Start by hand every run.
func _watch_practice_auto_activate() -> void:
	# _find_game() first, unconditionally -- it's the thing that notices a
	# fresh game instance and resets _practice_auto_activate_was_pre /
	# _practice_auto_activate_checked_state_for_game (see _find_game()
	# above). Checking those before calling it would make this function's
	# correctness depend on _find_game() having already been called
	# elsewhere earlier in the same frame (it usually has, via
	# _tool_restricted(), but not when only_active_in_debug_or_solo is off
	# or this is a debug build) -- calling it here first makes this
	# function correct on its own regardless of that.
	var g: = _find_game()
	if not _practice_auto_activate:
		_practice_auto_activate_waiting_for_alive = false
		return
	if _practice_playback:
		# NEVER auto-(re)start while a stitched Play Macro run is actually in
		# progress. _start_practice_mode() wipes _practice_checkpoints down
		# to a single fresh entry, but _advance_practice_playback() is still
		# mid-flight referencing the OLD macro's checkpoint boundary indices
		# (_practice_playback_checkpoint_at) into that now-tiny array --
		# every tick past the first old boundary then indexes past the end
		# of _practice_checkpoints and errors out, permanently, freezing
		# playback at that frame with no visible sign of what happened. This
		# is exactly what made Play Macro (stitched) look completely dead
		# with Auto-Activate armed: gameplay_state reading LEVEL_PRE again
		# for any reason mid-run (a multi-round transition, a native
		# game-instance reference change, etc.) mid-playback used to stomp
		# it. Just don't fire at all while playback owns practice state --
		# it'll get another chance once this run naturally finishes.
		return
	if _practice_auto_activate_waiting_for_alive:
		# LEVEL_PRE was already seen for this game instance (below) -- a fresh
		# attempt is underway and just needs to wait for the player to
		# actually be ready before checkpoint 0 gets snapshotted.
		#   THE FIX (2026-08-30, fourth pass): the wait-until-ready check and
		# the _start_practice_mode() call it leads to used to both live right
		# HERE, in this idle-frame function -- but capturing checkpoint 0
		# needs the SAME physics-tick footing _watch_practice_start_request()
		# now gives the manual Start button, for exactly the same reason (see
		# the big comment on _on_toggle_practice_pressed()): an idle-frame
		# read of alive/body_enabled can disagree with what the very next
		# physics tick actually records as tick 0, and a checkpoint 0
		# snapshotted "ready" against a stale read is just as silently
		# corrupting as one snapshotted flat-out disabled. So this function
		# now only does what it's actually suited for -- edge-detecting a
		# fresh attempt on an idle frame is harmless, no player state is read
		# or written here -- and hands the wait-for-ready-and-fire part off
		# to _watch_practice_start_request(), the one physics-tick-driven
		# place that now owns it for both Auto-Activate and the manual
		# button. This var stays true until that function's own check
		# succeeds and clears _practice_start_waiting; nothing here needs to
		# poll readiness itself anymore.
		if not _practice_start_waiting:
			_practice_start_waiting = true
			_practice_start_reason = " (auto-activated on level entry)"
		return
	if g == null or g.wp_game_data == null:
		return
	if not ("gameplay_state" in g.wp_game_data):
		return
	var is_pre: bool = g.wp_game_data.gameplay_state == WPGameData.GameplayState_LEVEL_PRE
	# Level-editor test-play (scenes/TestGameplayScene.gd, confirmed
	# verbatim) skips LEVEL_PRE entirely on its very first entry -- it sets
	# gameplay_state straight to LEVEL_PLAY ("if is_level_editor: ...
	# gameplay_state = GameplayState_LEVEL_PLAY"), unlike every other way
	# into a level, which always passes through LEVEL_PRE first. Its own
	# Retry button, though, calls WPGame._reset_players_with_reset_time()
	# (also confirmed verbatim), which DOES set gameplay_state = LEVEL_PRE
	# same as normal -- so it's only that very first entry that has no PRE
	# edge to ever detect. Treat the first gameplay_state this function ever
	# observes for a level-editor game instance as an equivalent trigger,
	# same as seeing LEVEL_PRE would be.
	var editor_first_entry_skip: bool = not _practice_auto_activate_checked_state_for_game and is_pre == false and ("is_level_editor" in g.wp_game_data) and g.wp_game_data.is_level_editor
	_practice_auto_activate_checked_state_for_game = true
	# Edge-triggered on is_pre (fires when it turns true, not for as long as
	# it STAYS true) rather than "once ever per game instance" -- this
	# matters because testing a level from the level editor's own Retry
	# button resets state on the SAME WPGame instance instead of reloading
	# the scene (a real Time Trial's Retry button, by contrast, calls
	# reload_scene() and gets a genuinely new instance, which _find_game()
	# already detects and resets everything for on its own). Firing only
	# once per game instance meant every retry after the first, IN THE
	# EDITOR SPECIFICALLY, left Macro Bot Mode holding checkpoints/segments
	# from whatever you did on a PREVIOUS attempt at the same level --
	# exactly the kind of mismatch that shows up as "fails on the first
	# jump" for no visible reason on a later attempt, since the checkpoint-0
	# restore and the segment recorded against it can end up from two
	# different attempts entirely.
	var is_new_attempt: bool = (is_pre and not _practice_auto_activate_was_pre) or editor_first_entry_skip
	_practice_auto_activate_was_pre = is_pre
	if is_new_attempt:
		# Don't snapshot checkpoint 0 here -- confirmed in WPGame.gd's own
		# round-start code, LEVEL_PRE's whole countdown runs with
		# player.alive FORCED false ("player.alive = false; player.dead_counter
		# = time_to_ticks(_compute_time_until_preplay_spawn(player))" fires
		# at exactly this gameplay_state). Starting immediately here would
		# capture a checkpoint 0 that's already dead, and the very next Play
		# Macro would then restore that dead state as its first action and
		# report "died mid-macro (frame 0)" -- which looks impossible
		# because it is: nothing about your run caused it, the macro was
		# already dead before a single recorded frame of input ever played
		# back. Wait for the player to actually be alive (gameplay truly
		# starting) before capturing anything. (The level-editor's own
		# first-entry skip already has the player alive immediately, so
		# this wait resolves on literally the next tick in that case.)
		_practice_auto_activate_waiting_for_alive = true


# ----------------------------------------------------------------------
#  Perfect Jumpzone mode -- auto-presses ACTION_JUMP on a fixed rhythm for as
#  long as it's armed. Uses the `delta` passed into _process(), which Godot
#  already scales by Engine.time_scale, so the rhythm slows/speeds along
#  with the rest of the tool's slowdown controls instead of staying locked
#  to real wall-clock time -- e.g. at 0.5x the presses land every 500ms of
#  real time but still every 250ms of game time, so timing stays correct
#  relative to the level while you practice slowed down.
#
#  NOTE on jumpzone_hold_ms ("the fullest extent of a jump"): the player's
#  actual jump-height/hold physics live in the native (compiled) player
#  controller, not in any GDScript this tool can read, so this hold
#  duration is a starting default (200ms of a 250ms cycle), not something
#  verified against the native jump code. Use the Configure row to tune it
#  against what you actually see in-game -- interval and hold are
#  independent so you can dial in your own level's rhythm.
# ----------------------------------------------------------------------
func _start_jumpzone_cycle() -> void:
	_jumpzone_cycle_timer = 0.0
	_inject_action(ACTION_JUMP, true)
	_jumpzone_key_held = true


func _stop_jumpzone_key() -> void:
	if _jumpzone_key_held:
		_inject_action(ACTION_JUMP, false)
		_jumpzone_key_held = false


func _watch_jumpzone(delta: float) -> void:
	if not _jumpzone_armed:
		return
	_jumpzone_cycle_timer += delta
	var hold_sec: = jumpzone_hold_ms / 1000.0
	var interval_sec: = jumpzone_interval_ms / 1000.0
	if _jumpzone_key_held and _jumpzone_cycle_timer >= hold_sec:
		_stop_jumpzone_key()
	if _jumpzone_cycle_timer >= interval_sec:
		_start_jumpzone_cycle()


func _on_toggle_jumpzone_pressed() -> void:
	_jumpzone_armed = not _jumpzone_armed
	_style_button(_jumpzone_button, COLOR_PINK if _jumpzone_armed else COLOR_BLUE)
	_jumpzone_button.text = "⤒ Perfect Jumpzone: ON" if _jumpzone_armed else "⤒ Perfect Jumpzone: OFF"
	if _jumpzone_armed:
		_start_jumpzone_cycle()
		_log_action("Perfect Jumpzone: ON -- pressing Jump every %.0fms (held %.0fms)" % [jumpzone_interval_ms, jumpzone_hold_ms], null)
	else:
		_stop_jumpzone_key()
		_log_action("Perfect Jumpzone: OFF", null)


func _on_toggle_jumpzone_config_pressed() -> void:
	_jumpzone_config_row.visible = not _jumpzone_config_row.visible


func _on_jumpzone_interval_delta_pressed(delta: float) -> void:
	jumpzone_interval_ms = clamp(jumpzone_interval_ms + delta, JUMPZONE_INTERVAL_MIN_MS, JUMPZONE_INTERVAL_MAX_MS)
	jumpzone_hold_ms = min(jumpzone_hold_ms, jumpzone_interval_ms - JUMPZONE_TIMING_STEP_MS)
	_jumpzone_interval_label.text = "%.0fms" % jumpzone_interval_ms
	_jumpzone_hold_label.text = "%.0fms" % jumpzone_hold_ms


func _on_jumpzone_hold_delta_pressed(delta: float) -> void:
	jumpzone_hold_ms = clamp(jumpzone_hold_ms + delta, JUMPZONE_HOLD_MIN_MS, jumpzone_interval_ms - JUMPZONE_TIMING_STEP_MS)
	_jumpzone_hold_label.text = "%.0fms" % jumpzone_hold_ms


# ----------------------------------------------------------------------
#  Macro Bot Mode (GD-style segment practice / macro splicing)
#  -- see the PRACTICE CHECKPOINTS block in the header doc-comment above.
# ----------------------------------------------------------------------
func _on_toggle_practice_pressed() -> void:
	if _practice_active or _practice_start_waiting:
		_practice_start_waiting = false
		_stop_practice_mode()
		return
	# THE FIX (2026-08-30, fourth pass): checkpoint 0's readiness check
	# (_player_ready_for_checkpoint()) and its snapshot (_snapshot_player())
	# used to both happen right here, synchronously, inside this idle-frame
	# Button "pressed" handler -- the exact same class of mistake
	# _on_play_practice_macro_pressed() made with ITS restore (see the big
	# comment there, and _watch_practice_start_request() below). This button
	# doesn't mutate the player the way that one did, so there's no doubled-
	# gravity artifact here -- but the READ of alive/body_enabled this button
	# used to do was still one idle frame removed from _physics_process()'s
	# own read of that same player on the very next physics tick, which is
	# what actually becomes tick 0 of the recorded log. A real divergence
	# report caught the two disagreeing: this button's idle-frame check found
	# the player ready and let Start through, snapshotting checkpoint 0 as
	# alive=true/body_enabled=true, yet the FIRST tick _physics_process()
	# went on to actually record moments later read body_enabled=FALSE --
	# still genuinely inside the level's opening hold. That's precisely the
	# "still-disabled checkpoint" the big comment on _player_ready_for_checkpoint()
	# warns silently corrupts the whole replay from tick 0 on, and precisely
	# why this button's own idle-frame reading of that state can't be trusted
	# to make the call.
	#   The fix: don't check or snapshot anything from this idle-frame
	# handler at all. Just arm a wait, and let _watch_practice_start_request()
	# -- called from _physics_process(), every physics tick, the exact same
	# footing the recording loop right below it already stands on -- do the
	# actual readiness check and hand off to _start_practice_mode() the
	# instant it agrees, tick for tick, no gap. If the player's already
	# ready this fires on the very next physics tick (imperceptible); if not,
	# it just keeps waiting instead of making you keep re-clicking Start --
	# Auto-Activate always worked this way (see _watch_practice_auto_activate()
	# below), and this folds the manual button onto that exact same
	# physics-tick-driven wait instead of a second, idle-frame copy of it.
	_practice_start_waiting = true
	_practice_start_reason = ""
	_log_action("Macro Bot Mode: arming -- will start recording the instant you can actually move", null)
	_refresh_practice_ui()


# Called every physics tick from _physics_process() -- see the big comment
# on _on_toggle_practice_pressed() for why this can't run from an idle frame.
# Shared by both ways a start can get armed: the manual Start button above,
# and Auto-Activate's own fresh-level-entry edge-detect in
# _watch_practice_auto_activate() below (which only sets the wait flags;
# this is the one place that actually watches for ready and fires).
#
# THE SEVENTH-PASS FIX (2026-08-30): a Divergence Diagnostics report caught
# checkpoint 0 snapshotted as alive=true/body_enabled=true (correctly passing
# _player_ready_for_checkpoint()), yet the very NEXT tick of that same LIVE
# recording read body_enabled=FALSE again -- the level's own native logic
# re-disabling the body for several more ticks before real gameplay actually
# began. So the tick this fired on was only ready for exactly one tick, not
# genuinely, stably ready -- and a replay restoring to that snapshot has no
# way to reproduce whatever native, one-time event caused that second
# disable (it isn't in any field this tool captures), so it just keeps
# falling under gravity instead, which is precisely the doubled-velocity
# signature the fifth-pass fix's evidence showed. Requiring
# PRACTICE_READY_STABLE_TICKS_REQUIRED consecutive ready ticks before
# actually trusting "ready" and snapshotting means a transient one-tick
# flicker like that gets waited out instead of latched onto -- by the time
# the count reaches the threshold, whatever native transition was still
# settling has had a few extra ticks to finish for good.
func _watch_practice_start_request() -> void:
	if not _practice_start_waiting:
		_practice_ready_stable_ticks = 0
		return
	if _practice_playback:
		# Never start recording over an in-progress Play Macro run -- wait it
		# out rather than firing mid-playback (mirrors the exact same guard
		# _watch_practice_auto_activate() already had for this).
		_practice_ready_stable_ticks = 0
		return
	var player: = _get_local_player()
	if player == null or not _player_ready_for_checkpoint(player) or not _game_ready_for_practice_start():
		_practice_ready_stable_ticks = 0 # any not-ready tick resets the count -- see THE SEVENTH-PASS FIX above
		return # keep waiting, tick by tick -- nothing to check or snapshot yet
	_practice_ready_stable_ticks += 1
	if _practice_ready_stable_ticks < PRACTICE_READY_STABLE_TICKS_REQUIRED:
		return # looked ready this tick, but not for long enough yet -- keep waiting
	_practice_ready_stable_ticks = 0
	_practice_start_waiting = false
	_practice_auto_activate_waiting_for_alive = false # whichever path armed this, the wait is over now -- Auto-Activate re-arms its own on the next fresh-attempt edge (_watch_practice_auto_activate() above), it doesn't need to keep polling once this fires
	if _practice_active:
		# Already running (armed mid-attempt, or a leftover from before a
		# fresh level/attempt was detected) -- restart clean on top of a
		# genuinely new attempt rather than keeping stale checkpoints.
		_stop_practice_mode()
	_start_practice_mode(_practice_start_reason)


func _start_practice_mode(reason_suffix: String = "") -> void:
	var player: = _get_local_player()
	if player == null:
		_log_action("Macro Bot Mode: no local player found -- get into a level first", null)
		return
	if not _player_ready_for_checkpoint(player):
		# Same guard _on_place_practice_checkpoint_pressed() already has for
		# every OTHER checkpoint -- checkpoint 0 needs it too. Snapshotting a
		# dead player here means every future Play Macro restores that dead
		# state as its very first action and immediately reports "died
		# mid-macro (frame 0)", which looks impossible because it is: nothing
		# about the run caused it. Snapshotting a player who's alive but
		# still in the level's initial "wait a few seconds" hold
		# (body_enabled=false) is worse and less obvious -- see the big
		# comment on _player_ready_for_checkpoint() for why THAT one silently
		# corrupts the entire replay from tick 1 on instead of failing loudly.
		# (Auto-Activate has its own, separate wait for this -- see
		# _watch_practice_auto_activate() -- this covers the manual Start
		# button.)
		var why: String = "while dead -- wait until you respawn" if not player.alive else "until you can actually move -- you're still in the level's opening hold"
		_log_action("Macro Bot Mode: can't start %s, then press Start again" % [why], null)
		return
	if not _game_ready_for_practice_start():
		_log_action("Macro Bot Mode: can't start during the level-start handoff -- wait a moment, then press Start again", null)
		return
	_clear_practice_data()
	_practice_active = true
	_ensure_game_over_submission_guard_runs_first()
	_practice_prev_alive = player.alive
	var snap: = _snapshot_player(player)
	_practice_checkpoints.append(snap)
	_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	_restyle_practice_markers()
	_log_action("Macro Bot Mode: ON%s -- checkpoint 0 placed at your current position" % reason_suffix, null)
	_refresh_practice_ui()


func _stop_practice_mode() -> void:
	_continue_resimulating = false
	_practice_continue_frame = -1
	_practice_active = false
	_practice_awaiting_native_respawn = false # THE NINTH-PASS FIX -- don't leave a wait armed with nothing left watching it
	_log_action("Macro Bot Mode: OFF (%d checkpoint(s) kept -- Play/Save still work)" % [max(_practice_checkpoints.size() - 1, 0)], null)
	_refresh_practice_ui()


func _is_normal_linked_time_trial_scene(scene: Node) -> bool:
	if scene == null or not ("parameters" in scene):
		return false
	var parameters = scene.get("parameters")
	if parameters == null or not ("level_id" in parameters) or str(parameters.get("level_id")).empty():
		return false
	# TimeTrial (0) and ReplayGhost (1) are both playable/submit-capable race
	# modes. Watching a Replay (2) and a level's required PrepublishRun (3)
	# retain stock behavior.
	if not ("mode" in parameters):
		return false
	var mode: int = int(parameters.get("mode"))
	return mode == 0 or mode == 1


func _clear_practice_data() -> void:
	_practice_continue_frame = -1
	_continue_resimulating = false
	_continue_new_frames = []
	_continue_start_snapshot = {}
	for m in _practice_markers:
		if is_instance_valid(m):
			m.queue_free()
	_practice_markers.clear()
	_practice_checkpoints.clear()
	_practice_segments.clear()
	_practice_current_segment.clear()
	_diag_live_committed.clear()
	_diag_live_current.clear()
	_practice_deaths_this_segment = 0
	_practice_awaiting_native_respawn = false # THE NINTH-PASS FIX -- same reasoning as _stop_practice_mode(); a fresh checkpoint set shouldn't inherit a stale wait from before
	_practice_native_respawn_wait_ticks = 0
	# THE THIRTEENTH-PASS FIX -- fresh baseline and fresh counts for the new
	# recording session about to start; see _live_tick_last_play_time's big
	# comment.
	_live_tick_last_play_time = -1.0
	_live_tick_fingerprint_normal = 0
	_live_tick_fingerprint_phantom = 0
	_live_tick_fingerprint_backfilled = 0
	# THE TWENTY-SECOND-PASS FIX -- same reasoning, playback side; see
	# _playback_tick_last_play_time's big comment.
	_playback_tick_last_play_time = -1.0
	_playback_tick_fingerprint_normal = 0
	_playback_tick_fingerprint_phantom = 0
	_playback_tick_fingerprint_gap = 0
	# THE SIXTEENTH-PASS FIX -- same reasoning: a fresh recording session
	# shouldn't inherit a stale computed speed left over from whatever the
	# last Play Macro run was doing when it stopped.
	_practice_playback_computed_vx = 0.0
	_practice_playback_dash_held = false
	_practice_playback_dash_direction_valid = false
	# Do NOT clear _practice_playback_air_hold_ticks here. This function is
	# called immediately before checkpoint 0 is snapshotted, often midair;
	# clearing it would replace the native airborne phase just observed by
	# _update_practice_live_airborne_clock() with a fabricated zero.


func _on_clear_practice_pressed() -> void:
	_clear_practice_data()
	_practice_active = false
	_practice_start_waiting = false # cancel any in-flight "waiting to start" too -- Clear should leave nothing armed behind it
	_log_action("Macro Bot Mode: cleared", null)
	_refresh_practice_ui()


# Arms/disarms auto-activation -- does NOT itself start Macro Bot Mode; that
# only happens the next time _watch_practice_auto_activate() sees a fresh
# level start (see there). Toggling this on mid-level just arms it for the
# NEXT level entry, same as Auto-Record's own arm/disarm button behaves.
func _on_toggle_practice_auto_activate_pressed() -> void:
	_practice_auto_activate = not _practice_auto_activate
	if _practice_auto_activate:
		# Reset the edge-detection state so toggling this on mid-level can
		# fire right away if applicable: _was_pre=false means a level
		# that's ALREADY mid-LEVEL_PRE right now reads as a fresh rising
		# edge next check, and _checked_state_for_game=false re-arms the
		# level-editor first-entry-skip check too.
		_practice_auto_activate_was_pre = false
		_practice_auto_activate_checked_state_for_game = false
	_style_button(_practice_auto_activate_button, COLOR_PINK if _practice_auto_activate else COLOR_BLUE)
	_practice_auto_activate_button.text = "Auto-Activate on Level Entry: ON" if _practice_auto_activate else "Auto-Activate on Level Entry: OFF"
	_log_action("Macro Bot Mode: Auto-Activate on Level Entry %s" % ("ON" if _practice_auto_activate else "OFF"), null)


func _on_toggle_debug_mode_pressed() -> void:
	_set_debug_mode_enabled(not _debug_mode_enabled)


# Godot 3.5's Dictionary != isn't reliably documented as a deep content
# comparison across every build, so this compares key-by-key explicitly
# rather than trusting it -- input-mismatch detection is the one check here
# that actually points at a bug in Macro Bot Mode itself rather than native
# physics, so it's worth not getting this particular comparison wrong.
func _inputs_differ(live_input: Dictionary, replay_input: Dictionary) -> bool:
	if live_input.size() != replay_input.size():
		return true
	for key in live_input:
		if not replay_input.has(key) or replay_input[key] != live_input[key]:
			return true
	return false


func _on_toggle_stop_on_desync_pressed() -> void:
	_set_stop_on_desync_enabled(not _replay_check_stop_on_desync)


# ----------------------------------------------------------------------
#  Debug Noclip -- free flight for investigation only. Disables the
#  player's physics body outright (so nothing here fights the native
#  controller/Box2D) and drives position directly from raw input every
#  tick; toggling off hands control back exactly the way _restore_player()
#  does (a real _reset_object() call), so Box2D gets a clean handoff
#  either way rather than resuming mid-whatever-state noclip left it in.
#  Controls: left/right to move horizontally, Jump to rise, Dash to
#  descend (dash itself is inert while noclip is on -- there's nothing
#  else useful for a fourth direction, and this way no new input action
#  needs to be defined just for this debug tool).
# ----------------------------------------------------------------------
func _on_toggle_noclip_pressed() -> void:
	_noclip_enabled = not _noclip_enabled
	_style_button(_noclip_toggle_button, COLOR_PINK if _noclip_enabled else COLOR_BLUE)
	_noclip_toggle_button.text = "Debug Noclip: ON" if _noclip_enabled else "Debug Noclip: OFF"
	var player: = _get_local_player()
	if player == null:
		_log_action("Debug Noclip: %s (no local player found to apply it to yet)" % ["ON" if _noclip_enabled else "OFF"], null)
		return
	if _noclip_enabled:
		_noclip_prev_body_enabled = player.body_enabled
		player.body_enabled = false
		if player.body != null:
			player.body.enabled = false
			player.body.linear_velocity = Vector2.ZERO
		player.linear_velocity = Vector2.ZERO
	else:
		player.body_enabled = _noclip_prev_body_enabled
		if player.body != null:
			player.body.enabled = _noclip_prev_body_enabled
		player._reset_object()
	var recording_note: String = ""
	if _practice_active:
		# THE ELEVENTH-PASS FIX -- see the big comment in _physics_process()
		# on why noclip and macro recording can't both capture at once.
		recording_note = " -- Macro Bot Mode recording is PAUSED while this is on, resuming automatically once it's off again" if _noclip_enabled else " -- Macro Bot Mode recording has resumed"
	_log_action("Debug Noclip: %s%s" % ["ON" if _noclip_enabled else "OFF", recording_note], null)


# Called every physics tick from _physics_process() -- a no-op unless
# _noclip_enabled. Gated by _tool_restricted() same as everything else
# (see the call site), so it can never fly the player during a real
# competitive match.
func _apply_noclip_movement(delta: float) -> void:
	if not _noclip_enabled:
		return
	var player: = _get_local_player()
	if player == null:
		return
	if not player.alive:
		# Hazards (spikes, etc.) still kill the player even with the
		# physics body disabled -- turning body_enabled/body.enabled off
		# only stops Box2D collision, and hazard detection almost
		# certainly isn't routed through that (it looks like a separate
		# trigger, since noclip visibly doesn't stop it). Best-effort
		# recovery so noclip stays usable for exploring hazard-heavy
		# sections: revive immediately. This can't undo whatever the
		# native death sequence already fired for the one tick alive was
		# false (a sound, a camera shake, a respawn timer starting) --
		# this is a debug tool working around code it can't see inside of,
		# not a guarantee that hazards are truly inert while noclip is on.
		player.alive = true
		player.dead_counter = 0
	var move: = Vector2.ZERO
	if Input.is_action_pressed(ACTION_MOVE_RIGHT):
		move.x += 1.0
	if Input.is_action_pressed(ACTION_MOVE_LEFT):
		move.x -= 1.0
	if Input.is_action_pressed(ACTION_JUMP):
		move.y -= 1.0
	if Input.is_action_pressed(ACTION_DASH):
		move.y += 1.0
	if move != Vector2.ZERO:
		player.position += move.normalized() * NOCLIP_SPEED * delta


func _on_toggle_visual_seam_polish_pressed() -> void:
	_visual_seam_polish_enabled = not _visual_seam_polish_enabled
	SavedSettings.set_value(SETTING_VISUAL_SEAM_POLISH, _visual_seam_polish_enabled)
	if not _visual_seam_polish_enabled:
		_visual_seam_filter_remaining = 0.0
		_visual_seam_output_valid = false
	else:
		call_deferred("_show_native_notify", "VISUAL SEAM POLISH", "Visual Seam Polish only tweens the displayed goober for 120ms. Physics and replay inputs stay unchanged.\n\nUse open, safe checkpoint areas when possible: during the blend the sprite may briefly overlap nearby spikes or walls even though the real hitbox does not.")
	_log_action("Visual Seam Polish %s (render-only)" % ("ON" if _visual_seam_polish_enabled else "OFF"), null)
	_refresh_practice_ui()


func _on_toggle_sync_moving_objects_pressed() -> void:
	_sync_moving_objects_enabled = not _sync_moving_objects_enabled
	SavedSettings.set_value(SETTING_SYNC_MOVING_OBJECTS, _sync_moving_objects_enabled)
	if _sync_moving_objects_enabled:
		call_deferred("_show_native_notify", "MOVING OBJECT SYNC", "Moving-object snapshots will be recorded at new checkpoints and restored during local playback.\n\nExisting macros remain playable, but old slots cannot contain world snapshots that were never recorded.")
	_log_action("Moving Object Sync %s" % ("ON" if _sync_moving_objects_enabled else "OFF"), null)
	_refresh_practice_ui()
