extends "user://mod/tools/match-info/WinsLeaderboard/02_board_period.gd"

func _period_result(period: String, latest_key: String) -> Dictionary:
	var latest: Dictionary = _snapshots.get(latest_key, {})
	var current_rows: Array = latest.get("rows", [])
	if period == "all_time":
		return {
			"available": true,
			"rows": current_rows.duplicate(true),
			"title": "ALL-TIME WINS · %d TRACKED PLAYERS" % current_rows.size(),
			"coverage": "Community snapshot dated %s UTC · showing the top %d" % [latest_key, min(MAX_VISIBLE_ROWS, current_rows.size())],
		}

	var base_key: String = ""
	var period_name: String = str(PERIOD_TITLES.get(period, period.to_upper()))
	if period == "daily":
		base_key = _date_key_offset(latest_key, -1)
	elif period == "weekly":
		base_key = _week_start_key(latest_key)
	elif period == "monthly":
		base_key = latest_key.substr(0, 8) + "01"
	elif period == "yearly":
		base_key = latest_key.substr(0, 4) + "-01-01"
	var boundary = base_key
	if not base_key.empty() and not _snapshots.has(base_key):
		var keys = _snapshots.keys()
		keys.sort()
		for key in keys:
			if str(key)>=boundary and str(key)<latest_key:
				base_key = str(key)
				break
	if base_key.empty() or not _snapshots.has(base_key):
		return {
			"available": false,
			"title": "%s WINS · TRACKING IN PROGRESS" % period_name,
			"coverage": "Latest snapshot: %s UTC · period starts: %s UTC" % [latest_key, boundary],
			"message": "Not enough observations in this period yet. Two dated snapshots are needed to measure wins; missing wins cannot be reconstructed from a lifetime total.",
		}

	var base: Dictionary = _snapshots.get(base_key, {})
	var base_wins: = {}
	for row in base.get("rows", []):
		if typeof(row) == TYPE_DICTIONARY:
			base_wins[str(row.get("id", ""))] = int(row.get("wins", 0))
	var observed_dates = _snapshots.keys()
	observed_dates.sort()
	var partial_players = 0
	for date in observed_dates:
		if str(date)<=base_key or str(date)>=latest_key:
			continue
		for row in _snapshots[date].get("rows",[]):
			var id = str(row.get("id",""))
			if not base_wins.has(id):
				base_wins[id] = int(row.get("wins",0))
				partial_players += 1
	var changes: = []
	for row in current_rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var user_id: String = str(row.get("id", ""))
		if not base_wins.has(user_id):
			continue
		var delta: int = int(row.get("wins", 0)) - int(base_wins[user_id])
		if delta <= 0:
			continue
		changes.append({"id": user_id, "username": str(row.get("username", "Unknown")), "wins": delta})
	return {
		"available": true,
		"rows": changes,
		"title": "%s WINS · %d PLAYERS GAINED WINS" % [period_name, changes.size()],
		"coverage": "%s → %s UTC · %s · %d players first observed later · not live totals" % [base_key, latest_key, "period to date" if base_key==boundary else "PARTIAL PERIOD: earlier wins unknown",partial_players],
	}


func _week_start_key(key: String) -> String:
	# Match the other calendar periods: Monday 00:00 UTC through the latest snapshot.
	if not _valid_date_key(key):
		return ""
	var parts = key.split("-")
	if parts.size() != 3:
		return ""
	var timestamp = OS.get_unix_time_from_datetime({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 0, "minute": 0, "second": 0})
	var weekday = int(OS.get_datetime_from_unix_time(timestamp).get("weekday", 0))
	return _date_key_offset(key, -((weekday + 6) % 7))


func _sort_wins_descending(a: Dictionary, b: Dictionary) -> bool:
	var a_wins: int = int(a.get("wins", 0))
	var b_wins: int = int(b.get("wins", 0))
	if a_wins == b_wins:
		return str(a.get("username", "")).to_lower() < str(b.get("username", "")).to_lower()
	return a_wins > b_wins


func _add_native_row(entry: Dictionary, rank: int, alternate: bool) -> void:
	if _leaderboard_script == null or not is_instance_valid(_leaderboard_script):
		return
	var row_scene = _leaderboard_script.get("row_scene")
	if row_scene == null or not row_scene is PackedScene:
		_add_fallback_row(entry, rank, alternate)
		return
	var row: Control = row_scene.instance() as Control
	if row == null:
		return
	_rows_parent.add_child(row)
	row.call("show_data", str(entry.get("username", "Unknown")), str(rank), str(entry.get("wins", 0)), {}, alternate)
	var country_holder: CanvasItem = row.get_node_or_null("MarginContainer/HBoxContainer/CountryIcon") as CanvasItem
	if country_holder != null:
		country_holder.visible = false
	if row.has_signal("pressed"):
		row.connect("pressed", self, "_on_wins_row_pressed", [str(entry.get("id", ""))])


