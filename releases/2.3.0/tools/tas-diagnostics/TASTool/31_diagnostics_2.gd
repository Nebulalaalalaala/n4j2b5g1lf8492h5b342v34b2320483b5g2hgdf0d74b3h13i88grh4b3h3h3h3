extends "user://mod/tools/tas-diagnostics/TASTool/30_diagnostics_1.gd"

# THE FIX (2026-08-30, user request): called from BOTH of
# _advance_practice_playback()'s exit points -- the clean "finished" branch
# (which already had its own, narrower version of this) and the "died mid-
# macro" branch (which previously auto-saved nothing at all, the exact
# opposite of what you'd want -- a death IS the interesting case). Bundles
# all three auto-savable reports behind their own existing enable toggles, so
# turning one on is still all that's needed for it to fire automatically
# every time a Play Macro run ends, without a single manual button press:
#   - the key-event report, whenever Debug Mode is on (unchanged condition
#     from before this fix -- only the trigger SITES changed)
#   - the Divergence Diagnostics report, whenever Diagnostic Logging is on
#     (a strict superset of Debug Mode being on, since Debug Mode forces
#     this on too -- so this also covers "just Diagnostic Logging by
#     itself, Debug Mode never touched")
#   - the Restore Drift report, whenever Restore Drift Diagnostics is on
#     AND at least one restore has actually been observed (avoids a useless
#     "nothing observed yet" log line firing on every single playback for
#     someone who turned the toggle on but never triggered a restore)
# Each of the three functions this calls already no-ops safely (with its own
# explanatory log line) if its own data happens to be empty, so there's no
# real risk of this spamming useless output when only some are on.
func _auto_generate_playback_reports() -> void:
	if _debug_mode_enabled:
		_auto_generate_key_event_report()
	if _diag_enabled:
		_on_compare_diagnostics_pressed()
	if _restore_drift_enabled and not _restore_drift_log.empty():
		_on_save_restore_drift_report_pressed()


# Called from _advance_practice_playback()'s finish branch, ONLY when Debug
# Mode is on -- see _on_toggle_debug_mode_pressed(). Mirrors
# _on_compare_diagnostics_pressed()'s own live/replay/coverage setup exactly
# (same _flatten_diag_live() / _diag_replay_log / _diag_coverage_prefix_ticks()
# calls) so the two reports are always talking about the same tick range,
# just rendered two different ways.
func _auto_generate_key_event_report() -> void:
	var live: = _flatten_diag_live()
	var replay: = _diag_replay_log
	if live.empty() or replay.empty():
		_log_action("Debug Mode: skipped auto key-event report -- no comparable diagnostic data (live=%d tick(s), replay=%d tick(s)). This shouldn't normally happen while Debug Mode is on, since it forces Diagnostic Logging on automatically -- if you're seeing this, Diagnostic Logging was probably switched off again, or nothing was recorded/played back yet." % [live.size(), replay.size()], null)
		return
	var overlap_count: = min(live.size(), replay.size())
	var safe_ticks: = _diag_coverage_prefix_ticks()
	var coverage_incomplete: = safe_ticks < overlap_count
	var compare_ticks: int = safe_ticks if coverage_incomplete else overlap_count
	var report_text: = _build_key_event_report_text(live, replay, compare_ticks, coverage_incomplete)
	var path: = _write_key_event_report(report_text)
	_log_action("Debug Mode: key-event comparison report auto-saved -- %s" % [path], null)


