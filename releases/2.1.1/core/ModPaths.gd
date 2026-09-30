extends Reference

# Where every mod file lives. Moving a file = change its folder here.
# Load with: const ModPaths = preload("user://mod/core/ModPaths.gd")

const ROOT: = "user://mod/"

# Shared assets
const SHARED_ASSETS_DIR: = ROOT + "shared/assets/"
const FONTS_DIR: = SHARED_ASSETS_DIR + "fonts/"
const ICONS_DIR: = SHARED_ASSETS_DIR + "icons/"
const THEME_BACKGROUNDS_DIR: = SHARED_ASSETS_DIR + "theme_backgrounds/"
const MAIN_FONT: = FONTS_DIR + "Inter-SemiBold.ttf"
const WORKSPACE_ATLAS: = ICONS_DIR + "workspace-atlas.png"

# Folders
const CORE_DIR: = ROOT + "core/"
const TOOLS_DIR: = ROOT + "tools/"
const JOURNEY_DIR: = TOOLS_DIR + "journey/"
const JOURNEY_ASSETS_DIR: = JOURNEY_DIR + "assets/"

# Scripts referenced by constant
const WORKSPACE_MENU: = ROOT + "core/WorkspaceMenu.gd"
const WINDOW_GEOMETRY: = ROOT + "core/GoobWindowGeometry.gd"
const UPDATER: = ROOT + "core/GoobUpdater.gd"
const POST_PHYSICS_GUARD: = ROOT + "tools/tas/TASPostPhysicsGuard.gd"
const MACRO_EDITOR: = ROOT + "tools/tas/TASMacroEditor.gd"
const WORLD_OVERLAY: = ROOT + "tools/overlays/TASWorldOverlay.gd"
const INPUT_DISPLAY: = ROOT + "tools/overlays/TASInputDisplay.gd"
const AUTOPLAY_BOT: = ROOT + "tools/autoplay/AutoplayBot.gd"
const GAME_TOOLS: = ROOT + "tools/game-tools/GameTools.gd"
const REPLAY_HUB: = ROOT + "tools/replay-hub/ReplayHub.gd"
const SOCIAL_HUB: = ROOT + "tools/social/SocialHub.gd"
const COSMETIC_SANDBOX: = ROOT + "tools/avatar-studio/CosmeticSandbox.gd"
const COSMETIC_LOADOUTS: = ROOT + "tools/avatar-studio/CosmeticLoadouts.gd"
const COSMETIC_TRANSFORMS: = ROOT + "shared/scripts/CosmeticTransforms.gd"
const AVATAR_STUDIO: = ROOT + "tools/avatar-studio/AvatarStudio.gd"
const EDITOR_THEME_PACK: = ROOT + "tools/editor-themes/EditorThemePack.gd"
const MATCH_MAP_PREVIEW: = ROOT + "tools/match-info/MatchMapPreview.gd"
const WINS_LEADERBOARD: = ROOT + "tools/match-info/WinsLeaderboard.gd"
const JOURNEY_HANDLER: = ROOT + "tools/journey/JourneyHandler.gd"
const JOURNEY_PROFILE_BADGES: = ROOT + "tools/journey/ui/JourneyProfileBadges.gd"