func _add_fallback_row(entry: Dictionary, rank: int, alternate: bool) -> void:
	var panel: = PanelContainer.new()
	panel.rect_min_size = Vector2(0, 62)
	var bg: Color = COLOR_CARD_BG if alternate else COLOR_PANEL_BG.lightened(0.05)
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", bg, Color(1, 1, 1, 0.08), 1, 8))
	_rows_parent.add_child(panel)
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 14)
	panel.add_child(row)
	var rank_label: Label = _make_label(str(rank), 18, COLOR_TEXT_DIM)
	rank_label.rect_min_size.x = 75
	row.add_child(rank_label)
	var name_label: Label = _make_label(str(entry.get("username", "Unknown")), 18, COLOR_WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_make_label(str(entry.get("wins", 0)), 20, COLOR_ORANGE))


func _on_wins_row_pressed(user_id: String) -> void:
	if user_id.empty():
		return
	if _leaderboard_script != null and is_instance_valid(_leaderboard_script):
		_leaderboard_script.call("on_leaderboard_row_pressed", user_id)
	else:
		var profile_scene = load("res://project_specific/ui/UIPlayerProfileDialog.tscn")
		if profile_scene is PackedScene and get_tree().current_scene != null:
			var profile = profile_scene.instance()
			get_tree().current_scene.add_child(profile)
			profile.call("show_player_profile_dialog", user_id)


func _clear_rows() -> void:
	for child in _rows_parent.get_children():
		_rows_parent.remove_child(child)
		child.queue_free()


func _add_empty_message(message: String) -> void:
	var panel: = PanelContainer.new()
	panel.rect_min_size = Vector2(0, 110)
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_CARD_BG, Color(1, 1, 1, 0.12), 1, 14))
	_rows_parent.add_child(panel)
	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 18)
	panel.add_child(margin)
	var label: Label = _make_label(message, 17, COLOR_TEXT_DIM)
	label.autowrap = true
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	margin.add_child(label)


func _open_import_dialog() -> void:
	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.popup_centered_ratio(0.72)


func _on_snapshot_file_selected(path: String) -> void:
	var filename: String = path.get_file().get_basename()
	var parts: PoolStringArray = filename.split("_")
	if parts.size() < 3 or not str(parts[parts.size() - 1]).is_valid_integer():
		_show_import_error("The filename needs the timestamp created by the stats page: wins_leaderboard_<timestamp>.csv")
		return
	var timestamp_msec: int = int(parts[parts.size() - 1])
	if timestamp_msec <= 0:
		_show_import_error("That CSV timestamp is invalid.")
		return
	var file: = File.new()
	var open_error: int = file.open(path, File.READ)
	if open_error != OK:
		_show_import_error("Could not open that CSV (error %d)." % open_error)
		return
	var csv_text: String = file.get_as_text()
	file.close()
	if csv_text.length() > MAX_RESPONSE_BYTES:
		_show_import_error("That CSV is unexpectedly large.")
		return
	var csv_rows: Array = _parse_wins_csv(csv_text)
	if csv_rows.empty():
		_show_import_error("That file is not a valid downloaded wins leaderboard CSV.")
		return
	var timestamp_sec: int = int(timestamp_msec / 1000)
	var date_key: String = _utc_date_key(OS.get_datetime_from_unix_time(timestamp_sec))
	_snapshots[date_key] = {"fetched_unix": timestamp_sec, "rows": csv_rows}
	_prune_snapshots()
	_save_snapshots()
	_render_active_period()
	_log("Wins leaderboard: imported %s with %d players" % [date_key, csv_rows.size()])


func _parse_wins_csv(csv_text: String) -> Array:
	var lines: PoolStringArray = csv_text.replace("\r", "").split("\n", false)
	if lines.size() < 2 or lines.size() > MAX_SOURCE_ROWS + 1:
		return []
	var header: PoolStringArray = lines[0].split(",")
	if header.size() < 3 or str(header[0]).strip_edges().to_lower() != "id" or str(header[2]).strip_edges().to_lower() != "wins":
		return []
	var raw_rows: = []
	for index in range(1, lines.size()):
		var fields: PoolStringArray = lines[index].split(",")
		if fields.size() < 3:
			continue
		var wins_text: String = str(fields[2]).strip_edges()
		if not wins_text.is_valid_integer():
			continue
		raw_rows.append({"id": str(fields[0]), "username": str(fields[1]), "wins": int(wins_text)})
	return _normalize_rows(raw_rows)


