extends Reference

# Bots built on TASStudio.probe(): every attempt runs the real game ahead
# with drawing off, then rewinds.
#  - Jump window: for the next frames, does pressing jump there survive?
#  - Stitch: joins the takes of each marked section into a candidate run,
#    working from the real end state of what came before. Where a take doesn't
#    line up it tries short bridges (hold right or left, wait, small jump,
#    skip a few frames). The working run is copied first; a failure or Stop
#    puts it back exactly, and a finished candidate waits for Keep or Revert.
#  - Route finder: beam search over short input chunks toward a target spot.

const CHUNK = 6
const STITCH_BUDGET_MS = 90000
const BEAM = 5
const ACTIONS = ["R", "RJ", "", "L", "LJ", "J", "RD>", "LD<", "RJD>"]

var studio = null
var task = {}
var jump_marks = null
var jump_results = []
var status = ""
var candidate = {}   # finished stitch waiting for Keep / Revert

signal progress


func setup(owner) -> void:
	studio = owner


func busy() -> bool:
	return not task.empty()


func cancel() -> void:
	if task.empty():
		return
	if task.kind == "stitch":
		_stitch_fail("Stopped -- your run is back as it was")
		return
	if task.kind == "finish":
		_finish_end("Stopped -- the run is back as it was", true)
		return
	task = {}
	studio.hold_render = false
	status = "Stopped"
	emit_signal("progress")


func _begin(kind: String, data: Dictionary) -> bool:
	if busy() or studio.busy() or studio.ready_for_studio() != "":
		return false
	studio.sync()
	task = data
	task["kind"] = kind
	task["began"] = OS.get_ticks_msec()
	studio.hold_render = true
	return true


func _finish(text: String) -> void:
	task = {}
	studio.hold_render = false
	studio._restore_render()
	status = text
	studio.message = text
	emit_signal("progress")
	studio.emit_signal("changed")


func _frames(sig: String, count: int) -> Array:
	var result = []
	for _i in count:
		result.append(studio.inputs_frame(sig))
	return result


# ---------------------------------------------------------------- jump window

func jump_window(width := 16, hold := 10, look := 75) -> bool:
	var start = studio.cursor
	var base = studio._range(studio.full, start, start + look)
	var buffered = {}
	for entry in studio.tool.BUFFERABLE_ACTIONS:
		buffered[entry[1]] = bool(studio.tool._buffered_actions.get(entry[1], false))
	while base.size() < look:
		base.append(buffered if base.empty() else base[base.size() - 1])
	if not _begin("jump", {"start": start, "base": base, "width": width, "hold": hold, "index": -1, "results": []}):
		return false
	jump_results = []
	_jump_next(null)
	return true


func _jump_next(result) -> void:
	if task.empty() or task.kind != "jump":
		return
	if result != null:
		var offset = task.index
		var at = result.positions[offset] if offset >= 0 and offset < result.positions.size() else Vector2.ZERO
		task.results.append({"offset": offset, "result": _jump_grade(result, offset), "position": at, "path": result.positions})
	task.index += 1
	status = "Jump window %d/%d" % [task.index, task.width]
	emit_signal("progress")
	if task.index >= task.width:
		jump_results = task.results
		var counts = {"landed": 0, "survived": 0, "died": 0}
		for entry in jump_results:
			counts[entry.result] += 1
		_draw_jump_marks()
		_finish("Jump window: %d land, %d only survive, %d die (%d frames ahead). Click a dot to see its path." % [counts.landed, counts.survived, counts.died, task.base.size()])
		return
	var inputs = []
	for index in task.base.size():
		var frame = task.base[index].duplicate()
		frame.erase(studio.STATE_KEY)
		frame.erase(studio.EDITED_KEY)
		frame[studio.JUMP] = index >= task.index and index < task.index + task.hold
		inputs.append(frame)
	if not studio.probe(task.start, inputs, self, "_jump_next", {"ground": []}):
		_finish("Jump window stopped")


# landed: left the ground after the press and came down again, alive.
# survived: alive at the end of the look-ahead but no landing seen.
func _jump_grade(result: Dictionary, offset: int) -> String:
	if result.dead:
		return "died"
	var ground = result.get("ground", [])
	var airborne = false
	for index in range(max(offset, 0), ground.size()):
		if not ground[index]:
			airborne = true
		elif airborne:
			return "landed"
	return "survived"


