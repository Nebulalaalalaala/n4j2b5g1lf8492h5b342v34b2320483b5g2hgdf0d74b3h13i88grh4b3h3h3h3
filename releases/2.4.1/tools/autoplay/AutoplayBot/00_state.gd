extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# AutoplayBot: shared state (variables, constants, signals, inner classes), in the original order.

# Local state-space level runner for Goobplayability's Macro Bot. It expands
# only positions and movement states reached through the game's real physics.

const ACTION_JUMP := "player_up"
const ACTION_DASH := "player_dash"
const ACTION_LEFT := "player_left"
const ACTION_RIGHT := "player_right"
const FRAME_STATE_KEY := "__tas_recorded_state"
const DASH_DIRECTION_KEY := "__tas_dash_direction"
const MIN_ATTEMPT_SECONDS := 4
const MAX_ATTEMPT_SECONDS := 180
const ATTEMPT_SECONDS_STEP := 2
const AUTO_HORIZON_EXTENSION_SECONDS := 15
const READY_TICKS_REQUIRED := 3
const RESTORE_SETTLE_TICKS := 3

# The mapper works from the editor's real 50 px level geometry. It samples
# the safe faces of solid nodes, connects only jumps/dashes that fit the
# player's practical reach, and runs A* before any learning attempt begins.
const NAV_SAMPLE_STEP := 90.0
const NAV_PLAYER_CLEARANCE := 34.0
const NAV_POINT_MERGE_DISTANCE := 24.0
const NAV_WAYPOINT_REACHED := 72.0
const NAV_MAX_POINTS := 10000
const NAV_MAX_WALK_X := 190.0
const NAV_MAX_JUMP_X := 410.0
const NAV_MAX_JUMP_UP := 285.0
const NAV_MAX_DROP := 520.0
const NAV_MAX_DASH_X := 560.0
const NAV_MAX_WALL_STEP := 145.0
const NAV_HAZARD_MARGIN := 28.0
const NAV_SOLID_MARGIN := 14.0
const NAV_ARC_SAMPLES := 8
const NAV_POINT_BUCKET_SIZE := 700.0
const NAV_GEOMETRY_BUCKET_SIZE := 300.0

# Real-physics frontier search. Each expansion starts from a state the bot
# actually reached, tries a deliberately varied set of short movement
# sequences, and keeps novel surviving endpoints. This is the authoritative
# planner; geometry is only a heuristic for ordering the search.
const SEARCH_DEFAULT_SEGMENT_TICKS := 24
const SEARCH_FRONTIER_LIMIT := 240
const SEARCH_VISITED_LIMIT := 6000
const SEARCH_POSITION_CELL := 40.0
const SEARCH_VELOCITY_CELL := 100.0
const SEARCH_DECISION_INTERVAL_TICKS := 8
const SEARCH_DECISION_MIN_DISTANCE := 28.0

const SOLID_NODE_TYPES := [
	"block", "floor", "ramp", "bouncy_block", "ice_block",
	"disappearing_block", "music_block", "physics_block",
]
const HAZARD_NODE_TYPES := ["pit", "sawblade", "laser", "cannon"]

# Exact values from TASTool's palette. Matching by value matters because its
# optional modern theme remaps these known accents into the flat slate/teal/
# red/green/violet palette.
const COLOR_BLUE := Color(0.211765, 0.541176, 0.854902)
const COLOR_PINK := Color(1.0, 0.219608, 0.588235)
const COLOR_RED := Color(0.8, 0.117647, 0.439216)
const COLOR_GREEN := Color(0.117647, 0.690196, 0.423529)
const COLOR_PURPLE := Color(0.55, 0.31, 0.88)
const COLOR_TEXT := Color(1.0, 1.0, 1.0)
const COLOR_DIM := Color(0.72, 0.8, 0.95)

var tas_tool: Node = null
var rng := RandomNumberGenerator.new()

var _learning := false
var _replaying := false
var _waiting_for_ready := false
var _ready_ticks := 0
var _settle_ticks := 0
var _attempt_seconds := 30
var _training_speed := 2.0
var _saved_time_scale := 1.0
var _saved_time_scale_valid := false
var _resume_existing := false

var _game: Node = null
var _game_id := 0
var _start_snapshot := {}
var _finish_rects := []
var _initial_finish_distance := 1.0
var _preferred_direction := 1
var _start_checkpoint := 0
var _solid_rects := []
var _hazard_rects := []
var _checkpoint_rects := []
var _checkpoint_nav_points := []
var _checkpoint_node_ids := []
var _completed_checkpoint_node_ids := {}
var _finish_nav_points := []
var _solid_spatial := {}
var _hazard_spatial := {}
var _nav_point_merge_buckets := {}
var _nav_sampled_point_count := 0
var _navigation_route := []
var _route_lengths := []
var _route_total_length := 0.0
var _route_index := 0
var _route_is_relaxed := false
var _route_is_partial := false
var _route_goal_kind := "finish"
var _route_stall_ticks := 0
var _route_last_position := Vector2.ZERO
var _search_frontier := []
var _search_visited := {}
var _search_visited_order := []
var _search_source := {}
var _search_pending_actions := []
var _search_action := {}
var _search_expansions := 0
var _search_accepted := 0
var _search_best_route_progress := 0.0
var _search_best_finish_distance := INF

var _attempt := 0
var _trial_tick := 0
var _trial_genome := []
var _trial_frames := []
var _trial_min_finish_distance := INF
var _trial_max_projection := 0.0
var _trial_max_checkpoint := 0
var _trial_max_route_index := 0
var _trial_progress_tick := 0
var _trial_last_snapshot := {}
var _trial_last_alive_position := Vector2.ZERO
var _trial_source_position := Vector2.ZERO
var _trial_last_saved_position := Vector2.ZERO
var _trial_prev_grounded := false
var _trial_prev_wall := false
var _trial_prev_velocity_y := 0.0
var _trial_prev_checkpoint := 0
var _finish_hit := false

var _elites := []
var _novelty_archive := {}
var _novelty_order := []
var _locked_frames := []
var _locked_finish_distance := INF
var _locked_projection := 0.0
var _locked_checkpoint := 0
var _best_score := -INF
var _best_genome := []
var _best_frames := []
var _best_end_snapshot := {}
var _best_progress_tick := 0
var _best_finish_distance := INF
var _best_checkpoint := 0
var _solved := false
var _solved_ticks := 0

var _status_text := "Open a Time Trial or editor test level to begin."
var _status_label: Label = null
var _result_label: Label = null
var _start_button: Button = null
var _stop_button: Button = null
var _play_button: Button = null
var _install_button: Button = null
var _reset_button: Button = null
var _duration_label: Label = null
var _speed_button: Button = null
var _ui_last_status := ""
var _ui_last_result := ""
