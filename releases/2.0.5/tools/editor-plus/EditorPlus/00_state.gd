extends CanvasLayer

# EditorPlus: shared state (variables, constants, signals, inner classes), in the original order.

# Uses the native editor, selection and UndoRedo. Optional visuals use namespaced properties.
var tool
var editor
var panel: PanelContainer
var body: VBoxContainer
var selection_label: Label
var message: Label
var fields = {}
var step: SpinBox
var undo_button: Button
var redo_button: Button
var recovery_list: ItemList
var recovery
var confirmation: ConfirmationDialog
var pending_recovery = ""
var elapsed = 0.0
var dragging = false
var drag_offset = Vector2.ZERO
var last_selection = ""
var autosave: CheckBox
var properties
var tween_panel
var groups_panel
var object_order
var library_panel
var geometry
var appearance_panel
var laser_panel
var section_choice: OptionButton
var scale_input: SpinBox
var window_scale = 1.0
var scale_auto_fit = true
var window_size = Vector2(520, 820)
var resizing = false
var resize_grip: Button
var content_scroll: ScrollContainer
var guide
var help_button: Button
var thumbnail_button: Button
var thumbnail = false
var thumbnail_hidden = {}
var thumbnail_scan = 0.0
const RESIZABLE = ["block", "ice_block", "ramp", "background", "background_ramp", "jump_zone", "gravity_field", "disappearing_block"]
const MIRRORABLE = ["block", "ice_block", "ramp", "floor", "pit", "background", "background_ramp", "jump_zone", "gravity_field", "disappearing_block"]
