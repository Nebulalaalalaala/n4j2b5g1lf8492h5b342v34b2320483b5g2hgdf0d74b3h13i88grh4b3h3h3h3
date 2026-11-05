extends Node2D
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Route = preload("user://mod/tools/tas/TASReplayRoute.gd")
const Selection = preload("user://mod/tools/tas/TASBoxSelection.gd")

# Uses the existing native preview camera/presentation. Boxes are world goals,
# never player teleports, physics fixtures or guessed entry save states.
var studio
var tool
var original = []
var layer
var toolbar
var selected = -1
var selection = Selection.new()
var selection_base = {}
var original_message = ""
var box_list
var list_button
var list_revision = -1
var list_drag_start = -1
var list_press = Vector2.ZERO
var list_base = {}
var focus_button
var delete_all_button
var apply_button
var context_menu
var confirmation
var pan_button = 0
var pan_origin = Vector2.ZERO
var pan_box = -1
var pan_moved = false
var camera_focus = {}
var dragging = false
var moving = false
var resizing = false
var panning = false
var origin = Vector2.ZERO
var old_zone = Rect2()
var draft = Rect2()
var closing = false
var font
var place_button
var instruction
var placing = false
var number_field
var number_button
var order_buttons = {}
var order_signature = ""
var hidden_windows = []
var pointer_position = Vector2.ZERO
var pointer_in_world = false
const DEFAULT_BOX_SIZE = Vector2(160,160)

var live_studio
var proposal = null
var preview_label
var replace_button
var add_button
var replace_armed = false
var preview_revision = -1
var spacing_field
var action_grid
var toolbar_column
var last_wall = 0
var compact = false
var compact_button
var title_handle
var panel_dragging = false
var panel_drag_offset = Vector2.ZERO
var replay_points = PoolVector2Array()
var replay_dashes = []
var dash_markers = true
var dash_toggle
var dash_label_style
var suspended_attempt = {}

