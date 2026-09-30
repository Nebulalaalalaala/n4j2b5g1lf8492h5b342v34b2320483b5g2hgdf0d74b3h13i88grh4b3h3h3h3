extends "user://mod/tools/journey/ui/JourneyPages/02_quest_pin.gd"

# ================================================================== maps
# Known public-map catalog plus personal history; presence is not progress.
# Objectives reflect personal recorded results only and award no XP.
func _map_items() -> Array:
	var m = _m()
	var out = []
	if map_catalog == null:
		map_catalog = load(ModPaths.path("JourneyMapCatalog.gd")).new()
	# Maps with a finished time trial (the "time trial record" objective).
	var trial_best = {}
	if m.stats != null and m.stats.get("store") != null:
		for r in m.stats.get("records", m.stats.store.records):
			if str(r.mode) == "time_trial" and str(r.result) == "finish" and float(r.finish_time) > 0:
				var id = str(r.map_id)
				trial_best[id] = min(float(trial_best.get(id, 1e12)), float(r.finish_time))
	var store = screen.journey_store
	for map in map_catalog.maps(m.stats):
		var map_id = str(map.key).split(":", true, 1)[-1]
		# Knockout maps have no placements or time trials: only Explore and Win.
		var knockout = str(map.mode) == "Knockout"
		var trial = str(map.key).begins_with("time_trial:")
		var obj = []
		var calculated = screen.ledger.ids.has("map:%s:discover:%s" % [map_id, str(screen.ledger.account_id)])
		obj.append({"key": "discover", "label": "Discovered", "icon": "compass", "done": int(map.plays) > 0 or calculated, "detail": "Recorded %d time%s" % [int(map.plays), "" if int(map.plays) == 1 else "s"], "xp": MAP_XP.discover})
		if knockout:
			obj.append({"key": "win", "label": "Last survivor", "icon": "crown", "done": int(map.wins) > 0, "detail": "%d recorded win%s" % [int(map.wins), "" if int(map.wins) == 1 else "s"], "xp": MAP_XP.first})
		else:
			obj.append({"key": "finish", "label": "Qualified" if not trial else "Finished", "icon": "flag", "done": int(map.completions) > 0, "detail": "%d recorded finish%s" % [int(map.completions), "" if int(map.completions) == 1 else "es"], "xp": MAP_XP.finish})
			obj.append({"key": "first", "label": "Finished first", "icon": "crown", "done": int(map.get("best_placement", 0)) == 1, "detail": "Best recorded placement: %s" % (str(map.best_placement) if int(map.get("best_placement", 0)) > 0 else "unknown"), "xp": MAP_XP.first})
			var tt = float(trial_best.get(map_id, -1.0))
			obj.append({"key": "pb", "label": "Time trial record", "icon": "stopwatch", "done": tt > 0, "detail": ("Best time trial: %.3fs" % tt) if tt > 0 else "Finish a time trial on this map", "xp": MAP_XP.pb})
			var verified_wr = screen.ledger.ids.has("wr:"+map_id+":"+str(screen.ledger.account_id))
			obj.append({"key": "wr", "label": "World record", "icon": "star", "done": verified_wr, "detail": "Verified world record awarded" if verified_wr else "Awaiting a verified world record on a certified map", "xp": int(m.rewards_table.get("first_world_record", 0)), "unsupported": not verified_wr})
		var supported = 0
		var done = 0
		var claim_xp = 0
		for o in obj:
			o.claim_key = "map:%s:%s" % [map_id, o.key]
			if o.key=="wr":
				o.claim_key = "wr:"+map_id
			o.claimed = (store != null and store.flag(o.claim_key)) or screen.ledger.ids.has(str(o.claim_key)+":"+str(screen.ledger.account_id))
			o.claimable = o.done and not o.claimed and not o.get("unsupported", false) and int(o.xp) > 0 and not m.preview
			claim_xp += int(o.xp) if o.claimable else 0
			if not o.get("unsupported", false):
				supported += 1
				done += int(o.done)
		out.append({"key": map.key, "id": map_id, "name": map.name, "mode": map.mode, "map": map, "objectives": obj,
			"done": done, "supported": supported, "last": int(map.last_played), "claim_xp": claim_xp})
	return out

