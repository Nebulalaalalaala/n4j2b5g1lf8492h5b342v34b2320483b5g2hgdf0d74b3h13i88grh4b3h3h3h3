extends Node

# EditorThemePack: shared state (variables, constants, signals, inner classes), in the original order.
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Goobplayability -- Editor Theme Pack
#
# Adds data-only visual themes to the existing editor. All placed objects keep
# their stock node types and physics; the custom "blocks" are themed visual
# variants, so testing remains deterministic and no new network object type is
# invented client-side.

const THEME_DEFINITIONS = preload("user://mod/tools/editor-themes/ThemeCatalog.gd").DEFINITIONS
const GraphicThemeSurfaces = preload("user://mod/tools/editor-themes/GraphicThemeSurfaces.gd")

const THEME_TERRAIN_SOURCE_PATHS: = {
	# Reuse real Goober Dash motifs whose visual language fits each pack.
	"cosmic_dots": "res://project_specific/level_themes/sandy/terrain-pattern.png",
	"neon_grid": "res://project_specific/level_themes/city/terrain-pattern.png",
	"sunset_circuit": "res://project_specific/level_themes/castle/terrain-pattern.png",
	"porcelain": "res://project_specific/level_themes/snow/terrain-pattern.png",
	"voltage": "res://project_specific/level_themes/city/terrain-pattern.png",
	"prism_break": "res://project_specific/level_themes/snow/terrain-pattern.png",
	"ink_shift": "res://project_specific/level_themes/city/terrain-pattern.png",
}

var tas_tool = null
var gui_enabled: = true
var _themes: = {}
var _crate_textures: = {}
var _graphic_surfaces = null
var _neutral_jump_texture: Texture = null
var _levels: = []
var _theme_dialogs: = []
var _scan_timer: = 0.0
var _was_editor_session: = false
var _scanned_scene: = 0
var _local_theme_choices: = {}
var menu_theme: String = "follow"
var _sync = null
var _rows: = []
var _row_mark_texture: Texture = null
