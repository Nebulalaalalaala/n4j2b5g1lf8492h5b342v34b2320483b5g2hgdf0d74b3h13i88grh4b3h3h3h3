extends "user://mod/tools/replay-hub/ReplayHub/01_placeholders.gd"

func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool


func _ready() -> void:
	layer = 150
	pause_mode = Node.PAUSE_MODE_PROCESS
	# Read the setting directly instead of waiting for TASTool.gd's
	# set_claude_experimental_icons_enabled() call: that call only arrives
	# via a deferred call made at the very end of TASTool.gd's own _ready(),
	# which runs AFTER add_child(_replay_hub) already triggered this whole
	# _ready() (including _build_modal()/_build_access_button() below) --
	# so waiting for it meant every stylebox got built with the toggle
	# still reading as off, no matter what the saved setting actually was.
	# Reading the same saved value straight from SavedSettings here sidesteps
	# that ordering entirely, the same way CheatMenu.gd reads its own
	# settings directly rather than waiting on TASTool.gd to push them.
	_claude_experimental_icons_enabled = bool(SavedSettings.get_value(SETTING_CLAUDE_EXPERIMENTAL_ICONS, false))
	_title_font = _make_font(34)
	_header_font = _make_font(24)
	_body_font = _make_font(19)
	_small_font = _make_font(16)

	_list_http = HTTPRequest.new()
	_list_http.pause_mode = Node.PAUSE_MODE_PROCESS
	_list_http.body_size_limit = MAX_LIST_RESPONSE_BYTES
	_list_http.connect("request_completed", self, "_on_list_request_completed")
	add_child(_list_http)

	_detail_http = HTTPRequest.new()
	_detail_http.pause_mode = Node.PAUSE_MODE_PROCESS
	_detail_http.body_size_limit = MAX_REPLAY_PAYLOAD_BYTES + 4096
	_detail_http.connect("request_completed", self, "_on_detail_request_completed")
	add_child(_detail_http)

	_upload_http = HTTPRequest.new()
	_upload_http.pause_mode = Node.PAUSE_MODE_PROCESS
	_upload_http.body_size_limit = MAX_REPLAY_PAYLOAD_BYTES + 4096
	_upload_http.connect("request_completed", self, "_on_upload_request_completed")
	add_child(_upload_http)

	_build_modal()
	_build_access_button()
	var recorder_script = ModPaths.try_load(ModPaths.path("CouncilRecorderClient.gd"))
	if recorder_script != null and recorder_script.can_instance():
		_council_recorder = recorder_script.new()
		add_child(_council_recorder)


func _unhandled_input(event: InputEvent) -> void:
	if _modal_root != null and _modal_root.visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		if _export_root != null and _export_root.visible:
			_close_export_picker()
		else:
			close_hub()
		get_tree().set_input_as_handled()


func open_hub() -> void:
	if tas_tool != null and tas_tool.has_method("_open_module_page") and tas_tool._open_module_page("replays"):
		return
	_modal_root.visible = true
	_refresh_list()

func open_council() -> void:
	if tas_tool != null and tas_tool.has_method("_open_module_page") and tas_tool._open_module_page("council"):
		return
	ensure_council()
	if _council != null and is_instance_valid(_council):
		_council.open()

func ensure_council() -> void:
	if (_council == null or not is_instance_valid(_council)) and _council_recorder != null and ModPaths.has("LevelCouncil.gd"):
		_council = load(ModPaths.path("LevelCouncil.gd")).new()
		add_child(_council)
		_council.build(self)
		_council.worker = _council_recorder
		var council_store = load(get_script().resource_path.get_base_dir().plus_file("ObservedCaptureStore.gd")).new()
		council_store.directory = _council_recorder.directory.plus_file("captures")
		_observed_library.store = council_store


func close_hub() -> void:
	if _export_root != null:
		_export_root.visible = false
	_modal_root.visible = false


