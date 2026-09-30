extends "user://mod/core/TASTool/00_state_1.gd"



# ---- Claude Experimental Mode "modern black" theme palette ----
# Only ever read through _theme_fill()/_theme_border()/_theme_text() below,
# and only when _modern_theme_active() is true. The classic palette above is
# never modified, so anyone with the experimental toggle off sees the exact
# original look, pixel for pixel.
const COLOR_MODERN_BG: = Color(0.094, 0.110, 0.125) # near-black flat panel background
const COLOR_MODERN_BORDER: = Color(0.204, 0.235, 0.251) # subtle hairline border
const COLOR_MODERN_WHITE: = Color(0.93, 0.94, 0.96) # soft off-white text
const COLOR_MODERN_TEXT_DIM: = Color(0.58, 0.6, 0.66) # neutral gray dim text
const COLOR_MODERN_DISABLED: = Color(0.3, 0.3, 0.34)
const COLOR_MODERN_GRIP: = Color(0.03, 0.03, 0.035)
const COLOR_MODERN_SLOT_EMPTY: = Color(0.133, 0.157, 0.173)
const COLOR_MODERN_SLOT_FILLED: = Color(0.16, 0.22, 0.20) # elevated gray card

# ---- scale ----
const SIZE_TITLE: = 28
const SIZE_HEADER: = 21
const SIZE_BODY: = 18
const SIZE_SMALL: = 15
const BUTTON_H: = 42
const LEADERBOARD_SEARCH_COOLDOWN_SEC: = 2.0
const TAB_SIZE: = Vector2(310, 44)
const GRIP_SIZE: = Vector2(36, 44)
const MENU_PANEL_MIN_W: = 1020
const LOG_PANEL_MIN_W: = 780

# ---- state ----
var _game: WPGame = null # cached, re-resolved whenever it becomes invalid
var _game_discovery_initialized: = false # after one initial scan, SceneTree node signals maintain the cache without menu-wide scans every frame
var _prev_key_state: = {}

var _is_paused: = false
var _saved_time_scale: = 1.0
var _pending_frame_step: = false
var _step_start_physics_frame: = 0

# Buffered Inputs: which BUFFERABLE_ACTIONS entries are armed (action name ->
# bool). While armed, the next Step press holds that action down for the
# whole step (see _request_frame_step()/_process_frame_step_watch()), so you
# can queue up e.g. a jump before advancing frames instead of needing to
# physically hold the real key at the exact right moment while also clicking
# Step.
var _buffered_actions: = {}
var _injected_actions_held: = [] # action names TASTool currently holds synthetically pressed

# Macro Bot movement/jump playback uses the SAME synthetic Input events as
# Buffered Inputs/Perfect Jumpzone. Dash is intentionally different: it is
# edge-triggered through WPGame.local_input_dash() with the exact direction
# captured in the macro frame, removing event-order ambiguity when direction
# and dash change together. Synthetic holds are tracked separately from
# _injected_actions_held above
# (which is Buffered Inputs/Perfect Jumpzone's own bookkeeping) so releasing
# one system's held keys can never step on the other's.
var _practice_playback_injected_held: = {} # action name -> bool, only true entries meaningful -- what Macro Bot Mode playback currently holds pressed via _inject_action()
var _practice_playback_dash_held: = false # edge tracker for the direct, explicitly-directed native dash command
var _practice_playback_dash_direction: = true
var _practice_playback_dash_direction_valid: = false

# THE SIXTEENTH-PASS FIX (2026-08-31) -- running total for
# _apply_practice_playback_computed_horizontal_velocity()'s own self-computed
# grounded horizontal speed, kept separate from player.linear_velocity.x
# itself so this file always knows what IT last set that field to on
# purpose, as opposed to whatever the native tick driver may have done to
# it independently. See that function's big comment for the full
# reasoning (item 8/9 in OPEN INVESTIGATION NOTES).
var _practice_playback_computed_vx: = 0.0

