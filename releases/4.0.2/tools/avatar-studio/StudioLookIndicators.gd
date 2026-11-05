extends Node
# One light, visible-only scan for the whole Look grid. A remembered selection
# is not enough: custom editing must remove the marker from an outdated Look.
var studio
var entries = []
var elapsed = 0.0
var last_id = "__unset"
var last_signature = ""

func _process(delta):
	if not is_instance_valid(studio.looks_grid) or not studio.looks_grid.is_visible_in_tree(): return
	elapsed += delta
	if elapsed < .25: return
	elapsed = 0.0
	refresh()

func refresh():
	var state = studio.capture()
	var signature = JSON.print(state)+studio.current_look
	if signature==last_signature: return
	last_signature = signature
	var equipped = ""
	for look in studio.library.looks:
		if studio.same_state(look.state,state):
			equipped = str(look.id)
			if equipped==studio.current_look: break
	if equipped == last_id: return
	last_id = equipped
	for entry in entries:
		if not is_instance_valid(entry.panel): continue
		var selected = str(entry.id)==equipped
		entry.panel.add_stylebox_override("panel",studio.style(studio.PANEL,studio.ACCENT if selected else studio.LINE))
		entry.label.text = "EQUIPPED" if selected else "SAVED LOOK"
		entry.label.add_color_override("font_color",studio.ACCENT if selected else studio.DIM)
		entry.button.text = "Equipped" if selected else "Equip"
		entry.button.disabled = selected