func setup(owner, draft_model = null, attempt := {}) -> void:
	live_studio = owner
	proposal = draft_model
	studio = draft_model if draft_model != null else owner
	if draft_model!=null:
		replay_points = Route.points(draft_model.samples)
		replay_dashes = Route.dash_events(draft_model.samples)
		dash_markers = bool(SavedSettings.get_value("tas_replay_dash_markers",true))
	tool = owner.tool
	font = tool._make_font(18)
	dash_label_style = Galaxy.box(Galaxy.color("surface"),Galaxy.color("record"),6,4)
	for index in replay_dashes.size():
		var dash = replay_dashes[index]
		dash["label"] = "D%d · %.2fs %s" % [index+1,dash.time,"→" if dash.direction.x>0 else ("←" if dash.direction.x<0 else "?")]
		dash["label_size"] = font.get_string_size(dash.label)+Vector2(12,6)
	original = studio.sections.duplicate(true)
	original_message = studio.message
	suspended_attempt = attempt
	for field in ["_menu_window","_log_window"]:
		var window = tool.get(field)
		if window != null and is_instance_valid(window):
			hidden_windows.append({"node":window,"visible":window.visible})
			window.hide()
	if proposal!=null and is_instance_valid(proposal.controller.captured_scene):
		var hud = proposal.controller.captured_scene.game_hud
		if is_instance_valid(hud):
			hidden_windows.append({"node":hud,"visible":hud.visible})
			hud.hide()
	pause_mode = Node.PAUSE_MODE_PROCESS
	z_index = 4090
	layer = CanvasLayer.new()
	layer.layer = 220
	layer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(layer)
	toolbar = PanelContainer.new()
	toolbar.rect_position = Vector2(16,16)
	var fill = Galaxy.color("surface")
	fill.a = clamp(float(SavedSettings.get_value("workspace_glass",0.97)),0.7,1.0)
	toolbar.add_stylebox_override("panel",Galaxy.box(fill,Galaxy.color("line"),16,14))
	layer.add_child(toolbar)
	toolbar_column = VBoxContainer.new()
	toolbar_column.add_constant_override("separation",8)
	toolbar.add_child(toolbar_column)
	var heading = HBoxContainer.new()
	heading.add_constant_override("separation",12)
	toolbar_column.add_child(heading)
	var icon = TextureRect.new()
	icon.texture = Galaxy.icon("sections",Galaxy.color("accent"),24)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(icon)
	var title = _text("Replay box preview" if proposal!=null else "Stop boxes",20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	title_handle = title
	title.hint_tooltip = "Drag the title to move this panel"
	if proposal!=null: heading.add_child(_toolbar_button("Fit route","fit_route"))
	compact_button = _toolbar_button("−","toggle_compact")
	compact_button.hint_tooltip = "Collapse controls to see more of the level"
	heading.add_child(compact_button)
	if proposal!=null:
		var source = _text(proposal.controller.source_label(),15)
		source.clip_text = true
		source.hint_tooltip = source.text
		toolbar_column.add_child(source)
		preview_label = _text("",15)
		preview_label.clip_text = true
		toolbar_column.add_child(preview_label)
		var generation_row = HBoxContainer.new()
		generation_row.add_constant_override("separation",10)
		toolbar_column.add_child(generation_row)
		generation_row.add_child(_text("Spacing",16))
		spacing_field = _spin(1,10,0.5,proposal.spacing)
		spacing_field.suffix = "s"
		spacing_field.hint_tooltip = "Approximate spacing. Grounded route points are preferred; the replay determines the order."
		generation_row.add_child(spacing_field)
		var regenerate = _toolbar_button("Regenerate","regenerate")
		regenerate.hint_tooltip = "Rebuild this preview using the chosen spacing. Current saved boxes stay untouched."
		generation_row.add_child(regenerate)
		var dash_row = HBoxContainer.new()
		dash_row.add_constant_override("separation",10)
		toolbar_column.add_child(dash_row)
		dash_toggle = _toolbar_button("Dash moments","_on_dash_toggle_pressed")
		dash_toggle.toggle_mode = true
		dash_toggle.set_pressed_no_signal(dash_markers)
		dash_toggle.hint_tooltip = "Show native dash starts, timestamps and launch directions. This doesn't change section boxes."
		dash_row.add_child(dash_toggle)
		dash_row.add_child(_text("%d dashes" % replay_dashes.size(),15))
	var order_row = HBoxContainer.new()
	order_row.add_constant_override("separation",8)
	toolbar_column.add_child(order_row)
	order_row.add_child(_text("Box",16))
	number_field = _spin(1,max(1,studio.sections.size()),1,1)
	number_field.get_line_edit().connect("text_entered",self,"_on_number_entered")
	number_field.hint_tooltip = "Position in the route. Other box numbers shift to make room."
	order_row.add_child(number_field)
	number_button = _toolbar_button("Set number","set_box_number")
	order_row.add_child(number_button)
	for entry in [["Earlier","earlier"],["Later","later"],["Delete","remove_selected"]]:
		var button = _toolbar_button(entry[0],entry[1])
		order_buttons[entry[1]] = button
		order_row.add_child(button)
	action_grid = GridContainer.new()
	action_grid.columns = 4
	action_grid.add_constant_override("hseparation",8)
	action_grid.add_constant_override("vseparation",8)
	toolbar_column.add_child(action_grid)
	for entry in [["+ Stop box","place_box"],["Zoom −","zoom_out"],["Zoom +","zoom_in"],["Auto boxes","auto_boxes"]]:
		if proposal!=null and entry[1]=="auto_boxes": continue
		var button = _toolbar_button(entry[0],entry[1])
		if entry[1]=="place_box":
			place_button = button
			button.toggle_mode = true
			button.hint_tooltip = "Click here, then click the level to place a box. Drag its corner to resize."
		if entry[1]=="auto_boxes": button.hint_tooltip = "Suggest boxes from map checkpoints. Use From leaderboard in Sections for replay order."
		action_grid.add_child(button)
	var manage = HBoxContainer.new()
	manage.add_constant_override("separation",8)
	toolbar_column.add_child(manage)
	list_button = _toolbar_button("Box list","_toggle_box_list")
	list_button.toggle_mode = true
	manage.add_child(list_button)
	focus_button = _toolbar_button("Focus box","_focus_selected")
	focus_button.hint_tooltip = "Move the camera to the selected box."
	manage.add_child(focus_button)
	delete_all_button = _toolbar_button("Delete all…","_confirm_delete_all")
	delete_all_button.add_color_override("font_color",Galaxy.color("danger"))
	manage.add_child(delete_all_button)
	box_list = ItemList.new()
	box_list.select_mode = ItemList.SELECT_MULTI
	box_list.focus_mode = Control.FOCUS_NONE
	box_list.rect_min_size.y = 112
	box_list.add_font_override("font",font)
	box_list.add_stylebox_override("bg",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),8,6))
	box_list.add_stylebox_override("selected",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),5,4))
	box_list.add_stylebox_override("selected_focus",box_list.get_stylebox("selected"))
	box_list.add_color_override("font_color",Galaxy.color("ink"))
	box_list.add_color_override("font_color_selected",Galaxy.color("ink"))
	box_list.hint_tooltip = "Drag across rows, or use Shift/Ctrl. Double-click a box to focus it."
	box_list.hide()
	toolbar_column.add_child(box_list)
	context_menu = Selection.context(self,layer,font,"_on_context_action")
	instruction = _text("",15)
	instruction.clip_text = true
	toolbar_column.add_child(instruction)
	var footer = HBoxContainer.new()
	footer.add_constant_override("separation",8)
	toolbar_column.add_child(footer)
	if proposal!=null:
		add_button = _toolbar_button("Add boxes","apply_add")
		for state in ["normal","hover","pressed"]:
			add_button.add_stylebox_override(state,Galaxy.primary_box(Galaxy.color("accent")))
			add_button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("accent_ink"))
		add_button.hint_tooltip = "Fill route gaps while keeping existing boxes and takes. Overlapping suggestions are skipped."
		footer.add_child(add_button)
		replace_button = _toolbar_button("Replace boxes…","apply_replace")
		replace_button.add_color_override("font_color",Galaxy.color("danger"))
		replace_button.hint_tooltip = "Replace the current section goals with this preview. Requires explicit confirmation; Undo restores the old goals and takes."
		footer.add_child(replace_button)
	else:
		apply_button = _toolbar_button("Done","done")
		footer.add_child(apply_button)
	footer.add_child(_toolbar_button("Cancel","cancel"))
	_set_place_mode(false)
	_refresh_order_controls()
	last_wall = OS.get_ticks_msec()
	set_process(true)
	set_process_input(true)

