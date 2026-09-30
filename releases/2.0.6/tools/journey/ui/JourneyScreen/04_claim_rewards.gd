extends "user://mod/tools/journey/ui/JourneyScreen/03_claim_rank.gd"

# Recomputes the badges. `redraw` updates the tab badges without a re-render.
func update_claims(redraw = true):
	claim_counts = claim_sections()
	if redraw and nav_row != null and nav_row.get_child_count() > 0:
		for item in nav_row.get_child(0).get_children():
			if item.has_meta("badge"):
				item.get_meta("badge").visible = int(claim_counts.get(item.name, 0)) > 0
	emit_signal("claims_changed", claim_total())

func make_badge(size = 34):
	var badge = ClaimBadge.new()
	badge.rect_min_size = Vector2(size, size)
	badge.rect_size = Vector2(size, size)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	return badge

func claimables() -> Array:
	var out = []
	for reward in milestone_rewards():
		if reward.claimable:
			out.append({"id":reward.key,"kind":"milestone","state":"claimable","title":reward.name,"detail":"Achievement bonus","xp":reward.xp,"target":pages.bonus_target(str(reward.key))})
	if model.get("inbox") != null:
		for item in model.inbox:
			if str(item.get("state", "")) != "claimable":
				continue
			# A tier already claimed on another account of this PC isn't claimable.
			if str(item.get("kind", "")) == "achievement":
				var parts = str(item.id).trim_prefix("ach_").rsplit("_", true, 1)
				if parts.size() == 2 and journey_store.claimed_tier(parts[0]) >= int(parts[1]):
					item.state = "claimed"
					continue
			out.append(item)
	return out

func _unread() -> int:
	if model.empty() or model.get("inbox") == null:
		return 0
	var n = 0
	for item in model.inbox:
		if str(item.get("state", "")) in ["unread", "claimable"]:
			n += 1
	return n

func request(kind, data = null):
	# Rerolls and swaps are local (JourneyQuests); only claims need the XP owner.
	if kind in ["reroll", "choose_quest"] and typeof(data) == TYPE_INT and not model.preview and journey_store.writable:
		var ok = quest_rules.reroll(journey_store, data) if kind == "reroll" else quest_rules.choose(journey_store, data, model.quests.daily)
		play("toggle" if ok else "click")
		if not ok:
			_toast("No rerolls left today.")
		refresh()
		return
	play("claim" if kind == "claim" else "click")
	if not get_signal_connection_list("journey_action").empty():
		emit_signal("journey_action", kind, data)
		return
	var what = ACTION_TEXT.get(kind, "This action")
	_toast(("Preview: nothing is saved. " if model.preview else "") + what + " isn't connected yet.")

func claim_all():
	var others = []
	var quest_xp = 0
	var rank_before = model.rank
	var xp_before = int(model.xp)
	for item in claimables():
		if str(item.get("kind", "")) == "milestone":
			continue # Award all milestone bonuses together below.
		elif str(item.get("kind", "")) == "quest":
			if _award_quest(_find_quest(str(item.id).trim_prefix("quest_"), item)):
				quest_xp += int(item.get("xp", 0))
		elif str(item.get("kind", "")) == "achievement" and model.get("achievements") != null:
			for c in model.achievements.collections:
				if c.key == str(item.get("target", {}).get("key", "")):
					var got = claim_tier(c, true)
					while got > 0:
						quest_xp += got
						c.claimed = int(c.get("claimed", 0)) + 1
						got = claim_tier(c, true)
		else:
			others.append(item)
	for reward in streak_rewards():
		quest_xp += claim_streak(reward, null, true)
	quest_xp += claim_playtime(null, true)
	quest_xp += max(0,claim_milestone("",true))
	if quest_xp > 0:
		play("claim")
		_claim_fx(null, quest_xp)
		_after_claim(xp_before, rank_before)
	if others.empty():
		return
	play("claim")
	if not get_signal_connection_list("journey_action").empty():
		emit_signal("journey_action", "claim_all", others)
		return
	_toast("Claiming isn't connected yet." if not model.preview else "Preview: nothing is saved.")

