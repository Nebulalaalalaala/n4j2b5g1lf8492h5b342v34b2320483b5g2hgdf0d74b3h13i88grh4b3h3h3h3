extends "user://mod/tools/match-info/WinsLeaderboard/01_placeholders.gd"

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_http = HTTPRequest.new()
	_http.name = "WinsLeaderboardHTTPRequest"
	_http.timeout = 35.0
	add_child(_http)
	_http.connect("request_completed", self, "_on_request_completed")

	_file_dialog = FileDialog.new()
	_file_dialog.name = "WinsLeaderboardImportDialog"
	_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.window_title = "Import a downloaded wins leaderboard snapshot"
	_file_dialog.add_filter("*.csv ; Wins leaderboard CSV")
	add_child(_file_dialog)
	_file_dialog.connect("file_selected", self, "_on_snapshot_file_selected")

	_load_snapshots()
	var tree: = get_tree()
	if not tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.connect("node_added", self, "_on_tree_node_added")


func configure(owner_tool) -> void:
	tas_tool = owner_tool
	var existing: Node = _find_existing_leaderboard(get_tree().root)
	if existing != null:
		call_deferred("_inject_into_leaderboard", existing)
	# Collect at most one snapshot per UTC day whenever Goobplayability starts,
	# even if the player does not open the Leaderboard tab that day. This is
	# what lets the period boards build useful history over normal game use.
	call_deferred("_request_latest_snapshot", false)


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if not value and _wins_mode:
		_show_crowns_board()
	if _selector_row != null and is_instance_valid(_selector_row):
		_selector_row.visible = value


func set_claude_experimental_icons_enabled(_value: bool) -> void:
	pass


func _on_tree_node_added(node: Node) -> void:
	if node != null and node.name == "LeaderboardScript" and node.has_method("on_leaderboard_row_pressed"):
		call_deferred("_inject_into_leaderboard", node)


func _find_existing_leaderboard(root: Node) -> Node:
	if root == null:
		return null
	var pending: = [root]
	while not pending.empty():
		var node: Node = pending.pop_back()
		if node.name == "LeaderboardScript" and node.has_method("on_leaderboard_row_pressed"):
			return node
		for child in node.get_children():
			pending.append(child)
	return null


func _inject_into_leaderboard(leaderboard_script: Node) -> void:
	if not is_instance_valid(leaderboard_script):
		return
	var page: Node = leaderboard_script.get_parent()
	if page == null:
		return
	var vbox: VBoxContainer = page.get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	var existing: Node = vbox.get_node_or_null("GoobplayabilityWinsSelector")
	if existing != null:
		_selector_row = existing as HBoxContainer
		_selector_row.visible = gui_enabled
		return

	_leaderboard_script = leaderboard_script
	_vbox = vbox
	_wins_mode = false
	_native_visibility_restore.clear()

	var background_panel: Control = vbox.get_node_or_null("BackgroundPanel") as Control
	var insert_index: = background_panel.get_index() if background_panel != null else vbox.get_child_count()

	_selector_row = HBoxContainer.new()
	_selector_row.name = "GoobplayabilityWinsSelector"
	_selector_row.add_constant_override("separation", 12)
	_selector_row.visible = gui_enabled
	vbox.add_child(_selector_row)
	vbox.move_child(_selector_row, insert_index)

	_crowns_button = _make_button("●  CROWNS", COLOR_BLUE, 280)
	_crowns_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crowns_button.hint_tooltip = "Goober Dash's official seasonal crown leaderboard"
	_crowns_button.connect("pressed", self, "_show_crowns_board")
	_selector_row.add_child(_crowns_button)

	_wins_button = _make_button("HIGHEST WINS", COLOR_ORANGE, 340)
	_wins_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wins_button.hint_tooltip = "Community lifetime wins, plus locally tracked period changes"
	_wins_button.connect("pressed", self, "_show_wins_board")
	_selector_row.add_child(_wins_button)

	_build_wins_panel()
	vbox.add_child(_wins_panel)
	vbox.move_child(_wins_panel, _selector_row.get_index() + 1)
	_refresh_mode_button_text()


