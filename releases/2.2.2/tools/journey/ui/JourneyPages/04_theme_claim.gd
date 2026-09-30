extends "user://mod/tools/journey/ui/JourneyPages/03_map_maps.gd"

func achievements(parent):
	var m = _m()
	var head = screen.section_intro(parent, "Your GooberDash Achievements")
	if m.achievements == null:
		var card = ui.card(parent)
		var col = ui.box(card, true, 24)
		screen.empty_state(col, "achievements", "Achievement tracking isn't connected yet", "")
		var grid = _columns(col, 3, 2, 22)
		for entry in COLLECTIONS:
			var tile = ui.well(grid, ui.NAVY_2, 22, 32)
			ui.grow(tile)
			var row = ui.box(tile, false, 18)
			ui.medal(row, 0, entry[0], 118, true)
			var c = ui.grow(ui.box(row, true, 2))
			c.alignment = BoxContainer.ALIGN_CENTER
			ui.label(c, entry[1], "h3")
			ui.label(c, entry[2], "small", ui.MUTED)
		var tiers = ui.box(col, false, 12)
		ui.label(tiers, "TIERS", "caps", ui.MUTED)
		for i in 6:
			ui.medal(tiers, i, "crown", 96, false)
			ui.label(tiers, ui.TIERS[i], "small", ui.MUTED)
		return
	var a = m.achievements
	var featured = ui.card(parent, ui.NAVY.linear_interpolate(Color("3a1575"), 0.25))
	var fwrap = ui.box(featured, not screen.wide(), 20)
	var fcol = ui.box(fwrap, true, 6)
	fcol.alignment = BoxContainer.ALIGN_CENTER
	ui.label(fcol, "FEATURED BADGES", "caps", ui.MUTED)
	ui.label(fcol, "Show up to three badges", "h3")
	ui.spacer(fwrap)
	var frow = ui.box(fwrap, false, 30)
	frow.alignment = BoxContainer.ALIGN_CENTER
	if a.get("featured", []).empty():
		ui.label(frow, "Open a badge you've earned and choose Feature badge.", "small", ui.MUTED)
	for key in a.get("featured", []):
		for c in a.collections:
			if c.key == key:
				var holder = ui.box(frow, true, 4)
				var badge = ui.medal(holder, _medal(int(c.tier)), c.emblem, 150)
				ui.clickable(badge, self, "_badge_details", {"key":c.key,"tier":max(0,int(c.tier)-1)})
				ui.label(holder, _tname(c, max(0, int(c.tier) - 1)), "caps", ui.MUTED, Label.ALIGN_CENTER)
	var controls = ui.box(parent, false, 16)
	var claimable = 0
	var bonus_claims = {}
	for reward in screen.milestone_rewards():
		if reward.claimable:
			var group = bonus_group(str(reward.key))
			bonus_claims[group] = int(bonus_claims.get(group,0)) + int(reward.xp)
	for c in a.collections:
		claimable += int(bool(c.get("claimable", false)) or bonus_claims.has(str(c.key)))
	_chip_row(controls, [["all", "All"], ["incomplete", "In progress"], ["completed", "Completed"], ["claimable", "Claimable (%d)" % claimable]], achievement_filter, "_achievement_filter")
	var grid = _columns(parent, 3, 1, 26)
	for c in a.collections:
		var tier = int(c.tier)
		var done = tier >= 6
		if achievement_filter == "incomplete" and done:
			continue
		if achievement_filter == "completed" and tier == 0:
			continue
		if achievement_filter == "claimable" and not bool(c.get("claimable", false)) and not bonus_claims.has(str(c.key)):
			continue
		c.bonus_xp = int(bonus_claims.get(str(c.key),0))
		_collection_card(grid, c)

# Claims carry what is being claimed so the XP owner can award it and then
# call journey_store.mark_claimed(key, tier).
func _claim_tier(c):
	screen.claim_tier(c)

func _claim_item(item):
	if str(item.get("kind", "")) == "milestone":
		screen.claim_milestone(str(item.id))
		return
	if str(item.get("kind", "")) == "achievement" and _m().achievements != null:
		var key = str(item.get("target", {}).get("key", ""))
		for c in _m().achievements.collections:
			if c.key == key and bool(c.get("claimable", false)):
				screen.claim_tier(c)
		return
	if str(item.get("kind", "")) == "quest":
		screen.claim_quest({"id": str(item.id).trim_prefix("quest_"), "xp": int(item.get("xp", 0))}, null)
		return
	screen.request("claim", item)

