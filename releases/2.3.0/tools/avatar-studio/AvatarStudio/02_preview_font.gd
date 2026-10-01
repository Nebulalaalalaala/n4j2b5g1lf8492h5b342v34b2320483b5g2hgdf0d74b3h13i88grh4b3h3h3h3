extends "user://mod/tools/avatar-studio/AvatarStudio/01_placeholders.gd"

func font(size: int) -> Font:
	if fonts.has(size):
		return fonts[size]
	var path = ModPaths.MAIN_FONT
	if File.new().file_exists(path):
		var data = DynamicFontData.new()
		data.font_path = path
		var result = DynamicFont.new()
		result.font_data = data
		result.size = size
		fonts[size] = result
	else:
		fonts[size] = sandbox.call("_make_font", size)
	return fonts[size]

func style(fill: Color = PANEL, border: Color = LINE) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(7)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

func label(text: String, size: int = 16, tint: Color = TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", font(size))
	l.add_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func button(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.rect_min_size.y = 36
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", font(15))
	b.add_color_override("font_color", TEXT)
	b.add_color_override("font_color_hover", TEXT)
	b.add_color_override("font_color_pressed", ACCENT)
	b.add_stylebox_override("normal", style())
	b.add_stylebox_override("hover", style(Color("2d373a")))
	b.add_stylebox_override("pressed", style(Color("304c40"), ACCENT))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	if not method.empty():
		b.connect("pressed", self, method, args)
	return b

func row(parent: Node) -> HBoxContainer:
	var r = HBoxContainer.new()
	r.add_constant_override("separation", 8)
	parent.add_child(r)
	return r

func column(parent: Node) -> VBoxContainer:
	var c = VBoxContainer.new()
	c.add_constant_override("separation", 12)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

func build(source, owner_tool) -> void:
	sandbox = source
	tool_ref = owner_tool
	pause_mode = Node.PAUSE_MODE_PROCESS
	shader = Shader.new()
	shader.code = SHADER_CODE
	_load()
	var old = sandbox.get("_modal_panel").get_child(0)
	old.hide()
	goober = sandbox.get("_preview_goober")
	if goober != null:
		goober.get_parent().remove_child(goober)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_" + side, 20)
	sandbox.get("_modal_panel").add_child(margin)
	sandbox.get("_modal_panel").add_stylebox_override("panel", style(BG))
	var theme = Theme.new()
	theme.default_font = font(15)
	for type in ["LineEdit", "TextEdit", "OptionButton", "PopupMenu"]:
		theme.set_color("font_color", type, TEXT)
		for state in ["normal", "read_only", "panel"]:
			theme.set_stylebox(state, type, style(PANEL))
		theme.set_stylebox("focus", type, style(PANEL, ACCENT))
		theme.set_stylebox("hover", type, style(Color("2d373a")))
	sandbox.get("_modal_panel").theme = theme
	var root = column(margin)
	var header = row(root)
	var title = label("Avatar Studio", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.connect("gui_input", sandbox, "_on_modal_move_gui_input")
	header.add_child(title)
	header.add_child(label("LOCAL APPEARANCE", 12, ACCENT))
	header.add_child(button("Undo", "undo"))
	header.add_child(button("Redo", "redo"))
	header.add_child(button("Fit window", "_fit_window"))
	header.add_child(button("×", "close"))
	var main = row(root)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left = column(main)
	left.rect_min_size.x = 350
	left.size_flags_stretch_ratio = 0.9
	var preview_panel = PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_stylebox_override("panel", style(BG))
	left.add_child(preview_panel)
	stage = Stage.new()
	stage.rect_min_size = Vector2(320, 285)
	stage.rect_clip_content = true
	stage.focus_mode = Control.FOCUS_ALL
	stage.mouse_default_cursor_shape = Control.CURSOR_DRAG
	stage.hint_tooltip = "Drag empty space or middle-drag to pan · Alt-drag to tilt · Reset to recenter"
	stage.connect("gui_input", self, "_stage_input")
	stage.connect("resized", self, "_position_preview")
	preview_panel.add_child(stage)
	if goober != null:
		stage.add_child(goober)
		goober.enable_sounds = false
		goober.enable_blink = false
		transform_gizmo = TransformGizmo.new()
		transform_gizmo.studio = self
		transform_gizmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(transform_gizmo)
	else:
		stage.add_child(label("Avatar preview unavailable", 16, DIM))
	var camera = row(left)
	camera.add_child(button("−", "_zoom", [-0.15]))
	camera.add_child(button("+", "_zoom", [0.15]))
	zoom_control = SpinBox.new()
	zoom_control.min_value = 5
	zoom_control.max_value = 1000
	zoom_control.allow_greater = true
	zoom_control.step = 5
	zoom_control.value = 100
	zoom_control.suffix = "%"
	zoom_control.rect_min_size.x = 85
	zoom_control.hint_tooltip = "Avatar zoom — type any percentage above 5%"
	zoom_control.connect("value_changed", self, "_set_zoom_percent")
	camera.add_child(zoom_control)
	camera.add_child(button("Face left", "_face", [1.0]))
	camera.add_child(button("Face right", "_face", [-1.0]))
	camera.add_child(button("Reset", "_reset_view"))
	var sizing = row(left)
	sizing.add_child(label("Goober size",14,DIM))
	size_control = SpinBox.new()
	size_control.min_value = 10
	size_control.max_value = 10000
	size_control.allow_greater = false
	size_control.step = 5
	size_control.value = 100
	size_control.suffix = "%"
	size_control.rect_min_size = Vector2(145, 36)
	size_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_control.get_line_edit().mouse_filter = Control.MOUSE_FILTER_STOP
	size_control.get_line_edit().add_font_override("font", font(15))
	size_control.get_line_edit().add_color_override("font_color", TEXT)
	size_control.hint_tooltip = "Saved local avatar size (10–10000%). Does not change hitboxes."
	size_control.connect("value_changed",self,"_set_avatar_size")
	size_control.get_line_edit().connect("text_entered",self,"_size_entered")
	size_control.get_line_edit().connect("focus_exited",self,"_size_focus_exit")
	sizing.add_child(size_control)
	summary = label("", 14, DIM)
	summary.autowrap = true
	left.add_child(summary)
	var bottom = row(left)
	bottom.add_child(button("Randomize", "randomize_appearance"))
	var compare = button("Hold to compare", "")
	compare.connect("button_down", self, "_compare", [true])
	compare.connect("button_up", self, "_compare", [false])
	bottom.add_child(compare)
	bottom.add_child(button("Clean view", "_fullscreen"))
	var local_controls = row(left)
	local_controls.add_child(button("Local look on / off", "_toggle_local"))
	local_controls.add_child(button("Profile base on / off", "_toggle_base"))
	left.add_child(button("Reset to profile", "_reset_appearance"))
	right_column = column(main)
	right_column.rect_min_size.x = 540
	var section_row = row(right_column)
	for title_text in ["Customize", "Looks", "Preview"]:
		var b = button(title_text, "select_section", [section_buttons.size()])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section_row.add_child(b)
		section_buttons.append(b)
	section_tabs = TabContainer.new()
	section_tabs.tabs_visible = false
	section_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section_tabs.add_stylebox_override("panel", StyleBoxEmpty.new())
	right_column.add_child(section_tabs)
	customize = _page("Customize")
	looks_page = _page("Looks")
	preview_page = _page("Preview")
	_build_customize()
	_build_looks()
	_build_preview()
	status = label("", 14, DIM)
	status.autowrap = true
	root.add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.png ; PNG texture")
	file_dialog.connect("file_selected", self, "_import_texture")
	sandbox.get("_modal_root").add_child(file_dialog)
	import_dialog = ConfirmationDialog.new()
	import_dialog.window_title = "Import Look"
	import_dialog.rect_min_size = Vector2(540, 280)
	import_dialog.get_ok().text = "Import to Looks"
	import_dialog.connect("confirmed", self, "_confirm_import")
	import_dialog.connect("popup_hide", self, "_end_preview")
	var ic = column(import_dialog)
	ic.add_child(label("Paste a Studio Look code. Your outfit stays unchanged.", 15))
	import_field = TextEdit.new()
	import_field.rect_min_size = Vector2(500, 140)
	import_field.connect("text_changed", self, "_validate_import")
	ic.add_child(import_field)
	import_feedback = label("Paste an AVATAR1 Look code to preview it.", 13, DIM)
	import_feedback.autowrap = true
	ic.add_child(import_feedback)
	sandbox.get("_modal_root").add_child(import_dialog)
	if library.has("working"):
		_restore(library["working"])
	working = capture()
	session_start = working.duplicate(true)
	call_deferred("_migrate_looks")
	select_section(0)
	set_process(true)
	print("[AvatarStudio] Ready: Customize / Looks / Preview (local only)")

func _page(title: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = title
	scroll.rect_min_size.y = 240
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	section_tabs.add_child(scroll)
	return column(scroll)

func _build_customize() -> void:
	var categories = row(customize)
	for entry in CATEGORIES:
		var b = button(entry[1], "set_category", [entry[0]])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		categories.add_child(b)
		category_buttons[entry[0]] = b
	goober_tabs = row(customize)
	goober_tabs.add_child(button("Color", "_goober_mode", [false]))
	goober_tabs.add_child(button("Texture", "_goober_mode", [true]))
	goober_tabs.add_child(button("Effects", "_effects_mode"))
	effect_controls = column(customize)
	for entry in [["Dash Effect", "dash", ["default", "none", "sparks", "stars"]], ["Trail", "trail", ["default", "none", "soft", "stars"]]]:
		var effect_row = row(effect_controls)
		effect_row.add_child(label(entry[0]))
		for id in entry[2]:
			var choice = button(str(id).capitalize(), "_effect_selected", [entry[1], id])
			choice.set_meta("effect", [entry[1], id])
			effect_row.add_child(choice)
	effect_color = ColorPickerButton.new()
	effect_color.rect_min_size = Vector2(90, 38)
	effect_color.size_flags_horizontal = 0
	effect_color.color = Color("9dd6bd")
	effect_color.edit_alpha = false
	effect_color.connect("color_changed", self, "_effect_color_changed")
	effect_controls.add_child(effect_color)
	effect_controls.add_child(label("Local only · Run or dash in Playable Preview to test", 13, DIM))
	transform_controls = column(customize)
	var transform_row = row(transform_controls)
	for entry in [["x", "X", -100, 100, 0.5], ["y", "Y", -100, 100, 0.5], ["rotation", "Rotate", -360, 360, 1], ["scale", "Scale", 0.1, 4.0, 0.05]]:
		var cell = column(transform_row)
		cell.add_child(label(entry[1], 13, DIM))
		var field = SpinBox.new()
		field.min_value = entry[2]
		field.max_value = entry[3]
		field.step = entry[4]
		field.rect_min_size.x = 105
		field.connect("value_changed", self, "_transform_changed", [entry[0]])
		cell.add_child(field)
		transform_fields[entry[0]] = field
	var resets = row(transform_controls)
	for entry in [["Position", "position"], ["Rotation", "rotation"], ["Scale", "scale"], ["All", "all"]]:
		resets.add_child(button("Reset " + entry[0], "_reset_transform", [entry[1]]))
	transform_note = label("", 13, DIM)
	transform_controls.add_child(transform_note)
	transform_controls.add_child(label("Drag item frame to move · Drag corners to scale", 13, DIM))
	transform_controls.add_child(label("Depth / X-Y rotation unavailable (2D)", 13, DIM))
	color_controls = column(customize)
	var cr = row(color_controls)
	picker = ColorPickerButton.new()
	picker.rect_min_size = Vector2(90, 38)
	picker.edit_alpha = false
	picker.connect("color_changed", self, "_color_changed")
	cr.add_child(picker)
	cr.add_child(button("Copy HEX", "_copy_color"))
	cr.add_child(button("Paste HEX", "_paste_color"))
	cr.add_child(button("Save color", "_save_color"))
	cr.add_child(button("Reset", "_reset_color"))
	color_palette = row(color_controls)
	texture_controls = column(customize)
	var tr = row(texture_controls)
	for name in ["Default", "Dots", "Stripes", "Grid"]:
		tr.add_child(button(name, "_texture", [name.to_lower()]))
	texture_controls.add_child(button("Import PNG texture", "_show_texture_import"))
	texture_controls.add_child(label("Body patterns · PNG imports stay on this computer", 13, DIM))
	var search_row = row(customize)
	search = LineEdit.new()
	search.placeholder_text = "Search this category"
	search.clear_button_enabled = true
	search.rect_min_size.y = 38
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_font_override("font", font(16))
	search.connect("text_changed", self, "_search_changed")
	search_row.add_child(search)
	var filter = OptionButton.new()
	for name in ["All", "Favorites", "Recent"]:
		filter.add_item(name)
	filter.add_font_override("font", font(15))
	filter.connect("item_selected", self, "_browser_filter")
	search_row.add_child(filter)
	inspector = label("", 13, DIM)
	inspector.autowrap = true
	customize.add_child(inspector)
	catalog_grid = GridContainer.new()
	catalog_grid.columns = 3
	catalog_grid.add_constant_override("hseparation", 8)
	catalog_grid.add_constant_override("vseparation", 8)
	customize.add_child(catalog_grid)
	var pager = row(customize)
	pager.add_child(button("Previous", "_page_delta", [-1]))
	paging = label("", 14, DIM)
	paging.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pager.add_child(paging)
	pager.add_child(button("Next", "_page_delta", [1]))
	category_actions = row(customize)
	category_actions.add_child(button("Remove category", "_remove_category"))
	category_actions.add_child(button("Randomize category", "randomize_appearance", [false]))

func _build_looks() -> void:
	var save_row = row(looks_page)
	look_name = LineEdit.new()
	look_name.placeholder_text = "Name your look"
	look_name.max_length = 60
	look_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look_name.add_font_override("font", font(16))
	save_row.add_child(look_name)
	save_row.add_child(button("Save as new", "save_look"))
	save_row.add_child(button("Update look", "save_look", [true]))
	looks_page.add_child(button("Import Look code", "_show_import"))
	looks_grid = GridContainer.new()
	looks_grid.columns = 2
	looks_grid.add_constant_override("hseparation", 12)
	looks_grid.add_constant_override("vseparation", 12)
	looks_page.add_child(looks_grid)

func _build_preview() -> void:
	preview_page.add_child(label("See your look in motion", 22))
	var anims = row(preview_page)
	for name in ["Idle", "Run", "Jump", "Fall", "Dash"]:
		anims.add_child(button(name, "_animate", [name]))
	var playback = row(preview_page)
	playback.add_child(button("Play / pause", "_pause_animation"))
	playback.add_child(button("Restart", "_restart_animation"))
	playback.add_child(button("Loop on / off", "_toggle_loop"))
	preview_page.add_child(label("Environment", 16, DIM))
	var env = row(preview_page)
	for name in ["Neutral", "Bright", "Dark"]:
		env.add_child(button(name, "_environment", [name]))
	preview_page.add_child(button("Enter playable preview", "_toggle_playable"))
	var hint = label("A contained movement sketch using the real avatar animations.\nClick the preview: A/D or arrows to run, W to jump, Space to dash.\nAvailable outside active runs; click Exit to return to editing.", 14, DIM)
	hint.autowrap = true
	preview_page.add_child(hint)
	preview_page.add_child(label("This avatar uses a 2D skeleton: facing, zoom and tilt are supported; a true back view is not.", 14, DIM))
	preview_page.get_child(preview_page.get_child_count() - 1).autowrap = true
	preview_page.add_child(button("Exit playable preview", "_exit_playable"))

func open(section: int = 0) -> void:
	_end_preview()
	sandbox.get("_modal_root").visible = true
	call_deferred("_keep_header_visible" if window_user_sized else "_fit_window")
	sandbox.set("_catalog_retry_attempts", 0)
	session_start = capture()
	if goober != null and not sandbox.sandbox_enabled:
		sandbox.call("_apply_to_goober", goober, sandbox.call("_build_local_skin"))
	select_section(section)
	_position_preview()
	refresh()

func _fit_window() -> void:
	window_user_sized = false
	# Autowrapped labels can briefly report a huge minimum before containers
	# receive their width. Fit after layout, not against that transient size.
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if window_user_sized or not is_instance_valid(sandbox) or not sandbox.get("_modal_root").visible:
		return
	var panel = sandbox.get("_modal_panel")
	var available = tool_ref.get_gui_viewport_size() if tool_ref != null else sandbox.get_viewport().size
	var minimum = panel.get_combined_minimum_size()
	panel.rect_size = Vector2(max(minimum.x, min(1100.0, available.x - 30)), max(minimum.y, min(740.0, available.y - 30)))
	_keep_header_visible()

func _keep_header_visible() -> void:
	var panel = sandbox.get("_modal_panel")
	var available = tool_ref.get_gui_viewport_size() if tool_ref != null else sandbox.get_viewport().size
	panel.rect_position.x = clamp(panel.rect_position.x, 0, max(0, available.x - panel.rect_size.x))
	panel.rect_position.y = clamp(panel.rect_position.y, 0, max(0, available.y - panel.rect_size.y))
	sandbox.call("_sync_modal_resize_grip")

func close() -> void:
	_end_item_drag()
	sandbox.call("_close_modal")

func on_closed() -> void:
	_end_item_drag()
	if is_instance_valid(effect_preview):
		effect_preview.queue_free()
		effect_preview = null
	_exit_playable()
	dragging_preview = false
	_end_preview()
	_save()
	for parent in [catalog_grid, looks_grid]:
		for child in parent.get_children():
			child.hide()
			child.queue_free()

func _end_preview() -> void:
	preview_skin_override.clear()
	if goober != null:
		_render_look(goober, capture())

func select_section(index: int) -> void:
	if section_tabs == null:
		return
	section_tabs.current_tab = index
	if index != 2:
		_exit_playable()
	for i in range(section_buttons.size()):
		section_buttons[i].add_stylebox_override("normal", style(Color("30463b") if i == index else PANEL))
	if index == 1:
		_build_look_cards()
	if index == 0:
		_end_preview()
		rebuild_catalog()

func set_category(value: String) -> void:
	category = value
	page_index = 0
	search.text = ""
	rebuild_catalog()

func _search_changed(_text: String) -> void:
	page_index = 0
	rebuild_catalog()

func _browser_filter(index: int) -> void:
	browser_mode = ["All", "Favorites", "Recent"][index]
	page_index = 0
	rebuild_catalog()
