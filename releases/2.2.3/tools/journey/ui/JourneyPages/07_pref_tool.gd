extends "user://mod/tools/journey/ui/JourneyPages/06_rank_king.gd"

func _fill_records():
	if record_list == null or not is_instance_valid(record_list):
		return
	for child in record_list.get_children():
		record_list.remove_child(child)
		child.queue_free()
	var st = _m().stats
	var maps = st.maps.duplicate()
	maps.sort_custom(self, "_by_name")
	var shown = 0
	for map in maps:
		if record_query != "" and (str(map.name) + " " + str(map.mode)).to_lower().find(record_query.to_lower()) < 0:
			continue
		shown += 1
		var p = ui.well(record_list, ui.NAVY_2, 16, 26)
		ui.clickable(p, screen, "open_item", {"view": "map", "key": map.key})
		var row = ui.box(p, false, 18)
		var col = ui.grow(ui.box(row, true, 0))
		ui.label(col, str(map.name), "h3")
		ui.label(col, str(map.mode), "small", ui.MUTED)
		for pair in [[("%.3fs" % float(map.best)) if float(map.best) >= 0 else "—", "BEST"], [str(map.completions), "FINISHES"], [str(map.wins), "WINS"], [ui.date_text(map.last_played), "LAST PLAYED"]]:
			var c = ui.box(row, true, 0)
			c.rect_min_size.x = 170 if screen.wide() else 120
			ui.label(c, pair[1], "caps", ui.FAINT, Label.ALIGN_RIGHT)
			ui.label(c, pair[0], "button", ui.WHITE, Label.ALIGN_RIGHT)
		ui.icon(row, "chevron_right", 28, ui.MUTED)
	if shown == 0:
		ui.label(record_list, "No matching map records.", "small", ui.MUTED)

func _by_name(a, b) -> bool:
	return str(a.name).to_lower() < str(b.name).to_lower()

func _export():
	var store = _m().stats.get("store")
	if store == null:
		screen._toast("Nothing to export in preview.")
		return
	OS.clipboard = store.export_text()
	screen._toast("Recorded history copied to the clipboard. Account stats aren't included.")

func _import():
	if _m().stats.get("store") == null:
		screen._toast("Import isn't available in preview.")
		return
	var body = screen._overlay("Import recorded history", "inbox")
	ui.label(body, "Paste exported JSON for this account. Existing records are kept; duplicates are skipped by the store.", "small", ui.MUTED)
	var edit = TextEdit.new()
	edit.rect_min_size = Vector2(0, 420)
	edit.add_font_override("font", ui.font("text", 24))
	edit.add_stylebox_override("normal", ui.flat(ui.NAVY_DEEP, 24, 20, 0, ui.INK, false))
	edit.add_color_override("font_color", ui.WHITE)
	body.add_child(edit)
	var row = ui.box(body, false, 14)
	ui.spacer(row)
	ui.button(row, "Import", "primary", self, "_confirm_import", edit, "check")

func _confirm_import(edit):
	var store = _m().stats.store
	var ok = store.import_text(edit.text)
	screen.close_overlay()
	screen.refresh()
	screen._toast("History imported." if ok else str(store.last_error))

func _reset():
	if _m().stats.get("store") == null:
		screen._toast("Reset isn't available in preview.")
		return
	var body = screen._overlay("Reset recorded history?", "close")
	ui.label(body, "This clears this account's locally recorded history and current session. Journey XP and your GooberDash account stats are not affected.", "body", ui.MUTED)
	var row = ui.box(body, false, 14)
	ui.spacer(row)
	ui.button(row, "Cancel", "secondary", screen, "close_overlay")
	ui.button(row, "Reset", "accent", self, "_confirm_reset", null, "close")

func _confirm_reset():
	var store = _m().stats.store
	var ok = store.reset()
	screen.close_overlay()
	screen.refresh()
	screen._toast("Recorded history reset." if ok else str(store.last_error))

