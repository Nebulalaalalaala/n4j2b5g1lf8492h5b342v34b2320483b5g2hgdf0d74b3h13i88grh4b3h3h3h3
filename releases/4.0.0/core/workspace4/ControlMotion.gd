extends Node
# One event-driven animator for mod controls. No full-tree scan each frame.
# Slider/input geometry never scales, keeping drag and text coordinates stable.
var bindings = {}

static func bind_control(control):
	if not control is Control or control.get_tree()==null: return
	if not control is BaseButton and not control is Range and not control is LineEdit: return
	var tree = control.get_tree()
	var motion = tree.root.get_node_or_null("GoobControlMotion")
	if motion==null:
		motion = load("user://mod/core/workspace4/ControlMotion.gd").new()
		motion.name = "GoobControlMotion"
		motion.pause_mode = Node.PAUSE_MODE_PROCESS
		tree.root.add_child(motion)
	motion.watch(control)

func watch(control):
	var id = control.get_instance_id()
	if bindings.has(id): return
	bindings[id] = {"ref":weakref(control),"scale":control.rect_scale,"color":control.modulate,"hover":false,"focus":false,"down":false,"tween":null}
	control.connect("mouse_entered",self,"_state",[true,"hover",id])
	control.connect("mouse_exited",self,"_state",[false,"hover",id])
	control.connect("focus_entered",self,"_state",[true,"focus",id])
	control.connect("focus_exited",self,"_state",[false,"focus",id])
	control.connect("tree_exiting",self,"_forget",[id])
	if control is BaseButton:
		control.connect("button_down",self,"_state",[true,"down",id])
		control.connect("button_up",self,"_state",[false,"down",id])
		if control.toggle_mode: control.connect("toggled",self,"_pulse",[id])
	elif control is Range: control.connect("value_changed",self,"_pulse",[id])

func _allowed():
	return not bool(SavedSettings.get_value("workspace_reduced_motion",false)) and bool(SavedSettings.get_value("workspace_control_motion",true))

func _stop(state):
	if is_instance_valid(state.tween):
		state.tween.stop_all()
		state.tween.queue_free()
	state.tween = null

func _state(value,key,id):
	if not bindings.has(id): return
	var state = bindings[id]
	state[key] = value
	_animate(id,false)

func _pulse(_value,id):
	if not bindings.has(id): return
	var control = bindings[id].ref.get_ref()
	if control is Range and not bindings[id].hover and not bindings[id].focus: return
	_animate(id,true)

func _animate(id,pulse):
	if not bindings.has(id): return
	var state = bindings[id]
	var control = state.ref.get_ref()
	if not is_instance_valid(control):
		_forget(id)
		return
	_stop(state)
	if not _allowed() or not control.is_visible_in_tree():
		control.rect_scale = state.scale
		control.modulate = state.color
		return
	var target = state.scale
	if control is BaseButton:
		control.rect_pivot_offset = control.rect_size*0.5
		target *= 0.975 if state.down else (1.012 if state.hover or state.focus else 1.0)
	var color = state.color
	if state.hover or state.focus: color = Color(color.r*1.035,color.g*1.035,color.b*1.035,color.a)
	if pulse: control.modulate = Color(state.color.r*1.10,state.color.g*1.10,state.color.b*1.10,state.color.a)
	var tween = Tween.new()
	add_child(tween)
	state.tween = tween
	var duration = 0.08 if state.down else 0.16
	if control is BaseButton: tween.interpolate_property(control,"rect_scale",control.rect_scale,target,duration,Tween.TRANS_QUAD,Tween.EASE_OUT)
	tween.interpolate_property(control,"modulate",control.modulate,color,duration,Tween.TRANS_SINE,Tween.EASE_OUT)
	tween.connect("tween_all_completed",self,"_finished",[id,tween])
	tween.start()

func _finished(id,tween):
	if bindings.has(id) and bindings[id].tween==tween: bindings[id].tween = null
	if is_instance_valid(tween): tween.queue_free()

func _forget(id):
	if not bindings.has(id): return
	var state = bindings[id]
	_stop(state)
	var control = state.ref.get_ref()
	if is_instance_valid(control):
		control.rect_scale = state.scale
		control.modulate = state.color
		# Reparented views may enter the tree again. Remove old connections,
		# retaining no stale target or duplicate motion handlers.
		for pair in [["mouse_entered","_state"],["mouse_exited","_state"],["focus_entered","_state"],["focus_exited","_state"],["button_down","_state"],["button_up","_state"],["toggled","_pulse"],["value_changed","_pulse"],["tree_exiting","_forget"]]:
			if control.has_signal(pair[0]) and control.is_connected(pair[0],self,pair[1]): control.disconnect(pair[0],self,pair[1])
	bindings.erase(id)

func _exit_tree():
	for id in bindings.keys(): _forget(id)
