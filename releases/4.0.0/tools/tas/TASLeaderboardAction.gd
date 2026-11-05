extends Button

# One action follows the native record card: a centred loading fallback,
# then a full-width action below Race ghost / Watch replay. Never a HUD corner.
var card

func setup(owner):
	card = owner
	card.player_profile_container.connect("visibility_changed",self,"_dock")
	card.dialog.connect("resized",self,"_fit")
	_fit()
	_dock()

func _fit():
	if not is_instance_valid(card): return
	# The native panel is designed at 1000 x 1100. Some editor viewports are
	# smaller than that; fit this card, without changing the global UI scale.
	var available = card.dialog.rect_size-Vector2(32,32)
	card.dialog.panel.rect_scale = Vector2.ONE*min(1.0,min(available.x/1000.0,available.y/1100.0))

func _dock():
	if not is_instance_valid(card): return
	var loaded = card.player_profile_container.visible
	var parent = card.player_profile_container.get_node("InnerPanel") if loaded else card.dialog
	if get_parent()!=parent:
		get_parent().remove_child(self)
		parent.add_child(self)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0 if loaded else 0.5
	anchor_bottom = anchor_top
	margin_left = -400 if loaded else -160
	margin_right = 400 if loaded else 160
	margin_top = 530 if loaded else 75
	margin_bottom = 602 if loaded else 147
	raise()
