extends Node

# TASTool: shared state (variables, constants, signals, inner classes), in the original order.

# TASTool: shared state (variables, constants, signals, inner classes), in the original order.

# TASTool: shared state (variables, constants, signals, inner classes), in the original order.

const ModPaths = preload("user://mod/core/ModPaths.gd")
# (Long history comment moved to TASTool/NOTES.md, section "enabled".)
export var enabled: = true
export var only_active_in_debug_or_solo: = true
export var start_with_menu_open: = false
export var start_with_log_open: = false
export var enable_frame_step: = false # off by default -- turn it on in the menu
export var frame_step_count: = 5
export var jumpzone_interval_ms: = 250.0 # time between the start of each jump press
export var jumpzone_hold_ms: = 200.0 # how long each press is held -- see PERFECT JUMPZONE MODE below
export var ui_scale: = 1.0 # scales both windows uniformly -- see the Scale control next to the drag grip
export var menu_background_opacity: = 0.35 # 0 = fully see-through, 1 = solid -- applies to both windows' panel backgrounds
export var fps_limit: = 0 # 0 = uncapped (engine default) -- see _apply_fps_limit()/FRAME RATE LIMIT below

# ---- tunables ----
const TIME_SCALE_STEP: = 0.1
const TIME_SCALE_MIN: = 0.05
const TIME_SCALE_MAX: = 2.0
const FRAME_STEP_COUNT_MIN: = 1
const FRAME_STEP_COUNT_MAX: = 60
const DEFAULT_PRACTICE_MACRO_SLOTS: = 1
const MAX_PRACTICE_MACRO_SLOTS: = 99
const PRACTICE_MACRO_DIR: = ModPaths.PRACTICE_MACRO_DIR
const PRACTICE_MACRO_LAYOUT_PATH: = ModPaths.MACRO_SLOTS_CFG
const SAVED_MACRO_AUTOPLAY_TIMEOUT_SECONDS: = 90.0
const DIAGNOSTIC_UI_REFRESH_MSEC: = 250
const DIAG_DIR: = ModPaths.DIAGNOSTICS_DIR
# Debug Mode's one on/off bit, persisted to its own tiny file so it survives
# the game restart every TASTool.gd update requires -- see
# _load_debug_mode_from_disk()/_save_debug_mode_to_disk(). Deliberately not
# folded into a bigger settings blob: this is the only piece of Macro Bot
# Mode state that needs to survive a restart at all (checkpoints/segments/
# macros already have their own explicit Save-to-slot flows, and reloading
# THOSE mid-comparison is exactly what "don't suggest loading instead of
# re-recording" ruled out -- Debug Mode itself carries no macro data, just
# the one flag, so persisting it doesn't run into that problem).
const DEBUG_MODE_SETTINGS_PATH: = ModPaths.DEBUG_MODE_CFG
# FRAME RATE LIMIT (2026-09-01, added directly in response to the user's own
# request: "you need to let me limit the game to a specific framerate
# configurably") -- OPEN INVESTIGATION NOTES item 1's own frame-rate-
# variability hypothesis has pointed at unstable/erratic render frame timing
# (reported as swinging ~400-800 fps) as a likely contributor to real-time
# gaps in native tick delivery ever since this item was first opened, and
# the newest real evidence (that item's THE TWENTY-SIXTH-PASS FIX follow-up)
# confirmed those gaps are directly responsible for a real, consequential
# Divergence Diagnostics residual (a replay ending at a different tick than
# live because of exactly one such gap's unrecoverable intermediate ticks).
# The suggested next experiment throughout that whole item was always
# "does this get better with a STABLE frame rate (V-Sync or an external
# cap)" -- but this tool never actually gave the user a way to set that cap
# from in-game, so testing it required a separate external tool/driver
# setting. This closes that gap directly: a persisted, in-menu frame rate
# cap via Engine.set_target_fps(), the same primitive external frame
# limiters use. Persisted the same way Debug Mode already is (a tiny
# standalone .cfg file, not folded into the bigger checkpoint/macro
# save-slot system) since, like Debug Mode, it's a tool-level preference
# that should survive the game restart every TASTool.gd update requires,
# not per-run practice state.
const FPS_LIMIT_SETTINGS_PATH: = ModPaths.FPS_LIMIT_CFG
const GUI_LAYOUT_PATH: = ModPaths.GUI_LAYOUT_CFG
const FPS_LIMIT_STEP: = 10
const FPS_LIMIT_MIN: = 0 # 0 is the sentinel for "uncapped" -- matches Engine.set_target_fps()'s own convention, not a real 0fps cap
const FPS_LIMIT_MAX: = 500
const MAX_LOG_ENTRIES: = 60
const JUMPZONE_INTERVAL_MIN_MS: = 50.0
const JUMPZONE_INTERVAL_MAX_MS: = 2000.0
const JUMPZONE_HOLD_MIN_MS: = 16.0
const JUMPZONE_TIMING_STEP_MS: = 10.0
const UI_SCALE_MIN: = 0.1
const UI_SCALE_STEP: = 0.1
const MENU_TAB_CONTENT_H: = 600 # fixed visible height per section-tab page; taller content scrolls inside it

