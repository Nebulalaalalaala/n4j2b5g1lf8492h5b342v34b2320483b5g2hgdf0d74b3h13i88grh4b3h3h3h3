extends "user://mod/tools/journey/ui/JourneyScreen/05_test_rank.gd"

func set_pref(key, value):
	if not PREFS.has(key):
		return
	prefs[key] = value
	_apply_sound_prefs()
	var settings = _settings()
	if settings != null:
		settings.set_value("journey_pref_" + key, value)
	ui.reduced_motion = bool(prefs.reduced_motion)

# The game's SavedSettings autoload; looked up through the SceneTree because
# build() runs before this page is added to the tree.
func _settings():
	var tree = Engine.get_main_loop()
	if tree == null or not tree is SceneTree:
		return null
	return tree.root.get_node_or_null("SavedSettings")

func debug_mode() -> bool:
	if profile_service == null or profile_service.get("tool") == null:
		return false
	var tool = profile_service.tool
	return is_instance_valid(tool) and bool(tool.get("_debug_mode_enabled"))

func _toggle_design_preview_switch(_on):
	_toggle_design_preview()

func _toggle_design_preview():
	design_preview = not design_preview and preview_data != null
	close_overlay()
	_render()

# ------------------------------------------------------------------ celebration
# Rank-up celebration. Callers queue it for a safe non-gameplay moment (results
# screen or Journey); it is skippable and honours reduced motion.
func celebrate(rank, unlocks = []):
	close_overlay()
	# Own layer so the celebration covers the whole window, not just the page.
	overlay = CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	var root_fx = Control.new()
	root_fx.mouse_filter = Control.MOUSE_FILTER_STOP
	root_fx.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	overlay.add_child(root_fx)
	var lg = ui.league(rank)
	var league_up = (int(rank.id) < 18 and int(rank.id) % 3 == 0) or str(rank.league) == "King League"
	var shade = ColorRect.new()
	shade.color = Color(0, 0.04, 0.12, 0.86)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root_fx.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_fx.add_child(center)
	var col = ui.box(center, true, 16)
	col.alignment = BoxContainer.ALIGN_CENTER
	var kicker = ui.label(col, "NEW LEAGUE" if league_up and str(rank.league) != "King League" else ("KING LEAGUE" if str(rank.league) == "King League" else "RANK UP"), "title", lg.light, Label.ALIGN_CENTER)
	kicker.add_font_override("font", ui.font("title", 64, 6))
	var stage = Control.new()
	stage.rect_min_size = Vector2(600, 600)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	var glow = ui.image(stage, "fx_glow", 600, Color(lg.light.r, lg.light.g, lg.light.b, 0.9))
	glow.rect_pivot_offset = Vector2(300, 300)
	var rays = ui.image(stage, "fx_rays", 600, Color(lg.light.r, lg.light.g, lg.light.b, 0.55))
	rays.rect_pivot_offset = Vector2(300, 300)
	var ring = ui.ring(stage, lg.light)
	var badge = ui.badge(stage, rank, 440, true)
	badge.rect_position = Vector2(80, 80)
	badge.rect_pivot_offset = Vector2(220, 220)
	var name = ui.label(col, str(rank.name).to_upper(), "title", ui.WHITE, Label.ALIGN_CENTER)
	name.add_font_override("font", ui.font("title", 104, 8))
	# Progress into the new rank, filling from empty.
	var info = ui.box(col, true, 8)
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var span = max(1, int(rank.next_xp) - int(rank.xp))
	var ratio = clamp(float(int(model.xp) - int(rank.xp)) / span, 0.0, 1.0)
	var bar = ui.bar(info, 0.0, lg.base, 30, Color(1, 1, 1, 0.1))
	bar.rect_min_size.x = 560
	var next = definitions.rank_at(int(rank.next_xp))
	ui.label(info, "Next: %s · %s XP to go" % [str(next.name), ui.thousands(max(0, int(rank.next_xp) - int(model.xp)))], "small", ui.MUTED, Label.ALIGN_CENTER)
	for unlock in unlocks:
		if unlock is Dictionary:
			unlock = unlock.get("name", "")
		ui.pill(col, "Unlocked · " + str(unlock), ui.INK, ui.YELLOW, "sparkle").size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var go = ui.button(col, "Continue", "primary", self, "close_overlay")
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.grab_focus()
	play("league" if league_up else "rankup")
	if ui.reduced_motion or str(prefs.celebrations) == "off":
		bar.ratio = ratio
		return
	var t = _tween()
	# Beat 1: dim in, the title drops.
	t.interpolate_property(root_fx, "modulate", Color(1, 1, 1, 0), Color.white, 0.18)
	kicker.rect_pivot_offset = Vector2(kicker.get_minimum_size().x * 0.5, 40)
	t.interpolate_property(kicker, "rect_scale", Vector2(1.8, 1.8), Vector2.ONE, 0.32, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(kicker, "modulate:a", 0.0, 1.0, 0.2)
	# Beat 2: the badge slams in with a flash ring, glow and confetti.
	badge.rect_scale = Vector2(0.2, 0.2)
	badge.modulate.a = 0.0
	t.interpolate_property(badge, "modulate:a", 0.0, 1.0, 0.12, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.25)
	t.interpolate_property(badge, "rect_scale", Vector2(0.2, 0.2), Vector2(1.12, 1.12), 0.3, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.25)
	t.interpolate_property(badge, "rect_scale", Vector2(1.12, 1.12), Vector2.ONE, 0.35, Tween.TRANS_ELASTIC, Tween.EASE_OUT, 0.55)
	t.interpolate_property(ring, "progress", 0.0, 1.0, 0.7, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.5)
	t.interpolate_property(glow, "rect_scale", Vector2(0.3, 0.3), Vector2(1.15, 1.15), 0.5, Tween.TRANS_BACK, Tween.EASE_OUT, 0.5)
	t.interpolate_property(glow, "modulate:a", 0.0, 1.0, 0.3, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.5)
	t.interpolate_property(rays, "modulate:a", 0.0, 1.0, 0.6, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.5)
	for i in 4:
		var shake = Vector2(14 - i * 3, 0) * (1 if i % 2 == 0 else -1)
		t.interpolate_property(stage, "rect_position", stage.rect_position + shake, stage.rect_position, 0.06, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.55 + i * 0.06)
	t.interpolate_callback(self, 0.55, "_celebrate_burst", stage, league_up)
	t.interpolate_callback(self, 0.55, "play", "claim", 1.12)
	# Beat 3: the name pops, the bar fills, Continue arrives.
	name.modulate.a = 0.0
	t.interpolate_property(name, "modulate:a", 0.0, 1.0, 0.2, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.8)
	name.rect_pivot_offset = Vector2(name.get_minimum_size().x * 0.5, 60)
	t.interpolate_property(name, "rect_scale", Vector2(0.6, 0.6), Vector2.ONE, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT, 0.8)
	t.interpolate_property(bar, "ratio", 0.0, ratio, 0.8, Tween.TRANS_QUAD, Tween.EASE_OUT, 1.05)
	info.modulate.a = 0.0
	t.interpolate_property(info, "modulate:a", 0.0, 1.0, 0.25, Tween.TRANS_LINEAR, Tween.EASE_IN, 1.0)
	go.modulate.a = 0.0
	t.interpolate_property(go, "modulate:a", 0.0, 1.0, 0.25, Tween.TRANS_LINEAR, Tween.EASE_IN, 1.4)
	t.start()
	# Rays keep turning and the glow breathes while the screen is up.
	var loop = Tween.new()
	root_fx.add_child(loop)
	loop.repeat = true
	loop.interpolate_property(rays, "rect_rotation", 0.0, 360.0, 14.0)
	loop.interpolate_property(glow, "modulate:a", 1.0, 0.65, 1.2, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	loop.interpolate_property(glow, "modulate:a", 0.65, 1.0, 1.2, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 1.2)
	loop.start()

func _celebrate_burst(stage, big):
	if not is_instance_valid(stage):
		return
	ui.burst(stage)
	if big:
		var t = Tween.new()
		stage.add_child(t)
		t.interpolate_callback(ui, 0.35, "burst", stage)
		t.start()

func show_match_results(awards, xp_before = -1, title = "", animate = true):
	last_results = [awards, xp_before, title]
	model = models.build(ledger, definitions, profile_service) if not design_preview else model
	var total = 0
	var groups = {}
	var seen = {}
	for entry in awards:
		if seen.has(entry.get("id", "")) and str(entry.get("id", "")) != "":
			continue
		seen[entry.get("id", "")] = true
		total += int(entry.amount)
		if not groups.has(entry.category):
			groups[entry.category] = []
		groups[entry.category].append(entry)
	if xp_before < 0:
		xp_before = max(0, int(model.xp) - total)
	var xp_after = xp_before + total
	var before = definitions.rank_at(xp_before)
	var after = definitions.rank_at(xp_after)
	var promotions = []
	var step = before
	while int(step.next_xp) <= xp_after and promotions.size() < 60:
		step = definitions.rank_at(int(step.next_xp))
		promotions.append(step)
	close_overlay()
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade = ColorRect.new()
	shade.color = Color(0, 0.04, 0.12, 0.8)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	overlay.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card = ui.card(center, ui.NAVY, 40, 48)
	var avail = rect_size.x if rect_size.x > 0 else get_viewport_rect().size.x
	card.rect_min_size.x = min(1900, avail - 96)
	var col = ui.box(card, true, 26)
	var head = ui.box(col, false, 20)
	var titles = ui.grow(ui.box(head, true, 0))
	ui.label(titles, "MATCH COMPLETE", "caps", ui.SKY_LIGHT)
	ui.label(titles, title if title != "" else "Journey XP earned", "h1")
	var count = ui.label(head, "+0 XP", "num_xl", ui.YELLOW, Label.ALIGN_RIGHT)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var body = ui.box(col, not wide(), 30)
	# Rank progress
	var lg = ui.league(after)
	var rank_card = ui.well(body, ui.NAVY.linear_interpolate(lg.deep, 0.35), 30, 36)
	ui.grow(rank_card, true, false, 0.9)
	var rc = ui.box(rank_card, true, 14)
	rc.alignment = BoxContainer.ALIGN_CENTER
	var stage = Control.new()
	stage.rect_min_size = Vector2(320, 320)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc.add_child(stage)
	var badge = ui.badge(stage, after, 320, true)
	badge.rect_pivot_offset = Vector2(160, 160)
	ui.label(rc, str(after.name).to_upper(), "h1", ui.WHITE, Label.ALIGN_CENTER)
	var span = max(1, int(after.next_xp) - int(after.xp))
	var from_ratio = 0.0 if promotions.size() > 0 else float(xp_before - int(after.xp)) / span
	var to_ratio = float(xp_after - int(after.xp)) / span
	var bar = ui.bar(rc, from_ratio, lg.base, 30)
	var nums = ui.box(rc, false, 10)
	ui.label(nums, "%s / %s XP" % [ui.thousands(xp_after - int(after.xp)), ui.thousands(span)], "small", ui.MUTED)
	ui.spacer(nums)
	var next = definitions.rank_at(int(after.next_xp))
	ui.label(nums, "%s to %s" % [ui.xp_text(int(after.next_xp) - xp_after).replace("+", ""), next.name], "small", lg.light, Label.ALIGN_RIGHT)
	var pill = null
	if promotions.size() > 0:
		pill = ui.pill(rc, ("Promoted to " + str(after.name)) if promotions.size() == 1 else ("%d promotions · now %s" % [promotions.size(), after.name]), ui.INK, ui.YELLOW, "sparkle")
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Category breakdown
	var list_card = ui.well(body, ui.NAVY_DEEP, 26, 30)
	ui.grow(list_card, true, false, 1.3)
	var list = ui.box(list_card, true, 12)
	results = {"groups": groups, "list": list, "open": {}, "count": count, "total": total, "promotions": promotions, "entering": true}
	_results_list()
	var foot = ui.box(col, false, 16)
	ui.button(foot, "XP history", "secondary", self, "_results_history", null, "xp")
	ui.spacer(foot)
	var go = ui.button(foot, "Continue", "primary", self, "_results_continue")
	go.grab_focus()
	play("open")
	if ui.reduced_motion or not animate:
		count.text = ui.xp_text(total)
		bar.ratio = to_ratio
		return
	# Sequence: card rises in, rank panel, then categories one by one while the
	# total counts up and the bar fills; a promotion ends with a badge pop,
	# confetti and the rank-up sound.
	var t = Tween.new()
	overlay.add_child(t)
	t.interpolate_property(shade, "modulate:a", 0.0, 1.0, 0.25)
	ui.pop_in(t, card, 0.0, 0.4, 0.9)
	ui.pop_in(t, rank_card, 0.15, 0.35)
	var rows = list.get_children()
	for i in rows.size():
		ui.pop_in(t, rows[i], 0.3 + 0.09 * i, 0.3, 0.92)
	var fill_at = 0.35 + 0.09 * rows.size()
	t.interpolate_method(self, "_results_count", 0, total, 1.2, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.3)
	t.interpolate_property(bar, "ratio", from_ratio, to_ratio, 1.0, Tween.TRANS_CUBIC, Tween.EASE_OUT, fill_at)
	count.rect_pivot_offset = count.rect_size * 0.5
	t.interpolate_property(count, "rect_scale", Vector2(1.18, 1.18), Vector2.ONE, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT, 1.5)
	if promotions.size() > 0:
		badge.rect_scale = Vector2(0.55, 0.55)
		t.interpolate_property(badge, "rect_scale", Vector2(0.55, 0.55), Vector2.ONE, 0.5, Tween.TRANS_BACK, Tween.EASE_OUT, fill_at + 0.9)
		t.interpolate_callback(self, fill_at + 0.95, "_results_promoted", stage)
		ui.pop_in(t, pill, fill_at + 1.0, 0.4, 0.5)
	t.start()

func _results_promoted(stage):
	play("rankup")
	if is_instance_valid(stage):
		ui.burst(stage)

func _results_count(value):
	if results.has("count") and is_instance_valid(results.count):
		results.count.text = ui.xp_text(int(value))
		if int(value) < int(results.total):
			play("tick", 1.0 + 0.4 * float(value) / max(1, int(results.total)))

func _results_list():
	var list = results.list
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var shown = false
	for category in RESULT_ORDER:
		if not results.groups.has(category):
			continue
		shown = true
		var info = ui.CATEGORY[category]
		var entries = results.groups[category]
		var subtotal = 0
		for entry in entries:
			subtotal += int(entry.amount)
		var open = bool(results.open.get(category, false))
		var p = ui.well(list, ui.NAVY_2, 18, 26)
		ui.clickable(p, self, "_results_toggle", category)
		var c = ui.box(p, true, 10)
		var row = ui.box(c, false, 16)
		ui.tile_icon(row, info.icon, info.color, 62)
		var name = ui.grow(ui.box(row, true, 0))
		name.alignment = BoxContainer.ALIGN_CENTER
		ui.label(name, str(info.name).replace(" XP", "").to_upper(), "h3")
		ui.label(name, "%d reward%s" % [entries.size(), "" if entries.size() == 1 else "s"], "small", ui.MUTED)
		ui.label(row, ui.xp_text(subtotal), "num_m", info.color)
		ui.icon(row, "chevron_down" if open else "chevron_right", 30, ui.MUTED)
		if open:
			var t = null
			if category == results.get("just_opened", "") and not ui.reduced_motion:
				t = Tween.new()
				c.add_child(t)
			var i = 0
			for entry in entries:
				var line = ui.box(c, false, 12)
				ui.spacer(line, 78, 0)
				ui.grow(ui.label(line, str(entry.reason), "small", ui.WHITE))
				ui.label(line, "+" + ui.thousands(entry.amount), "button", ui.MUTED)
				ui.pop_in(t, line, 0.04 * i, 0.22, 0.97)
				i += 1
			if t != null:
				t.start()
	results.just_opened = ""
	if not shown:
		empty_state(list, "xp", "No Journey XP this match", "")

func _results_toggle(category):
	results.open[category] = not bool(results.open.get(category, false))
	results.just_opened = category if results.open[category] else ""
	play("click")
	_results_list()

func _results_history():
	close_overlay()
	_history_from_results = true
	open("history")

func _results_continue():
	var promotions = results.get("promotions", [])
	close_overlay()
	# Opened from the in-match result card: Continue goes straight back to the game.
	if closable and has_meta("close_after_results"):
		remove_meta("close_after_results")
		emit_signal("close_requested")
		return
	refresh()
	if promotions.empty() or str(prefs.celebrations) == "off":
		return
	var top = promotions.back()
	if str(prefs.celebrations) == "leagues":
		var league_up = false
		for rank in promotions:
			if (int(rank.id) < 18 and int(rank.id) % 3 == 0) or str(rank.league) == "King League":
				league_up = true
		if not league_up:
			return
	celebrate(top)