# Native WPPlayer uses continuous time airborne to ramp horizontal air
# acceleration from player_air_accel_max toward player_air_accel_min.  This
# counter is deliberately maintained during LIVE play as well as playback:
# checkpoints must save the native ramp's current phase, not a playback-only
# variable that is still zero when the checkpoint is recorded.
var _practice_playback_air_hold_ticks: = 0
var _practice_playback_air_hold_dir: = 0.0 # retained in saved macro format for compatibility; native air timing is direction-independent
var _practice_live_airborne_player_id: = 0 # resets the observed clock when the local WPPlayer instance changes

# Perfect Jumpzone: presses ACTION_JUMP on a fixed rhythm (jumpzone_interval_ms),
# holding each press for jumpzone_hold_ms, for as long as it's armed. See
# _watch_jumpzone().
var _jumpzone_armed: = false
var _jumpzone_cycle_timer: = 0.0
var _jumpzone_key_held: = false

# ----------------------------------------------------------------------
#  Macro Bot Mode (GD-style segment practice / macro splicing)
# ----------------------------------------------------------------------
var _practice_active: = false # currently watching for deaths / recording a segment
var _practice_auto_respawn: = true # snap back to the last checkpoint on death, once the native respawn hold finishes (see THE NINTH-PASS FIX on PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS -- no longer instant)
var _practice_auto_activate: = false # armed via the Macro Bot tab -- see _watch_practice_auto_activate()
var _practice_auto_activate_was_pre: = false # previous tick's LEVEL_PRE reading, for edge-triggering on every NEW attempt (not just once per game instance) -- see _watch_practice_auto_activate()
var _practice_auto_activate_checked_state_for_game: = false # true once gameplay_state has actually been read at least once for the current game instance
var _practice_auto_activate_waiting_for_alive: = false # a new-attempt edge fired, but the player isn't ready yet -- see _watch_practice_auto_activate() (edge-detect, idle-frame) and _watch_practice_start_request() (the actual wait-and-fire, physics-tick)
var _practice_start_waiting: = false # armed by the manual Start button (_on_toggle_practice_pressed()) OR by Auto-Activate's edge-detect above -- consumed on the first PHYSICS tick (not idle frame) the player reads as ready, by _watch_practice_start_request() below. See the big comment on _on_toggle_practice_pressed() for why checkpoint 0's readiness check/snapshot needed to move off the idle frame entirely, same as Play Macro's restore did.
var _practice_start_reason: = "" # reason_suffix forwarded to _start_practice_mode() once _practice_start_waiting above actually fires
var _practice_ready_stable_ticks: = 0 # THE SEVENTH-PASS FIX -- consecutive physics ticks _player_ready_for_checkpoint() has read true in a row while _practice_start_waiting is armed; reset to 0 the instant it reads false, or while not waiting at all. Only once this reaches PRACTICE_READY_STABLE_TICKS_REQUIRED does _watch_practice_start_request() actually trust "ready" and snapshot checkpoint 0 -- see that function's big comment for why a single ready-looking tick isn't enough.
var _practice_place_pending: = false # armed by _on_place_practice_checkpoint_pressed() (idle-frame Button handler) -- consumed on the first PHYSICS tick the player reads as ready, by _watch_practice_place_request() below, same pattern and same reason as _practice_start_waiting above
var _practice_place_ready_stable_ticks: = 0 # THE SEVENTH-PASS FIX -- same stability counter as _practice_ready_stable_ticks above, kept separate since a placement and a start-wait are tracked independently and shouldn't share (or reset) each other's progress
var _practice_checkpoints: = [] # [Dictionary snapshot, ...] -- index 0 is the practice start point
var _practice_segments: = [] # [Array of per-frame key-state Dictionaries, ...] -- segments[i] connects checkpoints[i] -> checkpoints[i+1]
var _practice_current_segment: = [] # frames recorded since the last committed checkpoint
var _practice_markers: = [] # [Node2D, ...] parallel to _practice_checkpoints, purely visual
var _practice_prev_alive: = true # for edge-detecting the alive -> dead transition
var _practice_deaths_this_segment: = 0 # just a stat surfaced in the UI/log
var _practice_awaiting_native_respawn: = false # THE NINTH-PASS FIX -- true from the tick a death is detected until either the native alive flag comes back true on its own, or PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS ticks have passed, whichever comes first; see the big comment on PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS for why the checkpoint restore waits for this instead of firing the instant alive goes false
var _practice_native_respawn_wait_ticks: = 0 # ticks spent so far waiting on the above, reset to 0 whenever _practice_awaiting_native_respawn is (re)armed
var _practice_playback: = false # a stitched Play Macro run is in progress
var _practice_playback_frames: = [] # flattened frame list currently being played back
var _practice_playback_index: = 0
var _practice_playback_state_corrections: = 0 # number of ticks on which the authoritative recorded state had to repair native replay drift
var _practice_playback_checkpoint_at: = [] # frame index into the above where each checkpoint boundary falls
# Playback Settle -- see the big comment block above _snapshot_is_at_rest()
# for the full rationale and, just as importantly, the infinite-loop history
# this needs to never repeat.
var _practice_playback_settling: = false # currently holding zero input right after a boundary restore, waiting for Box2D to settle
var _practice_playback_settle_ticks_left: = 0
var _practice_playback_settle_last_position: = Vector2.ZERO
var _practice_playback_settled_boundary: = -1 # checkpoint boundary already restored/started; prevents an unexpected repeated callback from restoring the same stitch twice
# Render-only playback track. The real player remains on the authoritative
# recorded physics state; these samples keep the local sprite and camera from
# witnessing the corrective teleport that can occur inside a physics tick.
var _practice_playback_visual_valid: = false
var _practice_playback_visual_player_id: = 0
var _practice_playback_visual_previous: = Vector2.ZERO
var _practice_playback_visual_current: = Vector2.ZERO
var _practice_playback_visual_renderer: Node = null
var _practice_playback_visual_camera: Camera2D = null
var _practice_playback_visual_sample_usec: = 0
var _practice_playback_visual_frame_index: = -2
var _practice_native_tick_game: WPGame = null
var _practice_playback_pending_start: = false # set by _on_play_practice_macro_pressed() (an IDLE-frame callback) so checkpoint 0's actual restore happens on the next PHYSICS tick instead -- see the big comment at that set site for why an idle-frame restore was silently double-integrating one tick of gravity
var _practice_macro_slots: = {} # slot(int) -> {"checkpoints":[...], "segments":[...], "level_context":{...}}
# One-click saved-macro playback survives the menu -> Time Trial scene swap
# because this TASTool node itself lives directly under SceneTree.root.
var _saved_macro_autoplay_slot: = 0
var _saved_macro_autoplay_level_id: = ""
var _saved_macro_autoplay_source_game_id: = 0
var _saved_macro_autoplay_elapsed: = 0.0
var _saved_macro_autoplay_ready_ticks: = 0
var _saved_macro_autoedit_slot: = 0
var _saved_macro_editor_visual_signature: = ""
var _macro_editor_preview_active: = false
var _macro_editor_preview_player_id: = 0
var _macro_editor_preview_snapshot: = {}
var _macro_editor_preview_was_tree_paused: = false
var _macro_editor_preview_camera_id: = 0
var _macro_editor_preview_camera_position: = Vector2.ZERO
var _macro_editor_preview_camera_zoom: = Vector2.ONE
var _macro_editor_preview_camera_follow_offset: = Vector2.ZERO
var _macro_editor_freecam_detached: = false
var _macro_editor_camera: Camera2D = null
var _macro_editor_preview_presentation_nodes: = []
var _macro_editor_preview_renderer: Node = null
var _macro_editor_preview_renderer_pause_mode: = Node.PAUSE_MODE_INHERIT
# Phase 0.9 -- Thin-Block Terrain Fallback. See _maintain_terrain_fallback_rendering()'s
# own comment. Re-decided per-node every time PolygonTerrain finishes a
# recalculate() (dirty flips true->false); the resulting set of "no real
# fill mesh covers this node" instance ids is then re-applied every frame
# while non-empty (PolygonTerrain re-hides nodes on every recalculate).
var _terrain_fallback_level_id: int = 0
# Debug Mode -- see _load_debug_mode_from_disk()/_on_toggle_debug_mode_pressed()
# and the KEY EVENT REPORT section below. The single persisted switch the
# 2026-08-30 tool revamp added: turning it on (a) forces _diag_enabled on too
# so there's no second toggle to remember to flip before recording, and (b)
# makes _advance_practice_playback()'s finish branch auto-build and
# auto-save a key-event comparison report the instant playback ends, with
# zero button presses. Everything it reads (_diag_live_committed/
# _diag_replay_log/_capture_diag_entry()'s per-tick "input"/"position"/
# "play_time" fields) already existed for Divergence Diagnostics -- this
# doesn't add a second recording system, it just also renders that same
# data as discrete press/release events instead of (or alongside) a raw
# per-tick dump.
var _debug_mode_enabled: = false
var _diag_enabled: = false # Divergence Diagnostics -- see _capture_diag_entry()
var _diag_live_current: = [] # per-tick diag entries since the last committed checkpoint -- parallel to _practice_current_segment, same clear-on-death/commit-on-checkpoint lifecycle
var _diag_live_committed: = [] # [Array of diag entries, ...] -- parallel to _practice_segments, index-for-index
var _diag_world_level_instance_id := 0
var _diag_world_nodes := []
var _diag_replay_log: = [] # flat per-tick diag entries captured live during the most recent Play Macro run -- parallel to _practice_playback_frames

