extends "user://mod/tools/tas/TASMacroEditor/01_placeholders.gd"

func _ready() -> void:
	layer = 190
	pause_mode = Node.PAUSE_MODE_PROCESS
	# Read the setting directly instead of waiting for TASTool.gd's
	# set_claude_experimental_icons_enabled() call: that call only arrives
	# via a deferred call made at the very end of TASTool.gd's own _ready(),
	# which runs AFTER add_child(_macro_editor) already triggered this whole
	# _ready() (including _build_ui() below) -- so every stylebox was
	# actually always being built with the toggle reading as off, regardless
	# of the saved setting, exactly like the same bug found and fixed in
	# ReplayHub.gd. Reading the same saved value straight from SavedSettings
	# here sidesteps that ordering entirely.
	_claude_experimental_icons_enabled = bool(SavedSettings.get_value("client_tools_claude_experimental_icons", false))
	var window_geometry_script = load(WINDOW_GEOMETRY_SCRIPT_PATH)
	if window_geometry_script != null:
		_window_geometry = window_geometry_script.new()
	_title_font = _font(34)
	_body_font = _font(23)
	_small_font = _font(18)
	_build_ui()
	_root.visible = false
	# Anchors are useful for the first responsive layout pass, but leaving them
	# active makes panels resize themselves whenever the viewport/UI scale
	# changes. Freeze the resolved rectangles once, after Containers laid out.
	call_deferred("_freeze_editor_layout")


func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool


