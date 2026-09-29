extends "user://mod/tools/journey/ui/JourneyScreen/01_placeholders.gd"

func build(store):
	rect_clip_content = true
	ledger = store
	var base = get_script().resource_path.get_base_dir()
	definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
	art = load(ModPaths.path("JourneyArt.gd")).new()
	ui = load(ModPaths.path("JourneyUI.gd")).new(art)
	models = load(ModPaths.path("JourneyModel.gd")).new()
	pages = load(ModPaths.path("JourneyPages.gd")).new(self, ui)
	journey_store = load(ModPaths.path("JourneyStore.gd")).new()
	achievement_rules = load(ModPaths.path("JourneyAchievements.gd")).new()
	session_rules = load(ModPaths.path("JourneySessions.gd")).new()
	quest_rules = load(ModPaths.path("JourneyQuests.gd")).new()
	career_rules = load(ModPaths.path("JourneyCareer.gd")).new()
	theme_rules = load(ModPaths.path("JourneyThemes.gd")).new(base)
	builder = load(ModPaths.path("JourneyBuilder.gd")).new()
	add_child(builder)
	builder.connect("updated", self, "refresh")
	# Only the home screen asks the server; the in-match overlay reads the cache.
	builder.fetching = not closable
	leaderboard = load(ModPaths.path("JourneyLeaderboard.gd")).new()
	add_child(leaderboard)
	leaderboard.connect("updated", self, "_leaderboard_updated")
	var preview_script = load(ModPaths.path("JourneyPreview.gd"))
	if preview_script != null:
		preview_data = preview_script.new()
	var sound_script = load(ModPaths.path("JourneySound.gd"))
	if sound_script != null:
		sound = sound_script.new(base)
		add_child(sound)
	_load_prefs()
	for edge in ["left", "right", "top", "bottom"]:
		add_constant_override("margin_" + edge, 36)
	root = ui.box(self, true, 26)
	ui.spacer(root, 0, 18)
	_header(root)
	scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.follow_focus = true
	ui.grow(scroll, true, true)
	_style_scrollbar(scroll)
	root.add_child(scroll)
	var pad = MarginContainer.new()
	for edge in ["left", "right"]:
		pad.add_constant_override("margin_" + edge, 6)
	pad.add_constant_override("margin_top", 6)
	pad.add_constant_override("margin_bottom", 40)
	ui.grow(pad)
	scroll.add_child(pad)
	content = ui.box(pad, true, 30)
	ui.grow(content)
	connect("resized", self, "_resized")
	_select_section("Overview")

# ------------------------------------------------------------------ routing
func _select_section(title):
	if not title in SECTIONS:
		title = "Overview"
	section = title
	view = ""
	view_arg = null
	_render()

func open(target_view, arg = null):
	play("click")
	view = target_view
	view_arg = arg
	_render()

func open_item(spec):
	if str(spec.get("view", "")).empty() and str(spec.get("section", "")) in SECTIONS:
		close_overlay()
		_select_section(spec.section)
		return
	open(str(spec.get("view", "")), spec)

func back():
	# Back from XP history opened on a match result returns to that result.
	if view == "history" and _history_from_results and last_results != null:
		_history_from_results = false
		view = ""
		_render()
		show_match_results(last_results[0], last_results[1], last_results[2], false)
		return
	_history_from_results = false
	if view == "map" or view == "achievement":
		view = ""
	elif view != "":
		view = ""
	_render()

# Re-render in place (keeps the scroll position; section changes reset it).
func refresh():
	var keep = scroll.scroll_vertical if scroll != null else 0
	_quiet_render = true
	_render()
	_quiet_render = false
	if scroll != null and keep > 0:
		scroll.call_deferred("set_v_scroll", keep)

# Stats count rounds from every account signed in on this PC (read-only; the
# account's own store, export/import/reset and XP stay per account).
func _merge_accounts(m):
	var store = m.stats.store
	var records = career_rules.merged_records(str(store.account_id), store.records)
	m.stats.records = records
	if records.size() == store.records.size():
		return
	var stats = store.statistics(records)
	var progression = store.progression(records)
	var maps = []
	var best = {}
	for r in records:
		var key = str(r.mode) + ":" + str(r.map_id)
		if int(r.placement) > 0 and (int(best.get(key, 0)) == 0 or int(r.placement) < int(best[key])):
			best[key] = int(r.placement)
	for key in stats.maps:
		var entry = stats.maps[key].duplicate()
		entry.key = key
		entry.best_placement = int(best.get(key, 0))
		entry.pb_steps = progression.maps[key].steps if progression.maps.has(key) else []
		maps.append(entry)
	var recent = records.duplicate()
	recent.invert()
	m.stats.all = stats
	m.stats.maps = maps
	m.stats.highlights = store.highlights(records)
	m.stats.recent = recent.slice(0, min(recent.size(), 40) - 1)
	m.stats.pb_events = progression.events
	m.stats.accounts = career_rules.account_count()

