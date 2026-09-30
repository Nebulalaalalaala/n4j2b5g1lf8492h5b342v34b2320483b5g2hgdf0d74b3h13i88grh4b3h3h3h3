extends CanvasLayer

# ReplayHub: shared state (variables, constants, signals, inner classes), in the original order.

const ModPaths = preload("user://mod/core/ModPaths.gd")
const OnlineConfig = preload("user://mod/shared/scripts/OnlineConfig.gd")

# Goobplayability -- Community Replay Hub.
#
# A fully independent client tool window, on the same footing as the Avatar
# Sandbox: it has no button anywhere inside TASTool.gd's own menu. It is
# opened only through its own floating access button, shown or hidden by
# the "COMMUNITY REPLAY HUB" toggle TASTool.gd injects into Settings ->
# Client Tools (see TASTool.gd's set_gui_enabled() call and
# _on_settings_replay_hub_gui_toggled()).
#
# Browses shared replays from a Supabase table over HTTPS and imports the
# chosen one into a normal local Macro Slot -- playback then goes through
# the exact same code TASTool.gd already uses for any saved Macro Slot
# (_on_play_saved_practice_macro_slot_pressed). This file never implements
# its own playback path.
#
# The key embedded below is Supabase's "anon/public" key. Its Row Level
# Security policy (see replay_hub_schema.sql) allows SELECT (browsing) and
# a bounded, anonymous INSERT (uploading) -- never UPDATE/DELETE, so
# nothing already uploaded can be changed or removed from the client, only
# by the project owner directly in Supabase. There is still no account
# system, so every upload is anonymous and forced to featured=false
# server-side; SHARE A MACRO SLOT's COPY SQL option is the manual fallback
# for anything that needs hand-editing (e.g. marking something Featured).
#
# Replay payloads are expected to be DATA ONLY (a Dictionary of
# checkpoints/segments/level_context, the same shape already used by local
# .tasmacro slot files, encoded with Godot's var2str()). Decoding is
# defensive: the encoded string is rejected outright if it contains an
# "Object(" literal (var2str() with the default full_objects=false, which
# is all this file's own export/upload path ever uses, never emits one),
# and the decoded value must still be a Dictionary with
# "checkpoints"/"segments" before anything is imported.

const SUPABASE_URL := OnlineConfig.SUPABASE_URL
const REPLAYS_TABLE := "replays"
const FONT_PATH := "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"
const LIST_LIMIT := 60
const SETTING_AUTHOR_NAME := "client_tools_replay_hub_author"
# Same key TASTool.gd stores its Claude Experimental Mode toggle under
# (SETTING_CLAUDE_EXPERIMENTAL_ICONS). Read directly here at _ready() --
# see the comment on that read below for why.
const SETTING_CLAUDE_EXPERIMENTAL_ICONS := "client_tools_claude_experimental_icons"

# Metadata-only responses (the browse list) are always small -- this stays
# tight regardless of how big individual replays get.
const MAX_LIST_RESPONSE_BYTES := 2097152
# One replay's encoded data, in either direction (download or upload) --
# real Macro Slots have come in around 8 MB uncompressed, so this needs
# real headroom above that. _encode_replay_data() gzips before this limit
# is ever checked, so most uploads land well under it in practice.
const MAX_REPLAY_PAYLOAD_BYTES := 16777216
# Sanity cap on a *claimed* decompressed size read from a downloaded row,
# checked before decompress() ever allocates that much memory -- stops a
# tiny malicious/corrupt row from claiming a huge decompressed size.
const MAX_DECOMPRESSED_BYTES := 67108864
const COMPRESSED_DATA_PREFIX := "GZDATA1:"

const NAVY := Color(0.0, 0.129412, 0.262745, 0.72)
const NAVY_2 := Color(0.0, 0.19, 0.36, 0.70)
const BLUE := Color(0.211765, 0.541176, 0.854902)
const PINK := Color(1.0, 0.219608, 0.588235)
const PINK_DARK := Color(0.80, 0.117647, 0.439216)
const GREEN := Color(0.117647, 0.690196, 0.423529)
const WHITE := Color.white
const DIM := Color(0.72, 0.82, 0.95)

# ---- Claude Experimental Mode "modern black" theme palette -- same
# restrained palette as TASTool.gd/CosmeticSandbox.gd/TASMacroEditor.gd.
# Only ever read through _theme_fill()/_theme_border()/_theme_text()/
# _theme_accent() below, and only when _modern_theme_active() is true, so
# the classic look above is completely unchanged for anyone with the
# toggle off.
const MODERN_BG := Color(0.094, 0.110, 0.125)
const MODERN_BG_2 := Color(0.133, 0.157, 0.173)
const MODERN_BORDER := Color(0.32, 0.34, 0.38)
const MODERN_WHITE := Color(0.93, 0.94, 0.96)
const MODERN_DIM := Color(0.58, 0.6, 0.66)
const CLAUDE_EXPERIMENTAL_FONT_PATH := ModPaths.MAIN_FONT

const TAB_FEATURED := 0
const TAB_NEWEST := 1
const TAB_BY_LEVEL := 2
const TAB_OBSERVED := 3
const TAB_TITLES := ["FEATURED", "NEWEST", "BY LEVEL"]
var _council = null
var _council_recorder = null
var _observed_library = null
var _community_scroll = null
var _community_export = null
var _observed_scroll = null

var tas_tool: Node = null
var gui_enabled := false

# Claude Experimental Mode -- set via set_claude_experimental_icons_enabled()
# (called by TASTool.gd's _apply_claude_experimental_icons(), same as
# CosmeticSandbox.gd/TASMacroEditor.gd). Off by default; only ever read
# through _modern_theme_active() below.
var _claude_experimental_icons_enabled: = false
var _claude_modern_font_data: DynamicFontData = null
var _claude_modern_font_load_attempted: = false

var _title_font: DynamicFont
var _header_font: DynamicFont
var _body_font: DynamicFont
var _small_font: DynamicFont

var _access_button: Button = null

var _modal_root: Control
var _list_box: VBoxContainer
var _status_label: Label
var _tab_buttons := []
var _active_tab := TAB_NEWEST

var _export_root: Control
var _export_list_box: VBoxContainer
var _author_field: LineEdit

var _list_http: HTTPRequest
var _detail_http: HTTPRequest
var _upload_http: HTTPRequest
var _list_busy := false
var _detail_busy := false
var _upload_busy := false
var _pending_detail_context := {}
