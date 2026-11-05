extends Node
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Route = preload("user://mod/tools/tas/TASReplayRoute.gd")
const Capture = preload("user://mod/tools/tas/TASReplayRouteCapture.gd")
const Draft = preload("user://mod/tools/tas/TASReplaySectionDraft.gd")
const ZoneEditor = preload("user://mod/tools/tas/TASSectionZones.gd")
const RecordAction = preload("user://mod/tools/tas/TASLeaderboardAction.gd")
var studio
var tool
var source = {}
var captured_scene
var captured_game
var captured_revision = -1
var account = ""
var generation = 0
var pending = false
var deadline = 0
var sampler
var progress_layer
var status_label
var progress_bar
var preview_owned = false
var browser_owned = false
var browser_scene
var browser_scale = 1.0
var browser_pause = false
var browser_dialog_pause = 0
var browser_closed_at = 0
var browser_cards = []
var browser_tool_process = false
var browser_tool_physics = false
var browser_origin = ""
var selection_origin = ""

func setup(owner) -> void:
	studio = owner
	tool = owner.tool
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(false)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if pending and event is InputEventKey and event.pressed and event.scancode==KEY_ESCAPE:
		cancel()
		get_tree().set_input_as_handled()

func attach_native(node) -> void:
	if not is_instance_valid(node) or not node is TimeTrialLeaderboardRecordCard: return
	if not tool._tas_gui_enabled: return
	var scene = get_tree().current_scene
	if not scene is TimeTrialGameplayScene or scene.parameters==null: return
	if node.has_meta("goob_sections_action"): return
	var owner = ""
	# Native card creation binds the actual selected replay owner, including
	# the WR/PB shortcut cards which don't emit a leaderboard-row signal.
	for connection in node.get_signal_connection_list("watch_replay_button_pressed"):
		if connection.target==scene and connection.binds.size()>0:
			owner = str(connection.binds[0])
	if owner.empty(): return
	var record = {}
	for item in scene.parameters.leaderboard_data.get("records",[])+scene.parameters.leaderboard_data.get("owner_records",[]):
		if item is Dictionary and str(item.get("owner_id",""))==owner:
			record = item.duplicate(true)
			break
	# Keep selection available while the native profile request is loading.
	# Its inner profile panel stays hidden until that separate RPC completes.
	var panel = node.get_node_or_null("UIDialog")
	if panel==null: return
	var button = RecordAction.new()
	button.name = "GoobUseForSections"
	button.text = "Use for sections"
	button.icon = Galaxy.icon("sections",Galaxy.color("accent_ink"),24)
	button.add_font_override("font",tool._make_font(30))
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal","hover","pressed"]:
		button.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent").lightened(0.08) if state=="hover" else Galaxy.color("accent")))
		button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink"))
	button.add_stylebox_override("disabled",Galaxy.box(Galaxy.color("raised"),Galaxy.color("border")))
	button.disabled = not _valid_scene(scene)
	button.hint_tooltip = "Suggest editable stop boxes along this run. Your current sections stay until you apply." if not button.disabled else "Open this level in a solo Time Trial to create section boxes."
	button.connect("pressed",self,"_request_select",[scene,owner,record,node])
	panel.add_child(button)
	button.setup(node)
	node.set_meta("goob_sections_action",true)
	if not browser_owned and (Engine.time_scale<=0.0 or get_tree().paused):
		_acquire_browser_clock(scene)
	if browser_owned:
		node.pause_mode = Node.PAUSE_MODE_PROCESS
		browser_cards.append(weakref(node))

func _valid_scene(scene) -> bool:
	return tool._tas_gui_enabled and is_instance_valid(scene) and scene==get_tree().current_scene and scene is TimeTrialGameplayScene and scene.parameters!=null and scene.parameters.mode in [0,1] and not scene.parameters.level_id.empty() and is_instance_valid(scene.game) and scene.game==tool._find_game() and scene.game.is_server() and not tool._tool_restricted()

