extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")

# Compact Journey result shown over the game's own end-of-match screen (WINNER,
# eliminated, back home) instead of opening the whole Journey menu. Right side,
# out of the way of the native title, podium and HOME button. "Details" opens
# the full breakdown; the X (or leaving the screen) dismisses it.
const ORDER = ["win", "placement", "exploration", "challenge", "activity", "record"]
const WIDTH = 760
# Drawn at Journey's scale, then enlarged to sit beside the native WINNER art.
const SCALE = 1.7

var controller
var ui
var definitions
var receipt = []
var xp_before = 0
var hud = null
var _count
var _total = 0
var _card
var _rows_col
var _display_scale = SCALE
var _account = ""
var sequence
var _reward_rows = {}

func setup(owner, awards, before, hud_node):
	controller = owner
	_account = str(owner.ledger.account_id)
	receipt = awards
	xp_before = int(before)
	hud = weakref(hud_node) if hud_node != null else null
	var base = get_script().resource_path.get_base_dir()
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()

func _ready():
	layer = 80
	ui.reduced_motion = bool(Data.preference(self, controller, "reduced_motion", false))
	var groups = {}
	var seen = {}
	for entry in receipt:
		if seen.has(str(entry.id)):
			continue
		seen[str(entry.id)] = true
		_total += int(entry.amount)
		groups[entry.category] = int(groups.get(entry.category, 0)) + int(entry.amount)
	var after_xp = xp_before + _total
	var before = definitions.rank_at(xp_before)
	var after = definitions.rank_at(after_xp)
	var promoted = int(after.id) > int(before.id)
	var celebrations = str(Data.preference(self, controller, "celebrations", "all"))
	var celebrate = promoted and (celebrations == "all" or (celebrations == "leagues" and str(before.art) != str(after.art)))
	var root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	scale = Vector2(SCALE, SCALE)
	_fit()
	get_viewport().connect("size_changed", self, "_fit")
	# Same restrained navy surface as Journey, without a new button-like rim.
	_card = PanelContainer.new()
	var style = ui.flat(ui.NAVY, 40, 30, 0, ui.INK, true)
	_card.add_stylebox_override("panel", style)
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.06
	_card.anchor_bottom = 0.94
	_card.margin_left = -WIDTH - 56
	_card.margin_right = -56
	_card.margin_top = 0
	_card.margin_bottom = 0
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_card)
	var col = ui.box(_card, true, 14)
	var head = ui.box(col, false, 10)
	var titles = ui.grow(ui.box(head, true, 0))
	ui.label(titles, "JOURNEY", "caps", ui.SKY_LIGHT)
	_count = ui.label(titles, "+0 XP", "num_l", ui.YELLOW)
	_count.add_font_override("font", ui.font("display", 58, 6))
	var close = ui.button(head, "", "small", self, "dismiss", null, "close")
	close.size_flags_vertical = 0
	close.hint_tooltip = "Close"
	# Rank and progress.
	var lg = ui.league(before)
	var rank_row = ui.box(col, false, 14)
	var stage = Control.new()
	stage.rect_min_size = Vector2(96, 96)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank_row.add_child(stage)
	var rcol = ui.grow(ui.box(rank_row, true, 6))
	rcol.alignment = BoxContainer.ALIGN_CENTER
	var rank_name = ui.label(rcol, str(before.name).to_upper(), "h2")
	var bar = ui.bar(rcol, 0.0, lg.base, 30)
	var caption = ui.label(rcol, "", "small", ui.MUTED)
	var status = ui.label(titles, "", "small", ui.MUTED)
	status.hide()
	var pill = null
	if promoted:
		pill = ui.pill(col, "Promoted to " + str(after.name), ui.INK, ui.YELLOW, "sparkle")
		pill.size_flags_horizontal = 0
		pill.modulate.a = 0.0
	# Where the XP came from.
	var rows = []
	var scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var scrollbar = scroll.get_v_scrollbar()
	scrollbar.rect_min_size.x = 10
	scrollbar.add_stylebox_override("scroll", ui.flat(Color(0, 0, 0, 0), 5, 0, 0, ui.INK, false))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		scrollbar.add_stylebox_override(state, ui.flat(ui.NAVY_3 if state == "grabber" else ui.SKY_LIGHT, 5, 0, 0, ui.INK, false))
	_rows_col = ui.box(scroll, true, 18)
	_rows_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for info in Data.reward_rows(receipt):
		var row = ui.box(_rows_col, false, 16)
		var color = ui.YELLOW if info.key in ["bonus", "sweep"] else ui.WHITE
		ui.icon(row, info.icon, 38, color)
		ui.grow(ui.label(row, str(info.name), "body", color))
		ui.label(row, ui.xp_text(info.amount), "h3", color)
		rows.append(row)
		_reward_rows[info.key] = row
	var details = ui.button(col, "Details", "quiet", self, "open_details", null, "chevron_right")
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var proceed = ui.button(col, "Continue", "primary", self, "dismiss")
	proceed.name = "Continue"
	proceed.rect_min_size.y = 80
	proceed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Data.shine(proceed)
	sequence = load(ModPaths.JOURNEY_DIR + "ui/JourneyRewardSequence.gd").new()
	add_child(sequence)
	sequence.configure(ui, definitions, receipt, xp_before, {"count": _count, "bar": bar, "stage": stage, "badge_size": 96,
		"name": rank_name, "caption": caption, "status": status, "celebrations": celebrations})
	sequence.connect("cue", self, "_play")
	sequence.connect("beat", self, "_reward_beat")
	sequence.connect("finished", self, "_sequence_done", [pill])
	sequence.start()
	_play("open")
	if ui.reduced_motion:
		for info in Data.reward_rows(receipt):
			if info.key == "sweep": _reward_beat(info)
		return
	var t = Tween.new()
	root.add_child(t)
	_card.rect_pivot_offset = Vector2(WIDTH, 250)
	t.interpolate_property(_card, "modulate:a", 0.0, 1.0, 0.2)
	t.interpolate_property(_card, "margin_left", -WIDTH + 140, -WIDTH - 56, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(_card, "margin_right", 140, -56, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	for i in rows.size():
		ui.pop_in(t, rows[i], 0.35 + 0.08 * i, 0.28, 0.9)
	t.start()

func _sequence_done(pill):
	if is_instance_valid(pill): pill.modulate.a = 1.0

func _reward_beat(info):
	if controller.has_method("reward_beat"): controller.reward_beat(info, receipt)
	if ui.reduced_motion: return
	var row = _reward_rows.get(info.key)
	if not is_instance_valid(row): return
	var t = Tween.new()
	row.add_child(t)
	t.interpolate_property(row, "modulate", Color(1.25, 1.25, 1.25), Color.white, 0.3)
	t.start()

func _fit():
	var root = get_node_or_null("Root")
	if root != null:
		var bounds = get_viewport().get_visible_rect().size
		_display_scale = min(clamp(bounds.y / 1920.0 * SCALE, 0.2, SCALE), bounds.x / (WIDTH + 112.0))
		scale = Vector2(_display_scale, _display_scale)
		root.rect_position = Vector2.ZERO
		root.rect_size = get_viewport().get_visible_rect().size / _display_scale

func _counted(value):
	if is_instance_valid(_count):
		_count.text = ui.xp_text(int(value))
		if int(value) < _total and int(value) % 7 == 0:
			_play("tick", 1.0 + float(value) / max(1, _total) * 0.3)

func _process(_delta):
	# A result must not survive its match scene or an account switch.
	if not is_instance_valid(controller) or str(controller.ledger.account_id) != _account or (hud != null and not is_instance_valid(hud.get_ref())):
		queue_free()

func _promoted(badge):
	_play("rankup")
	if is_instance_valid(badge):
		ui.burst(badge)

func _play(key, pitch = 1.0):
	if controller != null and controller.has_method("play_moment"):
		controller.play_moment(key, pitch)
		return
	var screen = controller.screen if controller != null else null
	if is_instance_valid(screen) and screen.has_method("play"):
		screen.play(key, pitch)

# Full breakdown: the Journey overlay in a match, the Journey tab at home.
# Its Back / XP history return to this result, not to the menu.
func open_details():
	var screen = null
	var hud_node = hud.get_ref() if hud != null else null
	if is_instance_valid(hud_node):
		controller.hud.open(weakref(hud_node))
		if is_instance_valid(controller.hud.layer):
			for child in controller.hud.layer.get_children():
				if child.has_method("show_match_results"):
					screen = child
	elif is_instance_valid(controller.screen) and is_instance_valid(controller.navigation):
		controller.navigation.tabs.get_node("ButtonGrouper").set_selected(5)
		screen = controller.screen
	if is_instance_valid(screen) and screen.is_inside_tree():
		if is_instance_valid(controller.get("promotions")):
			screen.set_meta("match_promotions", controller.promotions)
		if is_instance_valid(hud_node):
			screen.set_meta("close_after_results", true)
		screen.show_match_results(receipt, xp_before)
	dismiss()

func dismiss():
	queue_free()