# Local systems that need no game hooks: achievements and milestones from the
# recorded match history, plus pins, featured badges and the inbox from
# JourneyStore. Returns inbox items that are new since the last render.
func _connect_local(m):
	journey_store.configure(str(ledger.account_id))
	if m.stats != null and m.stats.get("store") != null:
		if m.preview:
			m.stats.records = m.stats.store.records
		else:
			_merge_accounts(m)
	if not m.preview and journey_store.writable and leaderboard != null:
		var moonlight = get_node_or_null("/root/Moonlight") if is_inside_tree() else null
		var display = moonlight.storage.storage_get("account.user.display_name", "") if moonlight != null and moonlight.get("storage") != null else ""
		leaderboard.submit(str(ledger.account_id), display, int(ledger.total_xp), str(definitions.rank_at(int(ledger.total_xp)).name))
	if not m.preview and m.get("roadmap") != null:
		m.cosmetics = {"themes": theme_rules.build(m.roadmap, int(ledger.total_xp), theme_rules.equipped(get_tree() if is_inside_tree() else null)), "finishes": _finishes()}
	if m.stats != null and m.stats.get("store") != null:
		var levels = null
		if builder != null and not m.preview:
			builder.configure(str(ledger.account_id))
			levels = builder.summary()
		var derived = achievement_rules.build(m.stats.records, journey_store, levels)
		m.builder = levels
		m.achievements = derived.achievements
		m.milestones = derived.milestones
		m.sessions = session_rules.build(m.stats.records, m.transactions)
		# Session recap: once the latest session has ended (no round for 30 min).
		if journey_store.writable and not m.sessions.empty() and not model_is_preview(m):
			var s = m.sessions[0]
			if OS.get_unix_time() - int(s.end) > session_rules.GAP and int(s.rounds) > 0:
				var detail = "%d round%s · %d win%s · %d new map%s" % [int(s.rounds), "" if int(s.rounds) == 1 else "s", int(s.wins), "" if int(s.wins) == 1 else "s", int(s.maps), "" if int(s.maps) == 1 else "s"]
				if journey_store.push({"id": "session_" + str(s.id), "kind": "session", "state": "unread", "title": "Session recap",
						"detail": detail, "time": int(s.end), "target": {"view": "session"}}) and bool(prefs.get("session_summary", true)):
					call_deferred("notify", "session", "Session recap", detail, int(s.xp), "session")
	if activity != null and is_instance_valid(activity) and activity.writable:
		m.activity = activity.snapshot()
	if not m.preview:
		var extra_milestones = load(ModPaths.path("JourneyMilestones.gd")).new().build(m, definitions)
		if m.milestones == null:
			m.milestones = []
		m.milestones.append_array(extra_milestones)
	if m.stats != null and m.stats.get("store") != null:
		var active_days = activity.active_days() if activity != null and is_instance_valid(activity) and activity.writable else {}
		m.streak = session_rules.streaks(m.stats.records, active_days)
	if not m.preview and str(section) == "Career":
		m.career = career_rules.build(str(ledger.account_id), m.activity, m.stats.records if m.stats != null and m.stats.get("records") != null else null)
		m.career_sessions = session_rules.build(m.career.records, m.transactions)
	if not journey_store.writable:
		return []
	if not m.preview and not journey_store.flag("notice:xp_calculated"):
		journey_store.push({"id": "calculate_xp", "kind": "reward", "state": "unread", "title": "Calculate your XP",
			"detail": "Add XP for the games you played before Goobplayability", "time": OS.get_unix_time(), "target": {"view": "calculate_xp"}})
	elif not m.preview and int(journey_store.backfill.get("version", 1)) < 3:
		journey_store.push({"id": "recalculate_xp", "kind": "reward", "state": "unread", "title": "Calculated XP was rebalanced",
			"detail": "Recalculate to include maps you have likely played", "time": OS.get_unix_time(), "target": {"view": "calculate_xp"}})
	if m.stats != null and m.stats.get("store") != null:
		m.quests = quest_rules.build(m.stats.records, journey_store, m.activity)
		for q in m.quests.daily + m.quests.weekly:
			if q.done and not q.claimed:
				journey_store.push({"id": "quest_" + q.id, "kind": "quest", "state": "claimable" if q.claimable else "unread",
					"title": ("Challenge complete" if q.weekly else "Quest complete"), "detail": q.title, "xp": q.xp if q.claimable else 0,
					"time": OS.get_unix_time(), "target": {"view": "", "section": "Quests"}})
	var fresh = journey_store.sync(m)
	m.inbox = journey_store.inbox
	m.pins = pages.resolve_pins(m, journey_store.pins)
	return fresh

