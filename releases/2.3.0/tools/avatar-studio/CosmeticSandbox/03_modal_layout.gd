extends "user://mod/tools/avatar-studio/CosmeticSandbox/02_goober_skin.gd"

func _apply_body_slot_gradient_row(goober, atlas_height: int) -> void:
	if atlas_height <= 1:
		return
	var skeleton = goober.call("get_skeleton")
	if skeleton == null:
		return
	var original_height := atlas_height - 1
	for value in skeleton.get_slots():
		var slot: SpineSlot = value
		var attachment = slot.get_attachment()
		if attachment == null:
			continue
		var attachment_name: String = attachment.get_attachment_name().to_lower()
		if attachment_name.find("-tint") < 0:
			continue
		var slot_color: Color = slot.get_color()
		if attachment_name.find("body-tint") >= 0:
			slot_color.g = (float(atlas_height - 1) + 0.5) / float(atlas_height)
		else:
			var original_row := clamp(int(floor(slot_color.g * original_height)), 0, original_height - 1)
			slot_color.g = (float(original_row) + 0.5) / float(atlas_height)
		slot.set_color(slot_color)


func _apply_body_effect_colors(goober) -> void:
	var renderer = _renderer_by_goober_id.get(goober.get_instance_id(), null)
	if renderer == null or not is_instance_valid(renderer):
		return
	var primary: Color = goober.call("get_tint")
	var dark: Color = goober.call("get_dark_tint")
	var particle_color := primary.lightened(0.2)
	_set_property_if_present(renderer, "particles_color", particle_color)
	_set_canvas_color(renderer.get_node_or_null("Position/LandingParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/JumpParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/SpineHolder/WallSlideParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/SpineHolder/FloorDust"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/GravityFieldEnterExitParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/GravityFieldLoopParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/DashTrailParticles"), particle_color, true)
	_set_canvas_color(renderer.get_node_or_null("Position/DashCharge"), particle_color, true)
	var cooldown = renderer.get_node_or_null("UIHolder/UI/DashCooldown")
	if cooldown != null:
		cooldown.set("tint_progress", primary)
		cooldown.set("tint_under", dark)
	var dash_trail = renderer.get_node_or_null("DashTrail")
	if dash_trail != null and dash_trail.get("material") is ShaderMaterial:
		dash_trail.get("material").set_shader_param("dash_color", primary)


func _set_canvas_color(node, color: Color, use_self_modulate: bool) -> void:
	if node == null or not (node is CanvasItem):
		return
	if use_self_modulate:
		node.self_modulate = color
	else:
		node.modulate = color


func _set_property_if_present(object, property_name: String, value) -> void:
	if object == null:
		return
	for property in object.get_property_list():
		if property.get("name", "") == property_name:
			object.set(property_name, value)
			return


func _restore_original_material(goober) -> void:
	var original = _original_materials.get(goober.get_instance_id(), null)
	if original == null:
		return
	goober.set("normal_material", original)
	if goober.get("gradient_material") != null:
		goober.set("gradient_material", original)


func _restore_all_registered_goobers() -> void:
	var profile = Moonlight.storage.storage_get("player.profile.skin", {})
	if typeof(profile) != TYPE_DICTIONARY:
		profile = {}
	for goober in _registered_goobers:
		if not is_instance_valid(goober):
			continue
		_restore_original_material(goober)
		var layers = goober.get_node_or_null("LocalCosmeticLayers")
		if layers != null: layers.clear()
		if goober.has_meta("studio_size"):
			goober.scale /= max(0.1,float(goober.get_meta("studio_size")))
			goober.remove_meta("studio_size")
		goober.call("set_goober_skin_data", profile)
		goober.call("apply_skin_data")
		if goober.has_method("update_skeleton"):
			goober.call("update_skeleton", 0.0)
		_apply_body_effect_colors(goober)
	_applied_signatures.clear()


func _attach_to_skin_selector(selector: Node) -> void:
	if selector == null or not is_instance_valid(selector):
		return
	_skin_selector = selector
	# Keep discovery for local rendering, but launch only through Workspace.
	var existing = selector.get_node_or_null("CosmeticSandboxButton")
	if existing != null:
		existing.hide()
		_avatar_button = existing


func _build_modal() -> void:
	_modal_root = Control.new()
	_modal_root.name = "CosmeticSandboxModal"
	_modal_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	dim.color = Color(0.015, 0.025, 0.08, 0.10)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.add_child(dim)

	_modal_panel = PanelContainer.new()
	_modal_panel.anchor_left = 0.055
	_modal_panel.anchor_top = 0.035
	_modal_panel.anchor_right = 0.945
	_modal_panel.anchor_bottom = 0.965
	_modal_panel.add_stylebox_override("panel", _flat_style(NAVY, Color(0.49, 0.78, 1.0, 0.9), 6, 34))
	_modal_root.add_child(_modal_panel)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 26)
	margin.add_constant_override("margin_right", 26)
	margin.add_constant_override("margin_top", 22)
	margin.add_constant_override("margin_bottom", 22)
	var modal_scroll := ScrollContainer.new()
	modal_scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	modal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_panel.add_child(modal_scroll)
	modal_scroll.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_constant_override("separation", 14)
	margin.add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_constant_override("separation", 12)
	root_vbox.add_child(header)
	_claude_title_icon = TextureRect.new()
	_claude_title_icon.expand = true
	_claude_title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_claude_title_icon.rect_min_size = Vector2(40, 40)
	_claude_title_icon.visible = false
	header.add_child(_claude_title_icon)
	var title := _make_label("COSMETIC SANDBOX", _title_font, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Phase 0.2 -- Universal Movable & Resizable GUI. A plain Label defaults to
	# MOUSE_FILTER_IGNORE in Godot 3.x, so it never received the gui_input
	# events _on_modal_move_gui_input() below was already listening for --
	# this connect() call was wired up but could never fire. That's the whole
	# reason dragging the Sandbox by its title never worked.
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.hint_tooltip = "Drag to move the Sandbox window."
	title.connect("gui_input", self, "_on_modal_move_gui_input")
	header.add_child(title)
	var local_badge := _make_label("  LOCAL ONLY  ", _small_font, Color(0.72, 1.0, 0.87))
	local_badge.add_stylebox_override("normal", _flat_style(Color(0.05, 0.32, 0.23, 1.0), GREEN, 3, 99))
	local_badge.valign = Label.VALIGN_CENTER
	header.add_child(local_badge)
	var close := _make_button("×", PINK_DARK, 22)
	close.rect_min_size = Vector2(64, 58)
	close.connect("pressed", self, "_close_modal")
	header.add_child(close)

	var subtitle := _make_label("Every catalog cosmetic is available here. Stack as many as you want; nothing is purchased, unlocked, uploaded, or written to your real profile.", _small_font, DIM)
	subtitle.autowrap = true
	root_vbox.add_child(subtitle)

	var hero := HBoxContainer.new()
	hero.add_constant_override("separation", 18)
	root_vbox.add_child(hero)
	var preview_panel := PanelContainer.new()
	preview_panel.rect_min_size = Vector2(245, 245)
	preview_panel.add_stylebox_override("panel", _flat_style(NAVY_2, Color(1, 1, 1, 0.25), 3, 24))
	hero.add_child(preview_panel)
	var preview_holder := Control.new()
	preview_holder.rect_min_size = Vector2(245, 245)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_holder)
	var goober_scene = load(GOOBER_SCENE_PATH)
	if goober_scene != null and goober_scene is PackedScene:
		_preview_goober = goober_scene.instance()
		_preview_goober.position = Vector2(122, 222)
		_preview_goober.scale = Vector2(-0.125, 0.125)
		_preview_goober.enable_sounds = false
		preview_holder.add_child(_preview_goober)
		_register_goober(_preview_goober)
		var animation_state = _preview_goober.get_animation_state()
		if animation_state != null:
			animation_state.set_animation("Idle", true, 0)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_constant_override("separation", 9)
	hero.add_child(controls)
	_status_label = _make_label("", _header_font, WHITE)
	controls.add_child(_status_label)
	_active_button = _make_button("", PINK, 20)
	_active_button.connect("pressed", self, "_toggle_sandbox_enabled")
	controls.add_child(_active_button)
	_profile_base_button = _make_button("", BLUE, 18)
	_profile_base_button.connect("pressed", self, "_toggle_profile_base")
	controls.add_child(_profile_base_button)
	var color_row := HBoxContainer.new()
	color_row.add_constant_override("separation", 10)
	controls.add_child(color_row)
	_custom_color_button = _make_button("", PURPLE, 18)
	_custom_color_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_color_button.connect("pressed", self, "_toggle_custom_color")
	color_row.add_child(_custom_color_button)
	_color_picker = ColorPickerButton.new()
	_color_picker.rect_min_size = Vector2(92, 58)
	_color_picker.color = custom_color
	_color_picker.focus_mode = Control.FOCUS_NONE
	_color_picker.hint_tooltip = "Choose any local Goober colour"
	_color_picker.connect("color_changed", self, "_on_custom_color_changed")
	color_row.add_child(_color_picker)

	var filter_row := HBoxContainer.new()
	filter_row.add_constant_override("separation", 7)
	root_vbox.add_child(filter_row)
	var filters := [["color", "COLORS"], ["suit", "SUITS"], ["hat", "HATS"], ["hand", "HANDS"], ["emote", "EMOTES"]]
	for item in filters:
		var filter_button := _make_button(item[1], TYPE_COLORS.get(item[0], BLUE), 15)
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_button.connect("pressed", self, "_set_filter", [item[0]])
		filter_row.add_child(filter_button)
		_filter_buttons[item[0]] = filter_button

	_search_box = LineEdit.new()
	_search_box.rect_min_size = Vector2(0, 52)
	_search_box.placeholder_text = "Search every cosmetic by name or ID…"
	_search_box.clear_button_enabled = true
	_search_box.focus_mode = Control.FOCUS_ALL
	if _body_font != null:
		_search_box.add_font_override("font", _body_font)
	_search_box.add_stylebox_override("normal", _flat_style(NAVY_2, Color(1, 1, 1, 0.35), 3, 16))
	_search_box.add_stylebox_override("focus", _flat_style(NAVY_2, PINK, 4, 16))
	_search_box.connect("text_changed", self, "_on_search_changed")
	root_vbox.add_child(_search_box)

	var scroll := ScrollContainer.new()
	# Phase 0.4 -- Cosmetic Sandbox Content Loading Bug. The catalog was
	# loading fine (confirmed via Debug Mode: 287 items) but never appeared,
	# because this ScrollContainer sits inside ANOTHER ScrollContainer
	# (modal_scroll, wrapping the whole modal body below). A ScrollContainer's
	# reported minimum size in Godot 3.x does not include its child's full
	# content size -- that's what lets it be smaller than what it scrolls --
	# so nested inside another ScrollContainer, root_vbox gets sized to its
	# bare minimum and this one collapses to near-zero height, hiding every
	# card even though they were all correctly created. Giving it an explicit
	# minimum height forces real space to be reserved for the grid.
	scroll.rect_min_size = Vector2(0, 460)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	root_vbox.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_constant_override("hseparation", 9)
	_grid.add_constant_override("vseparation", 9)
	scroll.add_child(_grid)

	var actions := HBoxContainer.new()
	actions.add_constant_override("separation", 10)
	root_vbox.add_child(actions)
	var random_button := _make_button("⚄  STACK RANDOM", PURPLE, 18)
	random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_button.connect("pressed", self, "_randomize_stack")
	actions.add_child(random_button)
	var clear_button := _make_button("CLEAR EXTRAS", BLUE, 18)
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.connect("pressed", self, "_clear_extras")
	actions.add_child(clear_button)
	var profile_button := _make_button("USE REAL PROFILE", PINK_DARK, 18)
	profile_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_button.connect("pressed", self, "_disable_and_restore_profile")
	actions.add_child(profile_button)

	_modal_resize_grip = _make_button("↘", Color(0.08, 0.34, 0.55, 0.84), 20)
	_modal_resize_grip.rect_min_size = Vector2(48, 48)
	_modal_resize_grip.rect_size = Vector2(48, 48)
	_modal_resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_modal_resize_grip.hint_tooltip = "Drag to resize the Sandbox window."
	_modal_resize_grip.connect("gui_input", self, "_on_modal_resize_gui_input")
	_modal_root.add_child(_modal_resize_grip)
	call_deferred("_sync_modal_resize_grip")

	_modal_root.visible = false
	_refresh_controls()


func _open_modal() -> void:
	if not gui_enabled:
		return
	if _studio != null:
		_studio.open(0)
		return
	_modal_root.visible = true
	_filter = "color"
	_search_box.text = ""
	_catalog_retry_elapsed = 0.0
	_catalog_retry_attempts = 0
	_rebuild_grid()
	_refresh_controls()


func _close_modal() -> void:
	if _studio != null:
		_studio.on_closed()
	_modal_resizing = false
	_modal_moving = false
	_modal_root.visible = false
	_catalog_waiting_for_source = false
	_clear_cosmetic_grid()


func _process_catalog_retry(delta: float) -> void:
	if _modal_root == null or not _modal_root.visible or not _catalog_waiting_for_source:
		return
	if _catalog_retry_attempts >= CATALOG_RETRY_LIMIT:
		return
	_catalog_retry_elapsed += delta
	if _catalog_retry_elapsed < CATALOG_RETRY_INTERVAL:
		return
	_catalog_retry_elapsed = 0.0
	_catalog_retry_attempts += 1
	var source = Moonlight.storage.storage_get("cosmetics", {})
	if typeof(source) == TYPE_DICTIONARY and not source.empty():
		_catalog_waiting_for_source = false
		_rebuild_grid()


func _on_modal_resize_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_modal_resizing = event.pressed
		if event.pressed:
			_convert_modal_panel_to_pixel_rect()
		else:
			_save_modal_layout()
	elif event is InputEventMouseMotion and _modal_resizing:
		# Phase 0.1/0.2 follow-up: when `available` (room between the panel's
		# fixed position and the viewport edge) dropped below the intended
		# 440x400 minimum, min_size got set to `available` too -- making the
		# clamp's min and max the SAME value and permanently locking the
		# panel at that exact size no matter which way you dragged. Clamping
		# the minimum DOWN to whatever's actually available (instead of
		# leaving it at a fixed 440/400) keeps min <= max always, so resizing
		# never gets stuck.
		var viewport_size: Vector2 = tas_tool.get_gui_viewport_size() if tas_tool != null else get_viewport().size
		var minimum := Vector2(440, 400)
		if _studio != null:
			_studio.window_user_sized = true
			minimum = _modal_panel.get_combined_minimum_size()
			_modal_panel.rect_size = Vector2(max(minimum.x, _modal_panel.rect_size.x + event.relative.x), max(minimum.y, _modal_panel.rect_size.y + event.relative.y))
		elif _window_geometry != null:
			_modal_panel.rect_size = _window_geometry.resized_size(_modal_panel.rect_size, event.relative, minimum, _modal_panel.rect_position, viewport_size, Vector2(18, 18))
		else:
			var available: Vector2 = viewport_size - _modal_panel.rect_position - Vector2(18, 18)
			var maximum := Vector2(max(minimum.x, available.x), max(minimum.y, available.y))
			_modal_panel.rect_size = Vector2(clamp(_modal_panel.rect_size.x + event.relative.x, minimum.x, maximum.x), clamp(_modal_panel.rect_size.y + event.relative.y, minimum.y, maximum.y))
		_grid.columns = 2 if _modal_panel.rect_size.x < 760.0 else (3 if _modal_panel.rect_size.x < 1040.0 else 4)
		_sync_modal_resize_grip()


func _on_modal_move_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_modal_moving = event.pressed
		if event.pressed:
			_convert_modal_panel_to_pixel_rect()
		else:
			_save_modal_layout()
	elif event is InputEventMouseMotion and _modal_moving:
		var viewport_size: Vector2 = tas_tool.get_gui_viewport_size() if tas_tool != null else get_viewport().size
		if _window_geometry != null:
			_modal_panel.rect_position = _window_geometry.moved_position(_modal_panel.rect_position, _modal_panel.rect_size, event.relative, viewport_size)
		else:
			var next: Vector2 = _modal_panel.rect_position + event.relative
			next.x = clamp(next.x, -_modal_panel.rect_size.x + 120.0, viewport_size.x - 120.0)
			next.y = clamp(next.y, 0.0, viewport_size.y - 64.0)
			_modal_panel.rect_position = next
		_sync_modal_resize_grip()


func _convert_modal_panel_to_pixel_rect() -> void:
	if _window_geometry != null:
		_window_geometry.convert_to_pixel_rect(_modal_panel)
		return
	if is_zero_approx(_modal_panel.anchor_right) and is_zero_approx(_modal_panel.anchor_bottom):
		return
	var position := _modal_panel.rect_position
	var size := _modal_panel.rect_size
	_modal_panel.anchor_left = 0.0
	_modal_panel.anchor_top = 0.0
	_modal_panel.anchor_right = 0.0
	_modal_panel.anchor_bottom = 0.0
	_modal_panel.rect_position = position
	_modal_panel.rect_size = size


func _sync_modal_resize_grip() -> void:
	if _modal_panel == null or _modal_resize_grip == null:
		return
	_modal_resize_grip.rect_position = _modal_panel.rect_position + _modal_panel.rect_size - _modal_resize_grip.rect_size - Vector2(8, 8)


func _initialize_saved_layout() -> void:
	if _modal_panel == null:
		return
	_convert_modal_panel_to_pixel_rect()
	_layout_default = {"position": _modal_panel.rect_position, "size": _modal_panel.rect_size}
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("restore_gui_panel_layout"):
		tas_tool.call("restore_gui_panel_layout", "cosmetic_sandbox", _modal_panel, Vector2(640, 440))
	_grid.columns = 2 if _modal_panel.rect_size.x < 760.0 else (3 if _modal_panel.rect_size.x < 1040.0 else 4)
	_sync_modal_resize_grip()


func _save_modal_layout() -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("save_gui_panel_layout"):
		tas_tool.call("save_gui_panel_layout", "cosmetic_sandbox", _modal_panel)


func reset_saved_layout() -> void:
	if _modal_panel == null or _layout_default.empty():
		return
	_modal_panel.rect_position = _layout_default["position"]
	_modal_panel.rect_size = _layout_default["size"]
	_grid.columns = 2 if _modal_panel.rect_size.x < 760.0 else (3 if _modal_panel.rect_size.x < 1040.0 else 4)
	_sync_modal_resize_grip()


func _set_filter(value: String) -> void:
	_filter = value
	_rebuild_grid()
	_refresh_filter_buttons()


func _on_search_changed(_text: String) -> void:
	_rebuild_grid()
