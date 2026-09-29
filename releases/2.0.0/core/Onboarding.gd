extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# First-launch introduction: "Press F1", then a spotlight through Settings to turn a
# tool on. The marker file lives with the saved data (not in mod/), so reinstalling
# never shows it again; Settings → Replay introduction does.
const MARKER = ModPaths.DATA_DIR + "first-launch.cfg"
const TOOL_SWITCHES = ["_sandbox_gui_enabled", "_replay_hub_gui_enabled", "_game_tools_gui_enabled", "_social_hub_gui_enabled",
	"_cosmetic_loadouts_gui_enabled", "_editor_theme_pack_enabled", "_match_map_preview_enabled", "_wins_leaderboard_enabled",
	"_leaderboard_search_enabled", "_custom_lobby_code_enabled"]

var tool
var spot
var step = "open"
var was_hidden = false
var home = null
var switches_before = {}


# "new" on the very first launch on this PC, "returning" when Goobplayability data
# already exists but no marker (intros marked seen), "" otherwise. Writes the marker.
static func check_first_launch() -> String:
	if File.new().file_exists(MARKER):
		return ""
	var returning = false
	var dir = Directory.new()
	if dir.open(ModPaths.DATA_DIR) == OK:
		dir.list_dir_begin(true, true)
		returning = not dir.get_next().empty()
		dir.list_dir_end()
	var config = ConfigFile.new()
	config.set_value("first_launch", "time", OS.get_unix_time())
	if returning:
		for key in ["tour", "journey"]:
			config.set_value("seen", key, true)
	dir.make_dir_recursive(ModPaths.DATA_DIR)
	config.save(MARKER)
	return "returning" if returning else "new"


static func seen(key: String) -> bool:
	var config = ConfigFile.new()
	return config.load(MARKER) == OK and bool(config.get_value("seen", key, false))


static func mark(key: String, value := true) -> void:
	var config = ConfigFile.new()
	config.load(MARKER)
	config.set_value("seen", key, value)
	Directory.new().make_dir_recursive(ModPaths.DATA_DIR)
	config.save(MARKER)


static func replay() -> void:
	for key in ["tour", "journey"]:
		mark(key, false)


func start(tas_tool, hide_overlay: bool) -> void:
	tool = tas_tool
	pause_mode = Node.PAUSE_MODE_PROCESS
	spot = load(ModPaths.path("Spotlight.gd")).new()
	add_child(spot)
	spot.ui_scale = float(tool.get("ui_scale"))
	spot.connect("pressed", self, "_on_pressed")
	if hide_overlay and not bool(tool.get("_overlay_hidden")):
		tool.call("_toggle_overlay_hidden")
	was_hidden = bool(tool.get("_overlay_hidden"))
	get_tree().connect("node_added", self, "_consider_home")
	_scan(get_tree().root, 64)


func _scan(node, depth):
	_consider_home(node)
	if depth > 0:
		for child in node.get_children():
			_scan(child, depth - 1)


func _consider_home(node):
	if node.name == "HomeScene":
		home = weakref(node)


func _at_home() -> bool:
	var node = home.get_ref() if home != null else null
	return node != null and node.is_inside_tree() and tool.call("_find_game") == null


func _process(_delta):
	if tool == null or not is_instance_valid(tool):
		return
	var hidden = bool(tool.get("_overlay_hidden"))
	if was_hidden and not hidden and step == "open":
		tool.call("_set_menu_open", true)
	was_hidden = hidden
	var menu = tool.get("_workspace_menu")
	if hidden:
		if _at_home():
			spot.show_step(null, "Press F1 to open Goobplayability", [["Skip", "skip"]])
		else:
			spot.clear()
		return
	if menu == null or not is_instance_valid(menu) or not bool(tool.get("_menu_open")):
		var tab = tool.get("_tab_button")
		if tab != null and is_instance_valid(tab) and tab.is_visible_in_tree():
			spot.show_step(tab, "Open the Goobplayability menu", [["Skip", "skip"]])
		else:
			spot.clear()
		return
	if step == "open":
		step = "settings"
	if step == "settings":
		if str(menu.get("active")) == "settings":
			step = "tools"
			for key in TOOL_SWITCHES:
				switches_before[key] = bool(tool.get(key))
		else:
			spot.show_step(menu.nav.get("settings"), "Turn tools on in Settings", [["Skip", "skip"]])
			return
	if step == "tools":
		for key in TOOL_SWITCHES:
			if bool(tool.get(key)) and not switches_before.get(key, false):
				step = "done"
		if step == "tools":
			spot.show_step(_tools_card(menu), "Your tools. Turn one on to get started.", [["Skip", "skip"], ["Next", "next", true]])
			return
	if step == "done":
		var sidebar = menu.nav.get("home")
		spot.show_step(sidebar.get_parent() if sidebar != null else null, "It's in the menu now. F1 hides or shows Goobplayability.", [["Got it", "finish", true]])


# The Settings card holding the most tool switches.
func _tools_card(menu):
	var counts = {}
	var best = null
	for entry in menu.get("_setting_checks"):
		if not entry[1] in TOOL_SWITCHES or not is_instance_valid(entry[0]):
			continue
		var card = entry[0].get_parent().get_parent()
		counts[card] = int(counts.get(card, 0)) + 1
		if best == null or counts[card] > counts[best]:
			best = card
	return best


func _on_pressed(id):
	if id == "next":
		step = "done"
		return
	mark("tour")
	spot.clear()
	if bool(tool.get("_overlay_hidden")):
		tool.call("_toggle_overlay_hidden")
	queue_free()