# ================================================================== inbox
func inbox(body):
	var m = _m()
	if m.inbox == null:
		screen.empty_state(body, "inbox", "Notifications aren't connected yet", "")
		return
	var actions = ui.box(body, false, 12)
	var claimable = screen.claimables()
	ui.button(actions, "Claim all (%d)" % claimable.size(), "primary", screen, "claim_all", null, "check").disabled = claimable.empty()
	ui.button(actions, "Mark all read", "small", screen, "inbox_mark_all_read", null, "check")
	var groups = [["READY TO CLAIM", "claimable"], ["NEW", "unread"], ["EARLIER", "read"]]
	for group in groups:
		var items = []
		for item in m.inbox:
			if str(item.state) == group[1] or (group[1] == "read" and str(item.state) == "claimed"):
				items.append(item)
		if items.empty():
			continue
		ui.label(body, group[0], "caps", ui.MUTED)
		for item in items:
			var p = ui.well(body, ui.NAVY_2 if item.state != "read" else Color(1, 1, 1, 0.03), 18, 28)
			if item.state != "claimable" and not m.preview:
				ui.clickable(p, screen, "inbox_open", item)
			var row = ui.box(p, false, 18)
			ui.tile_icon(row, _kind_icon(str(item.kind)), ui.YELLOW if item.state == "claimable" else ui.MUTED, 68)
			var col = ui.grow(ui.box(row, true, 0))
			ui.label(col, str(item.title), "h3", ui.WHITE if item.state != "read" else ui.MUTED)
			ui.label(col, "%s · %s" % [str(item.detail), _ago(item.time)], "small", ui.MUTED)
			if item.state == "claimable":
				ui.button(row, "Claim " + ui.xp_text(item.xp), "primary", self, "_claim_item", item, "check")
			elif item.state == "unread":
				var dot = Panel.new()
				dot.add_stylebox_override("panel", ui.flat(ui.PINK, 10, 0, 0, ui.INK, false))
				dot.rect_min_size = Vector2(20, 20)
				dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(dot)

func _ago(timestamp) -> String:
	var d = OS.get_unix_time() - int(timestamp)
	if d < 3600:
		return "%d min ago" % max(1, d / 60)
	if d < 86400:
		return "%d h ago" % (d / 3600)
	return ui.date_text(timestamp)

# ================================================================== preferences
func _knob(color):
	var size = 36
	var img = Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	var c = (size - 1) / 2.0
	for y in size:
		for x in size:
			var d = Vector2(x - c, y - c).length()
			var a = clamp(c - d + 0.5, 0.0, 1.0)
			var col = color if d < c - 5 else ui.INK
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex

