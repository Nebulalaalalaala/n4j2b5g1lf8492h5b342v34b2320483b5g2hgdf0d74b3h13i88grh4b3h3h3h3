extends "user://mod/tools/overlays/TASTool/29_overlays.gd"

# ----------------------------------------------------------------------
#  Divergence Diagnostics
# ----------------------------------------------------------------------
# THE POINT: everything Macro Bot Mode does to keep a replay accurate --
# facing_dir, dash-edge tracking, the checkpoint-boundary fixes, the
# _reset_object() call, all of it -- is a THEORY about what the native
# controller and Box2D need to see in order to reproduce the original run.
# Every one of those theories was checked against a stub project standing in
# for the native code, because the native code itself can't be run outside
# the real game. That's the ceiling: no amount of reasoning from outside a
# black box can tell you whether it's now accurately modeled, only playing
# it against the REAL native code can. This is what does that -- not by
# guessing better, but by recording exactly what the real game does on a
# genuine live run and diffing it, tick for tick, field for field, against
# what the exact same recorded inputs produce when fed back through Macro
# Bot Mode's own replay path.
#   The output is no longer "the replay feels a bit off around bouncy
# blocks" -- it's "tick 214, right after a JUMP input, linear_velocity.y
# was 640 live and 480 in replay" (or: it's not, and everything after tick
# 214 was drifting only because 214 already had drifted, which is just as
# useful to know). A concrete tick and field is something a specific fix
# can target, or something to go stand on in the level editor and look at
# with fresh eyes -- "always at this exact tick" narrows it to a boundary
# effect or a native tick-ordering quirk; "different tick every run" points
# at fresh Box2D floating point rather than anything Macro Bot Mode itself
# does. Either way, it replaces guessing with a place to look.
#   HOW TO USE IT: turn on Diagnostic Logging (Macro Bot tab) before you
# record your segments, so the ORIGINAL live run is captured tick by tick as
# you record it -- this is the "ground truth" half. Then Play Macro once
# (also with it on) to capture the "replay" half from the exact same
# recorded inputs. Then press Compare. It writes a full report to disk and
# logs a summary of the first mismatch (if any) right in the action log.
#   WHAT IT DOESN'T DO: if inputs and state both match at every tick right
# up until playback ends, the replay genuinely reproduced the original run
# bit-for-bit as far as this tool can observe -- if it still LOOKS or FEELS
# wrong at that point, whatever's different isn't in any of the fields
# tracked here (camera/renderer-only cosmetics, or state on some other
# native object entirely, e.g. the bouncy block itself rather than the
# player). This narrows the search, it doesn't guarantee there's nothing
# left outside what it's able to see.
func _capture_diag_entry(p: WPPlayer, g: WPGame, frame: Dictionary) -> Dictionary:
	var recorded_input: = {}
	for action in PRACTICE_RECORD_ACTIONS:
		recorded_input[action] = frame.get(action, false)
	var entry: = {
		"input": recorded_input,
		"position": p.position,
		"linear_velocity": p.linear_velocity,
	}
	for field in DIAG_SCALAR_FIELDS:
		entry[field] = p.get(field)
	# Debug-only compact moving-world observation. The expensive scene walk is
	# cached once per loaded level; each physics tick only visits the small set
	# of AnimationPlayers and moving physics bodies. This lets the determinism
	# check distinguish a player/input bug from a moving-platform phase mismatch
	# without serializing a full world snapshot into every diagnostic frame.
	entry["world_fingerprint"] = _diag_moving_world_fingerprint(g)
	if g != null and g.wp_game_data != null and ("play_time" in g.wp_game_data):
		entry["play_time"] = g.wp_game_data.play_time
	return entry


func _diag_moving_world_fingerprint(game: WPGame) -> int:
	if game == null or not ("level" in game) or game.level == null:
		_diag_world_level_instance_id = 0
		_diag_world_nodes.clear()
		return 0
	var level_id := game.level.get_instance_id()
	if _diag_world_level_instance_id != level_id:
		_diag_world_level_instance_id = level_id
		_diag_world_nodes.clear()
		_collect_diag_world_nodes(game.level)
	var fingerprint := 5381
	fingerprint = _diag_hash_mix(fingerprint, _diag_world_nodes.size())
	for tracked in _diag_world_nodes:
		if tracked == null or not is_instance_valid(tracked):
			continue
		fingerprint = _diag_hash_mix(fingerprint, str(game.level.get_path_to(tracked)).hash())
		if tracked is AnimationPlayer:
			var animation := tracked as AnimationPlayer
			fingerprint = _diag_hash_mix(fingerprint, animation.current_animation.hash())
			fingerprint = _diag_hash_mix(fingerprint, int(round(animation.current_animation_position * 1000.0)) if not animation.current_animation.empty() else 0)
			fingerprint = _diag_hash_mix(fingerprint, int(round(animation.playback_speed * 1000.0)))
			fingerprint = _diag_hash_mix(fingerprint, animation.is_playing())
		elif tracked is Node2D:
			var moving := tracked as Node2D
			fingerprint = _diag_hash_mix(fingerprint, int(round(moving.position.x * 1000.0)))
			fingerprint = _diag_hash_mix(fingerprint, int(round(moving.position.y * 1000.0)))
			fingerprint = _diag_hash_mix(fingerprint, int(round(moving.rotation * 10000.0)))
			if "linear_velocity" in moving:
				var velocity: Vector2 = moving.get("linear_velocity")
				fingerprint = _diag_hash_mix(fingerprint, int(round(velocity.x * 1000.0)))
				fingerprint = _diag_hash_mix(fingerprint, int(round(velocity.y * 1000.0)))
			if "angular_velocity" in moving:
				fingerprint = _diag_hash_mix(fingerprint, int(round(float(moving.get("angular_velocity")) * 10000.0)))
	return fingerprint


