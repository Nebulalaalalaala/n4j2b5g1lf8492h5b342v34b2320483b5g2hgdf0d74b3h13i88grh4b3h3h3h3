extends CanvasLayer

# Goobplayability -- Public Match Map Preview
#
# A public game server sends every level chosen for the match in game_metadata
# when the client joins. This module only presents that already-received data;
# it does not predict random maps. Top rated uses the native batch query,
# on demand, with a five-minute cache and no per-level requests.

const COLOR_PANEL_BG: = Color(0, 0.129412, 0.262745, 0.98)
const COLOR_CARD_BG: = Color(0.0, 0.18, 0.34, 0.90)
const COLOR_PANEL_BORDER: = Color(0, 0, 0, 0.64)
const COLOR_BLUE: = Color(0.211765, 0.541176, 0.854902)
const COLOR_GREEN: = Color(0.117647, 0.690196, 0.423529)
const COLOR_PINK: = Color(0.8, 0.117647, 0.439216)
const COLOR_ORANGE: = Color(1.0, 0.60, 0.10)
const COLOR_WHITE: = Color.white
const COLOR_TEXT_DIM: = Color(0.72, 0.82, 0.95)

var tas_tool = null
var gui_enabled: = true
var _poll_timer: = 0.0
var _seen_game_id: = 0
var _presented_signature: = ""
var _current_maps: = []
var _top_rated = false
var _ratings_cache = {}
var _ratings_busy = false
var _ratings_last_request = -600000
var _rating_period = 0

var _access_button: Button = null
var _modal_root: Control = null
var _maps_list: VBoxContainer = null
var _subtitle_label: Label = null
var _rating_views
var _page_title

func set_catalog_mode(value):
	_top_rated = value
	if _page_title != null:
		_page_title.text = "TOP RATED LEVELS" if value else "MATCH MAPS"
	if _rating_views != null:
		_rating_views.visible = value
	if not value:
		_render_maps()


func _ready() -> void:
	layer = 153
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)


func configure(owner_tool) -> void:
	tas_tool = owner_tool
	_build_ui()


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if not value:
		close_window()
		_current_maps.clear()
	if _access_button != null and is_instance_valid(_access_button):
		_access_button.visible = false


func set_claude_experimental_icons_enabled(_value: bool) -> void:
	pass


func is_open() -> bool:
	return _modal_root != null and is_instance_valid(_modal_root) and _modal_root.visible


func open_window() -> void:
	if tas_tool != null and tas_tool.has_method("_open_module_page") and tas_tool._open_module_page("rated" if _top_rated else "maps"):
		return
	if not gui_enabled:
		return
	_render_maps()
	_modal_root.visible = true
	if _top_rated:
		_show_top_rated(_rating_period)


func close_window() -> void:
	if _modal_root != null and is_instance_valid(_modal_root):
		_modal_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close_window()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer < 0.25:
		return
	_poll_timer = 0.0
	_poll_for_match_maps()


func _find_game():
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_find_game"):
		return tas_tool.call("_find_game")
	return null


func _poll_for_match_maps() -> void:
	var game = _find_game()
	if game == null or not is_instance_valid(game):
		_reset_for_no_game()
		return
	var game_id: int = game.get_instance_id()
	if game_id != _seen_game_id:
		_seen_game_id = game_id
		_presented_signature = ""
		_current_maps.clear()
		if not _modal_root.has_meta("shell_embedded"):
			close_window()
	if not gui_enabled or not _is_public_match(game):
		if _access_button != null:
			_access_button.visible = false
		return
	var metadata = game.get("game_metadata")
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	var level_data = metadata.get("level_data", {})
	if typeof(level_data) != TYPE_DICTIONARY or level_data.empty():
		return
	var signature: String = "%d:%d" % [game_id, level_data.hash()]
	_current_maps = _parse_maps(level_data)
	if _access_button != null:
		_access_button.visible = false
	if _current_maps.empty() or signature == _presented_signature:
		return
	_presented_signature = signature
	_render_maps()
	# Match data refresh must not open a window; access lives in Workspace.


func _reset_for_no_game() -> void:
	if _seen_game_id == 0:
		return
	_seen_game_id = 0
	_presented_signature = ""
	_current_maps.clear()
	if not _modal_root.has_meta("shell_embedded"):
		close_window()
	elif not _top_rated:
		_render_maps()
	if _access_button != null:
		_access_button.visible = false


func _is_public_match(game) -> bool:
	var scene = get_tree().current_scene
	if scene == null or scene.name != "ClientScene":
		return false
	var metadata = game.get("game_metadata")
	if typeof(metadata) == TYPE_DICTIONARY and str(metadata.get("lobby_type", "")) == "custom":
		return false
	var game_data = game.get("wp_game_data")
	if game_data != null:
		for flag_name in ["is_level_editor", "is_time_trial", "is_tutorial"]:
			if flag_name in game_data and bool(game_data.get(flag_name)):
				return false
	return true


