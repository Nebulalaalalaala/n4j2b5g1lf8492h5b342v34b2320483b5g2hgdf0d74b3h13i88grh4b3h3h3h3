extends CanvasLayer
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")

# Small FPS / ping readout in a screen corner.

const CORNERS = ["Top right", "Top left", "Bottom right", "Bottom left"]

var tool
var enabled = false
var corner = 0
var label
var frames = 0
var elapsed = 0.0


func setup(owner) -> void:
	tool = owner
	layer = 512
	enabled = bool(SavedSettings.get_value("corner_readout_enabled", false))
	corner = int(clamp(int(SavedSettings.get_value("corner_readout_corner", 0)), 0, CORNERS.size() - 1))
	label = Label.new()
	label.add_color_override("font_color", GoobStyle.INK)
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.7))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	label.add_font_override("font", tool._make_font(16))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_place()
	label.visible = enabled


func set_enabled(value: bool) -> void:
	enabled = value
	SavedSettings.set_value("corner_readout_enabled", value)
	label.visible = value


func set_corner(index: int) -> void:
	corner = index
	SavedSettings.set_value("corner_readout_corner", index)
	_place()


func _place() -> void:
	var right = corner == 0 or corner == 2
	var bottom = corner >= 2
	label.anchor_left = 1.0 if right else 0.0
	label.anchor_right = label.anchor_left
	label.anchor_top = 1.0 if bottom else 0.0
	label.anchor_bottom = label.anchor_top
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	label.align = Label.ALIGN_RIGHT if right else Label.ALIGN_LEFT
	label.margin_left = -10 if right else 10
	label.margin_right = label.margin_left
	label.margin_top = -8 if bottom else 8
	label.margin_bottom = label.margin_top


func _process(delta: float) -> void:
	if not enabled:
		return
	frames += 1
	elapsed += delta
	if elapsed < 0.5:
		return
	var text = "%d FPS" % int(round(frames / elapsed))
	frames = 0
	elapsed = 0.0
	var game = tool._find_game() if tool.has_method("_find_game") else null
	if game != null and is_instance_valid(game) and not game.is_server() and game.has_method("get_client_round_trip_time"):
		var seconds = float(game.get_client_round_trip_time())
		# No measurement yet is shown as unknown, never as 0 ms.
		text += ("  ·  %d ms" % int(round(seconds * 1000.0))) if seconds > 0.0 else "  ·  ping -"
	label.text = text
