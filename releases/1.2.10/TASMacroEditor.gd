extends CanvasLayer

# Non-destructive timeline editor for saved/current Macro Bot data. All edits
# happen on a deep copy and are committed only through the explicit Save button.

signal editor_closed

const FONT_PATH := "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"
const PLAY_ICON_PATH := "res://project_specific/gfx/icons/icon_play.png"
const SAVE_ICON_PATH := "res://project_specific/gfx/icons/icon-save.png"
const BACK_ICON_PATH := "res://project_specific/gfx/icons/icon_back.png"
const FORWARD_ICON_PATH := "res://project_specific/gfx/icons/icon_forward.png"
const WINDOW_GEOMETRY_SCRIPT_PATH := "user://mod/GoobWindowGeometry.gd"

const NAVY := Color(0.015, 0.075, 0.145, 0.72)
const NAVY_2 := Color(0.02, 0.13, 0.24, 0.68)
const PANEL := Color(0.035, 0.18, 0.31, 0.76)
const BLUE := Color(0.20, 0.58, 0.93)
const PINK := Color(1.0, 0.20, 0.57)
const GREEN := Color(0.18, 0.78, 0.49)
const ORANGE := Color(1.0, 0.57, 0.18)
const WHITE := Color.white
const DIM := Color(0.67, 0.79, 0.91)

const ACTIONS := ["player_up", "player_dash", "player_left", "player_right"]
const ACTION_LABELS := {
	"player_up": "JUMP",
	"player_dash": "DASH",
	"player_left": "LEFT",
	"player_right": "RIGHT",
}
const ACTION_COLORS := {
	"player_up": Color(0.24, 0.86, 1.0),
	"player_dash": Color(1.0, 0.32, 0.60),
	"player_left": Color(0.69, 0.43, 1.0),
	"player_right": Color(0.24, 0.86, 0.49),
}
const STATE_KEY := "__tas_recorded_state"
const DASH_DIRECTION_KEY := "__tas_dash_direction"


