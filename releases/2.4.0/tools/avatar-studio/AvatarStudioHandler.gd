extends Reference

# Avatar Studio: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "avatar-studio"
const NAME = "Avatar Studio"
const SWITCHES = {"sandbox": "_sandbox_gui_enabled", "loadouts": "_cosmetic_loadouts_gui_enabled"}   # menu key -> TASTool setting that enables it
const KEYS = ["loadouts", "sandbox"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "sandbox":
		var target = tas_tool.get("_cosmetic_sandbox")
		if target == null or not is_instance_valid(target):
			return "This module could not load. Check the action log."
		if "gui_enabled" in target and not target.gui_enabled:
			return "Enable this module in Settings first."
		target.call("_open_modal")
	elif key == "loadouts":
		var target = tas_tool.get("_cosmetic_loadouts")
		if target == null or not is_instance_valid(target):
			return "This module could not load. Check the action log."
		if "gui_enabled" in target and not target.gui_enabled:
			return "Enable this module in Settings first."
		target.call("open_window")
	return ""