# CORRECTED: this used to be a set of hardcoded physical keys (W/A/S/D/Space),
# on the assumption that the native player controller reads raw keyboard
# state directly. It does NOT. The real input path (confirmed verbatim in
# project_specific/GameInput.gd's _process_input()) reads Godot's INPUT
# ACTION layer exclusively -- Input.get_action_strength("player_right") /
# ("player_left") for movement, Input.is_action_pressed("player_up") for
# jump, Input.is_action_just_pressed("player_dash") for dash -- and this
# game's own project.godot binds EACH of those actions to several physical
# inputs at once (player_right, for example: Right-arrow, D, AND a joypad
# button), not just the one key this tool used to assume. Recording raw
# Input.is_key_pressed(KEY_D) only ever sees a literal D key press -- a
# player using the arrow keys (or Z for jump, or X for dash -- also
# first-class defaults in this game) would have every one of those inputs
# silently recorded as "nothing happened," which is exactly what "the macro
# does none of what I did" looks like. There's also no "player_down" action
# consumed by player movement anywhere in the game (it's wired to an
# unrelated UI slider widget, goodoh/ui/components/ControllerSlider.gd) --
# so the old KEY_MOVE_DOWN entry was never doing anything real either.
#   Recording/replaying at the ACTION layer instead of the key layer sees
# and reproduces the input correctly no matter which physical key, joypad
# button, or on-screen touch control actually produced it -- this is also
# proven correct by the game's OWN touch controls, which synthesize the
# exact same InputEventAction objects this tool now uses (see
# goodoh/ui/components/TouchableButton.gd / InputActionOnPress.gd).
const ACTION_JUMP: = "player_up"
const ACTION_DASH: = "player_dash"
const ACTION_MOVE_LEFT: = "player_left"
const ACTION_MOVE_RIGHT: = "player_right"