func _collect_diag_world_nodes(node: Node) -> void:
	if node is AnimationPlayer or (node is Node2D and (node is RigidBody2D or node is KinematicBody2D or node.get_class() == "Box2DPhysicsBody")):
		_diag_world_nodes.append(node)
	for child in node.get_children():
		_collect_diag_world_nodes(child)


func _diag_hash_mix(accumulator: int, value) -> int:
	return int((accumulator * 33 + hash(value)) & 0x7fffffff)


func _on_toggle_diag_pressed() -> void:
	if _debug_mode_enabled:
		_log_action("Diagnostic Logging is forced ON while Debug Mode is on -- turn Debug Mode off first if you want to control it separately.", null)
		return
	_diag_enabled = not _diag_enabled
	_style_button(_diag_toggle_button, COLOR_PINK if _diag_enabled else COLOR_BLUE)
	_diag_toggle_button.text = "Diagnostic Logging: ON" if _diag_enabled else "Diagnostic Logging: OFF"
	_log_action("Divergence Diagnostics %s -- %s" % ["ON" if _diag_enabled else "OFF", "record your segments now, Play Macro once, then press Compare" if _diag_enabled else "existing captured data is kept until Macro Bot data is cleared"], null)
	_refresh_practice_ui()


# Flattens _diag_live_committed (one array per committed segment, same shape
# as _practice_segments) into a single tick-ordered list, exactly mirroring
# what _build_practice_playback_frames() does to _practice_segments to build
# the flat frame list _diag_replay_log is captured against -- this is what
# keeps index i meaning the same tick on both sides of the comparison.
func _flatten_diag_live() -> Array:
	var flat: = []
	for seg in _diag_live_committed:
		for entry in seg:
			flat.append(entry)
	return flat


func _diag_field_matches(field: String, live_val, replay_val) -> bool:
	if field in DIAG_VECTOR_FIELDS:
		var eps: = DIAG_POSITION_EPSILON if field == "position" else DIAG_VELOCITY_EPSILON
		return live_val.distance_to(replay_val) <= eps
	return live_val == replay_val


# _diag_live_committed is only guaranteed to correspond index-for-index to
# _practice_segments (and therefore to _practice_playback_frames/_diag_replay_log)
# when Diagnostic Logging was already ON for every tick of every committed
# segment. If it got switched on partway through recording -- entirely
# possible in practice, since nothing stops you from recording some
# checkpoints before ever touching the new toggle -- or a checkpoint got
# undone after already being logged, some _diag_live_committed[k] ends up
# SHORTER than the real _practice_segments[k] it's supposed to mirror (or
# missing entirely). Once that happens, every flattened index from that
# segment onward stops lining up with the same tick on both sides, which
# would silently produce a comparison that looks like scattered, confusing
# divergence when it's actually just misaligned bookkeeping. Returns how
# many leading ticks are still guaranteed aligned -- comparing only up to
# here keeps the report honest instead of quietly wrong.
func _diag_coverage_prefix_ticks() -> int:
	var ticks: = 0
	var n: = min(_diag_live_committed.size(), _practice_segments.size())
	for k in range(n):
		if _diag_live_committed[k].size() != _practice_segments[k].size():
			return ticks
		ticks += _diag_live_committed[k].size()
	if _diag_live_committed.size() != _practice_segments.size():
		return ticks # trailing segment(s) never got any diag data at all
	return ticks