func is_open() -> bool:
	return _modal_root != null and _modal_root.visible


# Called by TASTool.gd's Settings -> Client Tools -> COMMUNITY REPLAY HUB
# toggle -- same pattern as CosmeticSandbox.gd's set_gui_enabled(). This is
# the ONLY way to open this window; it has no button anywhere inside
# TASTool.gd's own menu, matching every other independent client tool
# window (Avatar Sandbox, etc).
func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if _access_button != null and is_instance_valid(_access_button):
		_access_button.visible = false
	if not value:
		close_hub()


# Called by TASTool.gd's _apply_claude_experimental_icons() -- same pattern
# as CosmeticSandbox.gd/TASMacroEditor.gd. This window has no approved
# title icon asset of its own yet (only goobplayability/debug_logs/
# cosmetic_sandbox/practice_mode/timeline_editor exist under
# user://mod/icons/), so this only flips the color/font theme, not an icon.
func set_claude_experimental_icons_enabled(value: bool) -> void:
	_claude_experimental_icons_enabled = value


func _build_access_button() -> void:
	# Workspace owns module access; no standalone Replay Hub launcher.
	if _access_button != null and is_instance_valid(_access_button):
		_access_button.hide()
func _build_modal() -> void:
	_modal_root = Control.new()
	_modal_root.name = "ReplayHubModal"
	_modal_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.visible = false
	add_child(_modal_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	dim.color = Color(0.015, 0.025, 0.08, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_top = 0.08
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.92
	panel.add_stylebox_override("panel", _flat_style(NAVY, Color(0.49, 0.78, 1.0, 0.9), 6, 28))
	_modal_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 24)
	margin.add_constant_override("margin_right", 24)
	margin.add_constant_override("margin_top", 20)
	margin.add_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_constant_override("separation", 12)
	margin.add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_constant_override("separation", 12)
	root_vbox.add_child(header)
	var title := _make_label("REPLAY HUB", _title_font, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var badge := _make_label("  READ-ONLY  ", _small_font, Color(0.72, 1.0, 0.87))
	badge.add_stylebox_override("normal", _flat_style(Color(0.05, 0.32, 0.23, 1.0), GREEN, 3, 99))
	badge.valign = Label.VALIGN_CENTER
	header.add_child(badge)
	var close := _make_button("×", PINK_DARK, 22)
	close.rect_min_size = Vector2(60, 54)
	close.connect("pressed", self, "close_hub")
	header.add_child(close)

	var subtitle := _make_label("Community macros and local observed captures. Observations are not verified replays.", _small_font, DIM)
	subtitle.autowrap = true
	root_vbox.add_child(subtitle)

	var tab_row := HBoxContainer.new()
	tab_row.add_constant_override("separation", 8)
	root_vbox.add_child(tab_row)
	_tab_buttons = []
	for i in range(TAB_TITLES.size()):
		var tab_btn := _make_button(TAB_TITLES[i], PINK if i == _active_tab else BLUE, 12)
		tab_btn.rect_min_size = Vector2(88, 36)
		tab_btn.toggle_mode = true
		tab_btn.pressed = (i == _active_tab)
		tab_btn.connect("pressed", self, "_on_tab_pressed", [i])
		tab_row.add_child(tab_btn)
		_tab_buttons.append(tab_btn)
	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)
	var refresh_btn := _make_button("⟳ REFRESH", BLUE, 15)
	refresh_btn.connect("pressed", self, "_refresh_list")
	tab_row.add_child(refresh_btn)
	var export_btn := _make_button("SHARE A MACRO SLOT...", GREEN, 14)
	_community_export = export_btn
	export_btn.hint_tooltip = "Upload one of your saved local Macro Slots to the Replay Hub, or copy it as SQL instead."
	export_btn.connect("pressed", self, "_open_export_picker")
	root_vbox.add_child(export_btn)

	_status_label = _make_label("", _small_font, DIM)
	root_vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	_community_scroll = scroll
	scroll.rect_min_size = Vector2(0, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_constant_override("separation", 10)
	scroll.add_child(_list_box)
	_observed_library = load(get_script().resource_path.get_base_dir().plus_file("ObservedLibrary.gd")).new()
	_observed_scroll = ScrollContainer.new()
	_observed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_observed_scroll.rect_min_size.y = 160
	root_vbox.add_child(_observed_scroll)
	_observed_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_observed_scroll.add_child(_observed_library)
	_observed_library.configure(self)
	_observed_library.hide()
	_observed_scroll.hide()

	_export_root = _build_export_picker()
	_modal_root.add_child(_export_root)


func _build_export_picker() -> Control:
	var root := Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.3
	panel.anchor_top = 0.22
	panel.anchor_right = 0.7
	panel.anchor_bottom = 0.78
	panel.add_stylebox_override("panel", _flat_style(NAVY, Color(0.49, 0.78, 1.0, 0.9), 4, 20))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 18)
	margin.add_constant_override("margin_right", 18)
	margin.add_constant_override("margin_top", 16)
	margin.add_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := _make_label("SHARE A MACRO SLOT", _header_font, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _make_button("×", PINK_DARK, 18)
	close.rect_min_size = Vector2(48, 44)
	close.connect("pressed", self, "_close_export_picker")
	header.add_child(close)

	vbox.add_child(_make_label("Pick a saved local Macro Slot below. UPLOAD sends it straight to the Hub under the name below; COPY SQL instead puts a ready-to-run INSERT statement on your clipboard to paste into the Supabase SQL editor yourself.", _small_font, DIM))

	var author_row := HBoxContainer.new()
	author_row.add_constant_override("separation", 10)
	vbox.add_child(author_row)
	author_row.add_child(_make_label("Your name:", _small_font, DIM))
	_author_field = LineEdit.new()
	_author_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_author_field.max_length = 40
	_author_field.placeholder_text = "Anonymous"
	_author_field.text = str(SavedSettings.get_value(SETTING_AUTHOR_NAME, ""))
	_author_field.connect("text_changed", self, "_on_author_field_changed")
	if _body_font != null:
		_author_field.add_font_override("font", _body_font)
	_author_field.add_stylebox_override("normal", _flat_style(NAVY_2, WHITE, 2, 10))
	_author_field.add_stylebox_override("focus", _flat_style(NAVY_2, PINK, 2, 10))
	_author_field.add_color_override("font_color", _theme_text(WHITE))
	_author_field.add_color_override("cursor_color", _theme_text(WHITE))
	author_row.add_child(_author_field)

	var scroll := ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_export_list_box = VBoxContainer.new()
	_export_list_box.add_constant_override("separation", 6)
	_export_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_export_list_box)

	return root


func _close_export_picker() -> void:
	if _export_root != null:
		_export_root.visible = false


# ----------------------------------------------------------------------
#  Tabs / list fetching
# ----------------------------------------------------------------------
func _on_tab_pressed(index: int) -> void:
	_active_tab = index
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		var is_active := (i == index)
		btn.pressed = is_active
		_style_button(btn, PINK if is_active else BLUE, 18, 4)
		btn.add_font_override("font", _small_font)
	_refresh_list()


func _refresh_list() -> void:
	var observed = _active_tab == TAB_OBSERVED
	_observed_library.visible = observed
	_observed_scroll.visible = observed
	_community_scroll.visible = not observed
	_community_export.visible = not observed
	_status_label.visible = not observed
	if observed:
		if _list_busy:
			_list_http.cancel_request()
			_list_busy = false
		_observed_library.refresh()
		return
	if _list_busy:
		return
	_list_busy = true
	_set_status("Loading...")
	_clear_list()
	var url := _list_url_for_tab(_active_tab)
	if _list_http.request(url, _auth_headers(), true, HTTPClient.METHOD_GET) != OK:
		_list_busy = false
		_set_status("Couldn't start the request.")


func _list_url_for_tab(tab: int) -> String:
	var base := SUPABASE_URL + "/rest/v1/" + REPLAYS_TABLE
	var select := "select=id,title,author,level,run_time_ms,compatibility,featured,created_at"
	if tab == TAB_FEATURED:
		return "%s?%s&featured=eq.true&order=created_at.desc&limit=%d" % [base, select, LIST_LIMIT]
	elif tab == TAB_BY_LEVEL:
		return "%s?%s&order=level.asc,created_at.desc&limit=%d" % [base, select, LIST_LIMIT * 3]
	else:
		return "%s?%s&order=created_at.desc&limit=%d" % [base, select, LIST_LIMIT]


func _auth_headers() -> PoolStringArray:
	return PoolStringArray([
		"apikey: " + OnlineConfig.anon_key(),
		"Authorization: Bearer " + OnlineConfig.anon_key(),
		"Accept: application/json",
	])


func _on_list_request_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	_list_busy = false
	if _active_tab == TAB_OBSERVED:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_set_status("Couldn't reach the Replay Hub (HTTP %d)." % response_code)
		return
	if body.size() <= 0 or body.size() > MAX_LIST_RESPONSE_BYTES:
		_set_status("Replay list response had an invalid size.")
		return
	var parsed := JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY:
		_set_status("Replay list response was not valid JSON.")
		return
	var rows: Array = parsed.result
	_clear_list()
	if rows.empty():
		_set_status("No replays here yet.")
		return
	var shown := 0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_list_box.add_child(_build_replay_card(row))
		shown += 1
	_set_status("%d replay(s)." % shown)


func _clear_list() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		child.queue_free()


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


# ----------------------------------------------------------------------
#  Replay cards
# ----------------------------------------------------------------------
func _build_replay_card(row: Dictionary) -> Control:
	var id := str(row.get("id", ""))
	var title := str(row.get("title", "Untitled Replay"))
	var author := str(row.get("author", "Anonymous"))
	var level := str(row.get("level", "?"))
	var run_time_ms := int(row.get("run_time_ms", 0))
	var compatibility := str(row.get("compatibility", "unknown"))
	var featured := bool(row.get("featured", false))

	var card := PanelContainer.new()
	card.add_stylebox_override("panel", _flat_style(NAVY_2, Color(1, 1, 1, 0.18), 2, 14))
	var row_box := HBoxContainer.new()
	row_box.add_constant_override("separation", 14)
	card.add_child(row_box)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(info)
	var title_row := HBoxContainer.new()
	title_row.add_constant_override("separation", 8)
	info.add_child(title_row)
	title_row.add_child(_make_label(title, _header_font, WHITE))
	if featured:
		title_row.add_child(_make_label("★ FEATURED", _small_font, Color(1.0, 0.82, 0.25)))
	var meta := "%s  ·  %s  ·  %s  ·  v%s" % [author, level, _format_time_ms(run_time_ms), compatibility]
	info.add_child(_make_label(meta, _small_font, DIM))

	var actions := HBoxContainer.new()
	actions.add_constant_override("separation", 8)
	row_box.add_child(actions)
	var download_btn := _make_button("DOWNLOAD", BLUE, 15)
	download_btn.rect_min_size = Vector2(140, 0)
	download_btn.connect("pressed", self, "_on_download_pressed", [id, title])
	actions.add_child(download_btn)
	var play_btn := _make_button("▶ PLAY", GREEN, 15)
	play_btn.rect_min_size = Vector2(120, 0)
	play_btn.connect("pressed", self, "_on_play_pressed", [id, title])
	actions.add_child(play_btn)

	return card


func _format_time_ms(ms: int) -> String:
	if ms <= 0:
		return "--:--"
	var total_seconds := ms / 1000
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	var millis := ms % 1000
	return "%d:%02d.%03d" % [minutes, seconds, millis]