# The actions Macro Bot Mode records/replays -- one bool per physics frame,
# per action, capturing whatever actually reached Input.is_action_pressed()
# that frame (real keyboard/joypad/touch, Buffered Inputs, or Perfect
# Jumpzone alike -- all of them ultimately resolve to actions).
const PRACTICE_RECORD_ACTIONS: = [ACTION_JUMP, ACTION_DASH, ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT]
const PRACTICE_FRAME_STATE_KEY: = "__tas_recorded_state"
# A dash is an edge-triggered native command, and its direction is decided at
# that exact edge.  Keeping the direction beside the held-action frame avoids
# reconstructing it later from dictionary/event dispatch order.
const PRACTICE_DASH_DIRECTION_KEY: = "__tas_dash_direction"
# Public gameplay fields which are safe to reassert at the beginning of a
# replay tick.  alive/body_enabled/dead_counter are deliberately excluded:
# an actual replay death must still stop the macro instead of being hidden.
const PRACTICE_FRAME_RESYNC_SCALAR_FIELDS: = ["dash_cooldown", "dash_timer", "coyote_timer", "squish_counter", "wallslide_counter", "wallslide_dir", "stun_timer", "is_inside_one_way_platform", "stick_to_ground_timer", "facing_dir", "ground_normal", "ground_tangent_speed"]
const POST_PHYSICS_GUARD_SCRIPT_PATH: = ModPaths.POST_PHYSICS_GUARD
const COSMETIC_SANDBOX_SCRIPT_PATH: = ModPaths.COSMETIC_SANDBOX
const MACRO_EDITOR_SCRIPT_PATH: = ModPaths.MACRO_EDITOR
const AUTOPLAY_BOT_SCRIPT_PATH: = ModPaths.AUTOPLAY_BOT
const REPLAY_HUB_SCRIPT_PATH: = ModPaths.REPLAY_HUB
const GAME_TOOLS_SCRIPT_PATH: = ModPaths.GAME_TOOLS
const SOCIAL_HUB_SCRIPT_PATH: = ModPaths.SOCIAL_HUB
const COSMETIC_LOADOUTS_SCRIPT_PATH: = ModPaths.COSMETIC_LOADOUTS
const EDITOR_THEME_PACK_SCRIPT_PATH: = ModPaths.EDITOR_THEME_PACK
const MATCH_MAP_PREVIEW_SCRIPT_PATH: = ModPaths.MATCH_MAP_PREVIEW
const WINS_LEADERBOARD_SCRIPT_PATH: = ModPaths.WINS_LEADERBOARD
const WORLD_OVERLAY_SCRIPT_PATH: = ModPaths.WORLD_OVERLAY
const INPUT_DISPLAY_SCRIPT_PATH: = ModPaths.INPUT_DISPLAY
const WINDOW_GEOMETRY_SCRIPT_PATH: = ModPaths.WINDOW_GEOMETRY
const UPDATER_SCRIPT_PATH: = ModPaths.UPDATER
const MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS: = [
	"res://project_specific/LevelSDFViewport.gd",
	"res://project_specific/FullScreenBlocks.gd",
	"res://project_specific/background/Background.gd",
	# 1.2.9 -- PhysicsBlockRenderer.gd deliberately removed from this list.
	# Len confirmed physics blocks were still invisible even after the 1.2.8
	# force-visible pass, unlike jump_zone/sawblade which it fixed immediately.
	# The difference: PhysicsBlockRenderer.gd (unlike the generic
	# LevelNodeRenderer jump_zone/sawblade/ice_block/block/ramp all use) has
	# its OWN _process() that unconditionally sets `visible = false` again
	# every single frame whenever ViewportRectCalculator.viewport_visible_rect
	# doesn't intersect the block's world rect. Being pause-exempted (as it
	# was here previously) meant that _process() kept running every frame
	# during Timeline Editor preview and re-fighting _force_dynamic_object_visibility_late()'s
	# `visible = true` back to false one frame later, even though that
	# function is deferred specifically to run after it. Since the whole
	# point of Phase 0.9 at this stage is "always show it, no condition,
	# exactly like ramps/blocks already are", there is no reason to keep this
	# script running (and re-fighting us) during preview at all -- removing
	# it from this list means it simply never runs while paused, so whatever
	# `visible` value _force_dynamic_object_visibility_late() sets is never
	# contested again for the rest of that preview session.
	"res://project_specific/level_editor/nodes/ice_block/ShaderUniformCamera.gd",
	# Spins the blade and picks which of 3 sprite sizes to show based on the
	# node's grid size -- `if not visible: return` at the top of its own
	# _process() means it also depends on being force-shown by
	# _force_dynamic_object_visibility_late() below to ever run in the first
	# place while the Timeline Editor has the tree paused.
	"res://project_specific/level_editor/nodes/sawblade/Renderer.gd",
	# Read from the decompiled source: PolygonTerrain.gd merges every "block"/
	# "ramp" LevelNode's individual Polygon2D into one themed terrain mesh and
	# only THEN calls node.hide() on the primitives it just merged (see
	# process_level_node()). That merge is deferred behind a `dirty` flag that
	# _process() consumes one tick at a time -- on_loaded_level() sets it, but
	# nothing forces it to run before the next tick. Timeline's preview pauses
	# the tree via _begin_macro_editor_preview() and can land exactly between
	# level load and that first merge, leaving every block/ramp visible as an
	# unmerged, un-hidden primitive ("naked" scattered blocks). Adding this
	# path exempts it from the pause the same way as the entries above, and
	# _refresh_macro_editor_presentation() below calls its _process()
	# synchronously right after pausing, so a pending merge completes
	# immediately instead of never running.
	"res://project_specific/level_editor/PolygonTerrain.gd",
]
const SETTING_TAS_GUI: = "client_tools_tas_gui"
const SETTING_SANDBOX_GUI: = "client_tools_avatar_sandbox_gui"
const SETTING_REPLAY_HUB_GUI: = "client_tools_replay_hub_gui"
const SETTING_GAME_TOOLS_GUI: = "client_tools_game_tools_gui"
const SETTING_SOCIAL_HUB_GUI: = "client_tools_social_hub_gui"
const SETTING_COSMETIC_LOADOUTS_GUI: = "client_tools_cosmetic_loadouts_gui"
const SETTING_EDITOR_THEME_PACK: = "client_tools_editor_theme_pack"
const SETTING_MATCH_MAP_PREVIEW: = "client_tools_match_map_preview"
const SETTING_WINS_LEADERBOARD: = "client_tools_wins_leaderboard"
const SETTING_LEADERBOARD_SEARCH: = "client_tools_leaderboard_search"
const SETTING_CUSTOM_LOBBY_CODE: = "client_tools_custom_lobby_code"
const SETTING_HITBOX_VIEWER: = "client_tools_hitbox_viewer"
const SETTING_TRAJECTORY_PREVIEW: = "client_tools_trajectory_preview"
const SETTING_VISUAL_SEAM_POLISH: = "client_tools_visual_seam_polish"
const SETTING_SYNC_MOVING_OBJECTS: = "client_tools_sync_moving_objects"
const SETTING_STOP_ON_DESYNC: = "client_tools_stop_on_desync"
const SETTING_SELF_TEST_STOP_ON_FAILURE: = "client_tools_self_test_stop_on_failure"
const SETTING_INPUT_DISPLAY: = "client_tools_input_display"
const SETTING_INPUT_DISPLAY_DETAILED: = "client_tools_input_display_detailed"
const SETTING_INPUT_DISPLAY_HOLD_FRAMES: = "client_tools_input_display_hold_frames"
const SETTING_UPDATE_CHECKS: = "goobplayability_update_checks"
# "Update ready" popup: shown on the first launches that find a version, until "Don't remind me".
const SETTING_UPDATE_PROMPT_VERSION: = "goobplayability_update_prompt_version"
const SETTING_UPDATE_PROMPT_COUNT: = "goobplayability_update_prompt_count"
const SETTING_UPDATE_PROMPT_MUTED: = "goobplayability_update_prompt_muted"
const UPDATE_PROMPT_LAUNCHES: = 3
const GOOBPLAYABILITY_VERSION: = "2.0.0"
const SETTING_CHANGELOG_VERSION: = "goobplayability_changelog_version"
const SETTING_HITBOX_CATEGORY_PREFIX: = "client_tools_hitbox_category_"
# Claude Experimental Mode -- opt-in, OFF by default. Currently gates a single
# purely-cosmetic experiment: swapping in the approved Goobplayability icon
# pack (PNGs shipped alongside the mod scripts under user://mod/icons/) next
# to existing menu titles/tabs. No layout, sizing, or behavior changes either
# way -- toggling it off (or never installing the icons/ folder) leaves every
# menu pixel-identical to how it already looked.
const SETTING_CLAUDE_EXPERIMENTAL_ICONS: = "client_tools_claude_experimental_icons"
const CLAUDE_EXPERIMENTAL_ICON_DIR: = ModPaths.ICONS_DIR
# Clean sans-serif font (Inter SemiBold, SIL OFL licensed) shipped alongside
# the mod's own scripts, same pattern as the icons above. Used in place of
# the game's rounded Baloo font only when the modern theme is active --
# DynamicFontData.font_path loads straight from a plain file path (no res://
# import needed), the same mechanism the icon PNGs already rely on via
# File/Image. If this file is missing, _make_font() falls back to Baloo
# exactly as if the toggle were off.
const CLAUDE_EXPERIMENTAL_FONT_PATH: = ModPaths.MAIN_FONT
const HITBOX_CATEGORIES: = [
	["player", "PLAYER", "The goober's collision shape."],
	["solids", "SOLIDS", "Static walls, floors and platforms."],
	["hazards", "HAZARDS", "Spikes, saws, pits and other hazards."],
	["sensors", "SENSORS", "Triggers and non-solid sensor areas."],
	["dynamic", "DYNAMIC", "Moving and physics-driven blocks."],
]