# Phase 0.1 -- Replay Determinism Check. A live-updating summary of the same
# comparison _on_compare_diagnostics_pressed() already does after the fact,
# computed incrementally each playback tick instead of only on demand.
var _replay_check_stop_on_desync: = false
var _replay_check_live_flat: = [] # snapshot of _flatten_diag_live() taken once when playback starts
var _replay_check_safe_ticks: = 0 # snapshot of _diag_coverage_prefix_ticks() taken once when playback starts
var _replay_check_compared_ticks: = 0
var _replay_check_matched_ticks: = 0
var _replay_check_first_desync_tick: = -1
var _replay_check_first_desync_field: = ""
var _replay_check_first_desync_category: = ""
var _replay_check_largest_drift: = 0.0

# Phase 0.2 -- Replay Self-Test. Wraps Play Macro in a repeat-test harness on
# top of the Replay Determinism Check above -- see _start_replay_self_test()
# and _on_replay_self_test_run_finished().
var _self_test_active: = false
var _self_test_stop_on_failure: = false
var _self_test_total_runs: = 0
var _self_test_completed_runs: = 0
var _self_test_results: = [] # [{run, passed, fail_frame, accuracy}, ...]

# One Node._physics_process callback is one Godot fixed physics step, including
# every step in a render-frame catch-up burst.  wp_game_data.play_time belongs
# to another node and is observed before that node runs because this tool has
# an extremely early process priority, so it must never be used to skip or
# invent macro frames.  Keep the old counters/field names for report and save
# compatibility; after this correction only the normal callback count grows.
var _live_tick_last_play_time: = -1.0 # legacy diagnostic field; no longer used to decide whether a frame exists
var _live_tick_fingerprint_normal: = 0
var _live_tick_fingerprint_phantom: = 0
var _live_tick_fingerprint_backfilled: = 0

