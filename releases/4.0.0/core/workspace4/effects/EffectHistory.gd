extends Reference
const LIMIT = 100
var past = []
var future = []
var current = {}
var token = ""
var at = 0
func reset(document):
	current = document.duplicate(true)
	past.clear()
	future.clear()
	token = ""
func commit(document, gesture = "") -> bool:
	if JSON.print(document)==JSON.print(current): return false
	var now = OS.get_ticks_msec()
	if gesture.empty() or gesture!=token or now-at>500:
		past.append(current.duplicate(true))
		if past.size()>LIMIT: past.pop_front()
	current = document.duplicate(true)
	future.clear()
	token = gesture
	at = now
	return true
func end_gesture(): token = ""
func undo() -> Dictionary:
	if past.empty(): return current.duplicate(true)
	future.append(current.duplicate(true))
	current = past.pop_back()
	token = ""
	return current.duplicate(true)
func redo() -> Dictionary:
	if future.empty(): return current.duplicate(true)
	past.append(current.duplicate(true))
	current = future.pop_back()
	token = ""
	return current.duplicate(true)
