extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
var manager
var root
var panel
var cards
var status
var font
var remove_dialog
var remove_id = ""
var dragging = false
var drag_offset = Vector2.ZERO
var buttons = []
var scale_value = 1.0

func style(color):
	var box = StyleBoxFlat.new()
	box.bg_color = Color(color)
	box.border_color = Color("34434b")
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func label(parent,text,tint = "e9eeeb"):
	var result = Label.new()
	result.text = text
	result.add_font_override("font",font)
	result.add_color_override("font_color",Color(tint))
	parent.add_child(result)
	return result

func button(parent,text,method,args = []):
	var result = Button.new()
	result.text = text
	result.add_font_override("font",font)
	result.add_stylebox_override("normal",style("2b373e"))
	result.add_stylebox_override("hover",style("35464d"))
	result.add_stylebox_override("pressed",style("24594c"))
	result.connect("pressed",self,method,args)
	parent.add_child(result)
	buttons.append(result)
	return result

func _ready():
	layer = 160
	pause_mode = Node.PAUSE_MODE_PROCESS
	font = DynamicFont.new()
	var data = DynamicFontData.new()
	data.font_path = ModPaths.MAIN_FONT
	font.font_data = data
	font.size = 17
	root = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(root)
	var dim = ColorRect.new()
	dim.color = Color(0,0,0,0.35)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.rect_min_size = Vector2(690,590)
	panel.rect_position = Vector2(70,55)
	panel.add_stylebox_override("panel",style("181f24"))
	root.add_child(panel)
	var column = VBoxContainer.new()
	column.add_constant_override("separation",12)
	panel.add_child(column)
	var title = HBoxContainer.new()
	column.add_child(title)
	var handle = label(title,"ACCOUNTS")
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.connect("gui_input",self,"drag")
	var scaling = SpinBox.new()
	scaling.min_value = 25
	scaling.max_value = 300
	scaling.allow_greater = true
	scaling.value = float(SavedSettings.get_value("account_manager_scale",100))
	scaling.suffix = "%"
	scaling.rect_min_size.x = 96
	scaling.get_line_edit().add_font_override("font",font)
	scaling.connect("value_changed",self,"scale_changed")
	title.add_child(scaling)
	scale_value = scaling.value/100.0
	button(title,"×","close")
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.rect_min_size.y = 370
	scroll.scroll_horizontal_enabled = false
	column.add_child(scroll)
	cards = VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_constant_override("separation",8)
	scroll.add_child(cards)
	status = label(column,"")
	status.autowrap = true
	status.rect_min_size.y = 42
	var actions = HBoxContainer.new()
	column.add_child(actions)
	button(actions,"+ Add account","add_account")
	label(actions,"Saved on this Windows account", "9ba8ad")
	actions.hint_tooltip = "Saved session tokens can sign you in. Never share the accounts folder. Windows protection does not protect against malware running as you."
	remove_dialog = ConfirmationDialog.new()
	remove_dialog.get_ok().text = "Remove locally"
	remove_dialog.connect("confirmed",self,"remove_confirmed")
	add_child(remove_dialog)
	manager.connect("changed",self,"refresh")
	root.hide()

func open():
	root.show()
	refresh()
	fit()
	call_deferred("settle_layout")

func settle_layout():
	yield(get_tree(),"idle_frame")
	fit()

func close():
	if not manager.busy:
		root.hide()

func fit():
	if panel.has_meta("shell_embedded"):
		return
	var size = get_viewport().get_visible_rect().size
	var stretch = max(0.01,OS.window_size.x/max(1,size.x))
	var factor = scale_value/stretch
	if is_equal_approx(scale_value,1.0):
		factor = min(factor,min((size.x-24)/panel.rect_size.x,(size.y-24)/panel.rect_size.y))
	panel.rect_scale = Vector2.ONE * factor
	panel.rect_position.x = clamp(panel.rect_position.x,0,max(0,size.x-80))
	panel.rect_position.y = clamp(panel.rect_position.y,0,max(0,size.y-30))
	if is_equal_approx(scale_value,1.0):
		panel.rect_position.x = clamp(panel.rect_position.x,0,max(0,size.x-panel.rect_size.x*factor-12))
		panel.rect_position.y = clamp(panel.rect_position.y,0,max(0,size.y-panel.rect_size.y*factor-12))

