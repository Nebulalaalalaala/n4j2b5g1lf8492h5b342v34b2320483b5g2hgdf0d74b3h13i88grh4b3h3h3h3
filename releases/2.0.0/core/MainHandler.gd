extends Reference

# Routes Workspace menu keys to the tool that owns them. Each tool has one handler
# (tools/<tool>/<Tool>Handler.gd) that says whether a key is enabled and how it opens.
# Adding a tool = add its handler file name to HANDLERS.

const ModPaths = preload("user://mod/core/ModPaths.gd")
const HANDLERS = [
	"CoreHandler.gd",
	"TasHandler.gd",
	"DiagnosticsHandler.gd",
	"ReplayHubHandler.gd",
	"LevelCouncilHandler.gd",
	"AvatarStudioHandler.gd",
	"SocialHandler.gd",
	"MatchInfoHandler.gd",
	"GameToolsHandler.gd",
	"AccountsHandler.gd",
	"EditorPlusHandler.gd",
	"EditorThemesHandler.gd",
]

# Menu keys and settings that only exist when a tool is installed
# (the installer can leave tools out). Missing file = key hidden.
const KEY_NEEDS = {
	"replays": "ReplayHub.gd", "council": "LevelCouncil.gd", "sandbox": "CosmeticSandbox.gd",
	"loadouts": "CosmeticLoadouts.gd", "social": "SocialHub.gd", "maps": "MatchMapPreview.gd",
	"rated": "MatchMapPreview.gd", "wins": "WinsLeaderboard.gd", "game": "GameTools.gd",
	"accounts": "AccountAccess.gd", "editor-plus": "EditorPlus.gd", "themes": "EditorThemePack.gd",
	"tab:0": "TasHandler.gd", "tab:1": "TasHandler.gd", "timeline": "TASMacroEditor.gd",
	"tab:2": "AutoplayBot.gd", "developer": "DiagnosticsHandler.gd", "logs": "DiagnosticsHandler.gd",
}
const SETTING_NEEDS = {
	"_sandbox_gui_enabled": "CosmeticSandbox.gd", "_replay_hub_gui_enabled": "ReplayHub.gd",
	"_game_tools_gui_enabled": "GameTools.gd", "_social_hub_gui_enabled": "SocialHub.gd",
	"_cosmetic_loadouts_gui_enabled": "CosmeticLoadouts.gd", "_editor_theme_pack_enabled": "EditorThemePack.gd",
	"_match_map_preview_enabled": "MatchMapPreview.gd", "_wins_leaderboard_enabled": "WinsLeaderboard.gd",
	"_debug_mode_enabled": "DiagnosticsHandler.gd", "_leaderboard_search_enabled": "MatchInfoHandler.gd",
	"_custom_lobby_code_enabled": "MatchInfoHandler.gd",
}

var installed = {}
var handlers = []
var by_key = {}

func _init():
	for file_name in HANDLERS:
		var script = ModPaths.try_load(ModPaths.path(file_name))
		if script == null:
			continue
		var handler = script.new()
		handlers.append(handler)
		for key in handler.KEYS:
			by_key[key] = handler

func is_installed(file_name: String) -> bool:
	if not installed.has(file_name):
		installed[file_name] = ModPaths.has(file_name)
	return installed[file_name]

func setting_available(setting: String) -> bool:
	return not SETTING_NEEDS.has(setting) or is_installed(SETTING_NEEDS[setting])

func owns(key: String) -> bool:
	return by_key.has(key)

func enabled(tas_tool, key: String) -> bool:
	if KEY_NEEDS.has(key) and not is_installed(KEY_NEEDS[key]):
		return false
	return not by_key.has(key) or by_key[key].enabled(tas_tool, key)

# "" when handled; otherwise a message to show in the menu.
func open(tas_tool, key: String) -> String:
	return by_key[key].open(tas_tool, key)