func _show_import_error(message: String) -> void:
	if _summary_label != null and is_instance_valid(_summary_label):
		_summary_label.text = message
	_log("Wins leaderboard: " + message)


func _load_snapshots() -> void:
	_snapshots.clear()
	var file: = File.new()
	if not file.file_exists(CACHE_PATH):
		return
	if file.open(CACHE_PATH, File.READ) != OK:
		return
	var text: String = file.get_as_text()
	file.close()
	if text.empty() or text.length() > 64 * 1024 * 1024:
		return
	var parsed: JSONParseResult = JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	for raw_key in parsed.result.keys():
		var key: String = str(raw_key)
		var snapshot = parsed.result[raw_key]
		if not _valid_date_key(key) or typeof(snapshot) != TYPE_DICTIONARY:
			continue
		var rows: Array = _normalize_rows(snapshot.get("rows", []))
		if rows.empty():
			continue
		_snapshots[key] = {"fetched_unix": int(snapshot.get("fetched_unix", 0)), "rows": rows}
	_prune_snapshots()


func _save_snapshots() -> void:
	var file: = File.new()
	var error: int = file.open(CACHE_PATH, File.WRITE)
	if error != OK:
		_log("Wins leaderboard: could not save snapshots (error %d)" % error)
		return
	file.store_string(JSON.print(_snapshots))
	file.close()


func _prune_snapshots() -> void:
	var keys: = _snapshots.keys()
	keys.sort()
	if keys.size() <= 45:
		return
	var keep: = {}
	var recent_start: int = max(0, keys.size() - 45)
	for index in range(recent_start, keys.size()):
		keep[str(keys[index])] = true
	var earliest_month: = {}
	var earliest_year: = {}
	var latest_month: = {}
	for raw_key in keys:
		var key: String = str(raw_key)
		var month: String = key.substr(0, 7)
		var year: String = key.substr(0, 4)
		latest_month[month] = key
		if not earliest_month.has(month):
			earliest_month[month] = key
		if not earliest_year.has(year):
			earliest_year[year] = key
	for key in earliest_month.values():
		keep[str(key)] = true
	for key in earliest_year.values():
		keep[str(key)] = true
	for key in latest_month.values():
		keep[str(key)] = true
	for raw_key in keys:
		var key: String = str(raw_key)
		if not keep.has(key):
			_snapshots.erase(key)


func _latest_snapshot_key() -> String:
	var keys: = _snapshots.keys()
	if keys.empty():
		return ""
	keys.sort()
	return str(keys[keys.size() - 1])


func _date_key_offset(key: String, days: int) -> String:
	if not _valid_date_key(key):
		return ""
	var date: = {
		"year": int(key.substr(0, 4)),
		"month": int(key.substr(5, 2)),
		"day": int(key.substr(8, 2)),
		"hour": 0,
		"minute": 0,
		"second": 0,
	}
	var unix_time: int = OS.get_unix_time_from_datetime(date) + days * 86400
	return _utc_date_key(OS.get_datetime_from_unix_time(unix_time))


func _utc_date_key(date: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(date.get("year", 1970)), int(date.get("month", 1)), int(date.get("day", 1))]


func _valid_date_key(key: String) -> bool:
	if key.length() != 10 or key.substr(4, 1) != "-" or key.substr(7, 1) != "-":
		return false
	return key.substr(0, 4).is_valid_integer() and key.substr(5, 2).is_valid_integer() and key.substr(8, 2).is_valid_integer()


func _make_label(text: String, size: int, color: Color) -> Label:
	return tas_tool.call("_make_label", text, tas_tool.call("_make_font", size), color) as Label

func _process(delta: float) -> void:
	_view_elapsed += delta
	if _view_elapsed < 0.5:
		return
	_view_elapsed = 0.0
	if _board_view != null and is_instance_valid(_board_view) and _board_view.is_visible_in_tree():
		_board_view.refresh()


func _make_button(text: String, color: Color, width: int) -> Button:
	var button: Button = tas_tool.call("_make_button", text, color, width) as Button
	button.rect_min_size.y = 54
	for state in ["normal", "hover", "pressed"]:
		button.add_stylebox_override(state, tas_tool.call("_make_flat_style", Color("22282c") if state == "normal" else Color("30483d"), Color("343c40") if state == "normal" else Color("9dd6bd"), 1, 8))
	return button


func _log(message: String) -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_log_action"):
		tas_tool.call("_log_action", message, null)