func open_leaderboard() -> void:
	var scene = get_tree().current_scene
	if not _valid_scene(scene):
		tool._show_responsive_popup("OPEN A SOLO LEVEL","Open a level in solo Time Trial, then choose a run from its leaderboard and press Use for sections.")
		return
	if studio.busy() or (studio.bots!=null and studio.bots.busy()):
		tool._show_responsive_popup("FINISH CURRENT ACTION","Close stop-box editing or stop the current attempt before choosing a replay.")
		return
	browser_origin = "sections" if is_instance_valid(studio.window) and studio.window.panel.visible else ("workspace" if is_instance_valid(tool._menu_window) and tool._menu_window.visible else "")
	if is_instance_valid(studio.window): studio.window.close()
	tool._set_menu_open(false)
	studio._leave_timeline_preview()
	_acquire_browser_clock(scene)
	scene.on_leaderboard_button_pressed()

func _acquire_browser_clock(scene):
	if browser_owned: return
	browser_owned = true
	browser_scene = scene
	browser_scale = Engine.time_scale
	browser_pause = get_tree().paused
	browser_dialog_pause = scene.leaderboard_dialog.pause_mode
	browser_tool_process = tool.is_processing()
	browser_tool_physics = tool.is_physics_processing()
	tool.set_process(false)
	tool.set_physics_process(false)
	browser_closed_at = 0
	browser_cards.clear()
	# Native dialog tweens need a running presentation clock. Pause the world
	# with the tree, so opening the chooser never advances the recorded run.
	get_tree().paused = true
	Engine.time_scale = 1.0
	scene.leaderboard_dialog.pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)

func _release_browser_clock(return_ui := true):
	if not browser_owned: return
	browser_owned = false
	var same_scene = is_inside_tree() and is_instance_valid(browser_scene) and browser_scene==get_tree().current_scene
	Engine.time_scale = browser_scale if same_scene else 1.0
	if is_inside_tree(): get_tree().paused = browser_pause if same_scene else false
	if not same_scene and is_instance_valid(tool): tool._is_paused = false
	if is_instance_valid(tool):
		tool.set_process(browser_tool_process)
		tool.set_physics_process(browser_tool_physics)
	if is_instance_valid(browser_scene) and is_instance_valid(browser_scene.leaderboard_dialog):
		browser_scene.leaderboard_dialog.pause_mode = browser_dialog_pause
	for reference in browser_cards:
		var card = reference.get_ref()
		if is_instance_valid(card): card.pause_mode = Node.PAUSE_MODE_INHERIT
	browser_cards.clear()
	browser_scene = null
	if not pending: set_process(false)
	if same_scene and return_ui: _return_to_origin(browser_origin)
	browser_origin = ""

func _return_to_origin(origin):
	if origin=="sections" and is_instance_valid(studio): studio.call_deferred("open_window")
	elif origin=="workspace" and is_instance_valid(tool._menu_window): tool.call_deferred("_set_menu_open",true)

func _request_select(scene,owner,record,card):
	# Leave the native dialog's input/signal stack before pausing or removing it.
	call_deferred("select_run",scene,owner,record,card)

