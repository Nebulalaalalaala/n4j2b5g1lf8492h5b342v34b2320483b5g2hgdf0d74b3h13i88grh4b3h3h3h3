extends CanvasLayer

# Sections: the big menu for improving a recorded run piece by piece.
#  - The run is split into sections automatically (about three seconds each,
#    cut where the Goober is on the ground).
#  - Practise a section: the menu hides, a bar at the top shows tries and
#    times, a start flag and a stop block appear in the level. Reaching the
#    stop block saves the try and puts you back at the start.
#  - Finish builds the fastest try into the run and re-plays the rest of the
#    run to check it still works. Nothing after the section is removed.

const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")

var studio = null
var tool = null
var panel            # the big menu
var info_panel       # frame info (separate small panel)
var info_label
var bar              # top bar while practising
var bar_labels = {}
var bar_buttons = {}
var bar_layout
var bar_fields
var bar_controls
var title_label
var run_label
var stat_labels = {}
var stat_captions = {}
var route_map
var card_grid
var practise_button
var selected_label
var status_label
var route_button
var undo_button
var remake_button
var markers = null
var selected = 0
var selected_id = 0
var remake_armed = false
var waiting_finish = false
var mode_button
var restore_restart_button
var save_button
var play_button
var section_scroll
var selection_scroll_pending = false
var refresh_timer = 0.0
var card_signature = ""
var target_picker
var bar_target_picker
var overview_button
var overview_visible = false
var section_actions
var empty_label
var reconcile_pending = false


func setup(owner) -> void:
	studio = owner
	tool = studio.tool
	layer = 110
	_build_menu()
	_build_bar()
	_build_info()
	# Live in the same layer as the tool's own panels (the one showing
	# STOPPED), so the menu shows wherever the tool's interface shows.
	var host = tool.get("_overlay_layer")
	if host != null and is_instance_valid(host):
		for node in [panel, bar, info_panel]:
			remove_child(node)
			host.add_child(node)
	panel.visible = false
	bar.visible = false
	visible = false
	studio.connect("changed", self, "_on_changed")
	if studio.bots != null:
		studio.bots.connect("progress", self, "_on_changed")
	set_process(true)


var _fonts = {}

func _font(size: int):
	if not _fonts.has(size):
		_fonts[size] = tool._make_font(size)
	return _fonts[size]


func _label(text: String, size: int, colour = null) -> Label:
	var label = Label.new()
	label.text = text
	label.add_color_override("font_color", Galaxy.color("ink") if colour==null else colour)
	label.add_font_override("font", _font(size))
	return label


func _button(text: String, colour: Color, method: String, args := [], width := 0) -> Button:
	var button = tool._make_button(text, colour, width)
	button.add_font_override("font", _font(18))
	button.rect_min_size.y = 40
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal","hover","pressed"]:
		button.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent")) if method in ["_on_practise","_on_finish"] else Galaxy.box(Galaxy.color("raised").lightened(0.04) if state=="hover" else Galaxy.color("raised"),Galaxy.color("border")))
		button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink") if method in ["_on_practise","_on_finish"] else Galaxy.color("ink"))
	button.connect("pressed", self, method, args)
	return button


# ---------------------------------------------------------------- menu