func test_tools(body):
	var store = screen.journey_store
	var t = store.test if store.writable else {}
	ui.label(body, "For testing. Nothing here touches your real XP; Reset to normal undoes it all.", "small", ui.MUTED)
	var xp_group = _tool_group(body, "Journey XP", "xp", "Showing %s XP (real %s)" % [ui.thousands(int(screen.model.xp)), ui.thousands(int(screen.ledger.total_xp))], [
		["+1,000", "test_xp", 1000], ["+10,000", "test_xp", 10000], ["+100,000", "test_xp", 100000],
		["Next rank", "test_next_rank", null], ["Remove test XP", "test_reset_xp", null]])
	# Any amount, or any rank.
	var set_row = ui.box(xp_group, false, 12)
	var amount = LineEdit.new()
	amount.placeholder_text = "Total XP, e.g. 250000"
	amount.text = str(int(screen.model.xp))
	amount.rect_min_size = Vector2(360, 56)
	amount.add_font_override("font", ui.font("display", 30))
	for state in ["normal", "focus", "read_only"]:
		var box = ui.flat(ui.NAVY_DEEP, 20, 18, 0, ui.INK, false)
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		amount.add_stylebox_override(state, box)
	amount.add_color_override("font_color", ui.WHITE)
	set_row.add_child(amount)
	ui.button(set_row, "Set XP", "small", self, "_tool_set_xp", amount, "check")
	var ranks = OptionButton.new()
	ranks.rect_min_size = Vector2(360, 56)
	ranks.add_font_override("font", ui.font("display", 28))
	var all = screen.definitions.finite_ranks()
	for n in range(1, 11):
		all.append(screen.definitions.king_rank(n))
	for rank in all:
		ranks.add_item(str(rank.name), int(rank.id))
		if int(rank.id) == int(screen.model.rank.id):
			ranks.select(ranks.get_item_count() - 1)
	for state in ["normal", "hover", "pressed", "focus"]:
		ranks.add_stylebox_override(state, ui.flat(ui.NAVY_DEEP if state != "hover" else ui.NAVY_3, 20, 18, 0, ui.INK, false))
	ranks.add_color_override("font_color", ui.WHITE)
	ranks.get_popup().add_font_override("font", ui.font("display", 28))
	set_row.add_child(ranks)
	ui.button(set_row, "Set rank", "small", self, "_tool_set_rank", ranks, "overview")
	_tool_group(body, "Quests", "quests", "%d completed by test tools" % t.get("done", {}).size(), [
		["Complete daily quests", "test_complete", "daily"], ["Complete weekly challenges", "test_complete", "weekly"],
		["New quests", "test_new_quests", null]])
	_tool_group(body, "Previews", "sparkle", "Plays the effect only", [
		["Rank-up", "test_preview", "rankup"], ["Quest claim", "test_preview", "claim"],
		["Session recap", "test_preview", "recap"], ["Match results", "test_preview", "results"]])
	_tool_group(body, "Journey data", "inbox", "", [["Clear inbox", "test_clear_inbox", null]])
	var admin = ModPaths.try_load(ModPaths.path("JourneyBadgeAdmin.gd"))
	if admin != null:
		admin.add_to(body, screen)
	var foot = ui.box(body, false, 12)
	ui.spacer(foot)
	ui.button(foot, "Reset to normal", "accent", screen, "test_reset", null, "check")

func _tool_group(body, title, icon_key, detail, actions):
	var p = ui.well(body, ui.NAVY_2, 22, 28)
	var col = ui.box(p, true, 14)
	ui.heading(col, title, icon_key, detail)
	var row = _flow(col, 12)
	for a in actions:
		ui.button(row, a[0], "small", screen, a[1], a[2])
	return col

func _tool_set_xp(field):
	var text = str(field.text).replace(",", "").strip_edges()
	if text.is_valid_integer():
		screen.test_set_total(int(text))

func _tool_set_rank(picker):
	screen.test_set_rank(picker.get_selected_id())