func maps(parent):
	# A previously selected internal filter must not leave the visible tab empty.
	if map_filter == "no_thumb":
		map_filter = "all"
	var m = _m()
	var items = _map_items()
	var head = screen.section_intro(parent, "Your GooberDash Map Collection")
	var summary = ui.card(parent)
	var srow = ui.box(summary, not screen.wide(), 32)
	var total_done = 0
	var total_supported = 0
	var complete = 0
	var firsts = 0
	var finished = 0
	for item in items:
		total_done += item.done
		total_supported += item.supported
		complete += int(item.done == item.supported)
		for o in item.objectives:
			if o.key in ["first", "win"] and o.done:
				firsts += 1
			if o.key in ["finish", "survive"] and o.done:
				finished += 1
	var ring_box = ui.box(srow, false, 28)
	var holder = Control.new()
	holder.rect_min_size = Vector2(190, 190)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_box.add_child(holder)
	var ratio = float(total_done) / max(1, total_supported)
	ui.ring_progress(holder, ratio, 190, ui.GREEN, 20).set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var pct = ui.label(holder, "%d%%" % int(round(ratio * 100)), "num_l", ui.WHITE, Label.ALIGN_CENTER)
	pct.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var intro = ui.box(ring_box, true, 6)
	intro.alignment = BoxContainer.ALIGN_CENTER
	ui.label(intro, "COLLECTION PROGRESS", "caps", ui.MUTED)
	var catalog_text = "in the known map catalog"
	ui.label(intro, "%d maps %s" % [items.size(), catalog_text], "h2")
	var kpis = ui.grow(ui.box(srow, false, 18))
	ui.kpi(kpis, str(finished), "Finished", "Qualified or survived", ui.WHITE, "flag")
	ui.kpi(kpis, str(firsts), "First place", "Recorded wins", ui.YELLOW, "crown")
	ui.kpi(kpis, str(complete), "Complete", "All supported objectives", ui.GREEN_LIGHT, "check")
	var ready = 0
	var ready_count = 0
	for item in items:
		ready += int(item.claim_xp)
		for o in item.objectives:
			ready_count += int(o.claimable)
	if ready > 0:
		var banner = ui.card(parent, ui.NAVY, 20, 36)
		var brow = ui.box(banner, false, 18)
		ui.tile_icon(brow, "maps", ui.YELLOW, 72)
		var bcol = ui.grow(ui.box(brow, true, 0))
		bcol.alignment = BoxContainer.ALIGN_CENTER
		ui.label(bcol, "%d map reward%s ready" % [ready_count, "" if ready_count == 1 else "s"], "h3")
		ui.label(bcol, ui.xp_text(ready) + " from discovering, qualifying, first places and time trials", "small", ui.YELLOW)
		ui.button(brow, "Claim all", "primary", self, "_claim_all_maps", null, "check")
	var controls = ui.box(parent, not screen.wide(), 18)
	var search = ui.search_field(controls, "Search maps", map_query, self, "_map_search")
	ui.grow(search, true, false, 0.6)
	_chip_row(controls, [["all", "All"], ["unplayed", "Never played"], ["almost", "Almost complete"], ["no_first", "Missing first place"], ["no_finish", "Not finished"], ["complete", "Complete"]], map_filter, "_map_filter")
	var sorts = ui.box(parent, false, 16)
	ui.label(sorts, "SORT", "caps", ui.WHITE)
	ui.segmented(sorts, [["name", "Name"], ["completion", "Completion"], ["recent", "Recently played"], ["remaining", "Remaining"]], map_sort, self, "_map_sort")
	map_grid = _columns(parent, 4, 2, 24)
	_fill_maps(items)

