extends "user://mod/core/TASTool/03_host_1.gd"

# Runs at physics-frame granularity (rather than _process's idle-frame
# granularity) because Macro Bot Mode needs to see every physics tick
# individually -- both to record input at the same resolution the native
# player controller reads it, and to catch an alive -> dead transition on
# the exact frame it happens rather than possibly missing a same-idle-frame
# flip-and-flop when multiple physics frames run per idle frame.
func _physics_process(delta: float) -> void:
	if _macro_editor_preview_active:
		return # Timeline preview owns state; never record/inject while paused.
	# Unconditional, regardless of enabled/_tool_restricted()/practice state
	# below -- a restore triggered from anywhere deserves the same
	# fixed-length observation window, and an in-progress watch shouldn't
	# get silently abandoned just because the tool was toggled off a tick
	# into it. No-op when no watches are active (the overwhelmingly common
	# case, since Restore Drift Diagnostics defaults off).
	_advance_restore_drift_watches()
	# Also unconditional, and for the same reason -- see Death Freeze
	# Diagnostics' own big comment (DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN)
	# for why this specifically must run even when `enabled` is false or
	# `_tool_restricted()` reads true: whether one of those two is
	# unexpectedly gating the freeze itself off is exactly one of the two
	# things this diagnostic exists to catch, and it can't catch that from
	# behind the very gate it's checking. Split into a "before" half here
	# (edge-detection, gating-flag capture, and -- ONLY on a tick the
	# freeze below won't run at all -- the tick's own state capture) and an
	# "after" half once the freeze block has actually run (see that call
	# site further down): capturing on both sides of the same tick the
	# freeze runs would show every death's first tick as a false-positive
	# "anomaly" (raw pre-freeze velocity/body state), since this call
	# necessarily happens before the freeze code that's about to correct
	# it. See _death_diag_before_gate()'s own comment for the full reasoning.
	_death_diag_before_gate()
	# Observe WPPlayer's native airborne-ramp phase continuously, even while
	# this overlay is disabled. A checkpoint can be created immediately after
	# enabling the tool, and a playback-only counter would then restore the
	# wrong air acceleration despite all recorded inputs being correct.
	_update_practice_live_airborne_clock()
	if not enabled or _tool_restricted():
		return
	# If a saved slot's green Play button opened a level, wait here (on the
	# same early physics clock used by recording/playback) until the NEW Time
	# Trial is active and its clock reaches checkpoint 0's recorded phase.
	# The watcher can arm playback in this callback; the normal playback branch
	# later in this function then performs checkpoint 0's restore immediately,
	# without introducing an extra idle-frame/tick delay.
	_watch_saved_macro_autoplay(delta)
	_apply_noclip_movement(delta) # no-op unless Debug Noclip is toggled on
	# THE THIRTIETH-PASS FIX (2026-08-31, user report: "the 0 velocity
	# feature you added doesn't always work I realized"). It didn't --
	# THE TWENTY-FOURTH-PASS FIX's freeze used to live further down, past
	# the `if not _practice_active: return` guard below, and was completely
	# unreachable during Play Macro too (that branch returns before ever
	# getting there). So it only ever protected a death that happened while
	# Macro Bot Mode was ACTIVELY RECORDING -- dying with the tool merely
	# enabled but not currently recording a segment (between takes, just
	# practicing, or in the moments right after a Play Macro attempt aborts
	# on an in-macro death) still coasted exactly like before this tool
	# touched any of this. The user's original complaint was never scoped
	# that narrowly ("I have been constantly saying that u get launched in
	# one direction after respawning when you die") -- it's just as real
	# outside an active recording. Moved up here, ahead of every mode-
	# specific branch below, so the freeze applies any time this tool is
	# meaningfully active at all -- enabled and not restricted, the same
	# gate everything else in this function already respects -- regardless
	# of whether Macro Bot Mode happens to be recording, replaying, or off.
	# Skipped while Debug Noclip is on: noclip already disables the physics
	# body and has its own auto-revive-on-death handling, so there's
	# nothing this needs to add there, and it isn't the segment/diag-log
	# discard this shares a name with below (_practice_active section) --
	# that part's unchanged, still specific to recording.
	if not _noclip_enabled:
		var freeze_player: = _get_local_player()
		if freeze_player != null:
			if freeze_player.alive:
				# Remember where the player actually was as of the most
				# recent tick they were still alive -- see THE THIRTY-FIRST-
				# PASS FIX below for why. Deliberately does NOT touch
				# velocity/position at all while alive -- this branch exists
				# purely to keep a one-tick-fresh bookmark for the else
				# branch below.
				_freeze_last_alive_position = freeze_player.position
				# THE THIRTY-SECOND-PASS FIX (2026-08-31, later still, user
				# report: THE THIRTY-FIRST-PASS FIX's velocity-zero-plus-
				# position-snap still wasn't enough -- "still bugged"). See
				# that pass's own big comment below for why a pure velocity
				# freeze can never fully close this: Box2D can also move an
				# overlapping body through its own CONTACT/PENETRATION
				# correction step, which resolves geometric overlap directly
				# by adjusting position, independent of velocity entirely --
				# zeroing linear_velocity every tick does nothing to stop
				# that if the corpse is still embedded in (or freshly landed
				# inside) a hazard's collision shape when the physics server
				# resolves contacts. The only way to stop ALL of that, not
				# just the velocity-driven half, is to stop the body from
				# being simulated at all. On the alive->dead edge below this
				# now also disables the physics body outright
				# (body_enabled/body.enabled = false, the same two flags
				# _restore_player() already keeps in sync with each other);
				# this branch's job is the other half -- catching the
				# dead->alive edge (respawn) and turning the body back on,
				# in case our own disabling of it is still in effect by
				# then. The decompiled respawn_player() does enable both
				# flags; these assignments are only an idempotent safety
				# reassertion after this tool's dead-hold override.
				if not _freeze_prev_alive:
					freeze_player.body_enabled = true
					if freeze_player.body != null:
						freeze_player.body.enabled = true
					# Do NOT call _reset_object() here. The decompiled native
					# respawn_player() path already enables both flags, zeroes
					# both velocities, and calls _reset_object() itself before
					# alive is observed here. Calling it a second time on this
					# following callback correlates exactly with the delayed
					# 0 -> 53..193 cached-velocity return in the real reports.
					# Reasserting the flags/velocity is safe; repeating the
					# opaque native reset is not.
					# THE THIRTY-SEVENTH-PASS FIX (2026-09-01, user report,
					# after being asked directly what "the velocity bug" now
					# looks like: "it's not that the velocity stays, its more
					# like it comes back maybe to it. So as soon as they
					# respawn they get the velocity for whatever reason.") --
					# this reframes the whole investigation: the freeze holds
					# velocity at zero perfectly the entire time the player is
					# dead (34+ straight clean death_freeze_reports already
					# confirm this), but NOTHING in this branch has ever
					# zeroed velocity again AFTER re-enabling the body here.
					# The working theory: while body_enabled/body.enabled are
					# false, this file's own every-tick
					# `freeze_player.linear_velocity = Vector2.ZERO` /
					# `freeze_player.body.linear_velocity = Vector2.ZERO`
					# writes (see the else branch below) may not actually
					# reach the physics body's own INTERNAL simulated
					# velocity state while it's disabled/removed from the
					# simulation -- Box2D bodies are commonly treated as
					# inactive once removed from the world, and a property
					# write made while inactive can be silently dropped or
					# just not applied to the underlying simulated state
					# until the body re-enters the world. If that's what's
					# happening here, then the ACTUAL velocity the body had
					# at the instant of death (whatever killed the player)
					# stays cached inside it the whole hold, invisible to
					# every read this file has ever done (every read of
					# linear_velocity/body.linear_velocity while dead came
					# back reporting 0, because those reads reflect what we
					# wrote, not necessarily the body's own live internal
					# state) -- and the moment body_enabled/body.enabled flip
					# back to true here, the body re-enters the simulation
					# with that stale, pre-death velocity intact, producing
					# exactly what the user described: it "comes back" the
					# instant they respawn. This matches Death Freeze
					# Diagnostics evidence pulled directly off the user's own
					# machine for this pass: report death_freeze_report_
					# 1788213583.txt shows velocity reading (9.374881, -0) on
					# the very first alive tick after 60 ticks of a
					# supposedly fully-zeroed hold, decaying over the next
					# several ticks (80.46 -> 71.01 -> 62.67 -> 55.30) the way
					# residual momentum decays under drag/friction, not the
					# way a fresh keypress ramps up.
					#   FIXED by explicitly zeroing velocity again, on both
					# script-level properties, immediately after re-enabling
					# the body and calling _reset_object() above -- so even
					# if whatever stale internal state _reset_object() or the
					# re-enable itself surfaces is nonzero, this write is the
					# last word before the player regains control this same
					# tick. Deliberately placed AFTER _reset_object() (not
					# before) in case that native call is itself what
					# surfaces/restores the stale cached velocity -- zeroing
					# before it would risk being overwritten right back.
					freeze_player.linear_velocity = Vector2.ZERO
					freeze_player.ground_tangent_speed = 0.0
					if freeze_player.body != null:
						freeze_player.body.linear_velocity = Vector2.ZERO
			else:
				# THE THIRTY-FIRST-PASS FIX (2026-08-31, later still, user
				# report: "after dying I still sometimes get momentum and get
				# thrown back into a spike from the momentum i had after
				# dying") -- THE THIRTIETH-PASS FIX's freeze runs every tick
				# the player reads not-alive, but that leaves exactly ONE
				# tick uncovered: the very tick death itself happens on.
				# Godot calls _physics_process() for every node BEFORE the
				# physics server steps that same frame -- so on the tick a
				# spike collision kills the player, this function's own
				# freeze check above still saw `alive == true` (kill_player()
				# hasn't run yet), and only AFTER this function returns does
				# the physics server actually integrate that tick's motion,
				# resolve the collision, and call kill_player() -- meaning
				# whatever velocity the player had at the moment of impact
				# still gets one full, un-frozen tick of Box2D-simulated
				# travel before the NEXT call to this function ever sees
				# alive=false and starts zeroing anything. Normally that's
				# too small to matter (one tick is ~1/60s), but a spike
				# field with hazards close together, or a high-speed death,
				# is exactly the case where that one uncontrolled tick is
				# enough to carry the corpse into a second, adjacent hazard
				# -- reproducing the user's "thrown back into a spike"
				# report, and explaining why it only happens "sometimes"
				# rather than every death.
				#   Fixed (at the time) by detecting the alive->dead EDGE
				# (comparing against _freeze_prev_alive, this function's own
				# copy of that edge, kept separate from the pre-existing
				# _practice_prev_alive further down since that one only runs
				# while _practice_active) and, on that first dead tick only,
				# restoring player.position back to _freeze_last_alive_position.
				#   STILL NOT ENOUGH ON THAT FIRST TICK ALONE -- THE THIRTY-
				# FOURTH-PASS FIX (2026-08-31, later still) -- Death Freeze
				# Diagnostics (see item 4's own THE THIRTY-THIRD-PASS FIX
				# entry) caught this directly on the very first real death it
				# ever captured: a report showed position moving 3.39 units
				# on the SECOND dead tick, one tick AFTER this snap-back,
				# THE THIRTY-SECOND-PASS FIX's body-disable, and the
				# velocity zero below had all already applied that same
				# first tick -- velocity read exactly (0, 0) and both
				# body_enabled/body.enabled already read false the whole
				# time, yet position still drifted on the very next tick
				# anyway. That rules out velocity-driven movement AND (as
				# far as this file's own state can show) a body genuinely
				# still being simulated -- whatever's moving the position
				# isn't visible as either of those two things from here, but
				# it's real, it's reproducible, and snapping back only once
				# clearly isn't sufficient to fully stop it.
				#   Since chasing the exact mechanism further didn't have a
				# clear next lead (and this file's standing methodology is
				# to act on real evidence rather than keep theorizing once
				# the evidence itself points at a workable fix), the
				# pragmatic fix is to stop being clever about WHEN to
				# reassert this and just do it every dead tick, exactly like
				# the velocity zero and body-disable below already do --
				# reasserting a value that's already correct costs nothing,
				# and this is provably not "only ever needed once" anymore.
				# Confirmed safe with respect to Auto-Respawn/native
				# respawn: both write position AND flip `alive` to true in
				# the same call (see _restore_player() and item 4's own
				# respawn_player() findings) -- by the time this freeze
				# block would next see the player as still `not alive` and
				# try to reassert, a real respawn has already made `alive`
				# read true, so this branch simply won't run that tick at
				# all. UPDATED (THE THIRTY-EIGHTH-PASS FIX, see below): this
				# comment used to say "deliberately NOT writing player.body.
				# position... body is a CHILD node at local (0,0), so
				# writing a world-space position into it too would stack a
				# second offset on top instead of correcting one." That
				# assumption is now directly contradicted by real evidence
				# (see below) -- body's actual rendered transform does NOT
				# always simply track the parent's the way ordinary Godot
				# node parenting would guarantee. THE THIRTY-EIGHTH-PASS FIX
				# below writes body.global_position specifically (not the
				# local .position this note used to warn about) precisely
				# because global_position's own setter accounts for
				# whatever the parent's current transform is, so it can't
				# double-stack an offset the way writing local .position
				# blindly would have.
				freeze_player.position = _freeze_last_alive_position
				freeze_player.linear_velocity = Vector2.ZERO
				freeze_player.ground_tangent_speed = 0.0
				if freeze_player.body != null:
					freeze_player.body.linear_velocity = Vector2.ZERO
				# THE THIRTY-SECOND-PASS FIX -- fully stop the body from
				# being simulated while dead, not just its velocity. Set
				# every dead tick (not just the edge) for the same reason
				# the velocity zero above already is: robustness against
				# anything else that might flip either flag back on mid-
				# hold. This is a deliberate deviation from the real game's
				# own kill_player(), which never touches body_enabled/
				# body.enabled (see item 4) -- same category of intentional
				# divergence as the velocity freeze itself already is, just
				# stronger, because the velocity-only version already
				# shipped twice and still wasn't enough on real hardware.
				freeze_player.body_enabled = false
				if freeze_player.body != null:
					freeze_player.body.enabled = false
				# THE THIRTY-EIGHTH-PASS FIX (2026-09-01, user report: "The
				# velocity bug is back and the macro is still inconsistent",
				# right after THE THIRTY-SEVENTH-PASS FIX shipped) -- pulled
				# and read the newest death_freeze_report_*.txt files
				# automatically (per the user's own established preference)
				# before touching any code, since "velocity bug is back"
				# needed to be checked against real data rather than
				# assumed to mean the same thing as last time. It doesn't:
				# velocity itself reads exactly (0, 0) at the respawn edge
				# and every tick of the hold in every single one of 18 fresh
				# reports -- THE THIRTY-SEVENTH-PASS FIX is confirmed still
				# holding, not regressed. What IS back, in 11 of those 18
				# reports (a clear majority, not a rare edge case): THE
				# THIRTY-SIXTH-PASS FIX's own new "BODY TRANSFORM DIVERGED
				# FROM FROZEN POSITION" flag, consistently 2.7-5.8 units
				# (one report: 627 units, a pre-round/hold-state case) for
				# the ENTIRE dead hold, every single tick, not just
				# transiently. That's very likely what the user is still
				# perceiving as "the velocity bug" -- the corpse's actually-
				# rendered position sitting several units away from where
				# this freeze's own state says it put it looks exactly like
				# residual momentum from the outside, even though it isn't
				# one. This also directly explains the still-reported
				# "macro is still inconsistent": Divergence Diagnostics
				# compares logical fields like player.position, which this
				# freeze has kept perfectly consistent -- it has no way to
				# see body's own separately-drifting rendered transform, so
				# a live/replay run could look identical by every field this
				# tool compares while still looking different to the user's
				# own eyes.
				#   This confirms the root cause this file already
				# theorized when THE THIRTY-SIXTH-PASS FIX first added the
				# check: body's own rendered transform is not simply
				# derived from the parent's (player's) transform the way
				# ordinary Godot node parenting would guarantee -- something
				# else (a native Box2D sync, most likely) drives it
				# independently, and disabling the body stops that sync
				# from ever correcting itself back onto the frozen parent
				# position.
				#   FIXED by explicitly forcing the sync every dead tick:
				# freeze_player.body.global_position is now written to match
				# the frozen position directly, using global_position (not
				# local .position) specifically so this can't double-stack
				# an offset the way the file's own long-standing note above
				# used to worry about -- global_position's setter already
				# accounts for whatever the parent's current transform is.
				if freeze_player.body != null:
					freeze_player.body.global_position = freeze_player.position
				# THE THIRTY-FIFTH-PASS FIX (2026-08-31, later still) called
				# freeze_player._reset_object() here on the alive->dead edge, on the
				# theory that a native reset call would force the position/velocity/
				# body-disable state above to become authoritative the same way it
				# does elsewhere in this file (_restore_player(), the respawn-edge
				# re-enable above). REVERTED (2026-08-31, later still, user report:
				# "First jump broke this time, the velocity bug remains") -- this
				# made things WORSE, not better: it broke the player's first jump
				# after a respawn, AND the original momentum/velocity bug this whole
				# chain exists to fix was still present on top of that. _reset_object()
				# is opaque, native, and undocumented -- this file has no decompiled
				# source for it -- and the leading theory for the new breakage is that
				# it clears some jump-related internal state (buffered input, ground-
				# contact/coyote-time tracking, a jump counter) that the respawn path
				# doesn't expect to have already been touched, since every OTHER place
				# this file calls it is paired with that same tick's own full
				# reinitialization (a real teleport, or the respawn-edge re-enable
				# immediately above, which runs right as alive flips back to true) --
				# calling it on the DEATH edge instead has no such pairing, so whatever
				# it clears is left cleared until the player's next real action, which
				# turned out to be that same player's first post-respawn jump input.
				# This is a theory, not a decompiled certainty, same as the fix it's
				# reverting -- but a change that regresses a working mechanic (jump)
				# while NOT fixing the bug it was made for has no case for staying,
				# regardless of the exact mechanism. Reverted back to relying solely
				# on THE THIRTY-FOURTH-PASS FIX's every-tick position/velocity/body-
				# disable reassertion above (unchanged, still in effect) while this
				# file goes back to real evidence (Death Freeze Diagnostics, still in
				# place) for the next step rather than another native-call guess.
				# See OPEN INVESTIGATION NOTES item 4 for the fuller writeup.
			_freeze_prev_alive = freeze_player.alive
	# The "after" half of Death Freeze Diagnostics -- captures the
	# CORRECTED state once the freeze block above has actually run this
	# tick (a no-op if there's no watch open, or if the freeze didn't run
	# this tick -- see that function's own comment for why it's safe to
	# call unconditionally here).
	_death_diag_after_freeze()
	if _autoplay_bot != null and is_instance_valid(_autoplay_bot) and bool(_autoplay_bot.call("physics_tick")):
		return
	_watch_practice_start_request() # no-op unless a Start (manual or Auto-Activate) is currently armed and waiting -- see the big comment on _on_toggle_practice_pressed()
	_watch_practice_place_request() # no-op unless a checkpoint placement is currently pending -- see the big comment on _on_place_practice_checkpoint_pressed()
	if _practice_playback:
		# SCHEDULER CORRECTION (2026-09-01): one callback already means one
		# fixed Godot physics step. Do not toggle time_scale inside the callback:
		# the engine may already have scheduled a render-frame catch-up batch,
		# and changing the global scale here cannot turn that batch into a
		# single step. Every callback consumes exactly one macro frame.
		# HISTORICAL, SUPERSEDED: THE FOURTEENTH-PASS FIX (2026-08-31) -- OWN THE CLOCK, DON'T SAMPLE
		# IT. See TASTool_TICK_ACCURACY_PLAN.md. Playback used to run at
		# whatever Engine.time_scale was in effect and call
		# _advance_practice_playback() unconditionally every
		# _physics_process() call, trusting that always meant one real
		# native tick -- the same assumption THE THIRTEENTH-PASS FIX above
		# just proved wrong for live recording. Recording has an excuse (a
		# human is playing it in real time, so its ticks can only be
		# detected after the fact); playback doesn't -- it can fully
		# control its own pacing instead of trusting it, the way real TAS
		# tools (TASBot, libTAS, Bizhawk, Dolphin frame-advance) actually
		# work: pause the engine, single-step it forward exactly one
		# physics tick at a time under explicit control, confirm that tick
		# actually happened, THEN act -- never running freely in between.
		#   This _physics_process() call itself IS that confirmation --
		# Godot's own contract guarantees a call here means a real tick
		# just occurred, not an assumption this tool is making. Re-pausing
		# immediately, before doing anything else, means no further tick
		# can slip in while _advance_practice_playback() does this one's
		# work below (the same Engine.time_scale primitive the manual
		# Frame Step feature already uses, just driven from the physics
		# callback itself instead of polled once per idle frame, for tighter
		# guarantees than manual stepping needs). Re-arms exactly one more
		# tick at the bottom, but only if playback is still actually
		# running AND the user hasn't manually paused (_toggle_pause()) in
		# the meantime -- _advance_practice_playback() already correctly
		# flips _practice_playback to false on every genuine stop condition
		# (finished, died, aborted, no player), so checking it after the
		# call, rather than duplicating that logic here, can't disagree
		# with it; and honoring a manual pause here means pressing Pause
		# actually freezes an in-progress macro instead of this loop
		# silently fighting it back to 1.0 next tick.
		#   Known trade-off: the Speed control has no effect on Play Macro
		# pacing anymore -- it's entirely this loop's own, one confirmed
		# tick at a time, not Engine.time_scale's. A cosmetic playback-speed
		# option (still one CONFIRMED tick at a time, just several per
		# visible render frame) is possible later; not done here since
		# accuracy, not speed, is what this pass is for.
		var native_clock_ready: bool = _ensure_practice_native_tick_hooks(_find_game())
		if not native_clock_ready or not _practice_playback_uses_native_clock():
			_advance_practice_playback()
		return
	if not _practice_active:
		return
	var player: = _get_local_player()
	if player == null:
		return
	if _practice_prev_alive and not player.alive:
		_practice_current_segment.clear()
		_diag_live_current.clear() # same discard-on-death lifecycle as the segment it mirrors
		_practice_deaths_this_segment += 1
		if _practice_auto_respawn and not _practice_checkpoints.empty():
			# THE NINTH-PASS FIX -- don't restore instantly on this same tick.
			# Arm a wait instead; see PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS's
			# big comment for why letting the native death hold run its course
			# first (instead of preempting it) is worth doing here.
			_practice_awaiting_native_respawn = true
			_practice_native_respawn_wait_ticks = 0
			_set_status("Macro Bot: died -- waiting for respawn")
		else:
			_set_status("Macro Bot: died -- segment discarded")
	# THE TWENTY-FOURTH-PASS FIX (2026-08-31, user report: "you get launched
	# in one direction after respawning when you die and still have
	# momentum" -- see OPEN INVESTIGATION NOTES item 4 for how this was
	# tracked down to a real, confirmed mechanism, not a guess: the real
	# game's own kill_player() (scripts/WPGame.gd, decompiled) only sets
	# alive=false and arms dead_counter -- it never disables the body or
	# touches velocity, so a corpse that was moving when it died just keeps
	# right on being fully Box2D-simulated -- gravity, existing momentum,
	# any collision it happens to hit -- for the WHOLE death hold, until
	# respawn_player() finally resets everything at once) USED TO have its
	# fix live right here, re-zeroing velocity every tick death holds --
	# but that was only reachable while `_practice_active`, so a death
	# outside an active recording (between takes, just practicing, right
	# after a Play Macro attempt aborts) still coasted. THE THIRTIETH-PASS
	# FIX (2026-08-31, later still, user report: "the 0 velocity feature
	# you added doesn't always work") moved the actual freeze up to the top
	# of _physics_process(), ahead of every mode-specific branch -- see
	# that comment for the full reasoning. Nothing left to do here.
	if _practice_awaiting_native_respawn:
		_practice_native_respawn_wait_ticks += 1
		if player.alive or _practice_native_respawn_wait_ticks >= PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS:
			_practice_awaiting_native_respawn = false
			_restore_player(player, _practice_checkpoints.back())
			_set_status("Macro Bot: died -- back to checkpoint %d" % [_practice_checkpoints.size() - 1])
	_practice_prev_alive = player.alive
	# THE ELEVENTH-PASS FIX (2026-08-30): explains basically every wild,
	# hundreds-of-units divergence this session, per the user -- they were
	# using Debug Noclip mid-recording (to reposition/skip around between
	# real attempts). Noclip reads the exact same player_left/right/up
	# actions as real movement (see _apply_noclip_movement()'s own header
	# comment) and drives position directly, bypassing Box2D entirely -- but
	# this capture had no idea any of that was happening, so it recorded
	# noclip's held actions as ordinary jump/movement frames. Play Macro,
	# with no way to know a stretch of "held up" was actually a noclip flight
	# and not a real jump, fed those frames through the NORMAL native input
	# pipeline instead -- producing completely unrelated real physics next
	# to wherever noclip had actually put the live player. That's a properly
	# unreproducible situation, not a bug in the replay logic being chased
	# all session -- so the fix is to stop recording it at all: while Debug
	# Noclip is on, this capture is skipped entirely (segment and diag log
	# both just don't grow this tick), the same way it's already skipped
	# while the player is dead. Recording resumes automatically the instant
	# Noclip is turned back off. A macro that used Noclip to actually GO
	# somewhere (not just idle/wait) will still need a fresh checkpoint
	# placed after turning Noclip off, same as it always would have --
	# skipping capture doesn't teleport the replay there on its own.
	if player.alive and not _noclip_enabled and not _ensure_practice_native_tick_hooks(_find_game()):
		_capture_practice_native_frame(player)


