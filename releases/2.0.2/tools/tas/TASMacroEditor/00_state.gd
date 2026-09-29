extends CanvasLayer

# TASMacroEditor: shared state (variables, constants, signals, inner classes), in the original order.

const ModPaths = preload("user://mod/core/ModPaths.gd")

# Non-destructive timeline editor for saved/current Macro Bot data. All edits
# happen on a deep copy and are committed only through the explicit Save button.

signal editor_closed

const FONT_PATH := "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"
const CLAUDE_EXPERIMENTAL_FONT_PATH := ModPaths.MAIN_FONT
const WINDOW_GEOMETRY_SCRIPT_PATH := ModPaths.WINDOW_GEOMETRY

const NAVY := Color(0.015, 0.075, 0.145, 0.72)
const NAVY_2 := Color(0.02, 0.13, 0.24, 0.68)
const PANEL := Color(0.035, 0.18, 0.31, 0.76)
const BLUE := Color(0.20, 0.58, 0.93)
const PINK := Color(1.0, 0.20, 0.57)
const GREEN := Color(0.18, 0.78, 0.49)
const ORANGE := Color(1.0, 0.57, 0.18)
const WHITE := Color.white
const DIM := Color(0.67, 0.79, 0.91)

# ---- Claude Experimental Mode "modern black" theme palette ----
# Only ever read through _theme_fill()/_theme_border()/_theme_text() below,
# and only when _modern_theme_active() is true, so the classic look above
# is completely unchanged for anyone with the toggle off.
const MODERN_BG := Color(0.094, 0.110, 0.125)
const MODERN_BG_2 := Color(0.133, 0.157, 0.173)
const MODERN_BORDER := Color(0.32, 0.34, 0.38)
const MODERN_WHITE := Color(0.93, 0.94, 0.96)
const MODERN_DIM := Color(0.58, 0.6, 0.66)

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
		rect_min_size = Vector2(480, header_h + row_h * ACTIONS.size())

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

	func _draw_action_symbol(action: String, center: Vector2) -> void:
		var color: Color = ACTION_COLORS[action]
		if action == "player_dash":
			var bolt := PoolVector2Array([Vector2(3, -11), Vector2(-8, 2), Vector2(-1, 2), Vector2(-4, 11), Vector2(8, -3), Vector2(1, -3)])
			for index in range(bolt.size()):
				bolt[index] += center
			draw_colored_polygon(bolt, color)
			return
		var direction := Vector2.UP if action == "player_up" else (Vector2.LEFT if action == "player_left" else Vector2.RIGHT)
		var side := Vector2(-direction.y, direction.x)
		draw_line(center - direction * 9, center + direction * 9, color, 3.0, true)
		draw_line(center + direction * 9, center + side * 6, color, 3.0, true)
		draw_line(center + direction * 9, center - side * 6, color, 3.0, true)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.008, 0.035, 0.07, 0.68), true)
		draw_rect(Rect2(0, 0, rect_size.x, header_h), Color(0.018, 0.095, 0.17, 0.76), true)
		draw_rect(Rect2(Vector2.ZERO, Vector2(label_w, rect_size.y)), Color(0.025, 0.12, 0.21, 0.78), true)
		draw_line(Vector2(label_w, 0), Vector2(label_w, rect_size.y), Color(0.34, 0.7, 0.95, 0.45), 2.0)
		var font = display_font if display_font != null else get_font("font")
		draw_string(font, Vector2(14, 30), "INPUT", Color(0.82, 0.9, 0.98))
		for row in range(ACTIONS.size()):
			var y := header_h + row_h * row
			draw_rect(Rect2(label_w, y, rect_size.x - label_w, row_h), Color(1, 1, 1, 0.018 if row % 2 == 0 else 0.038), true)
			draw_line(Vector2(0, y + row_h), Vector2(rect_size.x, y + row_h), Color(1, 1, 1, 0.09), 1.0)
			_draw_action_symbol(ACTIONS[row], Vector2(22, y + 21))
			draw_string(font, Vector2(44, y + 28), ACTION_LABELS[ACTIONS[row]], ACTION_COLORS[ACTIONS[row]])
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
var _preview_direction := 0
var _preview_fraction := 0.0
var _preview_speed := 1.0
var _preview_clock: Label
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
var _timeline_content: VBoxContainer
var _layout_root_size := Vector2.ZERO

# Claude Experimental Mode -- see TASTool.gd's SETTING_CLAUDE_EXPERIMENTAL_ICONS
# comment. Off by default; set via set_claude_experimental_icons_enabled()
# (called by TASTool.gd). Purely cosmetic -- swaps in an icon next to this
# window's title, nothing else changes.
var _claude_experimental_icons_enabled: = false
var _claude_icon_texture_cache: = {}
var _claude_modern_font_data: DynamicFontData = null
var _claude_modern_font_load_attempted: = false
var _claude_title_icon: TextureRect = null