# Phase 0.2 -- Replay Self-Test. Repeatedly re-triggers Play Macro, collecting
# one PASS/FAIL result per run from whichever exit path
# _advance_practice_playback() takes (natural finish vs. mid-macro death),
# combined with the Replay Determinism Check's per-run accuracy. See the
# _self_test_active checks inside _advance_practice_playback() for where runs
# actually get chained together.
func _start_replay_self_test(run_count: int) -> void:
	if _practice_segments.empty() or _practice_playback or _self_test_active:
		return
	var expected_ticks := _practice_recorded_frame_count()
	var safe_ticks := _diag_coverage_prefix_ticks()
	if expected_ticks <= 0 or safe_ticks < expected_ticks:
		var coverage_message := "Replay Self-Test: NO DATA -- record the complete macro with Debug Mode enabled first (%d/%d comparable frames)." % [safe_ticks, expected_ticks]
		_log_action(coverage_message, null)
		if _self_test_status_label != null:
			_self_test_status_label.text = coverage_message
		return
	_self_test_active = true
	_self_test_total_runs = run_count
	_self_test_completed_runs = 0
	_self_test_results = []
	_log_action("Replay Self-Test: starting %d run(s)." % run_count, null)
	_refresh_self_test_status()
	_on_play_practice_macro_pressed()


func _on_replay_self_test_run_finished(passed: bool, fail_frame: int) -> void:
	if not _self_test_active:
		return
	var accuracy: = 0.0
	if _replay_check_compared_ticks > 0:
		accuracy = 100.0 * float(_replay_check_matched_ticks) / float(_replay_check_compared_ticks)
	_self_test_completed_runs += 1
	_self_test_results.append({"run": _self_test_completed_runs, "passed": passed, "fail_frame": fail_frame, "accuracy": accuracy, "compared": _replay_check_compared_ticks, "expected": _practice_recorded_frame_count(), "category": _replay_check_first_desync_category, "field": _replay_check_first_desync_field})
	_refresh_self_test_status()
	if _self_test_completed_runs >= _self_test_total_runs or (not passed and _self_test_stop_on_failure):
		_finish_replay_self_test()
	else:
		_on_play_practice_macro_pressed()


func _finish_replay_self_test() -> void:
	var pass_count: = 0
	for result in _self_test_results:
		if result["passed"]:
			pass_count += 1
	_log_action("Replay Self-Test: finished -- %d/%d run(s) passed." % [pass_count, _self_test_results.size()], null)
	_self_test_active = false
	_refresh_practice_ui()


func _refresh_self_test_status() -> void:
	if _self_test_status_label == null:
		return
	if _self_test_results.empty():
		_self_test_status_label.text = "Replay Self-Test: no runs yet"
		return
	var pass_count: = 0
	for result in _self_test_results:
		if result["passed"]:
			pass_count += 1
	var last: Dictionary = _self_test_results[_self_test_results.size() - 1]
	var last_text: String
	if last["passed"]:
		last_text = "PASS"
	else:
		last_text = "FAIL @ frame %d" % int(last["fail_frame"])
		if not str(last.get("category", "")).empty():
			last_text += " (%s: %s)" % [last["category"], last.get("field", "unknown")]
	_self_test_status_label.text = "Replay Self-Test: %d/%d passed so far -- last run: %s (%.1f%% accuracy)" % [pass_count, _self_test_results.size(), last_text, float(last["accuracy"])]


func _on_self_test_x3_pressed() -> void:
	_start_replay_self_test(3)


func _on_self_test_x5_pressed() -> void:
	_start_replay_self_test(5)


func _on_self_test_x10_pressed() -> void:
	_start_replay_self_test(10)


func _set_self_test_stop_on_failure(value: bool) -> void:
	_self_test_stop_on_failure = value
	SavedSettings.set_value(SETTING_SELF_TEST_STOP_ON_FAILURE, value)
	_refresh_practice_ui()


func _on_toggle_self_test_stop_on_failure_pressed() -> void:
	_set_self_test_stop_on_failure(not _self_test_stop_on_failure)