# ----------------------------------------------------------------------
#  Divergence Diagnostics -- see the big comment block above
#  _capture_diag_entry() for what this is and how to read its output.
#  DIAG_SCALAR_FIELDS are compared with exact equality (bools/ints, or
#  anything where the game itself only ever assigns whole discrete values);
#  DIAG_FLOAT_FIELDS get an epsilon tolerance since two independently-taken
#  floating point values that are "the same" for gameplay purposes can still
#  differ in their last bit or two.
# ----------------------------------------------------------------------
const DIAG_SCALAR_FIELDS: = ["alive", "body_enabled", "dead_counter", "dash_cooldown", "dash_timer", "coyote_timer", "squish_counter", "wallslide_counter", "wallslide_dir", "stun_timer", "is_inside_one_way_platform", "stick_to_ground_timer", "facing_dir"]
const DIAG_VECTOR_FIELDS: = ["position", "linear_velocity"]
const DIAG_WORLD_FIELDS: = ["world_fingerprint"]
const DIAG_POSITION_EPSILON: = 0.05
const DIAG_VELOCITY_EPSILON: = 0.05
const DIAG_CONTEXT_WINDOW: = 5 # ticks shown before/after the first divergence in the report -- see _build_divergence_context_lines()

# ----------------------------------------------------------------------
#  Playback Settle -- used only before checkpoint 0 starts playing. Internal
#  stitch boundaries must consume their next recorded frame immediately;
#  inserting even one neutral physics tick there is a visible pause and also
#  lets the freshly teleported body drift before the segment begins.
# ----------------------------------------------------------------------
const PLAYBACK_SETTLE_MAX_TICKS: = 5 # hard cap regardless of stabilization -- this is what makes settling ALWAYS terminate
const PLAYBACK_SETTLE_VELOCITY_EPSILON: = 0.05 # a restored snapshot's linear_velocity below this counts as "at rest"
const PLAYBACK_SETTLE_STABLE_EPSILON: = 0.05 # position movement below this between two ticks counts as "already stabilized" (ends the hold early)

# ----------------------------------------------------------------------
#  THE SIXTEENTH-PASS FIX (2026-08-31) -- see the big comment above
#  _apply_practice_playback_computed_horizontal_velocity() for the full
#  reasoning. These two numbers are reverse-engineered directly from the
#  user's own real-game test recordings (test 1: a clean grounded press
#  held from rest; test 2: a grounded press already sitting at the cap),
#  not read from any decompiled source -- WPGameData/WPGameNativeFunctions,
#  where the real constants actually live, are fully native/compiled with
#  no .gd source anywhere in the decompile. Both fit that data essentially
#  exactly:
#    PLAYBACK_GROUND_ACCEL: test 1's live linear_velocity.x climbed by
#    16.666666/16.666664/16.666660/16.666672/16.666657 units on five
#    consecutive grounded ticks holding one direction from a dead stop --
#    as constant a delta as floating point ever gets, i.e. flat linear
#    acceleration, and 16.6667 units/tick * 60 ticks/sec = 1000.0 units/s^2
#    on the nose.
#    PLAYBACK_GROUND_MAX_SPEED: test 2's live linear_velocity.x hit
#    -400.000061 and sat there, unchanging, for the rest of that press --
#    matching a number a much older pass of this file (long since
#    superseded) had already independently landed on from a different
#    angle. 400.0 even is close enough to call it the real cap.
#  Airborne (mid-air, fresh-press) horizontal movement is deliberately NOT
#  covered by this fix yet -- it clearly follows some kind of
#  exponential-approach curve rather than flat linear acceleration (the
#  per-tick delta visibly decays), and the curve's rate constant is a very
#  consistent ~0.0212 across every sample this file has ever captured, but
#  the speed it approaches did NOT come back consistent (target ~555-585
#  across otherwise-clean same-formula samples, varying by ~5% in a way a
#  single shared constant can't explain -- possibly a dependency on
#  vertical fall speed at the moment of the press, unconfirmed). Shipping
#  a guessed airborne model on top of an already-uncertain formula is
#  exactly the kind of unverified fix this whole investigation has been
#  trying to get away from, so airborne horizontal movement is left to the
#  game's own native physics for now, same as it always has been.
const PLAYBACK_GROUND_ACCEL: = 1000.0 # units/s^2, grounded horizontal acceleration toward whatever direction is held
const PLAYBACK_GROUND_MAX_SPEED: = 400.0 # units/s, grounded horizontal speed cap in either direction

# ----------------------------------------------------------------------
#  THE SEVENTEENTH-PASS FIX (2026-08-31) -- see the big comment above
#  _apply_practice_playback_computed_horizontal_velocity()'s airborne branch
#  for the full reasoning. Unlike the grounded numbers above, these did NOT
#  come from fitting the user's live gameplay data with a free-parameter
#  curve -- that approach is what produced item 9's inconsistent "target
#  speed" in the first place. Instead these are the game's own real,
#  named tuning constants, read directly out of upguys.exe's ClassDB
#  property-registration metadata (the user supplied the exe; see the
#  conversation for the disassembly approach -- byte-pattern search for
#  known float values, cross-checked against actual SSE float-load
#  instructions, then correlated with the human-readable getter/setter
#  name strings Godot's ClassDB bakes in right next to each property's
#  default value). The real engine exposes THREE separate air-accel
#  numbers -- player_air_accel_min=600.0, player_air_accel_max=800.0,
#  player_air_accel_duration=1.0 (presumably a ramp between the two over
#  that many seconds) -- plus player_air_friction_lambda=1.0 and
#  player_max_horizontal_vel_air=400.0 (same cap as grounded). This fix
#  uses only accel_max, friction_lambda, and the cap -- see
#  PLAYBACK_AIR_ACCEL's own comment for why the ramp is deliberately left
#  out. Re-simulating the user's own test-3 real recording (a fresh RIGHT
#  press mid-freefall) with a friction-opposed-acceleration model
#  (dv/dt = accel - lambda*v, semi-implicit-Euler-integrated at 60Hz --
#  the same style of formula Box2D itself uses for its own built-in linear
#  damping, which is a good sign this is structurally the right shape, not
#  just a coincidence) using these exact real numbers reproduced the
#  measured decaying-per-tick-delta curve far better than the free-fit
#  exponential from item 9 ever explained it, though not perfectly --
#  see the STATUS entry in TASTool_TICK_ACCURACY_PLAN.md for the actual
#  fit numbers and the honest confidence level this ships at (lower than
#  the grounded fix -- explicitly flagged to the user as an experiment).
const PLAYBACK_AIR_ACCEL: = 800.0 # units/s^2 -- SUPERSEDED by PLAYBACK_AIR_ACCEL_MAX/MIN/DURATION below (THE NINETEENTH-PASS FIX); kept defined so nothing else referencing it breaks, no longer used by the airborne branch itself
const PLAYBACK_AIR_FRICTION_LAMBDA: = 1.0 # matches the real player_air_friction_lambda constant exactly -- confirmed BOTH from ClassDB registration metadata AND, as of THE NINETEENTH-PASS FIX, from the actual decompiled instruction sequence that applies it (see below) -- opposes velocity every tick, same shape as Box2D's own linear damping
const PLAYBACK_AIR_MAX_SPEED: = 400.0 # units/s -- matches the real player_max_horizontal_vel_air constant exactly (same cap as grounded); confirmed as the literal clamp target in the decompiled function too, not just a registered property

