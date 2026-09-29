extends Reference

# Match maps and wins: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "match-info"
const NAME = "Match maps and wins"
const SWITCHES = {"maps": "_match_map_preview_enabled", "rated": "_match_map_preview_enabled", "wins": "_wins_leaderboard_enabled"}   # menu key -> TASTool setting that enables it
const KEYS = ["maps", "rated", "wins"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "maps":
		var target = tas_tool.get("_match_map_preview")
		if target == null or not is_instance_valid(target):
			return "This module could not load. Check the action log."
		if "gui_enabled" in target and not target.gui_enabled:
			return "Enable this module in Settings first."
		target.call("open_window")
	return ""
