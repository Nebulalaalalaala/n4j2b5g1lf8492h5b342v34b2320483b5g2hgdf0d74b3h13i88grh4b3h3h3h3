extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Compact Journey result shown over the game's own end-of-match screen (WINNER,
# eliminated, back home) instead of opening the whole Journey menu. Right side,
# out of the way of the native title, podium and HOME button. "Details" opens
# the full breakdown; the X (or leaving the screen) dismisses it.
const ORDER = ["win", "placement", "exploration", "challenge", "activity", "record"]
const WIDTH = 500
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

func setup(owner, awards, before, hud_node):
	controller = owner
	receipt = awards
	xp_before = int(before)
	hud = weakref(hud_node) if hud_node != null else null
	var base = get_script().resource_path.get_base_dir()
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()

func _ready():
	layer = 80
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
	var root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	scale = Vector2(SCALE, SCALE)
	_fit()
	get_viewport().connect("size_changed", self, "_fit")
	# Goober Dash look: navy body with the thick white rim of the native buttons.
	_card = PanelContainer.new()
	var style = ui.flat(ui.NAVY, 40, 30, 0, ui.INK, true)
	style.border_width_left = 7
	style.border_width_right = 7
	style.border_width_top = 7
	style.border_width_bottom = 12
	style.border_color = Color.white
	_card.add_stylebox_override("panel", style)
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.margin_left = -WIDTH - 56
	_card.margin_right = -56
	_card.margin_top = -250
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
	var lg = ui.league(after)
	var rank_row = ui.box(col, false, 14)
	var badge = ui.badge(rank_row, after, 96)
	badge.rect_pivot_offset = Vector2(48, 48)
	var rcol = ui.grow(ui.box(rank_row, true, 6))
	rcol.alignment = BoxContainer.ALIGN_CENTER
	ui.label(rcol, str(after.name).to_upper(), "h2")
	var span = max(1, int(after.next_xp) - int(after.xp))
	var from_ratio = 0.0 if promoted else float(xp_before - int(after.xp)) / span
	var to_ratio = float(after_xp - int(after.xp)) / span
	var bar = ui.bar(rcol, from_ratio, lg.base, 20)
	var next = definitions.rank_at(int(after.next_xp))
	ui.label(rcol, "%s XP to %s" % [ui.thousands(int(after.next_xp) - after_xp), next.name], "small", ui.MUTED)
	var pill = null
	if promoted:
		pill = ui.pill(col, "Promoted to " + str(after.name), ui.INK, ui.YELLOW, "sparkle")
		pill.size_flags_horizontal = 0
	# Where the XP came from.
	var rows = []
	for category in ORDER:
		if not groups.has(category):
			continue
		var info = ui.CATEGORY[category]
		var row = ui.box(col, false, 12)
		ui.icon(row, info.icon, 32, info.color)
		ui.grow(ui.label(row, str(info.name).replace(" XP", ""), "body", ui.WHITE))
		ui.label(row, ui.xp_text(groups[category]), "h3", info.color)
		rows.append(row)
	var details = ui.button(col, "Details", "secondary", self, "open_details", null, "chevron_right")
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play("open")
	if ui.reduced_motion:
		_count.text = ui.xp_text(_total)
		bar.ratio = to_ratio
		return
	var t = Tween.new()
	root.add_child(t)
	_card.rect_pivot_offset = Vector2(WIDTH, 250)
	t.interpolate_property(_card, "modulate:a", 0.0, 1.0, 0.2)
	t.interpolate_property(_card, "margin_left", -WIDTH + 140, -WIDTH - 56, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(_card, "margin_right", 140, -56, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	for i in rows.size():
		ui.pop_in(t, rows[i], 0.35 + 0.08 * i, 0.28, 0.9)
	t.interpolate_method(self, "_counted", 0, _total, 1.1, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.3)
	t.interpolate_property(bar, "ratio", from_ratio, to_ratio, 0.9, Tween.TRANS_CUBIC, Tween.EASE_OUT, 0.5)
	if promoted:
		badge.rect_scale = Vector2(0.6, 0.6)
		t.interpolate_property(badge, "rect_scale", Vector2(0.6, 0.6), Vector2.ONE, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT, 1.35)
		t.interpolate_callback(self, 1.4, "_promoted", badge)
		ui.pop_in(t, pill, 1.45, 0.35, 0.5)
	t.start()

func _fit():
	var root = get_node_or_null("Root")
	if root != null:
		root.rect_position = Vector2.ZERO
		root.rect_size = get_viewport().get_visible_rect().size / SCALE

func _counted(value):
	if is_instance_valid(_count):
		_count.text = ui.xp_text(int(value))
		if int(value) < _total and int(value) % 7 == 0:
			_play("tick", 1.0 + float(value) / max(1, _total) * 0.3)

func _promoted(badge):
	_play("rankup")
	if is_instance_valid(badge):
		ui.burst(badge)

func _play(key, pitch = 1.0):
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
		if is_instance_valid(hud_node):
			screen.set_meta("close_after_results", true)
		screen.show_match_results(receipt, xp_before)
	dismiss()

func dismiss():
	queue_free()
