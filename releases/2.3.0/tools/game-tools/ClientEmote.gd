extends "res://project_specific/gfx/spine/upguy/emote.gd"

const STATIC_HOLD = 2.0
var _remaining = 0.0

func show_loop_animation(anim: String) -> void:
	.show_loop_animation(anim)
	visible = true

func show_static_frame(anim: String) -> void:
	.show_static_frame(anim)
	visible = true

func show_single_animation_and_hide(anim: String) -> void:
	_reset_everything()
	var animation = get_skeleton().get_data().find_animation(anim)
	if animation == null:
		visible = false
		return
	var duration: float = animation.get_duration()
	var hold: float = STATIC_HOLD if duration <= 0.001 else 0.0
	visible = true
	_hide_after_complete = true
	var state = get_animation_state()
	state.set_animation("popin", 0.0, false)
	state.add_animation(anim, 0.0, false)
	_popout_entry = state.add_animation("popout", hold, false)
	_remaining = 0.8 + duration + hold + 0.5

func _on_animation_completed(_sprite: Object, _state: SpineAnimationState, entry: Object):
	if _hide_after_complete and _popout_entry == entry:
		visible = false
		_hide_after_complete = false
		_popout_entry = null
		_remaining = 0.0

func _reset_everything():
	visible = false
	_hide_after_complete = false
	_popout_entry = null
	_remaining = 0.0
	._reset_everything()

func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	var owner_node = get_parent()
	while owner_node != null and not owner_node.has_method("get_network_object"):
		owner_node = owner_node.get_parent()
	if owner_node != null:
		var player = owner_node.get_network_object()
		if player == null or not player.alive:
			_remaining = 0.0
	if _remaining <= 0.0 or not visible:
		visible = false
		_reset_everything()
