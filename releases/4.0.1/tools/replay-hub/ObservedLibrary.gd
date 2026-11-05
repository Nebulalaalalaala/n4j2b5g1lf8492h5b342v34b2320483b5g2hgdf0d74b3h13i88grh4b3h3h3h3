extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")
signal refreshed

var hub
var service
var store
var message
var files_picker
var rounds_picker
var participants
var viewer
var slider
var research_label
var mode_picker
var outcome_picker
var date_picker
var delete_dialog
var file_dialog
var data = {}
var entries = []
var names = []
var selected_file = ""
var round_index = 0
var sort_picker
var runs_picker
var research_rows = []
var live_camera = null

func configure(owner):
	hub = owner
	var base = get_script().resource_path.get_base_dir()
	service = load(base.plus_file("MatchObserver.gd")).new()
	service.tool = hub.tas_tool
	add_child(service)
	store = service.store
	add_constant_override("separation", 8)
	label("OBSERVED CAPTURES · LOCAL MAP RESEARCH")
	var notice = label("Public spectator join unavailable: the server admission API is not exposed.\nThese are partial client-position observations, not original-input replays or verified records.")
	notice.autowrap = true
	var actions = HBoxContainer.new()
	add_child(actions)
	button(actions, "Record spectator", "record")
	button(actions, "Freecam", "open_camera")
	button(actions, "Stop / save", "stop")
	button(actions, "Import capture", "import_picker")
	button(actions, "Refresh", "refresh")
	message = label("")
	message.autowrap = true
	var pickers = HBoxContainer.new()
	add_child(pickers)
	files_picker = OptionButton.new()
	style_picker(files_picker)
	files_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files_picker.connect("item_selected", self, "choose_file")
	pickers.add_child(files_picker)
	rounds_picker = OptionButton.new()
	style_picker(rounds_picker)
	rounds_picker.connect("item_selected", self, "choose_round")
	pickers.add_child(rounds_picker)
	var playback_row = HBoxContainer.new()
	add_child(playback_row)
	participants = ItemList.new()
	participants.add_font_override("font", hub._small_font)
	participants.select_mode = ItemList.SELECT_MULTI
	participants.rect_min_size = Vector2(190, 170)
	participants.connect("multi_selected", self, "selection_changed")
	playback_row.add_child(participants)
	viewer = load(base.plus_file("ObservedPlayback.gd")).new()
	viewer.name_font = hub._small_font
	viewer.rect_min_size = Vector2(220, 170)
	viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback_row.add_child(viewer)
	var controls = HBoxContainer.new()
	add_child(controls)
	button(controls, "Play / pause", "play")
	button(controls, "Hotspots", "toggle_overview").hint_tooltip = "Pulse inferred death/respawn locations from the entire round. Missing observations and final eliminations are excluded. These are not verified deaths."
	slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.step = 0.01
	slider.connect("value_changed", self, "seek")
	controls.add_child(slider)
	button(controls, "Save selected runs", "extract")
	button(controls, "Delete", "confirm_delete")
	label("Position dots and schematic object bounds only. Gaps stay blank; times are approximate.")
	var filters = HBoxContainer.new()
	add_child(filters)
	mode_picker = picker(filters, ["All match types", "8P", "16P", "32P", "Elimination", "unknown"])
	outcome_picker = picker(filters, ["All results", "finish", "dnf", "unknown"])
	date_picker = picker(filters, ["All dates", "Last 7 days", "Last 30 days", "Last year"])
	sort_picker = picker(filters, ["All runs", "Fastest finish", "Median finish", "Slowest finish"])
	runs_picker = OptionButton.new()
	style_picker(runs_picker)
	runs_picker.connect("item_selected", self, "choose_research_run")
	add_child(runs_picker)
	research_label = label("")
	research_label.autowrap = true
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.dialog_text = "Delete this local observed capture? This cannot be undone."
	delete_dialog.connect("confirmed", self, "delete_capture")
	add_child(delete_dialog)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.filters = PoolStringArray(["*.json ; Observed capture JSON"])
	file_dialog.connect("file_selected", self, "import_capture")
	add_child(file_dialog)
	message.text = "Open Observed or press Refresh to load local captures."

func label(text):
	var result = hub._make_label(text, hub._small_font, hub.DIM)
	result.autowrap = true
	result.rect_min_size.y = 24
	add_child(result)
	return result