func select_run(scene, owner: String, record: Dictionary, card = null) -> void:
	if pending or not _valid_scene(scene): return
	if studio.busy() or (studio.bots!=null and studio.bots.busy()):
		tool._show_responsive_popup("FINISH CURRENT ACTION","Finish the current section action before importing boxes.")
		return
	selection_origin = browser_origin
	_release_browser_clock(false)
	if not studio.set_workflow_mode("sections"): return
	var level = scene.parameters.level_data
	if not level is Dictionary or not level.get("nodes") is Array or level.nodes.empty():
		tool._show_responsive_popup("LEVEL NOT READY","Wait for this level to finish loading, then try again.")
		return
	if is_instance_valid(studio.window): studio.window.close()
	studio._leave_timeline_preview()
	if not tool._begin_macro_editor_preview():
		tool._show_responsive_popup("PREVIEW UNAVAILABLE","The level isn't ready for freecam. Your sections are unchanged.")
		return
	preview_owned = true
	if is_instance_valid(card):
		# UIDialog emits animated_out immediately, then relies on a tween to
		# remove itself. Our scene-tree pause would freeze that tween, leaving
		# the card covering the level throughout freecam. Close it explicitly.
		card.dialog.animate_out()
		card.dialog.hide()
		card.queue_free()
	_hide_leaderboard(scene)
	tool._set_menu_open(false)
	source = {"level_id":scene.parameters.level_id,"owner":owner,"record":record.duplicate(true),"level":level.duplicate(true)}
	account = str(Moonlight.local_user_id())
	captured_scene = scene
	captured_game = scene.game
	captured_revision = studio.revision
	generation += 1
	pending = true
	deadline = OS.get_ticks_msec()+150000
	_show_progress("Downloading selected replay…")
	set_process(true)
	var token = generation
	var result = yield(_download(source.level_id,owner),"completed")
	if not pending or token!=generation: return
	if not _context_ok(true):
		fail("The level, account or section project changed. Select the replay again.")
		return
	if not result is Dictionary or result.has("error"):
		fail("Couldn't download that replay. Your sections are unchanged; choose another run or try again.")
		return
	var replay = result.get("replay",{})
	if not replay is Dictionary or not replay.get("metadata") is Dictionary or not replay.get("data") is String or replay.data.length()>12*1024*1024:
		fail("The replay response is missing or too large.")
		return
	var bytes = Marshalls.base64_to_raw(replay.data)
	var metadata = replay.metadata
	if bytes.size()<20 or bytes.size()>8*1024*1024 or int(metadata.get("version",-1))!=UpGuys_ReplayPackager.new().get_replay_version() or not metadata.get("player_metadata") is Dictionary or metadata.player_metadata.size()!=1 or float(metadata.get("time",0))<=0 or float(metadata.get("time",0))>900:
		fail("This replay is empty, too long or uses an unsupported format. Your sections are unchanged.")
		return
	for id in metadata.player_metadata:
		if not str(id).is_valid_integer() or int(id)<=0 or not metadata.player_metadata[id] is Dictionary:
			fail("The replay's player metadata is invalid.")
			return
	source["time"] = float(metadata.time)
	status_label.text = "Following the recorded route…"
	sampler = Capture.new()
	add_child(sampler)
	sampler.connect("completed",self,"_captured")
	sampler.connect("progress",self,"_progress")
	sampler.start(source.level,bytes,metadata)

func _download(level_id: String, owner: String):
	return ReplayDownloader.async_download_replay(level_id,owner)

func _hide_leaderboard(scene) -> void:
	if is_instance_valid(scene):
		scene.leaderboard_dialog.dialog.animate_out()
		scene.leaderboard_dialog.dialog.hide()

func _context_ok(check_geometry := false) -> bool:
	if not _valid_scene(captured_scene) or captured_game!=tool._find_game() or source.get("level_id","")!=captured_scene.parameters.level_id or account!=str(Moonlight.local_user_id()) or studio.revision!=captured_revision:
		return false
	return not check_geometry or JSON.print(source.get("level",{}).get("nodes",[]))==JSON.print(captured_scene.parameters.level_data.get("nodes",[]))

