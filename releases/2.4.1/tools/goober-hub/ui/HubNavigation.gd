extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Goober Hub's tab in the home screen's bottom bar (after Journey's), plus the
# unread-messages dot. The Hub itself starts with the game so encounters and
# your feed events are noted even before it is first opened.
var tool
var tabs
var paginator
var page
var button
var dot
var hub
var retry_timer
var pending_home
var tries = 0
var _hud = null

func _ready():
	if not _available(): return
	pause_mode = Node.PAUSE_MODE_PROCESS
	call_deferred("_start")

func _start():
	hub = _hub()
	if hub != null:
		hub.connect("unread_changed", self, "_unread")
	get_tree().connect("node_added", self, "_consider")
	_scan(get_tree().root)

func _available():
	var handler = ModPaths.try_load(ModPaths.path("GooberHubHandler.gd"))
	return handler != null and handler.can_instance() and handler.new().enabled(tool, "goober-hub")

func _hub():
	var existing = tool.get_node_or_null("GooberHub")
	if existing != null: return existing
	var script = ModPaths.try_load(ModPaths.path("GooberHub.gd"))
	if script == null or not script.can_instance(): return null
	var node = script.new()
	node.name = "GooberHub"
	tool.add_child(node)
	node.configure(tool)
	return node

func _scan(node):
	_consider(node)
	for child in node.get_children(): _scan(child)

func _consider(node):
	if node.name == "HomeScene": call_deferred("_prepare", weakref(node))
	elif node.name == "GameHUD" and node is Control: get_tree().create_timer(0.2).connect("timeout", self, "_attach_hud", [weakref(node)])

# In a match: a button in the HUD's top-right column, under Journey's (or the cog).
func _attach_hud(reference):
	var hud = reference.get_ref()
	if not is_instance_valid(hud) or not is_instance_valid(hub):
		return
	var column = hud.get_node_or_null("Container/TopRight/VBoxContainer")
	var settings = column.get_node_or_null("SettingsButton") if column != null else null
	if settings == null or column.has_node("GooberHubButton"):
		return
	var scene = load("res://project_specific/ui/button_styles/FlatButtonWhite.tscn")
	var icon = load(ModPaths.path("HubScreen.gd")).icon_texture("hub_hud.png")
	if scene == null or icon == null:
		return
	var hud_button = scene.instance()
	hud_button.name = "GooberHubButton"
	hud_button.rect_min_size = settings.rect_min_size
	hud_button.set("swatch", settings.get("swatch"))
	hud_button.set("icon_tex", icon)
	hud_button.hint_tooltip = "Goober Hub"
	column.add_child(hud_button)
	var after = column.get_node_or_null("JourneyButton")
	column.move_child(hud_button, (after if after != null else settings).get_index() + 1)
	hud_button.connect("pressed", self, "_open_from_hud", [weakref(hud)])
	load(ModPaths.path("InterfaceLayout.gd")).acquire(get_tree()).bind_hud(hud_button, hud, "hud_hub", "Goober Hub button")

func _open_from_hud(reference):
	_hud = reference
	hub.open_from_hud()

# While open from a match, the HUD's Goober Hub or Journey button closes it.
func _input(event):
	if _hud == null or not is_instance_valid(hub) or not hub.from_hud or not hub.is_interface_open():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		var hud_script = ModPaths.try_load(ModPaths.path("JourneyHud.gd"))
		var hud = _hud.get_ref()
		if hud_script != null and hud_script.hud_button_hit(hud, event.position):
			hub.back()
			get_tree().set_input_as_handled()

func _prepare(reference):
	if is_instance_valid(button): return
	pending_home = reference
	tries = 0
	if not is_instance_valid(retry_timer):
		retry_timer = Timer.new()
		retry_timer.wait_time = 0.5
		add_child(retry_timer)
		retry_timer.connect("timeout", self, "_try_attach")
	_try_attach()
	if pending_home != null: retry_timer.start()

func _try_attach():
	var home = pending_home.get_ref() if pending_home != null else null
	tries += 1
	if not is_instance_valid(home) or tries > 20:
		pending_home = null
		if is_instance_valid(retry_timer): retry_timer.stop()
		return
	var content = home.get_node_or_null("MainContentContainer")
	if content == null: content = home.get_node_or_null("HomeScene/MainContentContainer")
	if content == null: return
	var native_tabs = content.get_node_or_null("BottomPanel/Tabs")
	var pages = content.get_node_or_null("SafeArea/FocusGroup/Paginator")
	if native_tabs == null or pages == null: return
	var group = native_tabs.get_node_or_null("ButtonGrouper")
	if group == null or group.buttons.size() != pages.pages.size(): return
	# Journey's adapter expects the original five tabs, so it attaches first.
	if ModPaths.has("JourneyHandler.gd") and not native_tabs.has_node("JourneyTab") and tries < 16: return
	if group.buttons.size() < 5 or native_tabs.has_node("GooberHubTab"): return
	if attach(native_tabs, pages):
		pending_home = null
		retry_timer.stop()

func attach(native_tabs, native_paginator):
	var group = native_tabs.get_node_or_null("ButtonGrouper")
	if group == null or group.buttons.size() != native_paginator.pages.size(): return false
	var icon = load(ModPaths.path("HubScreen.gd")).icon_texture()
	if icon == null: return false
	tabs = native_tabs
	paginator = native_paginator
	button = load("res://goodoh/ui/nodes/DeepButton.tscn").instance()
	button.name = "GooberHubTab"
	button.label_text = ""
	button.icon_tex = icon
	button.hint_tooltip = "Goober Hub"
	tabs.add_child(button)
	button.toggle_mode = true
	button.group = group.button_group
	button.connect("pressed", group, "button_pressed", [button])
	group.buttons.append(button)
	dot = Panel.new()
	var look = StyleBoxFlat.new()
	look.bg_color = Color("ff4d6d")
	look.set_corner_radius_all(12)
	look.border_color = Color("0b2149")
	look.set_border_width_all(3)
	dot.add_stylebox_override("panel", look)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 1.0
	dot.anchor_right = 1.0
	dot.margin_left = -30
	dot.margin_right = -6
	dot.margin_top = 2
	dot.margin_bottom = 26
	button.add_child(dot)
	_unread(hub.chat.total_unread(hub.store.data.muted) if hub != null else 0)
	page = Control.new()
	page.name = "GOOBER_HUB"
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paginator.add_child(page)
	page.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	page.hide()
	paginator.pages.append(page)
	var tween = Tween.new()
	paginator.add_child(tween)
	paginator.tweens.append(tween)
	paginator.connect("page_changed", self, "_page_changed")
	paginator.connect("resized", self, "fit", [], CONNECT_DEFERRED)
	page.connect("tree_exiting", self, "_home_exiting")
	tabs.get_parent().connect("resized", self, "resize_tabs")
	if not get_viewport().is_connected("size_changed", self, "resize_tabs"):
		get_viewport().connect("size_changed", self, "resize_tabs", [], CONNECT_DEFERRED)
	resize_tabs()
	call_deferred("resize_tabs")
	return true

func _unread(count):
	if is_instance_valid(dot): dot.visible = int(count) > 0

func _page_changed(selected):
	if selected == page:
		hub = _hub()
		if hub == null:
			return_home()
			return
		hub.entry_navigation = self
		hub.open()
	elif is_instance_valid(hub) and hub.entry_navigation == self and hub.is_interface_open():
		hub.screen.close()
		hub.entry_navigation = null
		tool._update_mouse_capture()

func return_home():
	open_page("HOME")

func open_page(page_name):
	if not is_instance_valid(paginator) or not is_instance_valid(tabs): return
	var index = paginator.pages.find(paginator.get_node_or_null(page_name))
	if index >= 0: tabs.get_node("ButtonGrouper").set_selected(index)

func _home_exiting():
	if is_instance_valid(hub) and hub.entry_navigation == self:
		hub.screen.close()
		hub.entry_navigation = null
	button = null

func resize_tabs():
	if not is_instance_valid(tabs): return
	var buttons = tabs.get_node("ButtonGrouper").buttons
	var count = buttons.size()
	var available = max(280, tabs.get_parent().rect_size.x - 80)
	var gap = min(24, max(6, available * 0.018))
	var width = min(128, (available - (count - 1) * gap) / count)
	tabs.add_constant_override("separation", int(gap))
	for native_button in buttons:
		native_button.rect_min_size = Vector2(width, 100)
		var icon = native_button.get_node_or_null("GoodIcon")
		if icon != null:
			icon.expand = true
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.rect_min_size = Vector2.ZERO
			icon.rect_size = Vector2.ONE * min(72, max(24, width - 20))
	tabs.rect_size = Vector2(width * count + gap * (count - 1), 100)
	var anchor = tabs.get_node_or_null("GoodAnchorPoint")
	var panel = tabs.get_parent_control().get_node_or_null("Panel")
	if anchor != null and panel != null:
		var transform = panel.get_global_transform_with_canvas()
		var visible_height = (get_viewport().get_visible_rect().size.y - transform.origin.y) / max(0.01, transform.get_scale().y)
		anchor.offset.y = visible_height * 0.5 - 6 if visible_height >= 112 else visible_height - 56
	fit()

func fit():
	if is_instance_valid(hub) and hub.is_interface_open(): hub.screen.fit()

# Where the Hub may draw: between the native header and the bottom bar.
func frame_rect(factor):
	if not is_instance_valid(paginator) or paginator.rect_size.y < 200: return null
	var transform = paginator.get_global_transform_with_canvas()
	var scale = transform.get_scale().abs()
	var origin = transform.origin
	var end = origin + paginator.rect_size * scale
	var top = max(116.0, (origin.y + 112 * scale.y) / factor)
	var bottom = min(940.0, (end.y - 16 * scale.y) / factor)
	var panel = tabs.get_parent_control().get_node_or_null("Panel") if is_instance_valid(tabs) else null
	if panel != null:
		bottom = min(bottom, (panel.get_global_transform_with_canvas().origin.y - 12 * scale.y) / factor)
	var left = max(60.0, (origin.x + 20 * scale.x) / factor)
	var right = min(1860.0, (end.x - 20 * scale.x) / factor)
	if right - left < 600 or bottom - top < 220: return null
	return Rect2(left, top, right - left, bottom - top)
