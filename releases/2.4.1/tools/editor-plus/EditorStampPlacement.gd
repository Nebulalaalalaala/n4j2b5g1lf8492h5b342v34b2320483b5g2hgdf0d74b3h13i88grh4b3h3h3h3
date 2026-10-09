extends Node
# Disabled native preview objects. Nothing enters Level's node map or Undo
# until the final click; clipboard and selected level objects are untouched.
var stamps
var editor
var payload = {}
var ghosts = []
var ghost_root
var capture
var bounds = Rect2()
var target = Vector2.ZERO
var old_process = {}
var active = false

func begin(data) -> bool:
	if not stamps.host.available() or not stamps.store.valid(data):
		queue_free()
		return false
	editor = stamps.host.editor
	payload = data.duplicate(true)
	ghost_root = Node2D.new()
	ghost_root.name = "EditorStampGhost"
	ghost_root.modulate = Color(1,1,1,.48)
	ghost_root.z_index = 150
	editor.level.add_child(ghost_root)
	for native_tool in [editor.tool_select,editor.tool_create]:
		old_process[native_tool.get_instance_id()] = {"process":native_tool.is_processing(),"input":native_tool.is_processing_input()}
		native_tool.set_process(false)
		native_tool.set_process_input(false)
		native_tool.is_mouse_down = false
		native_tool.was_mouse_down = false
	capture = Control.new()
	capture.name = "StampPlacementInput"
	capture.mouse_default_cursor_shape = Control.CURSOR_CROSS
	editor.ui_root.add_child(capture)
	# The native inspector is also inside EditorViewport. Keep it above the
	# placement input surface so rotate/flip/cancel and other UI stay clickable.
	editor.ui_root.move_child(capture,0)
	capture.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	capture.connect("gui_input",self,"_event")
	capture.focus_mode = Control.FOCUS_ALL
	capture.grab_focus()
	editor.level.connect("unloading_level",self,"cancel")
	active = true
	_rebuild()
	target = LevelGrid2.world_to_grid_rounded_2d(editor.level_editor_camera.get_camera_screen_center())
	_position()
	stamps.host.message.text = "Stamp preview: click the level to place · Esc cancels."
	return active

func _rebuild():
	for node in ghosts:
		ghost_root.remove_child(node)
		node.free()
	ghosts.clear()
	for data in payload.nodes:
		var node = LevelJson.deserialize_level_node(data.duplicate(true),editor.node_factory)
		if node == null:
			cancel()
			return
		_disable_bodies(node)
		ghost_root.add_child(node)
		# Native _ready normalizes sub-cell shapes. Restore after entering the
		# tree, exactly as the committed Editor+ paste repair does.
		stamps.host.geometry.restore(node,data)
		_disable_bodies(node)
		node.apply_theme(editor.level.level_theme)
		ghosts.append(node)
		bounds = node.grid_rect if ghosts.size()==1 else bounds.merge(node.grid_rect)
	_position()

func _disable_bodies(node):
	# Both rigid objects and static hazards/sensors must be inert. Inspect
	# properties instead of depending on a custom engine class-name alias.
	if node is LevelNode and node.body != null: node.body.enabled = false
	for child in node.get_children(): _disable_bodies(child)

func _position():
	if not is_instance_valid(ghost_root): return
	var offset = target-Vector2(round(bounds.size.x*.5),round(bounds.size.y*.5))-bounds.position
	ghost_root.position = LevelGrid2.grid_rect_to_world_rect(Rect2(offset,Vector2.ONE)).position

func _process(_delta):
	if not active: return
	if not stamps.host.available() or editor != stamps.host.editor:
		cancel()
		return
	ghost_root.visible = editor.is_mouse_present
	if editor.is_mouse_present:
		target = LevelGrid2.world_to_grid_rounded_2d(editor.level.get_local_mouse_position())
		_position()

func _input(event):
	if active and event is InputEventKey and event.pressed and not event.echo and event.scancode==KEY_ESCAPE:
		cancel()
		get_tree().set_input_as_handled()

func _event(event):
	if not active: return
	if event is InputEventMouseButton:
		capture.accept_event()
		if event.button_index==BUTTON_LEFT and event.pressed:
			target = LevelGrid2.world_to_grid_rounded_2d(editor.level.get_local_mouse_position())
			var saved_payload = payload.duplicate(true)
			var saved_target = target
			cancel()
			stamps.place(saved_payload,saved_target)
		elif event.button_index in [BUTTON_WHEEL_UP,BUTTON_WHEEL_DOWN,BUTTON_MIDDLE]:
			editor.on_ui_root_gui_input(event)
		elif event.button_index==BUTTON_RIGHT and event.pressed: cancel()

func transform_preview(action):
	if not active: return
	var horizontal = action=="horizontal"
	if action!="rotate":
		for node in ghosts:
			if not stamps.host.mirrorable_animation(node):
				stamps.host.message.text = "This animation cannot be safely flipped. Preview unchanged."
				return
	for data in payload.nodes:
		var shape = int(data.get("shape_rotation",0))
		if action=="rotate":
			data.shape_rotation = posmod(shape+1,4)
			continue
		var rect = Rect2(data.x,data.y,data.width,data.height)
		if horizontal:
			data.x = bounds.position.x+bounds.end.x-rect.end.x
			data.pivot_x = 1.0-float(data.get("pivot_x",.5))
		else:
			data.y = bounds.position.y+bounds.end.y-rect.end.y
			data.pivot_y = 1.0-float(data.get("pivot_y",.5))
		data.rotation = -float(data.get("rotation",0))
		var base = (3 if horizontal else 1) if data.type in ["ramp","background_ramp","background_ramp2"] else (0 if horizontal else 2)
		if data.type=="laser": base = 2 if horizontal else 0
		data.shape_rotation = posmod(base-shape,4)
	for i in ghosts.size():
		if action!="rotate" and ghosts[i].animation != null:
			var reflected = stamps.host.mirror_animation(ghosts[i].animation.animation_data,horizontal)
			ghosts[i].animation.set_animation_data(reflected)
			payload.nodes[i].animation = ghosts[i].serialize_level_node().animation
	_rebuild()

func cancel():
	if not active: return
	active = false
	stamps._refresh_preview_buttons()
	if is_instance_valid(editor):
		for native_tool in [editor.tool_select,editor.tool_create]:
			native_tool.is_mouse_down = false
			native_tool.was_mouse_down = false
			var saved = old_process.get(native_tool.get_instance_id(),{"process":true,"input":true})
			native_tool.set_process(saved.process)
			native_tool.set_process_input(saved.input)
		if editor.level.is_connected("unloading_level",self,"cancel"):
			editor.level.disconnect("unloading_level",self,"cancel")
	if is_instance_valid(ghost_root): ghost_root.queue_free()
	if is_instance_valid(capture): capture.queue_free()
	stamps.host.message.text = "Stamp preview cancelled. Level unchanged."
	queue_free()

func _exit_tree():
	if active: cancel()