func _process(_delta: float) -> void:
	if browser_owned and not pending:
		if not is_instance_valid(browser_scene) or browser_scene!=get_tree().current_scene:
			_release_browser_clock()
			return
		# Frame-step/slowdown controls must not strand native dialog tweens.
		# The tree pause keeps the original gameplay world stationary.
		Engine.time_scale = 1.0
		get_tree().paused = true
		var open_card = false
		for reference in browser_cards:
			if is_instance_valid(reference.get_ref()): open_card = true
		var shown = is_instance_valid(browser_scene) and browser_scene==get_tree().current_scene and browser_scene.leaderboard_dialog.dialog.visible
		if shown or open_card: browser_closed_at = 0
		elif browser_closed_at==0: browser_closed_at = OS.get_ticks_msec()+350
		elif OS.get_ticks_msec()>=browser_closed_at:
			_release_browser_clock()
	if not pending: return
	if not _context_ok(): fail("The level or project changed. Replay analysis was cancelled; your sections are unchanged.")
	elif OS.get_ticks_msec()>deadline: fail("Replay analysis timed out. Your sections are unchanged.")

func _progress(value: float) -> void:
	if is_instance_valid(progress_bar): progress_bar.value = value*100.0

func _captured(samples: Array, error: String) -> void:
	if not pending: return
	if not error.empty():
		fail(error)
		return
	if not _context_ok(true):
		fail("The level or sections changed. Your current boxes are unchanged.")
		return
	var model = Draft.new()
	model.setup(self,samples)
	if model.sections.empty():
		fail("No separated stop boxes could be suggested from this route. Place boxes manually instead.")
		return
	_cleanup(true)
	if not tool._macro_editor_preview_active:
		tool._show_responsive_popup("PREVIEW UNAVAILABLE","The level is not ready for freecam. Your existing boxes are unchanged.")
		return
	var editor = ZoneEditor.new()
	studio.zone_editor = editor
	get_tree().root.add_child(editor)
	editor.setup(studio,model)

func source_label() -> String:
	var record = source.get("record",{})
	var username = record.get("username",{})
	var name = str(username.get("value","Leaderboard run")) if username is Dictionary else str(username)
	return ("World record" if int(record.get("rank",0))==1 else "Leaderboard run")+" · "+name+" · %.3fs" % float(source.get("time",0))

func apply(model, replace: bool) -> String:
	if not _context_ok(true): return "The level or sections changed. Cancel and choose the replay again."
	if not studio.job.empty() or not studio.practice.empty() or (studio.bots!=null and studio.bots.busy()): return "Stop the current attempt before applying boxes."
	if model.sections.empty(): return "Add at least one box before applying."
	var error = Route.retime(model.sections,model.samples)
	if not error.empty(): return error
	var result = [] if replace else studio.sections.duplicate(true)
	# Add fills gaps around the existing goals. Preserve every old ID, zone,
	# take and relative order. Reject an ambiguous old route instead of
	# reordering it by spatial proximity or silently discarding its progress.
	if not replace and not result.empty():
		var at = 0
		for section in result:
			var box = studio.zone_for(section)
			if not box is Rect2: return "An existing section has no box. Use Replace explicitly or finish editing the old route first."
			var visit = Route.first_visit(model.samples,box,at)
			if visit<0: return "The selected run doesn't reach your existing boxes in their current order. Keep them, or explicitly choose Replace boxes."
			section["_import_visit"] = visit
			at = visit
	var additions = 0
	var previous_proposal = 0
	for proposal in model.sections:
		var visit = Route.first_visit(model.samples,proposal.zone,previous_proposal)
		previous_proposal = visit
		var duplicate = false
		for existing in result:
			var box = studio.zone_for(existing)
			var old_visit = int(existing.get("_import_visit",-1))
			var same_passage = old_visit>=0 and abs(float(model.samples[old_visit].time)-float(model.samples[visit].time))<0.75
			if not replace and same_passage and box is Rect2 and box.intersects(proposal.zone):
				duplicate = true
				break
		if duplicate: continue
		var section = proposal.duplicate(true)
		section.erase("id")
		section.erase("target_id")
		section.erase("name")
		section["source"] = "leaderboard"
		section["replay_source"] = {"level_id":source.level_id,"owner":source.owner,"name":source_label()}
		section["_import_visit"] = visit
		var insert_at = result.size()
		for index in result.size():
			if int(result[index].get("_import_visit",-1))>visit:
				insert_at = index
				break
		result.insert(insert_at,section)
		additions += 1
	if result.size()>256: return "This would exceed 256 boxes. Remove some preview boxes first."
	if additions==0: return "All preview boxes already overlap existing goals. Your sections are unchanged."
	if not replace and studio.segmented:
		var new_before_kept = false
		for section in result:
			if not section.has("id"): new_before_kept = true
			elif new_before_kept and bool(section.get("done",false)):
				return "A new box would precede a kept section. Keep your run, or explicitly replace the boxes and start a fresh segmented run."
	# All validation is complete. Assign IDs only at commit, not in preview.
	studio._push_undo(studio.full.size()+1)
	studio.undo_stack.back()["box_import"] = true
	studio.undo_stack.back()["guide_points"] = studio.guide_points
	for section in result:
		section.erase("_import_visit")
		if not section.has("id"): studio._fill_section(section)
	studio.sections = result
	studio.normalize_section_order()
	if replace or studio.guide_points.empty(): studio.guide_points = Route.points(model.samples)
	# Spatial goals aren't foreign replay save states. Segmented practice
	# will still start from the user's own native countdown/kept states.
	if studio.segmented:
		for section in studio.sections:
			if not bool(section.get("done",false)):
				section.start = -1
				section.end = -1
		studio._bind_open_segment_start()
	studio.message = "%d replay boxes applied. Start Segmented run to build your own takes." % additions
	studio.touch()
	studio.emit_signal("changed")
	return ""