func _achievement_filter(key):
	achievement_filter = key
	screen.refresh()

func _collection_card(parent, c):
	var tier = int(c.tier)
	var next_index = tier
	var target = _thr(c, next_index)
	var previous = _thr(c, tier - 1) if tier > 0 else 0
	var card = ui.card(parent, ui.NAVY, 30, 44)
	ui.grow(card)
	ui.clickable(card, screen, "open_item", {"view": "achievement", "key": c.key})
	var col = ui.box(card, true, 18)
	var top = ui.box(col, false, 22)
	var badge = ui.medal(top, _medal(tier), c.emblem, 176, tier == 0)
	ui.clickable(badge, self, "_badge_details", {"key":c.key,"tier":max(0,tier-1)})
	badge.hint_tooltip = "Statistics, earned date and XP"
	var info = ui.grow(ui.box(top, true, 6))
	info.alignment = BoxContainer.ALIGN_CENTER
	ui.label(info, str(c.name), "h2")
	ui.label(info, (_tname(c, tier - 1).to_upper() + " · TIER %d" % tier) if tier > 0 else "NOT STARTED", "caps", ui.YELLOW if tier > 0 else ui.MUTED)
	ui.label(info, str(c.detail), "small", ui.MUTED)
	if not c.get("unsupported", false):
		var pin = _pin_toggle(top, "achievement", c.key)
		pin.size_flags_vertical = 0
	if c.get("unsupported", false):
		ui.label(col, "Not tracked yet", "small", ui.FAINT)
	else:
		var line = ui.box(col, false, 14)
		var b = ui.bar(line, 1.0 if c.get("catalog_complete",false) else float(int(c.value) - previous) / max(1, target - previous), ui.YELLOW, 22)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ui.label(line, "%s / %s" % [ui.thousands(c.value), ui.thousands(target)], "button", ui.WHITE)
	var foot = ui.box(col, false, 10)
	for i in 6:
		var pip = ui.medal(foot, i, c.emblem, 64, i >= tier)
		pip.hint_tooltip = ui.TIERS[i]
	if bool(c.get("claimable", false)):
		ui.spacer(foot)
		var next_claim = int(c.get("claimed", 0))
		ui.button(foot, "Claim " + ui.xp_text(c.xp[min(next_claim, c.xp.size() - 1)]), "primary", self, "_claim_tier", c, "check")
	elif int(c.get("bonus_xp",0))>0:
		ui.button(foot, "Bonus " + ui.xp_text(c.bonus_xp), "primary", self, "_badge_details", {"key":c.key,"tier":max(0,tier-1)}, "xp")
	elif c.get("catalog_complete",false):
		ui.label(foot, "All catalog tiers earned", "small", ui.MUTED)
	elif not c.get("unsupported", false):
		# Clipped so this line never sets the grid column width (a width it
		# drives can make the grid re-sort forever).
		var next = ui.label(foot, "Next: " + _tname(c, next_index) + " · " + ui.xp_text(c.xp[min(next_index, c.xp.size() - 1)]), "small", ui.MUTED, Label.ALIGN_RIGHT)
		next.clip_text = true
		next.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# Tier helpers: past Kingly (tier 6) levels are "Kingly N" and keep the Kingly medal.
func _tname(c, i) -> String:
	var names = c.get("tier_names", ui.TIERS)
	return str(names[i]) if i < names.size() else "Kingly %d" % (i - 4)

func _thr(c, i) -> int:
	return int(c.thresholds[min(i, c.thresholds.size() - 1)])

func _medal(tier) -> int:
	return int(clamp(tier - 1, 0, 5))