# Challenge claim: Journey awards the XP itself (ledger category "challenge";
# test-mode completions only add test XP), marks it claimed and plays the
# reward moment. journey_action("quest_claimed", {quest, xp}) is informational.
func _milestone_model():
	var current = model.duplicate()
	current.transactions = ledger.entries
	current.activity = activity.snapshot() if is_instance_valid(activity) and activity.account_id==ledger.account_id else null
	return current

func milestone_rewards():
	return load(ModPaths.path("JourneyMilestones.gd")).new().rewards(_milestone_model(),ledger,journey_store,definitions)

func claim_milestone(key = "", silent = false):
	var before = int(ledger.total_xp)
	var rank_before = definitions.rank_at(before)
	var amount = load(ModPaths.path("JourneyMilestones.gd")).new().claim(_milestone_model(),ledger,journey_store,str(key),definitions)
	if amount < 0:
		_toast("Couldn't save milestone XP. Try again.")
	elif amount > 0 and not silent:
		play("claim")
		_claim_fx(null,amount)
		_after_claim(before,rank_before)
	return amount

func claim_quest(quest, source = null):
	var rank_before = model.rank
	var xp_before = int(model.xp)
	if not _award_quest(_find_quest(str(quest.get("id", "")), quest)):
		return
	play("claim")
	_claim_fx(source, int(quest.get("xp", 0)))
	_after_claim(xp_before, rank_before)

func claim_map_rewards(objs, source = null):
	if objs.empty():
		return
	var rank_before = model.rank
	var xp_before = int(model.xp)
	var total = 0
	var batch = []
	for o in objs:
		if model.preview or not journey_store.writable:
			total += int(o.xp)
		elif not journey_store.flag(o.key):
			batch.append({"id": "%s:%s" % [o.key, ledger.account_id], "player_id": str(ledger.account_id),
				"category": MAP_CATEGORY.get(str(o.obj), "exploration"), "reason": "%s: %s" % [str(o.map).strip_edges(), str(o.label)],
				"related_id": str(o.key), "source": "verified_local_activity", "amount": int(o.xp), "timestamp": OS.get_unix_time()})
	if not batch.empty():
		# One ledger write for the whole claim, however many maps.
		var added = ledger.award_batch(batch)
		if added < 0:
			_toast(str(ledger.error) if str(ledger.error) != "" else "Couldn't save the reward.")
			return
		total = added
		for o in objs:
			journey_store.note(str(o.key))
	journey_store.save()
	if total <= 0:
		return
	play("claim")
	_claim_fx(source, total)
	_after_claim(xp_before, rank_before)

func _leaderboard_updated():
	if view == "leaderboard":
		refresh()

func streak_rewards() -> Array:
	var out = []
	var streak = model.get("streak")
	if streak == null:
		return out
	for step in STREAK_REWARDS:
		var key = "streak:%s:%d" % [str(streak.get("start", "")), int(step[0])]
		var done = int(streak.current) >= int(step[0])
		var claimed = done and journey_store.flag(key)
		out.append({"days": int(step[0]), "xp": int(step[1]), "key": key, "done": done, "claimed": claimed,
			"claimable": done and not claimed and not model.preview and journey_store.writable and str(streak.get("start", "")) != ""})
	return out

func claim_streak(reward, source = null, silent = false) -> int:
	if not bool(reward.get("claimable", false)) or journey_store.flag(reward.key):
		return 0
	var rank_before = model.rank
	var xp_before = int(model.xp)
	var ok = ledger.award({"id": "%s:%s" % [reward.key, ledger.account_id], "player_id": str(ledger.account_id), "category": "activity",
		"reason": "%d-day streak" % int(reward.days), "related_id": str(reward.key), "source": "verified_local_activity",
		"amount": int(reward.xp), "timestamp": OS.get_unix_time()})
	if not ok:
		_toast(str(ledger.error) if str(ledger.error) != "" else "Couldn't save the reward.")
		return 0
	journey_store.set_flag(reward.key)
	if not silent:
		play("claim")
		_claim_fx(source, int(reward.xp))
		_after_claim(xp_before, rank_before)
	return int(reward.xp)

