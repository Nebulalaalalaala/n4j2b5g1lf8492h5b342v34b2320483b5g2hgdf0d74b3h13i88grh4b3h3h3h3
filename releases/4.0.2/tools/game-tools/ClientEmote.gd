extends "res://project_specific/gfx/spine/upguy/emote.gd"
const ModPaths = preload("user://mod/core/ModPaths.gd")

const STATIC_HOLD = 2.0
var _remaining = 0.0
var _hidden_mode = -1

func watch_visibility() -> void:
	# Native world emotes keep a Spine tick even with their empty/hidden skin.
	# Preview skeletons have their separate UI lifecycle; don't own them here.
	var ancestor = get_parent()
	while ancestor != null and not ancestor is UpGuys_PlayerRenderer: ancestor = ancestor.get_parent()
	if ancestor == null: return
	if not is_connected("visibility_changed",self,"_visibility_activity"):
		connect("visibility_changed",self,"_visibility_activity")
	_visibility_activity()

func _visibility_activity() -> void:
	if is_visible_in_tree():
		if _hidden_mode >= 0:
			update_mode = _hidden_mode
			_hidden_mode = -1
	else:
		if _hidden_mode < 0: _hidden_mode = update_mode
		update_mode = SpineConstant.UpdateMode_Manual

func _ready() -> void:
	set_process(false)

func show_loop_animation(anim: String) -> void:
	load(ModPaths.CUSTOM_COSMETICS).patch_emote(self, "")
	.show_loop_animation(anim)
	visible = true

func show_static_frame(anim: String) -> void:
	load(ModPaths.CUSTOM_COSMETICS).patch_emote(self, "")
	.show_static_frame(anim)
	visible = true

func show_single_animation_and_hide(anim: String) -> void:
	_reset_everything()
	load(ModPaths.CUSTOM_COSMETICS).patch_emote(self, load(ModPaths.CUSTOM_COSMETICS).take_pending_emote(anim))
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
	set_process(true)

func _on_animation_completed(_sprite: Object, _state: SpineAnimationState, entry: Object):
	if _hide_after_complete and _popout_entry == entry:
		visible = false
		_hide_after_complete = false
		_popout_entry = null
		_remaining = 0.0
		set_process(false)

func _reset_everything():
	visible = false
	_hide_after_complete = false
	_popout_entry = null
	_remaining = 0.0
	set_process(false)
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
