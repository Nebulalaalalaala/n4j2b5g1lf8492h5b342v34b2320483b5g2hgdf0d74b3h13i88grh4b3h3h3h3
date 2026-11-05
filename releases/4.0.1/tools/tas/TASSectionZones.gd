extends Node2D
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Route = preload("user://mod/tools/tas/TASReplayRoute.gd")

# Uses the existing native preview camera/presentation. Boxes are world goals,
# never player teleports, physics fixtures or guessed entry save states.
var studio
var tool
var original = []
var layer
var toolbar
var selected = -1
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
var restart_data = {}
var restart_on_apply = false

func setup(owner, draft_model = null) -> void:
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
	restart_on_apply = proposal==null and owner.segmented
	if restart_on_apply and owner.records!=null: restart_data = owner.records.capture_restart_data()
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
	for entry in [["Earlier","earlier"],["Later","later"],["Remove","remove_selected"]]:
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
		var apply = _toolbar_button("Apply & restart" if restart_on_apply else "Done","done")
		apply.hint_tooltip = "Apply changed boxes and restart at the countdown. The previous run is backed up." if restart_on_apply else "Keep these boxes"
		footer.add_child(apply)
	footer.add_child(_toolbar_button("Cancel","cancel"))
	_set_place_mode(studio.sections.empty())
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
	_refresh_order_controls()

func toggle_compact() -> void:
	compact = not compact
	compact_button.text = "+" if compact else "−"
	var visible_count = 3 if proposal!=null else 1
	for index in range(visible_count,toolbar_column.get_child_count()):
		toolbar_column.get_child(index).visible = not compact
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
		if not number_field.get_line_edit().has_focus() and tool._keybinds != null and tool._keybinds.held(binding[0]):
			direction += binding[1]
	if direction != Vector2.ZERO:
		tool._move_macro_editor_freecam(direction.normalized() * 720.0 * elapsed)
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
	order_signature = "%d:%d:%d" % [selected,studio.sections.size(),studio.revision]
	var has = selected >= 0 and selected < studio.sections.size()
	number_field.max_value = max(1,studio.sections.size())
	number_field.editable = has
	number_field.value = selected + 1 if has else 1
	number_button.disabled = not has
	order_buttons.earlier.disabled = not has or selected <= 0
	order_buttons.later.disabled = not has or selected >= studio.sections.size()-1
	order_buttons.remove_selected.disabled = not has or (has and bool(studio.sections[selected].get("done",false)))
	if instruction != null and not placing:
		instruction.text = "Box %d selected · set number or drag to move" % (selected+1) if has else "Select a box · right-drag to pan · wheel to zoom"
		if proposal!=null and has:
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
	if selected < 0 or selected >= studio.sections.size():
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


func _input(event: InputEvent) -> void:
	if closing:
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
		if panning:
			panning = false
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
	if moving:
		studio.sections[selected]["zone"] = draft
		studio.touch()
	elif draft.size.x >= 8 and draft.size.y >= 8:
		selected = studio.add_stop_box(draft)
	studio.emit_signal("changed")

func _handle_world_input(event: InputEvent) -> void:
	if closing:
		return
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		finish(false)
		get_tree().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index in [BUTTON_RIGHT,BUTTON_MIDDLE]:
			panning = event.pressed
		elif event.pressed and event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			tool._zoom_macro_editor_freecam(1.0 / 1.15 if event.button_index == BUTTON_WHEEL_UP else 1.15)
		elif event.button_index == BUTTON_LEFT:
			if event.pressed:
				origin = _world_point(event.position)
				if placing:
					selected = studio.add_stop_box(Rect2(origin-DEFAULT_BOX_SIZE*0.5,DEFAULT_BOX_SIZE))
					if selected >= 0:
						_set_place_mode(false)
					get_tree().set_input_as_handled()
					return
				selected = -1
				var zoom = tool._macro_editor_camera.zoom.x if is_instance_valid(tool._macro_editor_camera) else 1.0
				for index in range(studio.sections.size()-1, -1, -1):
					var zone = studio.zone_for(studio.sections[index])
					if zone is Rect2 and zone.grow(18.0 * zoom).has_point(origin):
						selected = index
						break
				if selected >= 0 and bool(studio.sections[selected].get("done", false)):
					get_tree().set_input_as_handled()
					return
				moving = selected >= 0
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
			tool._move_macro_editor_freecam(-event.relative)
		elif dragging:
			var at = _world_point(event.position)
			if resizing:
				draft = Rect2(old_zone.position, Vector2(max(8,old_zone.size.x+at.x-origin.x),max(8,old_zone.size.y+at.y-origin.y)))
			else:
				draft = Rect2(old_zone.position + at - origin, old_zone.size) if moving else Rect2(Vector2(min(at.x,origin.x),min(at.y,origin.y)), Vector2(abs(at.x-origin.x),abs(at.y-origin.y)))
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
		draw_rect(zone, Color(colour.r,colour.g,colour.b,0.14))
		draw_rect(zone, colour if selected != index else Color.white, false, 2.5*zoom)
		if selected == index and not bool(studio.sections[index].get("done",false)):
			draw_rect(Rect2(zone.end-Vector2(7,7)*zoom,Vector2(14,14)*zoom),Color.white)
		draw_set_transform(zone.position+Vector2(4,-8)*zoom,0,Vector2.ONE*zoom)
		draw_string(font,Vector2.ZERO,str(index+1),colour)
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	if dragging and not moving:
		draw_rect(draft, Color(0.4,0.8,1,0.2))
		draw_rect(draft, Color(0.4,0.8,1), false, 3)
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

func zoom_in(): tool._zoom_macro_editor_freecam(1.0/1.15)
func zoom_out(): tool._zoom_macro_editor_freecam(1.15)
func auto_boxes():
	if studio.segmented and studio.first_open_segment() != 0:
		return # never discard already committed segments
	studio.make_map_boxes()
	selected = -1
func earlier(): _move_order(-1)
func later(): _move_order(1)
func _move_order(direction: int) -> void:
	var target = selected + direction
	_move_to_number(target)
func remove_selected():
	if selected >= 0 and not bool(studio.sections[selected].get("done",false)):
		studio.sections.remove(selected)
		selected = -1
		studio.normalize_section_order()
		studio.touch()
		studio.emit_signal("changed")
func done(): finish(true)
func cancel(): finish(false)
func finish(keep: bool, reopen := true) -> void:
	if closing: return
	var restart = keep and reopen and restart_on_apply and var2bytes(studio.sections)!=var2bytes(original)
	if restart and live_studio.records!=null and not live_studio.records.save_before_restart(restart_data):
		instruction.text = "Couldn't back up the old run. Free space, then try Apply again."
		return
	closing = true
	if not keep and proposal==null:
		studio.sections = original
	tool._end_macro_editor_preview()
	for entry in hidden_windows:
		if is_instance_valid(entry.node):
			entry.node.visible = entry.visible
	hidden_windows.clear()
	if keep and proposal==null:
		studio._bind_open_segment_start()
	live_studio.zone_editor = null
	if proposal==null: studio.touch()
	if restart:
		live_studio.call_deferred("start_section_recording",true)
	elif reopen and is_instance_valid(live_studio.window):
		live_studio.window.call_deferred("open")
	elif reopen and keep and proposal!=null:
		live_studio.call_deferred("open_window")
	queue_free()