# See TASTool.gd's _load_claude_icon() for the full explanation -- same
# loader, duplicated here since this file has no import access to TASTool.gd's
# copy. Resizes the 142x142 source art down to the exact display size with
# high-quality interpolation instead of leaving TextureRect to scale it at
# draw time -- that's what made the first pass look muddy/out of proportion.
# Returns null (never an error) if the icon pack isn't installed.
# The approved icon PNGs are fully opaque 142x142 squares -- the dark tile
# art is baked into the pixels, not a transparent background behind a
# cut-out glyph. This keys out the tile's own fill color to transparent on
# the in-memory copy only (never touches the source PNG on disk), so the
# glyph blends into the modern black panels instead of floating as a chip.
func _strip_icon_background(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	if w < 4 or h < 4:
		return
	image.lock()
	var bg := Color(0, 0, 0)
	var samples := [
		image.get_pixel(1, 1), image.get_pixel(w - 2, 1),
		image.get_pixel(1, h - 2), image.get_pixel(w - 2, h - 2),
		image.get_pixel(w / 2, 1), image.get_pixel(1, h / 2),
	]
	for s in samples:
		bg += s
	bg /= samples.size()
	var threshold := 0.16
	var feather := 0.1
	for y in range(h):
		for x in range(w):
			var px := image.get_pixel(x, y)
			var dist := sqrt(pow(px.r - bg.r, 2) + pow(px.g - bg.g, 2) + pow(px.b - bg.b, 2))
			if dist <= threshold:
				px.a = 0.0
				image.set_pixel(x, y, px)
			elif dist <= threshold + feather:
				px.a = (dist - threshold) / feather
				image.set_pixel(x, y, px)
	image.unlock()


func _load_claude_icon(icon_name: String, size: int = 40) -> Texture:
	var cache_key: = "%s@%d" % [icon_name, size]
	if _claude_icon_texture_cache.has(cache_key):
		return _claude_icon_texture_cache[cache_key]
	var texture: Texture = null
	var path: = ModPaths.ICONS_DIR + icon_name + ".png"
	if File.new().file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			_strip_icon_background(image)
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
			var image_texture := ImageTexture.new()
			image_texture.create_from_image(image, Texture.FLAGS_DEFAULT)
			texture = image_texture
	_claude_icon_texture_cache[cache_key] = texture
	return texture


# Called by TASTool.gd whenever Claude Experimental Mode is toggled (and once
# at startup if it was already on). Purely cosmetic.
func set_claude_experimental_icons_enabled(value: bool) -> void:
	_claude_experimental_icons_enabled = value
	if _claude_title_icon == null:
		return
	if not value:
		_claude_title_icon.visible = false
		return
	var texture: = _load_claude_icon("timeline_editor", 40)
	_claude_title_icon.texture = texture
	_claude_title_icon.visible = texture != null


func open_editor(target_slot: int, data: Dictionary) -> void:
	slot = target_slot
	working_data = data.duplicate(true)
	_dirty = false
	_selected_frame = 0
	_name_edit.text = str(working_data.get("name", "Macro %d" % slot if slot > 0 else "Current Macro"))
	_rebuild_timeline()
	_root.visible = true
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_begin_macro_editor_preview"):
		tas_tool.call("_begin_macro_editor_preview")
	_refresh_freecam_zoom_label()
	_refresh_inspector()


func close_editor() -> void:
	_set_preview_direction(0)
	_freecam_dragging = false
	_resizing_panel = ""
	_moving_panel = ""
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_end_macro_editor_preview"):
		tas_tool.call("_end_macro_editor_preview")
	_root.visible = false
	emit_signal("editor_closed")


func is_open() -> bool:
	return _root != null and _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and (event is InputEventMouseButton or event is InputEventMouseMotion):
		_on_editor_background_gui_input(event)
	if _root.visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close_editor()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	if _root == null or not _root.visible:
		return
	if _root.rect_size != _layout_root_size:
		_fit_editor_panels()
	_sync_editor_resize_grips()
	_advance_preview(delta)
	var focus: Control = _root.get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox:
		return
	var direction := Vector2.ZERO
	if tas_tool._keybinds.held("camera_left"):
		direction.x -= 1.0
	if tas_tool._keybinds.held("camera_right"):
		direction.x += 1.0
	if tas_tool._keybinds.held("camera_up"):
		direction.y -= 1.0
	if tas_tool._keybinds.held("camera_down"):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		_move_freecam(direction.normalized() * 720.0 * delta)


func _on_editor_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_RIGHT:
			_freecam_dragging = event.pressed
			get_tree().set_input_as_handled()
		elif event.pressed and event.button_index == BUTTON_WHEEL_UP:
			_zoom_freecam(1.0 / 1.15)
			get_tree().set_input_as_handled()
		elif event.pressed and event.button_index == BUTTON_WHEEL_DOWN:
			_zoom_freecam(1.15)
			get_tree().set_input_as_handled()
	elif event is InputEventMouseMotion and _freecam_dragging:
		_move_freecam(-event.relative)
		get_tree().set_input_as_handled()


func _move_freecam(screen_delta: Vector2) -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_move_macro_editor_freecam"):
		tas_tool.call("_move_macro_editor_freecam", screen_delta)


func _zoom_freecam(factor: float) -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_zoom_macro_editor_freecam"):
		tas_tool.call("_zoom_macro_editor_freecam", factor)
	_refresh_freecam_zoom_label()


func _center_freecam() -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_center_macro_editor_freecam"):
		tas_tool.call("_center_macro_editor_freecam")
	_refresh_freecam_zoom_label()


func _reset_freecam() -> void:
	_freecam_dragging = false
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_reset_macro_editor_freecam"):
		tas_tool.call("_reset_macro_editor_freecam")
	_refresh_freecam_zoom_label()


func _refresh_freecam_zoom_label() -> void:
	if _freecam_zoom_label == null:
		return
	var percent := 100
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_get_macro_editor_freecam_zoom_percent"):
		percent = int(tas_tool.call("_get_macro_editor_freecam_zoom_percent"))
	_freecam_zoom_label.text = "%d%%" % percent


func _add_editor_resize_grip(key: String, target: Control, minimum_size: Vector2) -> void:
	_resize_targets[key] = target
	_resize_minimums[key] = minimum_size
	var grip := _button("↘", Color(0.08, 0.34, 0.55, 0.86), 46)
	grip.rect_min_size = Vector2(46, 46)
	grip.rect_size = Vector2(46, 46)
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.hint_tooltip = "Drag to resize this panel."
	grip.connect("gui_input", self, "_on_editor_resize_gui_input", [key])
	_root.add_child(grip)
	_resize_grips[key] = grip


func _add_editor_move_handle(key: String, target: Control, handle: Control) -> void:
	_move_targets[key] = target
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.hint_tooltip = "Drag this title bar to move the panel."
	handle.connect("gui_input", self, "_on_editor_move_gui_input", [key])


func _on_editor_move_gui_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_moving_panel = key if event.pressed else ""
		if event.pressed:
			_convert_editor_panel_to_pixel_rect(_move_targets[key])
		else:
			_save_panel_layout(key)
	elif event is InputEventMouseMotion and _moving_panel == key:
		var target: Control = _move_targets[key]
		var viewport_size: Vector2 = tas_tool.get_gui_viewport_size() if tas_tool != null else get_viewport().size
		if _window_geometry != null:
			target.rect_position = _window_geometry.moved_position(target.rect_position, target.rect_size, event.relative, viewport_size, 110.0, 60.0)
		else:
			var next: Vector2 = target.rect_position + event.relative
			next.x = clamp(next.x, -target.rect_size.x + 110.0, viewport_size.x - 110.0)
			next.y = clamp(next.y, 0.0, viewport_size.y - 60.0)
			target.rect_position = next
		_sync_editor_resize_grips()


func _on_editor_resize_gui_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_resizing_panel = key if event.pressed else ""
		if event.pressed:
			_convert_editor_panel_to_pixel_rect(_resize_targets[key])
		else:
			_save_panel_layout(key)
	elif event is InputEventMouseMotion and _resizing_panel == key:
		var target: Control = _resize_targets[key]
		var viewport_size: Vector2 = tas_tool.get_gui_viewport_size() if tas_tool != null else get_viewport().size
		var requested_minimum: Vector2 = _resize_minimums[key]
		# A panel spawned well away from the top-left (e.g. the details panel,
		# anchored ~68% across the screen) only has a sliver of room between
		# its own top-left and the viewport edge, even when the rest of the
		# screen is empty -- that's what read as "stuck, can't grow bigger".
		# resized_size_and_position() bounds growth by the whole viewport
		# instead and, only if that would push the panel off the right/bottom
		# edge, pulls the panel's CURRENT top-left back to make room. That's
		# not the same as the old spawn-point-jump bug noted below: this uses
		# wherever the panel actually is right now, and only nudges it back by
		# exactly the overflow amount, so a panel with room to grow in place
		# never moves at all.
		#
		# Old note (still true for resized_size(), kept as a fallback below):
		# the very first implementation sized against the entire viewport and
		# then clamped rect_position inward using a stale reference point,
		# which made a panel jump back toward its spawn point after it had
		# been moved. That's why resized_size() derives available size from
		# the panel's fixed top-left and never touches position.
		var resize_delta := Vector2(event.relative.x, event.relative.y)
		if _window_geometry != null and _window_geometry.has_method("resized_size_and_position"):
			var result: Dictionary = _window_geometry.resized_size_and_position(target.rect_size, target.rect_position, resize_delta, requested_minimum, viewport_size)
			target.rect_position = result["position"]
			target.rect_size = result["size"]
		elif _window_geometry != null:
			target.rect_size = _window_geometry.resized_size(target.rect_size, resize_delta, requested_minimum, target.rect_position, viewport_size)
		else:
			var available: Vector2 = viewport_size - target.rect_position - Vector2(12, 12)
			var maximum: Vector2 = Vector2(max(requested_minimum.x, available.x), max(requested_minimum.y, available.y))
			var requested: Vector2 = target.rect_size + resize_delta
			target.rect_size = Vector2(clamp(requested.x, requested_minimum.x, maximum.x), clamp(requested.y, requested_minimum.y, maximum.y))
		_sync_editor_resize_grips()


func _convert_editor_panel_to_pixel_rect(target: Control) -> void:
	if _window_geometry != null:
		_window_geometry.convert_to_pixel_rect(target)
		return
	if is_zero_approx(target.anchor_right) and is_zero_approx(target.anchor_bottom):
		return
	var position := target.rect_position
	var size := target.rect_size
	target.anchor_left = 0.0
	target.anchor_top = 0.0
	target.anchor_right = 0.0
	target.anchor_bottom = 0.0
	target.rect_position = position
	target.rect_size = size


func _sync_editor_resize_grips() -> void:
	for key in _resize_grips.keys():
		var target: Control = _resize_targets[key]
		var grip: Control = _resize_grips[key]
		if target != null and grip != null:
			grip.rect_position = target.rect_position + target.rect_size - grip.rect_size - Vector2(7, 7)


func _freeze_editor_layout() -> void:
	# Resolve anchored panels in the same scaled coordinate space as WorkspaceMenu
	# before freezing their geometry; the native canvas starts at only 960x540.
	if tas_tool != null and is_instance_valid(tas_tool):
		_root.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
		_root.rect_size = tas_tool.get_gui_viewport_size()
		_root.rect_scale = Vector2.ONE * tas_tool.get_gui_scale_factor()
	for key in _move_targets.keys():
		var target: Control = _move_targets[key]
		if target != null and is_instance_valid(target):
			_convert_editor_panel_to_pixel_rect(target)
			_layout_defaults[key] = {"position": target.rect_position, "size": target.rect_size}
			if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("restore_gui_panel_layout"):
				tas_tool.call("restore_gui_panel_layout", "timeline_" + str(key), target, _resize_minimums.get(key, Vector2(240, 120)))
	_fit_editor_panels()


func _fit_editor_panels() -> void:
	_layout_root_size = _root.rect_size
	for key in _move_targets.keys():
		var target: Control = _move_targets[key]
		if target != null and is_instance_valid(target):
			var available := _root.rect_size - Vector2(24, 24)
			var minimum: Vector2 = _resize_minimums.get(key, Vector2(240, 120))
			if key == "timeline":
				minimum = _timeline_content.get_combined_minimum_size() + Vector2(48, 48)
			elif key == "details":
				minimum = Vector2(420, 380)
			elif key == "freecam":
				minimum = target.get_combined_minimum_size() + Vector2(48, 12)
			minimum = Vector2(min(minimum.x, available.x), min(minimum.y, available.y))
			_resize_minimums[key] = minimum
			target.rect_size = Vector2(min(available.x, max(target.rect_size.x, minimum.x)), min(available.y, max(target.rect_size.y, minimum.y)))
			target.rect_position = Vector2(clamp(target.rect_position.x, 12, _root.rect_size.x - target.rect_size.x - 12), clamp(target.rect_position.y, 12, _root.rect_size.y - target.rect_size.y - 12))
			_layout_defaults[key] = {"position": target.rect_position, "size": target.rect_size}
	# Repair overlap caused by enlarging old, undersized saved windows.
	if _timeline_panel.get_rect().intersects(_details_panel.get_rect()) or _timeline_panel.get_rect().intersects(_move_targets["freecam"].get_rect()):
		_timeline_panel.rect_position.y = max(12.0, _root.rect_size.y - _timeline_panel.rect_size.y - 12.0)
	if _details_panel.get_rect().intersects(_move_targets["freecam"].get_rect()) or _details_panel.get_rect().intersects(_timeline_panel.get_rect()):
		_details_panel.rect_position = Vector2(max(12.0, _root.rect_size.x - _details_panel.rect_size.x - 12.0), 12.0)
	for key in _move_targets:
		_layout_defaults[key] = {"position": _move_targets[key].rect_position, "size": _move_targets[key].rect_size}
	for key in ["details", "freecam"]:
		var fits: bool = not _move_targets[key].get_rect().intersects(_timeline_panel.get_rect())
		_move_targets[key].visible = fits
		_resize_grips[key].visible = fits
	_sync_editor_resize_grips()


func _toggle_editor_panel(key: String) -> void:
	var panel: Control = _move_targets[key]
	panel.visible = not panel.visible
	_resize_grips[key].visible = panel.visible


func _save_panel_layout(key: String) -> void:
	if not _move_targets.has(key):
		return
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("save_gui_panel_layout"):
		tas_tool.call("save_gui_panel_layout", "timeline_" + key, _move_targets[key])


func reset_saved_layout() -> void:
	for key in _layout_defaults.keys():
		if not _move_targets.has(key):
			continue
		var target: Control = _move_targets[key]
		var defaults: Dictionary = _layout_defaults[key]
		target.rect_position = defaults["position"]
		target.rect_size = defaults["size"]
	_sync_editor_resize_grips()
