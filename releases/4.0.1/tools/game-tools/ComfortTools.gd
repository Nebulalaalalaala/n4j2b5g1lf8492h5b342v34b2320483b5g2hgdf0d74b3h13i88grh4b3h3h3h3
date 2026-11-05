extends CanvasLayer

# Presentation and convenience controller; retains the game's camera and reward UI.
signal changed
const SETTING="goobplayability_comfort"
const DEFAULTS={"standard":true,"free_spin":false,"spectator":true,"zoom":false,"wheel":true,"hold_zoom":1.65,"zoom_value":1.0,"smoothness":12.0}
var settings=DEFAULTS.duplicate()
var tool_ref
var game
var camera
var native_factor=1.0
var factor=1.0
var target_factor=1.0
var held=false
var poll: Timer
var reward_poll: Timer
var wheel_nodes=[]
var reward_dialog
var reward_owner=""
var retry_at=0
var claim_at=0
var reward_status="Waiting for home"
var spectator_panel: PanelContainer
var player_picker: OptionButton
var pending_target=0
var pending_from=-1
var pending_at=0
var pending_steps=0
var player_signature=""

func configure(owner):
	tool_ref=owner
	layer=160
	pause_mode=Node.PAUSE_MODE_PROCESS
	set_process_priority(999999)
	var saved=SavedSettings.get_value(SETTING,{})
	if saved is Dictionary:
		for key in DEFAULTS:
			if typeof(saved.get(key))==typeof(DEFAULTS[key]) or (typeof(DEFAULTS[key])==TYPE_REAL and typeof(saved.get(key))==TYPE_INT): settings[key]=saved[key]
	for key in ["hold_zoom","zoom_value"]: settings[key]=clamp(float(settings[key]),0.5,3.0)
	settings.smoothness=clamp(float(settings.smoothness),2,30)
	poll=_timer(0.2,"_poll")
	reward_poll=_timer(1.0,"_reward_tick")
	_build_spectator()
	get_tree().connect("node_added",self,"_node_added")
	_scan_wheels(get_tree().root)
	set_process(false)
	_update_timers()

func _timer(seconds,method):
	var timer=Timer.new()
	timer.wait_time=seconds
	timer.pause_mode=Node.PAUSE_MODE_PROCESS
	add_child(timer)
	timer.connect("timeout",self,method)
	return timer

func set_option(key,value):
	if not DEFAULTS.has(key): return
	if typeof(DEFAULTS[key])==TYPE_BOOL: value=bool(value)
	elif key in ["hold_zoom","zoom_value"]: value=clamp(float(value),0.5,3.0)
	else: value=clamp(float(value),2,30)
	settings[key]=value
	SavedSettings.set_value(SETTING,settings.duplicate())
	_update_timers()
	_poll()
	emit_signal("changed")

func _update_timers():
	if settings.zoom or (settings.standard and settings.spectator):
		if poll.is_stopped(): poll.start()
	else:
		poll.stop()
		restore_native_presentation()
	if settings.standard and settings.free_spin:
		if reward_poll.is_stopped(): reward_poll.start()
	else: reward_poll.stop()

func _blocked() -> bool:
	if not is_instance_valid(tool_ref): return true
	if is_instance_valid(game) and game.wp_game_data.is_level_editor: return true
	for flag in ["_macro_editor_preview_active","_practice_active","_practice_playback"]:
		if bool(tool_ref.get(flag)): return true
	return false

func _find_camera(node):
	if node is GameCamera and node.game==game: return node
	for child in node.get_children():
		var found=_find_camera(child)
		if found!=null: return found
	return null

func _poll():
	var next=tool_ref.call("_find_game") if is_instance_valid(tool_ref) else null
	if next!=game or (is_instance_valid(game) and not is_instance_valid(camera)):
		restore_native_presentation()
		game=next
		if is_instance_valid(game):
			camera=_find_camera(game.get_parent())
			if is_instance_valid(camera): native_factor=camera.z_factor
	if _blocked() or (held and (tool_ref._keybinds==null or not tool_ref._keybinds.held("view_zoom_hold"))): held=false
	_update_spectator()
	_update_zoom()
	_advance_target()

func _zoom_allowed() -> bool:
	return is_instance_valid(camera) and not _blocked() and (settings.zoom or (settings.standard and settings.spectator and _spectating()))

func _update_zoom():
	target_factor=float(settings.zoom_value) if _zoom_allowed() else 1.0
	if held and settings.zoom and _zoom_allowed(): target_factor=float(settings.hold_zoom)
	if not is_instance_valid(camera): return
	if abs(factor-target_factor)>0.0001: set_process(true)

func _process(delta):
	if not is_instance_valid(camera):
		set_process(false)
		return
	if _blocked(): target_factor=1.0
	if bool(SavedSettings.get_value("workspace_reduced_motion",false)): factor=target_factor
	else: factor=lerp(factor,target_factor,1.0-exp(-float(settings.smoothness)*delta))
	if abs(factor-target_factor)<0.0001:
		factor=target_factor
		set_process(false)
	camera.z_factor=native_factor*factor