# THE TWENTY-SECOND-PASS FIX (2026-08-31) -- see OPEN INVESTIGATION NOTES
# item 1's "CONFIRMED ON PLAYBACK TOO" entry. THE FOURTEENTH-PASS FIX's
# Engine.time_scale pause/single-step wrapper assumed every
# _physics_process() call it receives during Play Macro corresponds to
# exactly one already-happened, already-confirmed real physics tick --
# "this callback IS the confirmation," per that pass's own comment. A real
# report from a demanding level proved that assumption wrong: Godot's own
# fixed-timestep engine loop can call _physics_process() more than once in
# a single real (rendered) frame to catch up whenever that frame ran long
# (exactly what a visually-heavy/"very difficult" level is prone to) --
# and time_scale, being a global scale on how much virtual time elapses
# PER tick rather than a "run at most one physics tick total" throttle,
# can't actually stop a catch-up burst already under way when it's toggled
# mid-callback: the physics engine simply doesn't advance during the
# zeroed-out ticks (position/velocity genuinely frozen, matching the
# report's evidence exactly), yet _advance_practice_playback() still gets
# called for each one anyway. Same root mechanism THE THIRTEENTH-PASS FIX
# already proved and fixed for live recording's own _physics_process()
# calls (see _live_tick_last_play_time above) -- just never checked for on
# the playback side, because THE FOURTEENTH-PASS FIX's single-step design
# was believed to make it structurally impossible there. It isn't. Fixed
# the same proven way: fingerprint playback's own calls via
# wp_game_data.play_time too (see the check at the top of
# _advance_practice_playback()) and skip -- do nothing at all, not even a
# duplicate capture -- on any call where play_time didn't actually move.
var _playback_tick_last_play_time: = -1.0 # legacy diagnostic field; no longer used to advance or suppress playback
var _playback_tick_fingerprint_normal: = 0
var _playback_tick_fingerprint_phantom: = 0
var _playback_tick_fingerprint_gap: = 0

