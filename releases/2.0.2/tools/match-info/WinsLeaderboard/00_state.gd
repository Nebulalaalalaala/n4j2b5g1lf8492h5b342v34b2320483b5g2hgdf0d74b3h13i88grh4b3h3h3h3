extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# WinsLeaderboard: shared state (variables, constants, signals, inner classes), in the original order.

# Goobplayability -- Highest Wins Leaderboard
#
# twhlynch's community stats service publishes a lifetime-wins snapshot once
# per UTC day. It does not publish historical daily/weekly/monthly/yearly boards, so
# this module keeps small, dated local snapshots and calculates honest deltas
# between available observations. Missing period boundaries produce a clearly
# marked partial period, never invented wins or a baseline of zero.

const API_URL: = "https://goober-dash-stats-api.onrender.com/wins_leaderboard.json"
const CACHE_PATH: = ModPaths.WINS_SNAPSHOTS
const MAX_RESPONSE_BYTES: = 8 * 1024 * 1024
const MAX_SOURCE_ROWS: = 10000
const MAX_VISIBLE_ROWS: = 100
const PERIODS: = ["all_time", "daily", "weekly", "monthly", "yearly"]
const PERIOD_TITLES: = {
	"all_time": "ALL TIME",
	"daily": "DAILY",
	"weekly": "WEEKLY",
	"monthly": "MONTHLY",
	"yearly": "YEARLY",
}

const COLOR_PANEL_BG: = Color(0, 0.129412, 0.262745, 1.0)
const COLOR_CARD_BG: = Color(0.019608, 0.219608, 0.423529, 1.0)
const COLOR_PANEL_BORDER: = Color(0, 0, 0, 0.64)
const COLOR_BLUE: = Color(0.211765, 0.541176, 0.854902)
const COLOR_GREEN: = Color(0.117647, 0.690196, 0.423529)
const COLOR_PINK: = Color(0.8, 0.117647, 0.439216)
const COLOR_ORANGE: = Color(1.0, 0.60, 0.10)
const COLOR_WHITE: = Color.white
const COLOR_TEXT_DIM: = Color(0.72, 0.82, 0.95)

var tas_tool = null
var gui_enabled: = true
var _snapshots: = {}
var _request_busy: = false
var _active_period: = "all_time"

var _http: HTTPRequest = null
var _file_dialog: FileDialog = null
var _leaderboard_script: Node = null
var _vbox: VBoxContainer = null
var _selector_row: HBoxContainer = null
var _crowns_button: Button = null
var _wins_button: Button = null
var _wins_panel: PanelContainer = null
var _summary_label: Label = null
var _coverage_label: Label = null
var _rows_parent: VBoxContainer = null
var _refresh_button: Button = null
var _period_buttons: = {}
var _native_visibility_restore: = []
var _wins_mode: = false
var _board_view = null
var _view_elapsed = 0.0
var _view_error = ""