class TimelineView extends Control:
	signal frame_selected(frame_index)
	signal viewport_changed(scroll_frame, pixels_per_frame)

	var frames := []
	var boundaries := []
	var selected_frame := 0
	var scroll_frame := 0.0
	var pixels_per_frame := 1.75
	var dragging := false
	var scrubbing := false
	var drag_origin_x := 0.0
	var drag_origin_scroll := 0.0
	var row_h := 42.0
	var header_h := 46.0
	var label_w := 140.0
	var display_font = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		rect_min_size = Vector2(480, 190)

	func set_timeline_data(next_frames: Array, next_boundaries: Array) -> void:
		frames = next_frames
		boundaries = next_boundaries
		selected_frame = clamp(selected_frame, 0, max(0, frames.size() - 1))
		_clamp_scroll()
		update()

	func set_selected_frame(value: int) -> void:
		selected_frame = clamp(value, 0, max(0, frames.size() - 1))
		_ensure_selected_visible()
		update()

	func set_zoom(value: float, anchor_x: float = -1.0) -> void:
		var old_ppf := pixels_per_frame
		pixels_per_frame = clamp(value, 0.08, 18.0)
		if anchor_x >= label_w and old_ppf > 0.0:
			var anchor_frame := scroll_frame + (anchor_x - label_w) / old_ppf
			scroll_frame = anchor_frame - (anchor_x - label_w) / pixels_per_frame
		_clamp_scroll()
		update()
		emit_signal("viewport_changed", scroll_frame, pixels_per_frame)

	func set_scroll(value: float) -> void:
		scroll_frame = value
		_clamp_scroll()
		update()

	func _visible_capacity() -> float:
		return max(1.0, (rect_size.x - label_w) / max(0.08, pixels_per_frame))

	func _clamp_scroll() -> void:
		scroll_frame = clamp(scroll_frame, 0.0, max(0.0, float(frames.size()) - _visible_capacity()))

	func _ensure_selected_visible() -> void:
		var capacity := _visible_capacity()
		if float(selected_frame) < scroll_frame:
			scroll_frame = float(selected_frame)
		elif float(selected_frame) > scroll_frame + capacity - 1.0:
			scroll_frame = float(selected_frame) - capacity + 1.0
		_clamp_scroll()

	func _frame_at_x(x: float) -> int:
		return int(clamp(int(floor(scroll_frame + (x - label_w) / pixels_per_frame)), 0, max(0, frames.size() - 1)))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_LEFT:
				scrubbing = event.pressed and event.position.x >= label_w and not frames.empty()
				if scrubbing:
					selected_frame = _frame_at_x(event.position.x)
					emit_signal("frame_selected", selected_frame)
					update()
			elif event.button_index == BUTTON_MIDDLE:
				dragging = event.pressed
				if dragging:
					drag_origin_x = event.position.x
					drag_origin_scroll = scroll_frame
			elif event.button_index == BUTTON_WHEEL_UP and event.pressed:
				set_zoom(pixels_per_frame * 1.22, event.position.x)
			elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
				set_zoom(pixels_per_frame / 1.22, event.position.x)
		elif event is InputEventMouseMotion:
			if scrubbing:
				selected_frame = _frame_at_x(event.position.x)
				emit_signal("frame_selected", selected_frame)
				update()
			elif dragging:
				scroll_frame = drag_origin_scroll - (event.position.x - drag_origin_x) / max(0.08, pixels_per_frame)
				_clamp_scroll()
				update()
				emit_signal("viewport_changed", scroll_frame, pixels_per_frame)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.008, 0.035, 0.07, 0.68), true)
		draw_rect(Rect2(0, 0, rect_size.x, header_h), Color(0.018, 0.095, 0.17, 0.76), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(label_w, rect_size.y)), Color(0.025, 0.12, 0.21, 0.78), true)
		draw_line(Vector2(label_w, 0), Vector2(label_w, rect_size.y), Color(0.34, 0.7, 0.95, 0.45), 2.0)
		var font = display_font if display_font != null else get_font("font")
		draw_string(font, Vector2(14, 30), "INPUT TRACKS", Color(0.82, 0.9, 0.98))
		for row in range(ACTIONS.size()):
			var y := header_h + row_h * row
			draw_rect(Rect2(label_w, y, rect_size.x - label_w, row_h), Color(1, 1, 1, 0.018 if row % 2 == 0 else 0.038), true)
			draw_line(Vector2(0, y + row_h), Vector2(rect_size.x, y + row_h), Color(1, 1, 1, 0.09), 1.0)
			draw_string(font, Vector2(14, y + 28), ACTION_LABELS[ACTIONS[row]], ACTION_COLORS[ACTIONS[row]])
		if frames.empty():
			draw_string(font, Vector2(label_w + 28, 122), "No frames in this macro", Color(0.7, 0.8, 0.9))
			return
		var start_frame := max(0, int(floor(scroll_frame)))
		var end_frame := min(frames.size() - 1, int(ceil(scroll_frame + _visible_capacity())) + 1)
		var grid_step := _grid_step()
		var first_grid := int(ceil(float(start_frame) / float(grid_step))) * grid_step
		for frame_index in range(first_grid, end_frame + 1, grid_step):
			var x := label_w + (float(frame_index) - scroll_frame) * pixels_per_frame
			draw_line(Vector2(x, header_h), Vector2(x, rect_size.y), Color(1, 1, 1, 0.10), 1.0)
			draw_string(font, Vector2(x + 7, 31), _format_frame_time(frame_index), Color(0.8, 0.88, 0.96))
		for row in range(ACTIONS.size()):
			_draw_action_runs(ACTIONS[row], row, start_frame, end_frame)
		for boundary in boundaries:
			if int(boundary) < start_frame or int(boundary) > end_frame:
				continue
			var bx := label_w + (float(boundary) - scroll_frame) * pixels_per_frame
			draw_line(Vector2(bx, header_h - 9), Vector2(bx, rect_size.y), Color(1.0, 0.65, 0.16, 0.72), 2.0)
			var marker := PoolVector2Array([Vector2(bx - 6, header_h - 9), Vector2(bx + 6, header_h - 9), Vector2(bx, header_h - 1)])
			draw_colored_polygon(marker, Color(1.0, 0.65, 0.16))
		var selected_x := label_w + (float(selected_frame) - scroll_frame) * pixels_per_frame
		draw_rect(Rect2(selected_x, header_h, max(2.0, pixels_per_frame), row_h * ACTIONS.size()), Color(1, 1, 1, 0.14), true)
		draw_line(Vector2(selected_x, 0), Vector2(selected_x, rect_size.y), Color.white, 3.0)

	func _grid_step() -> int:
		for candidate in [10, 30, 60, 120, 300, 600, 1200, 1800, 3600]:
			if float(candidate) * pixels_per_frame >= 118.0:
				return candidate
		return 7200

	func _draw_action_runs(action: String, row: int, start_frame: int, end_frame: int) -> void:
		var run_start := -1
		for frame_index in range(start_frame, end_frame + 2):
			var active := frame_index <= end_frame and bool(frames[frame_index].get(action, false))
			if active and run_start < 0:
				run_start = frame_index
			elif not active and run_start >= 0:
				var x := label_w + (float(run_start) - scroll_frame) * pixels_per_frame
				var width := max(2.0, float(frame_index - run_start) * pixels_per_frame)
				var y := header_h + row_h * row + 7.0
				draw_rect(Rect2(x, y, width, row_h - 14.0), ACTION_COLORS[action], true)
				draw_line(Vector2(x, y + 2), Vector2(x + width, y + 2), ACTION_COLORS[action].lightened(0.28), 2.0)
				run_start = -1

	func _format_frame_time(frame_index: int) -> String:
		var seconds := int(floor(float(frame_index) / 60.0))
		return "%02d:%02d" % [seconds / 60, seconds % 60]