func _parse_maps(level_data: Dictionary) -> Array:
	var parsed_maps: = []
	var numeric_keys: = []
	for raw_key in level_data.keys():
		var key_text: String = str(raw_key)
		if key_text.is_valid_integer():
			numeric_keys.append(int(key_text))
	numeric_keys.sort()
	numeric_keys.invert()
	for player_key in numeric_keys:
		var raw_level = level_data.get(str(player_key), level_data.get(player_key, null))
		var data = raw_level
		if typeof(raw_level) == TYPE_STRING:
			data = parse_json(raw_level)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var metadata = data.get("metadata", {})
		if typeof(metadata) != TYPE_DICTIONARY:
			continue
		var mode: String = str(metadata.get("game_mode", "Race"))
		if mode == "Lobby" or player_key <= 0:
			continue
		parsed_maps.append({
			"players": player_key,
			"name": str(metadata.get("name", "Unknown map")),
			"mode": mode,
			"author": str(metadata.get("author_name", "")),
			"rating": float(metadata.get("rating", 0.0)),
		})
	return parsed_maps


func _build_ui() -> void:
	if tas_tool == null or not is_instance_valid(tas_tool):
		return
	var access: Button = _make_button("MAPS", COLOR_BLUE, 132)
	access.anchor_left = 1.0
	access.anchor_right = 1.0
	access.margin_left = -170.0
	access.margin_right = -38.0
	access.margin_top = 38.0
	access.margin_bottom = 92.0
	access.visible = false
	access.hint_tooltip = "Show every map selected for this public match"
	access.connect("pressed", self, "open_window")
	add_child(access)
	_access_button = access

	var root: = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	_modal_root = root

	var shade: = ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.74)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)

	var panel: = PanelContainer.new()
	panel.anchor_left = 0.17
	panel.anchor_top = 0.11
	panel.anchor_right = 0.83
	panel.anchor_bottom = 0.89
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_PANEL_BG, COLOR_PANEL_BORDER, 4, 24))
	root.add_child(panel)

	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)

	var column: = VBoxContainer.new()
	column.add_constant_override("separation", 12)
	margin.add_child(column)
	var header: = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	column.add_child(header)
	var title: Label = _make_label("MATCH MAPS", 36, COLOR_WHITE)
	_page_title = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = _make_button("GOT IT", COLOR_GREEN, 140)
	close_button.connect("pressed", self, "close_window")
	header.add_child(close_button)

	_subtitle_label = _make_label("The server selected these maps when the match was created.", 18, COLOR_TEXT_DIM)
	_subtitle_label.autowrap = true
	column.add_child(_subtitle_label)
	var views = HBoxContainer.new()
	_rating_views = views
	views.visible = false
	column.add_child(views)
	for entry in [["All time", 0], ["Today", 3], ["Week", 2], ["Month", 1]]:
		var view_button = _make_button(entry[0], COLOR_BLUE, 100)
		view_button.connect("pressed", self, "_show_top_rated", [entry[1]])
		views.add_child(view_button)

	var scroll: = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_maps_list = VBoxContainer.new()
	_maps_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maps_list.add_constant_override("separation", 10)
	scroll.add_child(_maps_list)


func _render_maps() -> void:
	if _top_rated:
		return
	if _maps_list == null or not is_instance_valid(_maps_list):
		return
	for child in _maps_list.get_children():
		_maps_list.remove_child(child)
		child.queue_free()
	_subtitle_label.text = "The server selected these maps for this match." if not _current_maps.empty() else "Join a public match to see its maps."
	for index in _current_maps.size():
		var entry: Dictionary = _current_maps[index]
		_maps_list.add_child(_make_map_row(entry, index))
	if _subtitle_label != null and not _current_maps.empty():
		_subtitle_label.text = "%d rounds are available. Player counts choose the next map automatically as people qualify or are eliminated." % _current_maps.size()