func _build_menu() -> void:
	panel = Control.new()
	panel.add_to_group("goobplayability_ui")
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.28)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	panel.add_child(dim)
	var frame = PanelContainer.new()
	frame.add_stylebox_override("panel", Galaxy.box(Galaxy.color("bg"),Galaxy.color("border"),24,16))
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.margin_left = 16
	frame.margin_top = 16
	frame.margin_right = -16
	frame.margin_bottom = -16
	panel.add_child(frame)
	var root = VBoxContainer.new()
	root.add_constant_override("separation", 10)
	frame.add_child(root)

	var header = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	root.add_child(header)
	var actions = GridContainer.new()
	actions.columns = 5
	actions.add_constant_override("hseparation", 10)
	actions.add_constant_override("vseparation", 8)
	section_actions = actions
	root.add_child(actions)
	var titles = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	title_label = _label("Sections", 30)
	titles.add_child(title_label)
	run_label = _label("", 16, Galaxy.color("muted"))
	run_label.clip_text = true
	titles.add_child(run_label)
	route_button = _button("Show route in level", GoobStyle.SKY.darkened(0.4), "_on_route")
	actions.add_child(route_button)
	mode_button = _button("Start recording", Galaxy.color("accent").darkened(0.35), "_on_mode")
	mode_button.hint_tooltip = "Start at the countdown with these boxes. The previous run and takes are backed up before restarting."
	for state in ["normal","hover","pressed"]:
		mode_button.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent")))
		mode_button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink"))
	actions.add_child(mode_button)
	var from_board = _button("From leaderboard", Galaxy.color("accent").darkened(0.35), "_on_leaderboard_boxes")
	from_board.icon = Galaxy.icon("trophy",Galaxy.color("accent_ink"),18)
	for state in ["normal","hover","pressed"]:
		from_board.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent")))
		from_board.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink"))
	from_board.hint_tooltip = "Choose any leaderboard run, then preview editable boxes along its route"
	actions.add_child(from_board)
	var boxes = _button("Preview boxes", GoobStyle.SKY.darkened(0.4), "_on_edit_boxes")
	boxes.hint_tooltip = "Draw, move and reorder goals in the level using freecam"
	actions.add_child(boxes)
	overview_button = _button("Overview", GoobStyle.EDGE, "_on_overview")
	overview_button.hint_tooltip = "Show the route summary above the section cards"
	actions.add_child(overview_button)
	save_button = _button("Save run", Galaxy.color("success").darkened(0.4), "_on_save")
	save_button.hint_tooltip = "Save the run so far, with its sections and tries, to a Macro Slot"
	play_button = _button("▶ Play run", GoobStyle.SKY.darkened(0.4), "_on_play_run")
	play_button.hint_tooltip = "Watch the recorded run so far, from the beginning"
	header.add_child(play_button)
	header.add_child(save_button)
	undo_button = _button("Undo last finish", GoobStyle.EDGE, "_on_undo")
	actions.add_child(undo_button)
	restore_restart_button = _button("Restore before restart",GoobStyle.EDGE,"_on_restore_restart")
	restore_restart_button.hint_tooltip = "Restore the run and takes backed up before the last fresh start or box change."
	actions.add_child(restore_restart_button)
	header.add_child(_button("Close", GoobStyle.RED.darkened(0.45), "close"))

	var stats = HBoxContainer.new()
	stats.add_constant_override("separation", 12)
	root.add_child(stats)
	for entry in [["run", "Run time", Galaxy.color("ink")], ["saved", "Time saved", Galaxy.color("success")], ["improved", "Sections improved", Galaxy.color("warning")], ["tries", "Tries", Galaxy.color("accent")]]:
		var tile = PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_stylebox_override("panel", Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),14,12))
		stats.add_child(tile)
		var box = VBoxContainer.new()
		tile.add_child(box)
		var value = _label("-", 28, entry[2])
		box.add_child(value)
		var caption = _label(entry[1], 15, Galaxy.color("muted"))
		box.add_child(caption)
		stat_labels[entry[0]] = value
		stat_captions[entry[0]] = caption

	route_map = RouteMap.new()
	route_map.window = self
	route_map.rect_min_size = Vector2(0, 100)
	route_map.visible = overview_visible
	root.add_child(route_map)

	empty_label = _label("Start recording to use automatic boxes. Preview boxes or choose a leaderboard route to customise them first.",20,Galaxy.color("muted"))
	empty_label.autowrap = true
	root.add_child(empty_label)
	var scroll = ScrollContainer.new()
	section_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	root.add_child(scroll)
	card_grid = GridContainer.new()
	card_grid.columns = 6
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_constant_override("hseparation", 12)
	card_grid.add_constant_override("vseparation", 12)
	scroll.add_child(card_grid)
	panel.connect("resized", self, "_fit_columns")

	var footer = HBoxContainer.new()
	footer.add_constant_override("separation", 14)
	root.add_child(footer)
	selected_label = _label("", 20)
	footer.add_child(selected_label)
	status_label = _label("", 16, Galaxy.color("muted"))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# No autowrap: a wrapping label inside an HBox can make the layout
	# re-sort itself endlessly, which floods Godot's message queue.
	status_label.clip_text = true
	footer.add_child(status_label)
	remake_button = _button("Use working run", GoobStyle.EDGE, "_on_remake")
	footer.add_child(remake_button)
	target_picker = _make_target_picker()
	footer.add_child(target_picker)
	practise_button = _button("Practise", Galaxy.color("success").darkened(0.35), "_on_practise", [], 200)
	practise_button.hint_tooltip = "Repeat this section, then keep your fastest successful take"
	footer.add_child(practise_button)
	# Keep the primary action beside the selected section, above a long grid.
	root.move_child(footer, 2)


func _fit_columns() -> void:
	card_grid.columns = int(clamp(floor((panel.rect_size.x - 100) / 280.0),1,6))
	if section_actions!=null: section_actions.columns = int(clamp(floor((panel.rect_size.x-80)/220.0),1,5))
	if route_map != null:
		route_map.visible = overview_visible


func _on_overview() -> void:
	overview_visible = not overview_visible
	route_map.visible = overview_visible


var open_pending = false

func open() -> void:
	if tool._debug_mode_enabled: print("[Sections] open: ",studio.ready_for_studio())
	var game = tool._find_game()
	if game!=null and tool._practice_restart_from_game_id==game.get_instance_id():
		# Native retry waits on a scaled fade before replacing the scene.
		# Queue the menu until then; pausing here would freeze that fade.
		studio.cancel_practice_request()
		studio.segment_pending_start = false
		tool._practice_start_waiting = false
		tool._is_paused = false
		Engine.time_scale = 1.0
		open_pending = true
		bar_labels.section.text = "Restarting the level…"
		return
	if not studio.job.empty() or studio.bots.busy() or _waiting_for_box_preview():
		open_pending = true # opens as soon as the running job is done
		return
	open_pending = false
	waiting_finish = false
	# Practice deliberately loops forever; waiting for busy() made this menu
	# unreachable. Explicitly opening Sections leaves that live attempt.
	var cancel_start = studio.segment_pending_start or studio.pending_practice_id!=0
	studio.cancel_practice_request()
	studio.segment_pending_start = false
	if cancel_start and tool._practice_start_waiting:
		tool._practice_start_waiting = false
		tool._stop_practice_mode()
	studio._leave_timeline_preview()
	studio.stop_practice()
	if tool._tas_gui_enabled and tool._overlay_hidden:
		tool._toggle_overlay_hidden()
	visible = true
	panel.visible = true
	panel.raise()
	bar.visible = false
	_show_markers(-1)
	_fit_columns()
	_refresh()
	# Let the menu draw first; pause and build sections a moment later.
	opening = 3

func _waiting_for_box_preview() -> bool:
	return is_instance_valid(studio.zone_editor) or (is_instance_valid(studio.replay_boxes) and studio.replay_boxes.pending)


var opening = 0

func _finish_opening() -> void:
	if studio.ready_for_studio() == "" and not tool._is_paused:
		tool._toggle_pause()
	studio.sync()
	_refresh()
	var host = panel.get_parent()
	print("[Sections] menu ready: %d sections, shown=%s rect=%s screen=%s layer=%s" % [studio.sections.size(), str(panel.is_visible_in_tree()), str(panel.get_global_rect()), str(panel.get_viewport_rect().size), str(host.layer) if host is CanvasLayer else host.get_class()])


func close() -> void:
	panel.visible = false
	opening = 0
	open_pending = false
	remake_armed = false
	visible = info_panel.visible or bar.visible
	if studio.practice.empty():
		_show_markers(-1)