func achievement_detail(parent, arg):
	var m = _m()
	var key = str(arg.get("key", "")) if arg is Dictionary else str(arg)
	var c = null
	if m.achievements != null:
		for candidate in m.achievements.collections:
			if candidate.key == key:
				c = candidate
	if c == null:
		screen.back_row(parent, "Achievement unavailable")
		return
	screen.back_row(parent, str(c.name), str(c.detail))
	var tier = int(c.tier)
	var layout = ui.box(parent, not screen.wide(), 28)
	var hero = ui.card(layout, ui.NAVY.linear_interpolate(Color("3a1575"), 0.2))
	ui.grow(hero, true, false, 0.9)
	var hcol = ui.box(hero, true, 16)
	hcol.alignment = BoxContainer.ALIGN_CENTER
	var holder = ui.box(hcol, true, 0)
	holder.alignment = BoxContainer.ALIGN_CENTER
	var badge = ui.medal(holder, _medal(tier), c.emblem, 340, tier == 0)
	ui.clickable(badge, self, "_badge_details", {"key":c.key,"tier":max(0,tier-1)})
	badge.hint_tooltip = "Statistics and rewards"
	ui.label(hcol, (_tname(c, tier - 1) + " tier") if tier > 0 else "Not started", "h1", ui.WHITE, Label.ALIGN_CENTER)
	ui.label(hcol, ("%d qualifying level%s" % [int(c.value), "" if int(c.value) == 1 else "s"]) if c.key == "builder" else ("Best streak: %d" % int(c.value) if c.key == "streak" else "%s recorded" % ui.thousands(c.value)), "body", ui.MUTED, Label.ALIGN_CENTER)
	var actions = ui.box(hcol, false, 14)
	actions.alignment = BoxContainer.ALIGN_CENTER
	if c.get("unsupported", false):
		ui.label(hcol, "Not tracked yet", "small", ui.FAINT, Label.ALIGN_CENTER)
	else:
		_pin_button(actions, "achievement", c.key, "Pin next tier")
		var featured = m.achievements.get("featured", []).has(c.key)
		var feature = ui.button(actions, "Unfeature" if featured else "Feature badge", "small", screen, "toggle_feature", c.key, "star")
		feature.disabled = tier == 0
	var tiers = ui.card(layout)
	ui.grow(tiers, true, false, 1.3)
	var tcol = ui.box(tiers, true, 14)
	ui.heading(tcol, "Tiers", "achievements")
	for i in c.thresholds.size():
		# Show the six named tiers plus the most recent Kingly levels.
		if i >= 6 and i < tier - 2:
			continue
		var reached = i < tier
		var p = ui.well(tcol, ui.NAVY_2 if reached or i == tier else Color(1, 1, 1, 0.03), 16, 28)
		var row = ui.box(p, false, 20)
		var tier_badge = ui.medal(row, min(i, 5), c.emblem, 92, not reached)
		ui.clickable(tier_badge, self, "_badge_details", {"key":c.key,"tier":i})
		tier_badge.hint_tooltip = "Statistics and rewards"
		var col = ui.grow(ui.box(row, true, 2))
		col.alignment = BoxContainer.ALIGN_CENTER
		ui.label(col, _tname(c, i), "h3", ui.WHITE if reached or i == tier else ui.MUTED)
		ui.label(col, "Reach %s" % ui.thousands(c.thresholds[i]), "small", ui.MUTED)
		if reached:
			ui.label(row, ui.date_text(c.dates[i], true) if int(c.dates[i]) > 0 else "Date unavailable", "small", ui.GREEN_LIGHT)
		elif i == tier:
			var b = ui.bar(row, float(c.value) / max(1, int(c.thresholds[i])), ui.YELLOW, 18)
			b.rect_min_size.x = 220
			b.size_flags_horizontal = 0
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if reached and i == int(c.get("claimed", 0)) and bool(c.get("claimable", false)):
			ui.button(row, "Claim " + ui.xp_text(c.xp[i]), "primary", self, "_claim_tier", c, "check")
		elif reached and i < int(c.get("claimed", 0)):
			ui.pill(row, "CLAIMED", ui.INK, ui.GREEN_LIGHT, "check")
		else:
			ui.pill(row, ui.xp_text(c.xp[i]), ui.INK, ui.GREEN_LIGHT if reached else ui.YELLOW)
	if c.key == "builder":
		_builder_levels(parent, m.get("builder"))