func _text(value: String, size: int) -> Label:
	var label = Label.new()
	label.text = value
	label.add_font_override("font",tool._make_font(size))
	label.add_color_override("font_color",Galaxy.color("ink"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _spin(low: float, high: float, step: float, value: float) -> SpinBox:
	var result = SpinBox.new()
	result.min_value = low
	result.max_value = high
	result.step = step
	result.value = value
	result.rect_min_size = Vector2(84,34)
	var edit = result.get_line_edit()
	edit.add_font_override("font",font)
	edit.add_color_override("font_color",Galaxy.color("ink"))
	edit.add_color_override("font_color_uneditable",Galaxy.color("dim"))
	edit.add_color_override("cursor_color",Galaxy.color("accent"))
	for state in ["normal","focus","read_only"]:
		edit.add_stylebox_override(state,Galaxy.box(Galaxy.color("raised"),Galaxy.color("accent") if state=="focus" else Galaxy.color("line"),8,8))
	return result

func regenerate() -> void:
	var entered = spacing_field.get_line_edit().text.replace("s","").replace(",",".").strip_edges()
	if not entered.is_valid_float():
		instruction.text = "Enter a spacing from 1 to 10 seconds."
		return
	spacing_field.value = clamp(float(entered),1,10)
	spacing_field.get_line_edit().release_focus()
	proposal.spacing = spacing_field.value
	proposal.regenerate()
	selected = -1
	selection.clear()
	_refresh_order_controls()

func toggle_compact() -> void:
	compact = not compact
	compact_button.text = "+" if compact else "−"
	var visible_count = 3 if proposal!=null else 1
	for index in range(visible_count,toolbar_column.get_child_count()):
		toolbar_column.get_child(index).visible = not compact
	box_list.visible = not compact and list_button.pressed
	toolbar.rect_size = Vector2.ZERO

func apply_add() -> void:
	_apply_proposal(false)

func apply_replace() -> void:
	if not replace_armed and not live_studio.sections.empty():
		replace_armed = true
		replace_button.text = "Confirm replace %d" % live_studio.sections.size()
		instruction.text = "Replaces existing section goals and takes. Undo is available."
		instruction.hint_tooltip = instruction.text
		return
	_apply_proposal(true)

func _apply_proposal(replace: bool) -> void:
	var error = proposal.controller.apply(proposal,replace)
	if not error.empty():
		instruction.text = error
		instruction.hint_tooltip = error
		return
	finish(true)

func fit_route() -> void:
	if proposal==null or proposal.samples.empty() or not is_instance_valid(tool._macro_editor_camera): return
	camera_focus.clear()
	var rect = Rect2(proposal.samples[0].position,Vector2.ZERO)
	for sample in proposal.samples: rect = rect.expand(sample.position)
	var camera = tool._macro_editor_camera
	var screen = get_viewport().get_visible_rect().size
	var free_width = max(200,screen.x-toolbar.rect_size.x-64)
	var zoom = clamp(max(rect.size.x/free_width,rect.size.y/max(200,screen.y-120))*1.15,0.18,4.0)
	camera.position = rect.position+rect.size*0.5-Vector2(toolbar.rect_size.x*0.5*zoom,0)
	camera.zoom = Vector2.ONE*zoom
	tool._macro_editor_freecam_detached = true
	camera.force_update_scroll()
	tool._refresh_macro_editor_presentation()
	update()


func _process(_delta: float) -> void:
	var now = OS.get_ticks_msec()
	var elapsed = clamp((now-last_wall)/1000.0,0.0,0.05)
	last_wall = now
	if proposal!=null and preview_revision!=studio.revision:
		preview_revision = studio.revision
		replace_armed = false
		replace_button.text = "Replace boxes…"
		preview_label.text = "%d suggested · %d existing kept until Apply" % [studio.sections.size(),live_studio.sections.size()]
		add_button.disabled = not studio.message.empty() or studio.sections.empty()
		replace_button.disabled = add_button.disabled
		if not studio.message.empty():
			instruction.text = studio.message
			instruction.hint_tooltip = studio.message
	if not closing and (not tool._macro_editor_preview_active or tool._find_game() == null):
		finish(false)
		return
	var signature = "%d:%d:%d" % [selected,studio.sections.size(),studio.revision]
	if signature != order_signature:
		_refresh_order_controls()
	var direction = Vector2.ZERO
	for binding in [["camera_left",Vector2.LEFT],["camera_right",Vector2.RIGHT],["camera_up",Vector2.UP],["camera_down",Vector2.DOWN]]:
		if not _popup_open() and not Selection.editing_text(toolbar.get_focus_owner()) and tool._keybinds != null and tool._keybinds.held(binding[0]):
			direction += binding[1]
	if direction != Vector2.ZERO:
		camera_focus.clear()
		tool._move_macro_editor_freecam(direction.normalized() * 720.0 * elapsed)
	_advance_focus(elapsed)
	update()

func _toolbar_button(text: String, method: String) -> Button:
	var button = Button.new()
	button.text = text
	button.add_font_override("font",font)
	button.rect_min_size = Vector2(36,34)
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus"]:
		button.add_stylebox_override(state,Galaxy.box(Galaxy.color("hover") if state in ["hover","pressed"] else Galaxy.color("raised"),Galaxy.color("accent") if state in ["hover","focus","pressed"] else Galaxy.color("line"),10,9))
		button.add_color_override("font_color"+("" if state=="normal" else "_"+state),Galaxy.color("ink"))
	button.add_stylebox_override("disabled",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),10,9))
	button.add_color_override("font_color_disabled",Galaxy.color("dim"))
	button.connect("pressed",self,method)
	return button