# ----------------------------------------------------------------------
#  Restore Drift Diagnostics -- purely observational (never changes
#  gameplay/physics itself, unlike Playback Settle) -- see
#  _arm_restore_drift_watch() for what this measures and why.
# ----------------------------------------------------------------------
var _restore_drift_enabled: = false
var _restore_drift_watches: = [] # in-progress watches: [{"player":WPPlayer, "start_position":Vector2, "snap_velocity":Vector2, "snap_grounded":bool, "ticks_left":int, "positions":[Vector2,...]}, ...]
var _restore_drift_log: = [] # finished watch summaries this session -- see _finish_restore_drift_watch()

# ----------------------------------------------------------------------
#  Debug Noclip -- free flight for investigation only; never touches
#  recording/playback state. See _apply_noclip_movement().
# ----------------------------------------------------------------------
var _noclip_enabled: = false
var _noclip_prev_body_enabled: = true

# Death-velocity freeze (THE TWENTY-FOURTH/THIRTIETH/THIRTY-FIRST-PASS
# FIXES) -- see the big comment in _physics_process() where these are used.
var _freeze_prev_alive: = true # for edge-detecting the alive -> dead transition, independent of (and parallel to) _practice_prev_alive's own copy of the same edge -- kept separate since this one must keep running whether or not Macro Bot Mode is recording
var _freeze_last_alive_position: = Vector2.ZERO # player.position as of the most recent tick it was still alive -- see THE THIRTY-FIRST-PASS FIX
var _post_physics_guard: Node = null
var _cosmetic_sandbox: Node = null
var _macro_editor: CanvasLayer = null
var _autoplay_bot: Node = null
var _replay_hub: CanvasLayer = null
var _game_tools: CanvasLayer = null
var _ping_optimizer_enabled = true
var _practice_continue_frame = -1
var _practice_continue_auto_resume = false
var _continue_resimulating = false
var _continue_new_frames = []
var _continue_start_snapshot = {}
var _saved_macro_continue_slot = 0
var _practice_continue_buttons = {}
var _social_hub: CanvasLayer = null
var _cosmetic_loadouts: CanvasLayer = null
var _editor_theme_pack: Node = null
var _match_map_preview: CanvasLayer = null
var _wins_leaderboard: Node = null
var _world_overlay: Node2D = null
var _input_display: CanvasLayer = null
var _updater: Node = null
var _update_checks_enabled := false
var _updater_status_label: Label = null
var _updater_latest_label: Label = null
var _updater_rollback_button: Button = null
var _updater_install_button: Button = null
var _pending_update_manifest := {}
var _tas_gui_enabled: = true
var _sandbox_gui_enabled: = true
var _replay_hub_gui_enabled: = false
var _game_tools_gui_enabled: = false
var _social_hub_gui_enabled: = true
var _cosmetic_loadouts_gui_enabled: = true
var _editor_theme_pack_enabled: = true
var _match_map_preview_enabled: = true
var _wins_leaderboard_enabled: = true
var _leaderboard_search_enabled: = true
var _leaderboard_search_cooldown_until_msec: = 0
var _leaderboard_search_row: HBoxContainer = null
var _leaderboard_search_status_label: Label = null
var _custom_lobby_code_enabled: = true
var _custom_lobby_code_busy: = false
var _custom_lobby_code_row: Control = null
var _custom_lobby_code_status_label: Label = null
var _claude_experimental_icons_enabled: = false
var _claude_icon_texture_cache: = {} # icon_name (String) -> Texture or null (cached "not found")
var _claude_modern_font_data: DynamicFontData = null
var _claude_modern_font_load_attempted: = false
var _claude_menu_nav_row: HBoxContainer = null
var _workspace_menu = null
var _claude_menu_nav_buttons: = []
var _claude_menu_title_icon: TextureRect = null
var _claude_log_title_icon: TextureRect = null
var _hitbox_viewer_enabled: = false
var _trajectory_preview_enabled: = false
var _input_display_enabled: = false
var _input_display_detailed: = false
var _input_display_hold_frames: = false
var _hitbox_categories: = {
	"player": true,
	"solids": false,
	"hazards": false,
	"sensors": false,
	"dynamic": false,
}
var _visual_seam_polish_enabled: = false
var _visual_seam_filter_position: = Vector2.ZERO
var _visual_seam_last_output: = Vector2.ZERO
var _visual_seam_filter_remaining: = 0.0
var _visual_seam_output_valid: = false
const VISUAL_SEAM_BLEND_SECONDS: = 0.12
const VISUAL_SEAM_MAX_DISTANCE: = 96.0
var _post_guard_player_id: = 0
var _post_guard_prev_alive: = true
var _post_guard_saw_gameplay_death: = false
var _post_guard_probe_ticks_left: = 0
var _post_guard_last_accepted_position: = Vector2.ZERO
var _post_guard_last_accepted_vx: = 0.0
var _post_guard_momentum_corrections: = 0

