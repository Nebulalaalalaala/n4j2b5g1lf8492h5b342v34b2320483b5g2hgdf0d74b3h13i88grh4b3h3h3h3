extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Explicit staged adapter: caller supplies verified HomeScene nodes. No broad
# scene mutation or replacing the native paginator/controller input system.
var tabs
var paginator
var button
var screen
var art
var badge

func attach(native_tabs,native_paginator,journey_screen) -> bool:
	if is_instance_valid(button):
		return true
	var group = native_tabs.get_node_or_null("ButtonGrouper")
	if group == null or group.buttons.size()!=5 or native_paginator.pages.size()!=5:
		return false
	tabs = native_tabs
	# The original bottom strip has a fixed 1080-unit minimum. Six buttons
	# must fit the actual viewport rather than inherit that cropped width.
	var strip = tabs.get_parent_control()
	strip.rect_min_size.x = 0
	strip.margin_left = 0
	strip.margin_right = 0
	if strip.get_parent_control()!=null:
		strip.rect_size.x = strip.get_parent_control().rect_size.x
	paginator = native_paginator
	screen = journey_screen
	art = load(ModPaths.path("JourneyArt.gd")).new()
	var icon = art.texture("journey")
	if icon == null:
		return false
	button = load("res://goodoh/ui/nodes/DeepButton.tscn").instance()
	button.name = "JourneyTab"
	button.label_text = ""
	button.icon_tex = icon
	button.hint_tooltip = "Journey"
	tabs.add_child(button)
	var icon_node = button.get_node("GoodIcon")
	icon_node.expand = true
	icon_node.rect_min_size = Vector2.ZERO
	icon_node.rect_size = Vector2(72,72)
	button.toggle_mode = true
	button.group = group.button_group
	button.connect("pressed",group,"button_pressed",[button])
	group.buttons.append(button)
	# Red "!" on the Journey tab while there's XP to claim somewhere.
	badge = screen.make_badge(40)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.margin_left = -44
	badge.margin_top = -4
	button.add_child(badge)
	screen.connect("claims_changed", self, "_claims_changed")
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	add_child(timer)
	timer.connect("timeout", self, "_refresh_claims")
	screen.name = "JOURNEY"
	paginator.add_child(screen)
	screen.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	call_deferred("_fit_page")
	paginator.connect("resized",self,"_fit_page",[],CONNECT_DEFERRED)
	screen.connect("minimum_size_changed",self,"_fit_page",[],CONNECT_DEFERRED)
	screen.hide()
	paginator.pages.append(screen)
	var tween = Tween.new()
	paginator.add_child(tween)
	paginator.tweens.append(tween)
	tabs.get_parent().connect("resized",self,"resize_tabs")
	get_viewport().connect("size_changed",self,"resize_tabs",[],CONNECT_DEFERRED)
	resize_tabs()
	call_deferred("resize_tabs")
	return true

func _claims_changed(total):
	if is_instance_valid(badge):
		badge.visible = total > 0

# Playtime rewards become claimable while playing; re-check now and then.
func _refresh_claims():
	if is_instance_valid(screen) and screen.model != null and not screen.model.empty():
		screen.update_claims()

func _fit_page():
	if is_instance_valid(screen) and is_instance_valid(paginator):
		screen.margin_top = 0
		screen.margin_bottom = 0
		screen.rect_size = paginator.rect_size

func resize_tabs():
	if not is_instance_valid(tabs):
		return
	var available = max(280,tabs.get_parent().rect_size.x-80)
	var gap = min(24,max(6,available*0.018))
	var width = min(128,(available-5*gap)/6.0)
	tabs.add_constant_override("separation",int(gap))
	for native_button in tabs.get_node("ButtonGrouper").buttons:
		native_button.rect_min_size = Vector2(width,100)
		var icon = native_button.get_node_or_null("GoodIcon")
		if icon != null:
			icon.expand = true
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.rect_min_size = Vector2.ZERO
			icon.rect_size = Vector2.ONE*min(72,max(24,width-20))
	# GoodAnchorPoint continues to center this container in the real HomeScene.
	tabs.rect_size = Vector2(width*6+gap*5,100)
	_seat_tabs()

# Sit the buttons inside the visible part of the dark bottom panel instead of
# on top of it. The panel starts at BottomPanel's top and runs off-screen.
func _seat_tabs():
	var anchor = tabs.get_node_or_null("GoodAnchorPoint")
	var bottom = tabs.get_parent_control()
	if anchor == null or bottom == null:
		return
	var panel = bottom.get_node_or_null("Panel")
	if panel == null:
		anchor.offset.y = -50
		return
	# Measure in window space: the bar starts at the bottom of the page area
	# but its drawn part runs on to the bottom of the window.
	var xform = panel.get_global_transform_with_canvas()
	var scale = max(0.01,xform.get_scale().y)
	var visible = (get_viewport().get_visible_rect().size.y-xform.origin.y)/scale
	# The deep buttons carry an 8-16 px bottom edge, so centre slightly high.
	anchor.offset.y = visible*0.5-6 if visible >= 112 else visible-56