var tas_tool: Node = null
var slot := 0
var working_data := {}
var _root: Control
var _timeline_panel: PanelContainer
var _details_panel: PanelContainer
var _resize_targets := {}
var _resize_minimums := {}
var _resize_grips := {}
var _resizing_panel := ""
var _move_targets := {}
var _moving_panel := ""
var _timeline: TimelineView
var _scroll: HSlider
var _zoom: HSlider
var _frame_spin: SpinBox
var _segment_jump: OptionButton
var _name_edit: LineEdit
var _summary_label: Label
var _active_actions_label: Label
var _freecam_zoom_label: Label
var _freecam_dragging := false
var _status: Label
var _state_label: Label
var _action_checks := {}
var _dash_direction: OptionButton
var _position_x: SpinBox
var _position_y: SpinBox
var _velocity_x: SpinBox
var _velocity_y: SpinBox
var _selected_frame := 0
var _flat_frames := []
var _locations := []
var _boundaries := []
var _dirty := false
var _updating_controls := false
var _title_font: DynamicFont
var _body_font: DynamicFont
var _small_font: DynamicFont
var _window_geometry = null
var _layout_defaults := {}


func _ready() -> void:
	layer = 190
	pause_mode = Node.PAUSE_MODE_PROCESS
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
	if _root.visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close_editor()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	if _root == null or not _root.visible:
		return
	_sync_editor_resize_grips()
	var focus: Control = _root.get_focus_owner()
	if focus is LineEdit or focus is SpinBox:
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
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
		var viewport_size: Vector2 = get_viewport().size
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
		var viewport_size: Vector2 = get_viewport().size
		var requested_minimum: Vector2 = _resize_minimums[key]
		# Resize owns size only. The former implementation sized against the
		# entire viewport and then clamped rect_position inward, which made a
		# panel jump back toward its spawn point after it had been moved. Derive
		# the available size from the panel's fixed top-left instead.
		var resize_delta := Vector2(event.relative.x, event.relative.y)
		if _window_geometry != null:
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
	for key in _move_targets.keys():
		var target: Control = _move_targets[key]
		if target != null and is_instance_valid(target):
			_convert_editor_panel_to_pixel_rect(target)
			_layout_defaults[key] = {"position": target.rect_position, "size": target.rect_size}
			if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("restore_gui_panel_layout"):
				tas_tool.call("restore_gui_panel_layout", "timeline_" + str(key), target, _resize_minimums.get(key, Vector2(240, 120)))
	_sync_editor_resize_grips()


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


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.connect("gui_input", self, "_on_editor_background_gui_input")
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.025)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.add_child(dim)
	_timeline_panel = PanelContainer.new()
	_timeline_panel.anchor_left = 0.015
	_timeline_panel.anchor_top = 0.42
	_timeline_panel.anchor_right = 0.985
	_timeline_panel.anchor_bottom = 0.985
	_timeline_panel.add_stylebox_override("panel", _style(NAVY, Color(0.26, 0.67, 1.0, 0.9), 4, 24))
	_root.add_child(_timeline_panel)
	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 16)
	margin.add_constant_override("margin_right", 16)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	var timeline_section_scroll := ScrollContainer.new()
	timeline_section_scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	timeline_section_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_section_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline_panel.add_child(timeline_section_scroll)
	timeline_section_scroll.add_child(margin)
	var main := VBoxContainer.new()
	main.add_constant_override("separation", 10)
	margin.add_child(main)

	var freecam_panel := PanelContainer.new()
	freecam_panel.anchor_left = 0.015
	freecam_panel.anchor_top = 0.025
	freecam_panel.anchor_right = 0.46
	freecam_panel.anchor_bottom = 0.115
	freecam_panel.add_stylebox_override("panel", _style(NAVY, Color(0.26, 0.67, 1.0), 4, 18))
	_root.add_child(freecam_panel)
	var freecam_row := HBoxContainer.new()
	freecam_row.add_constant_override("separation", 8)
	freecam_panel.add_child(freecam_row)
	var freecam_title := _label("⋮⋮  FREECAM", _body_font, WHITE)
	freecam_title.hint_tooltip = "Right-drag the level or use arrow keys to move the camera."
	freecam_title.valign = Label.VALIGN_CENTER
	freecam_row.add_child(freecam_title)
	_add_editor_move_handle("freecam", freecam_panel, freecam_title)
	var zoom_out := _button("−", PANEL, 52)
	zoom_out.hint_tooltip = "Zoom out"
	zoom_out.connect("pressed", self, "_zoom_freecam", [1.15])
	freecam_row.add_child(zoom_out)
	_freecam_zoom_label = _label("100%", _body_font, WHITE)
	_freecam_zoom_label.rect_min_size = Vector2(82, 48)
	_freecam_zoom_label.align = Label.ALIGN_CENTER
	_freecam_zoom_label.valign = Label.VALIGN_CENTER
	freecam_row.add_child(_freecam_zoom_label)
	var zoom_in := _button("+", PANEL, 52)
	zoom_in.hint_tooltip = "Zoom in"
	zoom_in.connect("pressed", self, "_zoom_freecam", [1.0 / 1.15])
	freecam_row.add_child(zoom_in)
	var center := _button("CENTER", BLUE, 124)
	center.hint_tooltip = "Re-center and follow the scrubbed player."
	center.connect("pressed", self, "_center_freecam")
	freecam_row.add_child(center)
	var reset_camera := _button("RESET", PANEL, 112)
	reset_camera.hint_tooltip = "Restore the level camera position and zoom."
	reset_camera.connect("pressed", self, "_reset_freecam")
	freecam_row.add_child(reset_camera)

	var header := HBoxContainer.new()
	header.add_constant_override("separation", 10)
	main.add_child(header)
	var title := _label("⋮⋮  GOOBPLAYABILITY TIMELINE", _title_font, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_editor_move_handle("timeline", _timeline_panel, title)
	_name_edit = LineEdit.new()
	_name_edit.rect_min_size = Vector2(260, 48)
	_name_edit.add_font_override("font", _body_font)
	_name_edit.placeholder_text = "Macro name"
	_name_edit.connect("text_changed", self, "_on_name_changed")
	header.add_child(_name_edit)
	var save := _button("SAVE CHANGES", GREEN, 175)
	save.hint_tooltip = "Save this edited macro."
	save.connect("pressed", self, "_save_changes")
	header.add_child(save)
	var close := _button("×", PINK, 56)
	close.connect("pressed", self, "close_editor")
	header.add_child(close)

	var transport := HBoxContainer.new()
	transport.add_constant_override("separation", 8)
	main.add_child(transport)
	var previous := _button("‹", PANEL, 54)
	previous.hint_tooltip = "Previous frame"
	previous.connect("pressed", self, "_select_relative", [-1])
	transport.add_child(previous)
	var next := _button("›", PANEL, 54)
	next.hint_tooltip = "Next frame"
	next.connect("pressed", self, "_select_relative", [1])
	transport.add_child(next)
	transport.add_child(_label("Frame", _body_font, DIM))
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 0
	_frame_spin.step = 1
	_frame_spin.rounded = true
	_frame_spin.rect_min_size = Vector2(130, 48)
	_frame_spin.add_font_override("font", _body_font)
	_frame_spin.connect("value_changed", self, "_on_frame_spin_changed")
	transport.add_child(_frame_spin)
	_segment_jump = OptionButton.new()
	_segment_jump.rect_min_size = Vector2(230, 48)
	_segment_jump.add_font_override("font", _body_font)
	_segment_jump.connect("item_selected", self, "_on_segment_selected")
	transport.add_child(_segment_jump)
	var play := _button("▶  PLAY MACRO", BLUE, 190)
	play.hint_tooltip = "Play this working copy without saving first."
	play.connect("pressed", self, "_play_working_copy")
	transport.add_child(play)
	var transport_spacer := Control.new()
	transport_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transport.add_child(transport_spacer)
	_active_actions_label = _label("INPUT: NONE", _body_font, WHITE)
	_active_actions_label.align = Label.ALIGN_RIGHT
	_active_actions_label.valign = Label.VALIGN_CENTER
	_active_actions_label.rect_min_size = Vector2(260, 48)
	transport.add_child(_active_actions_label)

	var view_row := HBoxContainer.new()
	view_row.add_constant_override("separation", 10)
	main.add_child(view_row)
	_summary_label = _label("", _small_font, DIM)
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_row.add_child(_summary_label)
	var zoom_label := _label("TIMELINE ZOOM", _small_font, DIM)
	zoom_label.hint_tooltip = "Mouse wheel also zooms around the cursor."
	view_row.add_child(zoom_label)
	_zoom = HSlider.new()
	_zoom.min_value = 0.08
	_zoom.max_value = 12.0
	_zoom.step = 0.01
	_zoom.value = 1.75
	_zoom.rect_min_size = Vector2(210, 44)
	_zoom.connect("value_changed", self, "_on_zoom_changed")
	view_row.add_child(_zoom)

	_timeline = TimelineView.new()
	_timeline.display_font = _small_font
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.connect("frame_selected", self, "_select_frame")
	_timeline.connect("viewport_changed", self, "_on_timeline_view_changed")
	main.add_child(_timeline)
	_scroll = HSlider.new()
	_scroll.min_value = 0
	_scroll.step = 1
	_scroll.hint_tooltip = "Drag to scrub the player backward and forward through the run."
	_scroll.connect("value_changed", self, "_on_scroll_changed")
	main.add_child(_scroll)

	_details_panel = PanelContainer.new()
	_details_panel.anchor_left = 0.68
	_details_panel.anchor_top = 0.025
	_details_panel.anchor_right = 0.985
	_details_panel.anchor_bottom = 0.395
	_details_panel.add_stylebox_override("panel", _style(NAVY, Color(0.26, 0.67, 1.0, 0.9), 4, 20))
	_root.add_child(_details_panel)
	var details_margin := MarginContainer.new()
	details_margin.add_constant_override("margin_left", 14)
	details_margin.add_constant_override("margin_right", 14)
	details_margin.add_constant_override("margin_top", 12)
	details_margin.add_constant_override("margin_bottom", 12)
	_details_panel.add_child(details_margin)
	var details_root := VBoxContainer.new()
	details_root.add_constant_override("separation", 8)
	details_margin.add_child(details_root)
	var details_title := _label("⋮⋮  FRAME INSPECTOR", _body_font, WHITE)
	details_root.add_child(details_title)
	_add_editor_move_handle("details", _details_panel, details_title)
	var details_scroll := ScrollContainer.new()
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_root.add_child(details_scroll)
	var bottom := VBoxContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_constant_override("separation", 10)
	details_scroll.add_child(bottom)
	var input_panel := _panel_box("SELECTED FRAME INPUT")
	input_panel.rect_min_size = Vector2(0, 0)
	bottom.add_child(input_panel)
	var input_box: VBoxContainer = input_panel.get_child(0)
	for action in ACTIONS:
		var check := CheckButton.new()
		check.text = ACTION_LABELS[action]
		check.add_font_override("font", _body_font)
		check.add_color_override("font_color", ACTION_COLORS[action])
		check.connect("toggled", self, "_on_action_toggled", [action])
		input_box.add_child(check)
		_action_checks[action] = check
	_dash_direction = OptionButton.new()
	_dash_direction.add_font_override("font", _body_font)
	_dash_direction.add_item("Dash direction: LEFT", 0)
	_dash_direction.add_item("Dash direction: RIGHT", 1)
	_dash_direction.connect("item_selected", self, "_on_dash_direction_changed")
	input_box.add_child(_dash_direction)

	var state_panel := _panel_box("AUTHORITATIVE STATE")
	state_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(state_panel)
	var state_box: VBoxContainer = state_panel.get_child(0)
	_state_label = _label("", _small_font, DIM)
	_state_label.autowrap = true
	state_box.add_child(_state_label)
	var values := GridContainer.new()
	values.columns = 2
	state_box.add_child(values)
	_position_x = _number_field(values, "Position X")
	_position_y = _number_field(values, "Position Y")
	_velocity_x = _number_field(values, "Velocity X")
	_velocity_y = _number_field(values, "Velocity Y")
	var apply_state := _button("APPLY STATE VALUES", ORANGE, 210)
	apply_state.hint_tooltip = "Advanced: changing position or velocity can make a macro invalid"
	apply_state.connect("pressed", self, "_apply_state_values")
	state_box.add_child(apply_state)

	var edit_panel := _panel_box("FRAME TOOLS")
	edit_panel.rect_min_size = Vector2(0, 0)
	bottom.add_child(edit_panel)
	var edit_box: VBoxContainer = edit_panel.get_child(0)
	var duplicate := _button("DUPLICATE FRAME", BLUE, 220)
	duplicate.connect("pressed", self, "_duplicate_frame")
	edit_box.add_child(duplicate)
	var neutral := _button("INSERT NEUTRAL COPY", PANEL, 220)
	neutral.connect("pressed", self, "_insert_neutral_frame")
	edit_box.add_child(neutral)
	var move_row := HBoxContainer.new()
	var move_left := _button("← MOVE", PANEL, 105)
	move_left.connect("pressed", self, "_move_frame", [-1])
	move_row.add_child(move_left)
	var move_right := _button("MOVE →", PANEL, 105)
	move_right.connect("pressed", self, "_move_frame", [1])
	move_row.add_child(move_right)
	edit_box.add_child(move_row)
	var delete := _button("DELETE FRAME", PINK, 220)
	delete.connect("pressed", self, "_delete_frame")
	edit_box.add_child(delete)

	_status = _label("Drag the timeline to scrub · Wheel zooms · Right-drag pans the level", _small_font, WHITE)
	main.add_child(_status)
	_add_editor_resize_grip("timeline", _timeline_panel, Vector2(520, 300))
	_add_editor_resize_grip("details", _details_panel, Vector2(300, 220))
	_add_editor_resize_grip("freecam", freecam_panel, Vector2(650, 58))
	call_deferred("_sync_editor_resize_grips")


func _rebuild_timeline() -> void:
	_flat_frames.clear()
	_locations.clear()
	_boundaries.clear()
	var cumulative := 0
	var segments: Array = working_data.get("segments", [])
	for segment_index in range(segments.size()):
		_boundaries.append(cumulative)
		var segment: Array = segments[segment_index]
		for local_index in range(segment.size()):
			_flat_frames.append(segment[local_index])
			_locations.append(Vector2(segment_index, local_index))
			cumulative += 1
	_selected_frame = clamp(_selected_frame, 0, max(0, _flat_frames.size() - 1))
	_timeline.set_timeline_data(_flat_frames, _boundaries)
	_timeline.set_selected_frame(_selected_frame)
	_frame_spin.max_value = max(0, _flat_frames.size() - 1)
	_scroll.max_value = max(0, _flat_frames.size() - 1)
	var duration := float(_flat_frames.size()) / 60.0
	_summary_label.text = "%s FRAMES   ·   %02d:%05.2f   ·   %d CHECKPOINTS" % [_flat_frames.size(), int(duration) / 60, fmod(duration, 60.0), _boundaries.size()]
	_segment_jump.clear()
	for i in range(_boundaries.size()):
		_segment_jump.add_item("Checkpoint %d · frame %d" % [i, _boundaries[i]])
	_refresh_inspector()


func _select_frame(frame_index: int) -> void:
	_selected_frame = clamp(frame_index, 0, max(0, _flat_frames.size() - 1))
	_timeline.set_selected_frame(_selected_frame)
	_refresh_inspector()


func _select_relative(delta: int) -> void:
	_select_frame(_selected_frame + delta)


func _on_frame_spin_changed(value: float) -> void:
	if not _updating_controls:
		_select_frame(int(value))


func _on_segment_selected(index: int) -> void:
	if index >= 0 and index < _boundaries.size():
		_select_frame(int(_boundaries[index]))


func _on_zoom_changed(value: float) -> void:
	_timeline.set_zoom(value)


func _on_scroll_changed(value: float) -> void:
	if not _updating_controls:
		_select_frame(int(value))


func _on_timeline_view_changed(scroll_frame: float, pixels_per_frame: float) -> void:
	_updating_controls = true
	_zoom.value = pixels_per_frame
	_updating_controls = false


func _refresh_inspector() -> void:
	_updating_controls = true
	_frame_spin.value = _selected_frame
	_scroll.value = _selected_frame
	if _flat_frames.empty():
		_state_label.text = "No frame selected"
		_active_actions_label.text = "INPUT: NONE"
		_updating_controls = false
		return
	var frame: Dictionary = _flat_frames[_selected_frame]
	var active_actions := []
	for action in ACTIONS:
		var active := bool(frame.get(action, false))
		_action_checks[action].set_pressed_no_signal(active)
		if active:
			active_actions.append(ACTION_LABELS[action])
	_dash_direction.select(1 if bool(frame.get(DASH_DIRECTION_KEY, true)) else 0)
	_active_actions_label.text = "INPUT: %s" % (" + ".join(active_actions) if not active_actions.empty() else "NONE")
	_active_actions_label.add_color_override("font_color", GREEN if not active_actions.empty() else DIM)
	var location: Vector2 = _locations[_selected_frame]
	var state = frame.get(STATE_KEY, {})
	if typeof(state) == TYPE_DICTIONARY:
		var position: Vector2 = state.get("position", Vector2.ZERO)
		var velocity: Vector2 = state.get("linear_velocity", Vector2.ZERO)
		_position_x.value = position.x
		_position_y.value = position.y
		_velocity_x.value = velocity.x
		_velocity_y.value = velocity.y
		_state_label.text = "Segment %d · local frame %d · %.3fs\nPosition %s   Velocity %s\nDash cooldown %s · Coyote %s · Ground timer %s" % [int(location.x), int(location.y), float(_selected_frame) / 60.0, position, velocity, state.get("dash_cooldown", "—"), state.get("coyote_timer", "—"), state.get("stick_to_ground_timer", "—")]
	else:
		_state_label.text = "Legacy input-only frame · no authoritative state stored"
	_updating_controls = false
	_preview_selected_frame(frame)


func _preview_selected_frame(frame: Dictionary) -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_preview_macro_editor_frame"):
		var shown := bool(tas_tool.call("_preview_macro_editor_frame", frame))
		if not shown and not frame.has(STATE_KEY):
			_status.text = "This old input-only macro has no recorded positions to preview."


func _on_action_toggled(value: bool, action: String) -> void:
	if _updating_controls or _flat_frames.empty():
		return
	_frame_at_selected()[action] = value
	_mark_dirty("Changed %s at frame %d" % [ACTION_LABELS[action], _selected_frame])
	_rebuild_timeline()


func _on_dash_direction_changed(index: int) -> void:
	if _updating_controls or _flat_frames.empty():
		return
	_frame_at_selected()[DASH_DIRECTION_KEY] = index == 1
	_mark_dirty("Changed dash direction at frame %d" % _selected_frame)
	_rebuild_timeline()


func _apply_state_values() -> void:
	if _flat_frames.empty():
		return
	var frame := _frame_at_selected()
	var state = frame.get(STATE_KEY, {})
	if typeof(state) != TYPE_DICTIONARY:
		_status.text = "This legacy frame has no state block to edit."
		return
	state["position"] = Vector2(_position_x.value, _position_y.value)
	state["linear_velocity"] = Vector2(_velocity_x.value, _velocity_y.value)
	frame[STATE_KEY] = state
	_mark_dirty("Advanced state updated — test this macro before relying on it")
	_rebuild_timeline()


func _duplicate_frame() -> void:
	_insert_frame_copy(false)


func _insert_neutral_frame() -> void:
	_insert_frame_copy(true)


func _insert_frame_copy(neutral: bool) -> void:
	if _flat_frames.empty():
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment: Array = working_data["segments"][int(location.x)]
	var copied: Dictionary = segment[int(location.y)].duplicate(true)
	if neutral:
		for action in ACTIONS:
			copied[action] = false
		copied.erase(DASH_DIRECTION_KEY)
	segment.insert(int(location.y) + 1, copied)
	working_data["segments"][int(location.x)] = segment
	_selected_frame += 1
	_mark_dirty("Inserted %s frame" % ("neutral" if neutral else "duplicate"))
	_rebuild_timeline()


func _delete_frame() -> void:
	if _flat_frames.empty():
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment: Array = working_data["segments"][int(location.x)]
	if segment.size() <= 1:
		_status.text = "A segment must keep at least one frame so checkpoint boundaries stay valid."
		return
	segment.remove(int(location.y))
	working_data["segments"][int(location.x)] = segment
	_selected_frame = min(_selected_frame, _flat_frames.size() - 2)
	_mark_dirty("Deleted one frame — timing after it shifted earlier")
	_rebuild_timeline()


func _move_frame(direction: int) -> void:
	if _flat_frames.empty():
		return
	var location: Vector2 = _locations[_selected_frame]
	var segment: Array = working_data["segments"][int(location.x)]
	var local_index := int(location.y)
	var destination := local_index + direction
	if destination < 0 or destination >= segment.size():
		_status.text = "Frames cannot move across checkpoint boundaries."
		return
	var temp = segment[local_index]
	segment[local_index] = segment[destination]
	segment[destination] = temp
	working_data["segments"][int(location.x)] = segment
	_selected_frame += direction
	_mark_dirty("Moved frame within its segment")
	_rebuild_timeline()


func _frame_at_selected() -> Dictionary:
	var location: Vector2 = _locations[_selected_frame]
	return working_data["segments"][int(location.x)][int(location.y)]


func _on_name_changed(value: String) -> void:
	if _updating_controls:
		return
	working_data["name"] = value.strip_edges()
	_mark_dirty("Renamed macro")


func _mark_dirty(message: String) -> void:
	_dirty = true
	_status.text = "UNSAVED · " + message
	_status.add_color_override("font_color", ORANGE)


func _save_changes() -> void:
	working_data["name"] = _name_edit.text.strip_edges()
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_save_macro_editor_data"):
		tas_tool.call("_save_macro_editor_data", slot, working_data.duplicate(true))
		_dirty = false
		_status.text = "Saved safely. Timeline and checkpoint boundaries rebuilt."
		_status.add_color_override("font_color", GREEN)


func _play_working_copy() -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_play_macro_editor_data"):
		var play_slot := slot
		var play_data := working_data.duplicate(true)
		close_editor()
		tas_tool.call("_play_macro_editor_data", play_slot, play_data)


func _number_field(parent: GridContainer, title: String) -> SpinBox:
	parent.add_child(_label(title, _small_font, DIM))
	var field := SpinBox.new()
	field.min_value = -1000000
	field.max_value = 1000000
	field.step = 0.01
	field.rect_min_size = Vector2(175, 46)
	field.add_font_override("font", _body_font)
	parent.add_child(field)
	return field


func _panel_box(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_stylebox_override("panel", _style(NAVY_2, Color(0.2, 0.48, 0.72), 2, 16))
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 5)
	box.add_child(_label(title, _body_font, WHITE))
	panel.add_child(box)
	return panel


func _font(size: int) -> DynamicFont:
	var font := DynamicFont.new()
	var data = load(FONT_PATH)
	if data != null:
		data = data.duplicate()
		data.antialiased = true
		data.override_oversampling = 2.0
	font.font_data = data
	font.size = size
	font.outline_size = 1
	font.outline_color = Color(0, 0.025, 0.06, 0.95)
	font.use_filter = true
	font.use_mipmaps = true
	return font


func _label(text: String, font: DynamicFont, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_font_override("font", font)
	label.add_color_override("font_color", color)
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.95))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 2)
	return label


func _button(text: String, color: Color, width: int, icon_path: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.rect_min_size = Vector2(width, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_font_override("font", _body_font)
	button.add_stylebox_override("normal", _style(color, WHITE, 3, 14))
	button.add_stylebox_override("hover", _style(color.lightened(0.14), WHITE, 3, 14))
	button.add_stylebox_override("pressed", _style(color.darkened(0.18), WHITE, 3, 14))
	if not icon_path.empty():
		var icon = load(icon_path)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
	return button


func _style(color: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