func _input(event):
	# Releases must arrive even when another control consumes the key event.
	if held and event is InputEventKey and not event.pressed and tool_ref._keybinds!=null and event.scancode==tool_ref._keybinds.key_event("view_zoom_hold").scancode:
		held=false
		_update_zoom()

func _unhandled_input(event):
	if not _zoom_allowed() or _menu_visible(): return
	if tool_ref._keybinds!=null and tool_ref._keybinds.typing(): return
	if event is InputEventMouseButton and event.pressed and settings.wheel and event.button_index in [BUTTON_WHEEL_UP,BUTTON_WHEEL_DOWN]:
		set_option("zoom_value",float(settings.zoom_value)*pow(1.10,-1 if event.button_index==BUTTON_WHEEL_UP else 1))
		get_tree().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and tool_ref._keybinds!=null:
		if settings.zoom and tool_ref._keybinds.matches(event,"view_zoom_hold"):
			held=true
			_update_zoom()
			get_tree().set_input_as_handled()
		elif tool_ref._keybinds.matches(event,"view_zoom_reset"):
			set_option("zoom_value",1.0)
			get_tree().set_input_as_handled()

func _notification(what):
	if what==MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		held=false
		_update_zoom()

func restore_native_presentation():
	if is_instance_valid(camera): camera.z_factor=native_factor
	camera=null
	factor=1.0
	target_factor=1.0
	held=false
	pending_target=0
	set_process(false)
	if is_instance_valid(spectator_panel): spectator_panel.hide()

func _exit_tree():
	if is_instance_valid(camera): camera.z_factor=native_factor

func _font(size):
	var face=DynamicFont.new()
	face.font_data=load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
	face.size=size
	face.use_filter=true
	return face

func _button_style(color):
	var style=StyleBoxFlat.new()
	style.bg_color=color
	style.border_color=Color("9fddff")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left=12
	style.content_margin_right=12
	style.content_margin_top=5
	style.content_margin_bottom=5
	return style

func _build_spectator():
	spectator_panel=PanelContainer.new()
	spectator_panel.add_stylebox_override("panel",_button_style(Color(0,0.12,0.23,0.94)))
	add_child(spectator_panel)
	var row=HBoxContainer.new()
	row.add_constant_override("separation",8)
	spectator_panel.add_child(row)
	player_picker=OptionButton.new()
	player_picker.rect_min_size=Vector2(210,36)
	player_picker.focus_mode=Control.FOCUS_NONE
	player_picker.add_font_override("font",_font(18))
	player_picker.get_popup().add_font_override("font",_font(18))
	player_picker.add_stylebox_override("normal",_button_style(Color("07426d")))
	player_picker.add_stylebox_override("hover",_button_style(Color("126093")))
	player_picker.add_stylebox_override("focus",StyleBoxEmpty.new())
	for state in ["font_color","font_color_hover","font_color_pressed"]: player_picker.add_color_override(state,Color.white)
	player_picker.connect("item_selected",self,"_choose_player")
	row.add_child(player_picker)
	for spec in [["−",1.1],["+",1.0/1.1],["Reset",0.0]]:
		var button=Button.new()
		button.text=spec[0]
		button.focus_mode=Control.FOCUS_NONE
		button.add_font_override("font",_font(18))
		button.add_stylebox_override("normal",_button_style(Color("07426d")))
		button.add_stylebox_override("hover",_button_style(Color("126093")))
		button.add_stylebox_override("pressed",_button_style(Color("00294a")))
		button.add_stylebox_override("focus",StyleBoxEmpty.new())
		for state in ["font_color","font_color_hover","font_color_pressed"]: button.add_color_override(state,Color.white)
		button.connect("pressed",self,"_zoom_button",[spec[1]])
		row.add_child(button)
	spectator_panel.hide()

func _spectating() -> bool:
	if not is_instance_valid(game) or game.is_game_over() or _blocked(): return false
	var data=game.wp_game_data
	if data.is_time_trial or data.is_replay or data.is_level_editor or data.is_tutorial: return false
	var player=game.get_local_player()
	return player!=null and (player.eliminated or player.rank!=0) and player.spectator_object_id>0

func _update_spectator():
	var shown=settings.standard and settings.spectator and _spectating() and not _menu_visible()
	spectator_panel.visible=shown
	if not shown:
		pending_target=0
		return
	var ids=[]
	var names=[]
	for i in game.get_player_count():
		var player=game.get_player_at_index(i)
		if player==null or player.eliminated or player.rank!=0 or not player.alive or player.type==NetworkPlayer.SPECTATOR: continue
		var info=game.get_metadata_for_player(player.object_id)
		ids.append(player.object_id)
		names.append(str(info.get("name","Goober")))
	var signature=str(ids)+str(names)
	if signature!=player_signature:
		player_signature=signature
		player_picker.clear()
		for i in ids.size():
			player_picker.add_item(names[i])
			player_picker.set_item_metadata(i,ids[i])
	var local=game.get_local_player()
	var selected=ids.find(local.spectator_object_id)
	if selected>=0: player_picker.select(selected)
	var view=get_viewport().get_visible_rect().size
	var physical_scale=max(0.01,abs(get_viewport().get_final_transform().get_scale().x))
	var scale=min(1.0/physical_scale,max(0.3,(view.x-20)/max(1,spectator_panel.rect_size.x)))
	spectator_panel.rect_scale=Vector2.ONE*scale
	spectator_panel.rect_position=Vector2((view.x-spectator_panel.rect_size.x*scale)/2,view.y-spectator_panel.rect_size.y*scale-24/physical_scale)