func pick_jump(point: Vector2) -> bool:
	for entry in jump_results:
		if entry.position.distance_to(point) <= 10.0:
			studio.path_points = entry.path
			studio._draw_path()
			studio.message = "Path for jumping at +%d (%s)" % [entry.offset, entry.result]
			studio.emit_signal("changed")
			return true
	return false


func _draw_jump_marks() -> void:
	var player = studio.tool._get_local_player()
	if player == null or player.get_parent() == null:
		return
	if jump_marks == null or not is_instance_valid(jump_marks):
		jump_marks = JumpMarks.new()
		player.get_parent().add_child(jump_marks)
	jump_marks.results = jump_results
	jump_marks.update()


func clear_jump_marks() -> void:
	jump_results = []
	if jump_marks != null and is_instance_valid(jump_marks):
		jump_marks.queue_free()
	jump_marks = null


class JumpMarks extends Node2D:
	var results = []

	func _ready() -> void:
		z_index = 3995

	func _draw() -> void:
		for entry in results:
			var colour = Color("ff7f8a")
			if entry.get("result", "") == "landed":
				colour = Color("7fe0b4")
			elif entry.get("result", "") == "survived":
				colour = Color("ffc46b")
			draw_circle(entry.position, 6.0, Color(colour.r, colour.g, colour.b, 0.9))
			draw_arc(entry.position, 9.0, 0.0, TAU, 16, Color(0, 0, 0, 0.5), 2.0, true)


# ---------------------------------------------------------------- stitching

func stitch() -> bool:
	if not candidate.empty():
		studio.message = "Keep or revert the stitched run first"
		studio.emit_signal("changed")
		return false
	var order = []
	for index in studio.sections.size():
		var section = studio.sections[index]
		if section.best >= 0 and studio.gate_for(section) != null:
			order.append(index)
	if order.empty():
		studio.message = "Record at least one take in a section first"
		studio.emit_signal("changed")
		return false
	var first = studio.sections[order[0]].start
	if studio.snap_for(first) == null:
		studio.message = "Re-play up to the first section before stitching"
		studio.emit_signal("changed")
		return false
	var gates = []
	for index in order:
		gates.append(studio.gate_for(studio.sections[index]))
	if studio.records != null:
		studio.records.last_signature = ""
		studio.records.save_recovery()
	var before = studio.full.size()
	var original = studio.snapshot_project()
	if not _begin("stitch", {"order": order, "gates": gates, "step": 0, "cursor": first, "candidates": [], "candidate": -1, "best": null, "joined": 0, "original": original, "first": first, "frames_before": before}):
		return false
	_stitch_section()
	return true


func _bridges() -> Array:
	var list = [[[], 0]]
	for count in [1, 2, 3, 5, 8]:
		list.append([_frames("R", count), 0])
	for count in [1, 2, 3, 5]:
		list.append([_frames("L", count), 0])
	for count in [1, 2, 3, 5]:
		list.append([_frames("", count), 0])
	for count in [2, 4]:
		list.append([_frames("RJ", count), 0])
		list.append([_frames("LJ", count), 0])
	for skip in [1, 2, 3, 5]:
		list.append([[], skip])
	return list


func _stitch_section() -> void:
	if task.empty() or task.kind != "stitch":
		return
	if task.step >= task.order.size():
		_stitch_done()
		return
	var section = studio.sections[task.order[task.step]]
	var takes = section.takes.duplicate()
	takes.sort_custom(self, "_take_order")
	# The take the user put into the run goes first.
	for take in section.takes:
		if int(take.id) == int(section.get("used", 0)):
			takes.erase(take)
			takes.push_front(take)
	# Inputs between the previous section's end and this section's start
	# stay as recorded; the take follows them.
	var gap = []
	for frame in studio._range(studio.full, task.cursor, section.start):
		var copy = frame.duplicate()
		copy.erase(studio.STATE_KEY)
		copy.erase(studio.EDITED_KEY)
		gap.append(copy)
	var candidates = []
	for take in takes.slice(0, min(3, takes.size()) - 1):
		for bridge in _bridges():
			var inputs = gap + bridge[0] + take.inputs.slice(min(bridge[1], take.inputs.size() - 1), take.inputs.size() - 1)
			candidates.append(inputs + _frames(_last_sig(inputs), 30))
	task.candidates = candidates
	task.candidate = -1
	task.best = null
	_stitch_try(null)


