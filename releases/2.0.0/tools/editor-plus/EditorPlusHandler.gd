extends Reference

# Editor+: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "editor-plus"
const NAME = "Editor+"
const SWITCHES = {"editor-plus": "_game_tools_gui_enabled"}   # menu key -> TASTool setting that enables it
const KEYS = ["editor-plus"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "editor-plus":
		var game_tools = tas_tool.get("_game_tools")
		if game_tools != null and game_tools.get("_editor_plus") != null:
			game_tools._editor_plus.open_window()
		else:
			return "Editor+ could not load. Check the action log."
	return ""
