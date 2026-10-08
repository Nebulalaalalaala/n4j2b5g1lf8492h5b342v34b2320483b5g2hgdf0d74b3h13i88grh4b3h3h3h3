extends VBoxContainer

# Shared presentation for the native Leaderboard tab and Workspace Wins page.
# Ranking, snapshots, imports and refreshes remain owned by WinsLeaderboard.
const BG = Color("181c20")
const SURFACE = Color("22282c")
const BORDER = Color("343c40")
const INK = Color("eef1ed")
const MUTED = Color("9ba8ad")
const MINT = Color("9dd6bd")
const MEDALS = [Color("e8c47f"), Color("bdcbd3"), Color("dba991")]
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
	return _fonts[size]

func box(fill: Color, border: Color = BORDER, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func text(value: String, size: int = 16, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = value
	label.add_font_override("font", font(size))
	label.add_color_override("font_color", color)
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
	btn.add_stylebox_override("hover", box(Color("2d3838"), MINT))
	btn.add_stylebox_override("pressed", box(Color("30483d"), MINT))
	btn.connect("pressed", self, method, args)
	return btn

func build(source, tool_ref) -> void:
	module = source
	owner_tool = tool_ref
	pause_mode = Node.PAUSE_MODE_PROCESS
	add_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	rect_min_size.y = 510
	var header = HBoxContainer.new()
	add_child(header)
	var title = text("Most wins", 27)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(text("COMMUNITY LEADERBOARD", 12, MINT))
	var periods = HBoxContainer.new()
	periods.add_constant_override("separation", 6)
	add_child(periods)
	for item in [["All time", "all_time"], ["Daily", "daily"], ["Weekly", "weekly"], ["Monthly", "monthly"], ["Yearly", "yearly"]]:
		var btn = button(item[0], "set_period", [item[1]])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		periods.add_child(btn)
		period_buttons[item[1]] = btn
	history = OptionButton.new()
	history.add_font_override("font",font(15))
	history.hint_tooltip = "View saved standings as of a date. Period totals use only observations available by that date."
	history.connect("item_selected",self,"select_history")
	add_child(history)
	podium = HBoxContainer.new()
	podium.add_constant_override("separation", 10)
	add_child(podium)
	var toolbar = HBoxContainer.new()
	toolbar.add_constant_override("separation", 8)
	add_child(toolbar)
	search = LineEdit.new()
	search.placeholder_text = "Find a player"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_font_override("font", font(15))
	search.add_color_override("font_color", INK)
	search.add_stylebox_override("normal", box(BG))
	search.add_stylebox_override("focus", box(BG, MINT))
	search.connect("text_changed", self, "_search_changed")
	toolbar.add_child(search)
	refresh_button = button("Refresh", "_refresh_requested")
	toolbar.add_child(refresh_button)
	toolbar.add_child(button("Import CSV", "_import_requested"))
	var table_header = HBoxContainer.new()
	table_header.add_constant_override("separation", 12)
	add_child(table_header)
	var rank = text("RANK", 12, MUTED)
	rank.rect_min_size.x = 62
	table_header.add_child(rank)
	var player = text("PLAYER", 12, MUTED)
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_header.add_child(player)
	table_header.add_child(text("WINS", 12, MUTED))
	var scroll = ScrollContainer.new()
	scroll.rect_min_size.y = 160
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)
	rows_parent = VBoxContainer.new()
	rows_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_parent.add_constant_override("separation", 4)
	scroll.add_child(rows_parent)
	count_label = text("", 13, MUTED)
	add_child(count_label)
	coverage = text("", 12, MUTED)
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
		period_buttons[key].add_stylebox_override("normal", box(Color("30483d"), MINT) if key == period else box(SURFACE))
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
	for index in range(min(3, _ranked.size())):
		_leader(_ranked[index], index)
	_render_rows()

func _leader(entry: Dictionary, index: int) -> void:
	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", box(SURFACE, MEDALS[index]))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1
	podium.add_child(panel)
	var content = VBoxContainer.new()
	content.add_constant_override("separation", 3)
	panel.add_child(content)
	content.add_child(text("#%d" % (index + 1), 13, MEDALS[index]))
	var username = text(str(entry.get("username", "Unknown")), 16)
	username.clip_text = true
	username.hint_tooltip = username.text
	content.add_child(username)
	content.add_child(text(number(int(entry.get("wins", 0))) + " wins", 22, MEDALS[index]))

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
	panel.add_stylebox_override("panel", box(SURFACE if index % 2 == 0 else BG, BORDER, 10))
	rows_parent.add_child(panel)
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