func button(parent, text, method):
	var result = hub._make_button(text, hub.BLUE, 13)
	result.rect_min_size.y = 36
	result.connect("pressed", self, method)
	parent.add_child(result)
	return result

func picker(parent, values):
	var result = OptionButton.new()
	style_picker(result)
	for value in values:
		result.add_item(value)
	result.connect("item_selected", self, "research")
	parent.add_child(result)
	return result

func style_picker(control):
	control.add_font_override("font", hub._small_font)
	control.get_popup().add_font_override("font", hub._small_font)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("24333d")
		style.content_margin_left = 8
		style.content_margin_right = 12
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		control.add_stylebox_override(state, style)
	var arrow = GradientTexture.new()
	arrow.width = 1
	control.add_icon_override("arrow", arrow)
	control.rect_min_size.y = 32

func record():
	service.tool = hub.tas_tool
	service.start()
	message.text = service.status

func open_camera():
	service.tool = hub.tas_tool
	if live_camera != null and is_instance_valid(live_camera):
		hub.close_hub()
		return
	live_camera = load(get_script().resource_path.get_base_dir().plus_file("ObserverCamera.gd")).new()
	hub.add_child(live_camera)
	if live_camera.start(hub, service):
		hub.close_hub()
	else:
		live_camera.queue_free()
		message.text = "Camera requires an existing server-assigned spectator session."

func stop():
	service.stop()
	refresh()
	message.text = service.status

func refresh(autoload = true):
	entries = store.entries()
	files_picker.clear()
	names = []
	var catalog_script = ModPaths.try_load(ModPaths.path("CouncilMaps.gd"))
	var catalog = catalog_script.new() if catalog_script != null else null
	for entry in entries:
		names.append(entry.file)
		var tag = " · Unfinished" if catalog != null and catalog.unknown_players(entry)>2 else ""
		files_picker.add_item("%s · %d rounds · %s" % [entry.rounds[0].map.name.substr(0,30), entry.rounds.size(), str(entry.created_at)]+tag)
	message.text = "%d / 10,000 local captures · 256 GB ceiling · 1 GB free-space reserve" % entries.size()
	if not names.empty() and autoload:
		choose_file(0)
	elif names.empty():
		selected_file = ""
		data = {}
		participants.clear()
		rounds_picker.clear()
		viewer.configure({"tracks":[]})
		runs_picker.clear()
		research_label.text = "No captures yet. Record a true spectator session or import an observed capture."
	emit_signal("refreshed")

func choose_file(index,initial_round = 0):
	if index < 0 or index >= names.size():
		return
	selected_file = names[index]
	data = store.read(selected_file)
	rounds_picker.clear()
	if data.empty():
		message.text = "Invalid capture; it has not been loaded."
		return
	for item in data.rounds:
		rounds_picker.add_item(item.map.name.substr(0,28) + (" · finished" if item.get("completion","") in ["round_transition","match_finished"] else " · partial"))
	rounds_picker.select(initial_round)
	choose_round(initial_round)

func choose_round(index):
	if data.empty() or index < 0 or index >= data.rounds.size():
		return
	round_index = index
	var item = data.rounds[index]
	participants.clear()
	for track in item.tracks:
		var rank = int(track.placement)
		var title = ("#%d  " % rank if rank > 0 else "") + track.name
		var icon = load("res://project_specific/gfx/trophyicon.png") if rank > 0 and track.outcome == "finish" else null
		participants.add_item(title,icon)
		var row = participants.get_item_count()-1
		participants.set_item_tooltip(row,track.name + " · " + track.outcome + (" · %.2fs" % track.finish_time if track.finish_time >= 0 else ""))
		if rank > 0 and rank <= 3:
			participants.set_item_icon_modulate(row,[Color("ffd166"),Color("c9d7e3"),Color("d89b72")][rank-1])
		participants.select(participants.get_item_count() - 1, false)
	participants.fixed_icon_size = Vector2(22,22)
	viewer.configure(item)
	slider.max_value = max(0.01, viewer.duration)
	slider.value = 0
	research()

func selection_changed(_index, _selected):
	viewer.selected = []
	var tracks = []
	if data.empty():
		return
	for index in participants.get_selected_items():
		viewer.selected.append(data.rounds[round_index].tracks[index].id)
		tracks.append(data.rounds[round_index].tracks[index])
	var overview = load(get_script().resource_path.get_base_dir().plus_file("ObservedOverview.gd")).new()
	viewer.hotspots = overview.clusters(overview.episodes(tracks,viewer.analysis_end))
	viewer.update()