# ----------------------------------------------------------------------
#  Restore Drift Diagnostics
# ----------------------------------------------------------------------
# THE POINT: Divergence Diagnostics already proved WHERE the problem is
# (position, starting 2-3 ticks after a restore) and Playback Settle proved
# it is NOT a brief, self-correcting wobble -- holding zero input for up to
# 5 extra ticks after a restore changed nothing, the final drift was
# byte-for-byte identical either way. That means whatever Box2D is doing
# after a teleport-style restore, it isn't "still settling, give it more
# time" -- it converges to a genuinely different resting spot than
# continuous simulation would have landed on, and it does so fast.
#   Rather than guess at another physics mitigation (twice was enough),
# this only WATCHES: every time a restore happens (while this is toggled
# on), it records the player's position for RESTORE_DRIFT_WATCH_TICKS
# ticks afterward, with no attempt to influence what happens. Save Restore
# Drift Report dumps everything observed so far -- if the drift really is a
# fixed, deterministic amount (which the two identical divergence reports
# strongly suggest), this is what proves it and measures exactly what it
# is, so it can be directly compensated for -- e.g. nudging a restored
# grounded position by the measured constant BEFORE Box2D ever gets a
# chance to introduce it -- instead of fighting Box2D's behavior after the
# fact. That is future work; this only gathers the evidence.
func _arm_restore_drift_watch(p: WPPlayer, snap: Dictionary, velocity_before_reset_object: Vector2 = Vector2.ZERO, velocity_after_reset_object: Vector2 = Vector2.ZERO, reset_object_called: bool = true) -> void:
	if not _restore_drift_enabled:
		return
	_restore_drift_watches.append({
		"player": p,
		"start_position": p.position,
		"snap_velocity": snap.get("linear_velocity", Vector2.ZERO),
		"snap_grounded": snap.get("stick_to_ground_timer", 0.0) > 0.0,
		"ground_probe": _probe_ground_below(p),
		"sleep_state": _probe_body_sleep_state(p.body), # read-only, informational -- see that function's comment for the (now ruled out) theory it was gathering evidence for
		"reset_object_called": reset_object_called, # see the REVISED note in _restore_player() -- false whenever the restored snapshot leaves the player disabled (still mid a pre-round/hold), matching the real game's own respawn_player()-only usage of _reset_object()
		"velocity_before_reset_object": velocity_before_reset_object,
		"velocity_after_reset_object": velocity_after_reset_object,
		# Filled in later by _arm_playback_settle()/the settle-hold branch in
		# _advance_practice_playback() only for checkpoint 0. Internal stitch
		# restores intentionally never settle because that added unrecorded
		# neutral ticks and made the boundaries visible.
		"settle_armed": false,
		"settle_ticks_used": -1,
		"settle_hit_cap": false,
		"ticks_left": RESTORE_DRIFT_WATCH_TICKS,
		"positions": [p.position],
	})


# THE THEORY THIS IS FOR: live stays at a dead-stop, bit-for-bit identical
# position/velocity, for many ticks in a row at exactly the restores that
# then free-fall on replay (see the comment above _snapshot_is_at_rest()).
# That kind of perfect, unchanging stillness is what a SLEEPING Box2D body
# looks like -- physics engines routinely stop simulating a body once it's
# been at rest for a few frames, so it simply doesn't move even if its
# support is marginal or technically gone, until something wakes it. A
# teleport-restored body can't be "still asleep" -- it's freshly
# repositioned and starts fully awake, which would make it immediately
# discover (correctly, per real physics) that nothing is actually holding
# it up. If that's right, the fix isn't matching more script-level fields
# at restore time, it's suspending the body's simulation for a few ticks
# the way sleep already does -- but that's a real behavior change to test
# properly before shipping, not something to guess at from here. This only
# tries to CONFIRM it's happening: best-effort, since nothing in the
# shipped GDScript source ever reads or names a sleep-state property on
# this native body class, so the exact name (if this build exposes one at
# all) isn't something to guess with confidence -- tries the handful of
# names Box2D/Godot ports commonly use, and reports plainly if none of them
# exist on this build rather than assuming any one is right.
# Takes the body directly (untyped -- it's a native class TASTool.gd
# doesn't declare, always accessed by duck-typing elsewhere in this file
# too) rather than a WPPlayer, so this same probe logic is testable against
# any stand-in body without needing it to satisfy WPPlayer.body's exact
# native type.
#
# RULED OUT (2026-08-30): a Divergence Diagnostics report showed exactly
# this signature at tick 0 of a fresh recording -- live perfectly still,
# bit-for-bit identical position AND velocity=(0,0) for many ticks in a
# row, at a checkpoint whose own script-level grounded check
# (stick_to_ground_timer) said FALSE the whole time; replay free-fell from
# that same restored position and velocity immediately. That looked exactly
# like a sleeping-body signature, so an experiment (_try_sleep_body(),
# since removed) tried forcibly sleeping the body on every near-zero-
# velocity restore. The FOLLOW-UP restore drift report showed the forced
# write genuinely stuck on this build (read back immediately as applied --
# e.g. "awake=False->False") on every single restore, yet the divergence
# report from that same run showed the identical free-fall, unchanged. That
# rules sleep out cleanly: whatever drives gravity/movement here isn't
# gated on Box2D's own sleep flag at all. The REAL mechanism, confirmed
# straight from GooberDash's own decompiled source: a player sitting in a
# pre-round hold has `alive = false` and `body.enabled = false` (see the
# REVISED note on _reset_object() in _restore_player()) -- a genuinely
# disabled, unsimulated body, nothing to do with sleep/wake at all. This
# probe is kept only as a plain, read-only diagnostic (still shown in every
# restore-drift report) in case sleep state becomes relevant to some other
# investigation later -- it no longer backs any active theory or fix.
func _probe_body_sleep_state(body) -> String:
	if body == null:
		return "no body"
	var found: = []
	for prop_name in RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES:
		var val = body.get(prop_name)
		if val != null:
			found.append("%s=%s" % [prop_name, val])
	if found.empty():
		return "not exposed under any known name (tried: %s)" % ", ".join(RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES)
	return ", ".join(found)


