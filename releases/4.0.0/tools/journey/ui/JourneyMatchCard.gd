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
var fx = null
var _stage = null
var _streak_pill = null
var _proceed = null
var context = {}
var _orb_pitch = 1.0
var _scroll = null
var _rolls = {}   # crate/drop rows: {"name", "amount", "label"}

# context (test tools only): {"streak", "losses", "preview"} instead of saved state.
func setup(owner, awards, before, hud_node, preview_context = {}):
	controller = owner
	context = preview_context
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
	_stage = stage
	stage.rect_min_size = Vector2(96, 96)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank_row.add_child(stage)
	var rcol = ui.grow(ui.box(rank_row, true, 6))
	rcol.alignment = BoxContainer.ALIGN_CENTER
	var rank_name = ui.label(rcol, str(before.name).to_upper(), "h2")
	var bar = ui.bar(rcol, 0.0, lg.base, 30)
	var caption = ui.label(rcol, "", "small", ui.MUTED)
	var unlock = _next_unlock(after)
	if not unlock.empty():
		ui.label(rcol, "Next unlock at %s · %s XP to go" % [unlock.name, ui.thousands(max(0, int(unlock.xp) - after_xp))], "small", ui.SKY_LIGHT)
	_streak_row(col)
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
	_scroll = scroll
	var scrollbar = scroll.get_v_scrollbar()
	scrollbar.rect_min_size.x = 10
	scrollbar.add_stylebox_override("scroll", ui.flat(Color(0, 0, 0, 0), 5, 0, 0, ui.INK, false))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		scrollbar.add_stylebox_override(state, ui.flat(ui.NAVY_3 if state == "grabber" else ui.SKY_LIGHT, 5, 0, 0, ui.INK, false))
	_rows_col = ui.box(scroll, true, 10)
	_rows_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for info in Data.reward_rows(receipt):
		var row = ui.box(_rows_col, false, 16)
		var color = ui.YELLOW if info.key in ["bonus", "sweep", "streak", "firstwin"] else ui.WHITE
		if info.key in ["crate", "drop"]:
			color = Color(Data.CRATE_COLORS.get(str(info.tier), "ffffff"))
		ui.icon(row, info.icon, 34, color)
		var name_label = ui.grow(ui.label(row, str(info.name), "body", color))
		var amount_label = ui.label(row, ui.xp_text(info.amount), "h3", color)
		if info.key in ["crate", "drop"] and not ui.reduced_motion:
			# The tier stays hidden until its number rolls in.
			_rolls[info.key] = {"name": name_label, "amount": amount_label, "text": str(info.name)}
			name_label.text = Data.ROWS[info.key][0]
			amount_label.text = "+??? XP"
			for l in [name_label, amount_label]:
				l.add_color_override("font_color", Color(Data.CRATE_COLORS.Common))
		rows.append(row)
		_reward_rows[info.key] = row
	var details = ui.button(col, "Details", "quiet", self, "open_details", null, "chevron_right")
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var proceed = ui.button(col, "Continue", "primary", self, "dismiss")
	proceed.name = "Continue"
	_proceed = proceed
	proceed.rect_min_size.y = 80
	proceed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Data.shine(proceed)
	if not ui.reduced_motion:
		fx = load(ModPaths.JOURNEY_DIR + "ui/JourneyMatchFX.gd").new()
		fx.name = "FX"
		root.add_child(fx)
		fx.setup(ui, _card)
		fx.track_bar(bar, lg.light)
		if is_instance_valid(_streak_pill):
			fx.embers_on(_streak_pill, Color("ff8a1c"), 10.0 + min(30.0, 4.0 * float(_streak_pill.get_meta("streak"))))
	sequence = load(ModPaths.JOURNEY_DIR + "ui/JourneyRewardSequence.gd").new()
	sequence.hold_crates = fx != null
	add_child(sequence)
	sequence.configure(ui, definitions, receipt, xp_before, {"count": _count, "bar": bar, "stage": stage, "badge_size": 96,
		"name": rank_name, "caption": caption, "status": status, "celebrations": celebrations})
	sequence.connect("cue", self, "_cue")
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
	if fx != null and is_instance_valid(_streak_pill) and int(_streak_pill.get_meta("streak")) >= 2:
		t.interpolate_callback(self, 0.3, "_streak_slam")

func _sequence_done(pill):
	if is_instance_valid(pill): pill.modulate.a = 1.0
	if fx == null: return
	fx.punch(_count, 1.4, Color(1.7, 1.5, 0.9))
	fx.ring(fx._local(_count), Color("ffd35a"), 260.0)
	fx.spark_burst(fx._local(_count), Color("ffd35a"), 40, 820.0, 10.0)
	fx.shake(10.0)
	var b = ui.burst(_card)
	if b != null:
		b.rect_position = Vector2(-120, -160)
		b.rect_size = _card.rect_size + Vector2(240, 120)
	_play("sweep" if _total >= 5000 else "claim", 1.0)
	_breathe(_proceed)