func play():
	if viewer.time >= viewer.duration:
		viewer.time = 0
	viewer.playing = not viewer.playing

func toggle_overview():
	viewer.overview = not viewer.overview
	viewer.update()
	message.text = "Hotspots: inferred death/respawn episodes only; not complete or verified death counts." if viewer.overview else "Timeline view. Drag the map to pan; scroll to zoom."

func seek(value):
	viewer.time = value
	viewer.update()

func _process(_delta):
	if slider != null and viewer.playing:
		slider.set_block_signals(true)
		slider.value = viewer.time
		slider.set_block_signals(false)

func extract():
	if data.empty():
		return
	var extracted = store.extract(data, round_index, viewer.selected)
	if extracted.empty():
		message.text = "Select at least one participant."
		return
	var saved = store.save(extracted)
	refresh()
	message.text = "Selected runs saved." if not saved.empty() else store.error

func confirm_delete():
	if not selected_file.empty():
		delete_dialog.popup_centered(Vector2(440, 160))

func delete_capture():
	var removed = store.remove(selected_file)
	refresh()
	message.text = "Local capture deleted permanently." if removed else "Could not delete capture."

func import_picker():
	file_dialog.popup_centered_ratio(0.75)

func import_capture(path):
	var imported = store.read_json(path, store.MAX_BYTES)
	if not store.valid(imported):
		message.text = "Not a valid observed capture. Macro slots and arbitrary level JSON are not accepted."
		return
	var saved = store.save(imported)
	refresh()
	message.text = "Imported local observed capture." if not saved.empty() else store.error

func research(_unused = 0):
	if data.empty():
		return
	var map = data.rounds[round_index].map
	var identity = map.id if not map.id.empty() else map.name + "|" + map.author
	var mode = "" if mode_picker.selected == 0 else mode_picker.get_item_text(mode_picker.selected)
	var outcome = "" if outcome_picker.selected == 0 else outcome_picker.get_item_text(outcome_picker.selected)
	var days = [0, 7, 30, 365][date_picker.selected]
	var after = 0 if days == 0 else int(OS.get_unix_time()) - days * 86400
	var rows = store.research(entries, identity, mode, outcome, after)
	var times = []
	var finished = 0
	var dnf = 0
	var matches = {}
	for row in rows:
		matches[row.capture_id] = true
		if row.outcome == "finish":
			finished += 1
			if row.time >= 0:
				times.append(float(row.time))
		elif row.outcome == "dnf":
			dnf += 1
	times.sort()
	research_label.text = "%s · %d captures · %d observed runs · %d finishes · %d confirmed DNFs\nUnknown results are not counted as failures." % [map.name, matches.size(), rows.size(), finished, dnf]
	if not times.empty():
		var median = (times[(times.size() - 1) / 2] + times[times.size() / 2]) * 0.5
		research_label.text += "\nObserved finish times: fastest %.2fs · median %.2fs · slowest %.2fs" % [times.front(), median, times.back()]
	research_rows = rows
	if sort_picker.selected > 0:
		research_rows = []
		for row in rows:
			if row.outcome == "finish" and row.time >= 0:
				research_rows.append(row)
		research_rows.sort_custom(self, "faster")
		if not research_rows.empty():
			var pick = 0 if sort_picker.selected == 1 else (research_rows.size() / 2 if sort_picker.selected == 2 else research_rows.size() - 1)
			research_rows = [research_rows[pick]]
	runs_picker.clear()
	for row in research_rows:
		runs_picker.add_item("%s · %s · %s" % [row.name.substr(0,32),row.outcome,"%.2fs" % row.time if row.time >= 0 else "time unknown"])
	runs_picker.hint_tooltip = "Choose a run to open its capture and focus that participant."

func faster(a, b):
	return a.time < b.time

func choose_research_run(index):
	if index < 0 or index >= research_rows.size():
		return
	var row = research_rows[index].duplicate()
	var file_index = names.find(row.file)
	if file_index < 0:
		return
	files_picker.select(file_index)
	choose_file(file_index)
	rounds_picker.select(row.round)
	choose_round(row.round)
	participants.unselect_all()
	for i in data.rounds[round_index].tracks.size():
		if data.rounds[round_index].tracks[i].id == row.track:
			participants.select(i)
	selection_changed(0, true)