# ----------------------------------------------------------------------
#  THE NINETEENTH-PASS FIX (2026-08-31, later the same day again) -- at the
#  user's explicit direction ("find the source by any means necessary")
#  after being asked twice whether the real physics FUNCTION (not just its
#  tuning constants) could be recovered. It could: WPPlayer's native
#  ClassDB property getters are single-instruction trampolines
#  (`movss xmm0, [this+OFFSET]; ret`), which made every exported movement
#  constant's exact struct offset recoverable by disassembling the getter
#  itself. Once those offsets were known, grep-ing the rest of upguys.exe's
#  .text section for code that touches SEVERAL of those specific offsets
#  together (not just one -- a bare offset like +0x294 collides with
#  dozens of unrelated classes' fields, but three or four of THIS class's
#  offsets appearing within the same ~100 bytes of machine code is not a
#  coincidence) landed directly on WPPlayer's real per-tick horizontal
#  movement function. This is no longer a fit against limited live-gameplay
#  samples -- it's the actual compiled formula, read back out of x86-64.
#
#  The grounded branch needed NO changes: the decompiled logic backsolves
#  a reduced delta-time so that applying the flat walk_accel for exactly
#  that reduced time would land precisely on player_max_horizontal_vel_walk,
#  then applies it -- which, for a constant accel within a single tick, is
#  mathematically identical to "accelerate then clamp," exactly what THE
#  SIXTEENTH-PASS FIX already shipped. That explains test 1's real 270-tick
#  exact match: it was already right.
#
#  The airborne branch was NOT right, and the real decompiled sequence is
#  two separate steps applied every airborne tick, in this order:
#    1. FRICTION DECAY (applied unconditionally while airborne, even with
#       no direction held): velocity.x *= exp(-player_air_friction_lambda * dt).
#       This is the exact real formula, not the SIXTEENTH-PASS FIX's guess
#       that friction and acceleration combined into one ODE -- the engine
#       keeps them as two discrete per-tick operations.
#    2. RAMPED ACCELERATION (only while a direction is held): the engine
#       tracks how many consecutive ticks the SAME direction has been held
#       while continuously airborne (resetting on landing, on release, or
#       on a direction change -- see _practice_playback_air_hold_ticks'
#       own comment for exactly how that's approximated here), converts
#       that to a 0..1 ratio against player_air_accel_duration, and uses it
#       to linearly interpolate the acceleration MAGNITUDE from
#       player_air_accel_max DOWN to player_air_accel_min (800 -> 600 over
#       1.0 real second) -- i.e. air acceleration is strongest at the
#       instant you leave the ground or first press a direction, and decays
#       toward a lower steady-state accel the longer it's held, which is
#       the OPPOSITE of a ramp-up and explains why item 9's free-fit curve
#       kept finding an inconsistent "target speed": it was trying to fit
#       a decaying-accel process with a single asymptote formula.
#       velocity.x += accel_magnitude(t) * facing * dt, then hard-clamped
#       to player_max_horizontal_vel_air exactly as before (the decompiled
#       clamp is a "scale back the last increment so it lands exactly on
#       the cap" scale-back rather than a post-hoc clamp, but those two are
#       numerically identical for a constant per-tick accel, same as the
#       grounded case above).
#  One piece was NOT fully recovered: the exact two boolean flags gating
#  the real hold-tick counter's increment (this file's best reading is
#  "holding a direction" and "was already airborne last tick", but their
#  precise semantics weren't traced end to end) -- so the reset conditions
#  below (grounded, released, or direction changed) are this file's
#  best-faith reconstruction of that gating, not a byte-for-byte copy of
#  it. Everything else in this fix -- both formulas, both constants sets,
#  the friction-then-accel ordering, and the clamp -- came directly out of
#  the disassembly, not a fit.
const PLAYBACK_AIR_ACCEL_MAX: = 800.0 # units/s^2 -- real player_air_accel_max, re-confirmed this pass directly from the ADD_PROPERTY default-value immediate (0x44480000 = 800.0f) next to the property's own registration code
const PLAYBACK_AIR_ACCEL_MIN: = 600.0 # units/s^2 -- real player_air_accel_min, re-confirmed the same way (0x44160000 = 600.0f)
const PLAYBACK_AIR_ACCEL_DURATION: = 1.0 # seconds -- real player_air_accel_duration; confirmed as a runtime GLOBAL (not per-instance) at a fixed .data address, read directly: exactly 1.0

