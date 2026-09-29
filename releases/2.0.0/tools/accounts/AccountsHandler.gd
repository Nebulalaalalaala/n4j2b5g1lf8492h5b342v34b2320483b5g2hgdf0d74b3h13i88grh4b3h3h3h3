extends Reference

# Accounts: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "accounts"
const NAME = "Accounts"
const SWITCHES = {"accounts": "_game_tools_gui_enabled"}   # menu key -> TASTool setting that enables it
const KEYS = ["accounts"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "accounts":
		tas_tool._game_tools._account_access.open_signin()
	return ""