# Read-only ground check via the real game's OWN native raycast helper --
# confirmed straight from the shipped source (WPPlayerAI.gd's
# detect_hazards()/_raycast_hazard(): "game.world.intersect_ray_fast(results,
# p, p + v)", and WPGame.gd's "onready var world: = $Box2DWorld as
# UpguysBox2DWorld") -- not a guess at collision layers, the same call the
# game's own AI already relies on. Casts straight down (+Y, matching the
# fall direction actually observed in restore drift data) from the restored
# position, up to RESTORE_DRIFT_GROUND_PROBE_DISTANCE. Returns the distance
# to whatever it hits, or -1.0 if nothing was hit within that range (or the
# native ray API wasn't reachable, e.g. no game/world yet). Never changes
# anything -- purely a measurement for the drift report to correlate
# against, testing the theory that a checkpoint captured the instant
# stick_to_ground_timer expired (grounded=False) but before the player
# actually left real Box2D contact will show a short probe distance right
# next to a since-observed large fall -- i.e. the "drift" is really the
# player correctly falling from a spot that was never truly resting to
# begin with, just still touching (per Box2D) for a moment past when the
# script-level timer said so.
func _probe_ground_below(p: WPPlayer) -> Dictionary:
	var out: = {"distance": -1.0, "label": ""}
	var g: = _find_game()
	if g == null:
		return out
	var world = g.get("world")
	if world == null or not world.has_method("intersect_ray_fast"):
		return out
	var from: = p.position
	var to: = p.position + Vector2(0, RESTORE_DRIFT_GROUND_PROBE_DISTANCE)
	var results: = {}
	if not world.intersect_ray_fast(results, from, to):
		return out
	out["distance"] = from.distance_to(results["position"])
	# Best-effort label of WHAT was hit, mirroring WPPlayerAI.gd's own
	# "f.get_collision_object().get_parent()" pattern (that's how it finds
	# the LevelNode to check collision_type == HAZARD) -- deliberately not
	# guessing at the HAZARD enum value ourselves here (better to show the
	# real node name/class and let a human eyeball it than risk mislabeling
	# something as "ground" when it's actually a hazard, or vice versa).
	var fixture = results.get("fixture")
	if fixture != null and fixture.has_method("get_collision_object"):
		var body = fixture.get_collision_object()
		if body != null and is_instance_valid(body):
			var owner: Node = body.get_parent()
			if owner != null:
				out["label"] = "%s (%s)" % [owner.name, owner.get_class()]
	return out