# ----------------------------------------------------------------------
#  THE EIGHTEENTH-PASS FIX (2026-08-31, later still) -- see the big comment
#  in _apply_practice_playback_computed_horizontal_velocity()'s grounded
#  branch for the full reasoning. A real macro recording (user-supplied:
#  hold RIGHT to the cap, release, then immediately hold LEFT without
#  waiting for the coast-down to finish) showed the flat linear-decel model
#  above is simply wrong for this case -- real ground braking against
#  existing momentum decays MUCH faster than a flat 1000 units/s^2 ramp,
#  and the decay isn't even linear, it's a shrinking delta each tick. The
#  live (ground-truth) tick-to-tick ratio implied a decay constant of
#  ~7.5-13 depending on exactly how it's measured, and -- far more
#  precisely -- the REPLAY side's very first post-reversal tick matched
#  `previous_velocity * exp(-7.5 * tick_rate)` to five decimal places,
#  where 7.5 is upguys.exe's own player_ground_friction_lambda constant
#  (see item 10/OPEN INVESTIGATION NOTES for how that was extracted). That
#  match is far too exact to be coincidence.
#    Live's own numbers decayed slightly FASTER than a pure friction-only
#  exponential predicts, suggesting the real native formula combines this
#  friction term with the new direction's acceleration simultaneously
#  (the same general shape as the airborne model above) rather than a
#  clean two-phase "brake to zero, then accelerate" split -- but with only
#  six real ticks to check against, all still positive (never crossing
#  zero), fitting that combined formula with confidence would repeat
#  exactly the overfitting risk that produced item 9's inconsistent
#  airborne "target speed." So this fix uses ONLY the well-confirmed piece
#  (exponential decay via the real lambda=7.5 constant) for the braking
#  phase, and falls back to the already-validated flat-linear
#  accelerate-toward-target model once the decaying velocity crosses back
#  through (near) zero -- which is provably closer to the truth than the
#  flat-linear-the-whole-way model this replaces, even though the exact
#  moment-of-crossover behavior is an engineering guess, not something the
#  available data confirms (no real sample actually crosses zero).
const PLAYBACK_GROUND_BRAKE_LAMBDA: = 7.5 # matches the real player_ground_friction_lambda constant exactly -- decay rate while held direction opposes current velocity
const PLAYBACK_GROUND_BRAKE_CROSSOVER_EPSILON: = 1.0 # units/s -- CONFIRMED exact by THE TWENTIETH-PASS FIX's disassembly (see below): the real decompiled code snaps EXACTLY to the target once the decayed value is within 1.0 unit of it, on both the reversal-to-zero and over-cap-toward-cap branches. What was a guess is now a decompiled fact, and it happened to already be right.

# ----------------------------------------------------------------------
#  THE TWENTIETH-PASS FIX (2026-08-31, later still) -- at the user's
#  explicit direction to keep pushing the same static-analysis technique
#  that produced item 12/THE NINETEENTH-PASS FIX ("keep looking... take as
#  much time until you get both") specifically at the two things that pass
#  left unresolved: the airborne accel-ramp counter's exact reset gating,
#  and the unnamed internal field (offset 0x2b8) read by the grounded
#  reversal-braking block. One came back fully answered, the other only
#  partially -- reported honestly below rather than papered over.
#
#  0x2b8 IS NAMED: `player_ground_friction_max_speed_lambda` (registered
#  default 1.0, found via the same ADD_PROPERTY-string-to-getter trace as
#  every other constant in this file -- its trivial getter is at a
#  slightly separated address than its sibling properties' island, which
#  is exactly why the first pass's blind offset search initially walked
#  past it as "no getter found"). Re-reading the full reversal-braking
#  block with this name in hand clarified the whole mechanism, which turns
#  out to handle TWO distinct cases through the same shared code path,
#  selected by comparing the held direction's sign against the current
#  velocity's sign:
#    - SIGNS DISAGREE (a genuine direction reversal, this file's existing
#      "opposing" case): decays toward a target of exactly ZERO using
#      `player_ground_friction_lambda` (7.5) -- CONFIRMING there is no
#      "combined friction+acceleration" formula after all. Item 11's
#      suspicion that live's faster-than-predicted decay meant a hidden
#      combined term was a reasonable read of six data points, but the
#      actual compiled code is a clean two-phase brake-to-zero-then-
#      accelerate split, exactly what THE EIGHTEENTH-PASS FIX already
#      shipped as its "provisional" model. It wasn't provisional; it was
#      right, once bugs (there weren't any, as it turns out) are excluded
#      -- the exact snap distance was the only real gap, and PLAYBACK_
#      GROUND_BRAKE_CROSSOVER_EPSILON's pre-existing value of 1.0 already
#      matched it exactly.
#    - SIGNS AGREE but the current speed's magnitude is already ABOVE
#      player_max_horizontal_vel_walk (e.g. carried in from a dash, wall
#      jump, or other source of speed this file's own accel model never
#      produces on its own) -- a case this file never modeled at all
#      before now: decays toward a target of `move * PLAYBACK_GROUND_
#      MAX_SPEED` (the cap, signed to match the held direction) using
#      `player_ground_friction_max_speed_lambda` (1.0) instead of the
#      steeper 7.5. Both cases share the identical decay-with-exact-snap
#      shape; only the target and the lambda differ.
#  Ordinary same-direction movement under the cap is untouched by any of
#  this -- it was never gated through this block to begin with.
#
#  THE AIR-HOLD-COUNTER GATING WAS NOT FULLY RESOLVED, reported honestly:
#  tracing the counter's owning object (`r13` inside the real physics
#  function) back to its caller revealed it isn't a persistent per-player
#  field at all -- it's pulled fresh out of a queue each call via
#  `call 0x14143d200(container, index)`, inside a loop that runs once per
#  BUFFERED input frame this render frame needs to catch up on (the same
#  buffered-input mechanism already implicated in item 8/9's jump-timing
#  race). That confirms the overall architecture but not the two specific
#  boolean flags (`r13+0x2be`, `r13+0x2d8`) that gate the counter's
#  increment -- pinning those down would mean tracing how and when that
#  queue's slots get reused/reset, which is a meaningfully bigger dig than
#  a single static pass, and static analysis alone (no debugger, no
#  running game) has a real ceiling here. _practice_playback_air_hold_ticks'
#  reset conditions (landing, releasing, direction change) remain this
#  file's best-faith reconstruction, unchanged from THE NINETEENTH-PASS
#  FIX -- not a regression, just not the byte-for-byte answer the user
#  asked for on that specific half of the question.
const PLAYBACK_GROUND_OVERCAP_LAMBDA: = 1.0 # matches the real player_ground_friction_max_speed_lambda constant's registered default exactly -- decay rate back toward the cap when current speed is already ABOVE it while still holding the same direction (e.g. carried-in speed from a dash/wall-jump); see THE TWENTIETH-PASS FIX's comment above