func _take_order(a, b) -> bool:
	return a.frames < b.frames


func _last_sig(inputs: Array) -> String:
	return studio.signature(inputs[inputs.size() - 1]) if not inputs.empty() else "R"


func _stitch_try(result) -> void:
	if task.empty() or task.kind != "stitch":
		return
	if result != null and not result.dead and result.reached >= 0:
		if task.best == null or result.reached < task.best.frames:
			task.best = {"frames": result.reached, "inputs": task.candidates[task.candidate].slice(0, max(result.reached - 1, 0))}
		if task.candidate == 0:
			task.candidate = task.candidates.size() # the take fits as-is: done
	task.candidate += 1
	if OS.get_ticks_msec() - int(task.began) > STITCH_BUDGET_MS:
		_stitch_fail("No connection found within the time limit at section %d -- your run is back as it was" % (task.order[task.step] + 1))
		return
	status = "Stitching section %d/%d · try %d of %d" % [task.step + 1, task.order.size(), min(task.candidate + 1, task.candidates.size()), task.candidates.size()]
	emit_signal("progress")
	if task.candidate >= task.candidates.size():
		_stitch_apply()
		return
	# Success needs the section's finish line crossed the right way and a
	# few frames survived after it, starting from the joined run so far.
	if not studio.probe(task.cursor, task.candidates[task.candidate], self, "_stitch_try", {"gate": task.gates[task.step], "gate_left": 0}):
		_stitch_fail("Stitching stopped -- your run is back as it was")


func _stitch_apply() -> void:
	var section_index = task.order[task.step]
	if task.best == null:
		_stitch_fail("No connection found for section %d -- your run is back as it was. Try another take or a later section start." % (section_index + 1))
		return
	var section = studio.sections[section_index]
	var inputs = task.best.inputs
	studio.replace_frames(task.cursor, section.end, inputs)
	section = studio.sections[section_index]
	section.start = min(section.start, task.cursor)
	section.end = task.cursor + inputs.size()
	task.cursor = section.end
	task.joined += 1
	task.step += 1
	# Replay the joined part so the next section starts from a real state.
	studio.hold_render = false
	if not studio.replay_to(task.cursor):
		_stitch_fail("Stitching stopped while re-playing -- your run is back as it was")
		return
	task.waiting_replay = true


# Called by the studio after any job; continues stitching after a re-play.
func on_job_finished() -> void:
	if not task.empty() and task.kind == "finish" and task.get("waiting_replay", false):
		task.waiting_replay = false
		_finish_replayed()
		return
	if task.empty() or task.kind != "stitch" or not task.get("waiting_replay", false):
		return
	task.waiting_replay = false
	studio.hold_render = true
	if studio.verified < task.cursor:
		_stitch_fail("The joined run died while re-playing -- your run is back as it was")
		return
	call_deferred("_stitch_section")


func _stitch_fail(text: String) -> void:
	var original = task.get("original", {})
	_finish(text)
	if not original.empty():
		if not studio.job.empty():
			studio.pending_restore = original # put back once the running job has ended
		else:
			studio.restore_project(original)
	for section in studio.sections:
		section["broken"] = false
	studio.message = text
	studio.emit_signal("changed")


# Every joined section was re-played from the real start of the run. The
# candidate now waits for Keep or Revert; one undo also takes it back later.
func _stitch_done() -> void:
	var original = task.original
	var end_at = task.cursor
	var change = studio.full.size() - int(task.frames_before)
	studio.collapse_undo(original, task.first)
	candidate = {"original": original, "change": change}
	_finish("Stitched %d section%s (%+d frames, checked by re-playing). Keep or revert it." % [task.joined, "" if task.joined == 1 else "s", change])
	studio.replay_to(end_at)


func keep_candidate() -> void:
	candidate = {}
	studio.message = "Kept the stitched run"
	studio.touch()
	studio.emit_signal("changed")


