extends MarginContainer

# JourneyScreen: shared state (variables, constants, signals, inner classes), in the original order.
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Journey page in HomeScene's native paginator (JourneyHandler and
# JourneyNavigation own registration). Renders JourneyModel; systems with no
# connected source show an explicit "not connected" state, never invented data.
const SECTIONS = ["Overview", "Quests", "Maps", "Achievements", "Rewards", "Career"]
const SECTION_ICONS = {"Overview": "overview", "Quests": "quests", "Maps": "maps", "Achievements": "achievements", "Rewards": "rewards", "Career": "activity"}
const MAX_WIDTH = 2640
const WIDE_AT = 1700
const PREFS = {"sounds": true, "volume": 0.8, "celebrations": "all", "reduced_motion": false, "notify": "after_match", "auto_claim": false, "session_summary": true, "finish": ""}

var ledger
var definitions
var art
var ui
var pages
var models
var preview_data = null
var journey_store = null
var activity = null
var session_rules = null
var achievement_rules = null
var quest_rules = null
var career_rules = null
var theme_rules = null
var leaderboard = null
var builder = null
# Set before build() when Journey is shown over a match (JourneyHud.gd): adds a
# close button and lets Esc close it.
var closable = false
signal close_requested
signal claims_changed(total)

var profile_service = null
var model = {}
var prefs = {}
var section = "Overview"
var view = ""
var view_arg = null
var layout = ""
var design_preview = false
var root
var nav_row
var sound
var results = {}
var header_col
var header_row
var intro_spot = null
var intro_step = 0
var header_gap
var scroll
var content
var overlay = null

var _quiet_render = false

# ------------------------------------------------------------------ claims
# How many things can be claimed in each section (for the red "!" badges on
# the section tabs and on the Journey tab in the home screen).
var claim_counts = {}

# Round red badge with a white "!" and a soft pulse.
class ClaimBadge extends Control:
	var t = 0.0
	func _process(delta):
		if is_visible_in_tree():
			t += delta
			update()
	func _draw():
		var r = min(rect_size.x, rect_size.y) * 0.5
		var c = rect_size * 0.5
		var pulse = 0.5 + 0.5 * sin(t * 4.0)
		draw_circle(c, r + 3.0 + 3.0 * pulse, Color(1.0, 0.25, 0.4, 0.25 * (1.0 - pulse)))
		draw_circle(c + Vector2(0, 2), r, Color(0.35, 0.02, 0.12, 0.6))
		draw_circle(c, r, Color("0b1c3d"))
		draw_arc(c, r - 0.5, 0, TAU, 48, Color("0b1c3d"), 1.5, true)
		draw_circle(c, r - 2.5, Color("ff3d63"))
		draw_arc(c, r - 2.5, 0, TAU, 48, Color("ff3d63"), 1.2, true)
		draw_circle(c + Vector2(-r * 0.28, -r * 0.32), r * 0.26, Color(1, 1, 1, 0.2))
		# The "!" as shapes, so it stays bold at any size.
		var w = max(2.0, r * 0.26)
		var top = c.y - r * 0.52
		var bottom = c.y + r * 0.14
		draw_line(Vector2(c.x, top + w * 0.5), Vector2(c.x, bottom), Color.white, w, true)
		draw_circle(Vector2(c.x, top + w * 0.5), w * 0.5, Color.white)
		draw_circle(Vector2(c.x, bottom), w * 0.5, Color.white)
		draw_circle(Vector2(c.x, c.y + r * 0.46), w * 0.62, Color.white)

# Every Journey action button routes here. Codex's systems can connect to
# journey_action(kind) to handle claim / reroll / choose_quest / pin / feature /
# equip / mark_read; until something is connected we only acknowledge the tap.
signal journey_action(kind, data)

const ACTION_TEXT = {
	"claim": "Claiming", "reroll": "Rerolling quests", "choose_quest": "Choosing quests",
	"pin": "Pinning goals", "feature": "Featuring badges", "equip": "Equipping cosmetics",
	"mark_read": "Inbox read state",
}

# Map objective rewards. Each is awarded once (ledger id map:<account>:<map>:<objective>).
const MAP_CATEGORY = {"discover": "exploration", "finish": "placement", "survive": "placement", "first": "win", "win": "win", "pb": "record"}

# Day-streak rewards, claimable once per streak (ledger category "activity",
# id streak:<first day of the streak>:<days>:<account>).
const STREAK_REWARDS = [[3, 500], [7, 1500], [14, 3000], [30, 6000]]

# One-time bonus for each of your levels in CERTIFIED (Goob Builder page).
const CERTIFIED_XP = 5000

# Finish effects (JourneyHud plays the equipped one on your own finish).
const FINISHES = [
	{"key": "dance", "name": "Dance", "rank_id": 18, "script": "JourneyFinishDance.gd", "text": "Dances on the spot with a mix of moves until the next round."},
	{"key": "star_ride", "name": "Star Ride", "rank_id": 19, "script": "JourneyFinishStarRide.gd", "text": "Rides a star around the finish, then flies through a star portal."},
	{"key": "tiny_goobers", "name": "Tiny Goobers", "rank_id": 20, "script": "JourneyFinishTinyGoobers.gd", "text": "A crew of tiny Goobers keeps throwing you into the air."},
	{"key": "rocket_ride", "name": "Rocket Ride", "rank_id": 21, "script": "JourneyFinishRocketRide.gd", "text": "Rides a rocket through loops and dives, then blasts off."},
]

# XP before the claim: the rank bars animate up from it on the next render.
var xp_anim_from = -1

# Countdown text that ticks while Journey is on screen (one timer, cheap text
# updates only; nothing is re-rendered and nothing runs while Journey is hidden).
var _live = []
var _live_timer = 0.0

# Pop-up notification (quest done, achievement tier, rank-up, unlock...).
# Codex should only call this at safe moments (never mid-race); the
# "Inbox only" pref suppresses it. Clicking opens target (a view or section).
const NOTIFY_STYLE = {
	"quest": ["quests", Color("ff7ed3")], "achievement": ["achievements", Color("ffc40f")],
	"rank": ["overview", Color("b1deff")], "map": ["maps", Color("5ee0c8")],
	"reward": ["rewards", Color("ff9231")], "session": ["session", Color("8af0b4")],
}

# Ctrl+M opens the test tools while Journey is on screen.
# Test tools (Ctrl+M) only for this account id (Emilia). Checked against the
# signed-in account's id from the game session, not the display name.
const ADMIN_ID = "96c5a97d-63c9-4dd7-bf47-d5ad48bb6cf2"

var harness_admin = false

# ------------------------------------------------------------------ match results
# Post-match XP screen. awards: ledger-style entries {id, category, reason,
# amount} for this match. xp_before: lifetime XP before them (defaults to the
# ledger total minus the awards). Promotions are worked out from the
# definitions, and Continue hands over to celebrate() per the Celebrations pref.
const RESULT_ORDER = ["win", "placement", "exploration", "challenge", "activity", "record"]

var last_results = null
var _history_from_results = false