func preferences(body):
	var p = screen.prefs
	_pref_switch(body, "Journey sounds", "", "sounds")
	var vol = ui.box(ui.well(body, ui.NAVY_2, 20, 28), false, 24)
	ui.label(vol, "Volume", "h3", ui.WHITE if p.sounds else ui.FAINT)
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = float(p.volume)
	slider.editable = bool(p.sounds)
	slider.rect_min_size = Vector2(360, 48)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui.grow(slider)
	var track = ui.flat(ui.NAVY_DEEP, 10, 0, 0, ui.INK, false)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill = ui.flat(ui.PINK if p.sounds else ui.FAINT, 10, 0, 0, ui.INK, false)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	slider.add_stylebox_override("slider", track)
	slider.add_stylebox_override("grabber_area", fill)
	slider.add_stylebox_override("grabber_area_highlight", fill)
	var knob = _knob(Color.white)
	slider.add_icon_override("grabber", knob)
	slider.add_icon_override("grabber_highlight", _knob(ui.PINK_LIGHT))
	slider.add_icon_override("grabber_disabled", _knob(ui.FAINT))
	slider.connect("value_changed", self, "_pref_value", ["volume"])
	vol.add_child(slider)
	_pref_choice(body, "Celebrations", "", "celebrations", [["all", "Every promotion"], ["leagues", "New leagues only"], ["off", "Off"]])
	_pref_switch(body, "Reduced motion", "", "reduced_motion")
	_pref_choice(body, "Notifications", "", "notify", [["after_match", "After matches"], ["inbox", "Inbox only"]])
	_pref_switch(body, "Auto-claim rewards", "", "auto_claim")
	_pref_switch(body, "Offer a session summary", "", "session_summary")
	var calc = ui.box(ui.well(body, ui.NAVY_2, 20, 28), false, 18)
	var calc_col = ui.grow(ui.box(calc, true, 2))
	ui.label(calc_col, "Calculate XP", "h3")
	ui.label(calc_col, "From your GooberDash wins, games and deaths", "small", ui.MUTED)
	var store = screen.journey_store
	var calculated = store.writable and store.flag("notice:xp_calculated")
	var done = calculated and int(store.backfill.get("version", 1)) >= 3
	ui.button(calc, "Done" if done else ("Recalculate" if calculated else "Calculate"), "small", screen, "open_xp_calculator", null, "check" if done else "xp").disabled = done or _m().preview
	if screen.debug_mode() or screen.design_preview:
		ui.label(body, "DEVELOPER", "caps", ui.PINK_LIGHT)
		var row = ui.box(ui.well(body, ui.NAVY_2, 20, 28), false, 18)
		var col = ui.grow(ui.box(row, true, 2))
		ui.label(col, "Design preview", "h3")
		ui.label(col, "Debug Mode only", "small", ui.MUTED)
		ui.switch(row, screen.design_preview, screen, "_toggle_design_preview_switch")

func _pref_switch(body, title, detail, key):
	var p = ui.well(body, ui.NAVY_2, 20, 28)
	var row = ui.box(p, false, 18)
	var col = ui.grow(ui.box(row, true, 2))
	ui.label(col, title, "h3")
	if detail != "":
		ui.label(col, detail, "small", ui.MUTED)
	ui.switch(row, screen.prefs[key], self, "_pref_toggled", key)

func _pref_choice(body, title, detail, key, options):
	var p = ui.well(body, ui.NAVY_2, 20, 28)
	var col = ui.box(p, true, 12)
	ui.label(col, title, "h3")
	if detail != "":
		ui.label(col, detail, "small", ui.MUTED)
	# Preserve the original pills. Constrain their minimum width inside a
	# horizontal scroll host rather than clipping the rightmost choice.
	var holder = ScrollContainer.new()
	holder.scroll_vertical_enabled = false
	holder.scroll_horizontal_enabled = true
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = 0
	col.add_child(holder)
	holder.set_meta("pref_key", key)
	holder.set_meta("options", options)
	var track = ui.segmented(holder, options, screen.prefs[key], self, "_pref_pick_" + key)
	holder.rect_min_size.y = track.get_combined_minimum_size().y + holder.get_h_scrollbar().get_minimum_size().y

func _pref_pick_celebrations(value):
	screen.set_pref("celebrations", value)
	screen._open_prefs()

func _pref_pick_notify(value):
	screen.set_pref("notify", value)
	screen._open_prefs()

func _pref_toggled(on, key):
	screen.set_pref(key, on)
	screen.play("toggle")

func _pref_value(value, key):
	screen.set_pref(key, value)

