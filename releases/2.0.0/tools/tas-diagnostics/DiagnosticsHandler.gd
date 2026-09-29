extends Reference

# Developer tools: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "tas-diagnostics"
const NAME = "Developer tools"
const SWITCHES = {"developer": "_debug_mode_enabled", "logs": "_debug_mode_enabled"}   # menu key -> TASTool setting that enables it
const KEYS = ["developer", "logs"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "logs":
		if not tas_tool.get("_debug_mode_enabled"):
			return "Enable Debug tools in Settings to view the action log."
		tas_tool.call("_on_log_tab_pressed")
	return ""
