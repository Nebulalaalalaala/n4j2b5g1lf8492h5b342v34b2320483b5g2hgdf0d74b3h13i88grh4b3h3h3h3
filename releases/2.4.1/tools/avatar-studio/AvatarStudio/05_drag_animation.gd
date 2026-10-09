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
	stage.pan = Vector2.ZERO
	stage.update()
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
	var avatar = goober
	var layers = goober.get_node_or_null("LocalCosmeticLayers")
	if layers != null and layers.avatars.has(id): avatar = layers.avatars[id]
	var renderer = avatar.get_node_or_null("LocalCosmeticTransforms")
	if renderer == null:
		renderer = load(ModPaths.COSMETIC_TRANSFORMS).new()
		renderer.name = "LocalCosmeticTransforms"
		avatar.add_child(renderer)
	var frame = renderer.item_frame(id)
	if frame.empty():
		var binding_key = str([id,avatar.goober_skin_data.hash(),item_transforms.hash()])
		if renderer.has_meta("studio_selection_binding") and renderer.get_meta("studio_selection_binding") == binding_key: return {}
		# An untouched item still needs a live frame for selection/first drag.
		# This default render binding never becomes a saved transform.
		var settings = item_transforms.duplicate(true)
		settings[id] = settings.get(id, {})
		renderer.configure(avatar, settings, sandbox.call("_all_cosmetics"))
		renderer.set_meta("studio_selection_binding",binding_key)
		frame = renderer.item_frame(id)
		if frame.empty(): return {}
	# The native wrapper exposes anchors but not vertices. Measure native
	# artwork once per item offscreen, never by GPU readback every frame.
	if not item_bounds.has(id):
		if not measuring_item and is_inside_tree():
			measuring_item = true
			call_deferred("_measure_item_bounds",id,skin)
		return {}
	var bounds: Rect2 = item_bounds[id]
	if bounds.size == Vector2.ZERO: return {}
	return {"id":id,"pivot":frame.pivot,"bounds":bounds,"frame":frame.frame,"warp":frame.warp}

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
	var box: Rect2 = geometry.bounds
	var output = Rect2()
	var first = true
	for point in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
		var local = geometry.warp.xform(point)
		var screen = goober.transform.xform(local)
		if first:
			output = Rect2(screen,Vector2.ZERO)
			first = false
		else: output = output.expand(screen)
	return output

func _item_handles(box: Rect2) -> Array:
	# Large/low cosmetics keep reachable handles inside the preview.
	var points = []
	for corner in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
		points.append(Vector2(clamp(corner.x,8,max(8,stage.rect_size.x-8)),clamp(corner.y,8,max(8,stage.rect_size.y-8))))
	return points

func _begin_item_drag(point: Vector2) -> bool:
	var geometry = _item_geometry()
	if geometry.empty(): return false
	if abs(geometry.frame.x.cross(geometry.frame.y)) < 0.000001: return false
	var box = _item_box()
	var resize = false
	for corner in _item_handles(box):
		if point.distance_to(corner) <= 12: resize = true
	if not resize and not box.has_point(point): return false
	if not item_transforms.has(geometry.id) and item_transforms.size() >= 64: return false
	var state = item_transforms.get(geometry.id,{}).duplicate(true)
	var pivot = geometry.pivot
	item_drag = {"id":geometry.id,"point":point,"state":state,"pivot":pivot,"frame":geometry.frame,"resize":resize,"update_mode":goober.get_update_mode()}
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
		var delta = item_drag.frame.affine_inverse().basis_xform(goober.transform.affine_inverse().basis_xform(point-item_drag.point))/10.0
		state.x = clamp(float(state.get("x",0))+delta.x,-100,100)
		state.y = clamp(float(state.get("y",0))+delta.y,-100,100)
	item_transforms[item_drag.id] = state
	# Update only the preview materials while dragging; save/undo once on release.
	var avatar = goober
	var layers = goober.get_node_or_null("LocalCosmeticLayers")
	if layers != null and layers.avatars.has(item_drag.id): avatar = layers.avatars[item_drag.id]
	var renderer = avatar.get_node_or_null("LocalCosmeticTransforms")
	if renderer != null:
		renderer.update_item(item_drag.id, state)
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
		if not playable and event.button_index == BUTTON_MIDDLE:
			dragging_preview = event.pressed
			preview_drag_button = BUTTON_MIDDLE
			preview_drag_tilt = false
			stage.accept_event()
			return
		if event.button_index == BUTTON_LEFT:
			if not event.pressed and not item_drag.empty():
				_end_item_drag()
				stage.accept_event()
				return
			if event.pressed and not event.alt and _begin_item_drag(event.position):
				stage.accept_event()
				return
			dragging_preview = event.pressed
			preview_drag_button = BUTTON_LEFT
			preview_drag_tilt = event.alt
		if event.pressed and event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			if not item_drag.empty(): return
			_zoom(0.1 if event.button_index == BUTTON_WHEEL_UP else -0.1)
	elif event is InputEventMouseMotion and not item_drag.empty():
		_move_item_drag(event.position)
		stage.accept_event()
	elif event is InputEventMouseMotion and dragging_preview and not playable:
		if event.shift and category in ["hat", "suit", "hand"] and not _transform_id().empty() and transform_fields.x.editable:
			var offset = goober.transform.affine_inverse().basis_xform(event.relative) / 10.0
			var geometry = _item_geometry()
			if not geometry.empty() and abs(geometry.frame.x.cross(geometry.frame.y)) > 0.000001:
				offset = geometry.frame.affine_inverse().basis_xform(offset)
			_transform_changed(clamp(transform_fields.x.value + offset.x, -100, 100), "x")
			_transform_changed(clamp(transform_fields.y.value + offset.y, -100, 100), "y")
			stage.accept_event()
			return
		if preview_drag_tilt:
			tilt = clamp(tilt + event.relative.x * 0.3, -30, 30)
		else:
			preview_pan += event.relative
		_position_preview()
		stage.accept_event()

# Continue a started drag across the floor decoration and neighbouring controls.
# Only acquisition uses the Stage hit-test; movement has pointer capture.
func _input(event: InputEvent) -> void:
	if not is_instance_valid(stage): return
	if item_drag.empty():
		if not dragging_preview or playable: return
		if event is InputEventMouseMotion:
			if preview_drag_tilt:
				tilt = clamp(tilt + event.relative.x * 0.3, -30, 30)
			elif event.shift and preview_drag_button == BUTTON_LEFT:
				# Preserve the existing Shift-drag cosmetic adjustment path.
				return
			else:
				preview_pan += stage.get_global_transform_with_canvas().affine_inverse().basis_xform(event.relative)
			_position_preview()
			get_tree().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == preview_drag_button and not event.pressed:
			dragging_preview = false
			get_tree().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_move_item_drag(stage.get_global_transform_with_canvas().affine_inverse().xform(event.position))
		get_tree().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
		_end_item_drag()
		get_tree().set_input_as_handled()

func _process(delta: float) -> void:
	if not item_drag.empty() and not Input.is_mouse_button_pressed(BUTTON_LEFT):
		_end_item_drag()
	if dragging_preview and not Input.is_mouse_button_pressed(preview_drag_button):
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
	goober.scale = Vector2(facing, 1) * 0.13 * avatar_size