# Daily playtime rewards (30m … 4h of verified active time today), each
# claimable once per day. Ledger category "activity", id play:<day>:<seconds>:<account>.
func playtime_rewards() -> Array:
	var out = []
	var activity = model.get("activity")
	# Claims must use today's live verified total, not a page left open overnight
	# or a snapshot belonging to the account that was previously signed in.
	if not model.preview:
		if not is_instance_valid(self.activity) or self.activity.account_id != str(ledger.account_id) or not self.activity.writable:
			return out
		activity = self.activity.snapshot()
	if activity == null or model.get("activity_milestones") == null:
		return out
	var day = session_rules._day_key(OS.get_unix_time())
	for step in model.activity_milestones:
		var key = "play:%s:%d" % [day, int(step.seconds)]
		var done = int(activity.today_seconds) >= int(step.seconds)
		var claimed = journey_store.flag(key)
		out.append({"key": key, "seconds": int(step.seconds), "xp": int(step.xp), "done": done, "claimed": claimed,
			"claimable": done and not claimed and not model.preview and journey_store.writable})
	return out

func claim_playtime(_arg = null, silent = false) -> int:
	var batch = []
	var keys = []
	var total = 0
	for reward in playtime_rewards():
		if reward.claimable:
			batch.append({"id": "%s:%s" % [reward.key, ledger.account_id], "player_id": str(ledger.account_id), "category": "activity",
				"reason": "%s active today" % ui.duration(reward.seconds), "related_id": str(reward.key), "source": "verified_local_activity",
				"amount": int(reward.xp), "timestamp": OS.get_unix_time()})
			keys.append(reward.key)
	if batch.empty():
		return 0
	var rank_before = model.rank
	var xp_before = int(model.xp)
	var added = ledger.award_batch(batch)
	if added < 0:
		_toast(str(ledger.error) if str(ledger.error) != "" else "Couldn't save the reward.")
		return 0
	for key in keys:
		journey_store.note(key)
	journey_store.save()
	if not silent and added > 0:
		play("claim")
		_claim_fx(null, added)
		_after_claim(xp_before, rank_before)
	return added

func claim_certified(level):
	var key = "certified:" + str(level.id)
	if model.preview or not journey_store.writable or journey_store.flag(key) or not bool(level.get("certified", false)):
		return
	var rank_before = model.rank
	var xp_before = int(model.xp)
	var ok = ledger.award({"id": "%s:%s" % [key, ledger.account_id], "player_id": str(ledger.account_id), "category": "challenge",
		"reason": "Certified level: " + str(level.name).substr(0, 60), "related_id": str(level.id), "source": "verified_local_activity",
		"amount": CERTIFIED_XP, "timestamp": OS.get_unix_time()})
	if not ok:
		_toast(str(ledger.error) if str(ledger.error) != "" else "Couldn't save the reward.")
		return
	journey_store.set_flag(key)
	play("claim")
	_claim_fx(null, CERTIFIED_XP)
	_after_claim(xp_before, rank_before)

func _finishes() -> Array:
	var out = []
	for f in FINISHES:
		var rank = definitions.king_rank(int(f.rank_id) - 17)
		var unlocked = _finish_xp() >= int(rank.xp)
		out.append({"key": f.key, "name": f.name, "script": f.script, "text": f.text, "requirement": "Reach " + str(rank.name), "rank_id": int(f.rank_id), "rank_xp": int(rank.xp),
			"rank_name": str(rank.name), "state": ("equipped" if str(prefs.get("finish", "")) == f.key else "unlocked") if unlocked else "locked"})
	return out

