extends CanvasLayer

# CosmeticSandbox: shared state (variables, constants, signals, inner classes), in the original order.

const ModPaths = preload("user://mod/core/ModPaths.gd")

# Local-only cosmetic playground. Nothing in this file writes Moonlight
# storage, player cards, ownership, wallet state, or calls a Nakama RPC.
# The official profile is only read as an optional base layer; sandbox
# cosmetics are composed directly on local Goober renderer instances.

const SETTINGS_PATH := ModPaths.COSMETIC_SANDBOX_CFG
const FONT_PATH := "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"
const CLAUDE_EXPERIMENTAL_FONT_PATH := ModPaths.MAIN_FONT
const GOOBER_SCENE_PATH := "res://project_specific/gfx/spine/upguy/upguy.tscn"
const COSMETIC_CARD_SCENE_PATH := "res://project_specific/ui/customization/CosmeticCard.tscn"
const WINDOW_GEOMETRY_SCRIPT_PATH := ModPaths.WINDOW_GEOMETRY
const CATALOG_RETRY_INTERVAL := 0.5
const CATALOG_RETRY_LIMIT := 20

const NAVY := Color(0.0, 0.129412, 0.262745, 0.72)
const NAVY_2 := Color(0.0, 0.19, 0.36, 0.70)
const BLUE := Color(0.211765, 0.541176, 0.854902)
const PINK := Color(1.0, 0.219608, 0.588235)
const PINK_DARK := Color(0.80, 0.117647, 0.439216)
const GREEN := Color(0.117647, 0.690196, 0.423529)
const PURPLE := Color(0.55, 0.31, 0.88)
const ORANGE := Color(0.96, 0.48, 0.20)
const WHITE := Color.white
const DIM := Color(0.72, 0.82, 0.95)

# ---- Claude Experimental Mode "modern black" theme palette ----
# Only ever read through _theme_fill()/_theme_border()/_theme_text() below,
# and only when _modern_theme_active() is true, so the classic look above
# is completely unchanged for anyone with the toggle off.
const MODERN_BG := Color(0.094, 0.110, 0.125)
const MODERN_BG_2 := Color(0.133, 0.157, 0.173)
const MODERN_BORDER := Color(0.32, 0.34, 0.38)
const MODERN_WHITE := Color(0.93, 0.94, 0.96)
const MODERN_DIM := Color(0.58, 0.6, 0.66)

const TYPE_COLORS := {
	"color": BLUE,
	"suit": PURPLE,
	"hat": PINK,
	"hand": GREEN,
	"emote": ORANGE,
}
const TYPE_ORDER := ["color", "suit", "hat", "hand", "emote"]

var sandbox_enabled := false
var include_profile_base := true
var selected_cosmetics := []
var custom_color_enabled := false
var custom_color := Color(0.25, 0.72, 1.0, 1.0)
var gui_enabled := true

# Phase 0.4 -- Cosmetic Sandbox Content Loading Bug. Optional back-reference
# set by TASTool.gd's configure() call, used only to gate/route Debug Mode
# diagnostics -- see _log_cosmetic_catalog_diagnostics(). Everything else in
# this file works standalone with tas_tool == null, same as before.
var tas_tool: Node = null

# Claude Experimental Mode -- see TASTool.gd's SETTING_CLAUDE_EXPERIMENTAL_ICONS
# comment. Off by default; set via set_claude_experimental_icons_enabled()
# (called by TASTool.gd). Purely cosmetic -- swaps in an icon next to this
# window's title, nothing else changes.
var _claude_experimental_icons_enabled: = false
var _claude_icon_texture_cache: = {}
var _claude_modern_font_data: DynamicFontData = null
var _claude_modern_font_load_attempted: = false
var _claude_title_icon: TextureRect = null

var _title_font: DynamicFont
var _header_font: DynamicFont
var _body_font: DynamicFont
var _small_font: DynamicFont

var _modal_root: Control
var _modal_panel: PanelContainer
var _modal_resize_grip: Button
var _modal_resizing := false
var _modal_moving := false
var _grid: GridContainer
var _status_label: Label
var _active_button: Button
var _profile_base_button: Button
var _custom_color_button: Button
var _color_picker: ColorPickerButton
var _search_box: LineEdit
var _filter_buttons := {}
var _filter := "color"
var _preview_goober = null

var _skin_selector: Node = null
var _avatar_button: Button = null
var _last_scene_id := 0
var _registered_goobers := []
var _original_materials := {}
var _applied_signatures := {}
var _renderer_by_goober_id := {}
var _gameplay_goober = null
var _sorting_cosmetics := {}
var _save_pending := false
var _save_delay := 0.0
var _apply_elapsed := 0.0
var _window_geometry = null
var _catalog_waiting_for_source := false
var _catalog_retry_elapsed := 0.0
var _catalog_retry_attempts := 0
var _last_catalog_diag_signature := ""
var _layout_default := {}


var _studio = null