func scale_changed(value):
	if is_nan(value) or is_inf(value):
		return
	scale_value = max(0.25,value/100.0)
	SavedSettings.set_value("account_manager_scale",value)
	fit()

func drag(event):
	if panel.has_meta("shell_embedded"):
		return
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		dragging = event.pressed
		drag_offset = panel.get_global_mouse_position()-panel.rect_position
	elif event is InputEventMouseMotion and dragging:
		panel.rect_position = panel.get_global_mouse_position()-drag_offset
		fit()

func _input(event):
	if not root.is_visible_in_tree() or panel.has_meta("shell_embedded"):
		return
	if event is InputEventMouseButton and not event.pressed:
		dragging = false
	if root.visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func order(a,b):
	var current = manager.current_id()
	if a.id == current:
		return b.id != current
	if b.id == current:
		return false
	return a.last_used > b.last_used

func last_used(at):
	if at <= 0:
		return "Not used yet"
	if OS.get_unix_time()-at < 120:
		return "Just now"
	var date = OS.get_datetime_from_unix_time(int(at))
	return "%04d-%02d-%02d · %02d:%02d UTC" % [date.year,date.month,date.day,date.hour,date.minute]

func refresh():
	if manager.busy:
		for item in buttons:
			if is_instance_valid(item):
				item.disabled = true
		status.text = manager.status
		return
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	var live = []
	for item in buttons:
		if is_instance_valid(item) and item.is_inside_tree():
			item.disabled = manager.busy
			live.append(item)
	buttons = live
	var ordered = manager.store.records.duplicate()
	ordered.sort_custom(self,"order")
	for record in ordered:
		card(record)
	if ordered.empty():
		label(cards,"No saved accounts yet.","9ba8ad")
	status.text = manager.status if not manager.status.empty() else "Choose an account to switch. Remember login stores credentials Windows-encrypted on this PC."

func card(record):
	var current = manager.is_current_usable(record.id)
	var card = PanelContainer.new()
	card.add_stylebox_override("panel",style("253c33" if current else "222c33"))
	cards.add_child(card)
	var row = HBoxContainer.new()
	row.add_constant_override("separation",14)
	card.add_child(row)
	var preview = Control.new()
	preview.rect_min_size = Vector2(80,86)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview)
	var goober = load("res://project_specific/gfx/spine/upguy/upguy.tscn").instance()
	goober.enable_sounds = false
	goober.apply_defaults = true
	preview.add_child(goober)
	goober.position = Vector2(40,79)
	goober.scale = Vector2(0.045,0.045)
	goober.set_goober_skin_data(record.skin)
	goober.get_animation_state().set_animation("Idle",true,0)
	var text = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	label(text,record.name.substr(0,28))
	label(text,"Level " + str(record.level),"a6b5bc")
	label(text,last_used(record.last_used),"9ba8ad")
	if current:
		label(row,"● CURRENT","9dd6bd")
	else:
		var action = button(row,"Sign in" if record.get("signin_required",false) else "Switch","switch_to",[record.id])
		action.disabled = manager.busy
		var more = button(row,"…","remove_prompt",[record.id])
		more.hint_tooltip = "Remove saved account from this device only"
		more.disabled = manager.busy

func add_account():
	manager.open_login()

func switch_to(id):
	manager.switch_account(id)

func remove_prompt(id):
	remove_id = id
	remove_dialog.dialog_text = "Remove %s from this device?\nThe online account will not be deleted." % manager.store.find(id).get("name","account")
	remove_dialog.popup_centered(Vector2(440,160))

func remove_confirmed():
	if manager.busy or remove_id == manager.current_id():
		return
	manager.status = "Removed from this device only." if manager.store.remove(remove_id) else "Could not remove local entry."
	refresh()
