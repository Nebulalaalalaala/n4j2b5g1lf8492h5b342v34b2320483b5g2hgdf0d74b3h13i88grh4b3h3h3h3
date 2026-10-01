extends Reference

# Macro Bot: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "tas"
const NAME = "Macro Bot"
const SWITCHES = {}
const KEYS = ["timeline"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "timeline":
		tas_tool.call("_on_edit_current_practice_macro_pressed")
	return ""