# Real XP; the admin's test XP also counts so the finish can be tried out.
func _finish_xp() -> int:
	var xp = int(ledger.total_xp)
	if is_admin() and journey_store.writable:
		xp += int(journey_store.test.get("xp", 0))
	return xp

func equip_finish(finish):
	if model.preview:
		_toast("Preview: nothing is saved.")
		return
	if str(finish.get("state", "")) == "locked":
		_toast(str(finish.requirement) + " to unlock this finish.")
		return
	var on = str(finish.state) != "equipped"
	set_pref("finish", str(finish.key) if on else "")
	play("toggle")
	_toast((str(finish.name) + " equipped") if on else "Finish removed")
	close_overlay()
	refresh()

# Theme rewards: equips an unlocked menu theme through the theme pack.
func equip_theme(theme):
	if model.preview:
		_toast("Preview: nothing is saved.")
		return
	if str(theme.get("state", "")) == "locked":
		_toast(str(theme.requirement) + " to unlock this theme.")
		return
	var result = theme_rules.equip(get_tree(), str(theme.key))
	if result.empty():
		_toast("Themes need Goobplayability's theme pack.")
		return
	play("toggle")
	_toast(str(theme.name) + " theme equipped")
	if result == "enabled" and journey_store.writable and not journey_store.flag("notice:themes_enabled"):
		journey_store.set_flag("notice:themes_enabled")
		journey_store.push({"id": "themes_enabled", "kind": "reward", "state": "unread", "title": "Editor themes turned on",
			"detail": "Equipping a theme switched on Settings → Editor theme pack. Turn it off there to go back to the normal menu.",
			"time": OS.get_unix_time(), "target": {"view": "", "section": "Rewards"}})
	close_overlay()
	refresh()

# Achievement tiers: claims the next unclaimed tier (ledger id
# ach:<account>:<key>:<tier>) and plays the medal celebration.
func claim_tier(c, silent = false) -> int:
	if silent and (model.preview or not journey_store.writable):
		return 0
	var tier = int(journey_store.claimed_tier(c.key)) + 1 if journey_store.writable else int(c.tier)
	if tier > int(c.tier) or tier < 1:
		return 0
	var xp = int(c.xp[min(tier - 1, c.xp.size() - 1)])
	var rank_before = model.rank
	var xp_before = int(model.xp)
	if not model.preview and journey_store.writable:
		var ok = ledger.award({"id": "ach:%s:%s:%d" % [ledger.account_id, c.key, tier], "player_id": str(ledger.account_id),
			"category": "challenge", "reason": "%s · %s" % [str(c.name), _tier_name(c, tier)], "related_id": "%s:%d" % [c.key, tier],
			"source": "verified_local_activity", "amount": xp, "timestamp": OS.get_unix_time()})
		if not ok:
			_toast(str(ledger.error) if str(ledger.error) != "" else "Couldn't save the reward.")
			return 0
		journey_store.mark_claimed(c.key, tier)
	if silent:
		return xp
	xp_anim_from = xp_before
	set_meta("rank_before", int(rank_before.id))
	refresh()
	celebrate_medal(c, tier, xp)
	return xp

func _tier_name(c, tier) -> String:
	var names = c.get("tier_names", [])
	return str(names[tier - 1]) if tier - 1 < names.size() else "Kingly %d" % (tier - 5)