# Sections need the run played with this tool. A run that was never played
# here (e.g. loaded from a slot) is re-played once, sped up; if it dies,
# sections cover the part before that.
var section_replay_tried = false
var changing = false

func _make_sections() -> void:
	studio.sync()
	if studio.verified < studio.full.size() and not section_replay_tried:
		section_replay_tried = true
		studio.replay_speed = 12.0
		if studio.replay_to(studio.full.size()):
			studio.message = "Playing the run once to make sections..."
			set_meta("make_after_replay", true)
			return
	section_replay_tried = false
	studio.replay_speed = studio.FAST
	studio.segmented = false
	var count = studio.make_sections()
	print("[Sections] made %d sections over %d of %d frames" % [count, studio.verified, studio.full.size()])
	selected = 0
	selected_id = 0
	if count == 0:
		studio.message = "Record a run first"
	elif studio.verified < studio.full.size():
		studio.message = "The run stops working at %s, so sections end there" % seconds(studio.verified)
	else:
		studio.message = ""


func _on_changed() -> void:
	if changing:
		return
	changing = true
	if has_meta("make_after_replay") and studio.job.empty():
		remove_meta("make_after_replay")
		call_deferred("_make_sections")
	elif waiting_finish and not studio.bots.busy() and studio.job.empty() and studio.segment_commit < 0:
		waiting_finish = false
		if studio.segmented and studio.segment_next >= 0:
			call_deferred("start_segment", studio.segment_next)
		else:
			call_deferred("_show_menu_after_practice")
	elif visible:
		_refresh()
	changing = false


func _process(delta: float) -> void:
	if open_pending and studio.job.empty() and not studio.bots.busy() and not _waiting_for_box_preview():
		open()
	if opening > 0:
		opening -= 1
		if opening == 0:
			_finish_opening()
	if not visible:
		return
	if bar.visible:
		_refresh_bar()
		_fit_live_bar()
	if info_panel.visible:
		_refresh_info()
	refresh_timer -= delta
	if panel.visible and refresh_timer <= 0.0:
		refresh_timer = 0.5
		_refresh()


# ---------------------------------------------------------------- numbers

static func seconds(frames: int) -> String:
	return "%.2fs" % (frames / 60.0)


func _section_state(index: int) -> String:
	var section = studio.sections[index]
	if studio.segmented:
		if section.has("skipped_by"):
			return "skipped"
		if bool(section.get("done", false)):
			return "improved" if int(section.get("guide", 0)) > studio.section_frames_now(section) else "kept"
		return "next" if index == studio.first_open_segment() else "locked"
	if int(section.start) > studio.verified:
		return "locked"
	if bool(section.get("broken", false)):
		return "redo"
	if int(section.get("base", studio.section_frames_now(section))) > studio.section_frames_now(section):
		return "improved"
	if int(section.attempts) > 0:
		return "tried"
	return "new"


func _totals() -> Dictionary:
	var saved = 0
	var improved = 0
	var tries = 0
	for section in studio.sections:
		var now = studio.section_frames_now(section)
		var base = int(section.get("base", now))
		if base > now:
			saved += base - now
			improved += 1
		tries += int(section.attempts)
	return {"saved": saved, "improved": improved, "tries": tries}


func _refresh() -> void:
	if studio == null:
		return
	var same_goal = studio.section_index_for_id(selected_id)
	if same_goal >= 0:
		selected = same_goal
	else:
		selected = int(clamp(selected, 0, max(0, studio.sections.size() - 1)))
	selected_id = int(studio.sections[selected].id) if selected < studio.sections.size() else 0
	var totals = _totals()
	var ready = studio.ready_for_studio()
	stat_labels.run.text = seconds(studio.full.size())
	stat_labels.tries.text = str(totals.tries)
	if studio.segmented:
		var seg = studio.segment_totals()
		title_label.text = "Segmented run"
		stat_labels.saved.text = ("-" if seg.ahead >= 0 else "+") + seconds(int(abs(seg.ahead)))
		stat_labels.improved.text = "%d / %d" % [seg.done, studio.sections.size()]
		stat_captions.saved.text = "Ahead of the guide run"
		stat_captions.improved.text = "Segments done"
		run_label.text = ready if ready != "" else "Reach a stop box, then keep your fastest take"
	else:
		title_label.text = "Sections"
		stat_labels.saved.text = "-" + seconds(totals.saved) if totals.saved > 0 else "0.00s"
		stat_labels.improved.text = "%d / %d" % [totals.improved, studio.sections.size()]
		stat_captions.saved.text = "Time saved"
		stat_captions.improved.text = "Sections improved"
		run_label.text = ready if ready != "" else "%d sections · pick one and press Practise" % studio.sections.size()
	mode_button.text = "Restart recording" if studio.segmented and (not studio.full.empty() or not tool._practice_checkpoints.empty()) else "Start recording"
	mode_button.disabled = studio.busy() or studio.segment_pending_start or studio.bots.busy() or tool._practice_playback
	restore_restart_button.visible = studio.records!=null and studio.records.has_restart_backup()
	var game = tool._find_game()
	var reloading = game!=null and tool._practice_restart_from_game_id==game.get_instance_id()
	restore_restart_button.disabled = studio.busy() or studio.segment_pending_start or studio.bots.busy() or reloading
	save_button.disabled = not studio.can_save()
	play_button.disabled = studio.busy() or studio.full.empty() or tool._practice_playback
	remake_button.visible = not studio.segmented
	var box_import = not studio.undo_stack.empty() and bool(studio.undo_stack.back().get("box_import",false))
	undo_button.visible = not studio.segmented or box_import
	undo_button.text = "Undo box import" if box_import else "Undo last finish"
	var text = studio.message
	if studio.bots.busy():
		text = studio.bots.status
	var offer = studio.records.offer_text()
	if not offer.empty():
		text = offer
	status_label.text = text
	status_label.hint_tooltip = text
	undo_button.disabled = studio.undo_stack.empty() or studio.busy()
	route_button.text = "Hide route in level" if studio.route_node != null and is_instance_valid(studio.route_node) else "Show route in level"
	remake_button.text = "Click again to confirm" if remake_armed else "Use working run"
	var has = selected < studio.sections.size()
	practise_button.text = "▶ Practise section %d" % (selected + 1) if has else "Practise"
	var can_begin = ready.empty() or (ready == "Start a recording first" and studio.segmented and has and studio.zone_for(studio.sections[selected]) is Rect2)
	practise_button.disabled = not has or not can_begin or studio.busy() or studio.bots.busy() or (has and _section_state(selected) == "locked")
	if has and _section_state(selected) == "skipped":
		practise_button.disabled = true
	if has and not studio.segmented and int(studio.sections[selected].start) < 0:
		practise_button.disabled = true
		run_label.text = "Boxes ready — Start recording begins your section run"
	_refresh_target_picker(target_picker, selected)
	if has:
		var section = studio.sections[selected]
		selected_label.text = studio.section_name(selected) if studio.segmented and not bool(section.get("done",false)) else "%s · %s" % [studio.section_name(selected), seconds(studio.section_frames_now(section))]
	else:
		selected_label.text = ""
	empty_label.visible = studio.sections.empty()
	_refresh_cards()
	route_map.update()