func _cue(key, pitch = 1.0):
	_play(key, pitch)
	if key == "rankup" and fx != null and is_instance_valid(_stage):
		fx.shake(12.0)
		fx.spark_burst(fx._local(_stage), Color("fff1a3"), 40, 760.0, 11.0)
		fx.ring(fx._local(_stage), Color("ffc629"), 180.0)

# Continue gently pulses once everything has landed.
func _breathe(button):
	if not is_instance_valid(button): return
	button.rect_pivot_offset = button.rect_size * 0.5
	var t = Tween.new()
	button.add_child(t)
	t.repeat = true
	t.interpolate_property(button, "rect_scale", Vector2.ONE, Vector2(1.04, 1.04), 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	t.interpolate_property(button, "rect_scale", Vector2(1.04, 1.04), Vector2.ONE, 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.6)
	t.start()

func _landed():
	if fx != null: fx.punch(_count)

func _reward_beat(info):
	if controller.has_method("reward_beat") and not context.get("preview", false): controller.reward_beat(info, receipt)
	if ui.reduced_motion: return
	var row = _reward_rows.get(info.key)
	if not is_instance_valid(row): return
	if is_instance_valid(_scroll): _scroll.ensure_control_visible(row)
	var color = ui.YELLOW
	_orb_pitch = 1.0
	if info.key in ["crate", "drop"]:
		color = Color(Data.CRATE_COLORS.get(str(info.tier), "ffffff"))
		if fx != null and _rolls.has(info.key):
			_roll(info)
		elif is_instance_valid(sequence):
			sequence.resume()
	elif info.key in ["bonus", "rested"] and fx != null:
		# Multipliers slam onto the counter instead of flying in like a row.
		var c = Color("5ad1ff") if info.key == "bonus" else Color("ff8fc7")
		fx.stamp(fx._local(_count) + Vector2(_count.rect_size.x * 0.25, -10), "DAILY 2x" if info.key == "bonus" else "RESTED 2x", c, 96, 0.8)
		fx.orbs(row, _count, c, 14, self, "_orb_hit")
		fx.popup(row, ui.xp_text(info.amount), c)
		get_tree().create_timer(0.22).connect("timeout", fx, "flash", [c, 0.2])
	elif fx != null:
		fx.popup(row, ui.xp_text(info.amount), color if info.key in ["win", "sweep", "streak", "firstwin"] else Color.white)
		fx.orbs(row, _count, color, int(clamp(info.amount / 120, 4, 14)), self, "_orb_hit")
	var t = Tween.new()
	row.add_child(t)
	t.interpolate_property(row, "modulate", Color(1.6, 1.5, 1.2), Color.white, 0.35)
	t.start()

func _orb_hit(color):
	if fx == null: return
	fx.bump(_count)
	_play("tick", _orb_pitch)
	_orb_pitch = min(2.0, _orb_pitch + 0.06)

# Bonus XP rolls like a counter, its colour climbing Common -> Rare -> Epic ->
# Legendary up to the tier that was won, then lands with one burst.
const ROLL_TIERS = ["Common", "Rare", "Epic", "Legendary"]
func _roll(info):
	var r = _rolls[info.key]
	var tier = max(0, ROLL_TIERS.find(str(info.tier)))
	var table = load(ModPaths.path("JourneyMatchRewards.gd")).DROPS if info.key == "drop" else load(ModPaths.path("JourneyMatchRewards.gd")).CRATES
	r.tier = tier
	r.table = table
	r.shown = -1
	r.amount_value = int(info.amount)
	r.key = info.key
	var t = Tween.new()
	add_child(t)
	t.interpolate_method(self, "_roll_" + str(info.key), 0.0, 1.0, 0.55 + 0.35 * tier, Tween.TRANS_SINE, Tween.EASE_IN)
	t.interpolate_callback(self, 0.6 + 0.35 * tier, "_roll_land", info.key)
	t.start()

func _roll_crate(progress):
	_roll_step("crate", progress)

func _roll_drop(progress):
	_roll_step("drop", progress)

func _roll_step(key, progress):
	var r = _rolls.get(key)
	if r == null or not is_instance_valid(r.amount):
		return
	var step = int(min(r.tier, floor(progress * (r.tier + 1))))
	if step != r.shown:
		r.shown = step
		var c = Color(Data.CRATE_COLORS[ROLL_TIERS[step]])
		for l in [r.name, r.amount]:
			l.add_color_override("font_color", c)
		if step > 0:
			fx.spark_burst(fx._local(r.amount), c, 10 + step * 4, 320.0, 7.0)
			fx.bump(r.amount, 1.15)
			_play("tick", 1.25 + step * 0.2)
	var low = int(r.table[step][1])
	var high = int(r.table[step][2])
	r.amount.text = ui.xp_text(int(round(lerp(low, high, randf()) / 50.0) * 50))
	_play("tick", 1.0 + progress * 0.3)

func _roll_land(key):
	var r = _rolls.get(key)
	if r == null:
		return
	if is_instance_valid(r.amount):
		var c = Color(Data.CRATE_COLORS[ROLL_TIERS[r.tier]])
		r.amount.text = ui.xp_text(r.amount_value)
		r.name.text = r.text
		fx.punch(r.amount, 1.3 + 0.08 * r.tier, Color(1.6, 1.5, 1.2))
		fx.spark_burst(fx._local(r.amount), c, 18 + r.tier * 10, 460.0 + r.tier * 90, 8.0)
		if r.tier >= 2:
			fx.ring(fx._local(r.amount), c, 120.0 + r.tier * 30)
		fx.orbs(_reward_rows[key], _count, c, 8 + r.tier * 3, self, "_orb_hit")
		_play(["claim", "claim", "rankup", "league"][r.tier], 1.0)
	get_tree().create_timer(0.35).connect("timeout", self, "_roll_done")

func _roll_done():
	if is_instance_valid(sequence): sequence.resume()

func _streak_slam():
	if not is_instance_valid(_streak_pill) or fx == null: return
	var n = int(_streak_pill.get_meta("streak"))
	var c = Color("ffb347") if n < 5 else (Color("ff6a3d") if n < 10 else Color("6ad8ff"))
	fx.stamp(Vector2(fx._local(_card).x, fx._local(_streak_pill).y - 20), "%d WIN STREAK!" % n, c, 64 + min(4, n) * 6, 0.6)
	fx.spark_burst(fx._local(_streak_pill), Color("ff8a1c"), 30, 520.0, 9.0)
	_play("first", 1.0)

# Current win streak and what the next win and the next milestone are worth.
func _streak_row(parent):
	var mxp = load(ModPaths.path("JourneyMatchXP.gd"))
	var streak = int(context.streak) if context.has("streak") else mxp.streak_of(_account)
	if streak < 1:
		# After a loss: the next win's crate is luckier, so the next match matters.
		var losses = int(context.losses) if context.has("losses") else mxp.losses_of(_account)
		if losses > 0:
			var lucky = ui.box(parent, false, 12)
			ui.pill(lucky, "LUCKIER NEXT WIN", ui.INK, ui.SKY_LIGHT, "sparkle")
			ui.grow(ui.label(lucky, "+%d%% better win bonus odds" % int(min(20, 4 * min(4, losses))), "small", ui.MUTED))
		return
	var policy = load(ModPaths.path("JourneyMatchRewards.gd"))
	var row = ui.box(parent, false, 12)
	_streak_pill = ui.pill(row, "%d WIN STREAK" % streak, ui.INK, ui.YELLOW, "crown")
	_streak_pill.set_meta("streak", streak)
	_flicker(_streak_pill)
	var milestone = (int(streak / 5) + 1) * 5
	var next_bonus = policy.STREAK_STEP * min(streak, policy.STREAK_STEP_CAP)
	ui.grow(ui.label(row, "Next win +%s · %d wins: +%s" % [ui.thousands(next_bonus), milestone, ui.thousands(policy.STREAK_XP.get(milestone, 40000 + 20000 * (milestone - 25) / 5))], "small", ui.MUTED))

func _flicker(control):
	if ui.reduced_motion: return
	var t = Tween.new()
	control.add_child(t)
	t.repeat = true
	t.interpolate_property(control, "modulate", Color(1, 1, 1), Color(1.25, 1.1, 0.85), 0.35, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	t.interpolate_property(control, "modulate", Color(1.25, 1.1, 0.85), Color(1, 1, 1), 0.45, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.35)
	t.start()

# The next rank that unlocks a menu theme or a finish.
func _next_unlock(rank) -> Dictionary:
	var themes = load(ModPaths.path("JourneyThemes.gd"))
	var ids = []
	for value in themes.UNLOCKS.values():
		ids.append(int(value))
	for value in [18, 19, 20, 21, 22]:
		ids.append(value)
	ids.sort()
	for id in ids:
		if id > int(rank.id):
			var next = definitions.king_rank(id - 17) if id >= 18 else definitions.finite_ranks()[id]
			return {"name": str(next.name), "xp": int(next.xp)}
	return {}

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
