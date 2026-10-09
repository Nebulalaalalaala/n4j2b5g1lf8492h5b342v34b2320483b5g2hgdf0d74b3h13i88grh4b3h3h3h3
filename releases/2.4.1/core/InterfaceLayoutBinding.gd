extends Node
var service
var target
var space
var slot = null
var key = ""
var title = ""
var scope = ""
var base_position = Vector2.ZERO
var base_scale = Vector2.ONE
var editing = false
var draft = null
var applying = false

func _ready():
	set_process(false)
	pause_mode = Node.PAUSE_MODE_PROCESS
	var bounds = space.get_ref()
	bounds.connect("resized", self, "apply", [], CONNECT_DEFERRED)
	call_deferred("apply")

func is_available():
	return is_instance_valid(target.get_ref()) and is_instance_valid(space.get_ref()) and space.get_ref().is_inside_tree()

func defaults(position, scale = Vector2.ONE):
	base_position = position
	base_scale = scale
	apply()

func layout():
	return draft if editing else service.layouts.get(key)

func apply():
	if not is_available() or applying:
		return
	applying = true
	var node = target.get_ref()
	var bounds = space.get_ref()
	var value = layout()
	var native_slot = slot.get_ref() if slot != null else null
	var show = editing or bool(service.preference({"hud_journey":"hud_journey_button", "hud_hub":"hud_hub_button", "home_stats":"home_stats"}.get(key, key), true))
	if native_slot != null:
		# Slots retain native column spacing only for default placement. A moved
		# button no longer leaves an empty hole; hidden buttons collapse as well.
		native_slot.visible = show and value == null
		node.visible = show
		node.rect_size = node.rect_min_size
		base_position = bounds.get_global_transform().affine_inverse().xform(native_slot.get_global_transform().origin)
	if value == null:
		node.rect_scale = base_scale
		node.rect_position = base_position
	else:
		node.rect_scale = base_scale * float(value.scale)
		var room = bounds.rect_size - node.rect_size * node.rect_scale
		room.x = max(0, room.x)
		room.y = max(0, room.y)
		# Normalize against the screen, not the widget's changing footprint:
		# expanding/collapsing a dropdown must not move its top-left anchor.
		node.rect_position = Vector2(clamp(float(value.x) * bounds.rect_size.x, 0, room.x), clamp(float(value.y) * bounds.rect_size.y, 0, room.y))
	applying = false

func current():
	var value = layout()
	if value != null:
		return value.duplicate(true)
	var node = target.get_ref()
	return position_value(node.rect_position, 1.0)

func position_value(position, scale):
	var bounds = space.get_ref().rect_size
	return {"x": clamp(position.x / max(1, bounds.x), 0, 1), "y": clamp(position.y / max(1, bounds.y), 0, 1), "scale": scale}

func move_window(point):
	var position = space.get_ref().get_global_transform_with_canvas().affine_inverse().xform(point)
	draft = position_value(position, float(current().scale))
	apply()

func resize_to(scale):
	var position = target.get_ref().rect_position
	draft = position_value(position, clamp(scale, 0.5, 1.75))
	apply()

func window_rect():
	var node = target.get_ref()
	var xform = node.get_global_transform_with_canvas()
	return Rect2(xform.origin, node.rect_size * xform.get_scale())
