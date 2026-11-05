extends VBoxContainer
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
var tool
var studio
var checkpoint_body
var section_body
var mode_buttons = {}
var status
var actions
var section_summary
var mode_signature = ""
var record_button

func setup(owner):
	tool = owner
	studio = tool._tas_studio()
	section_summary = tool._make_label("",tool._header_font,Galaxy.color("ink"))
	section_summary.autowrap = true
	tool._practice_status_label.get_parent().add_child(section_summary)
	add_constant_override("separation",12)
	var choices = GridContainer.new()
	choices.columns = 2
	choices.add_constant_override("hseparation",10)
	add_child(choices)
	for spec in [["checkpoints","Checkpoints","flag","Record and retry using checkpoints."],["sections","Sections","sections","Build a run with stop boxes and alternate takes."]]:
		var button = tool._make_button(spec[1],tool.COLOR_PURPLE,0)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.icon = Galaxy.icon(spec[2],Galaxy.color("ink"),20)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.hint_tooltip = spec[3]
		button.connect("pressed",self,"_choose",[spec[0]])
		choices.add_child(button)
		mode_buttons[spec[0]] = button
	checkpoint_body = VBoxContainer.new()
	add_child(checkpoint_body)
	section_body = tool._open_card(self,"Section run")
	record_button = tool._make_button("Start recording",tool.COLOR_PURPLE,0)
	record_button.icon = Galaxy.icon("play",Galaxy.color("accent_ink"),20)
	record_button.focus_mode = Control.FOCUS_NONE
	record_button.hint_tooltip = "Start at the countdown using your stop boxes. The previous run is backed up."
	record_button.connect("pressed",self,"_record")
	section_body.add_child(record_button)
	actions = GridContainer.new()
	actions.columns = 2
	actions.add_constant_override("hseparation",10)
	actions.add_constant_override("vseparation",8)
	section_body.add_child(actions)
	for spec in [["Sections & takes","sections","_open"],["Use working run","macro","_use_run"],["Edit boxes","plus","_edit_boxes"],["From leaderboard","trophy","_leaderboard"]]:
		var button = tool._make_button(spec[0],tool.COLOR_BLUE,0)
		button.icon = Galaxy.icon(spec[1],Galaxy.color("ink"),18)
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for state in ["normal","hover","pressed"]:
			button.add_stylebox_override(state,Galaxy.box(Galaxy.color("raised"),Galaxy.color("border")))
			button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("ink"))
		button.connect("pressed",self,spec[2])
		button.hint_tooltip = {"_open":"Practise sections and compare saved takes.","_use_run":"Suggest sections along the loaded or recorded run. Replacing existing boxes needs confirmation.","_edit_boxes":"Place, move and reorder stop boxes in freecam.","_leaderboard":"Choose a native leaderboard run, review its route, then apply its suggested boxes."}[spec[2]]
		actions.add_child(button)
	status = tool._make_label("",tool._small_font,tool.COLOR_TEXT_DIM)
	status.autowrap = true
	section_body.add_child(status)
	studio.connect("changed",self,"refresh")
	connect("resized",self,"_fit")
	refresh()

func _fit():
	if is_instance_valid(actions): actions.columns = 2 if rect_size.x>=440 else 1

func _choose(mode):
	studio.set_workflow_mode(mode)
	refresh()

func refresh():
	if not is_instance_valid(studio) or not is_instance_valid(tool._practice_status_label) or not is_instance_valid(section_summary): return
	var sections = studio.workflow_mode=="sections"
	tool._practice_status_label.visible = not sections
	section_summary.visible = sections
	section_summary.text = "%d section boxes · %.2fs recorded" % [studio.sections.size(),studio.full.size()/60.0] if not studio.sections.empty() else "Sections · ready to record"
	checkpoint_body.visible = not sections
	section_body.visible = sections
	var signature = Galaxy.theme_name()+":"+studio.workflow_mode
	if signature!=mode_signature:
		for state in ["normal","hover","pressed"]:
			record_button.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent")))
			record_button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink"))
	for key in mode_buttons:
		var button = mode_buttons[key]
		button.set_pressed_no_signal(key==studio.workflow_mode)
		if signature==mode_signature: continue
		for state in ["normal","hover","pressed"]:
			button.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent")) if key==studio.workflow_mode else Galaxy.box(Galaxy.color("raised"),Galaxy.color("border")))
			button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink") if key==studio.workflow_mode else Galaxy.color("ink"))
	mode_signature = signature
	var continuing = studio.has_section_recording()
	record_button.text = "Continue run" if continuing else "Start recording"
	record_button.hint_tooltip = "Continue from the next section's saved entry." if continuing else "Start at the countdown using your stop boxes."
	record_button.disabled = studio.busy() or studio.segment_pending_start or studio.bots.busy() or tool._practice_playback or (continuing and studio.first_open_segment() < 0)
	status.text = studio.message if not studio.message.empty() else ("%d stop boxes · ready to record" % studio.sections.size() if not studio.sections.empty() else "Open Edit boxes to place goals or choose Auto boxes.")

func _open(): studio.open_window()
func _record():
	if not studio.start_or_continue_sections(): tool._show_responsive_popup("SECTION RECORDING",studio.message)
func _use_run():
	studio.open_window()
	studio.window.call_deferred("import_working_run")
func _edit_boxes():
	if not studio.edit_stop_boxes():
		tool._show_responsive_popup("STOP BOXES",studio.message)
func _leaderboard(): studio.leaderboard_boxes().open_leaderboard()

func _exit_tree():
	if is_instance_valid(section_summary): section_summary.queue_free()
