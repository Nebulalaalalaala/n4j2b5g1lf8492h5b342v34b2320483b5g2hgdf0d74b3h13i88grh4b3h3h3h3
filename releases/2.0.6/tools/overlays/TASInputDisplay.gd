extends CanvasLayer

# Small on-screen overlay showing recorded/live input state for TASTool
# (Phase 1.2 -- Input Display). Reads existing input actions only; never
# writes input, physics, or replay data.

const ACTIONS := ["player_left", "player_right", "player_up", "player_dash"]
const ACTION_LABELS := {
	"player_left": "LEFT",
	"player_right": "RIGHT",
	"player_up": "JUMP",
	"player_dash": "DASH",
}

const COLOR_BG := Color(0.05, 0.07, 0.12, 0.78)
const COLOR_IDLE := Color(0.62, 0.68, 0.78, 0.85)
const COLOR_HELD := Color(0.28, 1.0, 0.85, 1.0)
const COLOR_LIVE := Color(0.36, 0.84, 1.0, 0.95)
const COLOR_REPLAY := Color(1.0, 0.45, 0.75, 0.95)

var tas_tool: Node = null
var display_enabled := false
var detailed := false
var show_hold_frames := false

var _panel: PanelContainer
var _rows := {} # action -> Label
var _hold_labels := {} # action -> Label
var _source_label: Label
var _hold_ticks := {} # action -> int


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	_build_ui()
	visible = false


func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool


func set_display_enabled(value: bool) -> void:
	display_enabled = value
	visible = value
	if not value:
		_hold_ticks.clear()


func set_detailed(value: bool) -> void:
	detailed = value
	_apply_layout()


func set_show_hold_frames(value: bool) -> void:
	show_hold_frames = value
	_apply_layout()


func _physics_process(_delta: float) -> void:
	if not display_enabled:
		return
	for action in ACTIONS:
		if Input.is_action_pressed(action):
			_hold_ticks[action] = int(_hold_ticks.get(action, 0)) + 1
		else:
			_hold_ticks[action] = 0


func _process(_delta: float) -> void:
	if not display_enabled:
		return
	var is_replay := false
	if tas_tool != null and is_instance_valid(tas_tool) and ("_practice_playback" in tas_tool):
		is_replay = bool(tas_tool.get("_practice_playback"))
	for action in ACTIONS:
		var held: bool = Input.is_action_pressed(action)
		var label: Label = _rows.get(action)
		if label != null:
			label.add_color_override("font_color", COLOR_HELD if held else COLOR_IDLE)
		if show_hold_frames:
			var hold_label: Label = _hold_labels.get(action)
			if hold_label != null:
				hold_label.text = str(int(_hold_ticks.get(action, 0))) if held else ""
	if _source_label != null:
		_source_label.visible = detailed
		if detailed:
			_source_label.text = "REPLAY" if is_replay else "LIVE"
			_source_label.add_color_override("font_color", COLOR_REPLAY if is_replay else COLOR_LIVE)


func _build_ui() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
	root.rect_position = Vector2(16, 16)
	add_child(root)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_stylebox_override("panel", style)
	root.add_child(_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_constant_override("separation", 12)
	column.add_child(row)

	for action in ACTIONS:
		var action_column := VBoxContainer.new()
		action_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_column.alignment = BoxContainer.ALIGN_CENTER
		var label := Label.new()
		label.text = ACTION_LABELS.get(action, action)
		label.add_color_override("font_color", COLOR_IDLE)
		label.align = Label.ALIGN_CENTER
		_rows[action] = label
		action_column.add_child(label)
		var hold_label := Label.new()
		hold_label.align = Label.ALIGN_CENTER
		hold_label.add_color_override("font_color", COLOR_IDLE)
		hold_label.visible = false
		_hold_labels[action] = hold_label
		action_column.add_child(hold_label)
		row.add_child(action_column)

	_source_label = Label.new()
	_source_label.align = Label.ALIGN_CENTER
	_source_label.visible = false
	column.add_child(_source_label)

	_apply_layout()


func _apply_layout() -> void:
	for action in ACTIONS:
		var hold_label: Label = _hold_labels.get(action)
		if hold_label != null:
			hold_label.visible = show_hold_frames
	if _source_label != null:
		_source_label.visible = detailed
