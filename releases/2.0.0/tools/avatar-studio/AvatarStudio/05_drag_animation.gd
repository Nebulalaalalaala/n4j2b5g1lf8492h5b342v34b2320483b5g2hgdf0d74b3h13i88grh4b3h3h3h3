extends "user://mod/tools/avatar-studio/AvatarStudio/04_look_import.gd"

func _pause_animation() -> void:
	animation_paused = not animation_paused
	if goober != null:
		var state = goober.call("get_animation_state")
		if state != null and state.has_method("set_time_scale"):
			state.call("set_time_scale", 0.0 if animation_paused else 1.0)
		else:
			animation_paused = false
			status.text = "This renderer does not expose animation pause."

func _restart_animation() -> void:
	_animate(animation)

func _toggle_loop() -> void:
	animation_loop = not animation_loop
	_restart_animation()
	status.text = "Animation loop " + ("on" if animation_loop else "off")

func _environment(name: String) -> void:
	stage.background = {"Neutral": Color("202b30"), "Bright": Color("c8d4cf"), "Dark": Color("0d1219")}[name]
	stage.update()

func _compare(held: bool) -> void:
	if goober != null:
		preview_skin_override = session_start.duplicate(true) if held else {}
		_render_look(goober, session_start if held else capture())

func _fullscreen() -> void:
	full_preview = not full_preview
	right_column.visible = not full_preview

func _toggle_playable() -> void:
	if playable:
		_exit_playable()
		return
	if tool_ref != null and tool_ref.call("_find_game") != null:
		status.text = "Leave the active run before entering playable preview."
		return
	playable = true
	preview_position = Vector2(stage.rect_size.x / 2, stage.rect_size.y - 65)
	preview_velocity = Vector2.ZERO
	grounded = true
	stage.grab_focus()
	status.text = "Preview active · A/D run · W jump · Space dash"

func _exit_playable() -> void:
	playable = false
	keys.clear()
	preview_velocity = Vector2.ZERO
	dash_time = 0.0
	if stage != null:
		stage.release_focus()
	_position_preview()

func _item_geometry() -> Dictionary:
	if playable or not category in ["hat", "suit", "hand"] or not is_instance_valid(goober) or sandbox == null:
		return {}
	var id = _transform_id()
	var data = sandbox.call("_all_cosmetics").get(id, {})
	var skin = goober.skeleton_data_res.find_skin(str(data.get("spine", "")))
	if skin == null: return {}
	var slots = goober.get_skeleton().get_slots()
	var points = []
	var pivot = Vector2.ZERO
	for entry in skin.get_attachments():
		var index = entry.get_slot_index()
		if index < 0 or index >= slots.size(): continue
		var slot = slots[index]
		var attachment = slot.get_attachment()
		if attachment == null or attachment.get_attachment_name() != entry.get_attachment().get_attachment_name(): continue
		var bone = slot.get_bone()
		var point = Vector2(bone.get_world_x(), -bone.get_world_y())
		if points.empty() or slot.get_data().get_name() in ["BODY", "SUIT", "HEADS", "HANDS"]: pivot = point
		points.append(point)
	if points.empty(): return {}
	# The native wrapper exposes anchors but not vertices. Measure native
	# artwork once per item offscreen, never by GPU readback every frame.
	if not item_bounds.has(id):
		if not measuring_item and is_inside_tree():
			measuring_item = true
			call_deferred("_measure_item_bounds",id,skin)
		return {}
	var bounds: Rect2 = item_bounds[id]
	if bounds.size == Vector2.ZERO: return {}
	return {"id":id,"pivot":pivot,"bounds":bounds}

