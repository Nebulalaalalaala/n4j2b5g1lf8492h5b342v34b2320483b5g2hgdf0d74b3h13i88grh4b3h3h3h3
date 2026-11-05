extends VBoxContainer

# Shared presentation for the native Leaderboard tab and Workspace Wins page.
# Ranking, snapshots, imports and refreshes remain owned by WinsLeaderboard.
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")
var BG = Galaxy.color("bg")
var SURFACE = Galaxy.color("surface")
var BORDER = Galaxy.color("border")
var INK = Galaxy.color("ink")
var MUTED = Galaxy.color("muted")
var MINT = Galaxy.color("accent")
var MEDALS = [Color("9a6a00"),Color("646878"),Color("9b573a")] if Galaxy.is_light() else [Color("ffd166"),Color("c9d7e3"),Color("e0a07a")]
var me_name = ""
var me_label: Label
var module = null
var owner_tool = null
var close_workspace_on_profile = false
var period = "all_time"
var period_buttons = {}
var search: LineEdit
var podium: HBoxContainer
var rows_parent: VBoxContainer
var coverage: Label
var count_label: Label
var refresh_button: Button
var _signature = ""
var _ranked = []
var _fonts = {}
var history: OptionButton
var history_date = ""

func font(size: int) -> Font:
	if not _fonts.has(size):
		_fonts[size] = owner_tool.call("_make_font", size)
		GoobStyle.remember_font(_fonts[size])
	return _fonts[size]