func _refresh_cards() -> void:
	var parts = [selected]
	for index in studio.sections.size():
		var section = studio.sections[index]
		parts.append("%d:%d:%d:%d:%d:%s" % [section.id, section.start, section.end, section.attempts, section.best, _section_state(index)])
	var signature = str(parts)
	if signature == card_signature:
		return
	card_signature = signature
	if card_grid.get_child_count()==studio.sections.size():
		for card in card_grid.get_children(): card.update()
	elif not reconcile_pending:
		reconcile_pending = true
		call_deferred("_reconcile_cards")

func _reconcile_cards():
	reconcile_pending = false
	if not is_instance_valid(card_grid): return
	while card_grid.get_child_count()>studio.sections.size():
		var child = card_grid.get_child(card_grid.get_child_count()-1)
		card_grid.remove_child(child)
		child.queue_free()
	for index in studio.sections.size():
		if index<card_grid.get_child_count():
			card_grid.get_child(index).update()
			continue
		var card = SectionCard.new()
		card.window = self
		card.index = index
		card.rect_min_size = Vector2(260,150)
		card.connect("picked",self,"_select",[index])
		card.connect("practise",self,"_practise",[index])
		card_grid.add_child(card)
	_queue_selection_scroll()

func _queue_selection_scroll():
	if selection_scroll_pending: return
	selection_scroll_pending = true
	call_deferred("_scroll_to_selection")

func _scroll_to_selection():
	selection_scroll_pending = false
	if is_instance_valid(section_scroll) and selected>=0 and selected<card_grid.get_child_count():
		section_scroll.ensure_control_visible(card_grid.get_child(selected))


func _select(index: int) -> void:
	selected = index
	selected_id = int(studio.sections[index].id) if index >= 0 and index < studio.sections.size() else 0
	card_signature = ""
	_refresh()
	_queue_selection_scroll()


func card_data(index: int) -> Dictionary:
	var section = studio.sections[index]
	var now = studio.section_frames_now(section)
	var base = int(section.get("base", now))
	if studio.segmented and not bool(section.get("done", false)):
		now = int(section.get("guide", 0))
		base = now
	elif studio.segmented:
		base = int(section.get("guide", now))
	var best = int(section.takes[section.best].frames) if section.best >= 0 else -1
	return {"name": str(index + 1), "now": now, "base": base, "best": best, "tries": int(section.attempts), "state": _section_state(index), "selected": index == selected}


# ---------------------------------------------------------------- actions

func _on_practise() -> void:
	_practise(selected)


func _practise(index: int) -> void:
	if index < 0 or index >= studio.sections.size():
		return
	if studio.segmented and _section_state(index) == "locked":
		studio.message = "Finish the segments before this one first"
		_refresh()
		return
	selected = index
	selected_id = int(studio.sections[index].id)
	if not studio.start_practice(index):
		_refresh()
		return
	opening = 0
	panel.visible = false
	bar.visible = true
	bar.raise()
	visible = true
	_show_markers(index)
	_refresh_bar()


func practice_ready(index: int) -> void:
	if studio.practice.empty():
		_show_menu_after_practice()
		return
	_show_markers(index)
	_refresh_bar()


func _on_route() -> void:
	var on = studio.route_node == null or not is_instance_valid(studio.route_node)
	studio.show_route(on)
	_refresh()


func _on_play_run() -> void:
	if studio.play_run():
		close()
	else:
		_refresh()


func _on_undo() -> void:
	var boxes_only = not studio.undo_stack.empty() and bool(studio.undo_stack.back().get("box_import",false))
	if studio.busy() or not studio.undo():
		return
	studio.message = "Restored the previous boxes." if boxes_only else "Undid the last finish -- checking the run..."
	if not boxes_only: studio.replay_to(studio.full.size())
	card_signature = ""
	_refresh()


func _on_remake() -> void:
	if not remake_armed and not studio.sections.empty():
		remake_armed = true
		_refresh()
		return
	remake_armed = false
	studio._push_undo(studio.full.size()+1)
	studio.undo_stack.back()["box_import"] = true
	_make_sections()
	card_signature = ""
	_refresh()

func _on_leaderboard_boxes() -> void:
	studio.leaderboard_boxes().open_leaderboard()


func _on_edit_boxes() -> void:
	if studio.edit_stop_boxes():
		panel.visible = false
		bar.visible = false
	else:
		_refresh()