func _fill_maps(items = null):
	if map_grid == null or not is_instance_valid(map_grid):
		return
	if items == null:
		items = _map_items()
	for child in map_grid.get_children():
		map_grid.remove_child(child)
		child.queue_free()
	var shown = []
	for item in items:
		if not map_catalog.search_matches(item.map, map_query):
			continue
		var first_done = false
		var finish_done = false
		for o in item.objectives:
			if o.key in ["first", "win"]:
				first_done = o.done
			if o.key in ["finish", "survive"]:
				finish_done = o.done
		match map_filter:
			"almost":
				if item.supported - item.done != 1:
					continue
			"no_first":
				if first_done:
					continue
			"no_finish":
				if finish_done:
					continue
			"complete":
				if item.done != item.supported:
					continue
			"unplayed":
				if int(item.map.get("plays", 0)) > 0:
					continue
			"no_thumb":
				if ui.art.texture(_map_key(item.name)) != null:
					continue
		shown.append(item)
	shown.sort_custom(self, "_map_order")
	if shown.empty():
		var none = ui.well(map_grid, ui.NAVY, 30, 32)
		ui.label(none, "No maps match this search or filter.", "body", ui.MUTED)
		return
	var t = null
	if not ui.reduced_motion:
		t = Tween.new()
		map_grid.add_child(t)
	var i = 0
	for item in shown:
		var card = _map_card(map_grid, item)
		if i < 24:
			ui.pop_in(t, card, 0.03 * i, 0.3, 0.9)
		i += 1
	if t != null:
		t.start()

func _map_order(a, b) -> bool:
	match map_sort:
		"completion":
			return float(a.done) / max(1, a.supported) > float(b.done) / max(1, b.supported)
		"recent":
			return a.last > b.last
		"remaining":
			return a.supported - a.done < b.supported - b.done
	return str(a.name).to_lower() < str(b.name).to_lower()

func _map_search(text):
	map_query = text
	_fill_maps()

func _map_filter(key):
	map_filter = key
	screen.refresh()

func _map_sort(key):
	map_sort = key
	screen.refresh()