# Goob Builder: every published level, whether it counts (more than 200
# objects) and the one-time bonus for levels that made it into CERTIFIED.
func _builder_levels(parent, builder):
	var card = ui.card(parent)
	var col = ui.box(card, true, 12)
	ui.heading(col, "Your published levels", "hammer", "Counts from %d objects" % (screen.builder.MIN_OBJECTS + 1))
	if builder == null:
		screen.empty_state(col, "hammer", "Checking your levels…", "")
		return
	if builder.levels.empty():
		screen.empty_state(col, "hammer", "No published levels yet", "")
		return
	var levels = builder.levels.duplicate()
	levels.sort_custom(self, "_by_objects")
	for level in levels:
		var p = ui.well(col, ui.NAVY_2, 16, 24)
		var row = ui.box(p, false, 16)
		ui.tile_icon(row, "star" if level.certified else "hammer", ui.YELLOW if level.certified else (ui.GREEN_LIGHT if level.qualifies else ui.MUTED), 56)
		var info = ui.grow(ui.box(row, true, 0))
		info.alignment = BoxContainer.ALIGN_CENTER
		var name = ui.label(info, str(level.name), "h3")
		name.clip_text = true
		ui.label(info, "%s objects%s" % [ui.thousands(level.objects), " · Certified" if level.certified else ""], "small", ui.MUTED)
		if level.certified:
			var key = "certified:" + str(level.id)
			if screen.journey_store.flag(key):
				ui.pill(row, "BONUS CLAIMED", ui.INK, ui.GREEN_LIGHT, "check")
			else:
				ui.button(row, "Claim " + ui.xp_text(screen.CERTIFIED_XP), "primary", screen, "claim_certified", level, "check")
		ui.pill(row, "COUNTS" if level.qualifies else "TOO SMALL", ui.INK if level.qualifies else ui.WHITE, ui.GREEN_LIGHT if level.qualifies else Color(1, 1, 1, 0.1))

func _by_objects(a, b) -> bool:
	return int(a.objects) > int(b.objects)

# ================================================================== rewards
func rewards(parent):
	var m = _m()
	var head = screen.section_intro(parent, "Themes, Finishes & Badges")
	if m.cosmetics == null:
		var card = ui.card(parent)
		var col = ui.box(card, true, 24)
		screen.empty_state(col, "rewards", "Cosmetic rewards aren't connected yet", "")
		var grid = _columns(col, 3, 1, 22)
		for entry in [["palette", "Complete themes", "Full menu themes", Color("ff7ed3")],
				["flag", "Finish animations", "Finish line celebrations", Color("5ee0c8")],
				["achievements", "Achievement badges", "Achievement badges", Color("ffc40f")]]:
			var tile = ui.well(grid, ui.NAVY_2, 26, 32)
			ui.grow(tile)
			var c = ui.box(tile, true, 12)
			ui.tile_icon(c, entry[0], entry[3], 88)
			ui.label(c, entry[1], "h3")
			ui.label(c, entry[2], "small", ui.MUTED)
		return
	var tabs = [["themes", "Themes"], ["badges", "Badges"]]
	if not m.cosmetics.finishes.empty():
		tabs.insert(1, ["finishes", "Finishes"])
	elif reward_tab == "finishes":
		reward_tab = "themes"
	ui.segmented(parent, tabs, reward_tab, self, "_reward_tab")
	if reward_tab == "finishes":
		var grid = _columns(parent, 3, 1, 26)
		for finish in m.cosmetics.finishes:
			_finish_reward_card(grid, finish)
	elif reward_tab != "badges":
		var themes = m.cosmetics.themes
		var equipped = themes[0]
		var unlocked = 0
		for theme in themes:
			unlocked += int(str(theme.state) != "locked")
			if str(theme.state) == "equipped":
				equipped = theme
		var banner = ui.card(parent, ui.NAVY, 20, 36)
		var brow = ui.box(banner, false, 22)
		var thumb = theme_art(brow, equipped, 150)
		thumb.rect_min_size.x = 267
		thumb.size_flags_horizontal = 0
		var bcol = ui.grow(ui.box(brow, true, 4))
		bcol.alignment = BoxContainer.ALIGN_CENTER
		ui.label(bcol, "MENU THEME", "caps", ui.MUTED)
		ui.label(bcol, str(equipped.name), "h2")
		ui.label(bcol, "%d of %d unlocked" % [unlocked, themes.size()], "small", ui.MUTED)
		var grid = _columns(parent, 4, 2, 26)
		for theme in themes:
			_theme_card(grid, theme)
	else:
		var card = ui.card(parent)
		var col = ui.box(card, true, 20)
		ui.heading(col, "Earned badges", "achievements", "Shown on your profile")
		var grid = _columns(col, 6, 3, 20)
		if m.achievements != null:
			for c in m.achievements.collections:
				var cell = ui.box(grid, true, 8)
				cell.alignment = BoxContainer.ALIGN_CENTER
				ui.medal(cell, _medal(int(c.tier)), c.emblem, 160, int(c.tier) == 0)
				ui.label(cell, str(c.name), "small", ui.MUTED, Label.ALIGN_CENTER)
	_upcoming(parent)

