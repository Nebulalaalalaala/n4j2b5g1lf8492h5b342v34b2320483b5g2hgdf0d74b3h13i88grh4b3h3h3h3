extends Reference

# Shared, presentation-agnostic window geometry for Goobplayability's Godot
# 3 Controls. Individual GUIs still own their content and styling.


func convert_to_pixel_rect(target: Control) -> void:
	if target == null:
		return
	if is_zero_approx(target.anchor_right) and is_zero_approx(target.anchor_bottom):
		return
	var position: Vector2 = target.rect_position
	var size: Vector2 = target.rect_size
	target.anchor_left = 0.0
	target.anchor_top = 0.0
	target.anchor_right = 0.0
	target.anchor_bottom = 0.0
	target.rect_position = position
	target.rect_size = size


func moved_position(current: Vector2, displayed_size: Vector2, screen_delta: Vector2, viewport_size: Vector2, visible_x: float = 120.0, bottom_reach: float = 64.0) -> Vector2:
	var next: Vector2 = current + screen_delta
	next.x = clamp(next.x, -displayed_size.x + visible_x, viewport_size.x - visible_x)
	next.y = clamp(next.y, 0.0, viewport_size.y - bottom_reach)
	return next


func resized_size(current: Vector2, local_delta: Vector2, minimum: Vector2, fixed_top_left: Vector2, viewport_size: Vector2, margin: Vector2 = Vector2(12, 12)) -> Vector2:
	var available: Vector2 = viewport_size - fixed_top_left - margin
	var maximum := Vector2(max(minimum.x, available.x), max(minimum.y, available.y))
	var requested: Vector2 = current + local_delta
	return Vector2(clamp(requested.x, minimum.x, maximum.x), clamp(requested.y, minimum.y, maximum.y))


func available_local_size(viewport_size: Vector2, screen_top_left: Vector2, scale_factor: float) -> Vector2:
	var safe_scale := max(0.01, scale_factor)
	var available: Vector2 = viewport_size - screen_top_left
	return Vector2(max(0.0, available.x / safe_scale), max(0.0, available.y / safe_scale))
