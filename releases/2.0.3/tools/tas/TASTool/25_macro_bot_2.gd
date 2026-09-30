extends "user://mod/tools/tas/TASTool/24_macro_bot_1.gd"

func _advance_practice_playback() -> void:
	if _continue_resimulating:
		_advance_continue_resimulation()
		return
	var player: = _get_local_player()
	if player == null:
		_practice_playback = false
		Engine.time_scale = 1.0
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1
		_practice_playback_frames = []
		_log_action("Macro Bot Mode: playback stopped -- no local player found", null)
		_refresh_practice_ui()
		if _self_test_active:
			_self_test_active = false
			_log_action("Replay Self-Test: aborted -- no local player found.", null)
		return
	# HISTORICAL, SUPERSEDED: THE TWENTY-SECOND-PASS FIX (2026-08-31) -- see _playback_tick_last_play_time's
	# big comment. Confirm THIS call actually corresponds to a real, newly-
	# elapsed physics tick before doing anything else below -- restore,
	# settle, diag capture, input sync, all of it. A Godot engine catch-up
	# burst (multiple _physics_process() calls in one real frame after a
	# slow/dropped render frame) can call this function again with the
	# physics engine itself still frozen at time_scale=0 from THIS pass's
	# own single-step gating -- play_time genuinely hasn't moved, so
	# treating that call as "one confirmed tick" the way the code used to
	# would silently re-process/re-capture a tick that never happened.
	# Bail out completely on those -- no capture, no index advance, nothing
	# -- and let whichever LATER call finally corresponds to a real tick
	# pick up exactly where this one left off.
	#   THE TWENTY-FIFTH-PASS FIX (2026-08-31): that was only HALF of what a
	# catch-up burst can do. This pass's own reports (three back-to-back
	# real Play Macro attempts on the same difficult-level recording, all
	# 100% reproducible) proved the OTHER half: a burst can just as easily
	# land multiple REAL native ticks' worth of play_time advancement behind
	# a single call to this function, instead of zero. That's not a phantom
	# call -- the physics engine genuinely simulated every one of those
	# ticks, gravity and all -- so it can't just be skipped. But the old code
	# treated any playback_ticks_elapsed >= 1 identically ("proceed
	# normally"), which only ever consumes exactly ONE recorded frame's
	# worth of _practice_playback_index advancement at the bottom of this
	# function no matter how many real ticks actually elapsed. The reports
	# showed exactly this: tick 0 (the checkpoint-0 restore) matched live
	# exactly, then the very next captured frame -- meant to be "1 tick
	# since boundary" -- already carried the position/velocity live itself
	# only reached at ITS OWN tick 3. Three real ticks of falling had
	# already happened to the (correctly Box2D-simulated) player body before
	# this function's second call ever ran, but the bookkeeping below only
	# advanced as if one had. Left uncorrected this isn't a one-tick
	# blip -- it's a PERMANENT frame-index offset for the rest of the
	# replay, since every later call keeps consuming frames one at a time
	# starting from the now-wrong index.
	#   The fix: when more than one real tick elapsed, additionally advance
	# _practice_playback_index by the extra tick count (ticks_elapsed - 1)
	# BEFORE this call does its own boundary lookup / capture / advance --
	# see the "playback_gap_ticks" application further down, right before
	# the boundary-restore check. This mirrors, inverted, THE THIRTEENTH-
	# PASS FIX's recording-side backfill (which duplicates a frame to cover
	# a gap in what got RECORDED); here on playback the gap is in what got
	# CONSUMED, so the fix is to consume the extra frames as already-passed
	# rather than duplicate anything. Whatever happened physically during
	# those skipped ticks can't be retroactively re-witnessed (if an input
	# change landed exactly inside the gap, it lands a tick or two later
	# than live saw it -- an acknowledged, unavoidable limit of catching up
	# after the fact) -- but it stops the index from silently falling
	# further and further behind for the rest of the run, which is what was
	# actually turning one bad tick into total post-divergence cascade in
	# every affected report's per-field mismatch counts.
	#   Deliberately computed here but NOT applied to _practice_playback_index
	# until after the settling block below: a gap that happens to land on a
	# tick where playback is mid-settle (holding zero input, waiting for
	# Box2D to re-settle after a restore) must NOT consume recorded frames --
	# settling never spends frames by design (see its own big comment) --
	# so the catch-up is only ever applied on a call that actually reaches
	# the frame-consuming code path below.
	# SCHEDULER CORRECTION (2026-09-01): this function is called once from
	# each _physics_process callback, so this is already one fixed step. The
	# play_time sampled here belongs to WPGame and can still describe the
	# previous ordered node callback; using it to skip/fast-forward frames was
	# the source of the recurring tick-1/tick-2 divergence and early deaths.
	_playback_tick_fingerprint_normal += 1
	# True for exactly one tick per checkpoint boundary -- the tick that
	# boundary's restore (checkpoint 0's below, or boundary_idx>0's further
	# down) actually completed on, INCLUDING the tick settling for that
	# boundary finally ends on, if it armed settling at all. Drives the
	# capture-and-advance step at the bottom of this function -- see the big
	# comment there (THE FIFTH-PASS FIX) for why a fresh boundary's first
	# frame needs to be captured/primed/advanced on this SAME tick instead
	# of a tick later.
	var at_fresh_boundary: = false
	if _practice_playback_pending_start:
		# THE FIX (2026-08-30, third pass): this used to run synchronously
		# inside _on_play_practice_macro_pressed() -- a UI Button "pressed"-signal
		# handler, which fires on an IDLE frame, not a physics frame. Every OTHER
		# restore in this file (the boundary_idx > 0 branch right below, and the
		# checkpoint-editor restores) happens from inside a _physics_process()
		# call. That fix (moving the restore itself onto physics-tick footing)
		# is still correct and still here -- but it turned out to only be HALF
		# the story. See THE FIFTH-PASS FIX below, on the capture-and-advance
		# step at the bottom of this function, for the other half: even with
		# the restore itself correctly tick-aligned, checkpoint 0's diag
		# capture used to still happen a whole tick LATE relative to the
		# restore, which is what was actually still doubling a falling
		# checkpoint's velocity after this fix alone shipped.
		_practice_playback_pending_start = false
		_restore_player(player, _practice_checkpoints[0])
		_practice_playback_settled_boundary = 0
		_arm_playback_settle(player, _practice_checkpoints[0])
		if _practice_playback_settling:
			return
		at_fresh_boundary = true
	if not player.alive:
		if _recover_authoritative_playback_death(player):
			_practice_playback_state_corrections += 1
			_log_action("Macro Bot Mode: recovered unexpected replay death at frame %d/%d from its authoritative recorded state." % [_practice_playback_index, _practice_playback_frames.size()], null)
		else:
			_practice_playback = false
			Engine.time_scale = 1.0
			_practice_playback_settling = false
			_practice_playback_settled_boundary = -1
			_release_all_injected_actions()
			_log_action("Macro Bot Mode: playback stopped -- player died mid-macro (frame %d/%d). This legacy frame has no authoritative state to recover." % [_practice_playback_index, _practice_playback_frames.size()], null)
			# Legacy/input-only recordings have no safe target state. Keep their
			# failure report rather than guessing a position through a hazard.
			_auto_generate_playback_reports()
			_practice_playback_frames = []
			_refresh_practice_ui()
			if _self_test_active:
				_on_replay_self_test_run_finished(false, _practice_playback_index)
			return
	if _practice_playback_settling:
		# Holding on zero input -- see the big comment above _snapshot_is_at_rest().
		# Deliberately does NOT touch _practice_playback_index: the next
		# recorded frame hasn't been "spent" yet, only delayed. Ends on
		# whichever comes first: the position stabilizing (Box2D re-settled
		# already, no need to burn the rest of the hold) or the hard tick cap
		# (guarantees this can never hold forever even if position never
		# reads as fully stable).
		# THE FIFTEENTH-PASS FIX (2026-08-31): used to hold zero input via the
		# direct native setters (g_settle.set_local_continuous_input(...)) --
		# now just releases whatever Macro Bot Mode playback currently holds
		# synthetically pressed, same as everywhere else this pass touches
		# (see _release_practice_playback_injected_input()'s own comment).
		_release_practice_playback_injected_input()
		_practice_playback_settle_ticks_left -= 1
		var moved: = player.position.distance_to(_practice_playback_settle_last_position)
		_practice_playback_settle_last_position = player.position
		if moved < PLAYBACK_SETTLE_STABLE_EPSILON or _practice_playback_settle_ticks_left <= 0:
			_practice_playback_settling = false
			if not _restore_drift_watches.empty():
				var settled_watch: Dictionary = _restore_drift_watches.back()
				settled_watch["settle_ticks_used"] = PLAYBACK_SETTLE_MAX_TICKS - _practice_playback_settle_ticks_left
				settled_watch["settle_hit_cap"] = _practice_playback_settle_ticks_left <= 0 and moved >= PLAYBACK_SETTLE_STABLE_EPSILON
		# Deliberately does NOT return here anymore (fifth pass): if settling
		# just now ended, this tick needs to fall through to the boundary
		# check below so a boundary_idx==0 (checkpoint 0's own settle) can be
		# recognized as freshly-settled and go straight to capture-and-advance
		# THIS SAME tick, instead of costing yet another tick first the way
		# the old "settling ends -> return -> re-prime next tick -> capture
		# the tick after THAT" chain used to. A boundary_idx>0 restore's own
		# settle-ended tick already fell through to this same check before
		# this pass -- this just makes checkpoint 0 consistent with it. Still
		# returns like before while settling is still IN PROGRESS (moved >=
		# epsilon and ticks remain) -- only a settle that just concluded this
		# tick continues on.
		if _practice_playback_settling:
			return
	# THE TWENTY-FIFTH-PASS FIX (2026-08-31) -- see the big comment up top
	# where playback_gap_ticks is computed. Only reached on a call that's
	# actually about to consume a recorded frame (every settling-in-progress
	# call already returned above), so it's now safe to catch the index up
	# by however many extra real ticks this call absorbed, BEFORE the
	# boundary lookup right below (in case the gap itself crossed a segment
	# boundary) and before the finished-playback check further down.
	if not at_fresh_boundary:
		# Array.find() would only return the FIRST checkpoint whose boundary
		# lands on this frame index -- normally fine, since each committed
		# segment adds at least one frame and boundaries are strictly
		# increasing. But a checkpoint placed with NO input recorded since the
		# previous one (e.g. two checkpoints placed back-to-back, or a segment
		# that died and was re-attempted in literally zero frames) commits a
		# zero-length segment, which means its start and end checkpoint land on
		# the exact same frame index. When that happens we want the LATEST
		# checkpoint at that index -- the one the very next frame's input was
		# actually recorded against -- not the first/earlier one, or the restore
		# silently lands one checkpoint behind where playback is about to run,
		# which reads exactly like the macro "confusing itself with a different
		# checkpoint."
		var boundary_idx: = _find_last_checkpoint_boundary(_practice_playback_index)
		# The final checkpoint has no following segment to initialize. Processing
		# it after the last recorded frame would only create a visible end snap,
		# so a boundary transition is useful only while another frame remains.
		if boundary_idx > 0 and _practice_playback_index < _practice_playback_frames.size():
			if boundary_idx >= _practice_checkpoints.size():
				# Defense in depth: _practice_checkpoints and
				# _practice_playback_checkpoint_at are built together at the start
				# of a run and should stay in lockstep for its whole duration. The
				# Auto-Activate-mid-playback bug (guarded against above, in
				# _watch_practice_auto_activate()) used to violate that by wiping
				# _practice_checkpoints out from under an in-progress playback,
				# and this is what that corruption actually hit: indexing past
				# the end of the now-too-short array, which threw the same script
				# error over and over, every single tick, forever -- freezing the
				# player in place with no visible explanation of what happened.
				# That specific cause is fixed now, but if anything else ever
				# mutates _practice_checkpoints mid-run in the future, fail safe
				# here instead of repeating that failure mode.
				_practice_playback = false
				Engine.time_scale = 1.0
				_practice_playback_settling = false
				_practice_playback_settled_boundary = -1
				_release_all_injected_actions()
				_log_action("Macro Bot Mode: playback aborted -- checkpoint data changed unexpectedly mid-run", null)
				_practice_playback_frames = []
				_refresh_practice_ui()
				return
			# Initialize an internal stitch exactly once and continue with its first
			# recorded frame on this same physics tick. The previous ordering did
			# the restore before this guard, armed Playback Settle, returned for a
			# neutral tick, then restored the same checkpoint a second time when
			# settling ended. Restore Drift Diagnostics showed those as paired
			# entries, and the forced renderer glide turned the two corrections
			# into the characteristic checkpoint shake. There is no smoothing
			# glide and no settle delay here now: authoritative recorded state is
			# applied below before native input handles this tick.
			if boundary_idx != _practice_playback_settled_boundary:
				_practice_playback_settled_boundary = boundary_idx
				_restore_moving_world_state(_practice_checkpoints[boundary_idx])
				# Format-3 macros put a complete authoritative player state on
				# the first frame of every segment. Applying that frame below is
				# sufficient to resync position, velocity and every gameplay timer.
				# Calling _restore_player() here as well ran native _reset_object()
				# despite the saved join already being continuous (the current slot's
				# measured joins are 0..0.42 units). That respawn-only reset was the
				# remaining observable stitch. Keep the hard restore solely as the
				# compatibility path for old input-only macros.
				var boundary_frame: Dictionary = _practice_playback_frames[_practice_playback_index]
				var has_authoritative_boundary_state: bool = boundary_frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(boundary_frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY
				if not has_authoritative_boundary_state:
					_restore_player(player, _practice_checkpoints[boundary_idx])
			# THE FIFTEENTH-PASS FIX (2026-08-31): dash used to need its own
			# reset here -- a single _practice_playback_dash_held edge-tracker
			# shared across the WHOLE stitched run, so a segment that happened
			# to end mid-dash-hold would otherwise leak into the next, entirely
			# independent segment's own fresh dash press and silently swallow
			# it (exactly what "dash right after dying/checkpoint doesn't come
			# out" looked like). Dash is now just another entry in
			# _practice_playback_injected_held, released the same way every
			# other held action is -- see the unified
			# _release_practice_playback_injected_input() call below, gated on
			# at_fresh_boundary, which now covers this case too, so each
			# segment's dash still starts clean without a dedicated reset here.
			at_fresh_boundary = true
		elif boundary_idx == 0:
			# checkpoint 0's own settle (armed above, in the pending-start
			# branch, on some earlier tick) just finished as of this tick --
			# see the big comment on the settling block above for why this is
			# reached at all instead of having already returned.
			at_fresh_boundary = true
	if _practice_playback_index >= _practice_playback_frames.size():
		_practice_playback = false
		Engine.time_scale = 1.0
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1
		_release_all_injected_actions()
		_log_action("Macro Bot Mode: playback finished (%d deterministic state correction(s))" % _practice_playback_state_corrections, null)
		# Zero manual steps by design -- see _auto_generate_playback_reports()'s
		# own comment. Runs before _practice_playback_frames is cleared below,
		# though that's not actually load-bearing: none of the three reports
		# read that array.
		_auto_generate_playback_reports()
		_practice_playback_frames = []
		_refresh_practice_ui()
		if _self_test_active:
			var expected_ticks := _practice_recorded_frame_count()
			var determinism_passed: = _replay_check_first_desync_tick == -1 and _replay_check_compared_ticks == expected_ticks and _replay_check_safe_ticks == expected_ticks
			var self_test_fail_tick := _replay_check_first_desync_tick if _replay_check_first_desync_tick >= 0 else _replay_check_compared_ticks
			_on_replay_self_test_run_finished(determinism_passed, self_test_fail_tick)
		return
	# THE FIFTEENTH-PASS FIX (2026-08-31): every heuristic that used to live in
	# this function from this point down -- the fresh-boundary catch-up prime,
	# the neutral-vs-active movement split, the grounded/jump-held-vs-airborne
	# "ahead of time" send -- existed only to work around a one-tick native
	# delivery lag specific to driving movement/jump/dash through
	# set_local_continuous_input()/local_input_dash() directly (see THE REAL
	# ACCURACY FIX's comment above _sync_practice_playback_injected_input(),
	# now itself superseded, for the full history). A fresh Divergence
	# Diagnostics report proved that whole heuristic stack still isn't enough:
	# a fresh, non-jumping airborne LEFT press landed a full tick late in
	# replay -- exactly the case THE TWELFTH-PASS FIX's "defer only when truly
	# airborne AND not jumping" branch was specifically built to handle
	# correctly -- while the SAME report's recording-side tick fingerprint
	# came back perfectly clean (0 phantom, 0 backfilled), ruling out native-
	# tick decoupling as an alternate explanation. At the user's own
	# suggestion, this drives playback through the exact same synthetic Input
	# events a real keyboard press generates (_inject_action(), already
	# proven correct by Buffered Inputs/Perfect Jumpzone) instead of the
	# direct native setters -- an injected action takes effect on Input's
	# tracked state synchronously, the instant it's injected, exactly like a
	# genuine keypress, so there's no lag left to compensate for and no
	# "current tick vs. next tick" distinction left to make at all. This is
	# safe during a catch-up batch because each fixed step invokes this method
	# separately, and _inject_action() flushes that step's change immediately
	# before the later-priority native controller runs.
	#   So: at a fresh boundary, release whatever the PREVIOUS segment left
	# synthetically held (a segment can end mid-press, same reasoning as the
	# old per-segment dash-hold reset this replaces) so the new segment starts
	# clean. Then capture this frame's diag entry (if enabled) BEFORE touching
	# input at all -- same "start of this tick, before this tick's own input
	# has had any effect" moment every earlier pass also captured at, so index
	# i in this log and index i in the flattened live log stay directly
	# comparable (see _capture_diag_entry()). Then sync all four actions
	# (movement/jump/dash) to exactly what this frame recorded, unshifted --
	# tick-for-tick replay of exactly what was recorded, no lookahead, no
	# grounded/airborne/jump-held branching, nothing deferred to a later tick.
	if at_fresh_boundary:
		_release_practice_playback_injected_input()
	var frame: Dictionary = _practice_playback_frames[_practice_playback_index]
	if frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY:
		if _apply_recorded_practice_frame_state(player, frame[PRACTICE_FRAME_STATE_KEY]):
			_practice_playback_state_corrections += 1
	if _diag_enabled:
		# THE TWENTY-SIXTH-PASS FIX (2026-08-31) -- THE TWENTY-FIFTH-PASS FIX
		# (see playback_gap_ticks' own comment up top) correctly catches
		# _practice_playback_index up across a real multi-tick gap, but a
		# real Divergence Diagnostics report right after that pass shipped
		# showed the exact same "tick 1" divergence STILL being reported,
		# byte-for-byte identical to the pre-fix symptom -- even though that
		# same report's own fingerprint line confirmed the gap WAS caught
		# (e.g. "3 extra tick(s) caught up across gap(s)"). That's because
		# this diag log only ever got ONE entry appended per call to this
		# function, same as before THE TWENTY-FIFTH-PASS FIX -- so whenever a
		# gap is caught, _diag_replay_log ends up SHORTER than the number of
		# real ticks that actually elapsed, by exactly playback_gap_ticks
		# entries. The comparison tool matches live_log[i] against
		# replay_log[i] by raw array position (see _capture_diag_entry()'s
		# own comment: "index i in this log and index i in the flattened
		# live log stay directly comparable") -- it has no other way to line
		# them up -- so a replay log that's short by N entries is compared
		# against the wrong live entries for the rest of the run, which
		# reads exactly like a real divergence even when gameplay itself
		# (which recorded frame's input actually gets applied) is now
		# correct.
		#   Fixed the same way THE THIRTEENTH-PASS FIX already fixes this on
		# the RECORDING side for an analogous gap: back-fill the skipped
		# slots into _diag_replay_log before the real one, keeping its
		# length 1:1 with real tick count. Recording's own backfill
		# duplicates one CAPTURED state across several assumed-identical
		# ticks because it never separately observed them; here it's the
		# mirror image -- the ticks that were skipped (frames
		# _practice_playback_index - playback_gap_ticks .. _practice_
		# playback_index - 1) DO each have their own real recorded input
		# (unlike live's case), but this replay run only ever observed the
		# player's PHYSICS STATE once, after all of them already happened --
		# there's no way to retroactively recover what position/velocity
		# looked like partway through a gap that's already over. So each
		# backfilled entry pairs that one real skipped frame's own input
		# with the one state we actually have (this tick's, i.e. the state
		# AFTER the whole gap), same "duplicate the only observation
		# available" honesty as the recording-side backfill. This can still
		# show as a divergence for those specific backfilled ticks if live's
		# own state genuinely changed during the gap (it's an inherent, not
		# fully avoidable, side effect of only having one real sample to
		# stand in for several ticks -- the exact same caveat recording's
		# own backfill has always carried) -- but it stops the length
		# mismatch from throwing EVERY tick after the gap out of alignment,
		# which is what was actually producing the byte-for-byte-identical
		# "tick 1" report seen twice in a row after THE TWENTY-FIFTH-PASS
		# FIX shipped.
		_diag_replay_log.append(_capture_diag_entry(player, _find_game(), frame))
		_advance_replay_determinism_check()
	_sync_practice_playback_injected_input(frame)
	# THE SIXTEENTH-PASS FIX (2026-08-31) -- must run AFTER the sync above,
	# same tick: _inject_action() takes effect on Input's tracked state
	# synchronously (see THE FIFTEENTH-PASS FIX's comment), so this reads
	# this exact tick's already-updated held-direction state, including on
	# a fresh-boundary tick whose first frame starts a press immediately.
	# State-backed frames already restore the velocity BEFORE this tick.
	# Native physics must integrate it exactly once. The legacy estimator
	# adds another acceleration/friction step and can undo collision response.
	if not frame.has(PRACTICE_FRAME_STATE_KEY) or (not _practice_playback_uses_native_clock() and player.stick_to_ground_timer <= 0.0):
		_apply_practice_playback_computed_horizontal_velocity(player, at_fresh_boundary)
	if frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY:
		Engine.time_scale = clamp(float(frame[PRACTICE_FRAME_STATE_KEY].get("tas_playback_speed", 1.0)), 0.05, 4.0)
	_practice_playback_index += 1
	# See the PERFORMANCE note on _update_overlay() -- the label itself is
	# only touched from there, once per idle frame, and only on a change.


# THE REAL ACCURACY FIX (2026-08-30, SUPERSEDED 2026-08-31 -- see THE
# FIFTEENTH-PASS FIX on _advance_practice_playback()): this used to drive
# movement/jump/dash DIRECTLY through the same native entry points the game's
# own input script uses -- WPGame.set_local_continuous_input()/
# local_input_dash(), confirmed verbatim in project_specific/GameInput.gd's
# _player_move()/_player_set_jumping()/_player_dash() -- instead of
# synthesizing Input events, specifically to dodge a real batching race: any
# time the engine runs more than one physics tick per main-loop iteration
# (physics catching up to a slow/jittery render frame), two queued synthetic
# events landing in the same dispatch pass would collapse into just the last
# one, silently dropping presses. That race is why this file moved away from
# synthetic input in the first place. It's gone back to synthetic input now;
# every catch-up step has its own _physics_process callback, and the current
# implementation parses and flushes that callback's event immediately before
# the native controller runs. The direct native setters'
# OWN one-tick delivery lag (THE ONE-TICK LOOKAHEAD, THE SIXTH/EIGHTH/TENTH/
# TWELFTH-pass heuristics that tried to compensate for it, all removed with
# this pass) is worth being rid of, since that heuristic stack kept failing
# on cases -- like a fresh, non-jumping airborne press -- it was specifically
# built to handle.
func _practice_playback_movement_value(frame: Dictionary) -> float:
	var move: float = 0.0
	if frame.get(ACTION_MOVE_RIGHT, false):
		move += 1.0
	if frame.get(ACTION_MOVE_LEFT, false):
		move -= 1.0
	return move


# THE FIFTEENTH-PASS FIX (2026-08-31): syncs movement and jump to exactly what
# `frame` recorded via the same _inject_action() synthetic-Input-event path
# Buffered Inputs/Perfect Jumpzone already use -- not the direct native
# setters this replaces (see the comment above _practice_playback_movement_value()
# for why direct native calls are no longer needed). Only actually calls
# _inject_action() for an action whose wanted state DIFFERS from what
# _practice_playback_injected_held already records -- most ticks change
# nothing (held input is typically held for many ticks in a row), which
# skips a needless Input.parse_input_event()/flush_buffered_events() round
# trip (a full input-dispatch pass through the tree) on every physics tick
# for every currently-held action, not just the ticks something changes.
#   Stub-verified (2026-08-31): Godot 3.5.3's own Input singleton already
# deduplicates repeated same-state InputEventAction dispatch on its own --
# re-injecting "pressed=true" every tick of an already-held press does NOT,
# by itself, re-fire is_action_just_pressed() -- so this guard isn't what
# makes an action edge fire exactly once per press; its actual, confirmed job
# is purely the dispatch-overhead skip above. Dash direction is recorded and
# delivered explicitly below because its old synthetic dispatch could race a
# same-tick Left/Right change.
func _sync_practice_playback_injected_input(frame: Dictionary) -> void:
	var move: float = _practice_playback_movement_value(frame)
	var wants: = {
		ACTION_MOVE_LEFT: move < 0.0,
		ACTION_MOVE_RIGHT: move > 0.0,
		ACTION_JUMP: frame.get(ACTION_JUMP, false),
	}
	# Dispatch continuous inputs in a fixed order.  Dash used to be another
	# member of this Dictionary; when direction and dash changed on the same
	# recorded tick, Dictionary iteration could deliver the dash edge first,
	# making GameInput calculate it from the previous direction.
	for action in [ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_JUMP]:
		var want: bool = wants[action]
		if want != _practice_playback_injected_held.get(action, false):
			_inject_action(action, want)
			if want:
				_practice_playback_injected_held[action] = true
			else:
				_practice_playback_injected_held.erase(action)

	# Synthetic dispatch may be consumed by UI or temporarily release one
	# direction before pressing the other. Publish the final pair atomically
	# after dispatch, and prime the native player's first post-restore tick.
	var input_game: = _find_game()
	if input_game != null:
		input_game.set_local_continuous_input(WPGameData.ContinuousInputKeys_MOVEMENT, move)
		input_game.set_local_continuous_input(WPGameData.ContinuousInputKeys_JUMP, bool(frame.get(ACTION_JUMP, false)))
		var input_player: = _get_local_player()
		if input_player != null:
			input_player.input_walk = move
			input_player.input_jump = bool(frame.get(ACTION_JUMP, false))

	# Send the edge through the same native WPGame method used by
	# GameInput._player_dash(), but pass the direction captured on the live
	# edge instead of asking a later event callback to reconstruct it.
	var wants_dash: bool = frame.get(ACTION_DASH, false)
	if wants_dash and not _practice_playback_dash_held:
		var player: = _get_local_player()
		var dash_right: bool
		if frame.has(PRACTICE_DASH_DIRECTION_KEY):
			dash_right = bool(frame[PRACTICE_DASH_DIRECTION_KEY])
		elif move != 0.0:
			dash_right = move > 0.0
		elif frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY and frame[PRACTICE_FRAME_STATE_KEY].has("facing_dir"):
			dash_right = bool(frame[PRACTICE_FRAME_STATE_KEY]["facing_dir"])
		else:
			dash_right = true if player == null else bool(player.facing_dir)
		# Dash direction is also the pose direction for this edge. The native
		# discrete-input queue applies the impulse, but does not reliably update
		# facing before the renderer reads it (especially when movement reverses
		# on the same tick), which produced leftward dashes facing right.
		if player != null:
			player.facing_dir = dash_right
		_practice_playback_dash_direction = dash_right
		_practice_playback_dash_direction_valid = true
		var game: = _find_game()
		if game != null:
			if _practice_playback_uses_native_clock() and player != null:
				# We are already at the native input boundary. Use the same
				# receiver as local_pre_tick before its continuous-input copy;
				# re-queuing here missed the first reliable edge in native tests.
				player.add_input_event(dash_right, NetworkSession.RELIABLE)
			else:
				game.local_input_dash(dash_right)
	_practice_playback_dash_held = wants_dash


# Releases every action Macro Bot Mode playback currently holds synthetically
# pressed via _inject_action(), so a playback that stops mid-press --
# finished, aborted, died, or crossing into a fresh checkpoint boundary --
# can never leave an action stuck held afterward (mirrors
# _release_practice_playback_native_input(), the direct-native-setter
# equivalent this replaces). Safe to call even when nothing is currently
# held (e.g. nothing was ever pressed, or this segment's input was already
# released).
func _release_practice_playback_injected_input() -> void:
	var had_playback_input: bool = _practice_playback or not _practice_playback_injected_held.empty() or _practice_playback_dash_held
	for action in _practice_playback_injected_held:
		_inject_action(action, false)
	_practice_playback_injected_held.clear()
	_practice_playback_dash_held = false
	_practice_playback_dash_direction_valid = false
	var input_game: = _find_game()
	if had_playback_input and input_game != null:
		input_game.set_local_continuous_input(WPGameData.ContinuousInputKeys_MOVEMENT, 0.0)
		input_game.set_local_continuous_input(WPGameData.ContinuousInputKeys_JUMP, false)