func _on_tas_tree_node_added(node: Node) -> void:
	if node != null and node.name == "LeaderboardScript" and node.has_method("on_leaderboard_row_pressed"):
		call_deferred("_inject_leaderboard_search", node)
	if node != null and node.name == "CustomLobbyScene" and node.has_method("on_create_lobby_button_pressed"):
		call_deferred("_inject_custom_lobby_code_button", node)
	if is_instance_valid(_game) and _game.is_inside_tree():
		return
	if _is_game_candidate(node):
		_set_cached_game(node as WPGame)


func _on_tas_tree_node_removed(node: Node) -> void:
	if is_instance_valid(_game) and node == _game:
		_set_cached_game(null)

func _on_ui_scale_percent_changed(value: float) -> void:
	ui_scale = value / 100.0
	_apply_ui_scale()
	_save_main_window_layout("menu")

func _on_main_ui_scale_reset() -> void:
	ui_scale = 1.0
	_apply_ui_scale()
	_gui_layout_config.erase_section("main_windows")
	for which in ["menu", "log"]:
		_restore_main_window_layout(which)
		_save_main_window_layout(which)

func _on_main_ui_fit() -> void:
	if _menu_window == null:
		return
	var available: Vector2 = get_viewport().get_visible_rect().size - Vector2(40, 40)
	var size: Vector2 = _menu_window.rect_size
	ui_scale = min(available.x / max(1.0, size.x), available.y / max(1.0, size.y)) * abs(get_viewport().get_final_transform().get_scale().x)
	_apply_ui_scale()
	_menu_window.rect_position = Vector2(20, 20)
	_save_main_window_layout("menu")
