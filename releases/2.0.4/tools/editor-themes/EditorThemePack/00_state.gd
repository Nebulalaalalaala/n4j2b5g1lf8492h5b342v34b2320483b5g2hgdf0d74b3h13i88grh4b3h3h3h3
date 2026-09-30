extends Node

# EditorThemePack: shared state (variables, constants, signals, inner classes), in the original order.
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Goobplayability -- Editor Theme Pack
#
# Adds data-only visual themes to the existing editor. All placed objects keep
# their stock node types and physics; the custom "blocks" are themed visual
# variants, so testing remains deterministic and no new network object type is
# invented client-side.

const THEME_DEFINITIONS: = {
	"mushroom_valley": {
		"name": "Mushroom Valley", "top": Color("c0c9b0"), "bottom": Color("7f8868"),
		"accent": Color("df9c83"), "accent_dark": Color("95695f"),
		"terrain": Color("494e3b"), "pattern": Color("92967b"),
		"laser": Color("ffd494"), "pattern_mode": "panels", "scenery": "mushrooms",
	},
	"floating_island": {
		"name": "Floating Island", "top": Color("477f9f"), "bottom": Color("c3ded6"),
		"accent": Color("b1d7b0"), "accent_dark": Color("628b83"),
		"terrain": Color("3b555d"), "pattern": Color("859f9f"),
		"laser": Color("f5d899"), "pattern_mode": "panels", "scenery": "islands",
	},
	"cloud_passage": {
		"name": "Cloud Passage", "top": Color("7fa5bc"), "bottom": Color("e3dcd0"),
		"accent": Color("eaf0eb"), "accent_dark": Color("91afbf"),
		"terrain": Color("526d84"), "pattern": Color("91a5b5"),
		"laser": Color("ffd79c"), "pattern_mode": "panels", "scenery": "clouds",
	},
	"sweet_hazard": {
		"name": "Sweet Hazard", "top": Color("292f3a"), "bottom": Color("827575"),
		"accent": Color("d3a0a0"), "accent_dark": Color("956e79"),
		"terrain": Color("3e3a48"), "pattern": Color("827889"),
		"laser": Color("ffcf8d"), "pattern_mode": "panels", "scenery": "ruins",
	},
	"animal_kingdom": {
		"name": "Animal Kingdom", "top": Color("b4a67e"), "bottom": Color("ead4a1"),
		"accent": Color("d9c482"), "accent_dark": Color("94824f"),
		"terrain": Color("554d38"), "pattern": Color("958667"),
		"laser": Color("ffe5a0"), "pattern_mode": "panels", "scenery": "savanna",
	},
	"holy_night": {
		"name": "Holy Night", "top": Color("111e34"), "bottom": Color("435d70"),
		"accent": Color("c9dee4"), "accent_dark": Color("759da9"),
		"terrain": Color("293e51"), "pattern": Color("78949f"),
		"laser": Color("ffe4a1"), "pattern_mode": "panels", "scenery": "winter",
	},
	"wild_jungle": {
		"name": "Wild Jungle", "top": Color("163c39"), "bottom": Color("719477"),
		"accent": Color("a6c494"), "accent_dark": Color("567e65"),
		"terrain": Color("28463c"), "pattern": Color("74977b"),
		"laser": Color("f3d091"), "pattern_mode": "panels", "scenery": "jungle",
	},
	"night_plain": {
		"name": "Night Plain", "top": Color("142839"), "bottom": Color("4c7779"),
		"accent": Color("a2c9bd"), "accent_dark": Color("568d87"),
		"terrain": Color("283f49"), "pattern": Color("749a9e"),
		"laser": Color("f5dfa2"), "pattern_mode": "panels", "scenery": "hills",
	},
	"black_forest": {
		"name": "Black Forest", "top": Color("151e24"), "bottom": Color("475b5d"),
		"accent": Color("a3b4a6"), "accent_dark": Color("607f77"),
		"terrain": Color("243438"), "pattern": Color("637d79"),
		"laser": Color("e4cc95"), "pattern_mode": "panels", "scenery": "forest",
	},
	"summer_beach": {
		"name": "Summer Beach", "top": Color("67a9bc"), "bottom": Color("f5deab"),
		"accent": Color("f0d49a"), "accent_dark": Color("b3a374"),
		"terrain": Color("586b68"), "pattern": Color("9dab97"),
		"laser": Color("fff0b4"), "pattern_mode": "panels", "scenery": "beach",
	},
	"cosmic_dots": {
		"name": "Space",
		"top": Color(0.035, 0.075, 0.18),
		"bottom": Color(0.09, 0.16, 0.34),
		"accent": Color(0.68, 0.76, 0.98),
		"accent_dark": Color(0.28, 0.34, 0.56),
		"terrain": Color(0.055, 0.075, 0.15),
		"pattern": Color(0.63, 0.70, 0.91),
		"laser": Color(0.66, 0.78, 1.0),
		"pattern_mode": "dots",
	},
	"neon_grid": {
		"name": "Neon",
		"top": Color(0.025, 0.01, 0.09),
		"bottom": Color(0.18, 0.025, 0.28),
		"accent": Color(0.12, 0.95, 1.0),
		"accent_dark": Color(0.55, 0.08, 0.82),
		"terrain": Color(0.025, 0.02, 0.08),
		"pattern": Color(0.2, 0.95, 1.0),
		"laser": Color(1.0, 0.17, 0.72),
		"pattern_mode": "grid",
	},
	"sunset_circuit": {
		"name": "Sunset",
		"top": Color(0.20, 0.035, 0.17),
		"bottom": Color(0.55, 0.16, 0.22),
		"accent": Color(1.0, 0.66, 0.25),
		"accent_dark": Color(0.91, 0.20, 0.36),
		"terrain": Color(0.16, 0.035, 0.11),
		"pattern": Color(1.0, 0.52, 0.36),
		"laser": Color(1.0, 0.86, 0.30),
		"pattern_mode": "circuit",
	},
	"moon": {
		"name": "Moon", "top": Color("151e30"), "bottom": Color("536474"),
		"accent": Color("d4dfed"), "accent_dark": Color("778b9d"),
		"terrain": Color("253343"), "pattern": Color("9cabbc"),
		"laser": Color("f6dfa8"), "pattern_mode": "crescents",
	},
	"lagoon": {
		"name": "Lagoon", "top": Color("073a47"), "bottom": Color("247b82"),
		"accent": Color("7dd8ce"), "accent_dark": Color("318f97"),
		"terrain": Color("103e4a"), "pattern": Color("4e9b9d"),
		"laser": Color("ffdc92"), "pattern_mode": "ripples",
	},
	"ember": {
		"name": "Ember", "top": Color("301f1e"), "bottom": Color("87422d"),
		"accent": Color("f3b074"), "accent_dark": Color("a55b40"),
		"terrain": Color("392623"), "pattern": Color("92543e"),
		"laser": Color("fff0b8"), "pattern_mode": "chevrons",
	},
	"orchard": {
		"name": "Orchard", "top": Color("253c31"), "bottom": Color("6d8554"),
		"accent": Color("c9d78e"), "accent_dark": Color("758b52"),
		"terrain": Color("304134"), "pattern": Color("829360"),
		"laser": Color("ffd09d"), "pattern_mode": "leaves",
	},
	"porcelain": {
		"name": "Porcelain", "top": Color("b4c5cb"), "bottom": Color("e7e1d0"),
		"accent": Color("85a6c7"), "accent_dark": Color("456483"),
		"terrain": Color("243e59"), "pattern": Color("7193ae"),
		"laser": Color("efad65"), "pattern_mode": "diamonds",
	},
}

const THEME_TERRAIN_SOURCE_PATHS: = {
	# Reuse real Goober Dash motifs whose visual language fits each pack.
	"cosmic_dots": "res://project_specific/level_themes/sandy/terrain-pattern.png",
	"neon_grid": "res://project_specific/level_themes/city/terrain-pattern.png",
	"sunset_circuit": "res://project_specific/level_themes/castle/terrain-pattern.png",
	"porcelain": "res://project_specific/level_themes/snow/terrain-pattern.png",
}

var tas_tool = null
var gui_enabled: = true
var _themes: = {}
var _crate_textures: = {}
var _neutral_jump_texture: Texture = null
var _levels: = []
var _theme_dialogs: = []
var _scan_timer: = 0.0
var _was_editor_session: = false
var _local_theme_choices: = {}
var menu_theme: String = "follow"
var _sync = null
var _rows: = []
var _row_mark_texture: Texture = null