func _refresh_order_controls() -> void:
	if number_field == null:
		return
	selection.prune(studio.sections)
	selected = selection.primary(studio.sections,selected)
	order_signature = "%d:%d:%d" % [selected,studio.sections.size(),studio.revision]
	var has = selected >= 0
	var single = selection.ids.size() == 1
	number_field.max_value = max(1,studio.sections.size())
	number_field.editable = single
	number_field.value = selected + 1 if has else 1
	number_button.disabled = not single
	order_buttons.earlier.disabled = not single or selected <= 0
	order_buttons.later.disabled = not single or selected >= studio.sections.size()-1
	order_buttons.remove_selected.disabled = not has
	order_buttons.remove_selected.text = "Delete %d" % selection.ids.size() if selection.ids.size() > 1 else "Delete"
	focus_button.disabled = not has or not studio.zone_for(studio.sections[selected]) is Rect2
	delete_all_button.disabled = studio.sections.empty()
	if apply_button != null:
		var continuing = not suspended_attempt.empty() and live_studio.section_index_for_id(suspended_attempt.id) >= 0
		apply_button.text = "Apply & continue" if continuing else "Done"
		apply_button.hint_tooltip = "Keep these box edits and return to the run."
	_refresh_box_list()
	if instruction != null and not placing:
		instruction.text = "Drag to select · right-drag to pan · wheel to zoom"
		if single: instruction.text = "Box %d selected · Delete or right-click for actions" % (selected+1)
		elif has: instruction.text = "%d selected · Delete or Backspace" % selection.ids.size()
		if proposal!=null and single:
			instruction.text += " · %.3fs" % float(studio.sections[selected].get("replay_time",0))
		instruction.hint_tooltip = instruction.text
	if proposal!=null and not studio.message.empty():
		instruction.text = studio.message
		instruction.hint_tooltip = studio.message
	update()

func _on_number_entered(text: String) -> void:
	_apply_number(text)

func set_box_number() -> void:
	_apply_number(number_field.get_line_edit().text)

func _apply_number(text: String) -> void:
	if selection.ids.size() != 1 or selected < 0 or selected >= studio.sections.size():
		return
	text = text.strip_edges()
	if not text.is_valid_integer():
		_refresh_order_controls()
		return
	var target = int(clamp(int(text),1,studio.sections.size()))-1
	number_field.get_line_edit().release_focus()
	_move_to_number(target)

func _move_to_number(target: int) -> void:
	if studio.move_section(selected,target):
		selected = target
	_refresh_order_controls()

