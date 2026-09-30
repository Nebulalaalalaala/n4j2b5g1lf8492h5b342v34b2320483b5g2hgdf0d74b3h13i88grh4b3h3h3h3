extends TabContainer

var service
var profile
var history: ItemList
var details: Label
var filter: LineEdit
var overview: Label
var tracked: Label
var records_label: Label
var visible_records := []
var import_dialog: ConfirmationDialog
var import_edit: TextEdit
var reset_dialog: ConfirmationDialog
var status: Label
var body_font: DynamicFont
var record_list: ItemList
var record_filter: LineEdit
var record_keys := []
var map_stats := {}
var pb_data := {}

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_constant_override("separation", 10)
	scroll.add_child(column)
	return column

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_font_override("font", body_font)
	label.autowrap = true
	label.rect_min_size.y = 36
	parent.add_child(label)
	return label

func build() -> void:
	rect_min_size = Vector2(450, 420)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var font := DynamicFont.new()
	font.font_data = load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
	font.size = 20
	body_font = font
	var local_theme := Theme.new()
	local_theme.default_font = font
	theme = local_theme
	add_font_override("font", font)
	var home := _page("Overview")
	overview = _label(home, "")
	status = _label(home, "")
	var actions := HBoxContainer.new()
	home.add_child(actions)
	for entry in [["Export", "_export"], ["Import", "_import"], ["Reset tracked", "_reset"]]:
		var button := Button.new()
		button.text = entry[0]
		button.add_font_override("font", body_font)
		button.rect_min_size = Vector2(120, 44)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.05, 0.28, 0.48)
		fill.content_margin_left = 12
		fill.content_margin_right = 12
		fill.content_margin_top = 6
		fill.content_margin_bottom = 6
		button.add_stylebox_override("normal", fill)
		button.add_stylebox_override("hover", fill)
		button.add_stylebox_override("pressed", fill)
		button.connect("pressed", self, entry[1])
		actions.add_child(button)
	var stats := _page("Statistics")
	_label(stats, "GOOBER DASH ACCOUNT STATS" if profile != null else "LOCAL OBSERVATIONS · native lifetime stats remain in your profile")
	# Keep the real server-populated rows, not locally reconstructed values.
	if profile != null:
		for row in profile.stats_list_container.get_children():
			if row == self or row == profile.stats_row_template:
				continue
			profile.stats_list_container.remove_child(row)
			stats.add_child(row)
	tracked = _label(stats, "")
	var history_page := _page("History")
	filter = LineEdit.new()
	filter.placeholder_text = "Filter maps or mode"
	filter.connect("text_changed", self, "_filter")
	history_page.add_child(filter)
	history = ItemList.new()
	history.rect_min_size = Vector2(0, 180)
	history.connect("item_selected", self, "_select")
	history_page.add_child(history)
	details = _label(history_page, "Select an observation for details.")
	var records_page := _page("Records")
	record_filter = LineEdit.new()
	record_filter.placeholder_text = "Filter maps or mode"
	record_filter.connect("text_changed", self, "_filter_records")
	records_page.add_child(record_filter)
	record_list = ItemList.new()
	record_list.rect_min_size = Vector2(0, 140)
	record_list.connect("item_selected", self, "_select_record")
	records_page.add_child(record_list)
	records_label = _label(records_page, "")
	import_dialog = ConfirmationDialog.new()
	import_dialog.window_title = "Import tracked profile JSON"
	import_edit = TextEdit.new()
	import_edit.rect_min_size = Vector2(520, 260)
	import_dialog.add_child(import_edit)
	import_dialog.connect("confirmed", self, "_confirm_import")
	add_child(import_dialog)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.dialog_text = "Reset this account's locally tracked history and session? Goober Dash account stats are unchanged."
	reset_dialog.connect("confirmed", self, "_confirm_reset")
	add_child(reset_dialog)
	refresh()