# Death Freeze Diagnostics (THE THIRTY-THIRD-PASS FIX) -- see
# _watch_death_freeze_diagnostics() and DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN's
# own big comment for why this exists. Deliberately its own separate
# alive-edge tracker (_death_diag_prev_alive), independent of both
# _freeze_prev_alive (which only updates when the freeze block itself
# actually runs -- exactly the "is it even running" question this is meant
# to answer without depending on) and _practice_prev_alive (which only
# updates while _practice_active).
var _death_diag_prev_alive: = true
var _death_diag_active_watch = null # Dictionary while a death window is being captured, null between deaths
var _death_diag_ticks_since_respawn: = -1 # -1 = respawn not yet observed this watch

var _status_message: = ""
var _status_message_timer: = 0.0
var _tool_popup_layer: CanvasLayer = null

var _title_font: DynamicFont = null
var _header_font: DynamicFont = null
var _body_font: DynamicFont = null
var _small_font: DynamicFont = null

var _menu_open: = false
var _log_open: = false
var _prev_mouse_mode: = -1
var _overlay_hidden: = false # F1: hides both windows/tab bars and Macro Bot checkpoint markers -- everything keeps running in the background
var _dragging: = {"menu": false, "log": false}

# UI refs -- TAS menu window
var _overlay_layer: CanvasLayer
var _menu_window: VBoxContainer
var _tab_row: HBoxContainer # hidden entirely (not just the panel) while `enabled` is false, so a
                             # disabled tool leaves NOTHING clickable sitting over the game/menu
var _tab_button: Button
var _scale_label: Label
var _scale_input: SpinBox
var _diag_label: Label # temporary FPS/node-count diagnostic -- see _build_menu_window()
var _toast_pill: PanelContainer
var _menu_panel: PanelContainer
var _inactive_label: Label
var _section_tabs: TabContainer # each heading (Playback/Recording/Jumpzone/Replays/Checkpoints/Macro Bot) is its own tab/page
var _tool_tab_scrolls: = []
var _log_scroll: ScrollContainer
var _resizing: = {"menu": false, "log": false}
var _window_geometry = null
var _gui_layout_config := ConfigFile.new()
var _gui_layout_defaults := {}

var _play_stop_button: Button
var _speed_label: Label
var _frame_step_checkbox: CheckBox
var _step_button: Button
var _step_config_row: Control
var _step_count_label: Label
var _buffer_action_buttons: = {} # action name -> Button
var _jumpzone_button: Button
var _jumpzone_config_row: Control
var _jumpzone_interval_label: Label
var _jumpzone_hold_label: Label
var _fps_limit_label: Label