func _choose_player(index):
	if index<0 or index>=player_picker.get_item_count(): return
	pending_target=int(player_picker.get_item_metadata(index))
	pending_from=-1
	pending_at=0
	pending_steps=0
	_advance_target()

func _advance_target():
	if pending_target<=0: return
	if not _spectating():
		pending_target=0
		return
	var local=game.get_local_player()
	var player=game.get_player_for_object_id(pending_target)
	if player==null or player.eliminated or not player.alive or local.spectator_object_id==pending_target:
		pending_target=0
		return
	# Reuse the game's existing next-player action, waiting for each change.
	if local.spectator_object_id==pending_from:
		if OS.get_ticks_msec()-pending_at>2000: pending_target=0
		return
	if pending_steps>game.get_player_count()+1:
		pending_target=0
		return
	pending_from=local.spectator_object_id
	pending_at=OS.get_ticks_msec()
	pending_steps+=1
	game.client_send_message_to_server({"spectate_next":""})

func _zoom_button(value): set_option("zoom_value",float(settings.zoom_value)*value if value>0 else 1.0)

func _node_added(node):
	if node.name=="FreeWheelSpinNode": call_deferred("_remember_wheel",weakref(node))

func _scan_wheels(node):
	_node_added(node)
	for child in node.get_children(): _scan_wheels(child)

func _remember_wheel(reference):
	var node=reference.get_ref()
	if not is_instance_valid(node) or node.get_script()==null: return
	if not str(node.get_script().resource_path).ends_with("/FreeWheelSpinNode.gd"): return
	for known in wheel_nodes:
		if known.get_ref()==node: return
	wheel_nodes.append(reference)

func _reward_tick():
	if not settings.standard or not settings.free_spin: return
	if is_instance_valid(tool_ref.call("_find_game")) or _blocked(): return
	var context=_reward_context()
	if not context.get("signed_in",false):
		reward_status="Sign in to claim Free Spins"
		return
	if _menu_visible() or tool_ref.has_node("GoobOnboarding") or is_instance_valid(tool_ref.get("_tool_popup_layer")):
		reward_status="Ready after closing menus"
		return
	var account=str(context.get("account",""))
	if account!=reward_owner:
		reward_owner=account
		reward_dialog=null
		retry_at=0
	if is_instance_valid(reward_dialog):
		if reward_dialog.is_going_home:
			reward_dialog=null
			return
		var wheel=reward_dialog.wheel.wheel
		if reward_dialog.dialog.is_showing and not wheel.wheel_cards.cards.empty() and not wheel.is_running(): reward_dialog.on_next_button_pressed()
		if int(context.get("last_spin",0))>claim_at: reward_status="Free Spin collected"
		return
	if account.empty() or OS.get_ticks_msec()<retry_at: return
	var live=[]
	for reference in wheel_nodes:
		var node=reference.get_ref()
		if is_instance_valid(node): live.append(reference)
	wheel_nodes=live
	for reference in wheel_nodes:
		var node=reference.get_ref()
		if not node.is_visible_in_tree() or node.button==null or node.button.disabled: continue
		var scene=get_tree().current_scene
		if scene==null: return
		for child in scene.get_children():
			if child is CanvasLayer and child.get("dialog")!=null: return
		claim_at=int(context.get("last_spin",0))
		retry_at=OS.get_ticks_msec()+60000
		var before=scene.get_child_count()
		node.on_button_pressed()
		if scene.get_child_count()>before:
			var added=scene.get_child(scene.get_child_count()-1)
			if added is FreeSpinDialog: reward_dialog=added
		reward_status="Collecting Free Spin…"
		return

func _reward_context() -> Dictionary:
	var moon=get_node_or_null("/root/Moonlight")
	if moon==null or not moon.is_logged_in(): return {"signed_in":false}
	return {"signed_in":true,"account":str(moon.storage.storage_get("account.user.id","")),"last_spin":int(moon.storage.storage_get("player.profile.last_free_spin_time",0))}

func _menu_visible() -> bool:
	if not is_instance_valid(tool_ref) or not bool(tool_ref.get("_menu_open")) or bool(tool_ref.get("_overlay_hidden")): return false
	var window=tool_ref.get("_menu_window")
	return not is_instance_valid(window) or window.is_visible_in_tree()