func thumbnail(parent, name, height = 200, radius = 28, caption = "", top_only = false, big = false):
	if _thumb_shader == null:
		_thumb_shader = Shader.new()
		_thumb_shader.code = THUMB_SHADER
	var holder = Control.new()
	holder.rect_min_size = Vector2(0, height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.grow(holder)
	parent.add_child(holder)
	var mat = ShaderMaterial.new()
	mat.shader = _thumb_shader
	mat.set_shader_param("radius", float(radius))
	mat.set_shader_param("top_only", top_only)
	var shot = ui.art.texture(_map_key(name))
	if shot != null:
		mat.set_shader_param("shot", shot)
		mat.set_shader_param("has_shot", true)
		mat.set_shader_param("shot_size", shot.get_size())
	else:
		mat.set_shader_param("tint", Color(MAP_TINTS[int(abs(hash(str(name)))) % MAP_TINTS.size()]))
		mat.set_shader_param("shade", 0.55)
	var pic = ColorRect.new()
	pic.material = mat
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	holder.add_child(pic)
	pic.connect("resized", self, "_thumb_resized", [pic])
	if shot == null:
		var hill = ui.image(holder, "icon_maps", Vector2(height * 1.6, height * 1.6), Color(1, 1, 1, 0.1))
		hill.anchor_left = 1
		hill.anchor_right = 1
		hill.margin_left = -height * 1.3
		hill.margin_right = height * 0.3
		hill.margin_top = -height * 0.2
		hill.margin_bottom = height * 1.4
		holder.rect_clip_content = true
	var text = VBoxContainer.new()
	text.add_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.anchor_top = 1
	text.anchor_bottom = 1
	text.anchor_right = 1
	var edge = 40 if big else 26
	text.margin_left = edge
	text.margin_right = -edge
	text.margin_bottom = -(edge - 6)
	text.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(text)
	var title = ui.label(text, str(name).strip_edges(), "h1" if big else "h2", ui.WHITE)
	title.clip_text = true
	title.autowrap = false
	title.add_color_override("font_color_shadow", Color(0, 0.05, 0.15, 0.6))
	title.add_constant_override("shadow_offset_x", 0)
	title.add_constant_override("shadow_offset_y", 4)
	if not str(caption).empty():
		var sub = ui.label(text, str(caption).to_upper(), "caps", Color(1, 1, 1, 0.75))
		sub.autowrap = false
	return holder

func _thumb_resized(pic):
	pic.material.set_shader_param("box", pic.rect_size)

func _mode_text(mode) -> String:
	return str(mode)

func _map_key(name) -> String:
	return map_key(name)

func _map_card(parent, item):
	var card = ui.card(parent, ui.NAVY, 0, 36)
	ui.grow(card)
	ui.clickable(card, screen, "open_item", {"view": "map", "key": item.key})
	var outer = ui.box(card, true, 0)
	thumbnail(outer, item.name, 300, 36, _mode_text(item.mode), true)
	var body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		body.add_constant_override("margin_" + side, 22)
	outer.add_child(body)
	var col = ui.box(body, true, 14)
	var row = ui.box(col, false, 8)
	for o in item.objectives:
		var dot = PanelContainer.new()
		var color = ui.GREEN if o.done else (Color(1, 1, 1, 0.05) if o.get("unsupported", false) else ui.NAVY_2)
		dot.add_stylebox_override("panel", ui.flat(color, 24, 0, 0, ui.INK, false))
		dot.rect_min_size = Vector2(48, 48)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.hint_tooltip = o.label
		row.add_child(dot)
		var c = CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_child(c)
		ui.icon(c, o.icon, 26, ui.INK if o.done else (ui.FAINT if not o.get("unsupported", false) else Color(1, 1, 1, 0.2)))
	ui.spacer(row)
	ui.label(row, "%d/%d" % [item.done, item.supported], "button", ui.GREEN_LIGHT if item.done == item.supported else ui.MUTED)
	_pin_toggle(row, "map", item.id)
	ui.bar(col, float(item.done) / max(1, item.supported), ui.GREEN, 14)
	if int(item.claim_xp) > 0:
		var claim = ui.button(col, "Claim " + ui.xp_text(item.claim_xp), "primary", self, "_claim_map", {"item": item, "row": card}, "check")
		claim.clip_text = true
	return card

func _claim_map_obj(arg):
	var o = arg.o
	screen.claim_map_rewards([{"key": o.claim_key, "xp": int(o.xp), "label": str(o.label), "map": str(arg.item.name), "obj": o.key}], arg.row)

func _claim_map(arg):
	var objs = []
	for o in arg.item.objectives:
		if o.claimable:
			objs.append({"key": o.claim_key, "xp": int(o.xp), "label": str(o.label), "map": str(arg.item.name), "obj": o.key})
	screen.claim_map_rewards(objs, arg.row)

func _claim_all_maps(_arg = null):
	var objs = []
	for item in _map_items():
		for o in item.objectives:
			if o.claimable:
				objs.append({"key": o.claim_key, "xp": int(o.xp), "label": str(o.label), "map": str(item.name), "obj": o.key})
	screen.claim_map_rewards(objs, null)

func _full_map_image(map_name):
	var shot = ui.art.texture(_map_key(map_name))
	if shot==null:
		return
	var body = screen._overlay(str(map_name), "maps")
	var image = TextureRect.new()
	image.texture = shot
	image.expand = true
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.rect_min_size = Vector2(0, min(620, max(200, screen.rect_size.y-280)))
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(image)

func map_detail(parent, arg):
	var key = str(arg.get("key", "")) if arg is Dictionary else str(arg)
	var item = null
	for candidate in _map_items():
		if candidate.key == key:
			item = candidate
	if item == null:
		screen.back_row(parent, "Map unavailable")
		screen.empty_state(ui.card(parent), "maps", "This map isn't in your recorded history", "")
		return
	screen.back_row(parent, str(item.name).strip_edges(), _mode_text(item.mode))
	var layout = ui.box(parent, not screen.wide(), 28)
	var left = ui.box(layout, true, 24)
	ui.grow(left, true, false, 1.2)
	var hero = ui.card(left, ui.NAVY, 0, 44)
	var outer = ui.box(hero, true, 0)
	var preview = thumbnail(outer, item.name, 520, 44, _mode_text(item.mode), true, true)
	if ui.art.texture(_map_key(item.name))!=null:
		ui.clickable(preview, self, "_full_map_image", item.name)
		preview.hint_tooltip = "View full image"
	var hpad = MarginContainer.new()
	hpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		hpad.add_constant_override("margin_" + side, 30)
	outer.add_child(hpad)
	var hcol = ui.box(hpad, true, 18)
	var progress = ui.box(hcol, false, 20)
	ui.label(progress, "%d of %d objectives" % [item.done, item.supported], "h2")
	ui.spacer(progress)
	_pin_button(progress, "map", str(item.key).split(":", true, 1)[-1], "Pin map")
	ui.bar(hcol, float(item.done) / max(1, item.supported), ui.GREEN, 24)
	var records = ui.card(left)
	var rcol = ui.box(records, true, 18)
	var rh = ui.heading(rcol, "Your records", "stopwatch")
	ui.spacer(rh)
	_observed_tag(rh)
	var grid = _columns(rcol, 3, 2, 18)
	var map = item.map
	var known = int(map.completions) + int(map.dnfs)
	ui.kpi(grid, ("%.3fs" % float(map.best)) if float(map.best) >= 0 else "—", "Best time", "Unverified local PB")
	ui.kpi(grid, str(map.best_placement) if int(map.get("best_placement", 0)) > 0 else "—", "Best placement")
	ui.kpi(grid, str(map.wins), "Wins", "", ui.YELLOW)
	ui.kpi(grid, str(map.completions), "Finishes")
	ui.kpi(grid, ("%d%%" % int(100.0 * int(map.completions) / known)) if known > 0 else "—", "Finish rate", "Known outcomes")
	ui.kpi(grid, ui.date_text(map.last_played), "Last played")
	var right = ui.card(layout)
	ui.grow(right, true, false, 1.0)
	var ocol = ui.box(right, true, 16)
	ui.heading(ocol, "Objectives", "flag")
	for o in item.objectives:
		var p = ui.well(ocol, ui.NAVY_2 if not o.get("unsupported", false) else Color(1, 1, 1, 0.03), 20, 28)
		var row = ui.box(p, false, 18)
		var dot = PanelContainer.new()
		dot.add_stylebox_override("panel", ui.flat(ui.GREEN if o.done else ui.NAVY_DEEP, 32, 0, 0, ui.INK, false))
		dot.rect_min_size = Vector2(64, 64)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var c = CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_child(c)
		ui.icon(c, "check" if o.done else o.icon, 32, ui.INK if o.done else ui.MUTED)
		var col = ui.grow(ui.box(row, true, 2))
		ui.label(col, o.label, "h3", ui.WHITE if not o.get("unsupported", false) else ui.FAINT)
		ui.label(col, o.detail, "small", ui.MUTED)
		if o.get("unsupported", false):
			ui.pill(row, "NOT COUNTED", ui.MUTED, Color(1, 1, 1, 0.06))
		elif o.get("claimable", false):
			ui.button(row, "Claim " + ui.xp_text(o.xp), "primary", self, "_claim_map_obj", {"item": item, "o": o, "row": p}, "check")
		elif o.get("claimed", false):
			ui.pill(row, "CLAIMED", ui.INK, ui.GREEN_LIGHT, "check")
		elif int(o.xp) > 0:
			ui.pill(row, ui.xp_text(o.xp), ui.INK, ui.YELLOW)
	if not item.map.get("pb_steps", []).empty():
		var steps = ui.card(parent)
		var scol = ui.box(steps, true, 14)
		ui.heading(scol, "Personal best progression", "stopwatch")
		var times = []
		var labels = []
		for step in item.map.pb_steps:
			times.append(float(step.time))
			var parts = ui.date_text(step.date).split(" ")
			labels.append(parts[0] + " " + parts[1] if parts.size() >= 2 else "")
		if times.size() > 1:
			ui.pb_chart(scol, times, labels)
		for step in item.map.pb_steps:
			var row = ui.box(scol, false, 16)
			ui.label(row, ui.date_text(step.date), "small", ui.MUTED)
			ui.spacer(row)
			ui.label(row, "%.3fs" % float(step.time), "button")
			ui.label(row, "First recorded finish" if step.baseline else "−%.3fs" % float(step.improvement), "small", ui.GREEN_LIGHT if not step.baseline else ui.MUTED)