# Called once per physics tick, unconditionally, BEFORE the enabled/
# _tool_restricted() gate -- see DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN's big
# comment for the full reasoning. Reads state only; never modifies player/
# body fields itself (that stays exclusively the freeze block's own job,
# so this diagnostic can't be accused of changing the very behavior it's
# trying to observe).
#   Split into this "before" half and _death_diag_after_freeze() (called
# once the freeze block has actually run, if it does) rather than one
# single capture here, specifically so the tick death is first detected
# doesn't always show a false-positive "anomaly": this call necessarily
# runs BEFORE the freeze code that's about to zero velocity/disable the
# body THIS SAME tick, so capturing here unconditionally would make every
# death's first tick look identical to a freeze failure whether the real
# freeze worked or not. This half only records the tick's own state
# directly when the freeze block ISN'T going to run at all this tick
# (tool disabled/restricted/noclip on) -- in every other case it just
# handles edge-detection and leaves the actual capture to the "after" half.
func _death_diag_before_gate() -> void:
	var p: = _get_local_player()
	if p == null:
		return
	if not _debug_mode_enabled:
		# Keep edge state current without allocating logs or writing reports.
		_death_diag_active_watch = null
		_death_diag_ticks_since_respawn = -1
		_death_diag_prev_alive = p.alive
		return
	var tool_would_freeze: = enabled and not _tool_restricted() and not _noclip_enabled
	if not p.alive and _death_diag_prev_alive:
		# Death edge -- start a fresh watch. If one was already open
		# somehow (e.g. a death observed again before the previous
		# watch's tail finished -- shouldn't normally happen given the
		# short tail length, but not assumed impossible), finish it first
		# rather than silently discarding it.
		if _death_diag_active_watch != null:
			_finish_death_freeze_watch()
		_death_diag_active_watch = {
			"tool_enabled": enabled,
			"tool_restricted": _tool_restricted(),
			"noclip_enabled": _noclip_enabled,
			"practice_active": _practice_active,
			"practice_playback": _practice_playback,
			"pre_death_position": _freeze_last_alive_position,
			"post_guard_corrections_start": _post_guard_momentum_corrections,
			"entries": [],
		}
		_death_diag_ticks_since_respawn = -1
	if _death_diag_active_watch != null and not tool_would_freeze:
		# The freeze block below won't run at all this tick -- capture the
		# raw, uncorrected state right here, since nothing else will
		# observe this tick otherwise.
		_death_diag_record_tick(p, false)
	_death_diag_prev_alive = p.alive


# Called once per physics tick, only reached once _physics_process() has
# already passed the enabled/_tool_restricted() gate and the freeze block
# above it has had its chance to run -- captures the CORRECTED state for
# any tick the freeze actually applied (or, for a tick where noclip is on,
# defers to _death_diag_before_gate() having already captured it there,
# via the same tool_would_freeze check, to avoid double-counting a tick).
func _death_diag_after_freeze() -> void:
	if _death_diag_active_watch == null:
		return
	var tool_would_freeze: = enabled and not _tool_restricted() and not _noclip_enabled
	if not tool_would_freeze:
		return # already captured by _death_diag_before_gate() this tick
	var p: = _get_local_player()
	if p == null:
		return
	_death_diag_record_tick(p, true)


func _death_diag_record_tick(p: WPPlayer, tool_would_freeze: bool) -> void:
	_death_diag_active_watch["entries"].append({
		"alive": p.alive,
		"position": p.position,
		"linear_velocity": p.linear_velocity,
		"body_linear_velocity": (p.body.linear_velocity if p.body != null else null),
		"body_enabled": p.body_enabled,
		"body_dot_enabled": (p.body.enabled if p.body != null else null),
		"tool_would_freeze_this_tick": tool_would_freeze,
		# THE THIRTY-SIXTH-PASS FIX (2026-08-31, later still) -- user report:
		# "First jump broke this time, the velocity bug remains", sent right
		# after THE THIRTY-FIFTH-PASS FIX (which forced a native
		# _reset_object() call and got reverted for breaking jump). Every
		# single death_freeze_report captured across two full sessions (34
		# deaths) shows ZERO anomalies in position/velocity/body_enabled --
		# this file's own existing NOTE at the bottom of this report already
		# says why that might not be the whole picture: "It cannot see
		# rendering/interpolation... a visual smoothing effect between
		# physics ticks could look like drift even if the underlying physics
		# state above is perfectly static." p.position is a logical/script
		# property THIS FILE ITSELF writes every dead tick -- of course it
		# reads back clean. It says nothing about whether the PHYSICS BODY's
		# own rendered transform actually followed that write. Capturing
		# body.global_position here (previously only body.linear_velocity
		# was captured, never the body's own position) lets the report below
		# compare the two directly and flag it if they ever diverge -- which
		# would mean the corpse is logically frozen but visibly still
		# somewhere else, exactly matching "I saw it get thrown" while every
		# prior report kept coming back clean.
		"body_global_position": (p.body.global_position if p.body != null else null),
	})
	if p.alive:
		if _death_diag_ticks_since_respawn < 0:
			_death_diag_ticks_since_respawn = 0
		else:
			_death_diag_ticks_since_respawn += 1
	var entries_count: int = _death_diag_active_watch["entries"].size()
	var respawn_tail_done: = _death_diag_ticks_since_respawn >= DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN
	if respawn_tail_done or entries_count >= DEATH_DIAG_MAX_ENTRIES:
		_finish_death_freeze_watch()