func _make_target_picker() -> OptionButton:
	var picker = OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.add_icon_override("arrow",Galaxy.icon("chev-down",Galaxy.color("muted"),18))
	picker.add_font_override("font", _font(18))
	for state in ["normal","hover","pressed","focus","disabled"]:
		picker.add_stylebox_override(state,Galaxy.box(Galaxy.color("raised"),Galaxy.color("border"),12,10))
		picker.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("ink") if state!="disabled" else Galaxy.color("dim"))
	picker.get_popup().add_font_override("font",_font(18))
	picker.get_popup().add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),8,10))
	picker.get_popup().add_stylebox_override("hover",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),8,8))
	picker.get_popup().add_color_override("font_color",Galaxy.color("ink"))
	picker.hint_tooltip = "Aim for a later box to skip sections. Changing the target restarts this attempt; saved takes stay."
	picker.connect("item_selected", self, "_on_target_selected", [picker])
	return picker


func _refresh_target_picker(picker, index: int) -> void:
	picker.visible = studio.segmented and index >= 0 and index < studio.sections.size()
	if not picker.visible:
		return
	var ids = []
	for section in studio.sections:
		ids.append(int(section.id))
	var signature = "%d:%s" % [index, str(ids)]
	if str(picker.get_meta("range") if picker.has_meta("range") else "") != signature:
		picker.get_popup().hide()
		picker.clear()
		for target in range(index, studio.sections.size()):
			picker.add_item("Stop at %d" % (target+1), target)
			picker.set_item_metadata(picker.get_item_count()-1, int(studio.sections[target].id))
		picker.set_meta("range", signature)
	picker.set_meta("source_id", int(studio.sections[index].id))
	picker.select(max(0,studio.target_for(index)-index))


func _on_target_selected(item: int, picker) -> void:
	var index = int(studio.practice.section) if not studio.practice.empty() else selected
	if index < 0 or index >= studio.sections.size() or item < 0 or item >= picker.get_item_count():
		return
	if not picker.has_meta("source_id") or int(picker.get_meta("source_id")) != int(studio.sections[index].id):
		return # A chooser from another section/project has no current owner.
	var target = studio.section_index_for_id(int(picker.get_item_metadata(item)))
	if target < index:
		_refresh_target_picker(picker,index)
		return
	var restart = not studio.practice.empty()
	if restart:
		studio.stop_practice()
	studio.set_section_target(index, target)
	if restart:
		_practise(index)
	else:
		_refresh()


# ---------------------------------------------------------------- top bar

func _build_bar() -> void:
	bar = PanelContainer.new()
	bar.add_to_group("goobplayability_ui")
	bar.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),12,12))
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.margin_top = 14
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)
	bar_layout = GridContainer.new()
	bar_layout.add_constant_override("hseparation",14)
	bar_layout.add_constant_override("vseparation",8)
	bar.add_child(bar_layout)
	bar_fields = HBoxContainer.new()
	bar_fields.add_constant_override("separation",14)
	bar_layout.add_child(bar_fields)
	bar_controls = HBoxContainer.new()
	bar_controls.add_constant_override("separation",10)
	bar_layout.add_child(bar_controls)
	for entry in [["section", 22, Galaxy.color("ink")], ["try", 18, Galaxy.color("muted")], ["run", 18, Galaxy.color("ink")], ["best", 18, Galaxy.color("success")], ["last", 18, Galaxy.color("muted")]]:
		var label = _label("", entry[1], entry[2])
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_fields.add_child(label)
		bar_labels[entry[0]] = label
	bar_buttons.restart = _button("Restart", GoobStyle.EDGE, "_on_restart")
	bar_controls.add_child(bar_buttons.restart)
	bar_target_picker = _make_target_picker()
	bar_target_picker.focus_mode = Control.FOCUS_NONE
	bar_controls.add_child(bar_target_picker)
	bar_buttons.finish = _button("Finish", Galaxy.color("success").darkened(0.35), "_on_finish")
	bar_controls.add_child(bar_buttons.finish)
	bar_buttons.menu = _button("Menu", GoobStyle.SKY.darkened(0.4), "_on_bar_menu")
	bar_controls.add_child(bar_buttons.menu)
	bar_buttons.boxes = _button("Boxes",GoobStyle.SKY.darkened(0.4),"_on_edit_boxes")
	bar_buttons.boxes.hint_tooltip = "Pause and preview stop boxes. Apply changed boxes to restart; the old run is backed up."
	bar_controls.add_child(bar_buttons.boxes)
	# Space is Dash during live play, not ui_accept for the last clicked
	# transport control. Keep keyboard navigation on the paused menu only.
	for button in bar_buttons.values():
		button.focus_mode = Control.FOCUS_NONE
	_fit_live_bar()


func _fit_live_bar() -> void:
	if bar_layout==null: return
	var width = bar_fields.get_combined_minimum_size().x+bar_controls.get_combined_minimum_size().x+14
	var available = get_viewport().get_visible_rect().size.x-60
	var columns = 2 if width<=available else 1
	if bar_layout.columns!=columns: bar_layout.columns = columns


func _refresh_bar() -> void:
	if studio.pending_practice_id != 0 or studio.segment_pending_start:
		bar_target_picker.visible = false
		bar_labels.section.text = "Waiting for the level countdown"
		for key in ["try","run","best","last"]:
			bar_labels[key].text = ""
		for key in bar_buttons:
			bar_buttons[key].visible = key == "menu"
		return
	if waiting_finish:
		bar_target_picker.visible = false
		bar_labels.section.text = studio.bots.status if studio.bots.busy() else "Building it into the run"
		for key in ["try", "run", "best", "last"]:
			bar_labels[key].text = ""
		for key in bar_buttons:
			bar_buttons[key].visible = false
		return
	for key in bar_buttons:
		bar_buttons[key].visible = true
	if studio.practice.empty() or int(studio.practice.section) >= studio.sections.size():
		return
	var section = studio.sections[studio.practice.section]
	_refresh_target_picker(bar_target_picker, int(studio.practice.section))
	var now = studio.section_frames_now(section)
	if studio.segmented:
		now = int(section.get("guide", now)) if not bool(section.get("done", false)) else now
	bar_buttons.finish.text = "Keep best & next" if studio.segmented else "Finish"
	var target = studio.target_for(int(studio.practice.section))
	bar_labels.section.text = studio.section_name(int(studio.practice.section)) + (" → %d" % (target+1) if studio.segmented and target > int(studio.practice.section) else "")
	bar_labels.try.text = "Try %d" % (int(section.attempts) + 1)
	bar_labels.run.text = ("Guide " if studio.segmented and not bool(section.get("done", false)) else "Run ") + seconds(now)
	if section.best >= 0:
		var best = int(section.takes[section.best].frames)
		bar_labels.best.text = "Best %s (%s%.2f)" % [seconds(best), "-" if best < now else "+", abs(best - now) / 60.0]
		bar_labels.best.add_color_override("font_color", Galaxy.color("success") if best < now else Galaxy.color("muted"))
	else:
		bar_labels.best.text = "Best -"
	var last = int(section.get("last", 0))
	bar_labels.last.text = "Last " + (seconds(last) if last > 0 else ("died" if last < 0 else "-"))


