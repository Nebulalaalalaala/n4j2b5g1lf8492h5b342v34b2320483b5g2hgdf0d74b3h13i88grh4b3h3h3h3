extends Reference

# Workspace: the entry point the main handler (core/MainHandler.gd) talks to.
# It owns the Workspace menu keys below: whether each is enabled and how it opens.

const ID = "core"
const NAME = "Workspace"
const SWITCHES = {}
const KEYS = ["reset-layout", "rollback", "updates", "intro", "install-update"]

func enabled(tas_tool, key: String) -> bool:
	return not SWITCHES.has(key) or bool(tas_tool.get(SWITCHES[key]))

# Opens the page/window for key. Returns "" when handled, or a message for the menu.
func open(tas_tool, key: String) -> String:
	if key == "reset-layout":
		tas_tool.call("_on_reset_gui_layout_pressed")
	elif key == "updates":
		tas_tool.call("_on_updater_check_now_pressed")
	elif key == "rollback":
		tas_tool.call("_on_updater_rollback_pressed")
	elif key == "install-update":
		if tas_tool.get("_pending_update_manifest").empty():
			return "No update to install. Use Check for updates first."
		tas_tool.call("_on_updater_install_pressed")
	elif key == "intro":
		tas_tool.call("_replay_onboarding")
	return ""
