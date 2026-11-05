extends VBoxContainer
const Kit=preload("user://mod/core/workspace4/Kit.gd")
const Galaxy=preload("user://mod/core/workspace4/Galaxy.gd")
var menu
var service
var toggles={}
var shortcut_buttons={}
var numbers={}
var reward_note
var options={}

func build(owner,controller):
	menu=owner
	service=controller
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_constant_override("separation",12)
	var standard=_module("Goobplayability Standard","standard")
	_toggle(standard,"Claim available Free Spins","free_spin","Collects the native free reward at home. Paid spins and ads are excluded.")
	_toggle(standard,"Spectator tools","spectator","Pick a living player and adjust the native camera view.")
	reward_note=menu.label("",13,Galaxy.color("muted"))
	reward_note.autowrap=true
	standard.add_child(reward_note)
	var zoom=_module("Zoom","zoom")
	_toggle(zoom,"Mouse wheel","wheel","Scroll over gameplay to zoom. Menus and editors keep their own controls.")
	_number(zoom,"Zoom out","zoom_value",0.5,3,0.05)
	_number(zoom,"Held zoom out","hold_zoom",0.5,3,0.05)
	_number(zoom,"Smoothness","smoothness",2,30,1)
	for spec in [["view_zoom_hold","Hold shortcut"],["view_zoom_reset","Reset shortcut"]]:
		var row=Kit.row(zoom)
		row.add_child(menu.label(spec[1],15,Galaxy.color("ink")))
		row.add_child(menu._spacer())
		shortcut_buttons[spec[0]]=Kit.action(menu,row,"Assign","keyboard",self,"_shortcut",[spec[0]])
	service.connect("changed",self,"refresh")
	var timer=Timer.new()
	timer.wait_time=0.5
	timer.pause_mode=Node.PAUSE_MODE_PROCESS
	add_child(timer)
	timer.connect("timeout",self,"_refresh_visible")
	timer.start()
	refresh()

func _module(title,key):
	var card=menu.card(self,title,Galaxy.color("accent"))
	var line=Kit.row(card)
	_toggle(line,"On",key,"")
	line.add_child(menu._spacer())
	var gear=Kit.action(menu,line,"","settings",self,"_expand",[key])
	gear.hint_tooltip="Configure "+title
	var panel=Kit.column(card,10)
	panel.hide()
	options[key]=panel
	return panel

func _toggle(parent,title,key,tip):
	var button=CheckButton.new()
	button.text=title
	button.focus_mode=Control.FOCUS_NONE
	button.pressed=bool(service.settings[key])
	button.hint_tooltip=tip
	button.add_font_override("font",menu.font(15))
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]: button.add_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["on","on_disabled"]: button.add_icon_override(state,menu._toggle_icon(true))
	for state in ["off","off_disabled"]: button.add_icon_override(state,menu._toggle_icon(false))
	for state in ["font_color","font_color_hover","font_color_pressed","font_color_hover_pressed"]: button.add_color_override(state,Galaxy.color("ink"))
	button.add_color_override("font_color_disabled",Galaxy.color("muted"))
	button.connect("toggled",self,"_toggle_changed",[key])
	parent.add_child(button)
	toggles[key]=button
	return button

func _number(parent,title,key,low,high,step):
	var line=Kit.row(parent)
	var label=menu.label(title,15,Galaxy.color("ink"))
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	line.add_child(label)
	var value=SpinBox.new()
	value.min_value=low
	value.max_value=high
	value.step=step
	value.value=float(service.settings[key])
	value.rect_min_size.x=100
	value.add_font_override("font",menu.font(15))
	var field=value.get_line_edit()
	field.add_font_override("font",menu.font(15))
	field.add_color_override("font_color",Galaxy.color("ink"))
	field.add_stylebox_override("normal",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),8,8))
	field.add_stylebox_override("focus",Galaxy.box(Color.transparent,Galaxy.color("accent"),8,8))
	numbers[key]=value
	value.connect("value_changed",self,"_number_changed",[key])
	line.add_child(value)

func _expand(key): options[key].visible=not options[key].visible
func _toggle_changed(value,key): service.set_option(key,value)
func _number_changed(value,key): service.set_option(key,value)
func _refresh_visible():
	if is_visible_in_tree(): refresh()

func refresh():
	for key in numbers:
		if not is_equal_approx(numbers[key].value,float(service.settings[key])):
			numbers[key].set_block_signals(true)
			numbers[key].value=float(service.settings[key])
			numbers[key].set_block_signals(false)
	for key in toggles: toggles[key].set_pressed_no_signal(bool(service.settings[key]))
	for key in ["standard","zoom"]: toggles[key].text="On" if toggles[key].pressed else "Off"
	if reward_note!=null: reward_note.text=service.reward_status
	for key in shortcut_buttons:
		var keys=service.tool_ref._keybinds
		shortcut_buttons[key].text=keys.caption(key) if keys!=null else "Unbound"

func _shortcut(id):
	menu.select("settings")
	var keys=service.tool_ref._keybinds
	if keys==null or not is_instance_valid(keys.view): return
	var ancestor=keys.view.get_parent()
	while ancestor!=null:
		if ancestor.get_script()!=null and str(ancestor.get_script().resource_path).ends_with("/PageTabs.gd"):
			ancestor.select(2,false)
			break
		ancestor=ancestor.get_parent()
	keys.view.capture(id)
	if keys.view.buttons.has(id): keys.view.buttons[id].grab_focus()