# THE SEVENTH-PASS FIX (2026-08-30): how many CONSECUTIVE physics ticks
# _player_ready_for_checkpoint() must read true, in a row, before
# _watch_practice_start_request()/_watch_practice_place_request() actually
# trust it and snapshot a checkpoint -- see the big comment on those two
# functions for the evidence (a live recording where the player read
# alive=true/body_enabled=true for exactly ONE tick, then the level's own
# native logic disabled the body again for several more ticks before
# genuinely starting). 3 ticks (50ms at 60fps) is comfortably past that
# one-tick flicker while still imperceptible as a delay to a human pressing
# Start.
const PRACTICE_READY_STABLE_TICKS_REQUIRED: = 3

# Checkpoint 0 has an additional constraint that ordinary checkpoints do
# not need.  The native game briefly reaches LEVEL_PLAY with an enabled
# player, then performs a one-time startup handoff which may reset velocity
# and pause the game timer for a callback.  A checkpoint captured inside
# that window cannot replay deterministically because restoring it later
# does not re-run the handoff.  The diagnostics from 2026-09-01 caught the
# exact signature: live velocity 45 -> 0 with unchanged position, while a
# restored replay continued 45 -> 60 before any input was pressed.
const PRACTICE_START_MIN_ACTIVE_TICKS: = 12

# THE NINTH-PASS FIX (2026-08-30): a cosmetic, native bug the user reported
# from real play -- the goober losing limbs after repeated deaths -- that
# this file has no direct access to (no limb/rig/ragdoll code exists
# anywhere in this script; whatever draws and animates the character model
# is entirely native/compiled). The mechanism this tool CAN affect: a real
# death normally runs the native game's own death animation/cleanup for
# however long player.dead_counter takes to count down, and only then does
# respawn_player() reposition/re-enable the player for real. Auto-Respawn
# (below, in _physics_process()) used to short-circuit that completely --
# the instant alive flips false, it force-writes alive=true/position/
# velocity/etc. from the checkpoint snapshot on that SAME tick, skipping the
# entire native hold. A human dying normally always lets that hold run to
# completion first; Auto-Respawn had never once done that, and does it far
# more often per minute than any human retrying by hand ever would -- exactly
# the kind of repeated, unnaturally-fast death cycling the user described.
# If the limb bug's cleanup lives inside that hold (or fires when it
# completes, e.g. inside respawn_player() itself), repeatedly cutting the
# hold off before it ever finishes would starve it of the one chance it
# gets to reset -- consistent with the bug accumulating over repeated deaths
# specifically.
#   The fix: on death, wait for the native alive flag to come back TRUE ON
# ITS OWN (i.e., let the native hold and whatever respawn_player() does run
# to completion) before laying the checkpoint restore on top of it, instead
# of preempting it. Capped at this many ticks so a death type that never
# naturally re-enables the player (no counted hold at all) can't leave
# Auto-Respawn stuck waiting forever -- 60 ticks (1s @ 60fps) comfortably
# covers a typical death-hold while still bounding the worst case.
#   Not independently verified against the actual limb bug (there's no way
# to reproduce a native rendering bug from this script), but it directly
# targets the one behavior in this file that removes the natural gap a real
# death always has, and it can't make things worse: the checkpoint restore
# below still runs exactly once per death either way, and every field it
# writes is unconditionally overwritten from the snapshot regardless of
# what the native hold did in the meantime -- so position/velocity/etc.
# staying correct for macro accuracy doesn't depend on this at all.
const PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS: = 60
# (Long history comment moved to TASTool/NOTES.md, section "RESTORE_DRIFT_WATCH_TICKS".)
const RESTORE_DRIFT_WATCH_TICKS: = 20 # how many physics ticks to keep observing position after each restore
const RESTORE_DRIFT_STABLE_EPSILON: = 0.02 # tick-to-tick position movement below this counts as "stopped moving" for that tick
const RESTORE_DRIFT_GROUND_PROBE_DISTANCE: = 3000.0 # how far straight down to look for solid ground at restore time, in world units -- wide enough to clear a full level's height (real gameplay checkpoints have been observed 700+ units apart vertically), since the first, narrower 200-unit probe came back empty even on restores that provably hit SOMETHING (a death) well within a couple of seconds of falling
const RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES: = ["sleeping", "is_sleeping", "awake", "is_awake"] # see _probe_body_sleep_state() -- best-effort names to try for a native Box2D "is this body asleep" flag; none are confirmed to exist on this build