func model_is_preview(m) -> bool:
	return bool(m.get("preview", false)) or design_preview

func toggle_pin(spec):
	if model.preview or not journey_store.writable:
		_toast("Preview: nothing is saved." if model.preview else "Sign in to pin goals.")
		return
	var result = journey_store.toggle_pin(str(spec.kind), str(spec.key))
	play("toggle")
	if result == "full":
		_toast("You can pin up to three goals. Unpin one first.")
	elif result == "pinned" or journey_store.has_pin(str(spec.kind), str(spec.key)):
		_toast("Pinned to Overview")
	else:
		_toast("Unpinned")
	refresh()

func toggle_feature(key):
	if model.preview or not journey_store.writable:
		_toast("Preview: nothing is saved." if model.preview else "Sign in to feature badges.")
		return
	if journey_store.toggle_featured(str(key)) == "full":
		_toast("You can feature up to three badges.")
	play("toggle")
	refresh()

func inbox_open(item):
	if journey_store.writable and not model.preview:
		journey_store.mark_read(str(item.id))
	close_overlay()
	var target = item.get("target", {})
	if target is Dictionary and str(target.get("view", "")) == "calculate_xp":
		open_xp_calculator()
	elif target is Dictionary and target.has("view"):
		open_item(target)
	else:
		refresh()

func inbox_mark_all_read():
	if journey_store.writable and not model.preview:
		journey_store.mark_all_read()
		play("toggle")
	_open_inbox()

func _render():
	if content == null:
		return
	model = models.build(ledger, definitions, profile_service)
	_apply_test_xp(model)
	var fresh = _connect_local(model)
	if design_preview and preview_data != null:
		model = preview_data.apply(model, definitions)
	ui.reduced_motion = bool(prefs.reduced_motion)
	_update_nav()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_banners(content)
	match view:
		"roadmap":
			pages.roadmap(content)
		"stats":
			pages.statistics(content)
		"session":
			pages.session(content)
		"map":
			pages.map_detail(content, view_arg)
		"achievement":
			pages.achievement_detail(content, view_arg)
		"history":
			pages.history(content)
		"calendar":
			pages.calendar(content)
		"leaderboard":
			pages.leaderboard(content)
		_:
			match section:
				"Overview":
					_overview(content)
				"Quests":
					pages.quests(content)
				"Maps":
					pages.maps(content)
				"Achievements":
					pages.achievements(content)
				"Rewards":
					pages.rewards(content)
				"Career":
					pages.activity(content)
	xp_anim_from = -1
	scroll.scroll_vertical = 0
	# Announce at most two new items per render; the inbox keeps the rest.
	if not model.preview and str(prefs.notify) != "inbox":
		for i in min(2, fresh.size()):
			notify(fresh[i].kind, fresh[i].title, fresh[i].detail, fresh[i].xp, fresh[i].target if not fresh[i].target.empty() else "inbox")
	if not ui.reduced_motion and is_inside_tree() and not _quiet_render:
		content.modulate = Color(1, 1, 1, 0)
		var tween = _tween()
		tween.interpolate_property(content, "modulate", Color(1, 1, 1, 0), Color.white, 0.22, Tween.TRANS_QUAD, Tween.EASE_OUT)
		tween.start()

# A fresh one-shot tween per animation. A shared tween that was cleared for
# each new animation cut the page fade-in short and left pages invisible.
func _tween():
	var tween = Tween.new()
	add_child(tween)
	tween.connect("tween_all_completed", tween, "queue_free")
	return tween

func _resized():
	# Measured from the space we are given, not our own rect: content wider than
	# MAX_WIDTH would otherwise grow the rect, then the margins, then the rect...
	var avail = get_parent_area_size().x
	var side = max(36, int((avail - MAX_WIDTH) * 0.5))
	add_constant_override("margin_left", side)
	add_constant_override("margin_right", side)
	var next_layout = "wide" if avail - side * 2 >= WIDE_AT else "narrow"
	if next_layout != layout:
		layout = next_layout
		_rebuild_nav()
		_render()

func wide() -> bool:
	return layout == "wide"