func _on_compare_diagnostics_pressed() -> void:
	var live: = _flatten_diag_live()
	var replay: = _diag_replay_log
	if live.empty() or replay.empty():
		_log_action("Divergence Diagnostics: nothing to compare yet -- turn on Diagnostic Logging, (re-)record your segments so there's live data, then Play Macro once so there's replay data, then press Compare again.", null)
		return

	var compare_fields: = DIAG_VECTOR_FIELDS + DIAG_SCALAR_FIELDS + DIAG_WORLD_FIELDS
	var overlap_count: = min(live.size(), replay.size())
	var safe_ticks: = _diag_coverage_prefix_ticks()
	var coverage_incomplete: = safe_ticks < overlap_count
	var compared_count: int = safe_ticks if coverage_incomplete else overlap_count
	var first_input_mismatch: = -1
	var first_state_divergence: = -1
	var first_state_field: = ""
	var mismatch_counts: = {}
	for field in compare_fields:
		mismatch_counts[field] = 0

	var report_lines: = []
	var dt: Dictionary = OS.get_datetime()
	report_lines.append("Divergence Diagnostics report -- %04d-%02d-%02d %02d:%02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]])
	report_lines.append("live ticks: %d, replay ticks: %d, compared: %d" % [live.size(), replay.size(), compared_count])
	# One callback is one fixed physics step. These legacy counters remain in
	# the report so old and new logs are easy to compare, but corrected runs
	# never skip/backfill from another node's play_time value.
	report_lines.append("live fixed-step callbacks: %d recorded, %d skipped, %d synthetic (expected skipped=0, synthetic=0)" % [_live_tick_fingerprint_normal, _live_tick_fingerprint_phantom, _live_tick_fingerprint_backfilled])
	report_lines.append("playback fixed-step callbacks: %d consumed, %d skipped, %d fast-forwarded (expected skipped=0, fast-forwarded=0)" % [_playback_tick_fingerprint_normal, _playback_tick_fingerprint_phantom, _playback_tick_fingerprint_gap])
	report_lines.append("authoritative recorded-state corrections applied during playback: %d" % _practice_playback_state_corrections)
	if coverage_incomplete:
		report_lines.append("")
		report_lines.append("WARNING: diagnostic coverage is incomplete -- only the first %d of %d overlapping ticks are guaranteed to line up tick-for-tick. This happens when Diagnostic Logging was switched on partway through recording (some already-recorded segment has fewer logged ticks than it actually has frames), or a checkpoint was undone after being logged. Ticks beyond %d are NOT included below because their numbers may not correspond to the same moment on both sides anymore. For a fully trustworthy report: Clear Macro Bot Mode data, turn Diagnostic Logging ON, then re-record your checkpoints/segments from scratch before Play Macro + Compare." % [safe_ticks, overlap_count, safe_ticks])
	report_lines.append("")

	for i in range(compared_count):
		var l: Dictionary = live[i]
		var r: Dictionary = replay[i]
		if first_input_mismatch == -1 and _inputs_differ(l["input"], r["input"]):
			first_input_mismatch = i
			report_lines.append("[tick %d] INPUT MISMATCH -- live=%s replay=%s (this is a bug in recording/stitching itself, not native physics -- the wrong input got fed back)" % [i, l["input"], r["input"]])
		for field in compare_fields:
			if not _diag_field_matches(field, l[field], r[field]):
				mismatch_counts[field] += 1
				if first_state_divergence == -1:
					first_state_divergence = i
					first_state_field = field
					report_lines.append("[tick %d] FIRST STATE DIVERGENCE -- field '%s': live=%s replay=%s (input this tick: live=%s replay=%s)" % [i, field, l[field], r[field], l["input"], r["input"]])

	report_lines.append("")
	var context_center: = -1
	if first_input_mismatch != -1 and (first_state_divergence == -1 or first_input_mismatch <= first_state_divergence):
		context_center = first_input_mismatch
	elif first_state_divergence != -1:
		context_center = first_state_divergence
	if context_center != -1:
		report_lines.append_array(_build_divergence_context_lines(live, replay, context_center, compared_count))
		report_lines.append("")
	report_lines.append("Per-field mismatch counts (out of %d compared ticks, AFTER the first divergence these largely just cascade from it, not independent problems):" % [compared_count])
	for field in compare_fields:
		if mismatch_counts[field] > 0:
			report_lines.append("  %s: %d" % [field, mismatch_counts[field]])
	if live.size() != replay.size():
		report_lines.append("")
		report_lines.append("NOTE: live and replay run lengths differ (%d vs %d) -- %s" % [live.size(), replay.size(), "replay ended early, likely died mid-macro" if replay.size() < live.size() else "replay ran longer than the live recording, which shouldn't be possible from the same input list -- worth a second look"])

	var report_text: = "\n".join(report_lines)
	var path: = _write_diag_report(report_text)

	var summary: String
	if compared_count == 0:
		summary = "Divergence Diagnostics: no comparable ticks -- diagnostic coverage doesn't even reach checkpoint 0's first tick (Diagnostic Logging almost certainly wasn't on yet when you started recording). Turn it on, re-record from scratch, then try again. Full report: %s" % [path]
		_log_action(summary, null)
		return
	if first_input_mismatch != -1 and (first_state_divergence == -1 or first_input_mismatch <= first_state_divergence):
		summary = "Divergence Diagnostics: input mismatch at tick %d -- that's on Macro Bot Mode's own recording/playback, not native physics. Full report: %s" % [first_input_mismatch, path]
	elif first_state_divergence != -1:
		summary = "Divergence Diagnostics: inputs matched, but '%s' first diverged at tick %d/%d. Full report: %s" % [first_state_field, first_state_divergence, compared_count, path]
	else:
		summary = "Divergence Diagnostics: every tracked field matched for all %d compared ticks -- replay reproduced the recorded run exactly, as far as this tool can see. Full report: %s" % [compared_count, path]
	if coverage_incomplete:
		summary += " (⚠ diagnostic coverage was incomplete -- only checked the first %d/%d overlapping ticks; see report for why)" % [safe_ticks, overlap_count]
	_log_action(summary, null)


# A tick-by-tick window around the first divergence -- both sides' full
# position/velocity/input, plus how many ticks it's been since the most
# recent checkpoint-boundary restore on the replay side (via
# _practice_playback_checkpoint_at, still populated from the Play Macro run
# Compare is reading). A single "[tick N] FIRST DIVERGENCE" line only ever
# showed the moment things had ALREADY gone wrong; this shows whether
# velocity was already off a few ticks earlier (before position visibly
# caught up to it), and whether the divergence tends to land suspiciously
# close to a checkpoint boundary -- both go directly to the "is this a
# checkpoint-restore momentum bug, or something else entirely" question,
# instead of leaving it a guess.
func _build_divergence_context_lines(live: Array, replay: Array, center_tick: int, compared_count: int) -> Array:
	var lines: = []
	lines.append("Context around the first divergence (tick %d), %d tick(s) each side:" % [center_tick, DIAG_CONTEXT_WINDOW])
	var lo: = max(0, center_tick - DIAG_CONTEXT_WINDOW)
	var hi: = min(compared_count - 1, center_tick + DIAG_CONTEXT_WINDOW)
	for i in range(lo, hi + 1):
		var l: Dictionary = live[i]
		var r: Dictionary = replay[i]
		var marker: = " <== FIRST DIVERGENCE" if i == center_tick else ""
		var since_boundary: = _ticks_since_last_playback_boundary(i)
		var boundary_note: = (" [%d tick(s) since last checkpoint boundary]" % since_boundary) if since_boundary >= 0 else ""
		# stick_to_ground_timer + is_inside_one_way_platform specifically --
		# these are what would show whether a restore lands on a one-way
		# platform edge (a very common source of "grounded per script, but
		# a raycast can't find the surface" -- one-way platforms are
		# typically special-cased in collision queries) and whether the
		# grounded flag was already false or freshly went false right in
		# this window, ahead of any visible position change.
		# alive/enabled/dead_counter specifically -- added 2026-08-30, after
		# confirming from GooberDash's own source that a pre-round/hold
		# player sits with alive=false, body.enabled=false, and dead_counter
		# counting down (see the REVISED note on _reset_object() in
		# _restore_player()). Showing these directly here means the NEXT
		# report using this window shows immediately whether that hold state
		# matches between live and replay, instead of only being inferable
		# indirectly from position/velocity staying frozen.
		# THE THIRTEENTH-PASS FIX -- play_time was always captured by
		# _capture_diag_entry() but never shown here. Printing it turns the
		# very next report showing a suspicious repeated tick (like the one
		# that motivated this fix) into a direct, unambiguous test: identical
		# play_time on two consecutive ticks is hard proof the native game
		# hadn't actually ticked between them; different play_time despite
		# identical position/velocity would point somewhere else entirely.
		# .get(..., "n/a") since older report data (or a build that doesn't
		# expose play_time at all -- see _capture_diag_entry()) may not have it.
		lines.append("  tick %d%s: live pos=%s vel=%s play_time=%s ground_timer=%s one_way=%s alive=%s enabled=%s dead_counter=%s input=%s | replay pos=%s vel=%s play_time=%s ground_timer=%s one_way=%s alive=%s enabled=%s dead_counter=%s input=%s%s" % [i, boundary_note, l["position"], l["linear_velocity"], l.get("play_time", "n/a"), l["stick_to_ground_timer"], l["is_inside_one_way_platform"], l["alive"], l["body_enabled"], l["dead_counter"], l["input"], r["position"], r["linear_velocity"], r.get("play_time", "n/a"), r["stick_to_ground_timer"], r["is_inside_one_way_platform"], r["alive"], r["body_enabled"], r["dead_counter"], r["input"], marker])
	return lines


func _write_diag_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/divergence_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


# ----------------------------------------------------------------------
#  Key Event report -- Debug Mode (2026-08-30 revamp)
# ----------------------------------------------------------------------
# THE POINT: Divergence Diagnostics (above) is complete but dense -- a
# per-tick, per-field dump that answers "is anything different" precisely
# but takes real effort to read as "what did the PLAYER actually do
# differently." This turns the exact same underlying per-tick captures
# (_diag_live_committed / _diag_replay_log -- nothing new is recorded here,
# see _capture_diag_entry()'s "input"/"position"/"play_time" fields) into
# discrete press/release EVENTS per action -- the level a human thinks at
# ("I pressed Jump here, held it this long") instead of the level physics
# thinks at (267 individual booleans). Millisecond timestamps come from
# wp_game_data.play_time * 1000.0 -- confirmed via
# ui/nodes/TimeTrialPill.gd (finish_time = game.wp_game_data.play_time) to
# be the exact field driving the game's own top-left race timer, so these
# timestamps line up with what you'd see on screen while recording.
#   This does NOT replace Divergence Diagnostics -- both stay. This is the
# "read this first" summary; that report is still what you'd dig into next
# if a specific tick/field needs a closer look.
func _build_key_events_for_action(flat: Array, action: String) -> Array:
	var events: = []
	# null, or a full duplicated diag entry (see _capture_diag_entry() --
	# "input"/"position"/"play_time"/every DIAG_SCALAR_FIELDS entry, alive/
	# body_enabled/dead_counter included) plus "tick" -- duplicating the
	# whole entry rather than picking out individual fields means any field
	# _capture_diag_entry() already captures is available to _finish_key_event()
	# below with no further plumbing, alive/body_enabled/dead_counter included.
	var held_since = null
	for i in range(flat.size()):
		var entry: Dictionary = flat[i]
		var input: Dictionary = entry.get("input", {})
		var pressed: bool = input.get(action, false)
		if pressed and held_since == null:
			held_since = entry.duplicate()
			held_since["tick"] = i
		elif not pressed and held_since != null:
			events.append(_finish_key_event(action, held_since, i, entry, false))
			held_since = null
	if held_since != null:
		# Still held when the log ran out (playback ended, or Diagnostic
		# Logging's coverage window stopped) -- reported as such rather than
		# silently dropped, since "was still holding Jump when it cut off" is
		# itself useful information.
		events.append(_finish_key_event(action, held_since, flat.size(), null, true))
	return events


# alive/body_enabled/dead_counter are surfaced here (2026-08-30, after the
# first real Debug Mode report showed press-tick/hold-tick matching
# PERFECTLY on every single event -- proving input timing itself is no
# longer the problem -- while replay position and play_time sat frozen
# identical for hundreds of ticks at a stretch, something live never did at
# the same points) specifically so a frozen stretch that lines up with
# body_enabled=false/dead_counter>0 is visible directly on the press/release
# lines that bracket it, instead of needing a second Divergence Diagnostics
# report to go find that out.
func _finish_key_event(action: String, held_since: Dictionary, release_tick: int, release_entry, still_held_at_end: bool) -> Dictionary:
	var press_time_ms: float = (held_since["play_time"] * 1000.0) if held_since.get("play_time", null) != null else -1.0
	var release_time_ms: float = -1.0
	var release_position = null
	var release_alive = null
	var release_body_enabled = null
	var release_dead_counter = null
	if release_entry != null:
		if release_entry.has("play_time"):
			release_time_ms = release_entry["play_time"] * 1000.0
		release_position = release_entry.get("position", null)
		release_alive = release_entry.get("alive", null)
		release_body_enabled = release_entry.get("body_enabled", null)
		release_dead_counter = release_entry.get("dead_counter", null)
	var hold_time_ms: float = (release_time_ms - press_time_ms) if (press_time_ms >= 0.0 and release_time_ms >= 0.0) else -1.0
	return {
		"action": action,
		"press_tick": held_since["tick"],
		"release_tick": (-1 if still_held_at_end else release_tick),
		"press_time_ms": press_time_ms,
		"release_time_ms": release_time_ms,
		"hold_ticks": release_tick - held_since["tick"],
		"hold_time_ms": hold_time_ms,
		"press_position": held_since.get("position", null),
		"release_position": release_position,
		"press_alive": held_since.get("alive", null),
		"press_body_enabled": held_since.get("body_enabled", null),
		"press_dead_counter": held_since.get("dead_counter", null),
		"release_alive": release_alive,
		"release_body_enabled": release_body_enabled,
		"release_dead_counter": release_dead_counter,
		"still_held_at_end": still_held_at_end,
	}


func _format_key_event_ms(ms: float) -> String:
	return ("%.1fms" % ms) if ms >= 0.0 else "unknown"


# One comparison line per matched (live event i, replay event i) pair for a
# single action, plus MISSING/EXTRA lines for either side having more
# presses than the other. Matching is purely positional (live press #0 vs
# replay press #0, etc.) -- correct as long as both sides recorded the same
# NUMBER of presses for this action, which is exactly the thing a MISSING/
# EXTRA line itself flags when it isn't true; once that happens, positions
# after the mismatch are only a best-effort guess, same caveat Divergence
# Diagnostics' own "these largely just cascade" note carries.
func _format_hold_state(alive, body_enabled, dead_counter) -> String:
	if alive == null:
		return "n/a"
	return "alive=%s enabled=%s dead_ctr=%s" % [alive, body_enabled, dead_counter]


func _compare_key_events_for_action(action: String, live_events: Array, replay_events: Array) -> Array:
	var lines: = []
	var n: = max(live_events.size(), replay_events.size())
	for i in range(n):
		if i >= live_events.size():
			var r: Dictionary = replay_events[i]
			lines.append("  [%s #%d] EXTRA IN REPLAY -- replay pressed at tick %d (%s) pos=%s [%s], held %d tick(s) (%s), live never pressed it here" % [action, i, r["press_tick"], _format_key_event_ms(r["press_time_ms"]), r["press_position"], _format_hold_state(r["press_alive"], r["press_body_enabled"], r["press_dead_counter"]), r["hold_ticks"], _format_key_event_ms(r["hold_time_ms"])])
			continue
		if i >= replay_events.size():
			var l: Dictionary = live_events[i]
			lines.append("  [%s #%d] MISSING IN REPLAY -- live pressed at tick %d (%s) pos=%s [%s], held %d tick(s) (%s), replay never pressed it" % [action, i, l["press_tick"], _format_key_event_ms(l["press_time_ms"]), l["press_position"], _format_hold_state(l["press_alive"], l["press_body_enabled"], l["press_dead_counter"]), l["hold_ticks"], _format_key_event_ms(l["hold_time_ms"])])
			continue
		var lv: Dictionary = live_events[i]
		var rv: Dictionary = replay_events[i]
		var tick_delta: int = rv["press_tick"] - lv["press_tick"]
		var ms_delta: float = (rv["press_time_ms"] - lv["press_time_ms"]) if (lv["press_time_ms"] >= 0.0 and rv["press_time_ms"] >= 0.0) else 0.0
		var hold_tick_delta: int = rv["hold_ticks"] - lv["hold_ticks"]
		var pos_delta: float = lv["press_position"].distance_to(rv["press_position"]) if (lv["press_position"] != null and rv["press_position"] != null) else -1.0
		# A hold-state mismatch (one side disabled/dead-counting at press
		# time, the other not) is flagged as its own kind of mismatch even
		# when tick/hold/position all happen to line up -- this is exactly
		# the signal a frozen-replay-stretch leaves on the press bracketing
		# it, see the big comment on _finish_key_event().
		var state_mismatch: bool = lv["press_alive"] != rv["press_alive"] or lv["press_body_enabled"] != rv["press_body_enabled"]
		var mismatched: bool = tick_delta != 0 or hold_tick_delta != 0 or pos_delta > DIAG_POSITION_EPSILON or state_mismatch
		var flag: String = ("  <== MISMATCH%s" % [" (hold-state differs!)" if state_mismatch else ""]) if mismatched else ""
		lines.append("  [%s #%d] live: tick %d (%s) pos=%s [%s] held %d tick(s) (%s) | replay: tick %d (%s) pos=%s [%s] held %d tick(s) (%s) | press-tick Δ=%d press-time Δ=%.1fms hold-tick Δ=%d pos-Δ=%.3f%s" % [action, i, lv["press_tick"], _format_key_event_ms(lv["press_time_ms"]), lv["press_position"], _format_hold_state(lv["press_alive"], lv["press_body_enabled"], lv["press_dead_counter"]), lv["hold_ticks"], _format_key_event_ms(lv["hold_time_ms"]), rv["press_tick"], _format_key_event_ms(rv["press_time_ms"]), rv["press_position"], _format_hold_state(rv["press_alive"], rv["press_body_enabled"], rv["press_dead_counter"]), rv["hold_ticks"], _format_key_event_ms(rv["hold_time_ms"]), tick_delta, ms_delta, hold_tick_delta, pos_delta, flag])
	return lines


# FROZEN STRETCH DETECTION -- added 2026-08-30 alongside the alive/
# body_enabled/dead_counter fields above, after the first real report
# showed EVERY press-tick/hold-tick matching exactly (input timing is
# correct) while replay position AND wp_game_data.play_time both sat
# completely unchanged for hundreds of consecutive ticks at several points
# that live sailed straight through without pausing at all. A per-press
# view only shows the two presses bracketing a stretch like that; this
# scans the whole tick-by-tick log directly for "position AND play_time
# (when known) didn't move at all, `min_ticks` ticks or more in a row" and
# reports each one with its tick range, real-time length, and the
# alive/body_enabled/dead_counter state at its start -- exactly the
# evidence needed to confirm or rule out "stuck in the disabled/dead-
# counter hold" as the cause. min_ticks=10 (~0.17s) is well above normal
# single-tick landing/collision jitter but well below a genuine hold
# (the shortest one seen in that first report was ~127 ticks).
func _find_frozen_stretches(flat: Array, min_ticks: int = 10) -> Array:
	var stretches: = []
	if flat.empty():
		return stretches
	var stretch_start: = 0
	for i in range(1, flat.size() + 1):
		var same_as_prev: = false
		if i < flat.size():
			var prev: Dictionary = flat[i - 1]
			var cur: Dictionary = flat[i]
			var prev_pos = prev.get("position", null)
			var cur_pos = cur.get("position", null)
			var pos_same: bool = (prev_pos != null and cur_pos != null and prev_pos.distance_to(cur_pos) <= DIAG_POSITION_EPSILON)
			var time_same: bool = true # unknown play_time on either side can't disprove "frozen" by itself
			if prev.has("play_time") and cur.has("play_time"):
				time_same = abs(prev["play_time"] - cur["play_time"]) <= 0.0005
			same_as_prev = pos_same and time_same
		if not same_as_prev or i == flat.size():
			var length: = i - stretch_start
			if length >= min_ticks:
				var s: Dictionary = flat[stretch_start]
				stretches.append({
					"start_tick": stretch_start,
					"end_tick": i - 1,
					"length_ticks": length,
					"position": s.get("position", null),
					"play_time_ms": (s["play_time"] * 1000.0) if s.get("play_time", null) != null else -1.0,
					"alive": s.get("alive", null),
					"body_enabled": s.get("body_enabled", null),
					"dead_counter": s.get("dead_counter", null),
				})
			stretch_start = i
	return stretches


func _format_frozen_stretches_section(label: String, flat: Array) -> Array:
	var lines: = []
	var stretches: = _find_frozen_stretches(flat)
	lines.append("-- %s: %d frozen stretch(es) of 10+ consecutive ticks with unchanged position%s --" % [label, stretches.size(), " and play_time" if not flat.empty() and flat[0].has("play_time") else " (play_time not available on this build/entry)"])
	for s in stretches:
		lines.append("  ticks %d-%d (%d tick(s) stuck) at pos=%s, play_time held at %s -- [%s]" % [s["start_tick"], s["end_tick"], s["length_ticks"], s["position"], _format_key_event_ms(s["play_time_ms"]), _format_hold_state(s["alive"], s["body_enabled"], s["dead_counter"])])
	return lines


func _build_key_event_report_text(live_flat: Array, replay_flat: Array, compare_ticks: int, coverage_incomplete: bool) -> String:
	var dt: Dictionary = OS.get_datetime()
	var lines: = []
	lines.append("Key Event report -- %04d-%02d-%02d %02d:%02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]])
	lines.append("Auto-generated by Debug Mode the instant Play Macro playback finished. One line per discrete press/release of each recorded action (Jump/Dash/Left/Right) -- press tick + millisecond timestamp (off wp_game_data.play_time, the same clock the game's own top-left timer reads), hold duration, and position, live vs replay side by side. Same underlying per-tick data as the Divergence Diagnostics report above (see that one for the full per-tick field dump if this doesn't pin things down) -- this just reads at the level of 'what did the player actually press,' not 'what did every field do.'")
	lines.append("live ticks: %d, replay ticks: %d" % [live_flat.size(), replay_flat.size()])
	if coverage_incomplete:
		lines.append("WARNING: diagnostic coverage was incomplete -- comparison below is limited to the first %d tick(s) that are guaranteed to line up tick-for-tick on both sides (see the Divergence Diagnostics report's own warning for why). Events built from anything after that point are not shown." % [compare_ticks])
	lines.append("")
	var live_capped: = _cap_flat_log(live_flat, compare_ticks)
	var replay_capped: = _cap_flat_log(replay_flat, compare_ticks)
	var any_mismatch: = false
	for action in PRACTICE_RECORD_ACTIONS:
		var live_events: = _build_key_events_for_action(live_capped, action)
		var replay_events: = _build_key_events_for_action(replay_capped, action)
		lines.append("== %s -- %d live press(es), %d replay press(es) ==" % [action, live_events.size(), replay_events.size()])
		if live_events.empty() and replay_events.empty():
			lines.append("  (never pressed, either side)")
		else:
			var action_lines: = _compare_key_events_for_action(action, live_events, replay_events)
			for line in action_lines:
				if line.find("MISMATCH") != -1 or line.find("MISSING") != -1 or line.find("EXTRA") != -1:
					any_mismatch = true
			lines.append_array(action_lines)
		lines.append("")
	if not any_mismatch:
		lines.append("Every recorded press/release matched between live and replay -- same tick offset, same hold duration, same position (within %.3f units), for every action. If the replay still looks/feels wrong despite that, whatever's different isn't in the input timing itself -- check the Divergence Diagnostics report above for a state field (velocity, dash_cooldown, etc.) that diverged even with matching input." % [DIAG_POSITION_EPSILON])
	lines.append("")
	lines.append_array(_format_frozen_stretches_section("LIVE", live_capped))
	lines.append_array(_format_frozen_stretches_section("REPLAY", replay_capped))
	lines.append("(A frozen stretch on REPLAY with no similar-length, similar-tick stretch on LIVE -- especially one where alive=False/enabled=False/dead_ctr>0 -- means the replay got stuck in the disabled/respawn-hold state at a point live sailed straight through. That's a real desync, not a settling artifact.)")
	return "\n".join(lines)


func _write_key_event_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/key_event_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path