func _on_restart() -> void:
	studio.retry_practice()


func _on_bar_menu() -> void:
	studio.cancel_practice_request()
	if studio.practice.empty():
		_show_menu_after_practice()
		return
	studio.stop_practice()
	_show_menu_after_practice()


func _on_finish() -> void:
	if studio.practice.empty():
		return
	var index = int(studio.practice.section)
	waiting_finish = true
	if studio.segmented:
		if not studio.commit_segment(index):
			waiting_finish = false
		_refresh_bar()
		return
	if not studio.bots.finish_section(index):
		waiting_finish = false
		_show_menu_after_practice()
		return
	_refresh_bar()


# Segmented run: go straight into a segment.
func start_segment(index: int) -> void:
	if panel.visible and opening > 0:
		return # A newer explicit menu request owns this idle frame.
	if index < 0:
		_show_menu_after_practice()
		return
	_practise(index)
	if studio.practice.empty() and studio.pending_practice_id==0:
		_show_menu_after_practice()


func _on_mode() -> void:
	if studio.busy() or studio.bots.busy():
		return
	studio.start_section_recording()
	card_signature = ""
	_refresh()


func _on_restore_restart() -> void:
	studio.message = studio.records.restore_before_restart()
	card_signature = ""
	_refresh()


func _on_save() -> void:
	studio.message = studio.save_run()
	_refresh()
	tool._show_responsive_popup("PROJECT SAVED" if studio.message.begins_with("Saved to Macro Slot ") else "SAVE NOT COMPLETED",studio.message)


func _show_menu_after_practice() -> void:
	_show_markers(-1)
	bar.visible = false
	card_signature = ""
	open()


# ---------------------------------------------------------------- level markers

func project_loaded() -> void:
	# IDs can be reused by a different slot. Old selection and live target
	# ownership must not leak into that new project's numbered goal order.
	selected = max(0, studio.first_open_segment()) if studio.segmented else 0
	selected_id = 0
	card_signature = ""
	waiting_finish = false
	bar.visible = false
	for picker in [target_picker, bar_target_picker]:
		picker.get_popup().hide()
		picker.clear()
		if picker.has_meta("range"):
			picker.remove_meta("range")
		if picker.has_meta("source_id"):
			picker.remove_meta("source_id")
	_show_markers(-1)


func _show_markers(index: int) -> void:
	if markers != null and is_instance_valid(markers):
		markers.visible = false
		markers.queue_free()
	markers = null
	if studio.sections.empty():
		return
	var player = tool._get_local_player()
	if player == null or player.get_parent() == null:
		return
	markers = SectionMarkers.new()
	markers.window = self
	markers.game = tool._find_game()
	if index >= 0 and index < studio.sections.size():
		markers.section_id = int(studio.sections[index].id)
	markers.refresh_target()
	markers.font = _font(18)
	player.get_parent().add_child(markers)


class SectionMarkers extends Node2D:
	var window = null
	var game = null
	var section_id = 0
	var target_index = -1
	var target_number = 0
	var revision = -1
	var start = null
	var zone = null
	var motion = Vector2.ZERO   # how the run was moving at the stop block
	var font = null
	var time = 0.0

	func _ready() -> void:
		z_index = 3990
		pause_mode = Node.PAUSE_MODE_PROCESS

	func refresh_target() -> void:
		var studio = window.studio
		revision = studio.revision
		target_index = -1
		target_number = 0
		start = null
		zone = null
		motion = Vector2.ZERO
		var index = studio.section_index_for_id(section_id)
		if index < 0:
			return
		var section = studio.sections[index]
		start = studio.start_marker_for(section)
		target_index = studio.target_for(index) if studio.segmented else index
		target_number = target_index + 1
		zone = studio.zone_for(studio.sections[target_index])
		var snap = studio.snap_for(int(section.end)) if int(section.end) >= 0 else null
		motion = snap.get("linear_velocity", Vector2.ZERO) if snap != null else Vector2.ZERO
		if studio.segmented:
			motion = studio.sections[target_index].get("motion", Vector2.ZERO)

	func _process(delta: float) -> void:
		if not is_instance_valid(window) or not is_instance_valid(window.studio):
			queue_free()
			return
		if revision != window.studio.revision:
			refresh_target()
		var tool = window.tool
		visible = tool.enabled and tool._tas_gui_enabled and not tool._overlay_hidden and not tool._macro_editor_preview_active and is_instance_valid(game) and tool._find_game() == game and game.is_server()
		time += delta
		update()

	func _draw() -> void:
		if not is_instance_valid(window):
			return
		# Numbered goals remain visible without starting practice. The active
		# target below receives the stronger STOP highlight and start flag.
		for index in window.studio.sections.size():
			var section = window.studio.sections[index]
			var goal = window.studio.zone_for(section)
			if not goal is Rect2 or index == target_index:
				continue
			var colour = Galaxy.color("success") if bool(section.get("done",false)) else Galaxy.color("warning")
			draw_rect(goal, Color(colour.r,colour.g,colour.b,0.1))
			draw_rect(goal, colour, false, 2.0)
			if font != null:
				draw_string(font, goal.position+Vector2(4,-8),str(index+1),colour)
		if start is Vector2:
			var base = start + Vector2(0, 30)
			draw_line(base, base + Vector2(0, -70), Color("e9f4ef"), 4.0, true)
			var flag = PoolVector2Array([base + Vector2(2, -70), base + Vector2(44, -58), base + Vector2(2, -46)])
			draw_colored_polygon(flag, Galaxy.color("success"))
			if font != null:
				draw_string(font, base + Vector2(-20, 22), "START", Galaxy.color("success"))
		if zone is Rect2:
			var pulse = 0.25 + 0.1 * sin(time * 4.0)
			draw_rect(zone, Color(1.0, 0.77, 0.42, pulse))
			draw_rect(zone, Galaxy.color("warning"), false, 3.0)
			if font != null:
				draw_string(font, zone.position + Vector2(zone.size.x * 0.5 - 20, -8), "STOP %d" % target_number, Galaxy.color("warning"))
			# Arrow: the direction and speed the run had here. Ending close to
			# it makes the join into the rest of the run easy.
			if motion.length() > 1.0:
				var centre = zone.position + zone.size * 0.5
				var tip = centre + motion.normalized() * clamp(motion.length() * 0.08, 18.0, 60.0)
				draw_line(centre, tip, Color.white, 4.0, true)
				var side = (tip - centre).normalized().tangent() * 7.0
				var back = tip - (tip - centre).normalized() * 12.0
				draw_colored_polygon(PoolVector2Array([tip, back + side, back - side]), Color.white)