var _practice_toggle_button: Button
var _practice_status_label: Label
var _practice_place_button: Button
var _practice_undo_button: Button
var _practice_clear_button: Button
var _practice_play_button: Button
var _practice_auto_respawn_button: Button
var _practice_auto_activate_button: Button
var _debug_mode_toggle_button: Button
var _debug_tools_container: VBoxContainer
var _diag_toggle_button: Button
var _diag_compare_button: Button
var _diag_status_label: Label
var _stop_on_desync_button: Button
var _replay_check_status_label: Label
var _self_test_x3_button: Button
var _self_test_x5_button: Button
var _self_test_x10_button: Button
var _self_test_stop_on_failure_button: Button
var _self_test_status_label: Label
var _restore_drift_toggle_button: Button
var _restore_drift_save_button: Button
var _restore_drift_status_label: Label
var _noclip_toggle_button: Button
var _visual_seam_polish_button: Button
var _sync_moving_objects_button: Button
var _sync_moving_objects_enabled: = true
var _hitbox_viewer_button: Button
var _trajectory_preview_button: Button
var _input_display_button: Button
var _input_display_detailed_button: Button
var _input_display_hold_frames_button: Button
var _hitbox_category_row: HBoxContainer
var _hitbox_category_buttons: = {}
var _practice_macro_slot_count: = DEFAULT_PRACTICE_MACRO_SLOTS
var _practice_macro_grid: GridContainer = null
var _practice_macro_slot_status_labels: = [] # index 0 unused, then one entry per user-created slot
var _practice_macro_slot_play_buttons: = []
var _practice_macro_slot_load_buttons: = []
var _practice_macro_slot_delete_buttons: = []
var _practice_macro_slot_edit_buttons: = []
var _practice_macro_slot_cards: = []

var _ui_last_paused = null # tri-state (null/true/false) so restyling only happens on change
# Every one of these caches the last string/value actually shown, so
# _update_overlay() only ever touches a Label/Button property (which
# invalidates that Control's layout) when the displayed value truly
# changed, instead of every single idle frame regardless -- see the
# PERFORMANCE note in the header doc-comment.
var _ui_last_tab_text: = ""
var _ui_last_log_tab_text: = ""
var _ui_last_speed_text: = ""
var _ui_last_step_disabled = null
var _ui_last_practice_status: = ""
var _ui_last_replay_check_status: = ""
var _ui_last_diag_text: = ""
var _ui_next_diag_refresh_msec: = 0

# UI refs -- Log window
var _log_window: VBoxContainer
var _log_tab_row: HBoxContainer
var _log_tab_button: Button
var _log_panel: PanelContainer
var _log_list_vbox: VBoxContainer
var _log_entries: = [] # newest last: {"text","time","undo"(Dictionary or null),"row"}


# Phase 0.9 -- Thin-Block Terrain Fallback.
#
# The theme-null theory (see CLAUDE_IMPLEMENTATION_NOTES.md section 12,
# "Level Theme Repair -- DISPROVEN AND REVERTED") was wrong. The real cause,
# confirmed against "Tower of Reflection"'s own exported level JSON and the
# grassy theme's real theme.tres:
#
#   PolygonTerrain.gd (project_specific/level_editor/PolygonTerrain.gd, base
#   game) merges every "block"/"ramp" LevelNode's Polygon2D into one mesh,
#   then insets it inward by each theme's three stroke thicknesses plus a
#   corner radius to draw rounded, layered outlines. For the grassy theme
#   (terrain_color_1/2/3_thickness = 0.025/0.03/0.04, times 256, per
#   PolygonTerrain's own math) that's roughly 3, 10 and 19 units of inward
#   offset, with terrain_corner_radius = 10. The level's own JSON shows its
#   two tower-wall blocks are only 2 units wide (2x230 and 2x234) -- nowhere
#   near enough width to support even the smallest of those insets, let alone
#   a 10-unit corner round. The native polygon-offset step (GDClipper2, a
#   GDExtension/native class with no decompiled .gd source to read or patch)
#   collapses for that geometry, so process_polys() ends up with zero usable
#   fill shapes while the outer boundary line still draws -- a hollow shape
#   with a real theme-colored outline (grassy's terrain_color_2 IS a bright
#   pink, Color(1, 0.368627, 0.996078, 1) -- not a "no theme" debug fallback).
#
# PolygonTerrain.gd and GDClipper2 aren't ours to edit, so this compensates
# from the mod side instead of reimplementing the merge: once per level load,
# after PolygonTerrain's own first merge attempt has actually completed,
# check whether it produced any real fill mesh despite the level having
# block/ramp geometry. If it didn't, take over rendering those specific
# LevelNodes individually -- undo PolygonTerrain's own node.hide() call on
# each one and set the currently-hidden, textureless Polygon2D underneath it
# (see e.g. nodes/block/Renderer.tscn: visible=false, no texture, exists only
# as merge input geometry) to visible with the theme's terrain_texture. This
# does not attempt the merge/inset/rounding itself -- it only prevents a
# failed merge from leaving the level fully invisible.
var _terrain_maintenance_next_ms = 0
var _terrain_maintenance_child_count = -1