func revert_candidate() -> void:
	if candidate.empty() or studio.busy():
		return
	var original = candidate.original
	candidate = {}
	studio.restore_project(original)
	studio.message = "Back to the run before stitching"
	studio.emit_signal("changed")


# ---------------------------------------------------------------- route finder

func find_route(target_frame: int) -> bool:
	var start = studio.cursor
	var target = studio.position_at(target_frame)
	if target == null:
		studio.message = "The target must be a frame that has been played"
		studio.emit_signal("changed")
		return false
	var limit = max(60, int((target_frame - start) * 1.6))
	if not _begin("route", {"start": start, "target": target, "target_frame": target_frame, "limit": limit, "beam": [{"inputs": [], "snap": null, "distance": INF}], "next": [], "queue": [], "depth": 0, "found": null}):
		return false
	_route_depth()
	return true


func _route_depth() -> void:
	if task.empty() or task.kind != "route":
		return
	if task.found != null:
		_route_apply(task.found)
		return
	if task.depth * CHUNK >= task.limit or task.beam.empty():
		_finish("No route found -- try a closer target")
		return
	task.queue = []
	for node in task.beam:
		for action in ACTIONS:
			task.queue.append([node, action])
	task.next = []
	task.depth += 1
	_route_next(null)


func _route_next(result) -> void:
	if task.empty() or task.kind != "route":
		return
	if result != null:
		var node = task.current[0]
		var chunk = _frames(task.current[1], CHUNK)
		if not result.dead:
			if result.reached >= 0:
				var inputs = node.inputs + chunk.slice(0, max(result.reached - 1, 0))
				if task.found == null or inputs.size() < task.found.size():
					task.found = inputs
			elif not result.end_snap.empty():
				var distance = result.end_position.distance_to(task.target)
				task.next.append({"inputs": node.inputs + chunk, "snap": result.end_snap, "distance": distance, "position": result.end_position})
	if task.queue.empty():
		_route_prune()
		return
	task.current = task.queue.pop_front()
	status = "Route finder · depth %d · %d left" % [task.depth, task.queue.size()]
	emit_signal("progress")
	var extra = {"target": task.target, "radius": 16.0}
	if task.current[0].snap != null:
		extra["from_snap"] = task.current[0].snap
	if not studio.probe(task.start, _frames(task.current[1], CHUNK), self, "_route_next", extra):
		_finish("Route finder stopped")


func _route_prune() -> void:
	task.next.sort_custom(self, "_closer")
	var kept = []
	for node in task.next:
		var similar = false
		for other in kept:
			if other.position.distance_to(node.position) < 6.0:
				similar = true
				break
		if not similar:
			kept.append(node)
		if kept.size() >= BEAM:
			break
	task.beam = kept
	call_deferred("_route_depth")


func _closer(a, b) -> bool:
	return a.distance < b.distance


func _route_apply(inputs: Array) -> void:
	var start = task.start
	var target_frame = task.target_frame
	var saved = (target_frame - start) - inputs.size()
	_finish("Route found: %d frames (%+d vs the current run)" % [inputs.size(), -saved])
	studio.replace_frames(start, target_frame, inputs)
	studio.replay_to(start + inputs.size())


# ---------------------------------------------------------------- finish a section

# Builds the fastest try of a section into the run. The rest of the run is
# never removed: the try goes in, a short bridge is searched so the next
# section's original inputs still reach its stop block, then the rest of the
# run is re-played (on screen, sped up) to check it still holds together.
# Builds the fastest try of a section into the run so the rest of the run
# carries on as before. A try never ends in exactly the same body state as
# the run did, so the bot looks for a join: it plays the try with a few
# short bridges, compares where the Goober ends up (position, speed, on the
# ground or not) with every moment of the old run just after the section,
# and joins onto the old run at the closest match. The best joins are then
# checked by playing on to the next section's stop block. Nothing after the
# section is removed.
const JOIN_WINDOW_BEFORE = 30
const JOIN_WINDOW_AFTER = 120
const JOIN_CHECKS = 6
const NO_JOIN = "This try couldn't be joined onto the run without breaking a later part, so the run is unchanged. Your try is kept -- try ending closer to the arrow in the stop block."

