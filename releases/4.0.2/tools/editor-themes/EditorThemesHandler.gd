extends Reference

# Editor themes: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "editor-themes"
const NAME = "Editor themes"
const SWITCHES = {"themes": "_editor_theme_pack_enabled"}   # menu key -> TASTool setting that enables it
const KEYS = ["themes"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	return ""