func box(fill: Color, border = null, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = BORDER if border==null else border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.anti_aliasing = true
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func text(value: String, size: int = 16, color = null) -> Label:
	var label = Label.new()
	label.text = value
	label.add_font_override("font", font(size))
	label.add_color_override("font_color", INK if color==null else color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func button(value: String, method: String, args: Array = []) -> Button:
	var btn = Button.new()
	btn.text = value
	btn.rect_min_size.y = 36
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_font_override("font", font(15))
	btn.add_color_override("font_color", INK)
	btn.add_color_override("font_color_hover", INK)
	btn.add_color_override("font_color_pressed", MINT)
	btn.add_stylebox_override("normal", box(SURFACE))
	btn.add_stylebox_override("hover", box(Galaxy.color("hover"), MINT))
	btn.add_stylebox_override("pressed", box(Galaxy.color("hover"), MINT))
	btn.connect("pressed", self, method, args)
	return btn

func build(source, tool_ref) -> void:
	module = source
	owner_tool = tool_ref
	pause_mode = Node.PAUSE_MODE_PROCESS
	add_constant_override("separation",14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var intro = PanelContainer.new()
	intro.add_stylebox_override("panel",box(SURFACE,BORDER,16))
	add_child(intro)
	var intro_column = VBoxContainer.new()
	intro_column.add_constant_override("separation",8)
	intro.add_child(intro_column)
	var header = HBoxContainer.new()
	intro_column.add_child(header)
	var title = text("Community standings",21)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(text("UNOFFICIAL",12,MINT))
	var subtitle = text("Wins across saved community snapshots",14,MUTED)
	subtitle.hint_tooltip = "This uses the existing community snapshot service, not an official complete GooberDash ranking. Period gains require boundary snapshots."
	subtitle.mouse_filter = Control.MOUSE_FILTER_PASS
	intro_column.add_child(subtitle)
	var periods = HBoxContainer.new()
	periods.add_constant_override("separation",6)
	intro_column.add_child(periods)
	for item in [["All time","all_time"],["Daily","daily"],["Weekly","weekly"],["Monthly","monthly"],["Yearly","yearly"]]:
		var btn = button(item[0],"set_period",[item[1]])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		periods.add_child(btn)
		period_buttons[item[1]] = btn
	var controls = HBoxContainer.new()
	controls.add_constant_override("separation",8)
	add_child(controls)
	history = OptionButton.new()
	history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.rect_min_size.y = 34
	history.add_font_override("font",font(15))
	for state in ["normal","hover","pressed"]:
		history.add_stylebox_override(state,box(SURFACE,BORDER,10))
	history.add_color_override("font_color",INK)
	history.get_popup().add_font_override("font",font(15))
	history.get_popup().add_stylebox_override("panel",box(SURFACE,BORDER,10))
	history.get_popup().add_color_override("font_color",INK)
	history.hint_tooltip = "Standings as of a saved date; unavailable boundary history is never estimated."
	history.connect("item_selected",self,"select_history")
	controls.add_child(history)
	refresh_button = button("Refresh","_refresh_requested")
	controls.add_child(refresh_button)
	controls.add_child(button("Import CSV","_import_requested"))
	podium = HBoxContainer.new()
	podium.add_constant_override("separation",10)
	add_child(podium)
	var toolbar = HBoxContainer.new()
	toolbar.add_constant_override("separation",8)
	add_child(toolbar)
	search = LineEdit.new()
	search.placeholder_text = "Find a player"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_font_override("font",font(15))
	search.add_color_override("font_color",INK)
	search.add_color_override("cursor_color",MINT)
	search.add_stylebox_override("normal",box(SURFACE))
	search.add_stylebox_override("focus",box(SURFACE,MINT))
	search.connect("text_changed",self,"_search_changed")
	toolbar.add_child(search)
	me_label = text("",14,Galaxy.color("playback"))
	toolbar.add_child(me_label)
	toolbar.add_child(button("Find me","_find_me"))
	var table = PanelContainer.new()
	table.add_stylebox_override("panel",box(SURFACE,BORDER,12))
	add_child(table)
	var table_column = VBoxContainer.new()
	table_column.add_constant_override("separation",10)
	table.add_child(table_column)
	var table_header = HBoxContainer.new()
	table_column.add_child(table_header)
	var rank = text("RANK",12,MUTED)
	rank.rect_min_size.x = 62
	table_header.add_child(rank)
	var player = text("PLAYER",12,MUTED)
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_header.add_child(player)
	table_header.add_child(text("WINS",12,MUTED))
	var scroll = ScrollContainer.new()
	scroll.rect_min_size.y = 250
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	table_column.add_child(scroll)
	rows_parent = VBoxContainer.new()
	rows_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_parent.add_constant_override("separation",4)
	scroll.add_child(rows_parent)
	count_label = text("",13,MUTED)
	table_column.add_child(count_label)
	coverage = text("",13,MUTED)
	coverage.autowrap = true
	add_child(coverage)
	refresh(true)

func set_period(value: String) -> void:
	period = value
	refresh(true)

func refresh(force: bool = false) -> void:
	if search == null:
		return
	if module == null or not is_instance_valid(module):
		_empty("Wins module unavailable.")
		return
	var latest = history_date if not history_date.empty() else str(module.call("_latest_snapshot_key"))
	var snapshots = module.get("_snapshots")
	var busy = bool(module.get("_request_busy"))
	var enabled = bool(module.get("gui_enabled"))
	var error = str(module.get("_view_error")) if "_view_error" in module else ""
	var signature = period + latest + str(snapshots.hash()) + str(busy) + str(enabled) + error
	if signature == _signature and not force:
		return
	_signature = signature
	history.clear()
	history.add_item("Latest available standings")
	history.set_item_metadata(0,"")
	var dates = snapshots.keys()
	dates.sort()
	dates.invert()
	for date in dates:
		history.add_item("As of " + str(date) + " UTC")
		history.set_item_metadata(history.get_item_count()-1,str(date))
		if str(date)==history_date:
			history.select(history.get_item_count()-1)
	refresh_button.disabled = busy or not enabled
	refresh_button.text = "Updating…" if busy else "Refresh"
	for key in period_buttons:
		period_buttons[key].add_stylebox_override("normal", box(Galaxy.color("hover"), MINT) if key == period else box(SURFACE))
	_clear(podium)
	if not enabled:
		_empty("Enable Wins leaderboard in Settings.")
		return
	if latest.empty():
		_empty("Fetching community stats…" if busy else "No snapshot yet. Refresh or import a downloaded CSV.")
		return
	var result = module.call("_period_result", period, latest)
	coverage.text = str(result.get("coverage", "")) + "\nSource: twhlynch.me · unofficial, incomplete player coverage"
	if not error.empty():
		coverage.text += "\n" + error
	if not result.get("available", false):
		_empty(str(result.get("message", "This period needs a boundary snapshot.")), false)
		return
	_ranked = result.get("rows", []).duplicate(true)
	_ranked.sort_custom(module, "_sort_wins_descending")
	for index in [1, 0, 2]:
		if index < _ranked.size():
			_leader(_ranked[index], index)
	me_name = _my_name()
	me_label.text = ""
	if not me_name.empty():
		for index in range(_ranked.size()):
			if str(_ranked[index].get("username", "")).to_lower() == me_name.to_lower():
				me_label.text = "You: #%d" % (index + 1)
				break
	_render_rows()

# Podium: second, first, third; first place stands tallest.
func _leader(entry: Dictionary, index: int) -> void:
	var color = MEDALS[index]
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.25 if index == 0 else 1.0
	column.alignment = BoxContainer.ALIGN_END
	column.rect_min_size.y = 150
	podium.add_child(column)
	var panel = PanelContainer.new()
	var style = box(Color(color.r, color.g, color.b, 0.14), color, 14)
	style.content_margin_top = [26, 16, 10][index]
	style.content_margin_bottom = [26, 16, 10][index]
	panel.add_stylebox_override("panel", style)
	column.add_child(panel)
	var content = VBoxContainer.new()
	content.add_constant_override("separation", 3)
	content.alignment = BoxContainer.ALIGN_CENTER
	panel.add_child(content)
	var place = text(["1st", "2nd", "3rd"][index], 15, color)
	place.align = Label.ALIGN_CENTER
	content.add_child(place)
	var username = text(str(entry.get("username", "Unknown")), [20, 17, 17][index])
	username.clip_text = true
	username.align = Label.ALIGN_CENTER
	username.hint_tooltip = username.text
	content.add_child(username)
	var wins = text(number(int(entry.get("wins", 0))) + " wins", [26, 21, 21][index], color if Galaxy.is_light() else color.lightened(0.1))
	wins.align = Label.ALIGN_CENTER
	content.add_child(wins)

func select_history(index):
	history_date = str(history.get_item_metadata(index))
	refresh(true)

func _search_changed(_query: String) -> void:
	_render_rows()

func _render_rows() -> void:
	_clear(rows_parent)
	var query = search.text.strip_edges().to_lower()
	var matched = 0
	var shown = 0
	for index in range(_ranked.size()):
		var entry = _ranked[index]
		if not query.empty() and not query in str(entry.get("username", "")).to_lower():
			continue
		matched += 1
		if shown >= 100:
			continue
		_add_row(entry, index + 1, shown)
		shown += 1
	count_label.text = "%d tracked · %d matching · showing %d" % [_ranked.size(), matched, shown]
	if shown == 0:
		var message = text("No matching players." if not query.empty() else "No recorded wins for this period.", 16, MUTED)
		rows_parent.add_child(message)

func _add_row(entry: Dictionary, rank: int, index: int) -> void:
	var panel = PanelContainer.new()
	var mine = not me_name.empty() and str(entry.get("username", "")).to_lower() == me_name.to_lower()
	panel.add_stylebox_override("panel", box(Color(0.435, 0.722, 1.0, 0.16) if mine else (SURFACE if index % 2 == 0 else BG), Color("6fb8ff") if mine else BORDER, 10))
	rows_parent.add_child(panel)
	# Thin bar behind the row: wins compared to first place.
	var top = float(_ranked[0].get("wins", 1)) if not _ranked.empty() else 1.0
	var low = float(_ranked[min(_ranked.size(), 100) - 1].get("wins", 0)) if not _ranked.empty() else 0.0
	var fraction = 0.08 + 0.92 * clamp((float(entry.get("wins", 0)) - low) / max(1.0, top - low), 0.0, 1.0)
	panel.connect("draw", self, "_draw_bar", [panel, fraction])
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 12)
	panel.add_child(row)
	var rank_label = text("%02d" % rank, 16, MEDALS[rank - 1] if rank <= 3 else MUTED)
	rank_label.rect_min_size.x = 44
	row.add_child(rank_label)
	var username = button(str(entry.get("username", "Unknown")), "_profile", [str(entry.get("id", ""))])
	username.clip_text = true
	username.align = Button.ALIGN_LEFT
	username.rect_min_size.y = 28
	username.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username.add_stylebox_override("normal", StyleBoxEmpty.new())
	username.hint_tooltip = str(entry.get("username", "")) + " · view profile"
	row.add_child(username)
	if int(entry.get("gained", 0)) > 0:
		var gained = text("+" + number(int(entry.gained)), 14, Color("6fb8ff"))
		gained.hint_tooltip = "Since " + str(entry.get("gained_since", "")) + " UTC"
		gained.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(gained)
	var wins = text(number(int(entry.get("wins", 0))), 17, MINT)
	wins.rect_min_size.x = 85
	wins.align = Label.ALIGN_RIGHT
	row.add_child(wins)

func _empty(message: String, clear_coverage: bool = true) -> void:
	_ranked.clear()
	_clear(rows_parent)
	var label = text(message, 16, MUTED)
	label.autowrap = true
	label.rect_min_size.y = 80
	rows_parent.add_child(label)
	count_label.text = ""
	if clear_coverage:
		coverage.text = "Source: twhlynch.me · community wins snapshots"

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func number(value: int) -> String:
	var digits = str(value)
	var result = ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits.substr(index, 1)
	return result

func _draw_bar(panel: Control, fraction: float) -> void:
	panel.draw_rect(Rect2(Vector2(2, 2), Vector2(max(0.0, (panel.rect_size.x - 4) * fraction), panel.rect_size.y - 4)), Color(MINT.r, MINT.g, MINT.b, 0.08))

func _my_name() -> String:
	var moonlight = get_node_or_null("/root/Moonlight")
	if moonlight == null or moonlight.get("local_account") == null:
		return ""
	var user = moonlight.local_account.get("user")
	return str(user.username) if user != null else ""

func _find_me() -> void:
	if not me_name.empty():
		search.text = me_name
		_render_rows()

func _refresh_requested() -> void:
	if module != null and module.gui_enabled:
		module.call("_request_latest_snapshot", true)
		refresh(true)

func _import_requested() -> void:
	if module != null and module.gui_enabled:
		module.call("_open_import_dialog")

func _profile(id: String) -> void:
	if module != null and module.gui_enabled:
		if close_workspace_on_profile and owner_tool != null:
			owner_tool.call("_on_tab_pressed")
		module.call("_on_wins_row_pressed", id)