# DIAGNOSTIC (temporary, see _maintain_terrain_fallback_rendering()'s own
# comment): prints straight to godot.log via print(), unlike _log_action()
# which only reaches the in-tool Action Log panel. Only prints when the
# message actually changes, so it can stay unconditional without spamming
# the log every single frame.
var _terrain_fallback_debug_last_message: String = ""


# 1.2.10 -- Len asked to just cover every remaining node type rather than
# keep finding and fixing them one report at a time. This is now every
# node_type folder under project_specific/level_editor/nodes/ EXCEPT "block"
# and "ramp" (those already get their own dedicated, textured fallback in
# _apply_terrain_fallback_rendering_unconditional() above -- forcing them
# here too would just be redundant, not wrong, but keeping one function per
# type avoids two different pieces of code fighting over the same node).
# Confirmed this is the complete list via device_list_dir on
# project_specific/level_editor/nodes/ directly (not guessed/inferred), and
# that node_type is always exactly the folder name (LevelNodeFactory.gd sets
# `node.node_type = node_type` from the directory name it scanned, with no
# aliasing layer -- confirmed against physics_block/ice_block/jump_zone/
# sawblade already, see the 1.2.7 entry).
const FORCE_VISIBLE_NODE_TYPES: = [
	"physics_block",
	"ice_block",
	"jump_zone",
	"sawblade",
	"alert",
	"arrow",
	"background",
	"background_ramp",
	"background_ramp2",
	"background2",
	"background3",
	"bouncy_block",
	"cannon",
	"checkpoint",
	"disappearing_block",
	"finish_line",
	"floor",
	"gravity_field",
	"laser",
	"music_block",
	"pit",
	"recharger",
	"sign",
	"start",
]


var _macro_editor_timer_pills := []
var _macro_playback_timer_pills := []


# ============================================================================
#  Macro Bot Mode -- world-space marker, drawn purely from this script
#  (no level assets / scenes needed). A GD-style ring-and-flag at each
#  committed checkpoint; the most recent one is restyled pink by
#  _restyle_practice_markers() so it's obvious which one death sends you
#  back to.
# ============================================================================
class CheckpointMarker extends Node2D:
	var ring_color: = Color(0.211765, 0.541176, 0.854902)
	var label_text: = ""
	var _font: DynamicFont = null

	func _ready() -> void:
		z_index = 4096

	func setup(color: Color, text: String, font: DynamicFont) -> void:
		ring_color = color
		label_text = text
		_font = font
		update()

	func _draw() -> void:
		var r: = 28.0
		draw_arc(Vector2.ZERO, r, 0.0, 2.0 * PI, 28, ring_color, 5.0, true)
		draw_arc(Vector2.ZERO, r * 0.55, 0.0, 2.0 * PI, 20, ring_color, 3.0, true)
		draw_line(Vector2(0, -r), Vector2(0, -r - 34), ring_color, 4.0, true)
		draw_line(Vector2(0, -r - 34), Vector2(16, -r - 26), ring_color, 4.0, true)
		draw_line(Vector2(16, -r - 26), Vector2(0, -r - 18), ring_color, 4.0, true)
		if _font != null and not label_text.empty():
			draw_string(_font, Vector2(-6, r + 26), label_text, ring_color)
