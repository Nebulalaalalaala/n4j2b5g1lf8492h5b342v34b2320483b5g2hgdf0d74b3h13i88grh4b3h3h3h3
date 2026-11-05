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
	# `maximum` is the room actually available between the panel's fixed
	# top-left and the viewport edge. The previous version computed maximum as
	# max(minimum, available) -- which forced maximum back UP to the intended
	# minimum whenever available room was smaller than that, making
	# minimum == maximum and permanently locking the panel at that exact size
	# no matter which way you dragged (near a screen edge, this reproduces as
	# "resize jumps to a tiny size and gets stuck"). Clamping the effective
	# minimum DOWN to whatever is actually available instead guarantees
	# minimum <= maximum always, so there's never a size the panel can get
	# stuck at.
	var maximum: Vector2 = viewport_size - fixed_top_left - margin
	maximum.x = max(40.0, maximum.x)
	maximum.y = max(40.0, maximum.y)
	var floor_size := Vector2(min(minimum.x, maximum.x), min(minimum.y, maximum.y))
	var requested: Vector2 = current + local_delta
	return Vector2(clamp(requested.x, floor_size.x, maximum.x), clamp(requested.y, floor_size.y, maximum.y))


# Resizes a panel that's dragged from its bottom-right corner, but -- unlike
# resized_size() above -- doesn't cap growth at "however far this panel's
# current top-left happens to be from the screen edge". A panel spawned
# well away from the top-left (e.g. a side panel anchored 68% across the
# screen) genuinely has very little room to its own bottom-right, even
# though there's plenty of free space elsewhere on screen -- which is
# exactly what reads as "stuck, can't grow bigger" even though the screen
# clearly isn't full. Here, the achievable size is bounded only by the
# WHOLE viewport, and if growing to the requested size would push the
# panel's bottom/right edge past the screen, its top-left is pulled back
# toward the origin (never past 0,0) to make room instead of refusing the
# resize. Shrinking is unaffected -- overflow is only ever positive when
# growing past an edge, so the position never moves while shrinking.
# Returns {"position": Vector2, "size": Vector2}.
func resized_size_and_position(current_size: Vector2, current_position: Vector2, local_delta: Vector2, minimum: Vector2, viewport_size: Vector2, margin: Vector2 = Vector2(12, 12)) -> Dictionary:
	var full_max: Vector2 = viewport_size - margin
	full_max.x = max(minimum.x, full_max.x)
	full_max.y = max(minimum.y, full_max.y)
	var requested_size: Vector2 = current_size + local_delta
	requested_size.x = clamp(requested_size.x, minimum.x, full_max.x)
	requested_size.y = clamp(requested_size.y, minimum.y, full_max.y)
	var position: Vector2 = current_position
	var overflow_x: float = (position.x + requested_size.x) - (viewport_size.x - margin.x)
	if overflow_x > 0.0:
		position.x = max(0.0, position.x - overflow_x)
	var overflow_y: float = (position.y + requested_size.y) - (viewport_size.y - margin.y)
	if overflow_y > 0.0:
		position.y = max(0.0, position.y - overflow_y)
	return {"position": position, "size": requested_size}