func _finish_death_freeze_watch() -> void:
	if _death_diag_active_watch == null:
		return
	var watch: Dictionary = _death_diag_active_watch
	_death_diag_active_watch = null
	_death_diag_ticks_since_respawn = -1
	var text: = _build_death_freeze_report_text(watch)
	var path: = _write_death_freeze_report(text)
	_log_action("Death Freeze Diagnostics: report auto-saved -- %s" % path, null)


# Flags exactly the failure modes THE THIRTIETH/THIRTY-FIRST/THIRTY-
# SECOND-PASS FIXES each individually targeted, plus the two "is it even
# running" possibilities neither of them could have caught -- see
# DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN's own big comment.
func _build_death_freeze_report_text(watch: Dictionary) -> String:
	var lines: = []
	var dt: Dictionary = OS.get_datetime()
	lines.append("Death Freeze Diagnostics report -- %04d-%02d-%02d %02d:%02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]])
	lines.append("tool_enabled=%s tool_restricted=%s noclip_enabled=%s practice_active=%s practice_playback=%s" % [watch["tool_enabled"], watch["tool_restricted"], watch["noclip_enabled"], watch["practice_active"], watch["practice_playback"]])
	lines.append("post-native leaked-momentum corrections during this death window: %d" % [_post_guard_momentum_corrections - int(watch.get("post_guard_corrections_start", _post_guard_momentum_corrections))])
	if watch["tool_enabled"] == false or watch["tool_restricted"] == true or watch["noclip_enabled"] == true:
		lines.append("*** THE FREEZE NEVER RAN AT ALL THIS DEATH *** -- at least one of tool_enabled=false / tool_restricted=true / noclip_enabled=true was true at the moment death was detected, which alone explains unfrozen momentum with no bug in the freeze logic itself needed. See _tool_restricted() (gated by only_active_in_debug_or_solo + OS.is_debug_build() + gd.is_time_trial) if tool_restricted=true is what's showing here.")
	lines.append("pre_death_position=%s" % watch["pre_death_position"])
	lines.append("")
	var entries: Array = watch["entries"]
	var prev_entry = null
	var flagged_nonzero_velocity: = false
	var flagged_body_enabled: = false
	var flagged_position_moved: = false
	var flagged_body_transform_diverged: = false
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var flags: = []
		if not e["alive"]:
			if not e["tool_would_freeze_this_tick"]:
				# Gated off this tick -- the freeze genuinely never ran, so
				# raw velocity/body state here is EXPECTED, not a bug in the
				# freeze logic itself (already called out at the report's
				# top). Flagging it again per-tick here would just be noise
				# on top of that -- the interesting anomaly case is below,
				# for ticks the freeze SHOULD have corrected.
				flags.append("TOOL WOULD NOT FREEZE THIS TICK (gated off)")
			else:
				if not (is_equal_approx(e["linear_velocity"].x, 0.0) and is_equal_approx(e["linear_velocity"].y, 0.0)):
					flags.append("VELOCITY NONZERO WHILE DEAD (freeze should have zeroed this)")
					flagged_nonzero_velocity = true
				if e["body_enabled"] == true or e["body_dot_enabled"] == true:
					flags.append("BODY STILL ENABLED WHILE DEAD (freeze should have disabled this)")
					flagged_body_enabled = true
				if prev_entry != null and not prev_entry["alive"] and prev_entry["tool_would_freeze_this_tick"]:
					var moved: float = e["position"].distance_to(prev_entry["position"])
					if moved > 0.01:
						flags.append("POSITION MOVED %.4f UNITS WHILE DEAD AND SUPPOSEDLY FROZEN" % moved)
						flagged_position_moved = true
				# THE THIRTY-SIXTH-PASS FIX -- see _death_diag_record_tick()'s
				# own comment on body_global_position for why this check
				# exists: p.position being frozen (confirmed clean, every
				# time, for 34 straight deaths) says nothing about whether
				# the physics BODY's own rendered transform actually matches
				# it. If they diverge, the player could be seeing the corpse
				# somewhere other than where this freeze thinks it put it.
				if e["body_global_position"] != null:
					var body_drift: float = e["body_global_position"].distance_to(e["position"])
					if body_drift > 0.5:
						flags.append("BODY TRANSFORM DIVERGED FROM FROZEN POSITION BY %.4f UNITS (rendered corpse may not be where player.position says it is)" % body_drift)
						flagged_body_transform_diverged = true
		var flag_text: = (" <== " + ", ".join(flags)) if not flags.empty() else ""
		lines.append("  tick %d: alive=%s pos=%s body_pos=%s vel=%s body_vel=%s body_enabled=%s body.enabled=%s would_freeze=%s%s" % [i, e["alive"], e["position"], e["body_global_position"], e["linear_velocity"], e["body_linear_velocity"], e["body_enabled"], e["body_dot_enabled"], e["tool_would_freeze_this_tick"], flag_text])
		prev_entry = e
	lines.append("")
	if not flagged_nonzero_velocity and not flagged_body_enabled and not flagged_position_moved and not flagged_body_transform_diverged:
		lines.append("No anomalies flagged above -- velocity stayed zero, the body stayed disabled, position never moved on any tick observed as dead, AND the physics body's own rendered transform (body_pos) matched the frozen logical position every tick. If momentum was still visible to the user during THIS death, it happened somewhere this capture doesn't look (see the note below) or somewhere between two of these ticks that this per-physics-tick capture can't resolve any finer.")
	lines.append("NOTE: this only observes physics-tick state (position/body_pos/velocity/body flags) exactly as _physics_process() and this freeze see them. It cannot see rendering/interpolation happening BETWEEN two physics ticks (a visual smoothing effect there could look like drift even if the physics-tick state above is perfectly static at every sampled instant), and it cannot see native collision response happening to some OTHER object (e.g. if what's actually moving is a hazard/platform the player is attached to, not the player itself).")
	return "\n".join(lines) + "\n"


func _write_death_freeze_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/death_freeze_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


# Called once per physics tick, unconditionally (see the call site in
# _physics_process()) -- independent of Macro Bot Mode / diag / anything
# else being active, so a restore triggered from anywhere (the checkpoint
# editor's Restore button, Macro Bot auto-respawn, Play Macro's boundary
# resync) gets the same fixed-length observation window.
func _advance_restore_drift_watches() -> void:
	if _restore_drift_watches.empty():
		return
	var remaining: = []
	for watch in _restore_drift_watches:
		var p: WPPlayer = watch["player"]
		if not is_instance_valid(p):
			continue # dropped silently -- nothing useful left to measure
		watch["positions"].append(p.position)
		watch["ticks_left"] -= 1
		if watch["ticks_left"] > 0:
			remaining.append(watch)
		else:
			_finish_restore_drift_watch(watch)
	_restore_drift_watches = remaining
	_refresh_restore_drift_ui()


func _finish_restore_drift_watch(watch: Dictionary) -> void:
	var positions: Array = watch["positions"]
	var start: Vector2 = watch["start_position"]
	var stabilized_tick: = -1
	for i in range(1, positions.size()):
		var step: float = positions[i].distance_to(positions[i - 1])
		if stabilized_tick == -1 and step < RESTORE_DRIFT_STABLE_EPSILON:
			stabilized_tick = i
	_restore_drift_log.append({
		"start_position": start,
		"final_position": positions.back(),
		"total_drift": positions.back().distance_to(start),
		"snap_velocity": watch["snap_velocity"],
		"snap_grounded": watch["snap_grounded"],
		"is_stationary": watch["snap_velocity"].length() < PLAYBACK_SETTLE_VELOCITY_EPSILON,
		"ground_probe_distance": watch["ground_probe"]["distance"],
		"ground_probe_label": watch["ground_probe"]["label"],
		"sleep_state": watch["sleep_state"],
		"reset_object_called": watch["reset_object_called"],
		"velocity_before_reset_object": watch["velocity_before_reset_object"],
		"velocity_after_reset_object": watch["velocity_after_reset_object"],
		"settle_armed": watch["settle_armed"],
		"settle_ticks_used": watch["settle_ticks_used"],
		"settle_hit_cap": watch["settle_hit_cap"],
		"stabilized_tick": stabilized_tick,
		"tick_count": positions.size() - 1,
	})


func _on_toggle_restore_drift_pressed() -> void:
	_restore_drift_enabled = not _restore_drift_enabled
	_style_button(_restore_drift_toggle_button, COLOR_PINK if _restore_drift_enabled else COLOR_BLUE)
	_restore_drift_toggle_button.text = "Restore Drift Diagnostics: ON" if _restore_drift_enabled else "Restore Drift Diagnostics: OFF"
	if _restore_drift_enabled:
		_restore_drift_watches = []
		_restore_drift_log = []
	_log_action("Restore Drift Diagnostics %s -- %s" % ["ON" if _restore_drift_enabled else "OFF", "every checkpoint restore from here on is measured for %d ticks afterward" % RESTORE_DRIFT_WATCH_TICKS if _restore_drift_enabled else "existing captured data is kept until you toggle back on"], null)
	_refresh_restore_drift_ui()


# Summarizes total_drift across a set of log entries: count/mean/min/max/
# spread of the drift itself, plus the mean ground-probe distance among
# whichever of those entries actually got a hit (a probe of -1.0 means "no
# ground found within RESTORE_DRIFT_GROUND_PROBE_DISTANCE" and is excluded
# from that average rather than dragging it down).
func _summarize_drift_bucket(entries: Array) -> Dictionary:
	if entries.empty():
		return {"count": 0}
	var total: = 0.0
	var lowest: float = entries[0]["total_drift"]
	var highest: float = entries[0]["total_drift"]
	var probe_total: = 0.0
	var probe_count: = 0
	for e in entries:
		var d: float = e["total_drift"]
		total += d
		lowest = min(lowest, d)
		highest = max(highest, d)
		if e["ground_probe_distance"] >= 0.0:
			probe_total += e["ground_probe_distance"]
			probe_count += 1
	return {
		"count": entries.size(),
		"mean": total / entries.size(),
		"min": lowest,
		"max": highest,
		"spread": highest - lowest,
		"mean_probe": (probe_total / probe_count if probe_count > 0 else -1.0),
		"probe_count": probe_count,
	}


func _on_save_restore_drift_report_pressed() -> void:
	if _restore_drift_log.empty():
		_log_action("Restore Drift Diagnostics: no completed restore(s) observed yet -- turn diagnostics on, then trigger some checkpoint restores (die/respawn, Play Macro, etc.) before saving", null)
		return
	var lines: = []
	lines.append("Restore Drift report -- %s" % _format_time())
	lines.append("%d restore(s) observed, %d watch tick(s) each, stabilized = first tick whose position moved less than %.3f from the tick before, ground probe casts up to %.0f units straight down from the restored position, body_sleep tries reading %s off the player's body (best-effort -- may report \"not exposed\" if this build doesn't have any of them; purely informational now -- forcing sleep was tried and ruled out, see _restore_player()), reset_object_called=<false whenever this restore left the player disabled (body_enabled=false in the snapshot -- a pre-round/hold moment, per the real game's own source) -- the real game's respawn_player() is the ONLY place that ever calls _reset_object(), always with the player enabled first, so this now skips it in that state to match>, reset_object_velocity=<right before p._reset_object() is called>-><right after> (both equal the pre-restore velocity, unchanged, whenever reset_object_called=false above) so a phantom velocity introduced specifically by that one native call is visible as a before!=after mismatch here, settle=<did Playback Settle arm for this restore, and if so did it end because the position genuinely looked stable or because it just gave up at the %d-tick cap> (only checkpoint-0/Play-Macro-boundary restores ever arm it -- manual/editor restores always show \"n/a\")" % [_restore_drift_log.size(), RESTORE_DRIFT_WATCH_TICKS, RESTORE_DRIFT_STABLE_EPSILON, RESTORE_DRIFT_GROUND_PROBE_DISTANCE, RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES, PLAYBACK_SETTLE_MAX_TICKS])
	lines.append("")
	# Bucketed by what the snapshot itself said, NOT just the ground flag --
	# a restore into a snapshot that was still genuinely MOVING (e.g. a
	# death mid-run, or the player just continuing to play normally after
	# an auto-respawn) will obviously rack up position change over the next
	# 20 ticks with no relation to this investigation at all, so it's
	# reported but excluded from the drift stats below. The interesting
	# split is between "at rest" (grounded AND ~zero velocity -- what
	# Playback Settle targets) and "stationary but NOT grounded" (~zero
	# velocity but stick_to_ground_timer already expired) -- the latter is
	# exactly the "coyote time just ran out, but Box2D was probably still
	# actually touching the ground a moment longer than the script-level
	# timer says" case this session's data has been pointing at.
	var at_rest: = []
	var airborne_stationary: = []
	var moving_count: = 0
	for i in range(_restore_drift_log.size()):
		var e: Dictionary = _restore_drift_log[i]
		var probe_text: String = "nothing hit within %.0f" % RESTORE_DRIFT_GROUND_PROBE_DISTANCE
		if e["ground_probe_distance"] >= 0.0:
			var probe_label: String = e["ground_probe_label"] if e["ground_probe_label"] != "" else "unlabeled"
			probe_text = "%.3f (%s)" % [e["ground_probe_distance"], probe_label]
		var settle_text: String = "n/a (never armed)"
		if e["settle_armed"]:
			if e["settle_ticks_used"] < 0:
				# Armed but this session's data predates the hold branch ever
				# reporting back (or playback was aborted/interrupted mid-hold)
				# -- shouldn't happen in a normal run, flagged rather than
				# silently shown as 0 ticks.
				settle_text = "armed but outcome unknown"
			elif e["settle_hit_cap"]:
				settle_text = "armed, gave up at the %d-tick cap (never read as stable)" % e["settle_ticks_used"]
			else:
				settle_text = "armed, settled in %d tick(s)" % e["settle_ticks_used"]
		lines.append("[restore %d] start=%s final=%s drift=%.6f stabilized_tick=%s snap_velocity=%s snap_grounded=%s ground_below=%s body_sleep=%s reset_object_called=%s reset_object_velocity=%s->%s settle=%s" % [i, e["start_position"], e["final_position"], e["total_drift"], (str(e["stabilized_tick"]) if e["stabilized_tick"] >= 0 else "never within %d ticks" % e["tick_count"]), e["snap_velocity"], e["snap_grounded"], probe_text, e["sleep_state"], e["reset_object_called"], e["velocity_before_reset_object"], e["velocity_after_reset_object"], settle_text])
		if not e["is_stationary"]:
			moving_count += 1
		elif e["snap_grounded"]:
			at_rest.append(e)
		else:
			airborne_stationary.append(e)
	lines.append("")
	if moving_count > 0:
		lines.append("%d restore(s) were already moving at the moment of restore -- excluded from the stats below as unrelated normal gameplay, not this investigation." % moving_count)
	var at_rest_stats: = _summarize_drift_bucket(at_rest)
	var airborne_stats: = _summarize_drift_bucket(airborne_stationary)
	if at_rest_stats["count"] > 0:
		lines.append("AT REST (grounded + ~zero velocity): %d sample(s), mean drift=%.6f, min=%.6f, max=%.6f, spread=%.6f, mean ground-below=%s" % [at_rest_stats["count"], at_rest_stats["mean"], at_rest_stats["min"], at_rest_stats["max"], at_rest_stats["spread"], ("%.3f" % at_rest_stats["mean_probe"]) if at_rest_stats["probe_count"] > 0 else "n/a"])
	else:
		lines.append("AT REST (grounded + ~zero velocity): no samples.")
	if airborne_stats["count"] > 0:
		lines.append("STATIONARY BUT NOT GROUNDED (~zero velocity, stick_to_ground_timer already expired): %d sample(s), mean drift=%.6f, min=%.6f, max=%.6f, spread=%.6f, mean ground-below=%s" % [airborne_stats["count"], airborne_stats["mean"], airborne_stats["min"], airborne_stats["max"], airborne_stats["spread"], ("%.3f" % airborne_stats["mean_probe"]) if airborne_stats["probe_count"] > 0 else "n/a"])
	else:
		lines.append("STATIONARY BUT NOT GROUNDED: no samples.")
	lines.append("")
	if at_rest_stats["count"] > 0 and at_rest_stats["spread"] < 0.01:
		lines.append("-> AT REST restores drift by a fixed, negligible-spread amount -- consistent with a small, constant, directly-compensable offset.")
	if airborne_stats["count"] > 0 and airborne_stats["spread"] >= 1.0:
		lines.append("-> STATIONARY-BUT-NOT-GROUNDED restores drift by wildly different amounts restore to restore -- NOT a fixed constant. That rules out a single compensation offset for this bucket. If the drift magnitude tracks the ground-below distance (bigger gap = bigger drift), this isn't a settle artifact at all -- it's just correct free-fall from a spot that was never really resting, because Box2D's real contact outlasted the script-level stick_to_ground_timer that our snapshot relied on to call it \"grounded.\"")
	var text: = "\n".join(lines) + "\n"
	var path: = _write_restore_drift_report(text)
	_log_action("Restore Drift Diagnostics: report saved (%d restore(s)) -- %s" % [_restore_drift_log.size(), path], null)


func _write_restore_drift_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/restore_drift_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


func _refresh_restore_drift_ui() -> void:
	if _restore_drift_status_label == null:
		return
	_restore_drift_status_label.text = "restore drift: %d completed observation(s), %d in progress" % [_restore_drift_log.size(), _restore_drift_watches.size()]