func _world_point(position: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse().xform(position)


func select_box_ids(ids: Array) -> void:
	selection.clear()
	for id in ids: selection.ids[int(id)] = true
	_refresh_order_controls()


func _toggle_box_list() -> void:
	box_list.visible = list_button.pressed
	toolbar.rect_size = Vector2.ZERO
	_clamp_toolbar()


func _refresh_box_list() -> void:
	list_button.text = "Box list (%d)" % studio.sections.size()
	if list_revision != studio.revision:
		var scroll = _list_scrollbar()
		var offset = scroll.value if scroll != null else 0.0
		box_list.clear()
		for index in studio.sections.size():
			var section = studio.sections[index]
			var label = "Box %d" % (index+1)
			if section.get("done",false): label += " · Kept"
			elif section.get("source","") == "finish": label += " · Finish"
			elif section.has("replay_time"): label += " · %.2fs" % float(section.replay_time)
			box_list.add_item(label)
		if scroll != null: scroll.value = offset
		list_revision = studio.revision
	box_list.unselect_all()
	for index in studio.sections.size():
		if selection.ids.has(int(studio.sections[index].id)): box_list.select(index,false)


func _list_scrollbar():
	for child in box_list.get_children():
		if child is VScrollBar: return child
	return null


func _choose_box(index: int, event) -> void:
	selection.choose(studio.sections,index,event.control or event.meta,event.shift)
	selected = index
	_refresh_order_controls()


func _handle_list_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and list_drag_start >= 0:
		if event.position.distance_to(list_press) > 5.0:
			var point = box_list.get_global_transform().affine_inverse().xform(event.position)
			point.y = clamp(point.y,0,max(0,box_list.rect_size.y-1))
			var row = box_list.get_item_at_position(point,false)
			if row >= 0:
				selection.select_range(studio.sections,list_drag_start,row,list_base)
				selected = row
				_refresh_order_controls()
		return true
	if not event is InputEventMouseButton: return false
	if not event.pressed and event.button_index == BUTTON_LEFT and list_drag_start >= 0:
		list_drag_start = -1
		return true
	if not event.pressed or not box_list.visible or not box_list.get_global_rect().has_point(event.position):
		return false
	if not event.button_index in [BUTTON_LEFT,BUTTON_RIGHT]: return false
	var scrollbar = _list_scrollbar()
	if scrollbar != null and scrollbar.visible and scrollbar.get_global_rect().has_point(event.position):
		return false
	var row = box_list.get_item_at_position(box_list.get_global_transform().affine_inverse().xform(event.position),true)
	if row < 0: return false
	if event.button_index == BUTTON_RIGHT:
		_open_context(row,event.position)
	else:
		_set_place_mode(false)
		list_base = selection.ids.duplicate() if event.control or event.meta or event.shift else {}
		_choose_box(row,event)
		if event.doubleclick: _focus_selected()
		else:
			list_drag_start = row
			list_press = event.position
	return true


func _popup_open() -> bool:
	return context_menu.visible or (is_instance_valid(confirmation) and confirmation.visible)


func _clamp_toolbar() -> void:
	var extent = get_viewport().get_visible_rect().size
	var desired = toolbar.rect_position
	toolbar.rect_position = Vector2(clamp(desired.x,8,max(8,extent.x-toolbar.rect_size.x-8)),clamp(desired.y,8,max(8,extent.y-toolbar.rect_size.y-8)))


func _input(event: InputEvent) -> void:
	if closing or _popup_open():
		return
	if _handle_list_input(event):
		get_tree().set_input_as_handled()
		return
	if panel_dragging:
		if event is InputEventMouseMotion:
			var extent = get_viewport().get_visible_rect().size
			var desired = event.position-panel_drag_offset
			toolbar.rect_position = Vector2(clamp(desired.x,8,max(8,extent.x-toolbar.rect_size.x-8)),clamp(desired.y,8,max(8,extent.y-toolbar.rect_size.y-8)))
			get_tree().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index==BUTTON_LEFT and not event.pressed:
			panel_dragging = false
			get_tree().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index==BUTTON_LEFT and event.pressed and title_handle.get_global_rect().has_point(event.position):
		panel_dragging = true
		panel_drag_offset = event.position-toolbar.rect_position
		get_tree().set_input_as_handled()
		return
	# Own world gestures before the native full-screen HUD consumes them in
	# GUI routing. Toolbar clicks still use Godot's normal Control handling.
	if event is InputEventMouseButton and not event.pressed and event.button_index in [BUTTON_RIGHT,BUTTON_MIDDLE]:
		if panning and event.button_index == pan_button:
			panning = false
			if not pan_moved and pan_button == BUTTON_RIGHT and pan_box >= 0:
				_open_context(pan_box,event.position)
			get_tree().set_input_as_handled()
		return
	if dragging and event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
		_commit_drag()
		get_tree().set_input_as_handled()
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		pointer_position = event.position
		pointer_in_world = not toolbar.get_global_rect().has_point(event.position)
		if not dragging and not panning and toolbar.get_global_rect().has_point(event.position):
			return
	_handle_world_input(event)


func _commit_drag() -> void:
	dragging = false
	if moving and draft != old_zone:
		studio.sections[selected]["zone"] = draft
		if proposal == null: studio.refresh_takes_for_box(int(studio.sections[selected].id))
		studio.touch()
		studio.emit_signal("changed")
	elif placing:
		var zone = draft if draft.size.x >= 8 and draft.size.y >= 8 else Rect2(origin-DEFAULT_BOX_SIZE*0.5,DEFAULT_BOX_SIZE)
		selected = studio.add_stop_box(zone)
		if selected >= 0:
			select_box_ids([studio.sections[selected].id])
			selection.anchor = int(studio.sections[selected].id)
			_set_place_mode(false)
	moving = false
	resizing = false
	_refresh_order_controls()


func _hit_box(point: Vector2) -> int:
	var zoom = tool._macro_editor_camera.zoom.x if is_instance_valid(tool._macro_editor_camera) else 1.0
	for index in range(studio.sections.size()-1,-1,-1):
		var zone = studio.zone_for(studio.sections[index])
		if zone is Rect2 and zone.grow(12.0*zoom).has_point(point): return index
	return -1

func _handle_world_input(event: InputEvent) -> void:
	if closing:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo or Selection.editing_text(toolbar.get_focus_owner()): return
		if event.scancode == KEY_ESCAPE:
			if placing: _set_place_mode(false)
			else: finish(false)
		elif event.scancode in [KEY_DELETE,KEY_BACKSPACE]:
			remove_selected()
		elif event.scancode == KEY_A and (event.control or event.meta):
			selection.select_range(studio.sections,0,studio.sections.size()-1,{})
			_refresh_order_controls()
		else: return
		get_tree().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index in [BUTTON_RIGHT,BUTTON_MIDDLE]:
			if not event.pressed or dragging or panning: return
			camera_focus.clear()
			panning = true
			pan_button = event.button_index
			pan_origin = event.position
			pan_box = _hit_box(_world_point(event.position)) if pan_button == BUTTON_RIGHT else -1
			pan_moved = false
		elif event.pressed and event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			if not dragging: _zoom(1.0 / 1.15 if event.button_index == BUTTON_WHEEL_UP else 1.15)
		elif event.button_index == BUTTON_LEFT:
			if event.pressed:
				if panning: return
				camera_focus.clear()
				origin = _world_point(event.position)
				selection_base = selection.ids.duplicate() if event.shift or event.control or event.meta else {}
				var hit = _hit_box(origin) if not placing else -1
				if not placing: _choose_box(hit,event)
				var zoom = tool._macro_editor_camera.zoom.x if is_instance_valid(tool._macro_editor_camera) else 1.0
				var simple_pick = hit >= 0 and not event.shift and not event.control and not event.meta
				if simple_pick and bool(studio.sections[hit].get("done", false)):
					get_tree().set_input_as_handled()
					return
				moving = simple_pick
				old_zone = studio.zone_for(studio.sections[selected]) if moving else Rect2(origin, Vector2.ZERO)
				resizing = moving and origin.distance_to(old_zone.end) <= 18.0 * zoom
				draft = old_zone
				dragging = true
			elif dragging:
				_commit_drag()
		else:
			return
		get_tree().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if panning:
			if pan_box < 0 or pan_moved or event.position.distance_to(pan_origin) > 5.0:
				var movement = event.relative if pan_moved or pan_box < 0 else event.position-pan_origin
				pan_moved = true
				tool._move_macro_editor_freecam(-movement)
		elif dragging:
			var at = _world_point(event.position)
			if resizing:
				draft = Rect2(old_zone.position, Vector2(max(8,old_zone.size.x+at.x-origin.x),max(8,old_zone.size.y+at.y-origin.y)))
			else:
				draft = Rect2(old_zone.position + at - origin, old_zone.size) if moving else Selection.dragging_rect(origin,at)
				if not moving and not placing and draft.size.length() > 5.0:
					selection.ids = selection_base.duplicate()
					for section in studio.sections:
						var zone = studio.zone_for(section)
						if zone is Rect2 and zone.intersects(draft,true): selection.ids[int(section.id)] = true
					_refresh_order_controls()
		else:
			return
		get_tree().set_input_as_handled()

func _draw() -> void:
	if closing or not is_instance_valid(studio):
		return
	var zoom = tool._macro_editor_camera.zoom.x if is_instance_valid(tool._macro_editor_camera) else 1.0
	if proposal!=null:
		if replay_points.size()>1: draw_polyline(replay_points,Color(0.62,0.5,1.0,0.75),2.5*zoom,true)
		if dash_markers: _draw_dash_markers(zoom)
		for old in live_studio.sections:
			var old_zone = live_studio.zone_for(old)
			if old_zone is Rect2: draw_rect(old_zone,Color(0.65,0.7,0.8,0.45),false,1.5*zoom)
	for index in studio.sections.size():
		var zone = studio.zone_for(studio.sections[index])
		if not zone is Rect2:
			continue
		if dragging and moving and selected == index:
			zone = draft
		var colour = Galaxy.color("success") if bool(studio.sections[index].get("done",false)) else Galaxy.color("accent")
		var picked = selection.ids.has(int(studio.sections[index].id))
		draw_rect(zone, Color(colour.r,colour.g,colour.b,0.28 if picked else 0.14))
		draw_rect(zone, Color.white if picked else colour, false, 2.5*zoom)
		if picked and selection.ids.size() == 1 and not bool(studio.sections[index].get("done",false)):
			draw_rect(Rect2(zone.end-Vector2(7,7)*zoom,Vector2(14,14)*zoom),Color.white)
		draw_set_transform(zone.position+Vector2(4,-8)*zoom,0,Vector2.ONE*zoom)
		draw_string(font,Vector2.ZERO,str(index+1),colour)
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	if dragging and not moving:
		var marquee = Galaxy.color("accent")
		draw_rect(draft,Color(marquee.r,marquee.g,marquee.b,0.22))
		draw_rect(draft,marquee,false,2.0*zoom)
	if placing and pointer_in_world:
		var at = _world_point(pointer_position)
		var preview = Rect2(at-DEFAULT_BOX_SIZE*0.5,DEFAULT_BOX_SIZE)
		draw_rect(preview, Color(0.4,0.8,1,0.2))
		draw_rect(preview, Color(0.4,0.8,1), false, 3)
		draw_line(at-Vector2(10,0),at+Vector2(10,0),Color.white,2)
		draw_line(at-Vector2(0,10),at+Vector2(0,10),Color.white,2)


func _toggle_dash_markers(value: bool) -> void:
	dash_markers = value
	SavedSettings.set_value("tas_replay_dash_markers",value)
	update()


func _on_dash_toggle_pressed() -> void:
	_toggle_dash_markers(dash_toggle.pressed)


func _draw_dash_markers(zoom: float) -> void:
	var colour = Galaxy.color("record")
	var inverse = get_viewport().canvas_transform.affine_inverse()
	var visible_world = Rect2(inverse.xform(Vector2.ZERO),Vector2.ZERO).expand(inverse.xform(get_viewport_rect().size)).grow(80*zoom)
	for index in replay_dashes.size():
		var dash = replay_dashes[index]
		if dash.points.size()>1: draw_polyline(dash.points,colour,3.5*zoom,true)
		var at = dash.position
		if not visible_world.has_point(at): continue
		draw_circle(at,6*zoom,Galaxy.color("surface"))
		draw_circle(at,4*zoom,colour)
		var direction = dash.direction
		if direction!=Vector2.ZERO:
			var tip = at+direction*32*zoom
			var side = Vector2(-direction.y,direction.x)*5*zoom
			draw_line(at+direction*8*zoom,tip,Galaxy.color("surface"),6*zoom,true)
			draw_line(at+direction*8*zoom,tip,colour,3*zoom,true)
			draw_colored_polygon(PoolVector2Array([tip,tip-direction*9*zoom+side,tip-direction*9*zoom-side]),colour)
		var origin = at+Vector2(8,-12)*zoom
		draw_set_transform(origin,0,Vector2.ONE*zoom)
		draw_style_box(dash_label_style,Rect2(Vector2(0,-dash.label_size.y),dash.label_size))
		draw_string(font,Vector2(6,-6),dash.label,Galaxy.color("ink"))
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func place_box() -> void:
	_set_place_mode(not placing)
func _set_place_mode(value: bool) -> void:
	placing = value
	place_button.set_pressed_no_signal(value)
	instruction.text = "Click the level to place a stop box" if value else "Drag box to move · corner to resize · right-drag to pan"
	_refresh_order_controls()
	update()

func zoom_in(): _zoom(1.0/1.15)
func zoom_out(): _zoom(1.15)
func _zoom(factor: float) -> void:
	camera_focus.clear()
	tool._zoom_macro_editor_freecam(factor)


func focus_box_id(id: int) -> void:
	if closing: return
	for index in studio.sections.size():
		if int(studio.sections[index].id) == id:
			selected = index
			if not selection.ids.has(id): select_box_ids([id])
			_focus_selected()
			return


func _focus_selected() -> void:
	if selected < 0 or selected >= studio.sections.size(): return
	var box = studio.zone_for(studio.sections[selected])
	var camera = tool._macro_editor_camera
	if not box is Rect2 or not is_instance_valid(camera): return
	var viewport = get_viewport().get_visible_rect().size
	var panel_rect = toolbar.get_global_rect()
	var screen_point = viewport*0.5
	var left = panel_rect.position.x
	var right = viewport.x-panel_rect.end.x
	if panel_rect.grow(32).has_point(screen_point):
		if max(left,right) > viewport.x*0.23:
			screen_point.x = left*0.5 if left > right else panel_rect.end.x+right*0.5
		elif panel_rect.end.y < viewport.y-48.0:
			screen_point.y = (panel_rect.end.y+viewport.y)*0.5
	tool._macro_editor_freecam_detached = true
	camera_focus = {"from":camera.position,"to":camera.position+box.position+box.size*0.5-_world_point(screen_point),"time":0.0}
	_advance_focus(0.34 if bool(SavedSettings.get_value("workspace_reduced_motion",false)) else 0.0)


func _advance_focus(delta: float) -> void:
	if camera_focus.empty(): return
	var camera = tool._macro_editor_camera
	if not is_instance_valid(camera):
		camera_focus.clear()
		return
	camera_focus.time += delta
	var progress = clamp(camera_focus.time/0.34,0.0,1.0)
	var eased = progress*progress*(3.0-2.0*progress)
	camera.position = camera_focus.from.linear_interpolate(camera_focus.to,eased)
	camera.force_update_scroll()
	tool._refresh_macro_editor_presentation()
	if progress >= 1.0: camera_focus.clear()


func _open_context(index: int, position: Vector2) -> void:
	if index < 0 or index >= studio.sections.size(): return
	var id = int(studio.sections[index].id)
	selected = index
	if not selection.ids.has(id): select_box_ids([id])
	_refresh_order_controls()
	Selection.show_context(context_menu,position,get_viewport().get_visible_rect().size,selection.ids.size(),not focus_button.disabled)


func _on_context_action(action: int) -> void:
	if action == 0: _focus_selected()
	elif action == 1: remove_selected()


func auto_boxes():
	if not studio.sections.empty():
		confirmation = Selection.confirm(layer,tool,self,"_generate_map_boxes","Replace the current boxes?","Generate new goals from map checkpoints and the finish. Cancel the editor to restore the original layout.","Generate boxes")
		return
	_generate_map_boxes()


func _generate_map_boxes() -> void:
	studio.make_map_boxes()
	select_box_ids([])
	_set_place_mode(false)
	instruction.text = studio.message
func earlier(): _move_order(-1)
func later(): _move_order(1)
func _move_order(direction: int) -> void:
	var target = selected + direction
	_move_to_number(target)
func remove_selected():
	if selection.ids.size() > 1 and selection.ids.size() == studio.sections.size():
		_confirm_delete_all()
	elif not selection.ids.empty():
		_delete_boxes(selection.ids.keys())


func _confirm_delete_all() -> void:
	if studio.sections.empty(): return
	var ids = []
	for section in studio.sections: ids.append(int(section.id))
	confirmation = Selection.confirm(layer,tool,self,"_delete_boxes","Delete all %d boxes?" % ids.size(),"The recorded replay stays. Cancel this editor to restore the original boxes and takes.","Delete all",[ids])


func _delete_boxes(ids: Array) -> void:
	studio.remove_sections(ids,true)
	select_box_ids([])
	_set_place_mode(false)


func done(): finish(true)
func cancel(): finish(false)
func finish(keep: bool, reopen := true) -> void:
	if closing: return
	var changed = proposal==null and var2bytes(studio.sections)!=var2bytes(original)
	closing = true
	if not keep and proposal==null:
		studio.sections = original
		studio.message = original_message
	tool._end_macro_editor_preview()
	for entry in hidden_windows:
		if is_instance_valid(entry.node):
			entry.node.visible = entry.visible
	hidden_windows.clear()
	if keep and proposal==null:
		if changed: studio.push_box_edit_undo(original)
		studio._bind_open_segment_start()
	live_studio.zone_editor = null
	if proposal==null: studio.touch()
	if (reopen or keep) and live_studio.restore_box_attempt(suspended_attempt,reopen):
		live_studio._window().show_active_attempt(int(live_studio.practice.section))
	elif reopen and is_instance_valid(live_studio.window):
		live_studio.window.call_deferred("open")
	elif reopen and keep and proposal!=null:
		live_studio.call_deferred("open_window")
	queue_free()
