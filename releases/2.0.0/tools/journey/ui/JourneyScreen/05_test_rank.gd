extends "user://mod/tools/journey/ui/JourneyScreen/04_claim_rewards.gd"

func _award_quest(quest) -> bool:
	var id = str(quest.get("id", ""))
	var xp = int(quest.get("xp", 0))
	if model.preview or not journey_store.writable or id.empty():
		return true
	if journey_store.quest_claimed(id):
		return false
	if bool(quest.get("test", false)):
		journey_store.test.xp = int(journey_store.test.get("xp", 0)) + xp
	elif xp > 0:
		var ok = ledger.award({"id": "challenge:%s:%s" % [ledger.account_id, id], "player_id": str(ledger.account_id),
			"category": "challenge", "reason": ("Weekly challenge: " if bool(quest.get("weekly", false)) else "Daily challenge: ") + str(quest.get("title", "Challenge")),
			"related_id": id, "source": "verified_local_activity", "amount": xp, "timestamp": OS.get_unix_time()})
		if not ok:
			_toast(str(ledger.error) if str(ledger.error) != "" else "Couldn't save the reward.")
			return false
	journey_store.mark_quest(id)
	if not get_signal_connection_list("journey_action").empty():
		emit_signal("journey_action", "quest_claimed", {"quest": id, "xp": xp})
	return true

func _after_claim(xp_before = -1, rank_before = null):
	xp_anim_from = xp_before
	if rank_before != null:
		set_meta("rank_before", int(rank_before.id))
	if ui.reduced_motion:
		refresh()
		_check_rank_up()
		return
	# Own tween: the shared one would cut short any page animation still running.
	var t = Tween.new()
	add_child(t)
	t.interpolate_callback(self, 0.75, "refresh")
	t.interpolate_callback(self, 1.9, "_check_rank_up")
	t.interpolate_callback(t, 2.0, "queue_free")
	t.start()

# After a claim, fill a rank bar from the old XP to the new XP.
func _xp_bar(bar, rank):
	if xp_anim_from < 0 or ui.reduced_motion:
		return bar
	var span = max(1, int(rank.next_xp) - int(rank.xp))
	var target = bar.ratio
	bar.ratio = clamp(float(xp_anim_from - int(rank.xp)) / span, 0.0, 1.0)
	var t = _tween()
	t.interpolate_property(bar, "ratio", bar.ratio, target, 0.9, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.15)
	t.start()
	return bar

func live(control, until, fmt):
	var label = control if control is Label else _first_label(control)
	if label == null:
		return control
	label.set_meta("until", int(until))
	label.set_meta("fmt", fmt)
	_live.append(label)
	_live_update(label)
	return control

func _first_label(node):
	for child in node.get_children():
		if child is Label:
			return child
		var found = _first_label(child)
		if found != null:
			return found
	return null

func _live_update(label):
	var left = max(0, int(label.get_meta("until")) - OS.get_unix_time())
	var text = str(label.get_meta("fmt")) % ui.duration(left)
	label.text = text.to_upper() if str(label.get_meta("fmt")).to_upper() == str(label.get_meta("fmt")) else text

func _process(delta):
	if _live.empty() or not is_visible_in_tree():
		return
	_live_timer += delta
	if _live_timer < 1.0:
		return
	_live_timer = 0.0
	var alive = []
	for label in _live:
		if is_instance_valid(label):
			_live_update(label)
			alive.append(label)
	_live = alive

func _check_rank_up():
	if has_meta("rank_before") and model.get("rank") != null and int(model.rank.id) > int(get_meta("rank_before")):
		var unlocks = []
		for i in model.roadmap.size():
			if int(model.roadmap[i].id) > int(get_meta("rank_before")) and int(model.roadmap[i].id) <= int(model.rank.id):
				unlocks += theme_rules.unlocks_at(int(model.roadmap[i].id))
		celebrate(model.rank, unlocks)
	if has_meta("rank_before"):
		remove_meta("rank_before")