func _build_wins_panel() -> void:
	_wins_panel = PanelContainer.new()
	_wins_panel.name = "GoobplayabilityWinsPanel"
	_wins_panel.visible = false
	_wins_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wins_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var view_script = load(get_script().resource_path.get_base_dir().plus_file("WinsBoardView.gd"))
	if view_script != null and view_script.can_instance():
		_wins_panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", Color("181c20"), Color("343c40"), 1, 12))
		var view_margin = MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			view_margin.add_constant_override("margin_" + side, 18)
		_wins_panel.add_child(view_margin)
		_board_view = view_script.new()
		view_margin.add_child(_board_view)
		_board_view.build(self, tas_tool)
		return
	_wins_panel.rect_min_size = Vector2(0, 820)
	_wins_panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_PANEL_BG, COLOR_PANEL_BORDER, 3, 28))

	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 20)
	_wins_panel.add_child(margin)

	var column: = VBoxContainer.new()
	column.add_constant_override("separation", 12)
	margin.add_child(column)

	var period_row: = HBoxContainer.new()
	period_row.add_constant_override("separation", 8)
	column.add_child(period_row)
	for period in PERIODS:
		var period_button: Button = _make_button(str(PERIOD_TITLES[period]), COLOR_BLUE, 154)
		period_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		period_button.connect("pressed", self, "_on_period_pressed", [period])
		period_row.add_child(period_button)
		_period_buttons[period] = period_button

	var tools_row: = HBoxContainer.new()
	tools_row.add_constant_override("separation", 10)
	column.add_child(tools_row)
	_refresh_button = _make_button("REFRESH", COLOR_GREEN, 170)
	_refresh_button.hint_tooltip = "Download today's community wins snapshot"
	_refresh_button.connect("pressed", self, "_request_latest_snapshot", [true])
	tools_row.add_child(_refresh_button)
	var import_button: Button = _make_button("IMPORT CSV", COLOR_ORANGE, 190)
	import_button.hint_tooltip = "Import a wins_leaderboard_<timestamp>.csv downloaded from the stats page"
	import_button.connect("pressed", self, "_open_import_dialog")
	tools_row.add_child(import_button)
	var spacer: = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_row.add_child(spacer)
	var source: Label = _make_label("COMMUNITY STATS · 00:00 UTC", 15, COLOR_TEXT_DIM)
	source.valign = Label.VALIGN_CENTER
	tools_row.add_child(source)

	_summary_label = _make_label("", 20, COLOR_WHITE)
	_summary_label.autowrap = true
	column.add_child(_summary_label)
	_coverage_label = _make_label("", 15, COLOR_TEXT_DIM)
	_coverage_label.autowrap = true
	column.add_child(_coverage_label)

	var scroll: = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_rows_parent = VBoxContainer.new()
	_rows_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_parent.add_constant_override("separation", 0)
	scroll.add_child(_rows_parent)

	var disclaimer: Label = _make_label("Unofficial community snapshot from twhlynch.me. It can omit players who have not been scraped; period boards only use exact locally saved UTC boundaries.", 14, COLOR_TEXT_DIM)
	disclaimer.autowrap = true
	disclaimer.align = Label.ALIGN_CENTER
	column.add_child(disclaimer)


func _show_wins_board() -> void:
	if not gui_enabled or _wins_panel == null or not is_instance_valid(_wins_panel):
		return
	if not _wins_mode:
		_capture_and_hide_native_board()
	_wins_mode = true
	_wins_panel.visible = true
	_set_header_text("WINS")
	_refresh_mode_button_text()
	_render_active_period()
	_request_latest_snapshot(false)


func _show_crowns_board() -> void:
	if _wins_panel != null and is_instance_valid(_wins_panel):
		_wins_panel.visible = false
	_restore_native_board()
	_wins_mode = false
	_set_header_text("LEADERS")
	_refresh_mode_button_text()


func _capture_and_hide_native_board() -> void:
	_native_visibility_restore.clear()
	if _vbox == null or not is_instance_valid(_vbox):
		return
	for path in ["BackgroundPanel", "Control2", "LeaderboardRow_Self", "BottomStuff", "GoobplayabilityLeaderboardSearch", "GoobplayabilityLeaderboardSearchStatus"]:
		var node: CanvasItem = _vbox.get_node_or_null(path) as CanvasItem
		if node != null:
			_native_visibility_restore.append({"node": node, "visible": node.visible})
			node.visible = false
	var countdown: CanvasItem = _vbox.get_node_or_null("TopStuff/SeasonCountdown") as CanvasItem
	if countdown != null:
		_native_visibility_restore.append({"node": countdown, "visible": countdown.visible})
		countdown.visible = false


func _restore_native_board() -> void:
	for saved in _native_visibility_restore:
		var node = saved.get("node", null)
		if node != null and is_instance_valid(node):
			node.visible = bool(saved.get("visible", true))
	_native_visibility_restore.clear()


func _set_header_text(value: String) -> void:
	if _vbox == null or not is_instance_valid(_vbox):
		return
	var header: Label = _vbox.get_node_or_null("TopStuff/LeadersLabel") as Label
	if header == null:
		return
	header.text = value
	var outline: Label = header.get_node_or_null("__SDFLabelOutline") as Label
	if outline != null:
		outline.text = value


func _refresh_mode_button_text() -> void:
	if _crowns_button != null and is_instance_valid(_crowns_button):
		_crowns_button.text = ("●  CROWNS" if not _wins_mode else "CROWNS")
	if _wins_button != null and is_instance_valid(_wins_button):
		_wins_button.text = ("●  HIGHEST WINS" if _wins_mode else "HIGHEST WINS")


