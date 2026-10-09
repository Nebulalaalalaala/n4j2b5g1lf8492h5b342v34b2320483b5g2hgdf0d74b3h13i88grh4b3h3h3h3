extends Node
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")

# Presentation only: the ledger has already committed the receipt. Never writes
# XP, rank thresholds, player state or settings. Shared by both result views.
signal beat(info)
signal cue(key, pitch)
signal finished
var ui
var definitions
var widgets = {}
var receipt = []
var before = 0
var total = 0
var rank = {}
var done = false
var tween
var last_tick = -1

static func rank_steps(defs, start, end) -> Array:
	var out = []
	var cursor = int(start)
	while cursor < int(end) and out.size() < 60:
		var current = defs.rank_at(cursor)
		var stop = min(int(end), int(current.next_xp))
		out.append({"rank": current, "from": cursor, "to": stop})
		cursor = stop
	# Huge historical receipts still end at the exact total without a long show.
	if cursor < int(end):
		out.append({"rank": defs.rank_at(int(end)), "from": int(end), "to": int(end)})
	return out

func configure(design, defs, awards, start, controls):
	ui = design
	definitions = defs
	receipt = awards
	before = max(0, int(start))
	widgets = controls
	for info in Data.reward_rows(receipt): total += int(info.amount)

func start(animate = true):
	_set_rank(definitions.rank_at(before))
	_progress(before)
	_count(0)
	if ui.reduced_motion or not animate:
		complete()
		return
	tween = Tween.new()
	add_child(tween)
	var at = 0.35
	var counted = 0
	for info in Data.reward_rows(receipt):
		tween.interpolate_callback(self, at, "_beat", info)
		tween.interpolate_method(self, "_count", counted, counted + int(info.amount), 0.24, Tween.TRANS_QUAD, Tween.EASE_OUT, at)
		counted += int(info.amount)
		at += 0.32
	# Let the final daily multiplier settle before filling the rank bar.
	at += 0.12
	var steps = rank_steps(definitions, before, before + total)
	var duration = min(0.65, 1.8 / max(1, steps.size()))
	for step in steps:
		tween.interpolate_callback(self, at, "_set_rank", step.rank)
		tween.interpolate_method(self, "_progress", step.from, step.to, duration, Tween.TRANS_CUBIC, Tween.EASE_OUT, at + 0.01)
		at += duration + 0.14 # visibly finish the old rank before revealing the next
		tween.interpolate_callback(self, at, "_crossed", step)
	tween.interpolate_callback(self, at + 0.04, "complete")
	tween.start()

func _beat(info):
	if is_instance_valid(widgets.get("status")):
		widgets.status.text = str(info.name)
		widgets.status.show()
	emit_signal("beat", info)
	if info.key != "sweep": emit_signal("cue", "tick", 1.0 + float(total_for_key(info.key)) / max(1, total) * 0.2)

func total_for_key(key):
	for info in Data.reward_rows(receipt):
		if info.key == key: return int(info.amount)
	return 0

func _count(value):
	if is_instance_valid(widgets.get("count")): widgets.count.text = ui.xp_text(int(value))
	# Fixed increments rather than depending on an arbitrary XP modulo per frame.
	var tick = int(float(value) / max(1, total) * 18)
	if tick > last_tick and int(value) < total:
		last_tick = tick
		emit_signal("cue", "tick", 1.0 + float(value) / max(1, total) * 0.25)

func _set_rank(value):
	if int(rank.get("id", -1)) == int(value.id): return
	rank = value
	if is_instance_valid(widgets.get("stage")):
		for child in widgets.stage.get_children():
			widgets.stage.remove_child(child)
			child.queue_free()
		ui.badge(widgets.stage, rank, int(widgets.get("badge_size", 96)), int(widgets.get("badge_size", 96)) > 100)
	if is_instance_valid(widgets.get("name")): widgets.name.text = str(rank.name).to_upper()
	if is_instance_valid(widgets.get("bar")):
		widgets.bar.fill = ui.league(rank).base
		widgets.bar.ratio = 0.0

func _progress(value):
	var span = max(1, int(rank.next_xp) - int(rank.xp))
	if is_instance_valid(widgets.get("bar")): widgets.bar.ratio = float(value - int(rank.xp)) / span
	if is_instance_valid(widgets.get("caption")):
		widgets.caption.text = "%s XP to %s" % [ui.thousands(max(0, int(rank.next_xp) - int(value))), definitions.rank_at(int(rank.next_xp)).name]
	if is_instance_valid(widgets.get("numbers")):
		widgets.numbers.text = "%s / %s XP" % [ui.thousands(int(value) - int(rank.xp)), ui.thousands(span)]

func _crossed(step):
	if int(step.to) < int(step.rank.next_xp): return
	_set_rank(definitions.rank_at(int(step.to)))
	_progress(step.to)
	var mode = str(widgets.get("celebrations", "all"))
	if mode == "off" or (mode == "leagues" and step.rank.art == rank.art): return
	emit_signal("cue", "rankup", 1.0)
	if is_instance_valid(widgets.get("stage")): ui.burst(widgets.stage)

func complete():
	if done: return
	if is_instance_valid(tween): tween.stop_all()
	_set_rank(definitions.rank_at(before + total))
	_progress(before + total)
	if is_instance_valid(widgets.get("count")): widgets.count.text = ui.xp_text(total)
	if is_instance_valid(widgets.get("status")): widgets.status.hide()
	done = true
	emit_signal("finished")