func _badge_details(spec):
	var m = _m()
	if m.achievements == null:
		return
	for c in m.achievements.collections:
		if str(c.key) != str(spec.key):
			continue
		var i = int(clamp(int(spec.tier),0,c.thresholds.size()-1))
		var reached = int(c.tier)>i
		var body = screen._overlay(str(c.name)+" · "+_tname(c,i), "achievements")
		var row = ui.box(body,false,20)
		ui.medal(row,min(i,5),c.emblem,150,not reached)
		var info = ui.grow(ui.box(row,true,8))
		ui.label(info,str(c.detail),"body",ui.MUTED)
		ui.label(info,"%s recorded · requires %s" % [ui.thousands(c.value),ui.thousands(c.thresholds[i])],"h3")
		ui.label(info,("Earned "+ui.date_text(c.dates[i],true) if int(c.dates[i])>0 else "Earned · date unavailable") if reached else "Not earned yet","small",ui.GREEN_LIGHT if reached else ui.MUTED)
		ui.label(info,"Tier reward · "+ui.xp_text(c.xp[i]),"body",ui.YELLOW)
		if reached and i < int(c.get("claimed",0)):
			ui.pill(info,"CLAIMED",ui.INK,ui.GREEN_LIGHT,"check")
		elif reached and i == int(c.get("claimed",0)) and bool(c.get("claimable",false)):
			ui.button(info,"Claim tier XP","primary",self,"_claim_badge_tier",c,"check")
		elif reached:
			ui.label(info,"Claim earlier tiers first","small",ui.MUTED)
		_bonus_summary(body,str(c.key))
		return

func _claim_badge_tier(c):
	screen.close_overlay()
	screen.claim_tier(c)

func _playtime_details(_unused = null):
	var body = screen._overlay("Playtime rewards","clock")
	var activity = _m().get("activity")
	ui.label(body,ui.duration(int(activity.get("lifetime_seconds",0)))+" verified" if activity != null else "Not tracked yet","h3")
	_bonus_summary(body,"activity")

func _bonus_summary(parent, group):
	var total = 0
	var earned = 0
	var next = null
	for reward in screen.milestone_rewards():
		if bonus_group(str(reward.key))!=group:
			continue
		if reward.claimable:
			total += int(reward.xp)
		if reward.claimed:
			earned += int(reward.xp)
		if not reward.done and next == null:
			next = reward
	if total==0 and earned==0 and next==null:
		return
	var panel = ui.card(parent)
	var col = ui.box(panel,true,10)
	ui.heading(col,"Bonus XP","xp")
	if earned>0:
		ui.label(col,ui.xp_text(earned)+" claimed","small",ui.GREEN_LIGHT)
	if total>0:
		ui.button(col,"Claim "+ui.xp_text(total),"primary",self,"_claim_group_bonus",group,"check")
	if next!=null:
		ui.label(col,"Next: "+str(next.name)+" · "+ui.xp_text(next.xp),"small",ui.MUTED)

func _claim_group_bonus(group):
	var before = int(screen.ledger.total_xp)
	var rank_before = screen.definitions.rank_at(before)
	var total = 0
	for reward in screen.milestone_rewards():
		if bonus_group(str(reward.key))==group and reward.claimable:
			total += max(0,screen.claim_milestone(str(reward.key),true))
	if total>0:
		screen.close_overlay()
		screen.play("claim")
		screen._claim_fx(null,total)
		screen._after_claim(before,rank_before)

