extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
const ID = "goober-hub"
const NAME = "Goober Hub"
const KEYS = ["goober-hub"]

func enabled(_tool, _key):
	return ModPaths.has("HubScreen.gd") and ModPaths.has("JourneyUI.gd") and ModPaths.has("JourneyArt.gd")

func open(tas_tool, _key):
	if not enabled(tas_tool, _key): return "Goober Hub needs Journey installed."
	var hub = tas_tool.get_node_or_null("GooberHub")
	if hub == null:
		var script = ModPaths.try_load(ModPaths.path("GooberHub.gd"))
		if script == null or not script.can_instance():
			return "Goober Hub could not load. Check the action log."
		hub = script.new()
		hub.name = "GooberHub"
		tas_tool.add_child(hub)
		hub.configure(tas_tool)
	hub.entry_navigation = null
	hub.open()
	return ""