func _make_map_row(entry: Dictionary, index: int) -> Control:
	var card: = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = COLOR_ORANGE if str(entry.get("mode", "Race")) == "Knockout" else COLOR_BLUE
	card.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_CARD_BG, accent.darkened(0.45), 3, 16))
	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 14)
	card.add_child(margin)
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 16)
	margin.add_child(row)
	var round_label: Label = _make_label(str(index + 1), 30, accent)
	round_label.rect_min_size = Vector2(40, 0)
	round_label.valign = Label.VALIGN_CENTER
	row.add_child(round_label)
	var info: = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var map_name: Label = _make_label(str(entry.get("name", "Unknown map")).to_upper(), 25, COLOR_WHITE)
	info.add_child(map_name)
	var details: = []
	var author: String = str(entry.get("author", "")).strip_edges()
	if not author.empty():
		details.append("by " + author)
	var rating: float = float(entry.get("rating", 0.0))
	if rating > 0.0:
		details.append("★ %.1f" % rating)
	var detail_text: String = "  •  ".join(details)
	if detail_text.empty():
		detail_text = "Official rotation map"
	info.add_child(_make_label(detail_text, 16, COLOR_TEXT_DIM))
	var mode: String = str(entry.get("mode", "Race"))
	var badge_text: String = "%dP  %s" % [int(entry.get("players", 0)), "ELIM" if mode == "Knockout" else "RACE"]
	var badge: Label = _make_label(badge_text, 22, accent)
	badge.rect_min_size = Vector2(150, 0)
	badge.align = Label.ALIGN_RIGHT
	badge.valign = Label.VALIGN_CENTER
	row.add_child(badge)
	return card


func _show_top_rated(period: int) -> void:
	_top_rated = period >= 0
	if not _top_rated:
		_render_maps()
		return
	_rating_period = period
	var cache = _ratings_cache.get(period, {})
	if not cache.empty() and OS.get_ticks_msec() - cache.time < 300000:
		_render_ratings(cache.levels)
		return
	for child in _maps_list.get_children():
		_maps_list.remove_child(child)
		child.queue_free()
	if _ratings_busy:
		_subtitle_label.text = "Loading ratings…"
		return
	if not Moonlight.is_logged_in():
		_subtitle_label.text = "Sign in to browse top-rated levels."
		return
	if OS.get_ticks_msec() - _ratings_last_request < 10000:
		_subtitle_label.text = "Please wait a few seconds before requesting another period."
		return
	_ratings_busy = true
	_ratings_last_request = OS.get_ticks_msec()
	_subtitle_label.text = "Loading ratings…"
	var response = yield(LevelCloudLoader.async_list_public_top_rated_levels(period), "completed")
	_ratings_busy = false
	if _top_rated and _rating_period != period:
		_subtitle_label.text = "Select the period again in a few seconds to load its ratings."
	if response.has("error"):
		if _top_rated and _rating_period == period:
			_subtitle_label.text = "Ratings unavailable. Try again later."
		return
	var levels = response.get("levels", [])
	if not levels is Array:
		if _top_rated and _rating_period == period:
			_subtitle_label.text = "Ratings response was unavailable."
		return
	_ratings_cache[period] = {"time": OS.get_ticks_msec(), "levels": levels}
	if _top_rated and _rating_period == period:
		_render_ratings(levels)

func _render_ratings(levels: Array) -> void:
	for child in _maps_list.get_children():
		_maps_list.remove_child(child)
		child.queue_free()
	_subtitle_label.text = "Server-ranked ratings · cached for 5 minutes · fewer than 10 votes = small sample"
	var packed = load("res://project_specific/level_editor/LevelEditor_LevelRow.tscn")
	var seen = {}
	for data in levels:
		if not data is Dictionary or str(data.get("id", "")).empty() or seen.has(data.id):
			continue
		seen[data.id] = true
		var row_data = data.duplicate(true)
		if not row_data.has("update_time"):
			row_data["update_time"] = "1970-01-01T00:00:00Z"
		var item = packed.instance()
		_maps_list.add_child(item)
		item.show_level_data(data.id, row_data)
		item.time_updated_label.visible = data.has("update_time")
		item.favorites_parent.visible = false
		item.rating_parent.visible = true
		if int(data.get("rating_count", 0)) < 10:
			item.name_label.text += " · small sample"
		item.connect("button_pressed", self, "_open_rated_level", [data.id, data])
	if levels.empty():
		_subtitle_label.text = "No rated levels returned for this period."

func _open_rated_level(id: String, data: Dictionary) -> void:
	var scene = get_tree().current_scene
	var playground = scene.find_node("PLAYGROUND", true, false) if scene != null else null
	if playground == null or not playground.has_method("on_level_selected"):
		_subtitle_label.text = "Return to the main menu to play a discovered level."
		return
	close_window()
	playground.on_level_selected(id, data)

func _make_label(text: String, size: int, color: Color) -> Label:
	return tas_tool.call("_make_label", text, tas_tool.call("_make_font", size), color) as Label


func _make_button(text: String, color: Color, width: int) -> Button:
	var button: Button = tas_tool.call("_make_button", text, color, width) as Button
	button.add_font_override("font", tas_tool.call("_make_font", 20))
	return button