# ================================================================== calculate XP
func xp_calculator(body):
	if xp_backfill == null:
		xp_backfill = load(ModPaths.path("JourneyXPBackfill.gd")).new()
	xp_plan = null
	ui.label(body, "Adds Journey XP for the games you played before Goobplayability. Time trials aren't included.", "small", ui.MUTED)
	var previous = _calculated_xp()
	if previous > 0:
		ui.label(body, "Replaces your earlier calculation (%s)." % ui.xp_text(previous), "small", ui.YELLOW)
	var status = ui.label(body, "Loading your GooberDash stats…", "body", ui.MUTED)
	var state = xp_backfill.fetch(screen.get_node_or_null("/root/Moonlight"), str(screen.ledger.account_id))
	var stats = state
	if state is GDScriptFunctionState:
		stats = yield(state, "completed")
	if not is_instance_valid(body) or not is_instance_valid(status):
		return
	if stats.empty():
		status.text = "Couldn't load your GooberDash stats. Try again later."
		return
	status.queue_free()
	var records = _m().stats.store.records if _m().stats != null and _m().stats.get("store") != null else []
	if map_catalog == null:
		map_catalog = load(ModPaths.path("JourneyMapCatalog.gd")).new()
	map_catalog.maps(null)
	xp_plan = xp_backfill.plan(stats, records, map_catalog.entries)
	var kpis = ui.box(body, false, 18)
	ui.grow(ui.kpi(kpis, ui.thousands(int(stats.GamesPlayed)), "Games", "", ui.WHITE, "flag"))
	ui.grow(ui.kpi(kpis, ui.thousands(int(stats.GamesWon)), "Wins", "", ui.YELLOW, "crown"))
	ui.grow(ui.kpi(kpis, ui.thousands(int(stats.Deaths)), "Deaths", "", ui.MUTED, "close"))
	for line in xp_plan.lines:
		var row = ui.box(ui.well(body, ui.NAVY_2, 18, 28), false, 18)
		var col = ui.grow(ui.box(row, true, 2))
		ui.label(col, str(line.label), "h3")
		ui.label(col, str(line.detail), "small", ui.MUTED)
		ui.pill(row, ui.xp_text(int(line.xp)), ui.INK, ui.YELLOW)
	if int(xp_plan.wins) > 0 or int(xp_plan.maps) > 0:
		ui.label(body, "Crown Collector and Map Explorer count these wins and maps too.", "small", ui.MUTED)
	var foot = ui.box(body, false, 14)
	ui.spacer(foot)
	ui.button(foot, "Cancel", "secondary", screen, "close_overlay")
	var label = ("Set to " if previous > 0 else "Add ") + ui.xp_text(int(xp_plan.total))
	ui.button(foot, label, "primary", self, "_add_calculated_xp", null, "check").disabled = int(xp_plan.total) <= 0 and previous <= 0

func _add_calculated_xp(_arg = null):
	var store = screen.journey_store
	if xp_plan == null or not store.writable:
		return
	if store.flag("notice:xp_calculated") and int(store.backfill.get("version", 1)) >= xp_backfill.VERSION:
		return
	var owner = str(screen.ledger.account_id)
	var before = int(screen.ledger.total_xp)
	var rank_before = screen.definitions.rank_at(before)
	var now = OS.get_unix_time()
	var total = screen.ledger.replace_prefixed("backfill:%s:" % owner, xp_backfill.entries(owner, xp_plan, now))
	if total >= 0:
		total = screen.ledger.award_batch(xp_backfill.map_entries(owner, xp_plan, now))
	if total < 0:
		screen._toast(str(screen.ledger.error) if str(screen.ledger.error) != "" else "Couldn't save the XP.")
		return
	var added = int(screen.ledger.total_xp) - before
	store.backfill = {"wins": int(xp_plan.wins), "maps": int(xp_plan.maps), "map_ids": xp_plan.map_ids, "time": now, "version": xp_backfill.VERSION}
	store.note("notice:xp_calculated")
	for item in store.inbox:
		if item.id in ["calculate_xp", "recalculate_xp"]:
			item.state = "read"
	store.save()
	screen.close_overlay()
	if added > 0:
		screen.play("claim")
		screen._claim_fx(null, added)
		screen._after_claim(before, rank_before)
	else:
		screen.play("toggle")
		screen._toast("Calculated XP updated")
		screen.refresh()

# XP currently in the ledger from Calculate XP.
func _calculated_xp() -> int:
	var prefix = "backfill:%s:" % str(screen.ledger.account_id)
	var total = 0
	for entry in screen.ledger.entries:
		if str(entry.id).begins_with(prefix):
			total += int(entry.amount)
	return total