func _on_period_pressed(period: String) -> void:
	if not PERIODS.has(period):
		return
	_active_period = period
	_render_active_period()


func _refresh_period_button_text() -> void:
	for period in PERIODS:
		var button: Button = _period_buttons.get(period, null) as Button
		if button != null and is_instance_valid(button):
			button.text = ("●  " if period == _active_period else "") + str(PERIOD_TITLES[period])


func _request_latest_snapshot(force: bool = false) -> void:
	if _request_busy or _http == null:
		return
	var today: String = _utc_date_key(OS.get_datetime(true))
	if not force and _snapshots.has(today):
		return
	_request_busy = true
	_view_error = ""
	if _refresh_button != null and is_instance_valid(_refresh_button):
		_refresh_button.disabled = true
	if _summary_label != null and is_instance_valid(_summary_label):
		_summary_label.text = "Downloading today's wins snapshot..."
	var headers: = PoolStringArray(["Accept: application/json", "User-Agent: Goobplayability-Wins-Leaderboard"])
	var error: int = _http.request(API_URL, headers, true, HTTPClient.METHOD_GET)
	if error != OK:
		_finish_request_with_error("Could not start the stats download (error %d)." % error)


func _on_request_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	_request_busy = false
	if _refresh_button != null and is_instance_valid(_refresh_button):
		_refresh_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish_request_with_error("Stats download failed (HTTP %d, result %d). Showing saved data." % [response_code, result])
		return
	if body.size() <= 0 or body.size() > MAX_RESPONSE_BYTES:
		_finish_request_with_error("The stats response had an unexpected size. Showing saved data.")
		return
	var parsed: JSONParseResult = JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY:
		_finish_request_with_error("The stats service returned invalid data. Showing saved data.")
		return
	var rows: Array = _normalize_rows(parsed.result)
	if rows.empty():
		_finish_request_with_error("The stats service returned no valid players. Showing saved data.")
		return
	var now: Dictionary = OS.get_datetime(true)
	var key: String = _utc_date_key(now)
	_snapshots[key] = {"fetched_unix": OS.get_unix_time(), "rows": rows}
	_prune_snapshots()
	_save_snapshots()
	_render_active_period()
	_log("Wins leaderboard: saved %s UTC snapshot with %d players" % [key, rows.size()])


func _finish_request_with_error(message: String) -> void:
	_view_error = message
	_request_busy = false
	if _refresh_button != null and is_instance_valid(_refresh_button):
		_refresh_button.disabled = false
	if _summary_label != null and is_instance_valid(_summary_label):
		_summary_label.text = message
	_log(message)


func _normalize_rows(raw_rows) -> Array:
	var rows: = []
	if typeof(raw_rows) != TYPE_ARRAY:
		return rows
	var seen: = {}
	var count: = 0
	for raw in raw_rows:
		if count >= MAX_SOURCE_ROWS:
			break
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var user_id: String = str(raw.get("id", "")).strip_edges()
		var username: String = str(raw.get("username", "")).strip_edges()
		var wins: int = int(raw.get("wins", -1))
		if user_id.empty() or user_id.length() > 80 or username.empty() or wins < 0:
			continue
		if username.length() > 80:
			username = username.substr(0, 80)
		if seen.has(user_id):
			continue
		seen[user_id] = true
		rows.append({"id": user_id, "username": username, "wins": wins})
		count += 1
	return rows


func _render_active_period() -> void:
	if _board_view != null and is_instance_valid(_board_view):
		_board_view.refresh(true)
		return
	_refresh_period_button_text()
	if _rows_parent == null or not is_instance_valid(_rows_parent):
		return
	_clear_rows()
	var latest_key: String = _latest_snapshot_key()
	if latest_key.empty():
		_summary_label.text = "No wins snapshot has been saved yet."
		_coverage_label.text = "Open this board online or press REFRESH to download today's community stats."
		_add_empty_message("Waiting for the first snapshot...")
		return

	var result: Dictionary = _period_result(_active_period, latest_key)
	if not bool(result.get("available", false)):
		_summary_label.text = str(result.get("title", "Period unavailable"))
		_coverage_label.text = str(result.get("coverage", ""))
		_add_empty_message(str(result.get("message", "A boundary snapshot is missing.")))
		return

	var rows: Array = result.get("rows", [])
	_summary_label.text = str(result.get("title", ""))
	_coverage_label.text = str(result.get("coverage", ""))
	if rows.empty():
		_add_empty_message("No positive win changes were recorded for this period.")
		return
	rows.sort_custom(self, "_sort_wins_descending")
	var visible_count: int = min(MAX_VISIBLE_ROWS, rows.size())
	for index in range(visible_count):
		_add_native_row(rows[index], index + 1, index % 2 == 0)