func finish_section(index: int) -> bool:
	if busy() or index < 0 or index >= studio.sections.size():
		return false
	var section = studio.sections[index]
	# End practice properly first: puts the run back to the section start
	# with everything after it kept.
	if not studio.practice.empty():
		studio.stop_practice()
	var current = studio.section_frames_now(section)
	if section.best < 0 or int(section.takes[section.best].frames) >= current:
		studio.instant_seek(section.start, true, false)
		studio.message = "No faster try than the run -- nothing changed"
		studio.emit_signal("changed")
		return false
	var take = section.takes[section.best]
	for other in studio.sections:
		other["broken"] = false
	var original = studio.snapshot_project()
	if studio.records != null:
		studio.records.last_signature = ""
		studio.records.save_recovery()
	var next_zone = null
	var next_end = -1
	# Joins are checked over the next two sections, so a join that only
	# just survives the first one doesn't count.
	var check_index = min(index + 2, studio.sections.size() - 1)
	if check_index > index:
		next_zone = studio.zone_for(studio.sections[check_index])
		next_end = int(studio.sections[check_index].end)
	if not _begin("finish", {"index": index, "take": take, "zone": next_zone, "next_end": next_end, "parts": [], "part": -1, "matches": [], "check": -1, "original": original, "old_end": int(section.end), "saved": current - int(take.frames)}):
		return false
	studio.hold_render = false
	studio.show_jobs = true
	if next_zone == null:
		_finish_commit(take.inputs, int(section.end))
		return true
	for bridge in _bridges():
		var part = take.inputs.slice(min(bridge[1], take.inputs.size() - 1), take.inputs.size() - 1) + bridge[0]
		if part.size() >= 2:
			task.parts.append(part)
	_finish_part(null)
	return true


# Old-run states near the section end: [frame, state].
func _join_targets() -> Array:
	var targets = []
	var section_start = int(studio.sections[task.index].start)
	var first = max(section_start + 1, int(task.old_end) - JOIN_WINDOW_BEFORE)
	var last = min(int(task.old_end) + JOIN_WINDOW_AFTER, min(studio.verified, studio.full.size() - 1))
	for frame_index in range(first, last + 1):
		var frame = studio.full[frame_index]
		var state = frame.get(studio.STATE_KEY) if typeof(frame) == TYPE_DICTIONARY else null
		if typeof(state) == TYPE_DICTIONARY and state.has("position"):
			targets.append([frame_index, state])
	return targets


static func _grounded_state(state: Dictionary) -> bool:
	var normal = state.get("ground_normal")
	return normal is Vector2 and normal != Vector2.ZERO


# How far apart two body states are, in pixels-ish.
static func state_distance(a: Dictionary, b: Dictionary) -> float:
	var distance = a.get("position", Vector2.ZERO).distance_to(b.get("position", Vector2.ZERO))
	distance += a.get("linear_velocity", Vector2.ZERO).distance_to(b.get("linear_velocity", Vector2.ZERO)) * 0.03
	if _grounded_state(a) != _grounded_state(b):
		distance += 25.0
	if a.has("facing_dir") and b.has("facing_dir") and bool(a.facing_dir) != bool(b.facing_dir):
		distance += 4.0
	if a.has("dash_cooldown") and b.has("dash_cooldown"):
		distance += abs(float(a.dash_cooldown) - float(b.dash_cooldown)) * 2.0
	return distance


# Step 1: play the try with each bridge and note how close its end state
# comes to the old run.
func _finish_part(result) -> void:
	if task.empty() or task.kind != "finish":
		return
	if result != null and not result.dead and not result.end_snap.empty():
		var part = task.parts[task.part]
		var prefix = part.slice(0, part.size() - 2)
		for target in task.targets:
			var distance = state_distance(result.end_snap, target[1])
			if distance <= 48.0:
				task.matches.append({"distance": distance, "prefix": prefix, "join": target[0]})
	if task.part < 0:
		task.targets = _join_targets()
	task.part += 1
	status = "Matching the end of the try to the run (%d/%d)" % [min(task.part + 1, task.parts.size()), task.parts.size()]
	emit_signal("progress")
	if task.part >= task.parts.size():
		task.matches.sort_custom(self, "_closer_match")
		if not task.matches.empty():
			print("[Sections] join: %d candidates, closest %.1f px at frame %d" % [task.matches.size(), task.matches[0].distance, task.matches[0].join])
		else:
			print("[Sections] join: no close match")
		_finish_check(null)
		return
	var section = studio.sections[task.index]
	if not studio.probe(section.start, task.parts[task.part], self, "_finish_part"):
		_finish_end("Couldn't test the join -- the run is unchanged", true)


