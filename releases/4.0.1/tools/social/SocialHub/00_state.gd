extends CanvasLayer

# SocialHub: shared state (variables, constants, signals, inner classes), in the original order.

# Goobplayability -- Friends & Party
#
# Goober Dash already constructs Moonlight.friends and Moonlight.party and its
# matchmaker already consumes squad state. The released client simply ships no
# usable front end for those objects. This window exposes only the APIs already
# present in the game: friend-code requests, friend-list management, presence,
# party creation/invites, party membership and leaving/kicking.

const COLOR_PANEL_BG: = Color(0, 0.129412, 0.262745, 0.97)
const COLOR_CARD_BG: = Color(0.0, 0.18, 0.34, 0.78)
const COLOR_PANEL_BORDER: = Color(0, 0, 0, 0.62)
const COLOR_BLUE: = Color(0.211765, 0.541176, 0.854902)
const COLOR_GREEN: = Color(0.117647, 0.690196, 0.423529)
const COLOR_PINK: = Color(0.8, 0.117647, 0.439216)
const COLOR_ORANGE: = Color(0.95, 0.48, 0.12)
const COLOR_WHITE: = Color(1, 1, 1)
const COLOR_TEXT_DIM: = Color(0.72, 0.8, 0.95)

const FRIENDS: = 0
const REQUEST_SENT: = 1
const REQUEST_RECEIVED: = 2
const BLOCKED: = 3
const DEFAULT_PARTY_SIZE: = 4

var tas_tool = null
var gui_enabled: = true
var _modules_connected: = false
var _retry_timer: = 0.0
var _busy: = false
var _friend_query_failed: = false

var _access_button: Button = null
var _modal_root: Control = null
var _status_label: Label = null
var _friend_code_label: Label = null
var _friend_code_input: LineEdit = null
var _friends_list: VBoxContainer = null
var _party_list: VBoxContainer = null
var _refresh_button: Button = null