func _reward_tab(key):
	reward_tab = key
	screen.refresh()

func _state_pill(parent, state):
	match str(state):
		"equipped":
			return ui.pill(parent, "EQUIPPED", ui.INK, ui.GREEN_LIGHT, "check")
		"unlocked":
			return ui.pill(parent, "UNLOCKED", ui.INK, ui.SKY_LIGHT)
	return ui.pill(parent, "LOCKED", ui.WHITE, Color(1, 1, 1, 0.1), "lock")

# The theme as the main menu shows it: its sky gradient with the sky and
# horizon art from theme_backgrounds/ (the Official theme uses the game's sky).
func theme_art(parent, theme, height = 200):
	var c = theme.colors
	var frame = Control.new()
	frame.rect_min_size = Vector2(0, height)
	frame.rect_clip_content = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var sky = TextureRect.new()
	sky.expand = true
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	if theme.get("official", false):
		sky.texture = load("res://gfx/cloudsky.png") if ResourceLoader.exists("res://gfx/cloudsky.png") else null
	if sky.texture == null:
		var gradient = Gradient.new()
		gradient.set_color(0, Color(str(c.top)))
		gradient.set_color(1, Color(str(c.bottom)))
		var fill = GradientTexture2D.new()
		fill.gradient = gradient
		fill.fill_to = Vector2(0, 1)
		sky.texture = fill
	frame.add_child(sky)
	if not theme.get("official", false):
		for layer in ["sky", "horizon"]:
			var texture = screen.theme_rules.art(str(theme.key), layer)
			if texture == null:
				continue
			var art = TextureRect.new()
			art.texture = texture
			art.expand = true
			art.stretch_mode = TextureRect.STRETCH_SCALE if layer == "horizon" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(art)
			art.anchor_right = 1.0
			art.anchor_top = 0.52 if layer == "horizon" else 0.0
			art.anchor_bottom = 1.0 if layer == "horizon" else 0.6
	var edge = Panel.new()
	edge.add_stylebox_override("panel", ui.flat(Color(0, 0, 0, 0), 26, 0, 0, ui.INK, false))
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	frame.add_child(edge)
	return frame

func _theme_card(parent, theme):
	var locked = str(theme.state) == "locked"
	var card = ui.card(parent, ui.NAVY, 0, 38)
	ui.grow(card)
	ui.clickable(card, self, "_preview_theme", theme)
	var outer = ui.box(card, true, 0)
	var art = theme_art(outer, theme, 190)
	if locked:
		art.modulate = Color(0.55, 0.6, 0.75, 1)
		var lock = CenterContainer.new()
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		art.add_child(lock)
		ui.tile_icon(lock, "lock", ui.WHITE, 72)
	var body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		body.add_constant_override("margin_" + side, 22)
	outer.add_child(body)
	var col = ui.box(body, true, 10)
	var row = ui.box(col, false, 12)
	var title = ui.label(row, str(theme.name), "h3")
	title.clip_text = true
	ui.grow(title)
	_state_pill(row, theme.state)
	if locked:
		ui.label(col, str(theme.requirement), "small", ui.MUTED)
		var to_go = int(theme.get("rank_xp", 0)) - int(screen.ledger.total_xp)
		ui.bar(col, float(screen.ledger.total_xp) / max(1, int(theme.get("rank_xp", 1))), ui.YELLOW, 12)
		ui.label(col, "%s XP to go" % ui.thousands(max(0, to_go)), "small", ui.FAINT)
	elif str(theme.state) == "equipped":
		ui.label(col, "In use on the main menu", "small", ui.GREEN_LIGHT)
	else:
		var equip = ui.button(col, "Equip", "primary", screen, "equip_theme", theme, "check")
		equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _preview_theme(theme):
	var body = screen._overlay(str(theme.name) + " theme", "palette")
	var art = theme_art(body, theme, 480)
	art.rect_min_size.x = 853
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row = ui.box(body, false, 14)
	ui.label(row, str(theme.requirement), "body", ui.MUTED)
	ui.spacer(row)
	if str(theme.state) == "unlocked":
		ui.button(row, "Equip theme", "primary", screen, "equip_theme", theme, "check")
	elif str(theme.state) == "equipped":
		ui.pill(row, "EQUIPPED", ui.INK, ui.GREEN_LIGHT, "check")
	elif theme.has("rank_id"):
		_pin_button(row, "rank", str(theme.rank_id), "Pin " + str(theme.get("rank_name", "rank")))