# Saved data (everything Goobplayability writes lives under DATA_DIR; accounts/ and journey/ were already there)
const DATA_DIR: = "user://goobplayability/"
const PRACTICE_MACRO_DIR: = DATA_DIR + "tas_practice_macros"
const MACRO_SLOTS_CFG: = DATA_DIR + "tas_macro_slots.cfg"
const DIAGNOSTICS_DIR: = DATA_DIR + "tas_diagnostics"
const DEBUG_MODE_CFG: = DATA_DIR + "tas_debug_mode.cfg"
const FPS_LIMIT_CFG: = DATA_DIR + "tas_fps_limit.cfg"
const GUI_LAYOUT_CFG: = DATA_DIR + "gui_layout.cfg"
const UPDATES_DIR: = DATA_DIR + "updates"
const PROFILE_HISTORY_DIR: = DATA_DIR + "profile_history"
const WINS_SNAPSHOTS: = DATA_DIR + "wins_leaderboard_snapshots.json"
const SEASON_DEALS_CACHE: = DATA_DIR + "season_deals_archive.json"
const COSMETIC_SANDBOX_CFG: = DATA_DIR + "cosmetic_sandbox.cfg"
const COSMETIC_LOADOUTS_CFG: = DATA_DIR + "cosmetic_loadouts.cfg"
const AVATAR_STUDIO_DATA: = DATA_DIR + "avatar_studio.json"
const AVATAR_STUDIO_TEXTURES: = DATA_DIR + "avatar_studio_textures"
const EDITOR_PLUS_GROUPS: = DATA_DIR + "editor_plus_groups"
const EDITOR_PLUS_LIBRARY: = DATA_DIR + "editor_plus_library"
const EDITOR_PLUS_RECOVERY: = DATA_DIR + "editor_plus_recovery"

# Old locations (before 2026-09-29) -> new, moved once by core/DataMigration.gd
const MOVED_DATA = [
	["user://tas_practice_macros", PRACTICE_MACRO_DIR],
	["user://tas_macro_slots.cfg", MACRO_SLOTS_CFG],
	["user://tas_diagnostics", DIAGNOSTICS_DIR],
	["user://tas_debug_mode.cfg", DEBUG_MODE_CFG],
	["user://tas_fps_limit.cfg", FPS_LIMIT_CFG],
	["user://goobplayability_gui_layout.cfg", GUI_LAYOUT_CFG],
	["user://goobplayability_updates", UPDATES_DIR],
	["user://profile_history", PROFILE_HISTORY_DIR],
	["user://wins_leaderboard_snapshots.json", WINS_SNAPSHOTS],
	["user://season_deals_archive.json", SEASON_DEALS_CACHE],
	["user://cosmetic_sandbox.cfg", COSMETIC_SANDBOX_CFG],
	["user://cosmetic_loadouts.cfg", COSMETIC_LOADOUTS_CFG],
	["user://avatar_studio.json", AVATAR_STUDIO_DATA],
	["user://avatar_studio_textures", AVATAR_STUDIO_TEXTURES],
	["user://editor_plus_groups", EDITOR_PLUS_GROUPS],
	["user://editor_plus_library", EDITOR_PLUS_LIBRARY],
	["user://editor_plus_recovery", EDITOR_PLUS_RECOVERY],
	["user://avatar_studio.json.bak", DATA_DIR + "avatar_studio.json.bak"],
	["user://tas_replays", DATA_DIR + "tas_replays"],
]