func _closer_match(a, b) -> bool:
	return a.distance < b.distance


# Step 2: check the closest joins by playing on to the next stop block.
func _finish_check(result) -> void:
	if task.empty() or task.kind != "finish":
		return
	if result != null and not result.dead and result.reached >= 0:
		var pick = task.matches[task.check]
		_finish_commit(pick.prefix, int(pick.join))
		return
	task.check += 1
	if task.check >= min(JOIN_CHECKS, task.matches.size()):
		# Never keep a run that breaks: leave it as it was.
		_finish_end(NO_JOIN, true)
		return
	var pick = task.matches[task.check]
	status = "Checking join %d of %d" % [task.check + 1, min(JOIN_CHECKS, task.matches.size())]
	emit_signal("progress")
	var tail = []
	for frame in studio._range(studio.full, int(pick.join), int(task.next_end) + 30):
		var copy = frame.duplicate()
		copy.erase(studio.STATE_KEY)
		copy.erase(studio.EDITED_KEY)
		tail.append(copy)
	var section = studio.sections[task.index]
	if not studio.probe(section.start, pick.prefix + tail, self, "_finish_check", {"zone": task.zone}):
		_finish_end("Couldn't test the join -- the run is unchanged", true)


# Replace the section (and the part of the old run the join skipped or
# repeats) with `part`, then re-play the whole rest of the run.
func _finish_commit(part: Array, join: int) -> void:
	var section = studio.sections[task.index]
	var start = int(section.start)
	studio.replace_frames(start, join, part)
	section = studio.sections[task.index]
	section.end = start + part.size()
	section["improved"] = true
	# Frames the join took from (or gave to) the next section count for this one.
	var moved = join - int(task.old_end)
	section["base"] = int(section.get("base", int(task.old_end) - start)) + moved
	task.saved = int(section.base) - part.size()
	if task.index + 1 < studio.sections.size():
		var next = studio.sections[task.index + 1]
		next.start = section.end
		next["base"] = int(next.get("base", int(next.end) - int(next.start))) - moved
	studio.collapse_undo(task.original, start)
	task.waiting_replay = true
	studio.replay_speed = 12.0
	status = "Building it into the run"
	emit_signal("progress")
	if not studio.replay_to(studio.full.size()):
		_finish_end("Couldn't re-play the run -- it is back as it was", true)


func _finish_replayed() -> void:
	studio.replay_speed = studio.FAST
	var broken = -1
	for index in studio.sections.size():
		var section = studio.sections[index]
		var ok = int(section.end) <= studio.verified
		section["broken"] = not ok and broken < 0 and int(section.start) <= studio.verified
		if section.broken:
			broken = index
	if broken >= 0:
		# The whole re-play found a problem the short check missed: put the
		# run back and try the next closest join, or give up cleanly.
		print("[Sections] join at frame %d breaks section %d, trying the next one" % [int(task.matches[task.check].join) if task.check < task.matches.size() else -1, broken + 1])
		studio.restore_project(task.original)
		for section in studio.sections:
			section["broken"] = false
		if task.check + 1 < min(JOIN_CHECKS, task.matches.size()):
			call_deferred("_finish_check", null)
		else:
			_finish_end(NO_JOIN, false)
	else:
		_finish_end("Section %d is %.2fs faster and the rest of the run still works" % [task.index + 1, task.saved / 60.0], false)


func _finish_end(text: String, revert: bool) -> void:
	var original = task.get("original", {})
	for section in studio.sections:
		section["broken"] = false
	studio.show_jobs = false
	studio.replay_speed = studio.FAST
	_finish(text)
	if revert and not original.empty():
		if not studio.job.empty():
			studio.pending_restore = original
		else:
			studio.restore_project(original)
	for section in studio.sections:
		section["broken"] = false
	studio.message = text
	studio.emit_signal("changed")