# ---------------------------------------------------------------- frame info

func _build_info() -> void:
	info_panel = PanelContainer.new()
	info_panel.add_stylebox_override("panel", GoobStyle.box(Color(0.05, 0.07, 0.08, 0.86), Color(0.5, 0.88, 0.7, 0.5), 12, 10))
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.margin_left = -330
	info_panel.margin_top = 90
	info_panel.visible = false
	info_label = _label("", 15)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_child(info_label)
	add_child(info_panel)


func set_info_visible(value: bool) -> void:
	info_panel.visible = value
	visible = panel.visible or bar.visible or value


func _refresh_info() -> void:
	var player = tool._get_local_player()
	if player == null:
		info_label.text = "No player"
		return
	var game = tool._find_game()
	var velocity: Vector2 = player.body.linear_velocity if player.body != null else player.linear_velocity
	var at: Vector2 = player.body.global_position if player.body != null else player.position
	var lines = []
	lines.append("Frame      %d" % studio.current_frame())
	lines.append("Position   %.2f, %.2f" % [at.x, at.y])
	lines.append("Velocity   %.2f, %.2f" % [velocity.x, velocity.y])
	lines.append("Speed      %.2f" % velocity.length())
	lines.append("Grounded   %s" % ("yes" if float(player.stick_to_ground_timer) > 0.0 else "no"))
	lines.append("Dash       cooldown %s · timer %s" % [str(player.dash_cooldown), str(player.dash_timer)])
	lines.append("Coyote     %s" % str(player.coyote_timer))
	if game != null and game.wp_game_data != null:
		lines.append("Race time  %.3f" % float(game.wp_game_data.play_time))
	info_label.text = PoolStringArray(lines).join("\n")


# Kept for the studio's callers.
func draft_text() -> String:
	return ""


func set_draft(_value: String) -> void:
	pass


func on_track_drag(first: int, last: int) -> void:
	studio.add_section(first, last)


func pick_passage(found: Array) -> void:
	if not found.empty():
		studio.mark_frame(found[0].frame)


# ---------------------------------------------------------------- drawing

class SectionCard extends Control:
	signal picked
	signal practise
	var window = null
	var index = 0
	var inside = false
	var card_box
	var box_signature = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_hover", [true])
		connect("mouse_exited", self, "_hover", [false])

	func _hover(value: bool) -> void:
		inside = value
		update()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
			if event.doubleclick:
				emit_signal("practise")
			else:
				emit_signal("picked")

	func _draw() -> void:
		# A slot/project can replace the sections before this frame's refresh.
		if not is_instance_valid(window) or index < 0 or index >= window.studio.sections.size():
			return
		var data = window.card_data(index)
		var accent = Galaxy.color("border")
		var state_text = ""
		if data.state == "tried":
			accent = Galaxy.color("playback")
		elif data.state == "improved":
			accent = Galaxy.color("success")
			state_text = "Improved"
		elif data.state == "redo":
			accent = Galaxy.color("danger")
			state_text = "Needs a new try"
		elif data.state == "locked":
			accent = Galaxy.color("dim")
			state_text = "Fix an earlier section first" if not window.studio.segmented else ""
		elif data.state == "kept":
			accent = Galaxy.color("playback")
			state_text = "Done"
		elif data.state == "skipped":
			accent = Galaxy.color("accent")
			state_text = "Skipped by shortcut"
		elif data.state == "next":
			accent = Galaxy.color("warning")
			state_text = "Next"
		var rect = Rect2(Vector2.ZERO, rect_size)
		var key = "%s:%s:%s" % [Galaxy.theme_name(),inside,data.selected]
		if key!=box_signature:
			box_signature = key
			card_box = Galaxy.box(Galaxy.color("raised") if inside or data.selected else Galaxy.color("surface"),Galaxy.color("accent") if data.selected else Galaxy.color("border"),0,12)
		draw_style_box(card_box,rect)
		draw_line(Vector2(8,14),Vector2(8,rect_size.y-14),accent,3,true)
		var big = window._font(30)
		var small = window._font(15)
		var mid = window._font(19)
		draw_string(big, Vector2(18, 40), data.name, Galaxy.color("ink"))
		draw_string(mid, Vector2(70, 34), "Goal" if window.studio.segmented and data.now == 0 and data.state in ["next","locked"] else window.seconds(data.now), Galaxy.color("ink"))
		if data.base > data.now:
			draw_string(small, Vector2(70, 56), "-%.2fs" % ((data.base - data.now) / 60.0), Galaxy.color("success"))
		var line = ""
		if data.best >= 0 and data.best < data.now:
			line = "Best try %s" % window.seconds(data.best)
		elif data.tries > 0:
			line = "%d tr%s" % [data.tries, "y" if data.tries == 1 else "ies"]
		draw_string(small, Vector2(18, 84), line, Galaxy.color("muted"))
		draw_string(small, Vector2(18, rect_size.y - 14), state_text, accent)


