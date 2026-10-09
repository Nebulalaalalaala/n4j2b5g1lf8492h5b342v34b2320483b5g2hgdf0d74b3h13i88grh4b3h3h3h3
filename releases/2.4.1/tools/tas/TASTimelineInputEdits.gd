extends Reference

# Differential history: one gesture, one undo. Never clone the whole recording
# per pointer event; changing inputs invalidates their old recorded trajectory.
const EDITED_KEY = "__tas_input_unverified"
const LIMIT = 128
const ACTIONS = ["player_up", "player_dash", "player_left", "player_right", "__tas_dash_direction"]
var history = []
var future = []
var pending = {}

func clear() -> void:
	history.clear()
	future.clear()
	pending.clear()

func apply(frames: Array, action: String, first: int, last: int, value: bool) -> bool:
	if not action in ACTIONS or frames.empty(): return false
	var changed = false
	for index in range(max(0, min(first, last)), min(frames.size() - 1, max(first, last)) + 1):
		var frame: Dictionary = frames[index]
		# Missing dash direction means right in the existing format/editor.
		var default_value = action == "__tas_dash_direction"
		if bool(frame.get(action, default_value)) == value: continue
		var key = str(index) + ":" + action
		if not pending.has(key):
			pending[key] = {"index": index, "action": action, "had": frame.has(action), "old": frame.get(action), "marked": frame.has(EDITED_KEY), "old_mark": frame.get(EDITED_KEY), "value": value}
		else: pending[key].value = value
		frame[action] = value
		frame[EDITED_KEY] = true
		changed = true
	return changed

func finish() -> bool:
	if pending.empty(): return false
	history.append(pending.values())
	if history.size() > LIMIT: history.pop_front()
	future.clear()
	pending.clear()
	return true

func undo(frames: Array) -> bool:
	finish()
	if history.empty(): return false
	var changes = history.pop_back()
	# Reverse order also restores the marker correctly when several actions
	# changed on the same frame in one transaction.
	for index in range(changes.size() - 1, -1, -1):
		var change: Dictionary = changes[index]
		if change.index >= frames.size():
			clear()
			return false
		var frame: Dictionary = frames[change.index]
		if change.had: frame[change.action] = change.old
		else: frame.erase(change.action)
		if change.marked: frame[EDITED_KEY] = change.old_mark
		else: frame.erase(EDITED_KEY)
	future.append(changes)
	return true

func redo(frames: Array) -> bool:
	if future.empty(): return false
	var changes = future.pop_back()
	for change in changes:
		if change.index >= frames.size():
			clear()
			return false
		frames[change.index][change.action] = change.value
		frames[change.index][EDITED_KEY] = true
	history.append(changes)
	return true