func _measure_item_bounds(id: String, skin) -> void:
	var viewport = Viewport.new()
	viewport.size = Vector2(512,512)
	viewport.transparent_bg = true
	viewport.render_target_v_flip = true
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(viewport)
	var avatar = load("res://project_specific/gfx/spine/upguy/upguy.tscn").instance()
	avatar.enable_sounds = false
	avatar.enable_blink = false
	viewport.add_child(avatar)
	avatar.set_update_mode(2)
	avatar.position = Vector2(256,400)
	avatar.scale = Vector2(.1,.1)
	var combined = avatar.new_skin("studio_measure")
	combined.copy_skin(avatar.skeleton_data_res.find_skin("body/Normal"))
	combined.copy_skin(skin)
	avatar.get_skeleton().set_skin(combined)
	avatar.get_skeleton().set_slots_to_setup_pose()
	avatar.update_skeleton(0)
	var owned = {}
	for entry in skin.get_attachments(): owned[str(entry.get_slot_index())+":"+entry.get_attachment().get_attachment_name()] = true
	var invisible = ShaderMaterial.new()
	var hide_shader = Shader.new()
	hide_shader.code = "shader_type canvas_item; void fragment(){ COLOR=vec4(0.0); }"
	invisible.shader = hide_shader
	var slots = avatar.get_skeleton().get_slots()
	for index in range(slots.size()):
		var slot = slots[index]
		var attachment = slot.get_attachment()
		if attachment != null and owned.has(str(index)+":"+attachment.get_attachment_name()): continue
		var node = ClassDB.instance("SpineSlotNode")
		avatar.add_child(node)
		node.slot_name = slot.get_data().get_name()
		node.normal_material = invisible
	for _frame in range(2):
		yield(get_tree(),"idle_frame")
		yield(VisualServer,"frame_post_draw")
	var rect = viewport.get_texture().get_data().get_used_rect()
	item_bounds[id] = Rect2()
	if rect.size != Vector2.ZERO:
		item_bounds[id] = Rect2((rect.position-avatar.position)/.1,rect.size/.1).grow(20)
	viewport.queue_free()
	measuring_item = false
	if is_instance_valid(transform_gizmo): transform_gizmo.update()

func _item_box() -> Rect2:
	var geometry = _item_geometry()
	if geometry.empty(): return Rect2()
	var state = item_transforms.get(geometry.id,{})
	var offset = Vector2(state.get("x",0),state.get("y",0))*10
	var box: Rect2 = geometry.bounds
	var output = Rect2()
	var first = true
	for point in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
		var local = (point-geometry.pivot).rotated(deg2rad(state.get("rotation",0)))*float(state.get("scale",1))+geometry.pivot+offset
		var screen = goober.transform.xform(local)
		if first:
			output = Rect2(screen,Vector2.ZERO)
			first = false
		else: output = output.expand(screen)
	return output

func _begin_item_drag(point: Vector2) -> bool:
	var geometry = _item_geometry()
	if geometry.empty(): return false
	var box = _item_box()
	var resize = false
	for corner in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
		if point.distance_to(corner) <= 12: resize = true
	if not resize and not box.has_point(point): return false
	if not item_transforms.has(geometry.id) and item_transforms.size() >= 64: return false
	var state = item_transforms.get(geometry.id,{}).duplicate(true)
	var pivot = geometry.pivot + Vector2(state.get("x",0),state.get("y",0))*10
	item_drag = {"id":geometry.id,"point":point,"state":state,"pivot":pivot,"resize":resize,"update_mode":goober.get_update_mode()}
	goober.set_update_mode(2)
	item_transforms[geometry.id] = state.duplicate(true)
	apply_effects(goober)
	return true

func _move_item_drag(point: Vector2) -> void:
	var state: Dictionary = item_drag.state.duplicate(true)
	if item_drag.resize:
		var start = goober.transform.affine_inverse().xform(item_drag.point)-item_drag.pivot
		var current = goober.transform.affine_inverse().xform(point)-item_drag.pivot
		state.scale = clamp(float(state.get("scale",1))*current.length()/max(1.0,start.length()),0.1,4.0)
	else:
		var delta = goober.transform.affine_inverse().basis_xform(point-item_drag.point)/10.0
		state.x = clamp(float(state.get("x",0))+delta.x,-100,100)
		state.y = clamp(float(state.get("y",0))+delta.y,-100,100)
	item_transforms[item_drag.id] = state
	# Update only the preview materials while dragging; save/undo once on release.
	var renderer = goober.get_node_or_null("LocalCosmeticTransforms")
	if renderer != null:
		for binding in renderer.bindings:
			if binding.id != item_drag.id: continue
			binding.material.set_shader_param("cosmetic_offset",Vector2(state.get("x",0),state.get("y",0))*10)
			binding.material.set_shader_param("cosmetic_scale",float(state.get("scale",1)))
	_refresh_transforms()
	if is_instance_valid(transform_gizmo): transform_gizmo.update()