# ------------------------------------------------------------------ shell
# Wide: title, nav capsule and buttons share one row. Narrow: the nav capsule
# drops to its own full-width row under the title.
func _header(parent):
	header_col = ui.box(parent, true, 18)
	var row = ui.box(header_col, false, 22)
	header_row = row
	var title = ui.label(row, "JOURNEY", "title")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_gap = ui.grow(Control.new())
	row.add_child(header_gap)
	nav_row = PanelContainer.new()
	var track = ui.flat(ui.INK, 48, 10, 0, ui.NAVY_DEEP, true)
	track.bg_color = Color(0, 0.13, 0.28, 0.94)
	nav_row.add_stylebox_override("panel", track)
	ui.grow(nav_row)
	row.add_child(nav_row)
	_round_button(row, "inbox", "_open_inbox", _unread())
	_round_button(row, "gear", "_open_prefs", 0)
	if closable:
		_round_button(row, "close", "_request_close", 0)

func _request_close():
	play("click")
	emit_signal("close_requested")

func _round_button(parent, key, method, count):
	var holder = Control.new()
	holder.rect_min_size = Vector2(96, 96)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)
	var b = ui.button(holder, "", "quiet", self, method, null, key)
	b.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	b.hint_tooltip = {"inbox": "Inbox", "gear": "Journey preferences", "close": "Close"}.get(key, "")
	for state in ["normal", "hover", "pressed", "focus"]:
		var s = b.get_stylebox(state).duplicate()
		s.set_corner_radius_all(48)
		s.content_margin_left = 24
		s.content_margin_right = 24
		b.add_stylebox_override(state, s)
	holder.set_meta("count_key", key)
	if count > 0:
		_count_bubble(holder, count)

func _count_bubble(holder, count):
	var bubble = PanelContainer.new()
	bubble.name = "Count"
	var s = ui.flat(ui.PINK, 22, 8, 0, ui.INK, false)
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.border_width_left = 4
	s.border_width_right = 4
	s.border_width_top = 4
	s.border_width_bottom = 4
	s.border_color = ui.INK
	bubble.add_stylebox_override("panel", s)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = ui.label(bubble, str(count), "caps", ui.WHITE, Label.ALIGN_CENTER)
	l.add_font_override("font", ui.font("display", 26))
	bubble.rect_position = Vector2(56, -8)
	holder.add_child(bubble)

func _rebuild_nav():
	nav_row.get_parent().remove_child(nav_row)
	if wide():
		header_row.add_child(nav_row)
		header_row.move_child(nav_row, 2)
	else:
		header_col.add_child(nav_row)
	header_gap.visible = not wide()
	for child in nav_row.get_children():
		nav_row.remove_child(child)
		child.queue_free()
	var items = ui.box(nav_row, false, 8 if wide() else 0)
	for title in SECTIONS:
		var item = PanelContainer.new()
		item.name = title
		ui.grow(item)
		items.add_child(item)
		var inner = ui.box(item, not wide(), 4 if not wide() else 14)
		inner.alignment = BoxContainer.ALIGN_CENTER
		ui.icon(inner, SECTION_ICONS[title], 44 if wide() else 40)
		# Red "!" when something in this section can be claimed.
		var overlay = Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(overlay)
		var badge = make_badge(34 if wide() else 30)
		badge.name = "ClaimBadge"
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.margin_left = -38 if wide() else -32
		badge.margin_top = 2
		overlay.add_child(badge)
		item.set_meta("badge", badge)
		var label = ui.label(inner, title, "h3", ui.WHITE, Label.ALIGN_CENTER)
		if not wide():
			label.add_font_override("font", ui.font("display", 23))
		item.set_meta("parts", inner)
	_update_nav()

func _update_nav():
	if nav_row == null or nav_row.get_child_count() == 0:
		return
	update_claims(false)
	var items = nav_row.get_child(0)
	for item in items.get_children():
		if item.has_meta("badge"):
			item.get_meta("badge").visible = int(claim_counts.get(item.name, 0)) > 0
		var active = item.name == section
		var s = ui.flat(ui.WHITE if active else Color(0, 0, 0, 0), 38, 20 if wide() else 4, 6 if active else 0, ui.PINK, false)
		s.content_margin_top = 14 if wide() else 10
		s.content_margin_bottom = 14 if wide() else 10
		item.add_stylebox_override("panel", s)
		if not item.has_meta("wired"):
			item.set_meta("wired", true)
			ui.clickable(item, self, "_nav_pressed", item.name, ui.NAVY_3)
		var styles = item.get_meta("journey_styles")
		styles[0] = s
		if active:
			styles[1] = s
		item.set_meta("journey_styles", styles)
		var tint = ui.INK if active else ui.MUTED
		for part in item.get_meta("parts").get_children():
			if part is Label:
				part.add_color_override("font_color", ui.INK if active else ui.WHITE)
			else:
				part.modulate = tint
		item.hint_tooltip = item.name

func _nav_pressed(title):
	if title == section and view == "":
		return
	play("click")
	_select_section(title)