func fail(message: String) -> void:
	_cleanup()
	tool._show_responsive_popup("REPLAY BOXES",message)

func cancel() -> void:
	generation += 1
	_release_browser_clock()
	_cleanup()

func _cleanup(keep_preview := false) -> void:
	pending = false
	set_process(false)
	if is_instance_valid(sampler):
		sampler.cancel()
		sampler.queue_free()
	sampler = null
	if preview_owned and not keep_preview and tool._macro_editor_preview_active:
		tool._end_macro_editor_preview()
	preview_owned = false
	if not keep_preview and is_instance_valid(captured_scene) and is_inside_tree() and captured_scene==get_tree().current_scene:
		_return_to_origin(selection_origin)
	selection_origin = ""
	if is_instance_valid(progress_layer): progress_layer.queue_free()
	progress_layer = null

func _show_progress(text: String) -> void:
	progress_layer = CanvasLayer.new()
	progress_layer.layer = 225
	progress_layer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(progress_layer)
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(360,0)
	panel.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),20,14))
	progress_layer.add_child(panel)
	var column = VBoxContainer.new()
	column.add_constant_override("separation",12)
	panel.add_child(column)
	status_label = Label.new()
	status_label.text = text
	status_label.add_font_override("font",tool._make_font(18))
	status_label.add_color_override("font_color",Galaxy.color("ink"))
	column.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.rect_min_size = Vector2(0,10)
	progress_bar.percent_visible = false
	progress_bar.add_stylebox_override("bg",Galaxy.box(Galaxy.color("raised"),Galaxy.color("border"),0,5))
	progress_bar.add_stylebox_override("fg",Galaxy.box(Galaxy.color("accent"),Galaxy.color("accent"),0,5))
	column.add_child(progress_bar)
	var button = Button.new()
	button.text = "Cancel"
	button.focus_mode = Control.FOCUS_NONE
	button.add_font_override("font",tool._make_font(16))
	button.add_color_override("font_color",Galaxy.color("ink"))
	button.add_stylebox_override("normal",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line")))
	button.connect("pressed",self,"cancel")
	column.add_child(button)
	yield(get_tree(),"idle_frame")
	if is_instance_valid(panel): panel.rect_position = (get_viewport().get_visible_rect().size-panel.rect_size)*0.5

func _exit_tree() -> void:
	browser_origin = ""
	selection_origin = ""
	cancel()