func _end_item_drag() -> void:
	if item_drag.empty(): return
	if is_instance_valid(goober): goober.set_update_mode(item_drag.update_mode)
	item_drag = {}
	dragging_preview = false
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change",false)

func _stage_input(event: InputEvent) -> void:
	if playable and event is InputEventKey:
		keys[event.scancode] = event.pressed
		if event.pressed and not event.echo:
			if event.scancode in [KEY_W, KEY_UP] and grounded:
				preview_velocity.y = -560
				grounded = false
			if event.scancode == KEY_SPACE and dash_time <= 0:
				dash_time = 0.16
		stage.accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if not event.pressed and not item_drag.empty():
				_end_item_drag()
				stage.accept_event()
				return
			if event.pressed and _begin_item_drag(event.position):
				stage.accept_event()
				return
			dragging_preview = event.pressed
		if event.pressed and event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			if not item_drag.empty(): return
			_zoom(0.1 if event.button_index == BUTTON_WHEEL_UP else -0.1)
	elif event is InputEventMouseMotion and not item_drag.empty():
		_move_item_drag(event.position)
		stage.accept_event()
	elif event is InputEventMouseMotion and dragging_preview and not playable:
		if event.shift and category in ["hat", "suit", "hand"] and not _transform_id().empty() and transform_fields.x.editable:
			var offset = goober.transform.affine_inverse().basis_xform(event.relative) / 10.0
			_transform_changed(clamp(transform_fields.x.value + offset.x, -100, 100), "x")
			_transform_changed(clamp(transform_fields.y.value + offset.y, -100, 100), "y")
			stage.accept_event()
			return
		tilt = clamp(tilt + event.relative.x * 0.3, -30, 30)
		_position_preview()

func _process(delta: float) -> void:
	if not item_drag.empty() and not Input.is_mouse_button_pressed(BUTTON_LEFT):
		_end_item_drag()
	if dragging_preview and not Input.is_mouse_button_pressed(BUTTON_LEFT):
		dragging_preview = false
	if sandbox == null or not sandbox.get("_modal_root").visible:
		if is_instance_valid(effect_preview):
			effect_preview.queue_free()
			effect_preview = null
		if playable:
			_exit_playable()
		return
	if is_instance_valid(transform_gizmo): transform_gizmo.update()
	if goober != null:
		if not is_instance_valid(effect_preview):
			effect_preview = load(ModPaths.path("MovementEffects.gd")).new()
			stage.add_child(effect_preview)
		effect_preview.configure(preview_skin_override.get("effects", effect_settings))
		effect_preview.sample(goober.position, dash_time > 0 if playable else effects_mode, preview_velocity.length_squared() > 625 if playable else effects_mode)
	if not playable or goober == null:
		return
	if tool_ref != null and tool_ref.call("_find_game") != null:
		_exit_playable()
		return
	if not stage.has_focus():
		keys.clear()
	delta = min(delta, 0.04)
	var direction = int(keys.get(KEY_D, false) or keys.get(KEY_RIGHT, false)) - int(keys.get(KEY_A, false) or keys.get(KEY_LEFT, false))
	if direction != 0:
		facing = -float(direction)
	preview_velocity.x = direction * 250.0
	preview_velocity.y += 1500 * delta
	var next_animation = "Idle" if grounded and direction == 0 else "Run"
	if not grounded:
		next_animation = "Jump" if preview_velocity.y < 0 else "Fall"
	if dash_time > 0:
		dash_time -= delta
		preview_velocity = Vector2(-facing * 700, 0)
		next_animation = "Dash"
	preview_position += preview_velocity * delta
	preview_position.x = clamp(preview_position.x, 45, stage.rect_size.x - 45)
	var floor_y = stage.rect_size.y - 65
	if preview_position.y >= floor_y:
		preview_position.y = floor_y
		preview_velocity.y = 0
		grounded = true
	if animation != next_animation:
		_animate(next_animation)
	goober.position = preview_position
	goober.scale = Vector2(facing, 1) * 0.13