func refresh() -> void:
	var store = service.store
	var stats: Dictionary = store.statistics(store.records)
	var current: Dictionary = store.statistics(store.session)
	map_stats = stats.maps
	pb_data = store.progression(store.records)
	overview.text = "Locally observed rounds / time trials: %d\nFinishes: %d   Confirmed match wins: %d\nMaps: %d   Observed deaths: %d\nLatest %d observations · not lifetime stats\nTracking began: %s" % [stats.observed, stats.finishes, stats.wins, stats.maps.size(), stats.deaths, store.LIMIT, _date(store.since)]
	tracked.text = "LOCAL RETAINED HISTORY\nKnown DNFs: %d · Unknown outcomes: %d\nObserved playtime: %.1f min\nAverage known placement: %s\n\nTHIS SESSION\nObservations: %d · Wins: %d · Deaths: %d\nPlaytime: %.1f min" % [stats.dnfs, stats.unknown, stats.play_seconds / 60.0, "%.2f" % (float(stats.placement_sum) / stats.placed) if stats.placed > 0 else "Unavailable", current.observed, current.wins, current.deaths, current.play_seconds / 60.0]
	status.text = store.last_error
	var session_pbs := 0
	for entry in store.session:
		if pb_data.events.has(entry.id) and not pb_data.events[entry.id].baseline:
			session_pbs += 1
	tracked.text += "\nPB improvements: %d (against retained history)" % session_pbs
	var highlights: Dictionary = store.highlights(store.records)
	for pair in [["Most played", "most_played"], ["Strongest map", "strongest"], ["Nemesis", "nemesis"]]:
		var key: String = highlights[pair[1]]
		overview.text += "\n%s: %s" % [pair[0], (map_stats[key].name + " · " + map_stats[key].mode) if not key.empty() else "Not enough evidence"]
	overview.text += "\nStrongest / nemesis: completion rate, minimum 5 known outcomes; unknowns excluded."
	_filter(filter.text)
	_filter_records(record_filter.text)

func _filter_records(query: String) -> void:
	record_list.clear()
	record_keys = []
	var keys := map_stats.keys()
	keys.sort()
	for key in keys:
		var map: Dictionary = map_stats[key]
		if not query.empty() and (map.name + " " + map.mode).to_lower().find(query.to_lower()) < 0:
			continue
		record_keys.append(key)
		record_list.add_item("%s · %s · %s" % [map.name, map.mode, "%.3fs" % map.best if map.best >= 0 else "No finish"])
	records_label.text = "Select a map for tracked statistics and PB progression." if not record_keys.empty() else "No matching map records."

func _select_record(index: int) -> void:
	if index < 0 or index >= record_keys.size():
		return
	var key: String = record_keys[index]
	var map: Dictionary = map_stats[key]
	var known: int = map.completions + map.dnfs
	records_label.text = "%s · %s\n%d observations · %d finishes · %d confirmed wins\nDeaths: %d · Last played: %s\nCompletion rate (known outcomes): %s\nAverage finish: %s\n\nPB PROGRESSION — retained history only" % [map.name, map.mode, map.plays, map.completions, map.wins, map.deaths, _date(map.last_played), "%.1f%%" % (100.0 * map.completions / known) if known > 0 else "Unavailable", "%.3fs" % (map.total_time / map.completions) if map.completions > 0 else "Unavailable"]
	if pb_data.maps.has(key):
		for step in pb_data.maps[key].steps:
			records_label.text += "\n%s · %.3fs · %s" % [_date(step.date), step.time, "First retained finish" if step.baseline else "−%.3fs" % step.improvement]

func _filter(query: String) -> void:
	history.clear()
	visible_records = []
	var source: Array = service.store.records.duplicate()
	source.invert()
	for entry in source:
		if not query.empty() and (entry.map_name + " " + entry.mode).to_lower().find(query.to_lower()) < 0:
			continue
		visible_records.append(entry)
		var suffix := ""
		if pb_data.events.has(entry.id) and not pb_data.events[entry.id].baseline:
			suffix = " · NEW PB −%.3fs" % pb_data.events[entry.id].improvement
		history.add_item("%s · %s · %s%s" % [entry.map_name, entry.mode, "%.3fs" % entry.finish_time if entry.result == "finish" else entry.result, suffix])

func _select(index: int) -> void:
	if index < 0 or index >= visible_records.size():
		return
	var entry: Dictionary = visible_records[index]
	details.text = "%s\n%s\nPlacement: %s · Players observed: %d\nDeaths observed: %d · Playtime: %.1fs\n%s" % [entry.map_name, entry.mode, str(entry.placement) if entry.placement > 0 else "Unknown", entry.players, entry.deaths, entry.play_seconds, _date(entry.date)]

func _date(timestamp: int) -> String:
	var date := OS.get_datetime_from_unix_time(timestamp)
	return "%04d-%02d-%02d" % [date.year, date.month, date.day]

func _export() -> void:
	OS.clipboard = service.store.export_text()
	status.text = "Tracked profile JSON copied. Account stats are not included."

func _import() -> void:
	import_edit.text = ""
	import_dialog.popup_centered(Vector2(560, 340))

func _confirm_import() -> void:
	var success: bool = service.store.import_text(import_edit.text)
	refresh()
	status.text = "History imported." if success else service.store.last_error

func _reset() -> void:
	reset_dialog.popup_centered(Vector2(520, 180))

func _confirm_reset() -> void:
	var success: bool = service.store.reset()
	refresh()
	status.text = "Local tracking reset." if success else service.store.last_error