# Medal moment for a claimed achievement tier.
func celebrate_medal(c, tier, xp):
	close_overlay()
	overlay = CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	var root_fx = Control.new()
	root_fx.mouse_filter = Control.MOUSE_FILTER_STOP
	root_fx.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	overlay.add_child(root_fx)
	var shade = ColorRect.new()
	shade.color = Color(0.05, 0.02, 0.14, 0.86)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root_fx.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_fx.add_child(center)
	var col = ui.box(center, true, 14)
	col.alignment = BoxContainer.ALIGN_CENTER
	var kicker = ui.label(col, str(c.name).to_upper(), "title", ui.YELLOW, Label.ALIGN_CENTER)
	kicker.add_font_override("font", ui.font("title", 56, 6))
	var stage = Control.new()
	stage.rect_min_size = Vector2(560, 560)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	var glow = ui.image(stage, "fx_glow", 560, Color(1, 0.85, 0.35, 0.8))
	glow.rect_pivot_offset = Vector2(280, 280)
	var rays = ui.image(stage, "fx_rays", 560, Color(1, 0.9, 0.5, 0.5))
	rays.rect_pivot_offset = Vector2(280, 280)
	var ring = ui.ring(stage, ui.YELLOW)
	var medal = ui.medal(stage, int(clamp(tier - 1, 0, 5)), c.emblem, 520)
	medal.rect_position = Vector2(20, 20)
	medal.rect_pivot_offset = Vector2(260, 260)
	var tier_label = ui.label(col, _tier_name(c, tier).to_upper() + " TIER", "title", ui.WHITE, Label.ALIGN_CENTER)
	tier_label.add_font_override("font", ui.font("title", 88, 8))
	var tag = ui.box(col, false, 12)
	tag.alignment = BoxContainer.ALIGN_CENTER
	ui.icon(tag, "xp", 56, ui.YELLOW)
	var amount = ui.label(tag, "+" + ui.thousands(xp) + " XP", "num_l", ui.YELLOW)
	amount.add_font_override("font", ui.font("display", 60, 6))
	var go = ui.button(col, "Continue", "primary", self, "_medal_done")
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.grab_focus()
	play("rankup")
	if ui.reduced_motion or str(prefs.celebrations) == "off":
		return
	var t = _tween()
	t.interpolate_property(root_fx, "modulate", Color(1, 1, 1, 0), Color.white, 0.18)
	medal.rect_scale = Vector2(0.2, 0.2)
	medal.rect_rotation = -25
	t.interpolate_property(medal, "rect_scale", Vector2(0.2, 0.2), Vector2(1.1, 1.1), 0.35, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.15)
	t.interpolate_property(medal, "rect_rotation", -25.0, 0.0, 0.6, Tween.TRANS_ELASTIC, Tween.EASE_OUT, 0.15)
	t.interpolate_property(medal, "rect_scale", Vector2(1.1, 1.1), Vector2.ONE, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT, 0.5)
	t.interpolate_property(ring, "progress", 0.0, 1.0, 0.7, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.45)
	t.interpolate_property(glow, "modulate:a", 0.0, 1.0, 0.4, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.4)
	t.interpolate_property(rays, "modulate:a", 0.0, 1.0, 0.6, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.4)
	t.interpolate_callback(self, 0.45, "_celebrate_burst", stage, tier >= 5)
	t.interpolate_callback(self, 0.45, "play", "claim", 1.1)
	tier_label.modulate.a = 0.0
	t.interpolate_property(tier_label, "modulate:a", 0.0, 1.0, 0.25, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.7)
	tag.modulate.a = 0.0
	tag.rect_pivot_offset = Vector2(tag.get_combined_minimum_size().x * 0.5, 30)
	t.interpolate_property(tag, "modulate:a", 0.0, 1.0, 0.2, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.95)
	t.interpolate_property(tag, "rect_scale", Vector2(0.5, 0.5), Vector2.ONE, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT, 0.95)
	go.modulate.a = 0.0
	t.interpolate_property(go, "modulate:a", 0.0, 1.0, 0.25, Tween.TRANS_LINEAR, Tween.EASE_IN, 1.3)
	t.start()
	var loop = Tween.new()
	root_fx.add_child(loop)
	loop.repeat = true
	loop.interpolate_property(rays, "rect_rotation", 0.0, 360.0, 16.0)
	loop.start()

func _medal_done():
	close_overlay()
	_check_rank_up()

func _find_quest(id, fallback) -> Dictionary:
	if model.get("quests") != null:
		for q in model.quests.daily + model.quests.weekly:
			if str(q.id) == id:
				return q
	return {"id": id, "xp": int(fallback.get("xp", 0)), "title": str(fallback.get("detail", "Challenge")), "test": false}