func _claim_fx(source, xp):
	if ui.reduced_motion:
		return
	var layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(layer)
	var area = Rect2(rect_size * Vector2(0.5, 0.45) - Vector2(300, 60), Vector2(600, 120))
	if source != null and is_instance_valid(source):
		area = Rect2(source.get_global_rect().position - get_global_rect().position, source.rect_size)
	# The layer is laid out inside this MarginContainer's margins.
	area.position -= Vector2(get_constant("margin_left"), get_constant("margin_top"))
	var t = Tween.new()
	layer.add_child(t)
	# Soft flash over the row, then a burst and the XP rising out of it.
	var flash = Panel.new()
	flash.add_stylebox_override("panel", ui.flat(Color(1, 0.95, 0.6, 1), 30, 0, 0, ui.INK, false))
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.rect_position = area.position
	flash.rect_size = area.size
	layer.add_child(flash)
	t.interpolate_property(flash, "modulate:a", 0.55, 0.0, 0.45, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var spot = Control.new()
	spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spot.rect_position = area.position
	spot.rect_size = area.size
	layer.add_child(spot)
	ui.burst(spot)
	var tag = ui.box(null, false, 12)
	ui.icon(tag, "xp", 64, ui.YELLOW)
	var amount = ui.label(tag, "+" + ui.thousands(xp) + " XP", "num_l", ui.YELLOW)
	amount.add_font_override("font", ui.font("display", 64, 8))
	layer.add_child(tag)
	tag.rect_size = tag.get_combined_minimum_size()
	tag.rect_pivot_offset = tag.rect_size * 0.5
	var start = area.position + area.size * 0.5 - tag.rect_size * 0.5
	tag.rect_position = start
	t.interpolate_property(tag, "rect_scale", Vector2(0.5, 0.5), Vector2(1.15, 1.15), 0.28, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(tag, "rect_scale", Vector2(1.15, 1.15), Vector2.ONE, 0.2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.28)
	t.interpolate_property(tag, "rect_position", start, start - Vector2(0, 170), 1.2, Tween.TRANS_QUAD, Tween.EASE_OUT)
	t.interpolate_property(tag, "modulate:a", 1.0, 0.0, 0.45, Tween.TRANS_QUAD, Tween.EASE_IN, 0.85)
	if source != null and is_instance_valid(source):
		source.rect_pivot_offset = source.rect_size * 0.5
		t.interpolate_property(source, "rect_scale", Vector2(1.03, 1.03), Vector2.ONE, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_callback(layer, 1.7, "queue_free")
	t.start()

func _toast(text):
	var p = ui.card(null, ui.INK, 20, 30)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1
	p.anchor_bottom = 1
	p.margin_top = -150
	p.margin_bottom = -60
	p.margin_left = -560
	p.margin_right = 560
	ui.label(p, text, "body", ui.WHITE, Label.ALIGN_CENTER)
	var layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	layer.add_child(p)
	var t = Tween.new()
	layer.add_child(t)
	t.interpolate_callback(layer, 2.6, "queue_free")
	t.start()

func notify(kind, title, detail = "", xp = 0, target = "inbox"):
	if str(prefs.notify) == "inbox" and kind != "session":
		return
	var style = NOTIFY_STYLE.get(kind, ["bell", ui.SKY_LIGHT])
	var layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(layer)
	var p = ui.card(null, ui.NAVY, 22, 34)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.anchor_left = 1
	p.anchor_right = 1
	var width = min(980, (rect_size.x if rect_size.x > 0 else 1080) - 24)
	p.margin_left = -width
	p.margin_right = 0
	p.margin_top = 150
	layer.add_child(p)
	var row = ui.box(p, false, 20)
	var tile = ui.tile_icon(row, style[0], style[1], 80)
	var col = ui.grow(ui.box(row, true, 2))
	col.alignment = BoxContainer.ALIGN_CENTER
	ui.label(col, title, "h3")
	if detail != "":
		ui.label(col, detail, "small", ui.MUTED)
	var timer = ui.bar(col, 1.0, style[1], 6, Color(1, 1, 1, 0.08))
	if int(xp) > 0:
		var pill = ui.pill(row, ui.xp_text(xp), ui.INK, ui.YELLOW, "xp")
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.clickable(p, self, "_notify_open", [layer, target])
	play("claim" if int(xp) > 0 else "open")
	var t = Tween.new()
	layer.add_child(t)
	t.interpolate_property(timer, "ratio", 1.0, 0.0, 4.5, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.3)
	if not ui.reduced_motion:
		t.interpolate_property(p, "margin_left", -width + 420, -width, 0.35, Tween.TRANS_BACK, Tween.EASE_OUT)
		t.interpolate_property(p, "margin_right", 420, 0, 0.35, Tween.TRANS_BACK, Tween.EASE_OUT)
		t.interpolate_property(p, "modulate:a", 0.0, 1.0, 0.2)
		ui.pop_in(t, tile, 0.18, 0.4, 0.4)
		t.interpolate_property(p, "margin_left", -width, -width + 420, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN, 4.8)
		t.interpolate_property(p, "margin_right", 0, 420, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN, 4.8)
		t.interpolate_property(p, "modulate:a", 1.0, 0.0, 0.3, Tween.TRANS_LINEAR, Tween.EASE_IN, 4.8)
	t.interpolate_callback(layer, 5.15, "queue_free")
	t.start()

func _notify_open(args):
	if is_instance_valid(args[0]):
		args[0].queue_free()
	if args[1] is Dictionary:
		open_item(args[1])
		return
	var target = str(args[1])
	if target == "inbox":
		_open_inbox()
	elif target in SECTIONS:
		_select_section(target)
	else:
		open(target)

# ------------------------------------------------------------------ overlays
func _open_inbox():
	pages.inbox(_overlay("Inbox", "inbox"))

func _open_prefs():
	pages.preferences(_overlay("Journey preferences", "gear"))

func open_xp_calculator(_arg = null):
	pages.xp_calculator(_overlay("Calculate XP", "xp"))

# First time Journey is opened: a short spotlight over the menu (core/Onboarding.gd marker).
# The account's own GooberDash stats for Win Streak, at most every 10 minutes.
func refresh_native_stats():
	if model.preview or not journey_store.writable or OS.get_unix_time() - int(journey_store.native.get("time", 0)) < 600:
		return
	var backfill = load(ModPaths.path("JourneyXPBackfill.gd")).new()
	var state = backfill.fetch(get_node_or_null("/root/Moonlight"), str(ledger.account_id))
	var stats = state
	if state is GDScriptFunctionState:
		stats = yield(state, "completed")
	if stats.empty() or not is_instance_valid(self) or not journey_store.writable:
		return
	journey_store.native = {"Winstreak": int(stats.get("Winstreak", 0)), "CurrentWinstreak": int(stats.get("CurrentWinstreak", 0)), "time": OS.get_unix_time()}
	load(ModPaths.path("JourneyMatchXP.gd")).set_streak(str(ledger.account_id), int(stats.get("CurrentWinstreak", 0)))
	journey_store.save()
	refresh()

func start_intro():
	var onboarding = ModPaths.try_load(ModPaths.path("Onboarding.gd"))
	if onboarding == null or onboarding.seen("journey") or model.preview or intro_spot != null:
		return
	intro_spot = load(ModPaths.path("Spotlight.gd")).new()
	add_child(intro_spot)
	intro_spot.connect("pressed", self, "_intro_pressed")
	intro_spot.connect("lost", self, "_intro_show", [], CONNECT_DEFERRED)
	intro_step = 0
	_intro_show()

func _intro_show():
	if intro_spot == null:
		return
	if intro_step == 0:
		intro_spot.show_step(nav_row, "Ranks, quests, maps and rewards", [["Skip", "skip"], ["Next", "next", true]])
	elif intro_step == 1:
		intro_spot.show_step(nav_row.find_node("Quests", true, false), "Daily quests and weekly challenges", [["Skip", "skip"], ["Next", "next", true]])
	else:
		var gear = null
		for holder in header_row.get_children():
			if holder.has_meta("count_key") and holder.get_meta("count_key") == "gear":
				gear = holder
		if journey_store.writable and not journey_store.flag("notice:xp_calculated"):
			intro_spot.show_step(gear, "Add XP for the games you played before Goobplayability", [["Later", "done"], ["Calculate XP", "calculate", true]])
		else:
			intro_spot.show_step(gear, "Preferences and Calculate XP", [["Got it", "done", true]])

func _intro_pressed(id):
	play("click")
	if id == "next":
		intro_step += 1
		_intro_show()
		return
	load(ModPaths.path("Onboarding.gd")).mark("journey")
	intro_spot.queue_free()
	intro_spot = null
	if id == "calculate":
		open_xp_calculator()

func is_admin() -> bool:
	return str(ledger.account_id) == ADMIN_ID or harness_admin

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_M and event.control and is_visible_in_tree() and is_admin():
		get_tree().set_input_as_handled()
		if overlay != null and is_instance_valid(overlay):
			close_overlay()
		_open_tools()

func _open_tools():
	if not is_admin():
		return
	pages.test_tools(_overlay("Test tools", "target"))

# ------------------------------------------------------------------ test tools
# Everything here is display-only and kept in journey_store.test; the XP ledger
# is never touched. "Reset to normal" removes all of it.
func _apply_test_xp(m):
	journey_store.configure(str(ledger.account_id))
	if m.preview or not journey_store.writable or int(journey_store.test.get("xp", 0)) == 0:
		return
	m.real_xp = int(m.xp)
	m.xp = int(m.xp) + int(journey_store.test.xp)
	m.rank = definitions.rank_at(m.xp)
	m.next = definitions.rank_at(int(m.rank.next_xp))
	m.roadmap = definitions.roadmap(m.xp)
	m.next_league = models._next_league(definitions, m.rank)

func _test_ready() -> bool:
	if not is_admin():
		return false
	if model.preview or not journey_store.writable:
		_toast("Sign in first (test tools are off in the design preview).")
		return false
	return true

func test_xp(amount):
	if not _test_ready():
		return
	var before = model.rank
	journey_store.test.xp = int(journey_store.test.get("xp", 0)) + int(amount)
	journey_store.save()
	play("claim")
	refresh()
	if int(model.rank.id) != int(before.id) and int(amount) > 0:
		celebrate(model.rank)

# Sets the shown Journey XP to exactly `total` (test XP = total - real XP).
func test_set_total(total):
	if not _test_ready():
		return
	var before = model.rank
	journey_store.test.xp = int(clamp(int(total), 0, 900000000)) - int(ledger.total_xp)
	journey_store.save()
	play("claim")
	close_overlay()
	refresh()
	if int(model.rank.id) > int(before.id):
		celebrate(model.rank)

func test_set_rank(rank_id):
	test_set_total(_rank_xp(int(rank_id)))

func _rank_xp(rank_id) -> int:
	for rank in definitions.finite_ranks():
		if int(rank.id) == rank_id:
			return int(rank.xp)
	return int(definitions.king_rank(rank_id - 17).xp)

func test_next_rank(_arg = null):
	if _test_ready():
		test_xp(max(1, int(model.rank.next_xp) - int(model.xp)))

func test_reset_xp(_arg = null):
	if not _test_ready():
		return
	journey_store.test.erase("xp")
	_test_save()

func test_complete(group):
	if not _test_ready() or model.quests == null:
		return
	if not journey_store.test.get("done") is Dictionary:
		journey_store.test.done = {}
	for q in model.quests[group]:
		journey_store.test.done[q.id] = true
	play("toggle")
	_test_save()

func test_new_quests(_arg = null):
	if not _test_ready():
		return
	journey_store.quests.erase("day")
	journey_store.quests.erase("week")
	_test_save()

func test_clear_inbox(_arg = null):
	if not _test_ready():
		return
	journey_store.inbox = []
	_test_save()

func test_preview(kind):
	match str(kind):
		"rankup":
			celebrate(model.rank, [{"name": "Sample reward", "icon": "palette"}])
		"claim":
			play("claim")
			_claim_fx(null, 500)
		"recap":
			notify("session", "Session recap", "12 rounds · 2 wins · 3 new maps", 1800, "session")
		"results":
			var awards = model.transactions.slice(0, 5) if not model.transactions.empty() else []
			show_match_results(awards, -1, "Test match")

# Removes test XP and test completions, and un-claims quests that were only
# complete because of the test tools.
func test_reset(_arg = null):
	if not journey_store.writable:
		return
	var done = journey_store.test.get("done", {})
	var claimed = journey_store.quests.get("claimed", {})
	for id in done:
		claimed.erase(id)
		for item in journey_store.inbox:
			if item.id == "quest_" + str(id):
				journey_store.inbox.erase(item)
				break
	journey_store.test = {}
	play("toggle")
	_test_save()
	_toast("Back to your real progress.")

func _test_save():
	journey_store.save()
	close_overlay()
	refresh()

func _overlay(title, icon_key):
	close_overlay()
	play("open")
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade = ColorRect.new()
	shade.color = Color(0, 0.05, 0.15, 0.55)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.connect("gui_input", self, "_shade_input")
	overlay.add_child(shade)
	var panel = ui.card(overlay, ui.NAVY, 36, 48)
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_bottom = 1
	panel.margin_left = -min(1100, rect_size.x - 72)
	panel.margin_right = 0
	panel.margin_top = 110
	panel.margin_bottom = 0
	var col = ui.box(panel, true, 22)
	var head = ui.box(col, false, 16)
	ui.icon(head, icon_key, 48, ui.MUTED)
	ui.grow(ui.label(head, title, "h1"))
	ui.button(head, "", "quiet", self, "close_overlay", null, "close").hint_tooltip = "Close"
	var s = ScrollContainer.new()
	s.scroll_horizontal_enabled = false
	ui.grow(s, true, true)
	_style_scrollbar(s)
	col.add_child(s)
	var body = ui.box(s, true, 18)
	ui.grow(body)
	if not ui.reduced_motion:
		var t = _tween()
		# Anchor-relative margins, so the slide is correct before the first layout pass.
		t.interpolate_property(panel, "margin_left", panel.margin_left + 160, panel.margin_left, 0.24, Tween.TRANS_QUAD, Tween.EASE_OUT)
		t.interpolate_property(panel, "margin_right", 160, 0, 0.24, Tween.TRANS_QUAD, Tween.EASE_OUT)
		t.interpolate_property(overlay, "modulate", Color(1, 1, 1, 0), Color.white, 0.2)
		t.start()
	return body

func _shade_input(event):
	if event is InputEventMouseButton and event.pressed:
		close_overlay()

func close_overlay():
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null

func _unhandled_input(event):
	if overlay != null and is_instance_valid(overlay) and event.is_action_pressed("ui_cancel"):
		close_overlay()
		get_tree().set_input_as_handled()
	elif closable and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_tree().set_input_as_handled()
		_request_close()

# ------------------------------------------------------------------ prefs
func _load_prefs():
	prefs = PREFS.duplicate()
	var settings = _settings()
	if settings == null:
		return
	for key in PREFS:
		var value = settings.get_value("journey_pref_" + key, PREFS[key])
		if typeof(value) == typeof(PREFS[key]) or (typeof(PREFS[key]) == TYPE_REAL and typeof(value) == TYPE_INT):
			prefs[key] = value
	_apply_sound_prefs()

func _apply_sound_prefs():
	if sound != null:
		sound.enabled = bool(prefs.sounds)
		sound.volume = float(prefs.volume)

func play(key, pitch = 1.0):
	if sound != null:
		sound.play(key, pitch)