# ----------------------------------------------------------------------
#  Death Freeze Diagnostics (2026-08-31, THE THIRTY-THIRD-PASS FIX) -- see
#  _watch_death_freeze_diagnostics(). Added after THE THIRTIETH/THIRTY-
#  FIRST/THIRTY-SECOND-PASS FIXES all shipped, each stub-verified and each
#  individually well-reasoned, and the user reported the exact same
#  "momentum after dying" symptom persisting through all three anyway.
#  Three real-hardware misses in a row on the same reported symptom means
#  continuing to guess a fourth time isn't the responsible move -- this
#  file's own standing methodology is to diagnose from real evidence, not
#  theory alone, and there's no real evidence yet of what's ACTUALLY
#  happening on the user's machine when this fires. This isn't another fix
#  attempt: it's an always-on (no toggle needed -- there's nothing to
#  remember to turn on before the death that matters) diagnostic capture,
#  independent of and unaffected by every other Diagnostics feature's own
#  on/off state, specifically built to answer the two questions that would
#  explain all three prior misses at once:
#    1) Is the freeze code even running at all when this happens? (If
#       `enabled` is somehow false, or `_tool_restricted()` reads true --
#       e.g. the death happens outside Time Trial mode -- NONE of THE
#       THIRTIETH/THIRTY-FIRST/THIRTY-SECOND-PASS FIXES ever execute, no
#       matter how correct their logic is. This is checked and logged
#       UNCONDITIONALLY, from a call placed ahead of _physics_process()'s
#       own `if not enabled or _tool_restricted(): return` gate, so it
#       still sees and reports a death even in exactly the scenario where
#       the freeze itself wouldn't have run.)
#    2) If it IS running, which specific guarantee is actually failing on
#       real hardware -- position still moving tick to tick while
#       "frozen," velocity reading nonzero, body_enabled/body.enabled
#       reading true when they should already be false, or something not
#       yet theorized at all (e.g. a RESPAWN, not the death itself,
#       putting the player back with residual motion -- this file has
#       never actually looked at that transition specifically).
#  Captures a full window around every death -- from the tick death is
#  first observed, through DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN ticks past
#  the tick the player is next observed alive again (or DEATH_DIAG_
#  MAX_ENTRIES ticks total, whichever comes first, as a hard safety cap in
#  case respawn is never observed at all) -- and auto-saves a report to
#  DIAG_DIR the moment each window closes, no button press required. See
#  _build_death_freeze_report_text() for exactly what gets flagged.
# ----------------------------------------------------------------------
const DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN: = 15 # how many ticks past the observed respawn to keep capturing, to catch a respawn-transition-specific leak (question 2 above) that the death-side alone wouldn't show
const DEATH_DIAG_MAX_ENTRIES: = 600 # hard safety cap (~10s at 60fps) in case respawn is never observed at all this watch (e.g. the level/session ends mid-hold) -- without this a single missed respawn would grow this log forever

# ----------------------------------------------------------------------
#  Debug Noclip -- see _apply_noclip_movement().
# ----------------------------------------------------------------------
const NOCLIP_SPEED: = 300.0

# label, action name -- shared by the Buffered Inputs UI grid
const BUFFERABLE_ACTIONS: = [
	["Jump", ACTION_JUMP],
	["Left", ACTION_MOVE_LEFT],
	["Right", ACTION_MOVE_RIGHT],
	["Dash", ACTION_DASH],
]

# ---- hotkeys (all single keys, no Ctrl/Alt chords) ----
const KEY_TOGGLE_MENU: = KEY_F1
const KEY_SLOWER: = KEY_F2
const KEY_FASTER: = KEY_F3
const KEY_RESET_SPEED: = KEY_F4
const KEY_PLAY_STOP: = KEY_F5
const KEY_FRAME_STEP: = KEY_F6
const KEY_EMERGENCY_CAMERA_RESTORE: = KEY_F7 # Phase 0.4 -- Freecam Stability Pass, see _process()'s unconditional check below
# Input.is_key_pressed() reads the OS/layout-translated keycode (same as
# every other hotkey above), so this fires on whatever key is actually
# LABELED "F" on the player's own keyboard -- German QWERTZ included, where
# that's a different physical key than on a US QWERTY board -- not a fixed
# physical position. Only fires _on_place_practice_checkpoint_pressed()
# (see _handle_macro_bot_hotkeys()), which already no-ops with a log message
# if Macro Bot Mode isn't active, so this is safe to leave always-armed.
#   THE TWENTY-EIGHTH-PASS FIX (2026-08-31, user request): was KEY_Y --
# GooberDash's own default binding for Jump (ACTION_JUMP/"player_up") is
# also Y, so placing a checkpoint and jumping fought over the same key the
# whole time this tool has existed. Moved to F, which isn't bound to
# anything else in this file or (per the user) their own in-game controls.
const KEY_PLACE_CHECKPOINT: = KEY_F

# ---- GooberDash palette, lifted from the game's own UI resources ----
const FONT_PATH: = "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"
const COLOR_PANEL_BG: = Color(0, 0.129412, 0.262745, 0.9) # goodoh/styles/upguys_style_dark_pill
const COLOR_PANEL_BORDER: = Color(0, 0, 0, 0.55)
const COLOR_BLUE: = Color(0.211765, 0.541176, 0.854902) # goodoh/styles/button_basic
const COLOR_PLAY_GREEN: = Color(0.117647, 0.690196, 0.423529) # one-click saved-macro launch accent
const COLOR_PURPLE: = Color(0.55, 0.31, 0.88)
const COLOR_PINK: = Color(1, 0.219608, 0.588235) # WPTheme hover/focus pink
const COLOR_PINK_DARK: = Color(0.8, 0.117647, 0.439216) # WPTheme pressed pink
const COLOR_SLOT_EMPTY: = Color(0, 0.129412, 0.262745, 0.68) # translucent dark navy card
const COLOR_SLOT_FILLED: = Color(0.501961, 0.756863, 0.945098, 0.82) # translucent filled card
const COLOR_SLOT_FILLED_BORDER: = Color(0, 0.447059, 0.780392) # upguys_style_grid_cell border


const COLOR_WHITE: = Color(1, 1, 1)
const COLOR_TEXT_DIM: = Color(0.72, 0.8, 0.95)
const COLOR_DISABLED: = Color(0.35, 0.38, 0.44, 0.7)
const COLOR_GRIP: = Color(0, 0.09, 0.19, 0.95)
