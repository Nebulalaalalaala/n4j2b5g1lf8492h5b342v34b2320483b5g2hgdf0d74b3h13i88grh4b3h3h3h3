extends Node

# Workshop and News as tabs in the home screen's bottom bar, after Journey and
# Goober Hub. Choosing one opens that page in the Goobplayability window and
# returns the bar to Home. Same attach pattern as Goober Hub's tab.

const ModPaths = preload("user://mod/core/ModPaths.gd")
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const TABS = [["WorkshopTab", "WORKSHOP_4", "Workshop", "workshop", "tab-workshop.png"], ["NewsTab", "NEWS_4", "News", "news", "tab-news.png"]]

var tool
var menu
var pending_home = null
var retry_timer: Timer
var tries = 0
var paginator
var tabs
var pages = {}

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("node_added", self, "_consider")
	_scan(get_tree().root)

func _scan(node):
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _consider(node):
	if node.name == "HomeScene":
		pending_home = weakref(node)
		tries = 0
		if retry_timer == null:
			retry_timer = Timer.new()
			retry_timer.wait_time = 0.5
			add_child(retry_timer)
			retry_timer.connect("timeout", self, "_try_attach")
		retry_timer.start()

func _try_attach():
	var home = pending_home.get_ref() if pending_home != null else null
	tries += 1
	if not is_instance_valid(home) or tries > 30:
		retry_timer.stop()
		return
	var content = home.get_node_or_null("MainContentContainer")
	if content == null:
		content = home.get_node_or_null("HomeScene/MainContentContainer")
	if content == null:
		return
	var native_tabs = content.get_node_or_null("BottomPanel/Tabs")
	var native_pages = content.get_node_or_null("SafeArea/FocusGroup/Paginator")
	if native_tabs == null or native_pages == null or native_tabs.has_node("WorkshopTab"):
		return
	var group = native_tabs.get_node_or_null("ButtonGrouper")
	if group == null or group.buttons.size() != native_pages.pages.size():
		return
	# Journey and Goober Hub attach first; wait for them while they load.
	if ModPaths.has("JourneyHandler.gd") and not native_tabs.has_node("JourneyTab") and tries < 16:
		return
	if ModPaths.has("GooberHub.gd") and not native_tabs.has_node("GooberHubTab") and tries < 20:
		return
	tabs = native_tabs
	paginator = native_pages
	pages.clear()
	for entry in TABS:
		var icon = Galaxy.texture(entry[4])
		if icon == null:
			continue
		var button = load("res://goodoh/ui/nodes/DeepButton.tscn").instance()
		button.name = entry[0]
		button.label_text = ""
		button.icon_tex = icon
		button.hint_tooltip = entry[2]
		tabs.add_child(button)
		button.toggle_mode = true
		button.group = group.button_group
		button.connect("pressed", group, "button_pressed", [button])
		group.buttons.append(button)
		var page = Control.new()
		page.name = entry[1]
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paginator.add_child(page)
		page.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		page.hide()
		paginator.pages.append(page)
		var tween = Tween.new()
		paginator.add_child(tween)
		paginator.tweens.append(tween)
		pages[page] = entry[3]
	paginator.connect("page_changed", self, "_page_changed")
	# Goober Hub's navigation sizes the whole bar; ask it to include our tabs.
	for node in [tool] + tool.get_children():
		var script = node.get_script()
		if script != null and str(script.resource_path).ends_with("HubNavigation.gd"):
			node.call_deferred("resize_tabs")
	retry_timer.stop()

func _page_changed(selected):
	if not pages.has(selected):
		return
	var key = pages[selected]
	print("[Workspace] bottom tab opened ", key)
	call_deferred("_back_home")
	# F1-hidden overlay: show it again (that also opens the menu).
	if bool(tool.get("_overlay_hidden")) and tool.has_method("_toggle_overlay_hidden"):
		tool.call("_toggle_overlay_hidden")
	if not bool(tool.get("_menu_open")):
		tool.call("_set_menu_open", true)
	menu.select(key)

func _back_home():
	if not is_instance_valid(paginator) or not is_instance_valid(tabs):
		return
	var index = paginator.pages.find(paginator.get_node_or_null("HOME"))
	if index >= 0:
		tabs.get_node("ButtonGrouper").set_selected(index)