# Every mod file by name -> folder (relative to ROOT)
const FILES = {
	"AccountAccess.gd": "tools/accounts/",
	"AccountAuthProxy.gd": "tools/accounts/",
	"AccountBackend.gd": "tools/accounts/",
	"AccountManager.gd": "tools/accounts/",
	"AccountManagerView.gd": "tools/accounts/",
	"AccountSigninForm.gd": "tools/accounts/",
	"AccountStore.gd": "tools/accounts/",
	"AccountVault.ps1": "tools/accounts/",
	"AccountsHandler.gd": "tools/accounts/",
	"AutoplayBot.gd": "tools/autoplay/",
	"AvatarStudio.gd": "tools/avatar-studio/",
	"AvatarStudioHandler.gd": "tools/avatar-studio/",
	"ClientEffectFixes.gd": "tools/game-tools/",
	"ClientEmote.gd": "tools/game-tools/",
	"CoreHandler.gd": "core/",
	"CosmeticLoadouts.gd": "tools/avatar-studio/",
	"CosmeticSandbox.gd": "tools/avatar-studio/",
	"CosmeticTransforms.gd": "shared/scripts/",
	"CouncilDiagnostics.ps1": "tools/level-council/",
	"CouncilGuestAuth.gd": "tools/level-council/worker-src/",
	"CouncilIcon.gd": "tools/level-council/",
	"CouncilLauncher.ps1": "tools/level-council/",
	"CouncilMaps.gd": "tools/level-council/",
	"CouncilPool.gd": "tools/level-council/worker-src/",
	"CouncilPoolClient.gd": "tools/level-council/worker-src/",
	"CouncilPublicCapture.gd": "tools/level-council/worker-src/",
	"CouncilRecorderClient.gd": "tools/level-council/",
	"CouncilSession.gd": "tools/level-council/worker-src/",
	"CouncilSummary.gd": "tools/level-council/",
	"CouncilWebhook.ps1": "tools/level-council/",
	"CouncilWorker.gd": "tools/level-council/worker-src/",
	"DataMigration.gd": "core/",
	"DiagnosticsHandler.gd": "tools/tas-diagnostics/",
	"EditorAnimation.gd": "tools/editor-plus/",
	"EditorAppearance.gd": "tools/editor-plus/",
	"EditorGeometry.gd": "tools/editor-plus/",
	"EditorGroups.gd": "tools/editor-plus/",
	"EditorGuide.gd": "tools/editor-plus/",
	"EditorGuideDiagram.gd": "tools/editor-plus/",
	"EditorGuidePages.gd": "tools/editor-plus/",
	"EditorLaserTiming.gd": "tools/editor-plus/",
	"EditorLibrary.gd": "tools/editor-plus/",
	"EditorNativeSelection.gd": "tools/editor-plus/",
	"EditorOrder.gd": "tools/editor-plus/",
	"EditorPlus.gd": "tools/editor-plus/",
	"EditorPlusHandler.gd": "tools/editor-plus/",
	"EditorProperties.gd": "tools/editor-plus/",
	"EditorRecovery.gd": "tools/editor-plus/",
	"EditorSelection.gd": "tools/editor-plus/",
	"EditorThemePack.gd": "tools/editor-themes/",
	"EditorThemesHandler.gd": "tools/editor-themes/",
	"EditorTweenPanel.gd": "tools/editor-plus/",
	"EditorTweenSequence.gd": "tools/editor-plus/",
	"EmoteWheel.gd": "tools/game-tools/",
	"FinishCapture.gd": "tools/journey/finish/",
	"GameToolCard.gd": "core/",
	"GameTools.gd": "tools/game-tools/",
	"GameToolsHandler.gd": "tools/game-tools/",
	"GoobUpdater.gd": "core/",
	"GoobWindowGeometry.gd": "core/",
	"InfiniteDash.gd": "tools/infinite-dash/",
	"JourneyAchievements.gd": "tools/journey/data/",
	"JourneyActivity.gd": "tools/journey/data/",
	"JourneyActivityEvidence.gd": "tools/journey/data/",
	"JourneyArt.gd": "tools/journey/ui/",
	"JourneyBadgeAdmin.gd": "tools/journey/ui/",
	"JourneyBuilder.gd": "tools/journey/data/",
	"JourneyCareer.gd": "tools/journey/data/",
	"JourneyCertified.gd": "tools/journey/data/",
	"JourneyCustomBadges.gd": "tools/journey/data/",
	"JourneyDefinitions.gd": "tools/journey/data/",
	"JourneyFinishDance.gd": "tools/journey/finish/",
	"JourneyFinishPlayer.gd": "tools/journey/finish/",
	"JourneyFinishProps.gd": "tools/journey/finish/",
	"JourneyFinishPuppet.gd": "tools/journey/finish/",
	"JourneyFinishRocketRide.gd": "tools/journey/finish/",
	"JourneyFinishShow.gd": "tools/journey/finish/",
	"JourneyFinishStarRide.gd": "tools/journey/finish/",
	"JourneyFinishTinyGoobers.gd": "tools/journey/finish/",
	"JourneyHandler.gd": "tools/journey/",
	"JourneyHud.gd": "tools/journey/",
	"JourneyLeaderboard.gd": "tools/journey/data/",
	"JourneyLedger.gd": "tools/journey/data/",
	"JourneyLooks.gd": "tools/journey/data/",
	"JourneyMapCatalog.gd": "tools/journey/data/",
	"JourneyMatchCard.gd": "tools/journey/ui/",
	"JourneyMatchRewards.gd": "tools/journey/data/",
	"JourneyMatchXP.gd": "tools/journey/data/",
	"JourneyMilestones.gd": "tools/journey/data/",
	"JourneyModel.gd": "tools/journey/data/",
	"JourneyNavigation.gd": "tools/journey/ui/",
	"JourneyPages.gd": "tools/journey/ui/",
	"JourneyPreview.gd": "tools/journey/ui/",
	"JourneyProfileBadges.gd": "tools/journey/ui/",
	"JourneyQuests.gd": "tools/journey/data/",
	"JourneyScreen.gd": "tools/journey/ui/",
	"JourneySessions.gd": "tools/journey/data/",
	"JourneySound.gd": "tools/journey/ui/",
	"JourneyStore.gd": "tools/journey/data/",
	"JourneyThemes.gd": "tools/journey/ui/",
	"JourneyUI.gd": "tools/journey/ui/",
	"JourneyXPBackfill.gd": "tools/journey/data/",
	"LevelCouncil.gd": "tools/level-council/",
	"LevelCouncilHandler.gd": "tools/level-council/",
	"LevelThemeSync.gd": "tools/editor-themes/",
	"LocalClient.gd": "tools/local-play/",
	"LocalLevelInfo.gd": "tools/local-play/",
	"LocalSession.gd": "tools/local-play/",
	"MainHandler.gd": "core/",
	"MatchInfoHandler.gd": "tools/match-info/",
	"MatchMapPreview.gd": "tools/match-info/",
	"MatchObserver.gd": "tools/replay-hub/",
	"ModPaths.gd": "core/",
	"ModuleGuidePages.gd": "core/",
	"ModulePages.gd": "core/",
	"MovementEffects.gd": "shared/scripts/",
	"ObservedCaptureStore.gd": "tools/replay-hub/",
	"ObservedLibrary.gd": "tools/replay-hub/",
	"ObservedOverview.gd": "tools/replay-hub/",
	"ObservedPlayback.gd": "tools/replay-hub/",
	"ObserverCamera.gd": "tools/replay-hub/",
	"Onboarding.gd": "core/",
	"OnlineConfig.gd": "shared/scripts/",
	"PingOptimizer.gd": "tools/game-tools/",
	"PlayerDataOutline.gd": "tools/tas-diagnostics/",
	"ProfileDialog.gd": "tools/profile-plus/",
	"ProfileHistoryStore.gd": "tools/profile-plus/",
	"ProfileObserver.gd": "tools/profile-plus/",
	"ProfilePanel.gd": "tools/profile-plus/",
	"ReplayHub.gd": "tools/replay-hub/",
	"ReplayHubHandler.gd": "tools/replay-hub/",
	"RunFinishCapture.bat": "tools/journey/finish/",
	"SeasonDeals.gd": "tools/game-tools/",
	"SocialHandler.gd": "tools/social/",
	"SocialHub.gd": "tools/social/",
	"SoloMatchmaker.js": "tools/local-play/",
	"SoloQueue.gd": "tools/local-play/",
	"Spotlight.gd": "core/",
	"TASInputDisplay.gd": "tools/overlays/",
	"TASMacroEditor.gd": "tools/tas/",
	"TASPostPhysicsGuard.gd": "tools/tas/",
	"TASWorldOverlay.gd": "tools/overlays/",
	"TasHandler.gd": "tools/tas/",
	"WinsBoardView.gd": "tools/match-info/",
	"WinsLeaderboard.gd": "tools/match-info/",
	"WorkspaceMenu.gd": "core/",
	"council-worker.pck": "tools/level-council/",
	"journey-map-catalog.json": "tools/journey/data/",
}

static func path(file_name: String) -> String:
	return ROOT + str(FILES.get(file_name, "")) + file_name

# True when that file is installed (the installer can leave tools out).
static func has(file_name: String) -> bool:
	return File.new().file_exists(path(file_name))

# load() for a tool that may not be installed: null instead of an error.
static func try_load(full_path: String):
	if not File.new().file_exists(full_path):
		return null
	return load(full_path)