class RouteMap extends Control:
	var window = null
	var _points = PoolVector2Array()
	var _frames = PoolIntArray()
	var _scale = 1.0
	var _offset = Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
			var frame_index = _frame_at(event.position)
			for index in window.studio.sections.size():
				var section = window.studio.sections[index]
				if frame_index >= int(section.start) and frame_index < int(section.end):
					window._select(index)
					return

	func _collect() -> void:
		_points = PoolVector2Array()
		_frames = PoolIntArray()
		var studio = window.studio
		var count = min(studio.verified + 1, studio.full.size())
		var step = int(max(1, ceil(count / 800.0))) # keep the drawing light
		for index in range(0, count, step):
			var frame = studio.full[index]
			var state = frame.get(studio.STATE_KEY) if typeof(frame) == TYPE_DICTIONARY else null
			if typeof(state) == TYPE_DICTIONARY and state.has("position"):
				_points.append(state.position)
				_frames.append(index)
		if _points.empty() or studio.segmented:
			return
		var box = Rect2(_points[0], Vector2.ZERO)
		for point in _points:
			box = box.expand(point)
		var area = rect_size - Vector2(40, 40)
		_scale = min(area.x / max(box.size.x, 1.0), area.y / max(box.size.y, 1.0))
		_offset = (rect_size - box.size * _scale) * 0.5 - box.position * _scale

	func _map(point: Vector2) -> Vector2:
		return point * _scale + _offset

	func _frame_at(position: Vector2) -> int:
		var best = -1
		var best_distance = 30.0
		for index in _points.size():
			var distance = _map(_points[index]).distance_to(position)
			if distance < best_distance:
				best_distance = distance
				best = _frames[index]
		return best

	var _logged = false

	func _draw_segmented() -> void:
		var studio = window.studio
		var points: PoolVector2Array = studio.guide_points
		if points.size() < 2:
			draw_string(window._font(16), Vector2(16, 30), "No guide route", Color("a9b7bd"))
			return
		var box = Rect2(points[0], Vector2.ZERO)
		for point in points:
			box = box.expand(point)
		var area = rect_size - Vector2(40, 40)
		_scale = min(area.x / max(box.size.x, 1.0), area.y / max(box.size.y, 1.0))
		_offset = (rect_size - box.size * _scale) * 0.5 - box.position * _scale
		for index in range(1, points.size()):
			draw_line(_map(points[index - 1]), _map(points[index]), Color(1, 1, 1, 0.25), 2.0, true)
		_collect()
		for index in range(1, _points.size()):
			draw_line(_map(_points[index - 1]), _map(_points[index]), Galaxy.color("success"), 3.0, true)
		var font = window._font(14)
		for index in studio.sections.size():
			var section = studio.sections[index]
			if not section.get("zone") is Rect2:
				continue
			var centre = _map(section.zone.position + section.zone.size * 0.5)
			var colour = Galaxy.color("success") if bool(section.get("done", false)) else (Galaxy.color("warning") if index == studio.first_open_segment() else Color("c8d2d6"))
			draw_rect(Rect2(centre - Vector2(5, 5), Vector2(10, 10)), colour)
			if index == window.selected:
				draw_rect(Rect2(centre - Vector2(8, 8), Vector2(16, 16)), Color.white, false, 2.0)
			draw_string(font, centre + Vector2(-4, -12), str(index + 1), Color.white)

	func _draw() -> void:
		if window.studio.segmented:
			draw_rect(Rect2(Vector2.ZERO, rect_size), Color("12171b"))
			_draw_segmented()
			return
		if not _logged:
			_logged = true
			print("[Sections] menu drawn (%d x %d)" % [rect_size.x, rect_size.y])
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color("12171b"))
		_collect()
		if _points.size() < 2:
			draw_string(window._font(16), Vector2(16, 30), "Play the run once to see its route", Color("a9b7bd"))
			return
		var studio = window.studio
		var palette = [Galaxy.color("success"), Galaxy.color("playback"), Galaxy.color("warning"), Color("ff8ec6"), Galaxy.color("accent")]
		var section_of = 0
		for index in range(1, _points.size()):
			var frame_index = _frames[index]
			while section_of + 1 < studio.sections.size() and frame_index >= int(studio.sections[section_of + 1].start):
				section_of += 1
			var colour = palette[section_of % palette.size()] if not studio.sections.empty() else Galaxy.color("success")
			var width = 5.0 if section_of == window.selected else 2.5
			if not studio.sections.empty() and section_of != window.selected:
				colour = Color(colour.r, colour.g, colour.b, 0.55)
			draw_line(_map(_points[index - 1]), _map(_points[index]), colour, width, true)
		var font = window._font(14)
		for index in studio.sections.size():
			var at = studio.position_at(int(studio.sections[index].start))
			if at is Vector2:
				var point = _map(at)
				draw_circle(point, 9.0 if index == window.selected else 6.0, Color.white if index == window.selected else Color("c8d2d6"))
				draw_string(font, point + Vector2(-4, -12), str(index + 1), Color.white)

func import_working_run():
	if studio.busy() or studio.bots.busy():
		studio.message = "Finish the current action before importing the working run."
		_refresh()
		return
	studio.sync()
	if studio.full.empty():
		studio.message = "Load or record a checkpoint run first, or draw stop boxes in the level."
		_refresh()
		return
	_on_remake()
