extends Node
class_name TASTool

# ============================================================================
#  GooberDash TAS Tool  --  slowdown / replay / checkpoints
#  Single-file debug utility. No scene required.
# ----------------------------------------------------------------------------
#  INSTALL
#   1. Copy this file into the project, e.g. res://tools/TASTool.gd
#   2. Project Settings -> AutoLoad -> add it as "TASTool" (Node, enabled).
#      (Autoload makes it survive scene changes, so it keeps working across
#      the level-select -> gameplay -> retry flow.) It can also just be
#      attached to any always-present node in a single gameplay scene if you
#      don't want it globally available.
#   3. Both windows (TAS MENU and LOG, top-left corner, or F1 to hide/show)
#      are available on ANY screen -- main menu, level select, in a level --
#      as long as this is installed as an autoload (see step 2). They only
#      go into their "inactive" read-only state while you're actually inside
#      a live, non-time-trial multiplayer match; everywhere else, including
#      screens with no game running at all, the full menu and its Configure
#      panels are open for setup (arming Auto-Record/Perfect Jumpzone,
#      setting frame-step count, arming Buffered Inputs, etc.) before you're
#      even in a level. Drag either window around by its top grip bar, and
#      resize the whole UI with the −/+ next to the drag grip (applies to
#      both windows). Nothing needs to be wired up in the level or player
#      scripts -- the tool finds the running WPGame and the local WPPlayer
#      on its own.
#   4. Setting `enabled` to false (export var, or your own code) hides
#      BOTH tab bars completely, not just the dropdown panels -- a
#      disabled tool leaves nothing clickable sitting over the game or
#      another menu underneath. A merely CLOSED window still leaves its
#      small tab visible/clickable by design (so you can reopen it) --
#      drag it out of the way if it happens to sit over something you need
#      to click, or set `enabled = false` to get rid of it entirely.
#   5. The TAS MENU is organized as one tab strip per heading (Tools, Macro
#      Bot) instead of one long scrolling wall -- click a tab to switch
#      section. Each section is also independently scrollable (mouse wheel,
#      or drag its scrollbar) since Macro Bot has more content than fits in
#      the fixed panel height. Panel backgrounds are translucent by default
#      (`menu_background_opacity`, 0..1) so the game stays visible
#      underneath. Macro Bot Mode is the only macro/checkpoint system this
#      file has -- everything else (slowdown, frame-step, Buffered Inputs,
#      Perfect Jumpzone) lives under Tools since none of it is specific to
#      routing.
#
#  HOTKEYS
#   F1        Hide / show the ENTIRE overlay -- both windows, tab bars, and
#             Macro Bot checkpoint markers included. Everything armed
#             (Perfect Jumpzone, Buffered Inputs, Macro Bot Mode, all other
#             hotkeys) keeps running in the background exactly the same
#             whether it's visible or not -- this is purely a "get it off my
#             screen for a second" toggle, not a pause. Press F1 again
#             (there's nothing left to click) to bring it back.
#   F2 / F3   Slower / faster
#   F4        Reset speed to 1.0x
#   F5        Play / Stop
#   F6        Frame step, while stopped (only if Frame-Step Mode is on --
#             it's OFF by default, turn it on in the menu; each press
#             advances "Steps per press" physics frames, 5 by default,
#             configurable via the Configure button next to it)
#   F         Place Checkpoint (Macro Bot Mode) -- the one Macro Bot action
#             with a keybind, since it's the one you'll actually want mid-run.
#             (Was Y -- moved off it since GooberDash's own default Jump
#             binding is also Y, see KEY_PLACE_CHECKPOINT's own comment.)
#  Buffered Inputs, Perfect Jumpzone, and every other Macro Bot Mode action
#  (Start, Undo, Clear, Play Macro, Save/Load/Delete slots) have no keybind
#  on purpose -- they're click-only, from the menu / log window.
#
#  SYNTHETIC INPUT TIMING (why this script forces itself to run first)
#   - Buffered Inputs, Perfect Jumpzone, and Macro Bot Mode's Play Macro all
#     feed synthetic key events through Input.parse_input_event(), the same
#     path real keyboard hardware uses. That part is solid. The part that
#     ISN'T automatically solid is WHEN, relative to the native player
#     controller's own _physics_process(), that injection happens -- and it
#     matters a lot more than it sounds like it should.
#   - Godot's Input.is_action_just_pressed()/is_action_just_released() are
#     true for exactly ONE physics tick: the tick during which the event was
#     parsed. If this script's _physics_process() (which does the injecting)
#     happens to run AFTER the controller's in the same tick -- which
#     depends purely on scene-tree add order, something a mod has no control
#     over -- the controller checks for "just pressed" on that tick, sees
#     nothing yet (we haven't injected it), and by the time we do inject it,
#     that tick's edge is already gone. It isn't merely delayed a frame, it's
#     gone for good, silently. Confirmed empirically against a real Godot
#     3.5.3 build with a minimal repro: a single-physics-frame synthetic
#     press is NEVER observed by a node whose _physics_process() runs before
#     ours in the same tick, full stop.
#   - This is almost certainly what was behind jumps occasionally getting
#     eaten entirely during Buffered Inputs / Perfect Jumpzone / Play Macro
#     playback (rather than just being mistimed) -- jump is a single-tick
#     "just pressed" edge, so it's exactly the kind of input this can
#     silently drop, especially for a short tap that's only held 1-2 recorded
#     frames. A dropped jump then carries the wrong momentum into whatever
#     comes next, which is also very likely what caused the "dies on random
#     parts" / "does something wrong" playback-accuracy symptoms that aren't
#     explained by the play_time-restore fix elsewhere in this file.
#   - The fix: _ready() calls set_process_priority() with a very low
#     (very negative) value, which Godot documents as controlling the order
#     _process()/_physics_process() run in across the WHOLE tree, not just
#     among siblings -- so this script's physics tick now always runs before
#     the controller's, regardless of where either one sits in the tree or
#     which was added first. That turns "sometimes never seen" into "always
#     seen this same tick," which is what all three synthetic-input features
#     were already implicitly assuming.
#   - HISTORY: Macro Bot Mode's Play Macro playback briefly stopped using
#     synthetic input entirely partway through this file's history ("THE REAL
#     ACCURACY FIX," 2026-08-30) in favor of driving movement/jump/dash
#     through the native WPGame.set_local_continuous_input()/local_input_dash()
#     calls directly -- a real batching race made synthetic events unsafe at
#     the time: whenever the engine ran more than one physics tick per
#     main-loop iteration (an ordinary occurrence, physics catching up to a
#     slow render frame), a queued press and its queued release could both
#     get dispatched together and collapse into just the last one. That direct-
#     native-call approach turned out to have its own persistent one-tick
#     delivery lag that a long chain of heuristics (THE ONE-TICK LOOKAHEAD
#     through THE TWELFTH-PASS FIX, all since removed) never fully patched
#     over. THE FIFTEENTH-PASS FIX (2026-08-31) moved Play Macro back onto
#     synthetic input via _inject_action() -- the same mechanism described in
#     this section, already proven correct for Buffered Inputs/Perfect
#     Jumpzone. It is safe here because every state change is parsed and
#     flushed synchronously inside this tool's very-early physics callback;
#     a render catch-up batch still consists of distinct fixed-step callbacks,
#     each of which dispatches its own input before the native controller runs.
#     The process-priority fix and the synthetic-input path described above
#     therefore apply to all three features uniformly again.
#
#  BUFFERED INPUTS (frame-step)
#   - Holding a real key down at the exact physics frame you click Step is
#     awkward -- your mouse is busy clicking the button. Instead, arm a key
#     here first (Jump/Left/Right/Down/Dash); the next Step press holds that
#     key down for the whole step (all "Steps per press" frames), then
#     releases it, exactly as if you'd held the real key for that duration.
#     Stays armed across repeated Step presses until you toggle it back off.
#     Works by feeding a synthetic key event through
#     Input.parse_input_event() -- the same path real keyboard hardware
#     uses, so the native player controller can't tell the difference.
#
#  PERFECT JUMPZONE MODE
#   - Auto-presses Jump (W) on a fixed rhythm for as long as it's armed:
#     press, hold for "Hold time", release, wait out the rest of "Interval",
#     repeat. Defaults to a press every 250ms held for 200ms -- both are
#     independently tunable via Configure. The rhythm is driven by the same
#     `delta` the rest of the tool's slowdown already scales, so it slows
#     down WITH you if you practice at less than 1x instead of staying
#     locked to real-world time.
#   - IMPORTANT: the actual jump-height/hold physics live in the native
#     (compiled) player controller, which isn't something this script can
#     read -- so the 200ms default hold isn't verified against that code,
#     it's a starting point. Tune Hold time and Interval against what you
#     actually see in-game for your jump zone's rhythm.
#
#  HOW A CHECKPOINT RESTORE WORKS
#   - Restoring a saved position (checkpoint 0, checkpoint editing, and the
#     compatibility path for an old input-only macro) goes through _restore_player(), which
#     mirrors the game's own respawn_player() exactly: it sets
#     player.position (only -- NOT player.body.position, which is a child
#     node's LOCAL offset and would double-count a world-space position if
#     written directly) and finishes with player._reset_object(), the same
#     native call the real respawn path always ends on. Earlier versions of
#     this tool didn't do either of those correctly, which is what caused
#     visible teleport/position-off-by-a-lot glitches on restore.
#   - New format-3 macros do not hard-respawn at internal stitch boundaries:
#     their first frame already contains the exact authoritative state and is
#     applied directly. This avoids exposing native _reset_object() as a seam.
#   - _restore_player() also resets the local player's on-screen RENDERER
#     (see _reset_renderer_smoothing()) right after teleporting it. The
#     game's renderer does its own client-side smoothing of small position
#     corrections (meant for network jitter, not deliberate teleports) for
#     any jump between 25 and 100 units -- exactly the range GD-style
#     checkpoints tend to be spaced at -- so without this, a restore would
#     still be visually correct a moment later but would visibly GLIDE to
#     the checkpoint first instead of appearing there instantly. This is
#     what "the macro doesn't display correctly" turned out to be.
#
#  MACRO BOT MODE (GD-style segment practice / macro splicing)
#   - Built for hard levels where a straight recording constantly gets wiped
#     out by deaths: instead of one continuous take, you build a macro out of
#     short segments, each one only kept once it reaches the next checkpoint
#     ALIVE. Dying discards whatever was recorded since the last checkpoint
#     -- exactly like a Geometry Dash practice-mode bot -- so a death never
#     costs you progress you already locked in.
#   - Start Macro Bot Mode: snapshots your current position/velocity/timers
#     as checkpoint 0 and drops a ring-shaped marker there, drawn directly by
#     this script (no level assets needed). Place Checkpoint commits
#     everything recorded since the last checkpoint as a segment, snapshots
#     again, and drops the next marker. Undo Last Checkpoint removes the most
#     recent one and its segment and snaps you back to whichever checkpoint
#     is now last.
#   - Auto-Activate on Level Entry (off by default): once armed, Macro Bot
#     Mode starts itself automatically -- checkpoint 0 placed at your actual
#     starting position -- the instant a fresh level begins, so you don't
#     have to click Start Macro Bot Mode by hand every single attempt. Keys
#     off wp_game_data.gameplay_state flipping to GameplayState_LEVEL_PRE,
#     and fires once per level instance -- a full level Retry reloads the
#     scene (a new WPGame instance), which re-arms it for the new attempt;
#     turning the toggle on/off itself doesn't start or stop a run in
#     progress, it only arms/disarms the NEXT level entry.
#   - Auto-Respawn to Checkpoint (on by default): when you die, this lets the
#     level's own respawn timer/animation finish naturally (or waits up to a
#     second, whichever comes first -- see THE NINTH-PASS FIX on
#     PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS for why), then restores you
#     straight to your last placed checkpoint's exact saved state -- same
#     spot, same speed, ready to re-attempt that segment. Turn it off if you'd rather let
#     the level handle death normally and just have the tool quietly discard
#     the failed segment in the background. Global race clocks are deliberately
#     never rewound by a checkpoint restore: doing that made the visible clock
#     oscillate and corrupted the game's own replay timeline. A saved slot's
#     one-click Play path instead opens a fresh level and waits until the clock
#     reaches checkpoint 0's originally-recorded phase before playback starts.
#   - What actually gets recorded is the real, already-in-effect state of
#     Input.is_action_pressed() for the player_up/player_dash/player_left/
#     player_right actions (the same layer the game's own input script reads
#     -- see the ACTION_* constants above), captured once per physics frame --
#     so it faithfully captures real keyboard input on ANY bound key
#     (WASD or arrows or Z/X), joypad input, touch input, Buffered Inputs
#     holds, and Perfect Jumpzone presses alike, whatever mix produced that
#     frame's input. Recording pauses automatically while Debug Noclip is on
#     (see _apply_noclip_movement()) -- noclip drives position directly and
#     bypasses physics entirely, so capturing it as ordinary input would feed
#     Play Macro a completely different trajectory than what actually
#     happened; recording resumes the instant Noclip is turned back off.
#   - Play Macro stitches every committed segment back to back and plays it
#     in place over the current level: it explicitly re-restores each
#     checkpoint's exact player snapshot (position, velocity, movement timers)
#     right before feeding that segment's inputs, rather than just trusting
#     the segments to line up on their own -- so one segment recorded
#     slightly differently than another can't drag the whole macro off
#     course. If the player dies mid-playback, it stops immediately, says so,
#     and -- per whichever of Debug Mode / Diagnostic Logging / Restore Drift
#     Diagnostics are toggled on -- auto-saves a report to disk, the same as
#     a clean finish, so there's always something to look at without a
#     manual button press.
#   - Save/Load/Delete and the green PLAY LEVEL action work on MACRO SLOTS,
#     persisted to
#     user://tas_practice_macros/slot_N.tasmacro, so a saved macro survives
#     restarting the game. Saving also remembers the current Time Trial level
#     link; PLAY LEVEL opens that level, waits for its playable clock phase,
#     loads the slot, and starts it automatically. An in-progress, not-yet-
#     saved run does NOT survive
#     a scene reload (an Edit-reload elsewhere in the level, the level's own
#     Retry) -- it's meant for iterating within one continuous attempt, so
#     save to a slot first if you want to keep progress across one of those.
#
#  WHAT ELSE IT TOUCHES / HOW IT WORKS
#   - Slowdown drives Engine.time_scale. This is global (it also slows menu
#     tweens etc. while a game is running) but is the standard, non-invasive
#     way to slow/pause/frame-advance a Godot game without touching the
#     native tick loop.
#   - Macro Bot Mode's checkpoints save/restore the LOCAL player's kinematic
#     + movement-state fields (position, velocity, dash/coyote/stun timers,
#     etc.) -- the same fields WPGame.respawn_player() /
#     _set_players_to_start_positions() write when the game itself resets a
#     player. It intentionally does NOT snapshot other players, bots, or
#     moving hazards, so it's built for solo practice/routing in a Test or
#     Time Trial scene, not for rewinding a live multiplayer match.
#   - The LOG window records every action this tool takes. Actions that can
#     actually be reversed get a working Undo button; actions that genuinely
#     can't (playing back a macro, an Edit-reload) are still logged but their
#     Undo stays disabled rather than faked.
#   - Both windows are built from real Control/Button nodes, use GooberDash's
#     own Baloo font and the same chunky, thick-white-border pill colors as
#     the game's UI (res://goodoh/... resources), and fall back to plain
#     defaults gracefully if that font ever moves in a future build.
#   - While either window is open the mouse cursor is forced visible so you
#     can click things, then restored to whatever mode the game had it in
#     once both windows are closed.
#
#  PERFORMANCE
#   - _update_overlay() (idle-frame UI refresh) only ever writes to a
#     Label's .text or a Button's .disabled when the value being shown
#     actually changed, caching the last-shown value for comparison first.
#     Godot doesn't skip that write itself even when the new value equals
#     the old one, and each one forces a layout re-sort of that Control's
#     containers -- so writing them unconditionally every single idle frame
#     (as opposed to only on a real change) is what caused the tool to get
#     measurably laggier as more menu sections were added. Follow the same
#     pattern (compare against a cached `_ui_last_*` value, only write on a
#     real change) if you add more live-updating UI.
#   - The section-tab layout (see INSTALL step 5) also helps here: Godot's
#     TabContainer hides every non-active page's Controls, so only the
#     currently-open tab's buttons/labels/grids are actually processed for
#     rendering at any moment, not both sections' worth at once.
#
#  SAFETY
#   `only_active_in_debug_or_solo` (on by default) disables every hotkey and
#   automated behavior (frame-step, Perfect Jumpzone, Buffered Inputs, speed
#   hotkeys, Macro Bot Mode) the moment you're inside a LIVE, non-time-trial
#   game -- i.e. real competitive multiplayer -- unless this is a debug
#   build. That's the one case worth guarding against, so it's the only one
#   that restricts anything: no game at all (main menu, level select, any
#   other screen) is never restricted, since there's nothing live to affect
#   there -- the full menu stays available for setup. Flip
#   `only_active_in_debug_or_solo` off yourself if you specifically want the
#   tool available inside a real match too, in a release build.
# ============================================================================

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
const PRACTICE_MACRO_DIR: = "user://tas_practice_macros"
const PRACTICE_MACRO_LAYOUT_PATH: = "user://tas_macro_slots.cfg"
const SAVED_MACRO_AUTOPLAY_TIMEOUT_SECONDS: = 90.0
const DIAGNOSTIC_UI_REFRESH_MSEC: = 250
const DIAG_DIR: = "user://tas_diagnostics"
# Debug Mode's one on/off bit, persisted to its own tiny file so it survives
# the game restart every TASTool.gd update requires -- see
# _load_debug_mode_from_disk()/_save_debug_mode_to_disk(). Deliberately not
# folded into a bigger settings blob: this is the only piece of Macro Bot
# Mode state that needs to survive a restart at all (checkpoints/segments/
# macros already have their own explicit Save-to-slot flows, and reloading
# THOSE mid-comparison is exactly what "don't suggest loading instead of
# re-recording" ruled out -- Debug Mode itself carries no macro data, just
# the one flag, so persisting it doesn't run into that problem).
const DEBUG_MODE_SETTINGS_PATH: = "user://tas_debug_mode.cfg"
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
const FPS_LIMIT_SETTINGS_PATH: = "user://tas_fps_limit.cfg"
const GUI_LAYOUT_PATH: = "user://goobplayability_gui_layout.cfg"
const FPS_LIMIT_STEP: = 10
const FPS_LIMIT_MIN: = 0 # 0 is the sentinel for "uncapped" -- matches Engine.set_target_fps()'s own convention, not a real 0fps cap
const FPS_LIMIT_MAX: = 500
const MAX_LOG_ENTRIES: = 60
const JUMPZONE_INTERVAL_MIN_MS: = 50.0
const JUMPZONE_INTERVAL_MAX_MS: = 2000.0
const JUMPZONE_HOLD_MIN_MS: = 16.0
const JUMPZONE_TIMING_STEP_MS: = 10.0
const UI_SCALE_MIN: = 0.6
const UI_SCALE_MAX: = 2.0
const UI_SCALE_STEP: = 0.1
const MENU_TAB_CONTENT_H: = 480 # fixed visible height per section-tab page; taller content scrolls inside it

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
const PRACTICE_FRAME_RESYNC_SCALAR_FIELDS: = ["dash_cooldown", "dash_timer", "coyote_timer", "squish_counter", "wallslide_counter", "wallslide_dir", "stun_timer", "is_inside_one_way_platform", "stick_to_ground_timer", "facing_dir"]

# Post-native death-momentum guard. A clean player can gain at most 1000/60
# = 16.667 horizontal velocity from the game's own default ground
# acceleration in one tick. The real reports show impossible post-respawn
# jumps of 53..193 instead, sometimes delayed by two callbacks, followed by
# friction decay. Keep a short observation window and reject only a velocity
# increase larger than this conservative per-tick envelope.
const POST_RESPAWN_MOMENTUM_PROBE_TICKS: = 12
const POST_RESPAWN_MAX_LEGIT_HORIZONTAL_DV: = 20.0
const POST_PHYSICS_GUARD_SCRIPT_PATH: = "user://mod/TASPostPhysicsGuard.gd"
const COSMETIC_SANDBOX_SCRIPT_PATH: = "user://mod/CosmeticSandbox.gd"
const MACRO_EDITOR_SCRIPT_PATH: = "user://mod/TASMacroEditor.gd"
const WORLD_OVERLAY_SCRIPT_PATH: = "user://mod/TASWorldOverlay.gd"
const INPUT_DISPLAY_SCRIPT_PATH: = "user://mod/TASInputDisplay.gd"
const WINDOW_GEOMETRY_SCRIPT_PATH: = "user://mod/GoobWindowGeometry.gd"
const UPDATER_SCRIPT_PATH: = "user://mod/GoobUpdater.gd"
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
const GOOBPLAYABILITY_VERSION: = "1.2.10"
const SETTING_CHANGELOG_VERSION: = "goobplayability_changelog_version"
const SETTING_HITBOX_CATEGORY_PREFIX: = "client_tools_hitbox_category_"
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

# ----------------------------------------------------------------------
#  OPEN INVESTIGATION NOTES (2026-08-30) -- no code change from these yet,
#  logged here so they survive regardless of how the conversation with the
#  user continues. Nothing below is confirmed; don't "fix" either of these
#  without new data that actually points at a mechanism.
# ----------------------------------------------------------------------
#  1) FRAME-RATE VARIABILITY HYPOTHESIS. User reports their actual render
#     frame rate swings constantly and unpredictably (~400-800 fps), and
#     separately that Play Macro "randomly fails" -- not at some fixed,
#     reproducible tick, and specifically as the replayed player visibly
#     TELEPORTING BACKWARD to a checkpoint's saved position after already
#     having walked past that spot in the replay.
#       That teleport is Play Macro's own checkpoint-boundary resync
#     working as designed, not a new bug at the checkpoint itself: Play
#     Macro stitches independently-recorded segments together, and at each
#     recorded checkpoint's own tick index it force-restores the replayed
#     player to that checkpoint's exact snapshot (see the fresh-boundary
#     handling in _advance_practice_playback()) to stop error from one
#     segment bleeding into the next. That's invisible when the replay is
#     still in sync at that tick, because the player is already
#     approximately there. If something desynced the replay EARLIER in the
#     segment, the player can visibly be further along by the time that
#     tick number comes up, and the forced resync then reads as snapping
#     backward past where the run already visually got to. I.e. the
#     checkpoint isn't where the problem happens, just where an earlier,
#     otherwise-invisible desync becomes visible -- which is also why it
#     looks "random": different recordings hit whatever's actually
#     desyncing at different points, or not at all.
#       Checked, from the decompiled game source, whether the underlying
#     simulation could plausibly be frame-rate-dependent: wp_game_data.
#     play_time and the Box2D world step both advance by a fixed
#     `tick_rate` once per _tick_game() call (WPGame.gd), not by real
#     elapsed/idle-frame delta -- so the moment-to-moment simulation itself
#     is tick-counted, not wall-clock-timed, at least at this layer. This
#     tool's own recording capture is similarly tick-scoped: it reads
#     Input.is_action_pressed() (level state, not an edge) exactly once per
#     _physics_process() tick, and the one known real edge-timing hazard
#     found earlier this session (is_action_just_pressed()/
#     is_action_just_released() being a single-PHYSICS-TICK-wide window,
#     not tied to idle/render frames) was already fixed via
#     set_process_priority() forcing this script's tick to always run
#     before the native controller's, regardless of frame rate. So nothing
#     found so far in either the native tick loop or this file's own
#     recording path is obviously frame-rate-sensitive.
#       That doesn't clear the hypothesis, though -- a fixed-timestep
#     accumulator driving _tick_game() from real elapsed time (the usual
#     way a physics loop is decoupled from render rate) is exactly the
#     kind of code that can misbehave specifically under erratic,
#     wildly-swinging frame timing (400 vs 800 fps back to back, rather
#     than a stable rate of either), via float-precision edge cases in the
#     accumulator that a steady frame rate would never hit -- and that
#     code is native/compiled, not something visible from here. The
#     single most useful next data point: whether the desync frequency
#     changes at all with a STABLE frame rate (V-Sync on, or an external
#     frame-rate cap) versus the current unstable one. Don't ask for this
#     as a dedicated test round -- fold it into normal play and mention
#     what happened next time it comes up.
#       STRONG NEW DATA POINT (2026-08-31): a report's FIRST STATE
#     DIVERGENCE landed at tick 1 -- the earliest possible tick after
#     checkpoint 0 -- during plain vertical freefall with ALL FOUR actions
#     held false the entire window (no jump, no dash, no left/right, not
#     even close to a press/release edge). That rules out every input-edge-
#     triggered theory in items 2/3/5 as the ROOT cause (though those fixes
#     stay in -- they're still correct for what they each individually
#     targeted); whatever is happening here needs zero input to trigger, so
#     it has to live in either this tool's tick-capture bookkeeping or the
#     native tick loop itself, matching this item's hypothesis far better
#     than any input-timing theory could. Even more telling: ticks 3 and 4
#     in that same report show byte-identical position AND velocity, on
#     BOTH the live and replay side independently ((-375, -854.749939),
#     vel (0, 90) -- appearing twice in a row under constant, unclamped
#     gravity, which should be physically impossible two ticks running).
#     Two live/replay-independent captures landing on an identical
#     duplicate strongly suggests a single tick's worth of native state got
#     read/logged twice somewhere upstream of both _capture_diag_entry()
#     call sites -- i.e. this tool's own tick-scoped capture (item 1's
#     opening paragraph) sampling the SAME underlying native tick twice
#     back-to-back, exactly the failure mode a real-time-driven _tick_game()
#     accumulator decoupled from _physics_process()'s own schedule would
#     produce under frame-timing jitter. Not confirmed as the mechanism,
#     and not fixable from here even if confirmed (native/compiled, per
#     above) -- but this is the cleanest, most isolated repro of the whole
#     investigation so far, and it points squarely at THIS item rather than
#     anything input-related. The V-Sync/stable-frame-rate test two
#     sentences above is now the single most valuable thing left to try.
#       IMPLEMENTED (2026-08-31, see TASTool_TICK_ACCURACY_PLAN.md delivered
#     alongside this file for the full plan/reasoning, not repeated here):
#     recording and playback got two DIFFERENT fixes, because they aren't
#     symmetric. RECORDING can't be single-stepped (a human is playing it
#     live in real time), so THE THIRTEENTH-PASS FIX gives it a play_time
#     fingerprint instead (see _live_tick_last_play_time's own big comment,
#     and the capture block in _physics_process()) -- unchanged since the
#     last capture = phantom call, skip; advanced by one tick_rate = normal;
#     by more than one = a real gap, back-filled -- so the recorded frame
#     list is now a true 1:1 map of real native ticks despite render
#     frame-rate jitter. PLAYBACK (Play Macro) got THE FOURTEENTH-PASS FIX,
#     per the user's own framing: it no longer runs at real-time pace
#     passively hoping _physics_process() lines up with native ticks --
#     it now pauses (Engine.time_scale = 0.0), single-steps forward exactly
#     one physics tick, confirms that tick via the _physics_process() call
#     it triggers (Godot's own contract, not an assumption), and only then
#     lets _advance_practice_playback() act -- see the wrapper around that
#     call in _physics_process() for the actual mechanism, which reuses the
#     same Engine.time_scale primitive the manual Frame Step feature already
#     uses, just physics-callback-driven instead of idle-polled. That makes
#     the whole "did a native tick happen between two calls" question moot
#     for playback specifically, without needing to ever prove the
#     mechanism above -- the tool now owns the clock instead of sampling it,
#     the way real TAS tools (TASBot, libTAS, Bizhawk, Dolphin frame-
#     advance) actually work.
#       REAL-WORLD VALIDATION (2026-08-31): the very next live macro/report
#     came back with "live recording tick fingerprint: 1067 normal, 0
#     phantom call(s) skipped, 0 tick(s) back-filled" -- a perfectly clean
#     run, confirming THE THIRTEENTH-PASS FIX works correctly on real data
#     and that this specific session's recording was already tick-aligned
#     with zero native-tick decoupling. That divergence still occurred
#     anyway (first at tick 19, a fresh non-jumping airborne LEFT press)
#     rules THIS item OUT as that divergence's cause -- clean fingerprint
#     means there was no duplicated/skipped native tick to blame. That
#     particular failure turned out to belong to items 2/3/5's territory
#     instead (the direct-native-setter one-tick delivery lag and its
#     lookahead heuristics), which is why those items are now marked
#     SUPERSEDED below -- see THE FIFTEENTH-PASS FIX on
#     _sync_practice_playback_injected_input()/_advance_practice_playback().
#     This item's own frame-rate-variability hypothesis remains open and
#     untouched by any of that -- still worth the V-Sync/stable-frame-rate
#     test mentioned above if a future report ever shows the tick-1/
#     duplicate-tick symptom again.
#       CONFIRMED ON PLAYBACK TOO, AND FIXED (2026-08-31, later) -- "very
#     difficult level," macro broke visibly around the 2nd jump. The
#     report's actual FIRST divergence was much earlier and unrelated to
#     any jump: tick 1, plain free-fall, zero input either side -- replay's
#     own diag log showed the EXACT SAME position/velocity/play_time
#     logged three ticks running ((475, -408.499969), vel (0, 45), play_
#     time 0.049997) while live continued advancing normally each tick,
#     then replay suddenly caught up to live exactly at tick 3 and tracked
#     it for a few ticks before drifting again -- and the SAME recording's
#     own live-side fingerprint read "81 phantom call(s) skipped, 81
#     tick(s) back-filled," an order of magnitude more than any earlier
#     test, meaning this specific session had real, heavy frame-timing
#     jitter (a demanding level to render is exactly what would cause
#     that). Root cause: THE FOURTEENTH-PASS FIX's Engine.time_scale pause/
#     single-step wrapper assumed every _physics_process() call it
#     receives during Play Macro means exactly one already-happened, real
#     physics tick ("this callback IS the confirmation," per that pass's
#     own comment) -- but Godot's own fixed-timestep engine loop can call
#     _physics_process() more than once in a single real frame to catch up
#     whenever that frame ran long, and time_scale (a scale on how much
#     virtual time elapses PER tick, not a "run at most one tick total"
#     throttle) can't actually gate individual ticks within a catch-up
#     burst already under way -- physics genuinely doesn't advance during
#     the zeroed-out extra calls (frozen position, matching the evidence
#     exactly), but _advance_practice_playback() still runs for each one,
#     re-processing/re-capturing ticks that never happened. Exactly the
#     same underlying native-tick/render-frame decoupling THE THIRTEENTH-
#     PASS FIX already proved and fixed for live recording's own
#     _physics_process() calls -- just never checked for on the playback
#     side, because THE FOURTEENTH-PASS FIX's single-step design was
#     believed to make it structurally impossible there. It isn't.
#       FIXED (THE TWENTY-SECOND-PASS FIX) the same proven way: playback's
#     own calls are now fingerprinted via wp_game_data.play_time too (see
#     _playback_tick_last_play_time's big comment and the check at the top
#     of _advance_practice_playback()) -- any call where play_time
#     provably hasn't moved since the last confirmed one is a complete
#     no-op (no capture, no index advance, no restore/settle/input-sync
#     logic at all), so a catch-up-burst call can never re-process or
#     duplicate a tick that never happened. The baseline resets to "none
#     yet" at the same choke point _restore_player() already resets the
#     recording-side one at, so the tick immediately after any restore
#     always re-establishes a fresh baseline instead of comparing against
#     a value play_time was just rewound away from. Divergence Diagnostics
#     reports now also print a "playback tick fingerprint" line alongside
#     the existing recording one, so a future report showing this same
#     symptom is immediately self-diagnosing instead of needing this same
#     manual trace again. Verified via a stub-project test that directly
#     drives _advance_practice_playback() through restore -> real tick ->
#     simulated catch-up-burst phantom call -> real tick, confirming the
#     phantom call is fully skipped (frame index untouched, fingerprint
#     counted correctly) and the real tick immediately after it resumes
#     exactly where the last real tick left off. Not yet checked against a
#     fresh real Divergence Diagnostics report on the same difficult level
#     -- that's the natural next test.
#       STILL NOT ENOUGH, PART 1 -- THE TWENTY-THIRD-PASS FIX (2026-08-31,
#     later the same day). The "natural next test" above came back and the
#     tick-1 frozen-duplicate symptom was STILL happening, even though the
#     SAME report's playback fingerprint line correctly caught 3 OTHER
#     phantom calls elsewhere in the run -- proving the mechanism itself
#     works, just not for this specific case. Root cause: the choke-point
#     reset in _restore_player() used the same -1.0 "no baseline yet"
#     sentinel the LIVE-recording side uses (see _live_tick_last_play_time's
#     reasoning) -- but -1.0 means "process unconditionally, nothing to
#     compare against," so a catch-up-burst call landing IMMEDIATELY after a
#     checkpoint-0/boundary restore (zero real ticks elapsed since play_time
#     was just rewound) sailed through as automatically valid instead of
#     being fingerprinted at all. Unlike live recording's restores (which
#     can happen from an asynchronous call site relative to recording's own
#     capture cadence, so no real baseline is knowable), a playback-side
#     restore ALWAYS happens inside _advance_practice_playback() itself --
#     the true next-expected baseline (whatever play_time reads right now,
#     at the end of this exact restore) is always knowable immediately.
#     Storing that real value instead of -1.0 means the very next call, even
#     one from the same burst with zero real ticks elapsed, compares against
#     a correct value and gets caught as phantom like any other. Verified
#     via a stub-project test reproducing the exact scenario (restore ->
#     phantom call with zero elapsed ticks immediately after, same tick
#     play_time was rewound to).
#       STILL NOT ENOUGH, PART 2 -- THE TWENTY-FIFTH-PASS FIX (2026-08-31,
#     later again). User report: "The replay is broken again, check the most
#     recent logs" -- three back-to-back real Play Macro attempts on the
#     same difficult-level recording, 100% reproducible, all showing the
#     exact same "+2 tick" offset starting at tick 1: replay's own tick-1
#     diag entry already carried the position/velocity/play_time live itself
#     only reaches at ITS tick 3 (e.g. vel=(0,90)/play_time=0.099997,
#     matching live's tick 3 exactly, not live's own tick 1 vel=(0,60.000004)/
#     play_time=0.066664). This was the other half of THE TWENTY-SECOND-PASS
#     FIX's own fingerprint check that never got handled: it only ever
#     branched on playback_ticks_elapsed <= 0 (phantom, skip). Any
#     ticks_elapsed >= 1 -- including a genuine 3-tick real gap, physics
#     fully simulated the whole way, not frozen -- fell through as "normal,
#     process one frame," which only ever advances _practice_playback_index
#     by exactly 1 regardless of how many real ticks actually happened.
#     That's not a one-tick blip -- it's a PERMANENT frame-index offset for
#     the rest of the replay, since every later call keeps consuming frames
#     one at a time starting from the now-wrong index, which is exactly why
#     these reports' per-field mismatch counts showed nearly every tick
#     wrong after the first divergence. FIXED: when playback_ticks_elapsed >
#     1, additionally advance _practice_playback_index by the extra
#     (ticks_elapsed - 1) BEFORE this call's own boundary lookup/capture/
#     advance -- silently treating those extra ticks as already-passed and
#     unwitnessed, mirroring (inverted) THE THIRTEENTH-PASS FIX's recording-
#     side backfill. A new _playback_tick_fingerprint_gap counter tracks how
#     often/how much this happens, reported alongside normal/phantom on the
#     "playback tick fingerprint" report line. Deliberately scoped to NOT
#     apply during an in-progress Playback Settle hold (settling never
#     spends recorded frames by design, gap or no gap -- see
#     _practice_playback_settling's own comment) -- the catch-up only ever
#     applies on a call that actually reaches the frame-consuming code path.
#     Verified via two stub-project tests: one reproducing the exact real-
#     report scenario (restore -> real tick -> simulated 3-tick real gap ->
#     confirms the index jumps by the full amount and the gap counter reads
#     2, not that the call is miscounted as phantom or plain-normal) plus a
#     regression check that a gap landing mid-settle does NOT touch the
#     index. An input change landing exactly inside a skipped gap still
#     can't be retroactively replayed at the precise right moment -- an
#     acknowledged, unavoidable limit of catching up after the fact rather
#     than never losing a tick in the first place -- but the alternative
#     (permanent drift for the rest of the run) was strictly worse. Not yet
#     checked against a fresh real Divergence Diagnostics report on the same
#     difficult level -- that's the natural next test.
#       STILL NOT ENOUGH, PART 3 -- THE TWENTY-SIXTH-PASS FIX (2026-08-31,
#     later still). The "natural next test" above came back TWICE (two
#     Play Macro attempts, same session) and both reports showed the exact
#     same tick-1 divergence, byte-for-byte identical to the pre-25th-pass
#     symptom -- even though both reports' own fingerprint lines confirmed
#     THE TWENTY-FIFTH-PASS FIX's gap catch-up fired ("2 extra tick(s)
#     caught up" / "3 extra tick(s) caught up"). That combination -- the
#     fix visibly firing, yet the exact same divergence still printing --
#     was the tell that the underlying GAMEPLAY was likely already fixed,
#     but the DIAGNOSTIC REPORT ITSELF had a separate, previously-latent
#     bug that a real gap now exposed. Root cause: `_diag_replay_log` only
#     ever got exactly one entry appended per call to
#     _advance_practice_playback() -- true before THE TWENTY-FIFTH-PASS FIX
#     and still true after it, since that pass only changed WHICH recorded
#     frame gets consumed, not how many diag entries get appended. The
#     comparison tool matches live_log[i] against replay_log[i] by raw
#     array position (see _capture_diag_entry()'s own comment: "index i in
#     this log and index i in the flattened live log stay directly
#     comparable") -- so the moment a real gap gets caught (correctly
#     advancing the index by more than 1), replay_log falls behind live_log
#     by exactly that many entries, and every comparison from that point on
#     is silently checking the wrong pair of entries against each other.
#     Live's own recording side already solved the identical problem for
#     itself back in THE THIRTEENTH-PASS FIX: it back-fills
#     `_diag_live_current` with duplicated-state entries whenever ITS OWN
#     gap is detected, keeping its diag log 1:1 with real tick count. This
#     pass mirrors that exactly on the playback side: when
#     playback_gap_ticks > 0, `_diag_replay_log` now gets one backfilled
#     entry per skipped frame BEFORE the real one, each pairing that
#     specific skipped frame's own actual recorded input (unlike live's
#     backfill, playback genuinely knows what input SHOULD have applied at
#     each skipped tick) with the one physics state actually observable --
#     this tick's, i.e. the state after the whole gap already happened,
#     since there's no way to retroactively recover what position/velocity
#     looked like partway through a gap that's already over. Verified via a
#     dedicated stub-project test (distinct inputs on frames 1/2/3 so each
#     backfilled entry's input can be checked independently) confirming the
#     log lands at the correct length with each entry carrying its own
#     frame's input paired with the shared post-gap state; a negative
#     control (reverting just this pass) reproduces an array-index crash
#     from the log coming up short, confirming the test is load-bearing.
#       Acknowledged residual limitation, same category as live's own
#     backfill: a backfilled entry can still register as a "divergence" if
#     live's real state genuinely changed during the gap window, since only
#     one (the final) state is available to stand in for all the skipped
#     ticks. That's an inherent cost of only having one real sample for
#     several ticks, not a bug this fix can close further -- but it no
#     longer throws every tick for the REST of the run out of alignment,
#     which is what the length mismatch was actually doing. Not yet checked
#     against a fresh real Divergence Diagnostics report -- that's the
#     natural next test, and this time the tick-1 entry should either match
#     cleanly or, if it still shows a mismatch, it should look like an
#     ordinary single-tick discrepancy rather than the "replay reading 2-3
#     ticks ahead of live for the entire rest of the run" shape these last
#     two reports had.
#       NATURAL NEXT TEST CAME BACK -- THE TWENTY-SIXTH-PASS FIX IS WORKING
#     AS DESIGNED, BUT ITS OWN ACKNOWLEDGED LIMITATION IS REAL AND
#     CONSEQUENTIAL (2026-09-01, user report: "there are some accuracy
#     inconsistencies that still happen," pulled and read automatically
#     per the user's own established preference). divergence_report_
#     1788214072.txt shows exactly the predicted shape: tick 0 (checkpoint
#     boundary) matches byte-for-byte on both sides, then replay's OWN
#     tick 1 reads pos=(475, -404.749969) vel=(0, 90) play_time=0.099997 --
#     which is not garbage, it's EXACTLY live's tick 3 state
#     (playback tick fingerprint line confirms "4 extra tick(s) caught up
#     across gap(s)" this run). This is THE TWENTY-FIFTH/SIXTH-PASS FIXES'
#     gap catch-up correctly detecting a real multi-tick timing gap right
#     after the checkpoint-0 restore and correctly advancing the frame
#     index by the full amount -- not a frame-index bug, not "replay ahead
#     for the entire rest of the run" the old broken shape. It IS, exactly
#     as predicted, "an ordinary single-tick discrepancy" at that one
#     boundary. That part of this fix chain is confirmed working correctly
#     on fresh real data.
#       The problem is what THE TWENTY-SIXTH-PASS FIX's own comment already
#     called out as an "acknowledged residual limitation": when several
#     real ticks happen inside one skipped gap, only the FINAL post-gap
#     state can be recovered and backfilled -- the intermediate ticks'
#     actual state is gone, unrecoverable after the fact. That one-tick
#     seed difference is enough: this platformer's physics (contact
#     resolution, friction, gravity accumulation) is sensitive to small
#     state differences, so from that single divergent tick onward nearly
#     everything downstream reads differently (per-field mismatch counts:
#     position 445/479, linear_velocity 357/479 -- effectively the entire
#     rest of the run), and it's not just numeric noise -- replay ended
#     EARLY (479 ticks vs live's 827), meaning the cascading divergence
#     changed WHEN AND WHERE the replay died relative to live. This is a
#     real, consequential "accuracy inconsistency," not a cosmetic one.
#       This is not a new bug to chase -- it's the known, already-documented
#     cost of "only one real sample survives a skipped gap," now confirmed
#     on real data rather than theorized. Actually reducing it means either
#     (a) preventing the underlying real-time gap from happening in the
#     first place, which loops back to this same item's still-untested,
#     still-pending V-Sync/stable-frame-rate experiment from the very
#     start of this item (a demanding-to-render moment is exactly what
#     produces the frame-timing jitter that creates these gaps), or (b)
#     somehow reconstructing the skipped intermediate ticks after the fact
#     -- not actually possible, since the real physics for those ticks
#     already happened and was never sampled. (a) is the only lead worth
#     pursuing; not attempted yet, since it needs the user's own play
#     conditions (V-Sync or an external frame-rate cap), not a code change
#     from this file.
#       IN-GAME FRAME RATE LIMIT ADDED (2026-09-01, user request: "you need
#     to let me limit the game to a specific framerate configurably") --
#     testing lead (a) above needed the user to cap their frame rate
#     externally, which this tool never gave them a way to do from inside
#     the game itself. Added a persisted Frame Rate Limit control to the
#     Tools tab (+/- stepping by 10, "Uncapped" at 0) that calls Godot's own
#     Engine.set_target_fps() -- the same primitive Project Settings' Max
#     FPS and external frame limiters use -- and saves/reloads across
#     restarts the same way Debug Mode already does (see
#     FPS_LIMIT_SETTINGS_PATH's own big comment, and
#     _load_fps_limit_from_disk()/_save_fps_limit_to_disk()/
#     _apply_fps_limit()/_on_fps_limit_delta_pressed()). This is a tool
#     feature, not a fix -- it doesn't change or explain anything by
#     itself, it just finally makes the standing "try a stable, capped
#     frame rate" experiment something the user can actually run without
#     leaving the game. Verified via a new stub test, RunCheck12.gd:
#     confirms the delta handler steps and clamps correctly at both ends
#     (0 = uncapped sentinel, FPS_LIMIT_MAX at the top), confirms
#     Engine.set_target_fps() is actually called to match (not just the
#     script-level variable updating), and confirms a value persists
#     across a simulated restart (a second, independent TASTool instance
#     loading from disk) for both a real cap (60) and the uncapped (0)
#     state specifically (0 round-tripping correctly, not being mistaken
#     for "nothing saved" -- the same subtlety Debug Mode's own bool
#     persistence doesn't have to worry about, since 0 is a meaningful
#     saved value here, not an empty/missing one). A negative control
#     (temporarily disabling _apply_fps_limit()'s body) reproduces the
#     exact "value updates but the engine never actually gets capped"
#     failure and fails, confirming the test is load-bearing. Full
#     regression suite (RunCheck1-12) re-runs clean together.
#       Next step is the user's own: pick a stable value (60/120/144, or
#     whatever matches their monitor) and see whether Divergence
#     Diagnostics accuracy inconsistencies -- specifically the gap-driven
#     residual just confirmed above -- get less frequent or disappear.
#  2) RESIDUAL-VELOCITY FRESH-PRESS ANOMALY -- SUPERSEDED 2026-08-31 (see
#     note at the end of this item). A 2026-08-30 divergence report
#     showed a fresh directional press landing its full acceleration one
#     tick early in replay vs. live, specifically when the player still had
#     real, decaying velocity left over from an earlier release (friction
#     hadn't yet brought it to rest). Replay's velocity delta on that tick
#     (~+21.04) closely matched live's own friction-decay delta that same
#     tick (~+4.37) PLUS the full acceleration constant (~+16.67) landing
#     on top of it -- i.e. looks like the one-tick continuous-input
#     lookahead (THE SIXTH-PASS FIX, ahead-priming a fresh press so its
#     native one-tick delivery lag lands on the right tick) is firing
#     correctly by its own logic, but the ahead-primed value plus whatever
#     the native friction/accel model does with still-nonzero opposing
#     velocity combine differently than a fresh press from a dead stop
#     does. Every other case this priming handles (checkpoints 0 velocity,
#     steady presses/releases from rest) has checked out clean, so this
#     looks like a narrower edge case in that interaction rather than the
#     priming mechanism being wrong in general. Not touched -- one
#     occurrence isn't enough to safely change priming logic that's
#     correct everywhere else it's been tested. Worth a look the next time
#     a report shows a fresh press occurring while velocity is still
#     nonzero and opposite in sign to the new input.
#       SUPERSEDED (2026-08-31): this whole item was about an edge case in
#     the direct-native-setter one-tick continuous-input lookahead (THE
#     SIXTH-PASS FIX's ahead-priming). THE FIFTEENTH-PASS FIX removed that
#     entire native-setter/lookahead mechanism in favor of synthetic Input
#     events via _inject_action(), which take effect on Input's tracked
#     state synchronously and have no native delivery lag to prime around
#     in the first place -- so there's no more "ahead-primed value" for
#     this anomaly to be about. Left above verbatim as investigation
#     history; a comparable magnitude anomaly under the new mechanism would
#     need a fresh root-cause look, since the mechanism this was diagnosed
#     against no longer exists.
#
#  3) AIRBORNE PRESS/RELEASE TIMING -- SUPERSEDED 2026-08-31 (see note at the
#     end of this item; WAS "release-to-neutral, possibly one tick late"
#     before its 2026-08-30 revision). THE TENTH-PASS FIX originally found
#     that a fresh PRESS while airborne needed to be sent on-time rather than
#     ahead -- concluded as "no native delivery lag while airborne, unlike
#     grounded." A SECOND 2026-08-30 report then caught a fresh airborne
#     PRESS -- clean, isolated, no dash or checkpoint boundary nearby, same
#     ground_timer==0 the whole window as the original case -- landing ONE
#     TICK LATE under that exact on-time/defer rule, i.e. the same failure
#     the rule was supposed to have already fixed. Identical measured
#     ground state, opposite outcome, so "grounded vs. airborne" alone can't
#     be the real split. The one concrete difference available: this new
#     press landed mid-ascent with ACTION_JUMP still actively held (19 ticks
#     into a 22-tick jump hold), while the ORIGINAL deferred-fix case was
#     described as plain freefall, "no ground contact since well before this
#     checkpoint even started" -- no live jump at all. THE TWELFTH-PASS FIX
#     (see the now-removed _apply_practice_playback_movement_input()'s big
#     comment, kept in version history) acted on that: an upcoming frame
#     that holds jump now gets the same ahead-of-time
#     treatment as grounded; only a frame that's both airborne AND not
#     jumping still gets deferred. Unlike grounded state (which has to be
#     approximated from the CURRENT tick, per that function's own "Known
#     limitation" note), whether the NEXT frame holds jump is exactly known
#     right now, since this is a prerecorded macro -- no approximation
#     needed there.
#       Still not independently confirmed: the original case's own jump-held
#     state is a description from memory (that raw report is gone), not a
#     re-checked log, so this is the best-fit theory across two data points,
#     not a certainty. Also unresolved and not chased further: the new
#     report's replay-vs-live velocity, once shifted onto the same tick,
#     still differed by a small, roughly constant ~0.055/tick offset even
#     where the gross one-tick timing matched up -- possibly the same kind of
#     narrow accel/friction interaction flagged in item 2 above, not touched
#     here since the tick-level shift was the dominant, unambiguous problem.
#     The still-open, never-independently-confirmed question from before
#     this revision -- whether an airborne RELEASE (not a press) has its own
#     one-tick-early problem -- is untouched by this fix (releases are
#     unconditional, on-time, unaffected by the jump-held check) and still
#     needs a clean, isolated example (a release by itself, not immediately
#     followed by a reversal) to look at again.
#       SUPERSEDED (2026-08-31): a fresh divergence report gave a THIRD
#     airborne-fresh-press case -- fresh non-jumping LEFT press, ground_timer
#     0 the whole window, no dash/boundary nearby -- and it landed ONE TICK
#     LATE yet again, the exact same failure this item's "defer only when
#     truly airborne AND not jumping" rule was supposed to have already
#     fixed. Two out of three attempts at explaining this same class of
#     failure (grounded-vs-airborne, then airborne-vs-jump-held) each held up
#     against their own confirming data point only to fail again on the very
#     next one -- strong evidence the real problem was never which heuristic
#     branch to pick, but the underlying one-tick native delivery lag itself
#     (see THE ONE-TICK LOOKAHEAD's own comment, now removed) being
#     fundamentally unpredictable enough that no branching rule on top of it
#     was ever going to be reliable. THE FIFTEENTH-PASS FIX removes the
#     native-setter path (and every heuristic built on top of it, this item
#     included) entirely, replacing it with synthetic Input events via
#     _inject_action() that have no such lag to branch around. Left above
#     verbatim as investigation history.
#
#  4) DEATH-VELOCITY QUESTION (2026-08-30, user report: "flew a bit left or
#     right" after respawning at a checkpoint post-death) -- checked
#     against the decompiled source rather than guessed at. WPGame.gd's
#     real respawn_player() unconditionally zeroes BOTH player.
#     linear_velocity and player.body.linear_velocity (along with
#     repositioning, re-enabling, and clearing dash/coyote/stun/etc.) every
#     time it runs -- confirmed verbatim, not an oversight in the native
#     respawn path itself. kill_player() (also confirmed verbatim), on the
#     other hand, does NOT touch velocity at all when a player dies -- it
#     only flips alive=false and arms dead_counter -- so whatever velocity
#     the player had at the moment of death stays exactly as-is for the
#     ENTIRE death hold, until respawn_player() finally clears it at the
#     end. If this is happening during plain, non-macro play, the two
#     likeliest explanations are (a) that's just the death hold's own
#     animation/ragdoll reacting to genuine leftover impact velocity before
#     the real reset happens -- cosmetic, not a position bug, since
#     respawn_player() still zeroes everything for real once it fires -- or
#     (b) whatever hazard-specific code a spike runs before calling
#     kill_player() (native/compiled, not in the decompiled scripts) adds
#     its own knockback impulse that (a) would also explain. If it's
#     specifically happening THROUGH Macro Bot Mode's Auto-Respawn, it's
#     most likely not a bug at all: Auto-Respawn intentionally reproduces
#     the checkpoint's own saved velocity exactly, so a checkpoint that
#     wasn't captured at a dead stop will legitimately carry that same
#     motion into every respawn -- that's correct behavior, not leftover
#     death velocity leaking through. ANSWERED (2026-08-30): the user
#     confirmed this happens in plain, non-macro play ("this 100% happens
#     with the positioning"), which rules out the Auto-Respawn explanation
#     just above -- Auto-Respawn was never involved. Left as a genuinely open
#     native-engine question: both respawn_player()'s explicit zeroing and
#     _reset_object()'s before/after equality (see the Restore Drift report)
#     were checked and ruled out as the leak point, and dead_counter/hazard-
#     collision code is compiled and invisible from the decompiled scripts,
#     so there's no further native-source lead to chase from here without a
#     live repro.
#       2026-08-31 theory revisited, still no live repro: user reported dying
#     on a jump, respawning at the start, and having their very next jump
#     "broken," theorizing leftover death momentum survived the respawn. The
#     divergence/restore-drift reports sent alongside that report don't show
#     it: checkpoint 0's own restored velocity was a small, ordinary-looking
#     (0, 45) (Restore Drift report, restore 0/6 -- ~consistent with the
#     checkpoint having simply been placed while gently falling, not with a
#     leftover "broken" value), dead_counter reads 0 throughout every tick in
#     the divergence report's shown window, and the run's actual first
#     divergence (see item 7 below) is a separate, already-characterized
#     replay-timing issue on a fresh RIGHT press, not a jump, and not
#     anywhere near a death/respawn transition. So this specific batch
#     neither confirms nor rules out the theory -- it simply doesn't happen
#     to contain a captured death-to-respawn moment to check it against
#     (Divergence/Restore Drift reports only show state AROUND the first
#     divergence and around Play-Macro-driven restores respectively; a
#     mid-recording native death+respawn that stays perfectly in sync
#     wouldn't show up as a divergence at all, live or replay). Still needs a
#     live repro that actually captures dead_counter transitioning
#     0 -> nonzero -> 0 within a compared window to check directly.
#       ANSWERED FOR REAL (2026-08-31) -- the user restated this same
#     complaint again ("I have been constantly saying that u get launched
#     in one direction after respawning when you die and still have
#     momentum") and asked for the actual cause, not another theory. This
#     time confirmed directly from the real game's own decompiled GDScript
#     source (a GDRE export of the shipped .pck, scripts/WPGame.gd -- this
#     one lives in ordinary project-level GDScript, not compiled into the
#     engine binary like WPPlayer/WPGame's native fields, so it can be read
#     verbatim instead of reverse-engineered): kill_player() is
#         player.alive = false
#         player.dead_counter = wp_game_data.player_respawn_ticks
#         player.dash_timer = 0
#     and that's genuinely everything it does to the player besides stat-
#     tracking -- no velocity change, no body_enabled/body.enabled = false,
#     nothing. respawn_player() is what finally does all of that -- position,
#     BOTH velocity fields zeroed, dash/coyote/squish/wallslide/stun/one-way
#     all cleared, _reset_object() called -- but only once, at the END of
#     dead_counter's hold. In between those two calls, the physics body is
#     never disabled and its velocity is never touched: it keeps being
#     fully Box2D-simulated, under gravity and whatever velocity it had at
#     the instant of death, for the entire respawn hold -- a corpse that
#     was moving when it died keeps right on sliding/falling/flying in
#     that exact direction, in full view, until respawn_player() finally
#     teleports it back and zeroes everything at once. That IS "getting
#     launched in one direction with your leftover momentum" -- not a
#     glitch reading momentum wrong, but the real game genuinely never
#     stopping the body in the first place. Confirmed as the real game's
#     own design/oversight (Winterpixel's code, not this mod's), present in
#     plain non-macro play exactly as the user already reported, and
#     unrelated to Macro Bot Mode/Auto-Respawn (which was already ruled out
#     above) -- TASTool.gd has no hook into the base game's own kill_player()/
#     respawn_player() cycle during ordinary play, so there's nothing this
#     file is doing to cause or fix this as-is. NOT implemented without
#     asking first: a small opt-in QoL addition IS possible -- watch for
#     player.alive flipping true->false (the same edge Macro Bot Mode
#     already watches for its own death handling) and zero
#     player.linear_velocity/player.body.linear_velocity right then,
#     freezing the corpse in place instead of letting it coast -- but
#     that's a genuine gameplay behavior change (and one that would need to
#     stay OUT of Macro Bot Mode's own recording/replay path specifically,
#     since a recording has to faithfully capture what the real game
#     actually did, coasting corpse included, or Play Macro would no longer
#     be reproducing real runs). Left unimplemented pending the user
#     actually wanting that toggle, rather than assumed.
#       FIGHT AGAINST IT AFTER ALL -- THE TWENTY-FOURTH-PASS FIX (2026-08-31,
#     later) -- the user's response to the mechanism above: "we need to
#     fight against it, because it's making replays inaccurate." Re-scoped
#     from the opt-in-QoL framing just above: this is now implemented
#     INSIDE Macro Bot Mode's own active-recording tick specifically
#     (_physics_process(), gated the same as everything else there on
#     _practice_active), not as a separate always-on toggle -- every tick
#     the local player reads not alive, its linear_velocity and
#     player.body.linear_velocity are forced to zero, re-applied every
#     tick death holds (not just the instant it's detected), so gravity
#     can't re-accelerate the corpse from rest either -- it stays pinned
#     exactly where it died for the entire hold. This doesn't change what
#     recording actually captures (frames were already skipped entirely
#     while not alive, unchanged) -- the real value is removing a genuine
#     accuracy RISK: real, uncontrolled, contact-sensitive Box2D physics
#     for however many ticks the hold lasts is exactly the kind of thing
#     this file has no way to verify or reproduce tick-for-tick, and a
#     coasting corpse could land somewhere checkpoint-to-checkpoint state
#     doesn't expect, or make the exact tick `player.alive` flips back true
#     depend on wherever momentum happened to carry it rather than a clean,
#     fixed timer. Freezing it removes that variable at the source instead
#     of trying to model or reproduce it. Deliberately still scoped to
#     Macro Bot Mode's own recording tick, not vanilla play with the tool
#     merely enabled -- extending this (or the separate, still-unimplemented
#     idea of letting Play Macro itself survive an IN-MACRO death via the
#     same freeze-then-restore instead of aborting outright) is a bigger,
#     separate ask this session hasn't been given yet.
#       SCOPE WAS TOO NARROW -- THE THIRTIETH-PASS FIX (2026-08-31, much
#     later, user report: "the 0 velocity feature you added doesnt always
#     work I realized. Unless I'm understanding it wrong") -- correct
#     understanding, real bug: THE TWENTY-FOURTH-PASS FIX's freeze block
#     lived in _physics_process() AFTER the `if not _practice_active:
#     return` guard, and _practice_playback's own early branch returns even
#     earlier than that -- so the freeze only ever ran while Macro Bot Mode
#     was actively RECORDING. It did nothing during plain play with the
#     tool merely enabled (no recording in progress), and nothing once a
#     Play Macro attempt aborts on an in-macro death, exactly matching the
#     user's "doesn't always work." FIXED by moving the freeze up to run
#     unconditionally near the top of _physics_process() (right after
#     _apply_noclip_movement(), before any of the practice-mode gating),
#     guarded only by `not _noclip_enabled` (freezing a noclipping player
#     who is also mid-death is a contradiction that shouldn't happen, but
#     the guard costs nothing) -- so it now runs on every death regardless
#     of whether Macro Bot Mode is recording, replaying, or just sitting
#     enabled. Still, deliberately, does not touch what a recording
#     actually captures (frames while not alive are still skipped
#     entirely, unchanged) and still does not make Play Macro survive an
#     in-macro death (that remains the separate, unrequested idea noted
#     above) -- it only ever stops the corpse from visibly coasting.
#       ONE TICK STILL LEAKED THROUGH -- THE THIRTY-FIRST-PASS FIX
#     (2026-08-31, later still, user report: "after dying I still sometimes
#     get momentum and get thrown back into a spike from the momentum i had
#     after dying") -- THE THIRTIETH-PASS FIX's freeze runs every tick the
#     player already reads not-alive, but Godot calls _physics_process() on
#     every node BEFORE the physics server steps that same frame -- so on
#     the exact tick a spike kills the player, this function's own freeze
#     check still saw alive==true (kill_player() hasn't run yet), and only
#     after this function returns does the physics server integrate that
#     tick's motion at the pre-death velocity, resolve the collision, AND
#     call kill_player(), all before the NEXT call ever sees alive=false.
#     That's one full, un-frozen tick of Box2D-simulated travel at whatever
#     speed the player died at -- ordinarily too small to matter, but
#     exactly enough to carry a fast-moving corpse into a second, adjacent
#     hazard in a tight spike field, matching "sometimes" (only when
#     something else is close enough to reach in one tick) rather than
#     every death. FIXED by tracking the player's own position on every
#     tick they're still alive (_freeze_last_alive_position, updated
#     unconditionally while alive) and, on the alive->dead EDGE specifically
#     (detected via a new, freeze-block-local _freeze_prev_alive, kept
#     separate from the pre-existing _practice_prev_alive since that one
#     only runs while _practice_active), snapping player.position back to
#     that bookmark for that one tick only -- undoing the already-applied
#     displacement on top of the existing velocity zero. Does NOT also
#     write player.body.position, same TELEPORT ACCURACY reasoning as
#     _restore_player() (body is a child node at local (0,0); writing a
#     world-space position into it stacks a second offset instead of
#     correcting one). Does NOT keep re-snapping on later dead ticks --
#     only the first one -- so it can't fight a legitimate later
#     reposition (e.g. Macro Bot Mode's own Auto-Respawn checkpoint
#     restore).
#       VELOCITY ALONE WAS NEVER GOING TO BE ENOUGH -- THE THIRTY-SECOND-
#     PASS FIX (2026-08-31, later still, user report: still "bugged" after
#     THE THIRTY-FIRST-PASS FIX, plus "the 0 velocity thing still doesnt
#     fully work") -- two velocity-only passes in a row still weren't
#     enough on real hardware, which is the tell that the residual isn't
#     (only) a velocity problem. Box2D resolves a body's geometric overlap
#     with whatever it's touching via its own CONTACT/PENETRATION
#     correction step -- a direct position adjustment, done independent of
#     velocity entirely. Zeroing linear_velocity every tick, however
#     reliably, does nothing to stop that if the corpse is still embedded
#     in (or lands freshly inside) a hazard's collision shape when the
#     physics server resolves contacts -- which is exactly what a spike
#     hazard's own kill geometry usually looks like. This is a different,
#     more fundamental gap than THE THIRTY-FIRST-PASS FIX's one-tick
#     ordering issue, and explains why fixing that one-tick lag alone
#     wasn't sufficient, and why "the 0 velocity thing" could look like it
#     "still doesn't fully work" even though the velocity itself genuinely
#     was zero the whole time -- position was still moving out from under
#     it.
#       FIXED by no longer relying on velocity at all: on the alive->dead
#     edge, the freeze now also disables the physics body outright
#     (player.body_enabled AND player.body.enabled = false, the same two
#     flags _restore_player() already keeps in sync with each other, and
#     the exact same pattern _on_toggle_noclip_pressed() already uses
#     elsewhere in this file to take manual control of the body) --
#     stopping Box2D from simulating or resolving contacts against the
#     corpse at all, not just zeroing the one field velocity happens to
#     live in. Re-enabled (both flags, plus a _reset_object() call --
#     mirroring noclip's own re-enable path exactly, since that's the only
#     other place in this file that already flips this same pair of flags
#     off and back on) the moment the player is observed alive again. This
#     is a deliberate deviation from the real game's own kill_player(),
#     which per this item's own earlier finding never touches either flag
#     during a death -- same category of intentional divergence the
#     velocity freeze itself already was, just a stronger version of it,
#     because the velocity-only version shipped twice and still wasn't
#     enough.
#       Verified in the stub project that TASTool.gd itself now sets and
#     clears the right flags at the right ticks, including re-disabling if
#     something else flips the body back on mid-hold and correctly leaving
#     it enabled during ordinary alive play. NOT verified, and can't be, in
#     this stub: the actual physical claim that disabling a Box2D body
#     stops its contact-resolution position correction. That's standard,
#     documented Box2D/Godot behavior, not something this project's dumb
#     stub bodies (plain fields, no physics) can exercise -- this fix rests
#     on that being true in the real engine, same as any fix in this file
#     that touches native physics behavior the stub can't reproduce.
#       ENOUGH GUESSING -- THE THIRTY-THIRD-PASS FIX (2026-08-31, later
#     still, user report: still "bugged," "the velocity thing remains") --
#     three real-hardware misses in a row on the same symptom, each an
#     individually well-reasoned fix that still passed every stub test.
#     That combination means the responsible move is to stop guessing a
#     fourth time and get real evidence instead -- this file's whole
#     methodology elsewhere is diagnose-from-evidence, and this bug is the
#     one place it hasn't been followed that way. NOT a fifth fix attempt:
#     added Death Freeze Diagnostics, an always-on (no toggle to remember)
#     capture around every death, auto-saved to user://tas_diagnostics/
#     death_freeze_report_<timestamp>.txt the moment each window closes,
#     same folder every other diagnostics report already lands in. Placed
#     to answer the two questions that would explain all three prior
#     misses at once: (1) is the freeze even running at all -- checked
#     from a call placed AHEAD of _physics_process()'s own enabled/
#     _tool_restricted() gate, so it can catch and flag the freeze being
#     gated off entirely (tool disabled, or outside Time Trial mode) as a
#     possibility neither of the first three passes could have ruled out;
#     (2) if it IS running, which specific guarantee is actually failing --
#     velocity nonzero, body_enabled/body.enabled still true, or position
#     still moving tick to tick -- each flagged explicitly per tick, or a
#     clean "no anomalies" if none of those hold (in which case whatever's
#     still happening isn't something this per-physics-tick capture can
#     see at all -- see the report's own closing note on rendering/
#     interpolation and other-object collision as the remaining
#     possibilities that would point to).
#       Caught a real bug in its own first draft before shipping: the
#     initial version captured state from the SAME call site the gating
#     check itself needed to run from (ahead of the freeze block), which
#     meant it always recorded the RAW pre-freeze state on a death's very
#     first tick, before the freeze code later in the same function tick
#     had a chance to correct it -- a false "anomaly" on every single
#     death's tick 0, working freeze or not. Fixed by splitting the
#     capture into two call sites: one ahead of the gate (edge-detection,
#     and the tick's own capture ONLY on a tick the freeze won't run at
#     all) and one placed right after the freeze block finishes (captures
#     the corrected state for every tick the freeze actually ran) --
#     verified via a dedicated stub test plus a negative control that
#     confirms the anomaly flag fires correctly when the freeze is broken
#     on purpose, and stays clean when it isn't.
#       NEXT STEP: reproduce the death once for real and send the newest
#     death_freeze_report_*.txt from tas_diagnostics. Whatever it shows
#     becomes the next fix's actual starting point instead of another
#     theory.
#       IT WORKED -- REAL EVIDENCE FOUND A REAL, DIFFERENT RESIDUAL --
#     THE THIRTY-FOURTH-PASS FIX (2026-08-31, later still) -- the user
#     reproduced several deaths; 7 of 8 captured Death Freeze Diagnostics
#     reports showed zero anomalies (freeze holding perfectly, confirming
#     THE THIRTIETH/THIRTY-FIRST/THIRTY-SECOND-PASS FIXES ARE working most
#     of the time), but one real report (a death during active Macro Bot
#     Mode recording) showed position moving 3.39 units on the SECOND dead
#     tick -- one tick AFTER THE THIRTY-FIRST-PASS FIX's snap-back, THE
#     THIRTY-SECOND-PASS FIX's body-disable, and the velocity zero had all
#     already applied that same first tick. Velocity read exactly (0, 0)
#     the whole time and body_enabled/body.enabled both already read false
#     the whole time too -- so whatever moved position on that second tick
#     isn't velocity-driven, and isn't (as far as this file's own state can
#     show) a body that's still being simulated. The exact native
#     mechanism remains unidentified -- this file isn't guessing a specific
#     cause this time, unlike the last three passes -- but the SYMPTOM is
#     now directly, reproducibly evidenced, not theorized: the snap-back
#     doesn't hold reliably after only firing once.
#       FIXED pragmatically rather than by chasing the exact mechanism
#     further: THE THIRTY-FIRST-PASS FIX's position snap-back now
#     reasserts _freeze_last_alive_position every dead tick, exactly like
#     the velocity zero and body-disable already do, instead of only on
#     the first tick after the alive->dead edge. Confirmed safe against
#     Auto-Respawn/native respawn specifically because both write position
#     AND flip alive to true in the SAME call (_restore_player() and
#     respawn_player() per this item's own earlier finding) -- by the time
#     this freeze block would next see the player as still not-alive and
#     try to reassert, a real respawn has already made alive read true, so
#     the reassertion branch simply doesn't run that tick at all. This is
#     also why the fix is safe to ship as "just do it every tick" without
#     first nailing the precise mechanism: nothing legitimate ever
#     repositions the corpse while it's still genuinely dead, so there's
#     no real case left for the every-tick reassertion to fight.
#       Verified in the stub project: RunCheck6 (previously verifying only
#     the first-tick snap-back) now also drives a second dead tick with a
#     simulated small unexplained drift, matching the real report's shape,
#     and confirms the freeze corrects it there too, plus a regression
#     check that a real respawn's own reposition (arriving together with
#     alive=true) is never fought. A negative control (reverting to the
#     old first-tick-only behavior) reproduces the exact real-report
#     failure shape and fails, confirming the test is load-bearing.
#       STILL NOT independently real-game-verified beyond the evidence
#     that motivated it -- next test should include another real death
#     during Macro Bot Mode recording (the exact scenario the anomaly
#     report came from) to confirm the drift is actually gone now, not
#     just corrected in the specific way this file could model it.
#       STILL NOT ENOUGH -- THE THIRTY-FIFTH-PASS FIX (2026-08-31, later
#     still, user report: "done, the velocity bug still exists. what else
#     can we do? Can we just change the part of the code where it doesnt
#     stop the goober to stop it?") -- more real Death Freeze Diagnostics
#     evidence, collected proactively from the user's own tas_diagnostics
#     folder after THE THIRTY-FOURTH-PASS FIX shipped: three fresh reports
#     (1788211225, 1788211227, 1788211253) still showed position jumping
#     ONCE -- 13.26, 11.58, and 15.25 units respectively, all three purely
#     vertical (X essentially unchanged) and all LARGER than the 3.39-unit
#     jump that motivated THE THIRTY-FOURTH-PASS FIX -- on the tick right
#     after death, then LOCKING EXACTLY at that new (wrong) position for
#     the rest of the hold (verified through tick 25+ in one excerpt).
#     This is a strictly harder case than before: THE THIRTY-FOURTH-PASS
#     FIX's every-tick, unconditional position reassertion was ALREADY in
#     effect and still lost this race exactly once per death, before
#     somehow holding perfectly after. A value reasserted unconditionally
#     every tick cannot visibly drift once and then hold at a new value
#     unless something downstream of this script -- later the same tick,
#     or during the physics step that runs immediately after this function
#     returns -- overwrites the write, for roughly one tick after the body
#     is disabled, before that downstream mechanism itself stabilizes. The
#     leading theory (this file's established custom-Box2D-fork ordering:
#     _physics_process() runs BEFORE the physics server steps each frame)
#     is a native sync of the body's own already-in-flight simulated
#     transform back onto player.position, lagging slightly behind
#     body.enabled actually taking hold -- offered as the best-supported
#     explanation the evidence allows, not a decompiled certainty.
#       FIXED by taking the user's own suggestion directly: rather than
#     keep reasserting a script-level property that's apparently still
#     losing a race against native state, the freeze now calls
#     _reset_object() on the alive->dead edge -- the exact native call this
#     file already relies on elsewhere (_restore_player(), and this same
#     freeze's own respawn-edge re-enable) specifically to force a clean,
#     fully-flushed physics state after a script-driven teleport, rather
#     than trusting property writes alone to fully propagate.
#       CAUGHT DURING VERIFICATION: the first version of the edge check
#     (`if not _freeze_prev_alive:`) was backwards -- since _freeze_prev_
#     alive holds the PREVIOUS tick's alive state, the death EDGE (alive ->
#     dead) is the tick where _freeze_prev_alive is still true, not false.
#     The inverted check would have called _reset_object() on every dead
#     tick EXCEPT the first -- the opposite of the intended once-per-death
#     edge call. A dedicated test (RunCheck9.gd, using a test-only tracked-
#     player subclass to count actual _reset_object() calls) caught this
#     immediately before delivery: 0 calls where 1 was expected on the
#     first dead tick, climbing by 1 every later dead tick instead. Fixed
#     to `if _freeze_prev_alive:`, reconfirmed against a negative control
#     (temporarily restoring the inverted check reproduces the identical
#     failure), then reconfirmed clean against the full RunCheck1-9
#     regression suite together.
#       STILL NOT independently real-game-verified beyond the evidence
#     that motivated it, same caveat as THE THIRTY-FOURTH-PASS FIX above --
#     next test should include another real death showing this specific
#     lock-after-one-jump shape, to confirm _reset_object() actually closes
#     it rather than just changing its timing or magnitude. Death Freeze
#     Diagnostics remains in place either way, so the next report will show
#     directly whether this residual is gone.
#       REVERTED -- THE THIRTY-FIFTH-PASS FIX WAS WRONG, MADE THINGS WORSE
#     (2026-08-31, later still, user report: "First jump broke this time,
#     the velocity bug remains") -- calling _reset_object() on the death
#     edge did NOT close the position-lock residual (the velocity/momentum
#     bug this whole chain exists to fix was still present), and it
#     introduced a new, worse regression: the player's first jump after
#     respawning stopped working. _reset_object() is opaque/native with no
#     decompiled source -- the leading theory is that it clears some
#     jump-related internal state (buffered input, ground-contact/coyote-
#     time tracking, a jump counter) that the respawn path doesn't expect
#     to already be touched. Every OTHER call site for it in this file is
#     paired with that SAME tick's own full reinitialization (a real
#     teleport, or this freeze's own respawn-edge re-enable, which runs
#     right as alive flips back to true) -- calling it on the death edge
#     instead has no such pairing, so whatever it clears stayed cleared
#     until the player's next real action, which turned out to be their
#     first post-respawn jump. This is a theory, not a decompiled
#     certainty, same as the fix it's reverting -- but a change that
#     regresses a working mechanic while not fixing the bug it targeted
#     has no case for staying regardless of the exact mechanism, so it was
#     reverted rather than chased further.
#       Reverted cleanly back to THE THIRTY-FOURTH-PASS FIX's every-tick
#     position/velocity/body-disable reassertion (unchanged, confirmed
#     still in place and still passing its own tests). RunCheck9.gd
#     (written specifically to verify THE THIRTY-FIFTH-PASS FIX's call
#     count) is retired/no longer expected to pass as originally written,
#     since the behavior it checked for on the death edge no longer
#     exists by design -- see TASTool_TICK_ACCURACY_PLAN.md for the
#     verification status of this revert.
#       STILL UNRESOLVED: the original position-lock residual (item 4's
#     THE THIRTY-FOURTH/FIFTH-PASS evidence) is still real and still
#     unexplained. Next step goes back to evidence, not another native-
#     call guess: reproduce a death showing the same lock-after-one-jump
#     shape (or the "velocity bug" the user is still describing, which
#     may or may not be literally the same residual as the position-lock
#     one -- worth clarifying directly with the user what "velocity bug"
#     looks like from their side now, since several different symptoms
#     have shared that name across this session) with Death Freeze
#     Diagnostics active, and let that report drive the next actual fix.
#       PROACTIVE EVIDENCE PULL + NEW INSTRUMENT -- THE THIRTY-SIXTH-PASS
#     FIX (2026-08-31, later still). Per the user's own request ("I kinda
#     wanted you to just take the diagnostics for everything i say
#     automatically, since those have always been available to you"), this
#     file's own maintainer now pulls tas_diagnostics directly off the
#     user's machine the moment a bug is reported, rather than asking first.
#     Doing exactly that here: pulled and checked all 34 death_freeze_
#     report_*.txt files across the two sessions since THE THIRTY-FOURTH-
#     PASS FIX shipped (including the session where jump broke) -- EVERY
#     SINGLE ONE flags zero anomalies. Velocity, body_enabled, and position
#     have now held perfectly clean across 34 straight deaths.
#       That's the real finding: the logical freeze this file controls
#     (player.position/linear_velocity/body_enabled) is not what's still
#     producing "the velocity bug." This file's own diagnostic report has
#     said as much all along, in its own NOTE line: "It cannot see
#     rendering/interpolation... a visual smoothing effect between physics
#     ticks could look like drift even if the underlying physics state
#     above is perfectly static." Every prior death_freeze_report only ever
#     captured p.position -- a script property THIS FILE ITSELF writes
#     every dead tick. Reading it back clean proves nothing about whether
#     the physics BODY's own rendered transform (what the player actually
#     SEES) ever tracked that write, especially given body_enabled/
#     body.enabled = false stops further simulation but was never confirmed
#     to force the body's own transform to immediately snap to match.
#       The user's own proposed alternative here -- "instead of trying to
#     keep the velocity at 0 which clearly doesn't work, we try to just
#     keep the player at the specific checkpoint spot for a time that's
#     barely noticeable, but enough to stop the momentum" -- is, at the
#     LOGICAL level, already exactly what THE THIRTY-FOURTH-PASS FIX does:
#     player.position is hard-pinned to _freeze_last_alive_position every
#     single dead tick, not just velocity zeroed, for the whole hold. If
#     that's still not what's visually happening, the gap isn't in the
#     logic being reasserted, it's in whether that reassertion actually
#     reaches the rendered body -- which is exactly the render/interpolation
#     possibility this file's own diagnostics have flagged as unmeasured
#     from the very first Death Freeze Diagnostics report onward.
#       Rather than guess at a sixth fix (this file has now shipped and
#     reverted one native-call guess already), instrumented the gap
#     instead: _death_diag_record_tick() now also captures
#     body.global_position every dead tick (previously only body.
#     linear_velocity was ever captured, never the body's own position),
#     and _build_death_freeze_report_text() now flags "BODY TRANSFORM
#     DIVERGED FROM FROZEN POSITION" whenever body.global_position and the
#     frozen player.position disagree by more than 0.5 units on a tick the
#     freeze should be holding. If the physics body's own rendered
#     transform is quietly disagreeing with the position this file thinks
#     it's enforcing, the NEXT report will show it directly, by name,
#     instead of this file having to infer it from "diagnostics say clean
#     but the player still saw movement" a sixth time.
#       Verified in the stub project with a new test, RunCheck10.gd:
#     confirms a normal hold (body's local transform never moves) produces
#     no divergence flag and a clean report, and confirms a deliberately
#     injected divergence (the body's own local transform displaced by
#     (5,5) while player.position is held perfectly frozen by the freeze
#     the whole time) IS flagged, with a negative control (temporarily
#     disabling the new check) reproducing the missed-detection failure and
#     failing, confirming the test is load-bearing. Full regression suite
#     (RunCheck1-10) re-runs clean.
#       NOT a fix -- exactly like THE THIRTY-THIRD-PASS FIX before it, this
#     is instrumentation, offered honestly as such. Next step: the user
#     reproduces the bug once more (jump breaking was specific to THE
#     THIRTY-FIFTH-PASS FIX and should not recur now that it's reverted,
#     but the underlying "velocity bug" perception should still be
#     checked), and whichever tas_diagnostics files land afterward get
#     pulled and read automatically, per the user's own stated preference,
#     rather than waited on.
#       BOTH THE ANSWER AND A REAL FIX -- THE THIRTY-SEVENTH-PASS FIX
#     (2026-09-01). The user reproduced again and, asked directly what
#     "the velocity bug" now looks like, gave the answer this file had been
#     missing all session: "it's not that the velocity stays, its more
#     like it comes back maybe to it. So as soon as they respawn they get
#     the velocity for whatever reason." That single sentence reframes
#     everything -- this was never about the corpse continuing to drift
#     WHILE dead (which 34+ straight clean reports already ruled out), it's
#     about velocity reappearing the INSTANT they respawn.
#       Diagnostics pulled automatically off the user's machine (per their
#     own stated preference from earlier this session) confirmed it
#     immediately: death_freeze_report_1788213583.txt shows a player
#     frozen (velocity exactly zero, body disabled) for 60 straight ticks,
#     then on the very first tick alive reads true again --
#     `vel=(9.374881, -0)`, NOT zero -- decaying over the next several
#     ticks (80.46 -> 71.01 -> 62.67 -> 55.30) the way residual momentum
#     decays under drag, not the way a fresh keypress ramps up.
#       ROOT CAUSE: this freeze's respawn-edge branch (the `if not
#     _freeze_prev_alive:` block that re-enables body_enabled/body.enabled
#     and calls _reset_object() -- see THE THIRTIETH-PASS FIX's own comment
#     just above) never zeroed velocity again AFTER re-enabling the body.
#     The leading theory: this file's own every-tick `linear_velocity =
#     Vector2.ZERO` writes while dead (the else branch below) may not
#     actually reach the physics body's own INTERNAL simulated velocity
#     state while body_enabled/body.enabled are false -- a disabled/
#     inactive Box2D body is commonly excluded from the simulation
#     entirely, and a property write made while inactive can be silently
#     dropped, or simply not applied to the underlying simulated state,
#     until the body re-enters the world. If that's what's happening,
#     every read of velocity while dead this whole session (always
#     reporting 0) reflected what this file itself last WROTE, not
#     necessarily the body's own live internal state -- and the real,
#     pre-death velocity stayed cached inside it the entire hold, invisible
#     to every diagnostic this file has, resurfacing the instant
#     body_enabled/body.enabled flip back to true.
#       FIXED by explicitly zeroing both freeze_player.linear_velocity and
#     freeze_player.body.linear_velocity again, immediately after
#     re-enabling the body and calling _reset_object(), on the respawn edge
#     itself -- so even if whatever stale internal state resurfaces there
#     is nonzero, this write is the last word before the player regains
#     control that same tick. This is additive and low-risk, unlike THE
#     THIRTY-FIFTH-PASS FIX's reverted native-call change: it doesn't touch
#     _reset_object() itself or its ordering, it just makes sure velocity
#     is zero on BOTH sides of that call now, not just the dead-hold side.
#       Verified in the stub project with a new test, RunCheck11.gd, that
#     deliberately re-injects the original death velocity into
#     body.linear_velocity/player.linear_velocity right before the respawn
#     edge (simulating the exact "stale internal state" failure mode
#     theorized above) and confirms the fix zeroes it again on that same
#     tick; a negative control (temporarily removing the new zero-write)
#     reproduces the exact real-report failure shape (velocity reads back
#     nonzero on respawn) and fails, confirming the test is load-bearing.
#     Also caught and fixed a pre-existing test gap while verifying this:
#     RunCheck5.gd's "an alive player's velocity must not be touched"
#     check was, without realizing it, asserting the OPPOSITE of this new
#     fix's intent on the respawn edge itself (it transitioned dead->alive
#     with a nonzero velocity and expected it preserved) -- updated to
#     cross the respawn edge on its own tick first, then assert velocity
#     is preserved only once genuinely past it. Full regression suite
#     (RunCheck1-11) re-runs clean together.
#       STILL NOT independently real-game-verified beyond the evidence
#     that motivated it, same standing caveat as every pass in this chain
#     -- next step is the user reproducing once more; whatever lands in
#     tas_diagnostics gets pulled automatically, as established.
#       THE THIRTY-EIGHTH-PASS FIX (2026-09-01, later still, user report:
#     "The velocity bug is back and the macro is still inconsistent").
#     Per the user's own stated preference, pulled and read the newest
#     tas_diagnostics files automatically before asking anything. Two
#     separate things were true in that batch, and pulling in the wrong
#     one would have chased a phantom regression of THE THIRTY-SEVENTH-
#     PASS FIX instead of the real cause:
#       First, THE THIRTY-SEVENTH-PASS FIX itself is NOT regressed. Of 18
#     fresh death_freeze_report_*.txt files, the several checked directly
#     (1788214854, 1788214864, 1788214865) all show velocity reading
#     exactly (0,0) at tick 60 (the respawn tick) AND tick 61, with the
#     first plausible nonzero values only appearing at tick 62+, which is
#     what a genuine fresh keypress after respawn looks like, not
#     residual momentum leaking back in. The specific bug that fix
#     targeted is holding.
#       Second, and this is the actual cause of both "the velocity bug is
#     back" and "the macro is still inconsistent": 11 of those same 18
#     reports flagged "BODY TRANSFORM DIVERGED FROM FROZEN POSITION" --
#     not a rare edge case, a majority, and in every flagged report the
#     divergence was present for essentially the entire dead hold (all 60
#     ticks flagged in each, magnitudes from ~2.7 up to 627 units, the 627
#     case being the already-known pre-round/(0,0)-position edge case).
#     This is exactly the check THE THIRTY-SIXTH-PASS FIX added, now
#     doing its job: player.position itself was frozen perfectly the
#     whole time (as it always has been, all 34+ prior reports), but the
#     physics BODY's own rendered transform (body.global_position) was
#     silently drifting away from it during the hold. The player visually
#     sees the body, not the internal player.position value, so this
#     alone fully explains "the velocity bug is back" without the actual
#     velocity fix having regressed at all -- a stray drifting corpse
#     looks exactly like "the velocity bug" from the outside. It also
#     independently explains "the macro is still inconsistent": the
#     Divergence Diagnostics comparison this file runs is driven by
#     player.position/velocity, which never had visibility into the
#     body's own transform, so a live run and its replay could each end
#     up with the body sitting somewhere slightly different at the moment
#     of respawn even while every value this file was comparing matched.
#       ROOT CAUSE (updates a since-outdated note earlier in this same
#     comment block): the assumption that a child Node2D always trivially
#     inherits the parent's transform when nothing is deliberately moving
#     it does not hold here -- something (most likely native physics-body
#     bookkeeping still running some reduced form of its own transform
#     update independent of the disabled/frozen simulation state) is
#     enough to let the body's own position drift from what this file
#     thinks it's enforcing.
#       FIXED by explicitly re-syncing freeze_player.body.global_position
#     to the frozen freeze_player.position on every single dead tick (not
#     just the position write to the logical player already being done)
#     -- using global_position specifically, not the body's local
#     .position, so this can't double-stack an offset the way the file's
#     own older comment on this exact line used to worry about:
#     global_position's own setter already accounts for whatever the
#     parent's current transform is, so writing it directly always lands
#     the body at the correct world-space spot regardless of what the
#     parent is doing.
#       Verified in the stub project with a new test, RunCheck13.gd, that
#     deliberately displaces body.position (local) by increasing amounts
#     across multiple dead ticks (simulating the exact drift this fix
#     targets) and confirms body.global_position is snapped back onto the
#     frozen position every single tick, not just once; a negative
#     control (temporarily disabling the new sync line) reproduces the
#     drift surviving uncorrected and fails every one of those checks,
#     confirming the test is load-bearing. Also updated RunCheck10.gd's
#     case 2 (THE THIRTY-SIXTH-PASS FIX's own divergence-detector test):
#     it used to inject a one-time (5,5) local displacement and assert the
#     detector flagged it; now that this fix corrects exactly that kind of
#     displacement before the diagnostic ever observes it, the injection
#     was changed to repeat every tick and the assertion flipped to expect
#     NO divergence flag, which now doubles as a second, independent
#     regression check for this fix -- confirmed via the same negative
#     control (disabling the sync line reproduces case 2's divergence flag
#     reappearing). Full regression suite (RunCheck1-13) re-runs clean
#     together with the fix in place.
#       STILL NOT independently real-game-verified beyond the evidence
#     that motivated it, same standing caveat as every pass in this chain
#     -- next step is the user reproducing once more; whatever lands in
#     tas_diagnostics gets pulled automatically, as established.
#
#  5) CROSS-AXIS HORIZONTAL ACCEL, SMALL AND GROWING, WHILE FALLING FAST --
#     SUPERSEDED 2026-08-31 (see note at the end of this item). A
#     2026-08-30 report's first divergence (tick 39) was a clean fresh LEFT
#     press starting from a dead stop horizontally -- no residual horizontal
#     velocity (item 2's scenario), no jump held (so this is the airborne/
#     not-jumping/defer path THE TWELFTH-PASS FIX left alone) -- while
#     falling fast (vertical velocity already 615-690 and climbing under
#     gravity). Press timing itself was correct: on-time, right tick, exactly
#     as the defer path is supposed to produce, which is a good sign that
#     fix is holding up on fresh, unrelated data. But the MAGNITUDE was off
#     from the very first tick the press took effect -- replay's horizontal
#     velocity consistently ~1.5% stronger than live's every single tick
#     after (live/replay deltas per tick: 10.76/10.93, 10.53/10.69, 10.30/
#     10.46, 10.07/10.23, 9.85/10.01 -- a near-constant ~1.015 ratio, not a
#     fixed offset), which by itself is tiny but compounds over hundreds of
#     ticks into the large position drift dominating this report's later
#     mismatch counts. Nothing here points at anything this file controls:
#     both live and replay run through the identical native tick_players_
#     pre_step()/post_step(), and TASTool never touches vertical velocity at
#     all (that's pure Box2D gravity) -- so if fall speed is somehow scaling
#     effective horizontal input strength natively (an air-control-vs-fall-
#     speed interaction, or a real-time-based input smoothing curve that
#     reacts differently to a continuous-input-setter call than to a genuine
#     dispatched key event), that's compiled/native behavior with no
#     decompiled source to check, same dead end as item 4. Not touched --
#     no theory here is strong enough to act on yet, just documented so a
#     future report showing the same ~1.5%-type ratio (rather than some
#     other percentage) would confirm it's a consistent, nameable effect
#     rather than noise.
#       SECOND DATA POINT (2026-08-30, later same day): a fresh checkpoint-0
#     LEFT press, no jump held, falling much SLOWER this time (vertical
#     velocity only 45-150 across the same window, versus 615-690 in the
#     first case) showed the exact same shape of error -- replay's horizontal
#     velocity consistently too strong, ratio holding steady around ~1.013
#     this time (13.222/13.056, 26.170/25.840, 38.849/38.357, 51.262/50.612,
#     63.415/62.609, 75.311/74.352 -- all ~1.0127-1.0129). Smaller ratio at
#     the slower fall speed, same direction of error both times -- consistent
#     with SOME real connection to fall speed, but not a simple
#     proportionality (8x the vertical speed only moved the error from ~1.3%
#     to ~1.5%, not 8x). Two data points is enough to call this a real,
#     repeatable effect rather than noise; still not enough to safely act on
#     -- still not touched.
#       SUPERSEDED (2026-08-31): both data points here measured the
#     magnitude of a value handed to set_local_continuous_input() after it
#     took effect -- a native call this item's own text already flags as a
#     dead end ("compiled/native behavior with no decompiled source to
#     check"). THE FIFTEENTH-PASS FIX removes that call path from Play Macro
#     playback entirely in favor of synthetic Input events via
#     _inject_action(), the same mechanism a real keyboard press generates,
#     which this item never had a chance to measure against. Left above
#     verbatim as investigation history; worth re-checking whether the same
#     ~1.3-1.5%-type ratio still appears under the new mechanism, since nothing
#     here ever ruled out an explanation independent of which call feeds the
#     input (e.g. a genuine fall-speed-dependent air-control curve, which
#     would still show up either way).
#       LIKELY RESOLVED (2026-08-31, much later, see item 15/THE TWENTY-
#     SEVENTH-PASS FIX): both data points here are a fresh press (hold_ticks
#     restarting near 0 under the then-current, wrong reset model) landing
#     during a fall that had already been airborne many ticks (hold_ticks
#     already large under the corrected, ticks-continuously-airborne model).
#     A too-small hold_ticks makes the ramp use an accel_mag closer to the
#     MAX (800) constant than it should, i.e. too strong -- exactly the
#     direction and rough shape of error recorded here (~1.3-1.5% too
#     strong, growing slightly with fall speed/elapsed airborne time). Not
#     re-tested against these exact two old reports (they predate the
#     ramp formula existing at all, so there's nothing to feed the fix's
#     inputs from), but the mechanism lines up well enough to call this
#     item explained rather than open.
#
#  6) LANDING-TRANSITION HORIZONTAL ACCEL RAMP, SLIGHTLY UNDER-STRENGTH IN
#     REPLAY (2026-08-31, first real-game data point AFTER THE FIFTEENTH-PASS
#     FIX shipped). MILESTONE FIRST: this report's Key Event log shows
#     press-tick Δ=0, press-time Δ=0.0ms, AND hold-tick Δ=0 for every single
#     logged press/release across all four actions (3x jump, 1x left, 4x
#     right) -- the one-tick native delivery lag that items 2/3/5 (and THE
#     SIXTH through TWELFTH-pass fixes trying to compensate for it) fought
#     with all session is GONE, completely, with zero exceptions in this
#     report. THE FIFTEENTH-PASS FIX's core goal -- input timing indistinguishable
#     from a real keypress -- is confirmed on real data.
#       What's left is smaller and different in shape: this report's FIRST
#     STATE DIVERGENCE (tick 43, field linear_velocity) lands exactly on the
#     tick a fresh RIGHT press's horizontal acceleration overlaps a LANDING
#     (vel.y drops from 690 to ~0 and ground_timer goes from 0 to 3 between
#     ticks 43 and 44 -- i.e. this is the exact moment of ground contact, not
#     a mid-air-only or mid-ground-only press). Both live and replay show the
#     SAME two-tick acceleration ramp shape before settling into a steady,
#     identical 16.666666/tick delta (matching a 1000 units/s^2 accel
#     constant at 60 ticks/s) -- live's ramp: 10.777778, then +10.544081;
#     replay's ramp: 10.333335, then +10.106980. Both ramps are proportionally
#     weaker versions of the same shape (live ~64.7%/63.3% of steady-state
#     over its first two ticks, replay ~62.0%/60.6%) -- so the ramp itself is
#     a real, shared native behavior on landing, not a replay-only artifact.
#     The BUG is that replay's version of that same ramp is consistently a
#     few percent weaker than live's: a 0.444443 velocity deficit after tick
#     43, growing to a 0.881544 deficit after tick 44, then holding EXACTLY
#     constant (0.881546, 0.88155, 0.881546, 0.881554 across the next four
#     ticks) once both sides reach the identical steady-state delta -- i.e.
#     this is a one-time, two-tick shortfall baked in right at the landing
#     moment, not a growing per-tick error like item 5's superseded pattern.
#       Notably the DIRECTION is opposite item 5's old data (replay was
#     ~1.3-1.5% STRONGER than live there, under the old native-setter path;
#     here replay is a few percent WEAKER than live, under the new
#     synthetic-Input path) -- consistent with item 5's own superseded note
#     that this class of effect might depend on which call feeds the input,
#     now with real data confirming the direction actually flipped rather
#     than just changing magnitude. Nothing here points at anything this file
#     controls: both live and replay run through the identical native
#     tick_players_pre_step()/post_step(), and the only difference between
#     them is which input path fed that tick's action state -- a native/
#     compiled interaction with no decompiled source available to explain
#     further, same dead end as items 4 and 5. Not touched -- one data point
#     isn't enough to safely guess at a mechanism, let alone a fix.
#       PRACTICAL IMPACT: small per-occurrence (well under 1 unit of
#     velocity), but this report's replay run ended at tick 330 while live
#     ran to tick 666 ("replay ended early, likely died mid-macro") -- each
#     fresh press near a landing bakes in another small, permanent position
#     offset (by tick 316/player_right#3, cascaded position drift had reached
#     11.196 units), and enough of those compounding over a long macro
#     eventually diverges far enough to change which hazard/gap the replayed
#     player does or doesn't clear. Worth watching for: does this same
#     landing-transition shortfall reappear on a FUTURE report with a
#     similar ~4-ish-percent-of-steady-state ramp deficit (confirming it's a
#     consistent, nameable effect rather than noise, the same bar item 5 set
#     for itself before being superseded)?
#
#  7) FRESH PRESS DURING PLAIN (NON-LANDING) FREEFALL -- FULL-TICK-LATE ONSET
#     RESURFACES (2026-08-31, later same day, second real-game report after
#     THE FIFTEENTH-PASS FIX). Item 6 (above) looked clean and small right
#     after this fix shipped; this report shows the OLD, much bigger failure
#     mode came right back for a DIFFERENT scenario -- so THE FIFTEENTH-PASS
#     FIX did not uniformly fix on-time delivery, only fixed it for the
#     specific shape item 6's data happened to be.
#       This report's first divergence (tick 16, checkpoint 0's segment, the
#     FIRST non-neutral frame of the entire macro) is a fresh RIGHT press
#     while plainly falling (vel.y climbing 270->345 across the window,
#     nowhere near a landing -- ground_timer stays 0 the whole time, unlike
#     item 6). Live's horizontal velocity jumps to 11.888888 on the press's
#     own tick and then follows a smooth decaying-delta curve (11.64, 11.39,
#     11.15, 10.91, 10.67 -- a real native "diminishing acceleration as speed
#     builds" curve, not a ramp-up-from-zero the way item 6's landing case
#     was). Replay's velocity stays at EXACTLY 0 on that same tick -- input
#     recorded as active on both sides per the frame log (see the Key Event
#     report: press-tick Δ=0, hold-tick Δ=0, i.e. TASTool's OWN bookkeeping
#     of when the press was sent/held matches perfectly) -- and only starts
#     moving the TICK AFTER, at 12.388888. That's the exact shape of the
#     original pre-fifteenth-pass one-tick native delivery lag: the *input
#     state* now reaches Input on the correct tick (confirmed both by the
#     Key Event log and by item 6/item 3's mostly-clean data elsewhere), but
#     whatever native code actually converts that state into a velocity
#     change for THIS press still took an extra tick to react.
#       On top of that full-tick delay, replay's own curve, once it starts,
#     runs a small, steadily-shrinking amount STRONGER than live's equivalent
#     tick (12.39 vs 11.64, 12.13 vs 11.39, 11.87 vs 11.15, 11.62 vs 10.91,
#     11.37 vs 10.67 -- roughly +0.7, narrowing slowly) -- the same
#     "replay runs a bit stronger" direction and rough magnitude as the OLD,
#     now-superseded item 5 data (which was ~1.3-1.5% under the native-setter
#     path), now showing up again under the NEW synthetic-Input path, on top
#     of a full-tick delay item 5's own data never had.
#       Practical impact was severe: 67-unit drift by the printed window,
#     and replay died at tick 131 against live's 603 ("replay ended early,
#     likely died mid-macro") -- worse than item 6's case.
#       Best-fit read so far, NOT acted on: whatever made item 6's press
#     land on-time (tick 43, well into a run, near-terminal fall speed
#     615-690, adjacent to landing) doesn't generalize to this press (tick
#     16, the very first non-neutral frame of the WHOLE macro, moderate fall
#     speed 270-345, no landing nearby) -- something about being the FIRST
#     press of an entire Play Macro run, and/or the specific fall-speed
#     regime, changes whether the native engine's own acceleration
#     application keeps pace with an injected action on its own tick or not.
#     Two data points under the new mechanism (item 6 clean, item 7 not) is
#     not enough to safely re-introduce ANY kind of ahead-of-time priming --
#     that exact kind of one-data-point-confirms/next-one-fails cycle is what
#     items 2/3/5/12 went through all last session under the OLD mechanism,
#     and re-adding heuristic complexity here on this little data would risk
#     repeating it under the new one. Needs at least one more clean repro of
#     "first non-neutral press of a macro, well away from a landing" before
#     touching code again.
#       Also checked against the user's own death-momentum theory sent with
#     this report -- see item 4's 2026-08-31 addendum for why this specific
#     data doesn't confirm or rule that out either; this item's divergence is
#     unrelated to any death/respawn transition (dead_counter reads 0
#     throughout, no death happens anywhere in the compared window).
#
#  8) LIKELY MECHANISM FOR ITEMS 6/7, FOUND FROM ACTUAL DECOMPILED SOURCE
#     (2026-08-31) -- upgrades "compiled/native, no decompiled source to
#     check" (items 4/5/7's dead end) to an actual, named race condition,
#     though the losing/winning side of that race is still outside anything
#     this file can inspect or control. Read project_specific/GameInput.gd
#     and scripts/WPGame.gd directly (not from memory/paraphrase):
#       GameInput.gd's OWN movement/jump path is entirely EVENT-DRIVEN, not
#     a per-tick poll: `_unhandled_input(event)` -> `_process_input(event)`
#     -> `game.set_local_continuous_input(...)`. It only runs when Godot
#     actually dispatches an input event -- exactly the path a real keypress
#     goes through, and exactly what _inject_action() (via
#     Input.parse_input_event() + flush_buffered_events()) is designed to
#     trigger synchronously. This CONFIRMS THE FIFTEENTH-PASS FIX's whole
#     premise is architecturally correct: TASTool is not computing or
#     guessing movement, and hasn't been since that pass -- it is doing
#     exactly what the user is asking for, driving the same event path a
#     real key does.
#       set_local_continuous_input() itself is trivial -- `local_client_
#     continuous_input[index] = input`, just a plain array write, no timing
#     logic at all. The array is only ever CONSUMED once per simulated tick,
#     inside `local_pre_tick()` (WPGame.gd), which reads whatever is
#     CURRENTLY in that array and bundles it into that tick's actual
#     simulated input. `local_pre_tick()` is wired to a `"pre_step"` SIGNAL
#     (`connect("pre_step", self, "local_pre_tick")`), not a GDScript
#     `_physics_process()` override -- and `_tick_game()` (which does the
#     real Box2D step) is called from the compiled/native NetworkGame base
#     class (grep of every .gd file in the decompiled project turns up zero
#     GDScript `_physics_process()` in WPGame.gd or anywhere plausible for
#     it), not from a script node whose ordering `set_process_priority()`
#     could ever influence.
#       That's the likely mechanism: whether TASTool's own `_physics_process()`
#     (synchronously injecting this tick's action via _inject_action(), which
#     synchronously runs GameInput.gd's whole chain down to the array write)
#     happens BEFORE or AFTER the native tick's OWN "pre_step" read of that
#     same array, for a GIVEN simulated tick, is decided by native/compiled
#     scheduling this file has no visibility into and set_process_priority()
#     was never actually able to govern for this specific race (that trick
#     only orders GDScript `_process`/`_physics_process` callbacks against
#     EACH OTHER -- it was originally verified against a MINIMAL repro for a
#     different race, node-vs-node, not against this compiled tick driver).
#     A race whose winner isn't fixed would explain everything observed so
#     far: on-time when TASTool happens to run first that tick (items 6,
#     most presses in item 7's own Key Event log), a full tick late when it
#     doesn't (item 7's actual divergence) -- inconsistent by nature, not a
#     constant offset a heuristic could ever reliably branch on, which also
#     retroactively explains why items 2/3/5/12's whole heuristic-branching
#     era (grounded vs airborne, jump-held vs not) kept looking confirmed by
#     one data point and failing on the next: it was never really about
#     which branch to pick, it was a coin flip dressed up as a pattern.
#       PRACTICAL CONCLUSION: this is not a logic bug left to find and fix in
#     TASTool.gd's own input-delivery code -- _inject_action() already does
#     the architecturally-correct thing. If this theory is right, no amount
#     of restructuring WHICH call TASTool makes (native setter vs synthetic
#     event) can fully close this gap, because both paths ultimately race the
#     same native tick driver for the same array write. Closing it for real
#     means not depending on that native tick driver to convert input into
#     movement AT ALL for at least the specific thing that's actually been
#     failing -- see TASTool_TICK_ACCURACY_PLAN.md's 2026-08-31 status entry
#     for the scoped plan being tried next (self-computed horizontal
#     accel/friction, direct velocity assignment, gravity/jump/dash/
#     collision left untouched since those have never once shown a
#     divergence in any report collected all session).
# ----------------------------------------------------------------------
#  9) THE SIXTEENTH-PASS FIX, IMPLEMENTED (2026-08-31) -- item 8's scoped
#     plan, now actually written: see
#     _apply_practice_playback_computed_horizontal_velocity()'s own big comment
#     for the mechanism, and PLAYBACK_GROUND_ACCEL/PLAYBACK_GROUND_MAX_SPEED's
#     comment for exactly how those two numbers were reverse-engineered from
#     the user's own three requested test recordings (real accel of
#     1000.0 units/s^2, real cap of 400.0 units/s -- both fit the live data
#     essentially exactly). GROUNDED horizontal movement only, and only
#     while a direction is actively held; airborne and release/friction stay
#     fully native (see that comment for why).
#       Two things came out of the SAME three-test data set that are worth
#     recording here even though this fix doesn't address them:
#       a) The airborne exponential-approach curve's rate constant (~0.0212)
#     keeps replicating across every sample ever captured, but its target
#     speed does NOT -- readings around 555-585 that a single shared
#     constant can't reconcile (residual as high as ~1.44 forcing one fit).
#     A dependency on vertical fall speed at the moment of the press is a
#     plausible next guess, not a confirmed one. Not enough to implement on
#     yet -- see PLAYBACK_GROUND_ACCEL's comment.
#       b) Test 2 (a LEFT hold already sitting at the -400 cap, into a JUMP
#     press) turned up an INDEPENDENT instance of item 8's exact same race,
#     this time on the jump axis, not horizontal: the Key Event report
#     showed the jump press itself landing on the correct tick (press-tick
#     Δ=0, hold-tick Δ=0), but the Divergence Diagnostics report showed the
#     actual jump IMPULSE (the velocity.y drop and ground_timer clearing)
#     applying a full tick late on replay -- live jumped on tick 76, replay's
#     tick 77 matched what live had already done on tick 76. Jump is
#     explicitly OUT OF SCOPE for this pass (this file has never touched
#     jump physics, and the reverse-engineered formula above only covers
#     horizontal movement) -- flagging it here since it's the same
#     underlying mechanism as item 8, just observed on a different axis, in
#     case it's worth a similarly-scoped fix later.
#       Also worth noting: the "direction reversal" scenario this fix's own
#     model has to guess at (decelerate-then-reaccelerate at the same
#     constant rate, unconfirmed -- see the big comment on
#     _apply_practice_playback_computed_horizontal_velocity()) was never actually
#     captured by the three requested test recordings -- test 3 recorded a
#     RIGHT press and a separate, later, non-overlapping LEFT press, not an
#     immediate swap from one direction to the other without releasing in
#     between. If a real reversal ever produces a divergence, that's why.
#       UNVERIFIABLE FROM A STUB: whether directly assigning
#     player.linear_velocity.x here actually survives the native tick
#     driver's own subsequent pass over that tick, or gets silently
#     overwritten by it downstream of local_pre_tick()'s unconditional
#     add_input_event() call (see item 8) -- WPGameData/WPGameNativeFunctions
#     are fully native/compiled, so there is no source to check and no way
#     to simulate that specific interaction in a Godot-headless stub
#     project. The very next real Divergence Diagnostics report on a plain
#     grounded hold (re-running test 1's exact scenario is the cleanest
#     check) is what actually answers this.
# ----------------------------------------------------------------------
#  10) THE SEVENTEENTH-PASS FIX -- AIRBORNE HORIZONTAL MOVEMENT, FROM REAL
#     ENGINE CONSTANTS (2026-08-31, later the same day) -- item 9's airborne
#     target-speed mystery is resolved, sort of: at the user's suggestion,
#     they supplied upguys.exe itself, and static analysis of the compiled
#     binary (byte-pattern search for known float constants, cross-checked
#     against actual SSE scalar float-load instructions to throw out
#     coincidental matches -- there were many, mostly vtable pointers whose
#     raw bytes happened to collide with the same 4 bytes) led to Godot's
#     own ClassDB property-registration metadata, which bakes each
#     property's name in as a readable string right next to its default
#     value. That's how player_walk_accel=1000.0 and
#     player_max_horizontal_vel_walk=400.0 were found and independently
#     CONFIRMED to exactly match what THE SIXTEENTH-PASS FIX already
#     reverse-engineered from live gameplay data alone -- strong validation
#     that this whole approach works, not just plausible-looking noise.
#       The same technique surfaced the real airborne constants:
#     player_air_accel_min=600.0, player_air_accel_max=800.0,
#     player_air_accel_duration=1.0 (presumably seconds, a ramp between the
#     two), player_air_friction_lambda=1.0, and
#     player_max_horizontal_vel_air=400.0 (same cap as grounded). This
#     explains why item 9's free-parameter exponential fit kept landing on
#     an inconsistent "target speed" across samples: the real curve isn't
#     approach-to-a-fixed-target at all, it's acceleration opposed by a
#     velocity-proportional drag term (the friction_lambda), which produces
#     a similar-LOOKING decaying-delta shape but isn't the same formula, so
#     fitting the wrong shape to it was always going to disagree between
#     samples that differed in ways the wrong model couldn't account for.
#       IMPLEMENTED, WITH AN HONEST CAVEAT: THE SEVENTEENTH-PASS FIX (see
#     _apply_practice_playback_computed_horizontal_velocity()'s airborne
#     branch) models this as dv/dt = accel - lambda*v, semi-implicit-Euler
#     integrated at 60Hz (the same shape Box2D itself uses for its own
#     built-in linear damping), using accel_max (800) as a flat stand-in
#     for the real min/max/duration ramp -- the ramp's direction (does
#     accel start high and decay to a lower sustained value, or the
#     reverse?) and time basis (since the press, or since leaving the
#     ground?) could NOT be confirmed from the disassembly in the time
#     spent looking, and re-simulating this exact formula against the
#     user's real test-3 recording landed close but not exact (best
#     free-parameter fit against that same data: accel~743, lambda~1.27 --
#     both in the right neighborhood of the real 800/1.0, but not dead on,
#     which given only 6 real ticks to check against could be either
#     genuine formula error or ordinary noise from a 2-parameter fit
#     against so little data). Shipped anyway at the user's explicit
#     choice (offered: ship now / get a longer test recording first / skip
#     airborne entirely -- they chose ship now), but this is a real,
#     acknowledged step down in confidence from the grounded branch, which
#     matched real data essentially exactly. If a real Divergence
#     Diagnostics report on an airborne hold still shows a horizontal
#     divergence, the honest next move is a longer single-direction
#     airborne test recording (20-30+ ticks, no landing) to fit accel and
#     lambda directly against real data instead of guessing from the
#     binary's constants alone, not another guess at the formula shape.
# ----------------------------------------------------------------------
#  11) THE EIGHTEENTH-PASS FIX -- GROUNDED DIRECTION-REVERSAL BRAKING
#     (2026-08-31, later still) -- the user recorded a real macro (Test 1:
#     hold RIGHT to the cap on CP0, release, immediately hold LEFT without
#     waiting for the coast-down to finish, place CP1) specifically to
#     stress-test THE SIXTEENTH-PASS FIX. Two results, one great, one that
#     needed fixing:
#       GREAT NEWS: from the initial press through the full cap-hold and
#     the release coast-down -- 270 ticks -- live and replay matched
#     EXACTLY. This is the first real confirmation that directly assigning
#     player.linear_velocity.x from this file actually survives contact
#     with the native tick driver for the plain hold/release case -- the
#     open risk flagged at the end of item 9 and THE SIXTEENTH-PASS FIX's
#     own comment. Answered: yes, it survives, at least for this case.
#       THE BUG: the moment LEFT was pressed while still coasting from a
#     positive velocity, replay diverged. THE SIXTEENTH-PASS FIX's
#     opposing-direction handling was just the same flat linear-decel-
#     toward-target math as normal acceleration -- but real ground braking
#     against existing momentum isn't linear at all. The user's live
#     (ground-truth) numbers showed a shrinking delta each tick, and -- far
#     more precisely -- replay's own first post-reversal tick matched
#     `previous_velocity * exp(-7.5 * tick_rate)` to five decimal places,
#     where 7.5 is upguys.exe's own player_ground_friction_lambda constant
#     (see item 10 for how the binary was read). Live's numbers decayed
#     slightly faster still, suggesting the real native formula combines
#     that friction with the new direction's acceleration at the same time
#     rather than a clean two-phase brake-then-accelerate split, but fitting
#     that combined formula confidently from six ticks that never even
#     cross zero would repeat the exact overfitting trap item 9's airborne
#     "target speed" fell into.
#       IMPLEMENTED: PLAYBACK_GROUND_BRAKE_LAMBDA (the real 7.5 constant)
#     now drives an exponential-decay branch specifically when the held
#     direction opposes the current computed velocity's sign, falling back
#     to the existing flat-linear accelerate-toward-target model once the
#     magnitude decays below PLAYBACK_GROUND_BRAKE_CROSSOVER_EPSILON (a
#     small, unconfirmed-by-data engineering choice, since no real sample
#     available crosses zero). Verified against the user's own recorded
#     numbers: this cuts the very first tick's error from ~41 units (old
#     flat model) to ~17 units (new model) -- a real, provable improvement,
#     though NOT a perfect match (the gap grows over the following ticks,
#     consistent with the suspected-but-unconfirmed combined friction+accel
#     formula this fix deliberately doesn't guess at). Presented three
#     options (ship now / get a dedicated reversal test recording first /
#     leave it) -- the user chose ship now, same as item 10's airborne
#     call. If a future report on a genuine reversal that actually crosses
#     zero and reaches the new top speed is available, that's what would
#     let the combined formula be fit with confidence instead of guessed at.
#
#  12) THE NINETEENTH-PASS FIX -- THE REAL PHYSICS FUNCTION, DECOMPILED
#     (2026-08-31, later still) -- the user asked, twice, why this file
#     didn't just use the "actual" physics instead of reverse-engineered
#     approximations, was told honestly that only named CONSTANTS had been
#     recovered (via ClassDB property-registration metadata) and not the
#     function that combines them, since no decompiler (Ghidra etc.) could
#     be installed in this sandbox (apt/pip/npm all confirmed blocked --
#     403/host_not_allowed from every package registry tried, despite
#     NO_PROXY listing them). The user's response: "find the source by any
#     means necessary." That turned out to be possible without a
#     decompiler, using only objdump + grep + python stdlib:
#       WPPlayer's exported-property getters are single-instruction
#     trampolines (Godot's ClassDB binder doesn't add overhead for a plain
#     field access) -- literally `movss xmm0, [this+OFFSET]; ret`. Tracing
#     each property's D_METHOD registration code to the getter's own
#     function-pointer immediate (a `lea rax, [rip+X]` a few instructions
#     after the getter/setter name strings load, storing into a MethodBind
#     construction helper) and disassembling THAT address recovered the
#     exact struct offset for every movement tunable: player_walk_accel
#     =0x290, player_air_accel_max=0x294, player_air_accel_min=0x29c,
#     player_max_horizontal_vel_walk=0x2a0, player_max_horizontal_vel_air
#     =0x2a4, player_air_friction_lambda=0x2bc (all per-WPPlayer-instance),
#     plus two confirmed as runtime GLOBALS at fixed .data addresses:
#     player_air_accel_duration=1.0 and player_ground_friction_lambda=7.5
#     (the exact value item 11 had already landed on from live data alone
#     -- a strong independent confirmation that pass's fix was on the right
#     track). A bare offset alone is worthless (dozens of unrelated classes
#     reuse the same small offsets), but grep-ing the full .text
#     disassembly for a tight cluster of THREE OR MORE of these specific
#     offsets appearing within ~100 bytes of each other -- not a
#     coincidence for any other class -- landed directly on WPPlayer's real
#     per-tick horizontal movement function, and it was readable by hand
#     from there.
#       GROUNDED: no change needed. The decompiled logic computes a
#     reduced delta-time so that applying the flat walk_accel for exactly
#     that reduced time lands precisely on the cap, then applies it --
#     mathematically identical, for a constant per-tick accel, to
#     "accelerate then clamp," which is exactly what THE SIXTEENTH-PASS FIX
#     already shipped. This is WHY test 1's 270 ticks matched exactly: it
#     was already right. (The item 11 reversal-braking branch lives in a
#     separate, earlier piece of the same function that this pass read but
#     did not fully trace end-to-end -- see that item's own comment; it
#     remains an evidence-based improvement, not a decompiled exact match.)
#       AIRBORNE: WAS WRONG, now replaced. The real formula is two discrete
#     steps every airborne tick, not the one-equation accel-minus-drag ODE
#     THE SEVENTEENTH-PASS FIX guessed:
#       (1) velocity.x *= exp(-player_air_friction_lambda * dt) -- applied
#           unconditionally while airborne, same exponential shape as the
#           grounded braking branch, just a separate discrete step here
#           rather than folded into one combined equation.
#       (2) velocity.x += accel_magnitude(t) * facing * dt, where
#           accel_magnitude(t) linearly ramps DOWN from player_air_accel_max
#           to player_air_accel_min (800 -> 600) as the current
#           same-direction continuous-airborne hold approaches
#           player_air_accel_duration (1.0s), then holds at the minimum --
#           i.e. air acceleration is STRONGEST the instant you leave the
#           ground or first press a direction, decaying toward a lower
#           steady-state rate the longer it's held. This is the OPPOSITE of
#           a ramp-up, and explains exactly why item 9's original free-fit
#           curve kept finding an inconsistent "target speed" across
#           samples: it was trying to fit a decaying-accel process with an
#           asymptote formula that has no such decay built in.
#       Then hard-clamped to player_max_horizontal_vel_air (400), same
#     reasoning as the grounded clamp above (numerically identical to the
#     decompiled scale-back approach for constant per-tick accel).
#       NOT fully recovered (AT THE TIME -- see RESOLVED note below): the
#     exact two flags gating the real same-direction-airborne-hold tick
#     counter's increment (best reading: "holding a direction" and "was
#     already airborne last tick", not traced end to end) --
#     _practice_playback_air_hold_ticks' reset conditions (landing,
#     releasing, or switching direction) are this file's good-faith
#     reconstruction of that gating, not a byte-for-byte copy.
#       RESOLVED (2026-08-31, much later, see item 15/THE TWENTY-SEVENTH-
#     PASS FIX): the "holding a direction" half of that guess was wrong.
#     Real-data back-calculation showed the counter tracks ticks-
#     continuously-airborne only -- it keeps running through a release or a
#     direction change, and only resets on landing. See item 15 for the
#     evidence and the fix.
#       Also not recovered: the exact meaning of one internal, non-
#     exported WPPlayer field (offset 0x2b8) referenced by the
#     reversal-braking block from item 11's part of the function -- it has
#     no ClassDB getter/setter (the property island jumps straight from
#     0x2b4 to an unrelated global, skipping it), so no name or value could
#     be recovered for it, only that it's read as a target/threshold
#     speed during that branch. UPDATE (see item 13): it was recovered on
#     the very next pass -- it does have a name, this pass's blind offset
#     search just walked past its getter's address.
#       This has NOT yet been checked against a real Divergence Diagnostics
#     report (it postdates every report available so far) -- next test
#     should include an airborne hold of 20-30+ ticks in one direction
#     (to exercise the ramp) and, ideally, an airborne direction reversal
#     (never yet observed in any real recording).
#
#  13) THE TWENTIETH-PASS FIX -- THE REMAINING TWO UNKNOWNS, ONE RESOLVED
#     (2026-08-31, later still) -- the user's response to item 12's two
#     open gaps: "just keep looking for the physics you need. Take as much
#     time until you get both." One came back fully answered:
#       OFFSET 0x2B8 IS `player_ground_friction_max_speed_lambda`
#     (registered default 1.0) -- its trivial getter sits at a slightly
#     separated address from its sibling properties' island, which is
#     exactly why item 12's blind grep for "getter reads [rcx+0x2b8]"
#     walked past it as a false lead the first time; re-deriving it from
#     its ADD_PROPERTY registration string (same method as every other
#     constant) found it directly. With the name in hand, the whole
#     reversal-braking block it lives in reread cleanly as TWO cases
#     sharing one code path, chosen by comparing the held direction's sign
#     against the current velocity's sign:
#       - Signs DISAGREE (item 11's "opposing" case, a genuine reversal):
#         decays toward a target of exactly ZERO using the already-known
#         player_ground_friction_lambda (7.5). This directly answers item
#         11's open suspicion that live's faster-than-predicted decay
#         meant a hidden combined friction+acceleration formula -- it
#         doesn't. The compiled code is a clean two-phase brake-to-zero-
#         then-accelerate split, exactly what THE EIGHTEENTH-PASS FIX
#         already shipped. The only real gap was the exact snap-to-target
#         distance once decay gets close, and PLAYBACK_GROUND_BRAKE_
#         CROSSOVER_EPSILON's existing guess of 1.0 turned out to already
#         match the decompiled snap threshold exactly.
#       - Signs AGREE but current speed is already above
#         player_max_horizontal_vel_walk (speed carried in from something
#         this file's own accel model never produces, like a dash or wall
#         jump): decays toward the signed cap using
#         player_ground_friction_max_speed_lambda (1.0) instead of 7.5,
#         same snap behavior. A real case this file never modeled before
#         this pass -- IMPLEMENTED as PLAYBACK_GROUND_OVERCAP_LAMBDA, see
#         its own comment for the full mechanism.
#       THE AIR-HOLD-COUNTER GATING WAS NOT FULLY RESOLVED, and that's
#     reported honestly rather than glossed over: tracing its owning
#     object (`r13` inside the real physics function) to its caller showed
#     it's pulled fresh from a QUEUE each call (`call 0x14143d200(queue,
#     index)`, inside a loop over however many buffered input frames this
#     render frame needs to catch up on -- the same buffered-input
#     mechanism item 8/9's jump-timing race already implicated). That
#     explains the architecture but not the two specific flags
#     (`r13+0x2be`, `r13+0x2d8`) gating the counter's own increment --
#     nailing those down would mean tracing how and when the queue's slots
#     get reused, a meaningfully bigger dig than fits in a single static
#     pass, and static disassembly without a live debugger has a real
#     ceiling here. _practice_playback_air_hold_ticks' reset conditions
#     are unchanged from THE NINETEENTH-PASS FIX: still this file's
#     best-faith reconstruction, not a byte-for-byte match.
#       Net effect: one of the user's two open questions is now fully
#     answered with a real name, a real default value, and a corrected
#     model (plus a previously entirely-missing over-cap case); the other
#     is better understood architecturally but still not pinned down
#     precisely, and this file says so plainly rather than presenting a
#     guess as settled.
# ----------------------------------------------------------------------
#  14) THE TWENTY-FIRST-PASS FIX -- CHECKPOINT RESTORE DIDN'T CARRY THE
#     AIR-HOLD RAMP COUNTER (2026-08-31, after the user's "All three have
#     been recorded.") -- three fresh real-game tests targeting THE
#     NINETEENTH/TWENTIETH-PASS FIXES specifically:
#       - Right-hold -> jump -> left-hold (287 ticks): PERFECT match, 0
#         field mismatches. Validates the airborne ramp formula end to end,
#         including a mid-air direction reversal.
#       - Right-hold -> dash -> continued right-hold (181 ticks): PERFECT
#         match, 0 field mismatches. Validates PLAYBACK_GROUND_OVERCAP_LAMBDA
#         (the brand-new item-13 branch) on its very first real test.
#       - Held-left airborne hold, checkpoint restored mid-hold (850
#         ticks): a small but real divergence on the FIRST compared tick --
#         live=-38.848896, replay=-39.01556. Not the one-tick-lag signature
#         of the already-known item 8/9 input-buffering race (that shows up
#         as replay reproducing live's PRIOR tick exactly, one tick late;
#         this was wrong from tick one with matching input both sides).
#         Manually working the item-12 ramp formula backward showed
#         replay's actual output matches hold_ticks=1 almost exactly --
#         i.e. replay's counter had been reset to a fresh start by the
#         restore, when the real in-progress hold was already partway
#         through its ramp. Root cause: _practice_playback_air_hold_ticks/
#         _dir (item 12's new state) were real per-recording state the
#         instant they were added, but were never wired into
#         _snapshot_player()/_restore_player() -- every checkpoint silently
#         dropped them back to their declared defaults (0, 0.0) on restore,
#         regardless of where the original recording's hold actually was.
#     FIXED by adding both fields to both functions, same .has()-guarded
#     convention as every other snapshot field (so older snapshots without
#     the key harmlessly leave the current in-progress values alone rather
#     than erroring). Two other reports from the same batch were reviewed
#     and are NOT new issues: a grounded left-press divergence (tick 39,
#     one-tick lag, live applies velocity on the press tick and replay
#     lags by one) is the already-documented item 8/9 race, just observed
#     on a movement key instead of jump for the first time; and a matched
#     pair of identical reports showing a large mid-macro divergence and an
#     early replay death are the already-documented item 1 phantom/
#     backfilled-tick artifact on what looks like an earlier/abandoned
#     recording attempt, unrelated to any of the three formulas above.
#       CONFIRMED (2026-08-31, same night, next real test): right-hold ->
#     jump -> turn-and-hold-left with a checkpoint placed shortly after the
#     turn (still airborne) -> continued left-hold off a ledge -> second
#     checkpoint placed airborne again just after leaving the ledge (596
#     ticks, 2 restores, both snap_grounded=False). PERFECT match, 0 field
#     mismatches across every tick, and Restore Drift Diagnostics shows
#     reset_object_velocity before==after at both restores (no phantom
#     velocity from _reset_object() either). This is exactly the checkpoint-
#     mid-air-hold scenario this pass's fix targeted, on the very next real
#     recording -- direct real-game confirmation the snapshot/restore fix
#     above closed the gap, not just the isolated stub-project round-trip
#     check it originally shipped with.
# ----------------------------------------------------------------------
#  15) THE TWENTY-SEVENTH-PASS FIX -- THE AIR-HOLD RAMP COUNTER'S REAL
#     RESET RULE (2026-08-31, much later, user report: "the replay broke
#     again and I saw it definitely do something weird midair this time")
#     -- divergence_report_1788206408.txt's first divergence (tick 28) is a
#     fresh LEFT press, mid-fall, after 27+ ticks of straight falling with
#     NO direction held at all. Under item 12/THE NINETEENTH-PASS FIX's
#     reset model ("holding a direction" gates the counter), this should
#     start the airborne accel ramp from hold_ticks=1 -- a strong, near-MAX
#     accel_mag. Instead replay was already slightly too strong from the
#     very first affected tick, and the gap to live WIDENED over the next
#     several ticks (velocities -11.666667/-11.777778, -23.084944/
#     -23.30533, -34.258938/-34.586792, -45.192688/-45.626232, -55.89016/
#     -56.42765, -66.35527/-66.99498 -- live/replay). That's the opposite
#     of what a fresh, correctly-reset ramp produces (which UNDERSHOOTS a
#     stale one, not overshoots) -- a real fresh start would track live
#     closely at first and only mismatch later, not diverge immediately and
#     keep growing.
#       Algebraically inverting the tick recursion
#     (vx_n = vx_{n-1}*exp(-lambda*dt) + move*accel_mag(n)*dt) against
#     LIVE's own sequence recovers the actual accel_mag live's game used
#     each tick: ~700.0, 696.47, 693.33, 689.42, 686.71, 683.34. The slope
#     between consecutive values (-3.33/tick) matches the ramp formula's
#     constants exactly -- (PLAYBACK_AIR_ACCEL_MIN - PLAYBACK_AIR_ACCEL_MAX)
#     / (PLAYBACK_AIR_ACCEL_DURATION * 60) = (600-800)/60 = -3.33 -- so the
#     formula's shape and constants are right. But the INTERCEPT only fits
#     a starting hold_ticks around 30, not 1 -- and the player had held no
#     direction at all for the 27+ ticks immediately before this press.
#     The only way hold_ticks could already be ~30 at a player's very first
#     press since landing is if the counter had been running the whole
#     time the player was airborne, completely independent of whether any
#     direction was held.
#       ROOT CAUSE: item 12's reset-condition guess ("landing, releasing,
#     or switching direction") was half wrong. The real counter is simpler
#     than guessed -- it tracks ticks-continuously-airborne, full stop.
#     It resets to 0 only on landing, and otherwise increments every single
#     airborne tick whether or not a direction is held, whether or not the
#     held direction changes. A release or a direction-switch mid-air does
#     NOT reset it -- it only ever stops the tick from adding VELOCITY that
#     tick (move==0 skips the accel step), it never stops the ramp's own
#     clock. This also finally explains item 5's old, pre-ramp-formula
#     mystery (a fresh press's magnitude was consistently ~1.3-1.5% too
#     strong versus live, worse the longer the fall) and closes item 12's
#     own acknowledged uncertainty about the counter's exact gating -- see
#     RESOLVED notes added to both items above.
#       FIXED by restructuring
#     _apply_practice_playback_computed_horizontal_velocity(): the
#     grounded/airborne check and the ticks-continuously-airborne counter
#     update (reset on grounded, increment otherwise) now happen
#     unconditionally, BEFORE the move==0 early-return, instead of being
#     folded into the old per-direction branches further down.
#     _practice_playback_air_hold_dir (the old "which direction is this
#     hold" tracker) is left in place, still snapshotted/restored by
#     checkpoints for backward compatibility with older saved macros, but
#     is no longer read anywhere to gate the counter -- it's vestigial.
#       NOT YET checked against a real Divergence Diagnostics report (it
#     postdates every report available so far) -- next test should include
#     a long airborne fall with no input held followed by a fresh press
#     (exactly this report's own shape) to confirm the fix, plus ideally a
#     release-then-re-press while still airborne (to confirm the counter
#     really does keep running through the release, per the new model,
#     rather than resetting the way the old code -- and the old, now-
#     removed test coverage -- assumed).
# ----------------------------------------------------------------------
#  16) TWO UI/UX FIXES, NOT PHYSICS -- filed here for a single dated
#     changelog trail, not because either needed the investigation
#     methodology above.
#       THE TWENTY-EIGHTH-PASS FIX (2026-08-31, user report: keybind
#     conflict) -- KEY_PLACE_CHECKPOINT moved from KEY_Y to KEY_F. Y is
#     GooberDash's own default Jump binding, so every checkpoint placement
#     was also triggering a jump. Confirmed via grep that no UI string
#     literal anywhere else hardcoded "Y" for this action before renaming.
#       THE TWENTY-NINTH-PASS FIX (2026-08-31, user report: "the GUI keeps
#     moving up and down... sometimes I accidentally click the wrong
#     button") -- root cause: _toast_pill (the transient status-message
#     panel) sits inside _menu_window, a VBoxContainer, between _tab_row
#     and _menu_panel (the Place Checkpoint/Undo/Clear buttons). Code was
#     toggling its .visible on/off every time _status_message changed
#     (roughly every 2.5s during normal use) -- Godot's BoxContainer skips
#     invisible children entirely when it re-sorts, so every toggle shifted
#     _menu_panel (and its buttons) up or down by the toast's height. FIXED
#     by toggling .modulate.a (0.0/1.0) instead of .visible -- the toast
#     keeps reserving its layout slot whether or not it's showing text, so
#     nothing below it moves. Its label also always holds at least a single
#     space instead of an empty string, so the reserved slot's height never
#     changes either. Not practically testable via the headless stub
#     project (no visual layout/rendering there) -- verified by code review
#     only; this is a well-understood, low-risk Godot pattern.
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
#  Restore Drift Diagnostics -- see _arm_restore_drift_watch().
# ----------------------------------------------------------------------
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

const CHECKPOINT_MARKER_RADIUS: = 28.0

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

# ---- scale ----
const SIZE_TITLE: = 42
const SIZE_HEADER: = 31
const SIZE_BODY: = 24
const SIZE_SMALL: = 20
const BUTTON_H: = 58
const TAB_SIZE: = Vector2(460, 68)
const GRIP_SIZE: = Vector2(64, 68)
const MENU_PANEL_MIN_W: = 780
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
var _world_overlay: Node2D = null
var _input_display: CanvasLayer = null
var _updater: Node = null
var _update_checks_enabled := false
var _updater_status_label: Label = null
var _updater_latest_label: Label = null
var _updater_rollback_button: Button = null
var _pending_update_manifest := {}
var _tas_gui_enabled: = true
var _sandbox_gui_enabled: = true
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


func _ready() -> void:
	_menu_open = start_with_menu_open
	_log_open = start_with_log_open
	set_process(true)
	set_physics_process(true)
	# Phase 0.9 -- Thin-Block Terrain Fallback follow-up. This node's own
	# pause_mode was left at the PAUSE_MODE_INHERIT default, so its entire
	# _process() (and therefore _maintain_terrain_fallback_rendering(),
	# called from the very top of it) simply never ran at all whenever
	# get_tree().paused was true -- which _begin_macro_editor_preview() sets
	# for the whole Timeline Editor preview. Patching just the one
	# _refresh_macro_editor_presentation() call site (see that function's
	# own comment) only helps at the specific moments it fires (opening the
	# editor, moving/zooming/centering/resetting freecam) -- looking at an
	# already-open preview without touching freecam never re-triggered it.
	# CheatMenu.gd and TASMacroEditor.gd already both set this exact same
	# property on themselves for exactly this reason (see their own
	# `pause_mode = Node.PAUSE_MODE_PROCESS` lines); applying it here too
	# means _process() -- and everything in it -- now genuinely runs every
	# frame regardless of pause state, closing that gap for good rather
	# than chasing individual call sites one at a time.
	pause_mode = Node.PAUSE_MODE_PROCESS
	# Phase 0.9 follow-up -- the ACTUAL cause of small blocks/ice blocks/etc.
	# going invisible specifically in the Timeline Editor (confirmed by
	# reading the decompiled source, not the thin-terrain theory this phase
	# started with, which was a real but unrelated bug in a different level).
	# `res://goodoh/autoloads/WPViewportRectCalculator.tscn` (autoload name
	# `ViewportRectCalculator`) recomputes `viewport_visible_rect` from the
	# current camera every frame in its own _process() -- and, like every
	# other node this session has found this exact problem in, never
	# exempts itself from pause. `_begin_macro_editor_preview()` pauses the
	# whole tree, so `viewport_visible_rect` freezes at whatever it was the
	# instant the Timeline Editor opened and never updates again no matter
	# where freecam moves afterward. Two node scripts that ARE already
	# correctly pause-exempted (`physics_block/PhysicsBlockRenderer.gd`,
	# `ice_block/ShaderUniformCamera.gd` -- both already in
	# MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS) read that frozen value every
	# frame regardless: PhysicsBlockRenderer.gd directly sets
	# `visible = false` when its own world rect no longer intersects the
	# stale rect, and ShaderUniformCamera.gd feeds the stale rect's center
	# into the ice block's shader as `camera_position`, which its reflection
	# effect depends on to look right. Being correctly exempted from pause
	# didn't help either of them, because the single shared value they both
	# read was never being kept fresh in the first place. Exempting this
	# one autoload fixes the actual root cause for every consumer of
	# `viewport_visible_rect`, not just these two known ones.
	# Looked up by absolute path rather than the bare `ViewportRectCalculator`
	# identifier project scripts use: that shorthand only resolves because
	# the project's own scripts are compiled with the autoload table baked
	# in as global identifiers, which this mod script (loaded from user://,
	# not part of the compiled project) cannot rely on.
	var viewport_rect_calculator: Node = get_node_or_null("/root/ViewportRectCalculator")
	if viewport_rect_calculator != null:
		viewport_rect_calculator.pause_mode = Node.PAUSE_MODE_PROCESS
	# Force this node's _process()/_physics_process() to run before every other
	# node in the tree, INCLUDING the native player controller -- see the
	# "SYNTHETIC INPUT TIMING" section in the header comment above. Without
	# this, whether an injected key press (Buffered Inputs, Perfect Jumpzone,
	# or Macro Bot Mode's Play Macro) actually gets seen by the controller the
	# same physics tick it was meant for depends entirely on scene-tree order,
	# which we don't control and which can put us AFTER the controller --
	# and Godot's is_action_just_pressed()/is_action_just_released() edges
	# only exist for the exact physics tick the event was parsed on, so a
	# same-tick-or-later injection is silently and permanently missed rather
	# than merely delayed. Confirmed empirically against a real Godot 3.5.3
	# build: a single-physics-frame synthetic press is NEVER observed by a
	# node whose _physics_process() runs before ours in the same tick, and
	# IS always observed when ours runs first. A very low priority guarantees
	# "first" regardless of tree position or add/remove order.
	set_process_priority(-1000000)
	_initialize_game_discovery()
	var window_geometry_script = load(WINDOW_GEOMETRY_SCRIPT_PATH)
	if window_geometry_script != null:
		_window_geometry = window_geometry_script.new()
	_load_client_tool_preferences()
	_load_gui_layout_store()
	_load_practice_macro_slots_from_disk()
	var updater_script = load(UPDATER_SCRIPT_PATH)
	if updater_script != null:
		_updater = updater_script.new()
		add_child(_updater)
		_updater.connect("status_changed", self, "_on_updater_status_changed")
		_updater.connect("latest_version_changed", self, "_on_updater_latest_version_changed")
		_updater.connect("update_available", self, "_on_updater_update_available")
		_updater.connect("update_installed", self, "_on_updater_update_installed")
		_updater.connect("rollback_changed", self, "_on_updater_rollback_changed")
		_updater.call_deferred("configure", GOOBPLAYABILITY_VERSION, _update_checks_enabled)
	var post_guard_script = load(POST_PHYSICS_GUARD_SCRIPT_PATH)
	if post_guard_script != null:
		_post_physics_guard = post_guard_script.new()
		_post_physics_guard.set("tas_tool", self)
		add_child(_post_physics_guard)
	var cosmetic_sandbox_script = load(COSMETIC_SANDBOX_SCRIPT_PATH)
	if cosmetic_sandbox_script != null:
		_cosmetic_sandbox = cosmetic_sandbox_script.new()
		add_child(_cosmetic_sandbox)
		if _cosmetic_sandbox.has_method("configure"):
			_cosmetic_sandbox.call("configure", self)
		if _cosmetic_sandbox.has_method("set_gui_enabled"):
			_cosmetic_sandbox.call("set_gui_enabled", _sandbox_gui_enabled)
	var world_overlay_script = load(WORLD_OVERLAY_SCRIPT_PATH)
	if world_overlay_script != null:
		_world_overlay = world_overlay_script.new()
		add_child(_world_overlay)
		_world_overlay.call("configure", self)
		for category in _hitbox_categories.keys():
			_world_overlay.call("set_hitbox_category", category, bool(_hitbox_categories[category]))
		_world_overlay.call("set_show_hitboxes", _hitbox_viewer_enabled)
		_world_overlay.call("set_show_trajectory", _trajectory_preview_enabled)
	var input_display_script = load(INPUT_DISPLAY_SCRIPT_PATH)
	if input_display_script != null:
		_input_display = input_display_script.new()
		add_child(_input_display)
		_input_display.call("configure", self)
		_input_display.call("set_display_enabled", _input_display_enabled)
		_input_display.call("set_detailed", _input_display_detailed)
		_input_display.call("set_show_hold_frames", _input_display_hold_frames)
	var macro_editor_script = load(MACRO_EDITOR_SCRIPT_PATH)
	if macro_editor_script != null:
		_macro_editor = macro_editor_script.new()
		add_child(_macro_editor)
		_macro_editor.call("configure", self)
		if _macro_editor.has_signal("editor_closed"):
			_macro_editor.connect("editor_closed", self, "_update_mouse_capture")
	_build_overlay()
	_apply_ui_scale()
	_load_debug_mode_from_disk()
	_load_fps_limit_from_disk()
	_apply_menu_open_state()
	_apply_log_open_state()
	_apply_tas_gui_visibility()
	_refresh_practice_ui() # picks up the just-loaded Debug Mode state on the buttons built in _build_overlay() above
	call_deferred("_initialize_main_gui_layout")
	call_deferred("_scan_for_client_tool_settings", get_tree().root)
	call_deferred("_show_changelog_if_needed")


# ----------------------------------------------------------------------
#  Main loop
# ----------------------------------------------------------------------
func _process(delta: float) -> void:
	# Phase 0.9 -- Thin-Block Terrain Fallback. Unconditional, same tier as F1
	# above -- baseline rendering correctness, not a TAS feature, so it must
	# self-heal even if the rest of the tool is toggled off.
	_maintain_terrain_fallback_rendering(_find_game())
	# Phase 0.9 follow-up #2 -- the ViewportRectCalculator pause-exemption
	# (see _ready()) turned out not to be enough on its own: Len confirmed
	# small/physics blocks, ice blocks, jump zones and sawblades were still
	# invisible in the Timeline Editor after that fix shipped. Rather than
	# keep chasing which specific per-type native script reads which stale
	# value, this applies the same guess-and-ship approach already used (and
	# already accepted) for the thin-wall terrain fallback above: stop trying
	# to make each native visibility CONDITION correct, and instead just force
	# the same "always show it" outcome that ramps/ordinary blocks already
	# get for free (they have no per-frame visibility check attached at all).
	# See _force_dynamic_object_visibility_late() for the mechanism and why
	# it's deferred instead of being called directly from here.
	call_deferred("_force_dynamic_object_visibility_late", _find_game())

	if _status_message_timer > 0.0:
		_status_message_timer -= delta
		if _status_message_timer <= 0.0:
			_status_message = ""

	if not enabled:
		_release_all_injected_actions()
		_update_overlay()
		return

	# F1 always works, even if the tool is otherwise gated off, so you can
	# still get the UI out of the way (or bring it back) no matter what.
	# It hides/shows BOTH windows entirely -- tab bars included, not just
	# the dropdown panels -- while every armed behavior (Auto-Record,
	# Perfect Jumpzone, Buffered Inputs, Macro Bot Mode, hotkeys)
	# keeps running in the background regardless of whether anything is
	# visible on screen.
	if _just_pressed(KEY_TOGGLE_MENU):
		_toggle_overlay_hidden()

	# Phase 0.4 -- Freecam Stability Pass. Unconditional and independent of the
	# Timeline Editor's own UI/input handling (same reasoning as F1 above) --
	# an emergency way to force the preview camera/pause state back to normal
	# if the editor panel itself is ever unresponsive. close_editor() already
	# does the right full teardown (_end_macro_editor_preview() + hiding the
	# panel), so this just calls it directly rather than duplicating that logic.
	if _macro_editor_preview_active and _just_pressed(KEY_EMERGENCY_CAMERA_RESTORE):
		_log_action("Freecam: emergency camera restore (F7)", null)
		if _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("close_editor"):
			_macro_editor.call("close_editor")
		else:
			_end_macro_editor_preview()

	if _tool_restricted():
		_release_all_injected_actions()
		_update_overlay()
		return

	_process_frame_step_watch()
	_handle_speed_hotkeys()
	_handle_macro_bot_hotkeys()
	_watch_practice_auto_activate()
	_watch_jumpzone(delta)

	_update_overlay()


# Runs at physics-frame granularity (rather than _process's idle-frame
# granularity) because Macro Bot Mode needs to see every physics tick
# individually -- both to record input at the same resolution the native
# player controller reads it, and to catch an alive -> dead transition on
# the exact frame it happens rather than possibly missing a same-idle-frame
# flip-and-flop when multiple physics frames run per idle frame.
func _physics_process(delta: float) -> void:
	# Unconditional, regardless of enabled/_tool_restricted()/practice state
	# below -- a restore triggered from anywhere deserves the same
	# fixed-length observation window, and an in-progress watch shouldn't
	# get silently abandoned just because the tool was toggled off a tick
	# into it. No-op when no watches are active (the overwhelmingly common
	# case, since Restore Drift Diagnostics defaults off).
	_advance_restore_drift_watches()
	# Also unconditional, and for the same reason -- see Death Freeze
	# Diagnostics' own big comment (DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN)
	# for why this specifically must run even when `enabled` is false or
	# `_tool_restricted()` reads true: whether one of those two is
	# unexpectedly gating the freeze itself off is exactly one of the two
	# things this diagnostic exists to catch, and it can't catch that from
	# behind the very gate it's checking. Split into a "before" half here
	# (edge-detection, gating-flag capture, and -- ONLY on a tick the
	# freeze below won't run at all -- the tick's own state capture) and an
	# "after" half once the freeze block has actually run (see that call
	# site further down): capturing on both sides of the same tick the
	# freeze runs would show every death's first tick as a false-positive
	# "anomaly" (raw pre-freeze velocity/body state), since this call
	# necessarily happens before the freeze code that's about to correct
	# it. See _death_diag_before_gate()'s own comment for the full reasoning.
	_death_diag_before_gate()
	# Observe WPPlayer's native airborne-ramp phase continuously, even while
	# this overlay is disabled. A checkpoint can be created immediately after
	# enabling the tool, and a playback-only counter would then restore the
	# wrong air acceleration despite all recorded inputs being correct.
	_update_practice_live_airborne_clock()
	if not enabled or _tool_restricted():
		return
	# If a saved slot's green Play button opened a level, wait here (on the
	# same early physics clock used by recording/playback) until the NEW Time
	# Trial is active and its clock reaches checkpoint 0's recorded phase.
	# The watcher can arm playback in this callback; the normal playback branch
	# later in this function then performs checkpoint 0's restore immediately,
	# without introducing an extra idle-frame/tick delay.
	_watch_saved_macro_autoplay(delta)
	_apply_noclip_movement(delta) # no-op unless Debug Noclip is toggled on
	# THE THIRTIETH-PASS FIX (2026-08-31, user report: "the 0 velocity
	# feature you added doesn't always work I realized"). It didn't --
	# THE TWENTY-FOURTH-PASS FIX's freeze used to live further down, past
	# the `if not _practice_active: return` guard below, and was completely
	# unreachable during Play Macro too (that branch returns before ever
	# getting there). So it only ever protected a death that happened while
	# Macro Bot Mode was ACTIVELY RECORDING -- dying with the tool merely
	# enabled but not currently recording a segment (between takes, just
	# practicing, or in the moments right after a Play Macro attempt aborts
	# on an in-macro death) still coasted exactly like before this tool
	# touched any of this. The user's original complaint was never scoped
	# that narrowly ("I have been constantly saying that u get launched in
	# one direction after respawning when you die") -- it's just as real
	# outside an active recording. Moved up here, ahead of every mode-
	# specific branch below, so the freeze applies any time this tool is
	# meaningfully active at all -- enabled and not restricted, the same
	# gate everything else in this function already respects -- regardless
	# of whether Macro Bot Mode happens to be recording, replaying, or off.
	# Skipped while Debug Noclip is on: noclip already disables the physics
	# body and has its own auto-revive-on-death handling, so there's
	# nothing this needs to add there, and it isn't the segment/diag-log
	# discard this shares a name with below (_practice_active section) --
	# that part's unchanged, still specific to recording.
	if not _noclip_enabled:
		var freeze_player: = _get_local_player()
		if freeze_player != null:
			if freeze_player.alive:
				# Remember where the player actually was as of the most
				# recent tick they were still alive -- see THE THIRTY-FIRST-
				# PASS FIX below for why. Deliberately does NOT touch
				# velocity/position at all while alive -- this branch exists
				# purely to keep a one-tick-fresh bookmark for the else
				# branch below.
				_freeze_last_alive_position = freeze_player.position
				# THE THIRTY-SECOND-PASS FIX (2026-08-31, later still, user
				# report: THE THIRTY-FIRST-PASS FIX's velocity-zero-plus-
				# position-snap still wasn't enough -- "still bugged"). See
				# that pass's own big comment below for why a pure velocity
				# freeze can never fully close this: Box2D can also move an
				# overlapping body through its own CONTACT/PENETRATION
				# correction step, which resolves geometric overlap directly
				# by adjusting position, independent of velocity entirely --
				# zeroing linear_velocity every tick does nothing to stop
				# that if the corpse is still embedded in (or freshly landed
				# inside) a hazard's collision shape when the physics server
				# resolves contacts. The only way to stop ALL of that, not
				# just the velocity-driven half, is to stop the body from
				# being simulated at all. On the alive->dead edge below this
				# now also disables the physics body outright
				# (body_enabled/body.enabled = false, the same two flags
				# _restore_player() already keeps in sync with each other);
				# this branch's job is the other half -- catching the
				# dead->alive edge (respawn) and turning the body back on,
				# in case our own disabling of it is still in effect by
				# then. The decompiled respawn_player() does enable both
				# flags; these assignments are only an idempotent safety
				# reassertion after this tool's dead-hold override.
				if not _freeze_prev_alive:
					freeze_player.body_enabled = true
					if freeze_player.body != null:
						freeze_player.body.enabled = true
					# Do NOT call _reset_object() here. The decompiled native
					# respawn_player() path already enables both flags, zeroes
					# both velocities, and calls _reset_object() itself before
					# alive is observed here. Calling it a second time on this
					# following callback correlates exactly with the delayed
					# 0 -> 53..193 cached-velocity return in the real reports.
					# Reasserting the flags/velocity is safe; repeating the
					# opaque native reset is not.
					# THE THIRTY-SEVENTH-PASS FIX (2026-09-01, user report,
					# after being asked directly what "the velocity bug" now
					# looks like: "it's not that the velocity stays, its more
					# like it comes back maybe to it. So as soon as they
					# respawn they get the velocity for whatever reason.") --
					# this reframes the whole investigation: the freeze holds
					# velocity at zero perfectly the entire time the player is
					# dead (34+ straight clean death_freeze_reports already
					# confirm this), but NOTHING in this branch has ever
					# zeroed velocity again AFTER re-enabling the body here.
					# The working theory: while body_enabled/body.enabled are
					# false, this file's own every-tick
					# `freeze_player.linear_velocity = Vector2.ZERO` /
					# `freeze_player.body.linear_velocity = Vector2.ZERO`
					# writes (see the else branch below) may not actually
					# reach the physics body's own INTERNAL simulated
					# velocity state while it's disabled/removed from the
					# simulation -- Box2D bodies are commonly treated as
					# inactive once removed from the world, and a property
					# write made while inactive can be silently dropped or
					# just not applied to the underlying simulated state
					# until the body re-enters the world. If that's what's
					# happening here, then the ACTUAL velocity the body had
					# at the instant of death (whatever killed the player)
					# stays cached inside it the whole hold, invisible to
					# every read this file has ever done (every read of
					# linear_velocity/body.linear_velocity while dead came
					# back reporting 0, because those reads reflect what we
					# wrote, not necessarily the body's own live internal
					# state) -- and the moment body_enabled/body.enabled flip
					# back to true here, the body re-enters the simulation
					# with that stale, pre-death velocity intact, producing
					# exactly what the user described: it "comes back" the
					# instant they respawn. This matches Death Freeze
					# Diagnostics evidence pulled directly off the user's own
					# machine for this pass: report death_freeze_report_
					# 1788213583.txt shows velocity reading (9.374881, -0) on
					# the very first alive tick after 60 ticks of a
					# supposedly fully-zeroed hold, decaying over the next
					# several ticks (80.46 -> 71.01 -> 62.67 -> 55.30) the way
					# residual momentum decays under drag/friction, not the
					# way a fresh keypress ramps up.
					#   FIXED by explicitly zeroing velocity again, on both
					# script-level properties, immediately after re-enabling
					# the body and calling _reset_object() above -- so even
					# if whatever stale internal state _reset_object() or the
					# re-enable itself surfaces is nonzero, this write is the
					# last word before the player regains control this same
					# tick. Deliberately placed AFTER _reset_object() (not
					# before) in case that native call is itself what
					# surfaces/restores the stale cached velocity -- zeroing
					# before it would risk being overwritten right back.
					freeze_player.linear_velocity = Vector2.ZERO
					if freeze_player.body != null:
						freeze_player.body.linear_velocity = Vector2.ZERO
			else:
				# THE THIRTY-FIRST-PASS FIX (2026-08-31, later still, user
				# report: "after dying I still sometimes get momentum and get
				# thrown back into a spike from the momentum i had after
				# dying") -- THE THIRTIETH-PASS FIX's freeze runs every tick
				# the player reads not-alive, but that leaves exactly ONE
				# tick uncovered: the very tick death itself happens on.
				# Godot calls _physics_process() for every node BEFORE the
				# physics server steps that same frame -- so on the tick a
				# spike collision kills the player, this function's own
				# freeze check above still saw `alive == true` (kill_player()
				# hasn't run yet), and only AFTER this function returns does
				# the physics server actually integrate that tick's motion,
				# resolve the collision, and call kill_player() -- meaning
				# whatever velocity the player had at the moment of impact
				# still gets one full, un-frozen tick of Box2D-simulated
				# travel before the NEXT call to this function ever sees
				# alive=false and starts zeroing anything. Normally that's
				# too small to matter (one tick is ~1/60s), but a spike
				# field with hazards close together, or a high-speed death,
				# is exactly the case where that one uncontrolled tick is
				# enough to carry the corpse into a second, adjacent hazard
				# -- reproducing the user's "thrown back into a spike"
				# report, and explaining why it only happens "sometimes"
				# rather than every death.
				#   Fixed (at the time) by detecting the alive->dead EDGE
				# (comparing against _freeze_prev_alive, this function's own
				# copy of that edge, kept separate from the pre-existing
				# _practice_prev_alive further down since that one only runs
				# while _practice_active) and, on that first dead tick only,
				# restoring player.position back to _freeze_last_alive_position.
				#   STILL NOT ENOUGH ON THAT FIRST TICK ALONE -- THE THIRTY-
				# FOURTH-PASS FIX (2026-08-31, later still) -- Death Freeze
				# Diagnostics (see item 4's own THE THIRTY-THIRD-PASS FIX
				# entry) caught this directly on the very first real death it
				# ever captured: a report showed position moving 3.39 units
				# on the SECOND dead tick, one tick AFTER this snap-back,
				# THE THIRTY-SECOND-PASS FIX's body-disable, and the
				# velocity zero below had all already applied that same
				# first tick -- velocity read exactly (0, 0) and both
				# body_enabled/body.enabled already read false the whole
				# time, yet position still drifted on the very next tick
				# anyway. That rules out velocity-driven movement AND (as
				# far as this file's own state can show) a body genuinely
				# still being simulated -- whatever's moving the position
				# isn't visible as either of those two things from here, but
				# it's real, it's reproducible, and snapping back only once
				# clearly isn't sufficient to fully stop it.
				#   Since chasing the exact mechanism further didn't have a
				# clear next lead (and this file's standing methodology is
				# to act on real evidence rather than keep theorizing once
				# the evidence itself points at a workable fix), the
				# pragmatic fix is to stop being clever about WHEN to
				# reassert this and just do it every dead tick, exactly like
				# the velocity zero and body-disable below already do --
				# reasserting a value that's already correct costs nothing,
				# and this is provably not "only ever needed once" anymore.
				# Confirmed safe with respect to Auto-Respawn/native
				# respawn: both write position AND flip `alive` to true in
				# the same call (see _restore_player() and item 4's own
				# respawn_player() findings) -- by the time this freeze
				# block would next see the player as still `not alive` and
				# try to reassert, a real respawn has already made `alive`
				# read true, so this branch simply won't run that tick at
				# all. UPDATED (THE THIRTY-EIGHTH-PASS FIX, see below): this
				# comment used to say "deliberately NOT writing player.body.
				# position... body is a CHILD node at local (0,0), so
				# writing a world-space position into it too would stack a
				# second offset on top instead of correcting one." That
				# assumption is now directly contradicted by real evidence
				# (see below) -- body's actual rendered transform does NOT
				# always simply track the parent's the way ordinary Godot
				# node parenting would guarantee. THE THIRTY-EIGHTH-PASS FIX
				# below writes body.global_position specifically (not the
				# local .position this note used to warn about) precisely
				# because global_position's own setter accounts for
				# whatever the parent's current transform is, so it can't
				# double-stack an offset the way writing local .position
				# blindly would have.
				freeze_player.position = _freeze_last_alive_position
				freeze_player.linear_velocity = Vector2.ZERO
				if freeze_player.body != null:
					freeze_player.body.linear_velocity = Vector2.ZERO
				# THE THIRTY-SECOND-PASS FIX -- fully stop the body from
				# being simulated while dead, not just its velocity. Set
				# every dead tick (not just the edge) for the same reason
				# the velocity zero above already is: robustness against
				# anything else that might flip either flag back on mid-
				# hold. This is a deliberate deviation from the real game's
				# own kill_player(), which never touches body_enabled/
				# body.enabled (see item 4) -- same category of intentional
				# divergence as the velocity freeze itself already is, just
				# stronger, because the velocity-only version already
				# shipped twice and still wasn't enough on real hardware.
				freeze_player.body_enabled = false
				if freeze_player.body != null:
					freeze_player.body.enabled = false
				# THE THIRTY-EIGHTH-PASS FIX (2026-09-01, user report: "The
				# velocity bug is back and the macro is still inconsistent",
				# right after THE THIRTY-SEVENTH-PASS FIX shipped) -- pulled
				# and read the newest death_freeze_report_*.txt files
				# automatically (per the user's own established preference)
				# before touching any code, since "velocity bug is back"
				# needed to be checked against real data rather than
				# assumed to mean the same thing as last time. It doesn't:
				# velocity itself reads exactly (0, 0) at the respawn edge
				# and every tick of the hold in every single one of 18 fresh
				# reports -- THE THIRTY-SEVENTH-PASS FIX is confirmed still
				# holding, not regressed. What IS back, in 11 of those 18
				# reports (a clear majority, not a rare edge case): THE
				# THIRTY-SIXTH-PASS FIX's own new "BODY TRANSFORM DIVERGED
				# FROM FROZEN POSITION" flag, consistently 2.7-5.8 units
				# (one report: 627 units, a pre-round/hold-state case) for
				# the ENTIRE dead hold, every single tick, not just
				# transiently. That's very likely what the user is still
				# perceiving as "the velocity bug" -- the corpse's actually-
				# rendered position sitting several units away from where
				# this freeze's own state says it put it looks exactly like
				# residual momentum from the outside, even though it isn't
				# one. This also directly explains the still-reported
				# "macro is still inconsistent": Divergence Diagnostics
				# compares logical fields like player.position, which this
				# freeze has kept perfectly consistent -- it has no way to
				# see body's own separately-drifting rendered transform, so
				# a live/replay run could look identical by every field this
				# tool compares while still looking different to the user's
				# own eyes.
				#   This confirms the root cause this file already
				# theorized when THE THIRTY-SIXTH-PASS FIX first added the
				# check: body's own rendered transform is not simply
				# derived from the parent's (player's) transform the way
				# ordinary Godot node parenting would guarantee -- something
				# else (a native Box2D sync, most likely) drives it
				# independently, and disabling the body stops that sync
				# from ever correcting itself back onto the frozen parent
				# position.
				#   FIXED by explicitly forcing the sync every dead tick:
				# freeze_player.body.global_position is now written to match
				# the frozen position directly, using global_position (not
				# local .position) specifically so this can't double-stack
				# an offset the way the file's own long-standing note above
				# used to worry about -- global_position's setter already
				# accounts for whatever the parent's current transform is.
				if freeze_player.body != null:
					freeze_player.body.global_position = freeze_player.position
				# THE THIRTY-FIFTH-PASS FIX (2026-08-31, later still) called
				# freeze_player._reset_object() here on the alive->dead edge, on the
				# theory that a native reset call would force the position/velocity/
				# body-disable state above to become authoritative the same way it
				# does elsewhere in this file (_restore_player(), the respawn-edge
				# re-enable above). REVERTED (2026-08-31, later still, user report:
				# "First jump broke this time, the velocity bug remains") -- this
				# made things WORSE, not better: it broke the player's first jump
				# after a respawn, AND the original momentum/velocity bug this whole
				# chain exists to fix was still present on top of that. _reset_object()
				# is opaque, native, and undocumented -- this file has no decompiled
				# source for it -- and the leading theory for the new breakage is that
				# it clears some jump-related internal state (buffered input, ground-
				# contact/coyote-time tracking, a jump counter) that the respawn path
				# doesn't expect to have already been touched, since every OTHER place
				# this file calls it is paired with that same tick's own full
				# reinitialization (a real teleport, or the respawn-edge re-enable
				# immediately above, which runs right as alive flips back to true) --
				# calling it on the DEATH edge instead has no such pairing, so whatever
				# it clears is left cleared until the player's next real action, which
				# turned out to be that same player's first post-respawn jump input.
				# This is a theory, not a decompiled certainty, same as the fix it's
				# reverting -- but a change that regresses a working mechanic (jump)
				# while NOT fixing the bug it was made for has no case for staying,
				# regardless of the exact mechanism. Reverted back to relying solely
				# on THE THIRTY-FOURTH-PASS FIX's every-tick position/velocity/body-
				# disable reassertion above (unchanged, still in effect) while this
				# file goes back to real evidence (Death Freeze Diagnostics, still in
				# place) for the next step rather than another native-call guess.
				# See OPEN INVESTIGATION NOTES item 4 for the fuller writeup.
			_freeze_prev_alive = freeze_player.alive
	# The "after" half of Death Freeze Diagnostics -- captures the
	# CORRECTED state once the freeze block above has actually run this
	# tick (a no-op if there's no watch open, or if the freeze didn't run
	# this tick -- see that function's own comment for why it's safe to
	# call unconditionally here).
	_death_diag_after_freeze()
	_watch_practice_start_request() # no-op unless a Start (manual or Auto-Activate) is currently armed and waiting -- see the big comment on _on_toggle_practice_pressed()
	_watch_practice_place_request() # no-op unless a checkpoint placement is currently pending -- see the big comment on _on_place_practice_checkpoint_pressed()
	if _practice_playback:
		# SCHEDULER CORRECTION (2026-09-01): one callback already means one
		# fixed Godot physics step. Do not toggle time_scale inside the callback:
		# the engine may already have scheduled a render-frame catch-up batch,
		# and changing the global scale here cannot turn that batch into a
		# single step. Every callback consumes exactly one macro frame.
		# HISTORICAL, SUPERSEDED: THE FOURTEENTH-PASS FIX (2026-08-31) -- OWN THE CLOCK, DON'T SAMPLE
		# IT. See TASTool_TICK_ACCURACY_PLAN.md. Playback used to run at
		# whatever Engine.time_scale was in effect and call
		# _advance_practice_playback() unconditionally every
		# _physics_process() call, trusting that always meant one real
		# native tick -- the same assumption THE THIRTEENTH-PASS FIX above
		# just proved wrong for live recording. Recording has an excuse (a
		# human is playing it in real time, so its ticks can only be
		# detected after the fact); playback doesn't -- it can fully
		# control its own pacing instead of trusting it, the way real TAS
		# tools (TASBot, libTAS, Bizhawk, Dolphin frame-advance) actually
		# work: pause the engine, single-step it forward exactly one
		# physics tick at a time under explicit control, confirm that tick
		# actually happened, THEN act -- never running freely in between.
		#   This _physics_process() call itself IS that confirmation --
		# Godot's own contract guarantees a call here means a real tick
		# just occurred, not an assumption this tool is making. Re-pausing
		# immediately, before doing anything else, means no further tick
		# can slip in while _advance_practice_playback() does this one's
		# work below (the same Engine.time_scale primitive the manual
		# Frame Step feature already uses, just driven from the physics
		# callback itself instead of polled once per idle frame, for tighter
		# guarantees than manual stepping needs). Re-arms exactly one more
		# tick at the bottom, but only if playback is still actually
		# running AND the user hasn't manually paused (_toggle_pause()) in
		# the meantime -- _advance_practice_playback() already correctly
		# flips _practice_playback to false on every genuine stop condition
		# (finished, died, aborted, no player), so checking it after the
		# call, rather than duplicating that logic here, can't disagree
		# with it; and honoring a manual pause here means pressing Pause
		# actually freezes an in-progress macro instead of this loop
		# silently fighting it back to 1.0 next tick.
		#   Known trade-off: the Speed control has no effect on Play Macro
		# pacing anymore -- it's entirely this loop's own, one confirmed
		# tick at a time, not Engine.time_scale's. A cosmetic playback-speed
		# option (still one CONFIRMED tick at a time, just several per
		# visible render frame) is possible later; not done here since
		# accuracy, not speed, is what this pass is for.
		_advance_practice_playback()
		return
	if not _practice_active:
		return
	var player: = _get_local_player()
	if player == null:
		return
	if _practice_prev_alive and not player.alive:
		_practice_current_segment.clear()
		_diag_live_current.clear() # same discard-on-death lifecycle as the segment it mirrors
		_practice_deaths_this_segment += 1
		if _practice_auto_respawn and not _practice_checkpoints.empty():
			# THE NINTH-PASS FIX -- don't restore instantly on this same tick.
			# Arm a wait instead; see PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS's
			# big comment for why letting the native death hold run its course
			# first (instead of preempting it) is worth doing here.
			_practice_awaiting_native_respawn = true
			_practice_native_respawn_wait_ticks = 0
			_set_status("Macro Bot: died -- waiting for respawn")
		else:
			_set_status("Macro Bot: died -- segment discarded")
	# THE TWENTY-FOURTH-PASS FIX (2026-08-31, user report: "you get launched
	# in one direction after respawning when you die and still have
	# momentum" -- see OPEN INVESTIGATION NOTES item 4 for how this was
	# tracked down to a real, confirmed mechanism, not a guess: the real
	# game's own kill_player() (scripts/WPGame.gd, decompiled) only sets
	# alive=false and arms dead_counter -- it never disables the body or
	# touches velocity, so a corpse that was moving when it died just keeps
	# right on being fully Box2D-simulated -- gravity, existing momentum,
	# any collision it happens to hit -- for the WHOLE death hold, until
	# respawn_player() finally resets everything at once) USED TO have its
	# fix live right here, re-zeroing velocity every tick death holds --
	# but that was only reachable while `_practice_active`, so a death
	# outside an active recording (between takes, just practicing, right
	# after a Play Macro attempt aborts) still coasted. THE THIRTIETH-PASS
	# FIX (2026-08-31, later still, user report: "the 0 velocity feature
	# you added doesn't always work") moved the actual freeze up to the top
	# of _physics_process(), ahead of every mode-specific branch -- see
	# that comment for the full reasoning. Nothing left to do here.
	if _practice_awaiting_native_respawn:
		_practice_native_respawn_wait_ticks += 1
		if player.alive or _practice_native_respawn_wait_ticks >= PRACTICE_NATIVE_RESPAWN_MAX_WAIT_TICKS:
			_practice_awaiting_native_respawn = false
			_restore_player(player, _practice_checkpoints.back())
			_set_status("Macro Bot: died -- back to checkpoint %d" % [_practice_checkpoints.size() - 1])
	_practice_prev_alive = player.alive
	# THE ELEVENTH-PASS FIX (2026-08-30): explains basically every wild,
	# hundreds-of-units divergence this session, per the user -- they were
	# using Debug Noclip mid-recording (to reposition/skip around between
	# real attempts). Noclip reads the exact same player_left/right/up
	# actions as real movement (see _apply_noclip_movement()'s own header
	# comment) and drives position directly, bypassing Box2D entirely -- but
	# this capture had no idea any of that was happening, so it recorded
	# noclip's held actions as ordinary jump/movement frames. Play Macro,
	# with no way to know a stretch of "held up" was actually a noclip flight
	# and not a real jump, fed those frames through the NORMAL native input
	# pipeline instead -- producing completely unrelated real physics next
	# to wherever noclip had actually put the live player. That's a properly
	# unreproducible situation, not a bug in the replay logic being chased
	# all session -- so the fix is to stop recording it at all: while Debug
	# Noclip is on, this capture is skipped entirely (segment and diag log
	# both just don't grow this tick), the same way it's already skipped
	# while the player is dead. Recording resumes automatically the instant
	# Noclip is turned back off. A macro that used Noclip to actually GO
	# somewhere (not just idle/wait) will still need a fresh checkpoint
	# placed after turning Noclip off, same as it always would have --
	# skipping capture doesn't teleport the replay there on its own.
	if player.alive and not _noclip_enabled:
		var frame: = _capture_practice_frame()
		var g: = _find_game()
		# Input alone cannot serialize the native physics body's private contact/
		# integration state. Keep the observable beginning-of-tick state beside
		# every input frame so playback can repair a drift at the first callback
		# where it becomes visible, before it cascades into a missed jump/death.
		frame[PRACTICE_FRAME_STATE_KEY] = _capture_practice_frame_state(player, g)
		# Godot invokes this method exactly once for each fixed physics step,
		# including every catch-up step. The game's play_time is updated by a
		# different node later in the same ordered step and is therefore not a
		# valid callback fingerprint here. Record the observed input once and
		# never synthesize or discard macro frames.
		_practice_current_segment.append(frame)
		if _diag_enabled:
			_diag_live_current.append(_capture_diag_entry(player, g, frame))
		_live_tick_fingerprint_normal += 1
		# The status label itself is updated once per idle frame from
		# _update_overlay() (and only when the text actually changes), not
		# here on every physics frame -- see the PERFORMANCE note there.


func _reset_post_native_momentum_guard() -> void:
	_post_guard_player_id = 0
	_post_guard_prev_alive = true
	_post_guard_saw_gameplay_death = false
	_post_guard_probe_ticks_left = 0
	_post_guard_last_accepted_position = Vector2.ZERO
	_post_guard_last_accepted_vx = 0.0


# Called by TASPostPhysicsGuard.gd at priority +1000000, after this main
# script's -1000000 input/recording callback and after the ordinary game
# nodes.  The pre-native freeze above remains useful throughout the dead
# hold; this closes its blind spot on the native death/respawn step itself.
func _post_native_death_momentum_guard() -> void:
	if not enabled or _tool_restricted() or _noclip_enabled:
		_reset_post_native_momentum_guard()
		return
	var player: = _get_local_player()
	if player == null:
		_reset_post_native_momentum_guard()
		return
	var player_id: = player.get_instance_id()
	if player_id != _post_guard_player_id:
		_post_guard_player_id = player_id
		_post_guard_prev_alive = player.alive
		_post_guard_saw_gameplay_death = false
		_post_guard_probe_ticks_left = 0
		_post_guard_last_accepted_position = player.position
		_post_guard_last_accepted_vx = player.linear_velocity.x
		return

	if not player.alive:
		# A committed macro contains no failed attempts. Repair replay-only
		# deaths here, after native collision handling but before the idle
		# renderer, so neither the dead pose nor its displacement is displayed.
		# The early playback callback keeps the same recovery as a fallback for
		# unusual callback ordering where this late guard does not run.
		if _practice_playback and _recover_authoritative_playback_death(player):
			_practice_playback_state_corrections += 1
			_post_guard_prev_alive = true
			_post_guard_saw_gameplay_death = false
			_post_guard_probe_ticks_left = 0
			_post_guard_last_accepted_position = player.position
			_post_guard_last_accepted_vx = player.linear_velocity.x
			_log_action("Macro Bot Mode: repaired unexpected replay collision at frame %d/%d before rendering." % [_practice_playback_index, _practice_playback_frames.size()], null)
			return
		if _post_guard_prev_alive:
			_post_guard_saw_gameplay_death = true
		# Undo the death-step displacement after native collision handling,
		# before rendering, then leave the existing pre-native freeze to hold
		# the same state on every later dead callback.
		if _post_guard_saw_gameplay_death:
			player.position = _freeze_last_alive_position
			player.linear_velocity = Vector2.ZERO
			player.body_enabled = false
			if player.body != null:
				player.body.global_position = _freeze_last_alive_position
				player.body.linear_velocity = Vector2.ZERO
				player.body.enabled = false
		_post_guard_prev_alive = false
		_post_guard_probe_ticks_left = 0
		return

	if not _post_guard_prev_alive and _post_guard_saw_gameplay_death:
		# Native respawn_player() has now completed. Its visible velocity is
		# zero here, but the reports prove a cached pre-death velocity can
		# reappear one or two callbacks later, so arm a bounded probe.
		_post_guard_probe_ticks_left = POST_RESPAWN_MOMENTUM_PROBE_TICKS
		_post_guard_last_accepted_position = player.position
		_post_guard_last_accepted_vx = 0.0
		player.linear_velocity.x = 0.0
		if player.body != null:
			player.body.linear_velocity.x = 0.0
		_post_guard_saw_gameplay_death = false

	_post_guard_prev_alive = true
	if _post_guard_probe_ticks_left <= 0:
		return
	# Never suppress an intentional immediate dash. dash_timer is set by the
	# native controller in the tick this late-priority guard observes.
	if player.dash_timer > 0:
		_post_guard_probe_ticks_left = 0
		return
	var observed_vx: float = player.linear_velocity.x
	var allowed_abs_vx: float = abs(_post_guard_last_accepted_vx) + POST_RESPAWN_MAX_LEGIT_HORIZONTAL_DV
	if abs(observed_vx) > allowed_abs_vx:
		# This is the impossible cached-momentum jump. Roll back only X so an
		# immediate legitimate jump/fall keeps its native vertical state.
		player.position.x = _post_guard_last_accepted_position.x
		player.linear_velocity.x = 0.0
		if player.body != null:
			var corrected_body_position: Vector2 = player.body.global_position
			corrected_body_position.x = _post_guard_last_accepted_position.x
			player.body.global_position = corrected_body_position
			player.body.linear_velocity.x = 0.0
		_post_guard_last_accepted_position = player.position
		_post_guard_last_accepted_vx = 0.0
		_post_guard_momentum_corrections += 1
	else:
		# Legitimate fresh acceleration (including continuously-held D/A) is
		# accepted and expands next tick's envelope naturally.
		_post_guard_last_accepted_position = player.position
		_post_guard_last_accepted_vx = observed_vx
	_post_guard_probe_ticks_left -= 1


# ----------------------------------------------------------------------
#  Gating
# ----------------------------------------------------------------------
# True only when we're actually inside a LIVE, non-time-trial game (real
# competitive multiplayer) -- the one case `only_active_in_debug_or_solo`
# exists to keep the tool out of. No game at all (main menu, level select,
# any other screen) is NOT restricted -- there's nothing risky to guard
# against there, so the menu and its Configure panels stay fully available
# for setting things up (arming Auto-Record, Perfect Jumpzone, Buffered
# Inputs, frame-step count, etc.) before you're even in a level.
func _tool_restricted() -> bool:
	if not only_active_in_debug_or_solo:
		return false
	if OS.is_debug_build():
		return false
	var g: = _find_game()
	if g == null:
		return false
	var gd: WPGameData = g.wp_game_data
	if gd == null:
		return false
	return not gd.is_time_trial


# ----------------------------------------------------------------------
#  Finding the active game / local player / scene
# ----------------------------------------------------------------------
func _initialize_game_discovery() -> void:
	if _game_discovery_initialized:
		return
	_game_discovery_initialized = true
	var tree: = get_tree()
	# A null result used to be re-searched from SceneTree.root on every call.
	# The main menu has no WPGame, and several idle/physics watchers ask for one
	# each frame, so that meant multiple full walks of the (large) menu tree per
	# frame. Scan once for nodes which predate this autoload, then keep the cache
	# current from SceneTree's O(1)-per-added/removed-node notifications.
	if not tree.is_connected("node_added", self, "_on_tas_tree_node_added"):
		tree.connect("node_added", self, "_on_tas_tree_node_added")
	if not tree.is_connected("node_removed", self, "_on_tas_tree_node_removed"):
		tree.connect("node_removed", self, "_on_tas_tree_node_removed")
	_set_cached_game(_search_for_game(tree.root) as WPGame)


func _is_game_candidate(node: Node) -> bool:
	return node != null and node.has_method("serialize_replay") and node.has_method("get_player_at_index")


func _set_cached_game(game: WPGame) -> void:
	if game == _game:
		return
	_game = game
	if _game != null:
		_connect_game_over_submission_guard(_game)
		_practice_auto_activate_was_pre = false
		_practice_auto_activate_checked_state_for_game = false
		_practice_auto_activate_waiting_for_alive = false


# Connect as soon as WPGame enters the tree.  That normally puts this callback
# ahead of TimeTrialGameplayScene._ready()'s own game_over callback, which is
# important: the recording replay must be stopped and made ineligible before
# the stock callback reaches async_submit_replay().
func _connect_game_over_submission_guard(game: WPGame) -> void:
	if game == null or not game.has_signal("game_over"):
		return
	if not game.is_connected("game_over", self, "_on_tas_game_over_before_native"):
		game.connect("game_over", self, "_on_tas_game_over_before_native")


# If the tool was injected while a Time Trial was already alive, its callback
# may predate ours.  Reconnect just those two callbacks when recording starts,
# preserving every other game_over listener and guaranteeing our guard runs
# first.  The stock connection has no binds or flags in the decompiled scene.
func _ensure_game_over_submission_guard_runs_first() -> void:
	var game: = _find_game()
	var scene: = get_tree().current_scene
	if game == null or scene == null or not game.has_signal("game_over"):
		return
	if not ("parameters" in scene) or not scene.has_method("on_game_over"):
		_connect_game_over_submission_guard(game)
		return
	var native_connected: = game.is_connected("game_over", scene, "on_game_over")
	if not native_connected:
		_connect_game_over_submission_guard(game)
		return
	if game.is_connected("game_over", self, "_on_tas_game_over_before_native"):
		game.disconnect("game_over", self, "_on_tas_game_over_before_native")
	game.disconnect("game_over", scene, "on_game_over")
	game.connect("game_over", self, "_on_tas_game_over_before_native")
	game.connect("game_over", scene, "on_game_over")


func _on_tas_tree_node_added(node: Node) -> void:
	if node != null and node.name == "UISettingsDialog":
		call_deferred("_inject_client_tool_settings", node)
	if is_instance_valid(_game) and _game.is_inside_tree():
		return
	if _is_game_candidate(node):
		_set_cached_game(node as WPGame)


func _on_tas_tree_node_removed(node: Node) -> void:
	if is_instance_valid(_game) and node == _game:
		_set_cached_game(null)


# ----------------------------------------------------------------------
#  Native Settings integration / persistent client-tool visibility
# ----------------------------------------------------------------------
func _load_client_tool_preferences() -> void:
	_tas_gui_enabled = bool(SavedSettings.get_value(SETTING_TAS_GUI, true))
	_sandbox_gui_enabled = bool(SavedSettings.get_value(SETTING_SANDBOX_GUI, true))
	_hitbox_viewer_enabled = bool(SavedSettings.get_value(SETTING_HITBOX_VIEWER, false))
	_trajectory_preview_enabled = bool(SavedSettings.get_value(SETTING_TRAJECTORY_PREVIEW, false))
	_input_display_enabled = bool(SavedSettings.get_value(SETTING_INPUT_DISPLAY, false))
	_input_display_detailed = bool(SavedSettings.get_value(SETTING_INPUT_DISPLAY_DETAILED, false))
	_input_display_hold_frames = bool(SavedSettings.get_value(SETTING_INPUT_DISPLAY_HOLD_FRAMES, false))
	_visual_seam_polish_enabled = bool(SavedSettings.get_value(SETTING_VISUAL_SEAM_POLISH, false))
	# Moving level geometry is part of deterministic playback, so new installs
	# and users who never touched this preference should get the safe behavior.
	# The toggle remains available for levels whose custom animation setup does
	# not tolerate seeking.
	_sync_moving_objects_enabled = bool(SavedSettings.get_value(SETTING_SYNC_MOVING_OBJECTS, true))
	_replay_check_stop_on_desync = bool(SavedSettings.get_value(SETTING_STOP_ON_DESYNC, false))
	_self_test_stop_on_failure = bool(SavedSettings.get_value(SETTING_SELF_TEST_STOP_ON_FAILURE, false))
	_update_checks_enabled = bool(SavedSettings.get_value(SETTING_UPDATE_CHECKS, false))
	for category in _hitbox_categories.keys():
		_hitbox_categories[category] = bool(SavedSettings.get_value(SETTING_HITBOX_CATEGORY_PREFIX + str(category), category == "player"))


# ----------------------------------------------------------------------
#  Phase 1.3 -- persistent GUI layout. Main/log windows are Containers, so
#  their meaningful dimensions are the child minimums that actually drive
#  layout; free-floating Timeline/Sandbox panels use exact pixel rectangles.
# ----------------------------------------------------------------------
func _load_gui_layout_store() -> void:
	_gui_layout_config = ConfigFile.new()
	_gui_layout_config.load(GUI_LAYOUT_PATH)


func save_gui_panel_layout(key: String, target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	_gui_layout_config.set_value("panels", key + "_position", target.rect_position)
	_gui_layout_config.set_value("panels", key + "_size", target.rect_size)
	_gui_layout_config.save(GUI_LAYOUT_PATH)


func restore_gui_panel_layout(key: String, target: Control, minimum_size: Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not _gui_layout_config.has_section_key("panels", key + "_position") or not _gui_layout_config.has_section_key("panels", key + "_size"):
		return false
	var viewport_size: Vector2 = get_viewport().size
	var saved_size: Vector2 = _gui_layout_config.get_value("panels", key + "_size", target.rect_size)
	var size := Vector2(clamp(saved_size.x, minimum_size.x, max(minimum_size.x, viewport_size.x - 12.0)), clamp(saved_size.y, minimum_size.y, max(minimum_size.y, viewport_size.y - 12.0)))
	var saved_position: Vector2 = _gui_layout_config.get_value("panels", key + "_position", target.rect_position)
	var position := saved_position
	if _window_geometry != null:
		position = _window_geometry.moved_position(saved_position, size, Vector2.ZERO, viewport_size, 110.0, 60.0)
	else:
		position.x = clamp(position.x, -size.x + 110.0, viewport_size.x - 110.0)
		position.y = clamp(position.y, 0.0, viewport_size.y - 60.0)
	target.rect_position = position
	target.rect_size = size
	return true


func _initialize_main_gui_layout() -> void:
	if _menu_window == null or _log_window == null:
		return
	var menu_height := 240.0
	if not _tool_tab_scrolls.empty() and _tool_tab_scrolls[0] != null:
		menu_height = _tool_tab_scrolls[0].rect_min_size.y
	_gui_layout_defaults["menu"] = {"position": _menu_window.rect_position, "width": _menu_panel.rect_min_size.x, "height": menu_height}
	_gui_layout_defaults["log"] = {"position": _log_window.rect_position, "width": _log_panel.rect_min_size.x, "height": _log_scroll.rect_min_size.y if _log_scroll != null else 140.0}
	_restore_main_window_layout("menu")
	_restore_main_window_layout("log")


func _save_main_window_layout(which: String) -> void:
	var window: Control = _menu_window if which == "menu" else _log_window
	if window == null:
		return
	_gui_layout_config.set_value("main_windows", which + "_position", window.rect_position)
	if which == "menu":
		_gui_layout_config.set_value("main_windows", which + "_width", _menu_panel.rect_min_size.x)
		var height := 240.0
		if not _tool_tab_scrolls.empty() and _tool_tab_scrolls[0] != null:
			height = _tool_tab_scrolls[0].rect_min_size.y
		_gui_layout_config.set_value("main_windows", which + "_height", height)
	else:
		_gui_layout_config.set_value("main_windows", which + "_width", _log_panel.rect_min_size.x)
		_gui_layout_config.set_value("main_windows", which + "_height", _log_scroll.rect_min_size.y if _log_scroll != null else 140.0)
	_gui_layout_config.save(GUI_LAYOUT_PATH)


func _restore_main_window_layout(which: String) -> void:
	if not _gui_layout_defaults.has(which):
		return
	var defaults: Dictionary = _gui_layout_defaults[which]
	var window: Control = _menu_window if which == "menu" else _log_window
	var minimum_width := 520.0 if which == "menu" else 420.0
	var minimum_height := 240.0 if which == "menu" else 140.0
	var position: Vector2 = _gui_layout_config.get_value("main_windows", which + "_position", defaults["position"])
	var width := float(_gui_layout_config.get_value("main_windows", which + "_width", defaults["width"]))
	var height := float(_gui_layout_config.get_value("main_windows", which + "_height", defaults["height"]))
	var viewport_size: Vector2 = get_viewport().size
	width = clamp(width, minimum_width, max(minimum_width, (viewport_size.x - position.x - 20.0) / max(ui_scale, 0.01)))
	height = clamp(height, minimum_height, max(minimum_height, (viewport_size.y - position.y - 90.0) / max(ui_scale, 0.01)))
	var scaled_size := Vector2(width, height + 100.0) * ui_scale
	if _window_geometry != null:
		position = _window_geometry.moved_position(position, scaled_size, Vector2.ZERO, viewport_size, 120.0, 48.0)
	window.rect_position = position
	if which == "menu":
		_menu_panel.rect_min_size.x = width
		for scroll in _tool_tab_scrolls:
			if scroll != null:
				scroll.rect_min_size.y = height
	else:
		_log_panel.rect_min_size.x = width
		if _log_scroll != null:
			_log_scroll.rect_min_size.y = height


func _on_reset_gui_layout_pressed() -> void:
	_gui_layout_config.erase_section("main_windows")
	_gui_layout_config.erase_section("panels")
	_gui_layout_config.save(GUI_LAYOUT_PATH)
	_restore_main_window_layout("menu")
	_restore_main_window_layout("log")
	if _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("reset_saved_layout"):
		_macro_editor.call("reset_saved_layout")
	if _cosmetic_sandbox != null and is_instance_valid(_cosmetic_sandbox) and _cosmetic_sandbox.has_method("reset_saved_layout"):
		_cosmetic_sandbox.call("reset_saved_layout")
	_show_responsive_popup("LAYOUT RESET", "Goobplayability windows were returned to their default positions and sizes for this resolution.")


func _inject_client_tool_settings(settings_dialog: Node) -> void:
	if settings_dialog == null or not is_instance_valid(settings_dialog) or not settings_dialog.is_inside_tree():
		return
	var settings_parent = settings_dialog.get_node_or_null("UIDialog/Panel/DialogRoot/ScrollContainer/MarginContainer/Columns/Settings")
	if settings_parent == null or settings_parent.get_node_or_null("ClientToolsSettings") != null:
		return
	var section := VBoxContainer.new()
	section.name = "ClientToolsSettings"
	section.add_constant_override("separation", 10)
	settings_parent.add_child(section)
	var divider := HSeparator.new()
	section.add_child(divider)
	var heading_row := HBoxContainer.new()
	heading_row.add_constant_override("separation", 12)
	section.add_child(heading_row)
	var icon := TextureRect.new()
	icon.texture = load("res://project_specific/gfx/icons/icon_settings.png")
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(44, 44)
	heading_row.add_child(icon)
	var heading := _make_label("CLIENT TOOLS", _header_font, COLOR_WHITE)
	heading.valign = Label.VALIGN_CENTER
	heading_row.add_child(heading)
	var description := _make_label("Choose which client interfaces are available. Changes persist after restarting.", _small_font, COLOR_TEXT_DIM)
	description.autowrap = true
	section.add_child(description)
	_add_native_settings_toggle(section, "GOOBPLAYABILITY GUI", _tas_gui_enabled, "_on_settings_tas_gui_toggled")
	_add_native_settings_toggle(section, "AVATAR SANDBOX GUI", _sandbox_gui_enabled, "_on_settings_sandbox_gui_toggled")
	_add_native_settings_toggle(section, "GOOBPLAYABILITY DEBUG", _debug_mode_enabled, "_on_settings_debug_mode_toggled")
	var reset_layout := _make_button("RESET GUI LAYOUT", COLOR_BLUE, 260)
	reset_layout.hint_tooltip = "Restore all Goobplayability windows to their default positions and sizes."
	reset_layout.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_layout.connect("pressed", self, "_on_reset_gui_layout_pressed")
	section.add_child(reset_layout)
	var update_divider := HSeparator.new()
	section.add_child(update_divider)
	var update_heading := _make_label("UPDATES", _header_font, COLOR_WHITE)
	section.add_child(update_heading)
	_add_native_settings_toggle(section, "CHECK FOR UPDATES", _update_checks_enabled, "_on_settings_update_checks_toggled")
	var version_row := HBoxContainer.new()
	version_row.add_constant_override("separation", 14)
	section.add_child(version_row)
	var current_label := _make_label("CURRENT  " + GOOBPLAYABILITY_VERSION, _body_font, COLOR_WHITE)
	current_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version_row.add_child(current_label)
	_updater_latest_label = _make_label("LATEST  --", _body_font, COLOR_TEXT_DIM)
	version_row.add_child(_updater_latest_label)
	var update_actions := HBoxContainer.new()
	update_actions.add_constant_override("separation", 10)
	section.add_child(update_actions)
	var check_now := _make_button("CHECK NOW", COLOR_BLUE, 190)
	check_now.hint_tooltip = "Check the pinned HTTPS release manifest. Nothing installs automatically."
	check_now.connect("pressed", self, "_on_updater_check_now_pressed")
	update_actions.add_child(check_now)
	_updater_rollback_button = _make_button("ROLL BACK", COLOR_PINK, 190)
	_updater_rollback_button.hint_tooltip = "Restore the backup created immediately before the last update."
	_updater_rollback_button.disabled = _updater == null or not bool(_updater.call("has_rollback"))
	_updater_rollback_button.connect("pressed", self, "_on_updater_rollback_pressed")
	update_actions.add_child(_updater_rollback_button)
	_updater_status_label = _make_label("Updater is idle.", _small_font, COLOR_TEXT_DIM)
	_updater_status_label.autowrap = true
	section.add_child(_updater_status_label)


func _scan_for_client_tool_settings(node: Node) -> void:
	if node == null:
		return
	if node.name == "UISettingsDialog":
		_inject_client_tool_settings(node)
	for child in node.get_children():
		_scan_for_client_tool_settings(child)


func _add_native_settings_toggle(parent: VBoxContainer, title: String, initial: bool, callback: String) -> void:
	var row := HBoxContainer.new()
	row.rect_min_size = Vector2(0, 66)
	parent.add_child(row)
	var label := _make_label(title, _body_font, COLOR_WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.valign = Label.VALIGN_CENTER
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.pressed = initial
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.rect_min_size = Vector2(110, 60)
	toggle.connect("toggled", self, callback)
	row.add_child(toggle)


func _on_settings_tas_gui_toggled(value: bool) -> void:
	_tas_gui_enabled = value
	SavedSettings.set_value(SETTING_TAS_GUI, value)
	_apply_tas_gui_visibility()


func _on_settings_sandbox_gui_toggled(value: bool) -> void:
	_sandbox_gui_enabled = value
	SavedSettings.set_value(SETTING_SANDBOX_GUI, value)
	if _cosmetic_sandbox != null and is_instance_valid(_cosmetic_sandbox) and _cosmetic_sandbox.has_method("set_gui_enabled"):
		_cosmetic_sandbox.call("set_gui_enabled", value)


func _on_settings_debug_mode_toggled(value: bool) -> void:
	_set_debug_mode_enabled(value)


func _on_settings_update_checks_toggled(value: bool) -> void:
	_update_checks_enabled = value
	SavedSettings.set_value(SETTING_UPDATE_CHECKS, value)
	if _updater != null and is_instance_valid(_updater):
		_updater.call("set_automatic_checks", value)
		if value:
			_updater.call("check_now", false)


func _on_updater_check_now_pressed() -> void:
	if _updater != null and is_instance_valid(_updater):
		_updater.call("check_now", true)


func _on_updater_status_changed(status: String, detail: String) -> void:
	if _updater_status_label != null:
		_updater_status_label.text = status + " — " + detail
	_log_action("Updater: " + status + " — " + detail, null)


func _on_updater_latest_version_changed(version: String) -> void:
	if _updater_latest_label != null:
		_updater_latest_label.text = "LATEST  " + version


func _on_updater_update_available(manifest: Dictionary) -> void:
	_pending_update_manifest = manifest.duplicate(true)
	var version := str(manifest.get("version", ""))
	var changelog := str(manifest.get("changelog", "No changelog was supplied."))
	var message := "Version %s is available.\n\n%s\n\nThe download is restricted to the pinned repository and every file must pass size and SHA-256 verification. A local rollback backup is created before installation." % [version, changelog]
	_show_update_choice_popup("GOOBPLAYABILITY UPDATE", message)


func _on_updater_install_confirmed() -> void:
	_close_tool_popup()
	if _updater != null and is_instance_valid(_updater):
		_updater.call("install_available_update")


func _on_updater_update_installed(version: String) -> void:
	_show_responsive_popup("UPDATE INSTALLED", "Goobplayability %s is installed.\n\nRestart Goober Dash to load the new scripts. The previous version remains available through Settings → Client Tools → Roll Back." % version)


func _on_updater_rollback_changed(available: bool) -> void:
	if _updater_rollback_button != null:
		_updater_rollback_button.disabled = not available


func _on_updater_rollback_pressed() -> void:
	_show_rollback_choice_popup()


func _on_updater_rollback_confirmed() -> void:
	_close_tool_popup()
	if _updater != null and is_instance_valid(_updater) and bool(_updater.call("rollback_last_update")):
		_show_responsive_popup("ROLLBACK READY", "The previous Goobplayability scripts were restored. Restart Goober Dash to load them.")


func _apply_tas_gui_visibility() -> void:
	if _overlay_layer != null:
		_overlay_layer.visible = _tas_gui_enabled and not _overlay_hidden
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.visible = not _overlay_hidden
	_set_practice_markers_visible(_tas_gui_enabled and not _overlay_hidden)
	if not _tas_gui_enabled and _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("is_open") and bool(_macro_editor.call("is_open")):
		_macro_editor.call("close_editor")
	_update_mouse_capture()


func _find_game() -> WPGame:
	if is_instance_valid(_game) and _game.is_inside_tree():
		return _game
	_game = null
	if not _game_discovery_initialized:
		_initialize_game_discovery()
	return _game


func _search_for_game(node: Node) -> Node:
	if node == null:
		return null
	if _is_game_candidate(node):
		return node
	for child in node.get_children():
		var found: Node = _search_for_game(child)
		if found != null:
			return found
	return null


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
func _maintain_terrain_fallback_rendering(game: WPGame) -> void:
	# DIAGNOSTIC (temporary): _log_action() only writes to the in-tool Action
	# Log panel, never to godot.log. _terrain_fallback_debug() below uses
	# print() so its trail lands in godot.log regardless of what the in-game
	# panel shows. Safe to remove once this fix is confirmed working in-game
	# and left alone for a while.
	if game == null:
		_terrain_fallback_debug("no WPGame found")
		return
	if not ("level" in game):
		_terrain_fallback_debug("WPGame has no 'level' property")
		return
	var level = game.get("level")
	if level == null:
		_terrain_fallback_debug("game.level is null")
		return
	if not ("loaded_level" in level):
		_terrain_fallback_debug("level has no 'loaded_level' property")
		return
	var loaded_level = level.get("loaded_level")
	if loaded_level == null:
		_terrain_fallback_debug("level.loaded_level is null")
		return
	var loaded_level_id: int = loaded_level.get_instance_id()
	if loaded_level_id != _terrain_fallback_level_id:
		_terrain_fallback_level_id = loaded_level_id
		_terrain_fallback_debug("new loaded_level id=%d -- applying always-on block/ramp safety net" % loaded_level_id)

	# v3 -- unconditional safety net, no success/failure detection at all.
	# Three narrower attempts (a level-wide "zero fill" check, then a
	# per-node point-in-polygon coverage test against PolygonTerrain's real
	# output, then a hardened version of that same test) each produced
	# exactly zero visible change in-game, despite being reasoned from the
	# decompiled source and, as far as static reading can tell, individually
	# sound. That pattern -- three different detection conditions, zero
	# observable effect from any of them -- points at something shared by
	# all three rather than any one heuristic: most likely the shared
	# game/level/loaded_level/PolygonTerrain lookup above silently failing
	# in a way this environment cannot exercise or confirm without a live
	# Godot process. Rather than guess a fourth detection condition, this
	# version removes detection entirely: every non-animated "block"/"ramp"
	# LevelNode's own Polygon2D is unconditionally shown and textured, every
	# frame, with its z-index forced below PolygonTerrain's merged output so
	# a successful merge still visually covers it exactly as before. See
	# _apply_terrain_fallback_rendering_unconditional()'s own comment for
	# the known cosmetic tradeoff this accepts.
	_apply_terrain_fallback_rendering_unconditional(level, loaded_level)


# DIAGNOSTIC (temporary, see _maintain_terrain_fallback_rendering()'s own
# comment): prints straight to godot.log via print(), unlike _log_action()
# which only reaches the in-tool Action Log panel. Only prints when the
# message actually changes, so it can stay unconditional without spamming
# the log every single frame.
var _terrain_fallback_debug_last_message: String = ""
func _terrain_fallback_debug(message: String) -> void:
	if message == _terrain_fallback_debug_last_message:
		return
	_terrain_fallback_debug_last_message = message
	print("[Goobplayability][TerrainFallback] " + message)


# Unconditionally shows and textures every non-animated "block"/"ramp"
# LevelNode's own (normally hidden, merge-input-only) Polygon2D, every
# frame, regardless of whether PolygonTerrain's merge actually succeeded
# for it. No success/failure detection at all -- see
# _maintain_terrain_fallback_rendering()'s comment for why three
# progressively more careful detection-based attempts were abandoned in
# favor of this.
# To avoid this drawing OVER a successful merge (which would turn every
# normal, correctly-rounded block in every level into a flat, square-
# cornered rectangle), each Polygon2D's z-index is forced below
# PolygonTerrain's own (both LevelNode and PolygonTerrain default to
# z_index=100, z_as_relative=true under Level.tscn -- equal z, so without
# this they'd tie-break on scene tree order, which is not guaranteed to put
# PolygonTerrain's merged mesh on top). z_as_relative=false makes the
# override absolute regardless of ancestor z-index, so it reliably stays
# beneath PolygonTerrain's merged fill wherever the merge succeeds, and is
# the only thing visible wherever it doesn't.
# Known cosmetic tradeoff, accepted deliberately: PolygonTerrain's merged
# fill has rounded corners (the theme's terrain_corner_radius) and the raw
# Polygon2D here is a plain, square-cornered rectangle/triangle. Since the
# fallback is now always present underneath, a small square-cornered sliver
# can peek out past each rounded corner on EVERY block/ramp in EVERY level,
# not just the pathologically thin ones this fix targets. That's a real,
# permanent, minor visual regression -- traded deliberately for actually
# guaranteeing no level is ever left fully hollow, since three attempts at
# a "no visible change when the merge already works" detection produced
# zero observable effect in-game and could not be verified further without
# a live Godot process. If the corner artifact turns out to be more
# noticeable/objectionable in practice than a rare hollow level, that's the
# tradeoff to revisit first.
func _apply_terrain_fallback_rendering_unconditional(level, loaded_level: Node) -> void:
	var theme = null
	if "level_theme" in level:
		theme = level.get("level_theme")
	var terrain_texture: Texture = null
	if theme != null and ("terrain_texture" in theme):
		terrain_texture = theme.get("terrain_texture") as Texture

	for child in loaded_level.get_children():
		if not ("node_type" in child):
			continue
		var node_type: String = str(child.get("node_type"))
		if node_type != "block" and node_type != "ramp":
			continue
		if ("animation" in child) and child.get("animation") != null:
			continue
		if child.has_method("show"):
			child.call("show")
		if "z_as_relative" in child:
			child.set("z_as_relative", false)
		if "z_index" in child:
			child.set("z_index", 50)
		if not ("renderer" in child):
			continue
		var renderer = child.get("renderer")
		if renderer == null:
			continue
		var polygon2d = renderer.get_node_or_null("Polygon2D")
		if polygon2d != null:
			polygon2d.set("visible", true)
			polygon2d.set("z_as_relative", false)
			polygon2d.set("z_index", 50)
			if terrain_texture != null and ("texture" in polygon2d):
				polygon2d.set("texture", terrain_texture)


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


# Called via call_deferred() from _process(), never directly. Read (decompiled):
# - physics_block/PhysicsBlockRenderer.gd sets `visible = false` itself, every
#   frame, whenever ViewportRectCalculator.viewport_visible_rect (however
#   fresh or stale) doesn't intersect the block's own world rect.
# - ice_block's ShaderUniformCamera.gd doesn't touch visibility, but feeds
#   that same rect's center into the ice shader as `camera_position` every
#   frame -- a wrong value there can make the reflection effect render wrong/
#   blank, which is visually indistinguishable from "invisible" at a glance.
# - jump_zone and sawblade don't reference ViewportRectCalculator at all in
#   their own scripts, so whatever hides them (if the exemption above didn't
#   already fix it) is a still-unidentified, separate mechanism.
# Rather than keep tracking down each type's own native condition one at a
# time, this forces the single outcome every one of them needs -- visible,
# unconditionally -- the same way _apply_terrain_fallback_rendering_unconditional()
# already does for block/ramp. It has to run via call_deferred(), AFTER this
# frame's regular _process() pass, because TASTool.gd sets its own
# process_priority to -1000000 (see _ready()) so it runs FIRST, before native
# nodes -- including PhysicsBlockRenderer.gd, whose own _process() would
# simply overwrite `visible = false` again later in the same frame if this
# ran directly from TASTool's _process() instead of deferred after it.
func _force_dynamic_object_visibility_late(game: WPGame) -> void:
	# 1.2.10 -- now that this covers every node type in the game (many of
	# which have real, legitimate show/hide or animation-driven visibility
	# as part of actual gameplay -- disappearing_block literally disappears
	# on purpose, cannons/lasers/alerts/checkpoints likely toggle state too),
	# unconditionally forcing them all visible EVERY frame regardless of
	# context would be a real gameplay regression, not just a harmless no-op
	# like it was for the original 4 always-visible-in-real-play types
	# (physics/ice blocks, jump zones, sawblades). Restricting this to only
	# run while the Timeline Editor preview is actually active keeps it
	# scoped to the bug Len is actually reporting (objects invisible in the
	# editor) without touching normal gameplay at all.
	if not _macro_editor_preview_active:
		return
	if game == null:
		return
	if not ("level" in game):
		return
	var level = game.get("level")
	if level == null:
		return
	if not ("loaded_level" in level):
		return
	var loaded_level = level.get("loaded_level")
	if loaded_level == null:
		return
	for child in loaded_level.get_children():
		if not ("node_type" in child):
			continue
		var node_type: String = str(child.get("node_type"))
		if not (node_type in FORCE_VISIBLE_NODE_TYPES):
			continue
		# Same caution _apply_terrain_fallback_rendering_unconditional() already
		# takes for block/ramp: don't fight a node that's deliberately mid-
		# animation (disappearing_block chief among the new types this could
		# matter for) even while paused for preview.
		if ("animation" in child) and child.get("animation") != null:
			continue
		if child.has_method("show"):
			child.call("show")
		if "visible" in child:
			child.set("visible", true)
		if not ("renderer" in child):
			continue
		var renderer = child.get("renderer")
		if renderer == null:
			continue
		if renderer.has_method("show"):
			renderer.call("show")
		if "visible" in renderer:
			renderer.set("visible", true)
		# 1.2.9 -- ice_block-specific safety net. Jump zones and sawblades
		# were fully fixed by the two lines above (forcing the LevelNode and
		# its top-level "Renderer" node visible); ice blocks were not, per
		# Len's report, even though ice_block's Renderer.tscn uses the same
		# generic LevelNodeRenderer base as jump_zone/sawblade and nothing
		# found by reading the decompiled source explains why it would
		# behave differently. Since the actual mechanism is unconfirmed,
		# this additionally force-shows the two named mesh children the ice
		# block's own scene defines (MeshInstance2D2 -- the base ice sprite
		# with the reflection shader -- and Outline), in case one of them
		# specifically ends up hidden by something this function's first two
		# checks don't reach. Deliberately NOT touching
		# "UpGuys_LevelNodeShadow" (shipped already `visible = false` in the
		# base scene -- that's the drop-shadow, not the ice block itself).
		if node_type == "ice_block":
			for ice_child_name in ["MeshInstance2D2", "Outline"]:
				var ice_child = renderer.get_node_or_null(ice_child_name)
				if ice_child != null:
					if ice_child.has_method("show"):
						ice_child.call("show")
					if "visible" in ice_child:
						ice_child.set("visible", true)


func _get_local_player() -> WPPlayer:
	var g: = _find_game()
	if g == null:
		return null
	var count: int = g.get_player_count()
	for i in count:
		var p: WPPlayer = g.get_player_at_index(i) as WPPlayer
		if p != null and g.is_local_player(p.object_id):
			return p
	return null


# ----------------------------------------------------------------------
#  Undo-able action log
# ----------------------------------------------------------------------
func _format_time() -> String:
	var t: = OS.get_time()
	return "%02d:%02d:%02d" % [t["hour"], t["minute"], t["second"]]


# `undo_data` is null for actions that genuinely cannot be reversed, or a
# Dictionary with a "type" key understood by _apply_undo().
func _log_action(text: String, undo_data) -> void:
	_set_status(text)
	var entry: = {"text": text, "time": _format_time(), "undo": undo_data}
	_log_entries.append(entry)
	_add_log_row(entry)
	while _log_entries.size() > MAX_LOG_ENTRIES:
		var oldest: Dictionary = _log_entries.pop_front()
		if oldest.has("row") and is_instance_valid(oldest["row"]):
			oldest["row"].queue_free()


func _snapshot_engine_state() -> Dictionary:
	return {
		"is_paused": _is_paused,
		"time_scale": Engine.time_scale,
		"saved_time_scale": _saved_time_scale,
	}


func _restore_engine_state(s: Dictionary) -> void:
	if s["is_paused"]:
		_is_paused = true
		_saved_time_scale = s["saved_time_scale"]
		Engine.time_scale = 0.0
	else:
		_is_paused = false
		Engine.time_scale = s["time_scale"]


func _apply_undo(undo: Dictionary) -> void:
	var kind: String = undo.get("type", "")
	if kind == "engine_state":
		_restore_engine_state(undo["state"])


func _on_undo_pressed(entry: Dictionary) -> void:
	var undo = entry.get("undo", null)
	if undo == null:
		return
	_apply_undo(undo)
	_set_status("Undid: %s" % entry["text"])
	_remove_log_entry(entry)


func _on_log_delete_pressed(entry: Dictionary) -> void:
	_remove_log_entry(entry)


func _remove_log_entry(entry: Dictionary) -> void:
	_log_entries.erase(entry)
	if entry.has("row") and is_instance_valid(entry["row"]):
		entry["row"].queue_free()


func _on_clear_log_pressed() -> void:
	for entry in _log_entries:
		if entry.has("row") and is_instance_valid(entry["row"]):
			entry["row"].queue_free()
	_log_entries.clear()


# ----------------------------------------------------------------------
#  Slowdown / pause / frame-step
# ----------------------------------------------------------------------
func _handle_speed_hotkeys() -> void:
	if _just_pressed(KEY_PLAY_STOP):
		_toggle_pause()
	if enable_frame_step and _just_pressed(KEY_FRAME_STEP):
		_request_frame_step()
	if _just_pressed(KEY_SLOWER):
		_adjust_time_scale(-TIME_SCALE_STEP)
	if _just_pressed(KEY_FASTER):
		_adjust_time_scale(TIME_SCALE_STEP)
	if _just_pressed(KEY_RESET_SPEED):
		_on_reset_speed_pressed()


func _toggle_pause() -> void:
	var before: = _snapshot_engine_state()
	if _is_paused:
		Engine.time_scale = _saved_time_scale
		_is_paused = false
		_log_action("Playing (%.2fx)" % Engine.time_scale, {"type": "engine_state", "state": before})
	else:
		_saved_time_scale = Engine.time_scale
		Engine.time_scale = 0.0
		_is_paused = true
		_log_action("Stopped", {"type": "engine_state", "state": before})


func _request_frame_step() -> void:
	if not enable_frame_step:
		return
	if not _is_paused:
		_saved_time_scale = Engine.time_scale
		_is_paused = true
	_step_start_physics_frame = Engine.get_physics_frames()
	Engine.time_scale = 1.0
	_pending_frame_step = true
	# Buffered Inputs: press+hold every armed action for the duration of this
	# step, so it's registered on the physics frame(s) about to run instead
	# of needing the real key physically held at this exact moment.
	for entry in BUFFERABLE_ACTIONS:
		var action: String = entry[1]
		if _buffered_actions.get(action, false):
			_inject_action(action, true)
			_injected_actions_held.append(action)
	_set_status("Frame step (%d frames)" % frame_step_count)


func _process_frame_step_watch() -> void:
	if _pending_frame_step and Engine.get_physics_frames() >= _step_start_physics_frame + frame_step_count:
		Engine.time_scale = 0.0
		_pending_frame_step = false
		for action in _injected_actions_held:
			_inject_action(action, false)
		_injected_actions_held.clear()


func _adjust_time_scale(delta_scale: float) -> void:
	var before: = _snapshot_engine_state()
	if _is_paused:
		_saved_time_scale = clamp(_saved_time_scale + delta_scale, TIME_SCALE_MIN, TIME_SCALE_MAX)
		_log_action("Speed (stopped, resumes at) %.2fx" % _saved_time_scale, {"type": "engine_state", "state": before})
	else:
		Engine.time_scale = clamp(Engine.time_scale + delta_scale, TIME_SCALE_MIN, TIME_SCALE_MAX)
		_log_action("Speed %.2fx" % Engine.time_scale, {"type": "engine_state", "state": before})


func _set_active_time_scale(v: float) -> void:
	v = clamp(v, TIME_SCALE_MIN, TIME_SCALE_MAX)
	if _is_paused:
		_saved_time_scale = v
	else:
		Engine.time_scale = v


func _on_reset_speed_pressed() -> void:
	var before: = _snapshot_engine_state()
	_set_active_time_scale(1.0)
	_log_action("Speed reset to 1.0x", {"type": "engine_state", "state": before})


func _on_enable_frame_step_toggled(pressed: bool) -> void:
	enable_frame_step = pressed
	if not enable_frame_step and _pending_frame_step:
		_pending_frame_step = false
		for action in _injected_actions_held:
			_inject_action(action, false)
		_injected_actions_held.clear()
	if _step_button != null:
		_step_button.disabled = not enable_frame_step
	_set_status("Frame-Step Mode: %s" % ("ON" if enable_frame_step else "OFF"))


func _on_toggle_step_config_pressed() -> void:
	_step_config_row.visible = not _step_config_row.visible


func _on_step_count_delta_pressed(delta: int) -> void:
	frame_step_count = clamp(frame_step_count + delta, FRAME_STEP_COUNT_MIN, FRAME_STEP_COUNT_MAX)
	_step_count_label.text = "%d" % frame_step_count


func _on_toggle_buffered_action_pressed(action: String) -> void:
	var armed: bool = not _buffered_actions.get(action, false)
	_buffered_actions[action] = armed
	var btn: Button = _buffer_action_buttons.get(action)
	if btn != null:
		_style_button(btn, COLOR_PINK if armed else COLOR_BLUE)


# Arms Macro Bot Mode the instant you enter a level (checkpoint 0 = your
# starting position) instead of you having to click Start by hand every run.
func _watch_practice_auto_activate() -> void:
	# _find_game() first, unconditionally -- it's the thing that notices a
	# fresh game instance and resets _practice_auto_activate_was_pre /
	# _practice_auto_activate_checked_state_for_game (see _find_game()
	# above). Checking those before calling it would make this function's
	# correctness depend on _find_game() having already been called
	# elsewhere earlier in the same frame (it usually has, via
	# _tool_restricted(), but not when only_active_in_debug_or_solo is off
	# or this is a debug build) -- calling it here first makes this
	# function correct on its own regardless of that.
	var g: = _find_game()
	if not _practice_auto_activate:
		_practice_auto_activate_waiting_for_alive = false
		return
	if _practice_playback:
		# NEVER auto-(re)start while a stitched Play Macro run is actually in
		# progress. _start_practice_mode() wipes _practice_checkpoints down
		# to a single fresh entry, but _advance_practice_playback() is still
		# mid-flight referencing the OLD macro's checkpoint boundary indices
		# (_practice_playback_checkpoint_at) into that now-tiny array --
		# every tick past the first old boundary then indexes past the end
		# of _practice_checkpoints and errors out, permanently, freezing
		# playback at that frame with no visible sign of what happened. This
		# is exactly what made Play Macro (stitched) look completely dead
		# with Auto-Activate armed: gameplay_state reading LEVEL_PRE again
		# for any reason mid-run (a multi-round transition, a native
		# game-instance reference change, etc.) mid-playback used to stomp
		# it. Just don't fire at all while playback owns practice state --
		# it'll get another chance once this run naturally finishes.
		return
	if _practice_auto_activate_waiting_for_alive:
		# LEVEL_PRE was already seen for this game instance (below) -- a fresh
		# attempt is underway and just needs to wait for the player to
		# actually be ready before checkpoint 0 gets snapshotted.
		#   THE FIX (2026-08-30, fourth pass): the wait-until-ready check and
		# the _start_practice_mode() call it leads to used to both live right
		# HERE, in this idle-frame function -- but capturing checkpoint 0
		# needs the SAME physics-tick footing _watch_practice_start_request()
		# now gives the manual Start button, for exactly the same reason (see
		# the big comment on _on_toggle_practice_pressed()): an idle-frame
		# read of alive/body_enabled can disagree with what the very next
		# physics tick actually records as tick 0, and a checkpoint 0
		# snapshotted "ready" against a stale read is just as silently
		# corrupting as one snapshotted flat-out disabled. So this function
		# now only does what it's actually suited for -- edge-detecting a
		# fresh attempt on an idle frame is harmless, no player state is read
		# or written here -- and hands the wait-for-ready-and-fire part off
		# to _watch_practice_start_request(), the one physics-tick-driven
		# place that now owns it for both Auto-Activate and the manual
		# button. This var stays true until that function's own check
		# succeeds and clears _practice_start_waiting; nothing here needs to
		# poll readiness itself anymore.
		if not _practice_start_waiting:
			_practice_start_waiting = true
			_practice_start_reason = " (auto-activated on level entry)"
		return
	if g == null or g.wp_game_data == null:
		return
	if not ("gameplay_state" in g.wp_game_data):
		return
	var is_pre: bool = g.wp_game_data.gameplay_state == WPGameData.GameplayState_LEVEL_PRE
	# Level-editor test-play (scenes/TestGameplayScene.gd, confirmed
	# verbatim) skips LEVEL_PRE entirely on its very first entry -- it sets
	# gameplay_state straight to LEVEL_PLAY ("if is_level_editor: ...
	# gameplay_state = GameplayState_LEVEL_PLAY"), unlike every other way
	# into a level, which always passes through LEVEL_PRE first. Its own
	# Retry button, though, calls WPGame._reset_players_with_reset_time()
	# (also confirmed verbatim), which DOES set gameplay_state = LEVEL_PRE
	# same as normal -- so it's only that very first entry that has no PRE
	# edge to ever detect. Treat the first gameplay_state this function ever
	# observes for a level-editor game instance as an equivalent trigger,
	# same as seeing LEVEL_PRE would be.
	var editor_first_entry_skip: bool = not _practice_auto_activate_checked_state_for_game and is_pre == false and ("is_level_editor" in g.wp_game_data) and g.wp_game_data.is_level_editor
	_practice_auto_activate_checked_state_for_game = true
	# Edge-triggered on is_pre (fires when it turns true, not for as long as
	# it STAYS true) rather than "once ever per game instance" -- this
	# matters because testing a level from the level editor's own Retry
	# button resets state on the SAME WPGame instance instead of reloading
	# the scene (a real Time Trial's Retry button, by contrast, calls
	# reload_scene() and gets a genuinely new instance, which _find_game()
	# already detects and resets everything for on its own). Firing only
	# once per game instance meant every retry after the first, IN THE
	# EDITOR SPECIFICALLY, left Macro Bot Mode holding checkpoints/segments
	# from whatever you did on a PREVIOUS attempt at the same level --
	# exactly the kind of mismatch that shows up as "fails on the first
	# jump" for no visible reason on a later attempt, since the checkpoint-0
	# restore and the segment recorded against it can end up from two
	# different attempts entirely.
	var is_new_attempt: bool = (is_pre and not _practice_auto_activate_was_pre) or editor_first_entry_skip
	_practice_auto_activate_was_pre = is_pre
	if is_new_attempt:
		# Don't snapshot checkpoint 0 here -- confirmed in WPGame.gd's own
		# round-start code, LEVEL_PRE's whole countdown runs with
		# player.alive FORCED false ("player.alive = false; player.dead_counter
		# = time_to_ticks(_compute_time_until_preplay_spawn(player))" fires
		# at exactly this gameplay_state). Starting immediately here would
		# capture a checkpoint 0 that's already dead, and the very next Play
		# Macro would then restore that dead state as its first action and
		# report "died mid-macro (frame 0)" -- which looks impossible
		# because it is: nothing about your run caused it, the macro was
		# already dead before a single recorded frame of input ever played
		# back. Wait for the player to actually be alive (gameplay truly
		# starting) before capturing anything. (The level-editor's own
		# first-entry skip already has the player alive immediately, so
		# this wait resolves on literally the next tick in that case.)
		_practice_auto_activate_waiting_for_alive = true


# ----------------------------------------------------------------------
#  Perfect Jumpzone mode -- auto-presses ACTION_JUMP on a fixed rhythm for as
#  long as it's armed. Uses the `delta` passed into _process(), which Godot
#  already scales by Engine.time_scale, so the rhythm slows/speeds along
#  with the rest of the tool's slowdown controls instead of staying locked
#  to real wall-clock time -- e.g. at 0.5x the presses land every 500ms of
#  real time but still every 250ms of game time, so timing stays correct
#  relative to the level while you practice slowed down.
#
#  NOTE on jumpzone_hold_ms ("the fullest extent of a jump"): the player's
#  actual jump-height/hold physics live in the native (compiled) player
#  controller, not in any GDScript this tool can read, so this hold
#  duration is a starting default (200ms of a 250ms cycle), not something
#  verified against the native jump code. Use the Configure row to tune it
#  against what you actually see in-game -- interval and hold are
#  independent so you can dial in your own level's rhythm.
# ----------------------------------------------------------------------
func _start_jumpzone_cycle() -> void:
	_jumpzone_cycle_timer = 0.0
	_inject_action(ACTION_JUMP, true)
	_jumpzone_key_held = true


func _stop_jumpzone_key() -> void:
	if _jumpzone_key_held:
		_inject_action(ACTION_JUMP, false)
		_jumpzone_key_held = false


func _watch_jumpzone(delta: float) -> void:
	if not _jumpzone_armed:
		return
	_jumpzone_cycle_timer += delta
	var hold_sec: = jumpzone_hold_ms / 1000.0
	var interval_sec: = jumpzone_interval_ms / 1000.0
	if _jumpzone_key_held and _jumpzone_cycle_timer >= hold_sec:
		_stop_jumpzone_key()
	if _jumpzone_cycle_timer >= interval_sec:
		_start_jumpzone_cycle()


func _on_toggle_jumpzone_pressed() -> void:
	_jumpzone_armed = not _jumpzone_armed
	_style_button(_jumpzone_button, COLOR_PINK if _jumpzone_armed else COLOR_BLUE)
	_jumpzone_button.text = "⤒ Perfect Jumpzone: ON" if _jumpzone_armed else "⤒ Perfect Jumpzone: OFF"
	if _jumpzone_armed:
		_start_jumpzone_cycle()
		_log_action("Perfect Jumpzone: ON -- pressing Jump every %.0fms (held %.0fms)" % [jumpzone_interval_ms, jumpzone_hold_ms], null)
	else:
		_stop_jumpzone_key()
		_log_action("Perfect Jumpzone: OFF", null)


func _on_toggle_jumpzone_config_pressed() -> void:
	_jumpzone_config_row.visible = not _jumpzone_config_row.visible


func _on_jumpzone_interval_delta_pressed(delta: float) -> void:
	jumpzone_interval_ms = clamp(jumpzone_interval_ms + delta, JUMPZONE_INTERVAL_MIN_MS, JUMPZONE_INTERVAL_MAX_MS)
	jumpzone_hold_ms = min(jumpzone_hold_ms, jumpzone_interval_ms - JUMPZONE_TIMING_STEP_MS)
	_jumpzone_interval_label.text = "%.0fms" % jumpzone_interval_ms
	_jumpzone_hold_label.text = "%.0fms" % jumpzone_hold_ms


func _on_jumpzone_hold_delta_pressed(delta: float) -> void:
	jumpzone_hold_ms = clamp(jumpzone_hold_ms + delta, JUMPZONE_HOLD_MIN_MS, jumpzone_interval_ms - JUMPZONE_TIMING_STEP_MS)
	_jumpzone_hold_label.text = "%.0fms" % jumpzone_hold_ms


# ----------------------------------------------------------------------
#  Macro Bot Mode hotkeys
# ----------------------------------------------------------------------
func _handle_macro_bot_hotkeys() -> void:
	if _just_pressed(KEY_PLACE_CHECKPOINT):
		_on_place_practice_checkpoint_pressed()


# Mirrors the fields WPGame itself reads/writes in respawn_player() and
# _set_players_to_start_positions(). Extend this dictionary if your player
# script exposes more state you want captured (e.g. custom power-ups).
# THE REAL ROOT CAUSE (2026-08-30, found via the first Key Event report with
# hold-state/frozen-stretch visibility): a Play Macro run whose checkpoint 0
# was captured DURING the level's own initial "wait a few seconds before you
# can move" hold (alive=true, body_enabled=false, dead_counter=0 -- this is
# NOT the death/respawn countdown, dead_counter stays 0 throughout it; it's
# WPGame's own LEVEL_PRE hold) can never be faithfully replayed. Evidence: a
# real divergence report showed live correctly HOLDING (position/enabled
# frozen) through tick 6+ after such a checkpoint's restore, while replay's
# player flipped enabled=true and teleported ~1200 units to a totally
# different position -- matching a LATER checkpoint's own recorded position
# almost exactly -- on the very NEXT tick. _restore_player() already
# restores last_checkpoint/last_checkpoint_anchor correctly, ruling out a
# stale-pointer bug there. The real mechanism: Play Macro restores player
# state IN PLACE on the SAME already-running WPGame instance -- it never
# reloads the level -- so wp_game_data.gameplay_state is already past
# LEVEL_PRE (the original live recording already transitioned it once, for
# real, at the actual correct moment). The instant that checkpoint's
# still-disabled snapshot is restored, the native game sees "alive, disabled
# player" + "gameplay already active" -- exactly what its own death/respawn
# recovery path exists to correct -- and calls what is presumably the same
# respawn_player() plumbing that legitimately fires after a real death:
# reposition to last_checkpoint, re-enable, reset velocity. Live never hits
# this because gameplay_state genuinely WAS still LEVEL_PRE at that real
# moment; replay always will, no matter how faithfully everything else is
# reproduced, because nothing about Play Macro re-enters LEVEL_PRE.
#   THE FIX: stop this at the source instead of trying to out-race or
# suppress a native recovery path we don't control -- refuse to snapshot
# ANY checkpoint (0 or otherwise) while the player is still in this state.
# This helper is the single place that decision is made, shared by
# _start_practice_mode(), _on_place_practice_checkpoint_pressed(), and
# _watch_practice_auto_activate()'s own separate wait -- all three used to
# gate on `alive` alone, which is exactly the gap that let this happen
# (alive is already true throughout the LEVEL_PRE hold; only body_enabled
# tells the two apart).
func _player_ready_for_checkpoint(p: WPPlayer) -> bool:
	return p.alive and p.body_enabled


func _game_ready_for_practice_start() -> bool:
	var g: = _find_game()
	if g == null or g.wp_game_data == null:
		return false
	var data: = g.wp_game_data
	if not ("gameplay_state" in data) or not ("state_time" in data):
		return false
	if data.gameplay_state != WPGameData.GameplayState_LEVEL_PLAY:
		return false
	var physics_fps: = max(1.0, float(Engine.iterations_per_second))
	return float(data.state_time) >= float(PRACTICE_START_MIN_ACTIVE_TICKS) / physics_fps


func _update_practice_live_airborne_clock() -> void:
	# During playback the reconstructed integrator below owns this counter;
	# updating it here as well would count every replay tick twice.
	if _practice_playback:
		return
	var p: = _get_local_player()
	if p == null or not p.alive or not p.body_enabled:
		_practice_playback_air_hold_ticks = 0
		_practice_playback_air_hold_dir = 0.0
		_practice_live_airborne_player_id = 0
		return
	var player_id: = p.get_instance_id()
	if player_id != _practice_live_airborne_player_id:
		_practice_live_airborne_player_id = player_id
		_practice_playback_air_hold_ticks = 0
	if p.stick_to_ground_timer > 0.0:
		_practice_playback_air_hold_ticks = 0
	else:
		_practice_playback_air_hold_ticks += 1


func _snapshot_player(p: WPPlayer) -> Dictionary:
	var g: = _find_game()
	var snap: = {
		"position": p.position,
		"linear_velocity": p.linear_velocity,
		"body_enabled": p.body_enabled,
		"alive": p.alive,
		"dash_cooldown": p.dash_cooldown,
		"dash_timer": p.dash_timer,
		"coyote_timer": p.coyote_timer,
		"squish_counter": p.squish_counter,
		"wallslide_counter": p.wallslide_counter,
		"wallslide_dir": p.wallslide_dir,
		"stun_timer": p.stun_timer,
		"is_inside_one_way_platform": p.is_inside_one_way_platform,
		"dead_counter": p.dead_counter,
		"last_checkpoint": p.last_checkpoint,
		"last_checkpoint_anchor": p.last_checkpoint_anchor,
		"stick_to_ground_timer": p.stick_to_ground_timer,
		"facing_dir": p.facing_dir,
		# This is the continuously observed LIVE airborne clock maintained by
		# _update_practice_live_airborne_clock(), not merely the playback
		# integrator's last value. That distinction is what makes a checkpoint
		# recorded partway through a fall restore the correct native ramp phase.
		"practice_playback_air_hold_ticks": _practice_playback_air_hold_ticks,
		"practice_playback_air_hold_dir": _practice_playback_air_hold_dir,
	}
	if g != null and g.wp_game_data != null:
		snap["play_time"] = g.wp_game_data.play_time
	if _sync_moving_objects_enabled:
		snap["moving_world_state"] = _snapshot_moving_world_state(g)
	return snap


func _capture_practice_frame_state(p: WPPlayer, g: WPGame) -> Dictionary:
	var state: = {
		"position": p.position,
		"linear_velocity": p.linear_velocity,
		"practice_playback_air_hold_ticks": _practice_playback_air_hold_ticks,
		"practice_playback_air_hold_dir": _practice_playback_air_hold_dir,
	}
	for field in PRACTICE_FRAME_RESYNC_SCALAR_FIELDS:
		state[field] = p.get(field)
	if g != null and g.wp_game_data != null:
		var data: = g.wp_game_data
		for field in ["play_time", "state_time", "time_remaining"]:
			if field in data:
				state[field] = data.get(field)
	# Speed is presentation metadata. It never replaces the game's race clock,
	# but it lets local playback reproduce portions recorded in slow motion.
	state["tas_playback_speed"] = 0.15 if _pending_frame_step else clamp(Engine.time_scale, 0.05, 4.0)
	return state


func _snapshot_moving_world_state(game: WPGame) -> Array:
	var result := []
	if game == null or not ("level" in game) or game.level == null:
		return result
	_snapshot_moving_world_state_recursive(game.level, game.level, result)
	return result


func _snapshot_moving_world_state_recursive(level_root: Node, node: Node, result: Array) -> void:
	if node is AnimationPlayer:
		var animation := node as AnimationPlayer
		var animation_name: String = animation.current_animation
		var animation_position: float = 0.0
		# Godot reports an engine error when current_animation_position is read
		# from an idle AnimationPlayer. Empty players are common in downloaded
		# levels, so snapshot them without querying that invalid property.
		if not animation_name.empty():
			animation_position = animation.current_animation_position
		result.append({
			"kind": "animation",
			"path": str(level_root.get_path_to(animation)),
			"animation": animation_name,
			"position": animation_position,
			"speed": animation.playback_speed,
			"playing": animation.is_playing(),
		})
	elif node is Node2D and (node is RigidBody2D or node is KinematicBody2D or node.get_class() == "Box2DPhysicsBody"):
		var moving := node as Node2D
		var entry := {
			"kind": "body",
			"path": str(level_root.get_path_to(moving)),
			"position": moving.position,
			"rotation": moving.rotation,
			"scale": moving.scale,
		}
		if "linear_velocity" in moving:
			entry["linear_velocity"] = moving.get("linear_velocity")
		if "angular_velocity" in moving:
			entry["angular_velocity"] = moving.get("angular_velocity")
		if "enabled" in moving:
			entry["enabled"] = moving.get("enabled")
		result.append(entry)
	for child in node.get_children():
		_snapshot_moving_world_state_recursive(level_root, child, result)


func _restore_moving_world_state(snapshot: Dictionary) -> void:
	if not _sync_moving_objects_enabled:
		return
	var game := _find_game()
	if game == null or not ("level" in game) or game.level == null:
		return
	if not snapshot.has("moving_world_state"):
		# Compatibility for format-3/older slots: animation tracks can still be
		# moved to their recorded checkpoint phase using the saved play clock.
		# Physics bodies cannot be reconstructed retroactively, so new recordings
		# use the exact snapshots above instead.
		_seek_legacy_level_animations(game.level, float(snapshot.get("play_time", 0.0)))
		return
	for entry in snapshot["moving_world_state"]:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("path"):
			continue
		var node := game.level.get_node_or_null(NodePath(str(entry["path"])))
		if node == null:
			continue
		if entry.get("kind", "") == "animation" and node is AnimationPlayer:
			var animation := node as AnimationPlayer
			animation.playback_speed = float(entry.get("speed", 1.0))
			var animation_name := str(entry.get("animation", ""))
			if not animation_name.empty():
				animation.play(animation_name)
				animation.seek(float(entry.get("position", 0.0)), true)
			if not bool(entry.get("playing", false)):
				animation.stop(false)
		elif node is Node2D:
			var moving := node as Node2D
			moving.position = entry.get("position", moving.position)
			moving.rotation = entry.get("rotation", moving.rotation)
			moving.scale = entry.get("scale", moving.scale)
			if entry.has("linear_velocity") and "linear_velocity" in moving:
				moving.set("linear_velocity", entry["linear_velocity"])
			if entry.has("angular_velocity") and "angular_velocity" in moving:
				moving.set("angular_velocity", entry["angular_velocity"])
			if entry.has("enabled") and "enabled" in moving:
				moving.set("enabled", entry["enabled"])


func _seek_legacy_level_animations(node: Node, recorded_time: float) -> void:
	if node is AnimationPlayer:
		var animation := node as AnimationPlayer
		var animation_name := animation.current_animation
		if not animation_name.empty() and animation.has_animation(animation_name):
			var resource := animation.get_animation(animation_name)
			var length := resource.length if resource != null else 0.0
			animation.seek(fposmod(recorded_time, length) if length > 0.0 else 0.0, true)
	for child in node.get_children():
		_seek_legacy_level_animations(child, recorded_time)


func _apply_recorded_practice_frame_state(p: WPPlayer, state: Dictionary) -> bool:
	var corrected: = false
	if state.has("position") and p.position.distance_to(state["position"]) > DIAG_POSITION_EPSILON:
		_begin_visual_seam_blend(p.position, state["position"])
		p.position = state["position"]
		if p.body != null:
			p.body.global_position = state["position"]
		corrected = true
	if state.has("linear_velocity") and p.linear_velocity.distance_to(state["linear_velocity"]) > DIAG_VELOCITY_EPSILON:
		p.linear_velocity = state["linear_velocity"]
		if p.body != null:
			p.body.linear_velocity = state["linear_velocity"]
		corrected = true
	# The horizontal replay integrator runs later in this same callback. Seed
	# it from the authoritative beginning-of-tick velocity every time so it
	# cannot immediately overwrite a correction with its own stale estimate.
	if state.has("linear_velocity"):
		_practice_playback_computed_vx = state["linear_velocity"].x
	for field in PRACTICE_FRAME_RESYNC_SCALAR_FIELDS:
		if state.has(field) and p.get(field) != state[field]:
			p.set(field, state[field])
			corrected = true
	if state.has("practice_playback_air_hold_ticks") and _practice_playback_air_hold_ticks != state["practice_playback_air_hold_ticks"]:
		_practice_playback_air_hold_ticks = state["practice_playback_air_hold_ticks"]
		corrected = true
	if state.has("practice_playback_air_hold_dir") and not is_equal_approx(_practice_playback_air_hold_dir, state["practice_playback_air_hold_dir"]):
		_practice_playback_air_hold_dir = state["practice_playback_air_hold_dir"]
		corrected = true
	# Never restore play_time/state_time/time_remaining here. They are global
	# race/server clocks, not player state. Reasserting the recorded values
	# made the visible clock oscillate and produced invalid native/LB replay
	# timestamps whenever a macro was started later in the same attempt.
	# The values remain in the frame state as read-only diagnostics.
	return corrected


func _recover_authoritative_playback_death(p: WPPlayer) -> bool:
	# Failed attempts are discarded when a segment is committed, so a dead
	# player in the middle of a stored segment can only be replay drift (most
	# commonly an old macro meeting a moving hazard at a different phase).  A
	# format-3 frame already contains the exact beginning-of-tick player state;
	# revive into that state instead of throwing the entire slot away.
	if _practice_playback_index < 0 or _practice_playback_index >= _practice_playback_frames.size():
		return false
	var frame = _practice_playback_frames[_practice_playback_index]
	if typeof(frame) != TYPE_DICTIONARY or not frame.has(PRACTICE_FRAME_STATE_KEY):
		return false
	var state = frame[PRACTICE_FRAME_STATE_KEY]
	if typeof(state) != TYPE_DICTIONARY or not state.has("position") or not state.has("linear_velocity"):
		return false
	var recovery: Dictionary = state.duplicate(true)
	recovery["alive"] = true
	recovery["body_enabled"] = true
	recovery["dead_counter"] = 0
	_restore_player(p, recovery)
	# _reset_object() is deliberately part of a real revive, but its native
	# implementation may rewrite velocity/timers. Reassert the recorded frame
	# after it, then make the three life gates explicit once more.
	_apply_recorded_practice_frame_state(p, state)
	p.alive = true
	p.body_enabled = true
	p.dead_counter = 0
	if p.body != null:
		p.body.enabled = true
		p.body.global_position = state["position"]
		p.body.linear_velocity = state["linear_velocity"]
	# _restore_player() snaps the render track to the revived (next-frame)
	# body. The post-physics sampler still owns the frame being displayed, so
	# let it initialize from that recorded frame instead of interpolating
	# backward from the recovery target.
	_reset_playback_visual_track()
	return true


func _restore_player(p: WPPlayer, snap: Dictionary) -> void:
	_restore_moving_world_state(snap)
	var visual_position_before_restore: Vector2 = p.position
	if snap.has("alive"):
		p.alive = snap["alive"]
	# REVERTED, per Divergence Diagnostics evidence: this used to disable the
	# physics body before repositioning it, then re-enable right after, as an
	# UNVERIFIED experiment aimed at "spawn on the edge of a block, land
	# standing in the middle of it" (theorized as Box2D resolving a marginal
	# teleport-induced overlap). It could never be tested against real Box2D
	# until now. With Diagnostic Logging on, two independent live-vs-replay
	# comparisons both showed the exact same reproducible ~1.5 unit downward
	# position shift starting 2-3 ticks after EVERY checkpoint restore
	# (identical live/replay starting position, identical inputs, position
	# alone drifting) -- i.e. the toggle was itself causing a small settle
	# on re-enable that the real game's own respawn_player() (WPGame.gd)
	# never exhibits, because it never disables the body at all: it sets
	# player.body.enabled = true once, unconditionally, with no OFF step
	# first. Removing the toggle and matching that exactly is what this now
	# does. If block-edge landings resurface, that theory wasn't wrong about
	# WHAT was happening, just about disable/re-enable being a safe way to
	# fix it -- re-run Diagnostic Logging to see whether this changed the
	# tick-2/3 divergence at all before trying another approach.
	var had_body: = p.body != null
	if snap.has("body_enabled"):
		p.body_enabled = snap["body_enabled"]
	if snap.has("position"):
		# Deliberately NOT also writing p.body.position here -- see the
		# TELEPORT ACCURACY note below. p.body is a CHILD node of p (see
		# nodes/WPPlayer.tscn: Box2DPhysicsBody is parented under WPPlayer,
		# at local position (0,0)), so p.body.position is a position LOCAL
		# to the player, not a world coordinate. Writing our captured
		# (world-space) position into it stacks a second full copy of that
		# offset on top of p.position, which is compounded again through
		# Box2D's own simulation -- exactly the "teleports / off by a lot"
		# symptom. The game's own respawn_player() (WPGame.gd) never
		# touches body.position either, only player.position -- this now
		# matches that exactly.
		p.position = snap["position"]
	if snap.has("linear_velocity"):
		p.linear_velocity = snap["linear_velocity"]
		if p.body != null:
			p.body.linear_velocity = snap["linear_velocity"]
	# INSTRUMENTATION for the horizontal-phantom-velocity finding (see the
	# 2026-08-30 divergence report: replay showed vel=(-13.27778, 15.000001)
	# on the very first compared tick after a restore whose OWN snapshot said
	# velocity was (0, 0), decaying smoothly over several following ticks --
	# not a one-tick glitch, a real leftover velocity riding along under
	# something we do AFTER zeroing it). p._reset_object() below is the one
	# remaining step in this function whose internals we don't control or
	# see (native/compiled, called only because the real respawn_player()
	# also calls it last -- see the TELEPORT ACCURACY note below). Snapshot
	# what linear_velocity actually reads immediately before and immediately
	# after that one call so Restore Drift Diagnostics can show, per restore,
	# whether _reset_object() itself is what's putting the phantom velocity
	# back -- if pre/post differ, that's the culprit, isolated to one call;
	# if they're identical (both already wrong, or both correctly zero),
	# whatever's happening is further downstream (this tick's
	# _sync_practice_playback_injected_input() call, or the engine's own
	# physics step) and this rules _reset_object() out instead.
	var velocity_before_reset_object: Vector2 = p.linear_velocity
	if had_body:
		# Set once, directly, now that position/velocity already hold the new
		# values -- no OFF step beforehand (see the note above). Falls back
		# to whatever the snapshot's own body_enabled said (matches the
		# pre-existing behavior when the snapshot explicitly wanted it
		# disabled) rather than unconditionally forcing it on.
		p.body.enabled = snap.get("body_enabled", true)
	if snap.has("dash_cooldown"):
		p.dash_cooldown = snap["dash_cooldown"]
	if snap.has("dash_timer"):
		p.dash_timer = snap["dash_timer"]
	if snap.has("coyote_timer"):
		p.coyote_timer = snap["coyote_timer"]
	if snap.has("squish_counter"):
		p.squish_counter = snap["squish_counter"]
	if snap.has("wallslide_counter"):
		p.wallslide_counter = snap["wallslide_counter"]
	if snap.has("wallslide_dir"):
		# wallslide_dir is wallslide_counter's own direction companion --
		# confirmed together in the real game's renderer (WPPlayerRenderer_Old.gd:
		# "if player.wallslide_counter: player_dir = -1 if player.wallslide_dir
		# else 1"). We were already restoring wallslide_counter (the "are we
		# wall-sliding" flag) but never this half of it, so a restored player
		# could come back flagged as wall-sliding against whichever wall it
		# happened to be touching a moment before -- not necessarily the one
		# the snapshot was actually taken against. Any velocity/friction the
		# wallslide logic applies would then push the wrong way, which reads
		# exactly like "a bit of velocity carries over" from before the death.
		p.wallslide_dir = snap["wallslide_dir"]
	if snap.has("stun_timer"):
		p.stun_timer = snap["stun_timer"]
	if snap.has("is_inside_one_way_platform"):
		p.is_inside_one_way_platform = snap["is_inside_one_way_platform"]
	if snap.has("dead_counter"):
		p.dead_counter = snap["dead_counter"]
	if snap.has("last_checkpoint"):
		p.last_checkpoint = snap["last_checkpoint"]
	if snap.has("last_checkpoint_anchor"):
		p.last_checkpoint_anchor = snap["last_checkpoint_anchor"]
	if snap.has("stick_to_ground_timer"):
		# stick_to_ground_timer is coyote_timer's grounded-side counterpart
		# (confirmed real and readable via WPPlayerAI.gd: "var is_on_ground: =
		# ai.player.stick_to_ground_timer > 0") -- it's what lets the game
		# treat the player as still grounded for a few ticks after actually
		# leaving the ground (e.g. running off a ledge or over a bump),
		# which affects whether ground-only movement/friction rules apply
		# that tick. We were already restoring coyote_timer but not this;
		# leaving it at whatever stale value it had going into the death
		# means a restored player can be treated as grounded (or not) based
		# on leftover state that has nothing to do with the snapshot -- another
		# way stale state can surface as unexpected velocity right after a
		# restore. Notably the game's OWN respawn_player() doesn't reset this
		# field either, but that's fine for a real respawn (a fresh, designed
		# spawn point) -- Macro Bot Mode restores to an arbitrary mid-run
		# position instead, where a mismatched grounded-state guess matters.
		p.stick_to_ground_timer = snap["stick_to_ground_timer"]
	if snap.has("facing_dir"):
		# facing_dir is real and gameplay-relevant, not cosmetic: it's the
		# fallback GameInput.gd's own dash-direction logic uses when a dash
		# is pressed with neither left nor right currently held ("elif not
		# local_player.facing_dir: dash_dir = local_player.facing_dir",
		# confirmed verbatim) -- and since THE FIFTEENTH-PASS FIX, Macro Bot
		# Mode's own playback dash goes through that exact same native
		# GameInput.gd logic itself (via a synthetic dash Input event), rather
		# than reproducing the fallback here as it used to. If a
		# checkpoint snapshot doesn't capture which way the player was
		# actually facing, a restore leaves facing_dir at whatever stale
		# value it happened to hold from BEFORE the restore -- e.g. still
		# "facing right" from earlier in the run even though the checkpoint
		# was taken mid-death facing left. Any no-direction-held dash
		# replayed right after that restore/boundary then fires backwards
		# relative to the original recording, which reads exactly like
		# "confuses itself" / a movement that doesn't match what was done.
		p.facing_dir = snap["facing_dir"]
	if snap.has("practice_playback_air_hold_ticks"):
		# See the matching comment in _snapshot_player(): restore the observed
		# native airborne-ramp phase captured during live play.
		_practice_playback_air_hold_ticks = snap["practice_playback_air_hold_ticks"]
	else:
		# Old on-disk macros predate this state. Zero is imperfect for a midair
		# checkpoint but deterministic; inheriting the unrelated live player's
		# current airborne time would make the same old macro vary run to run.
		_practice_playback_air_hold_ticks = 0
	if snap.has("practice_playback_air_hold_dir"):
		_practice_playback_air_hold_dir = snap["practice_playback_air_hold_dir"]
	else:
		_practice_playback_air_hold_dir = 0.0
	# snap["play_time"] is intentionally NOT written back. Goober Dash's
	# time-trial replay recorder timestamps native input against this global
	# clock; rewinding it at checkpoint boundaries created non-monotonic
	# uploaded replays (clock jumping 5 -> 7 -> 5, deaths followed by apparent
	# teleports, and occasional resets toward zero). A player checkpoint may
	# restore player state, but it must never rewrite the race/server clock.
	# TELEPORT ACCURACY: the game's own respawn_player() (WPGame.gd) always
	# finishes a reposition with player._reset_object() -- confirmed from
	# the real game's source, called as the very last step after every
	# other field is set, exactly like here. We don't know everything it
	# does internally (native/compiled), but skipping it meant every
	# checkpoint restore this tool ever did (Checkpoints load/edit, Macro
	# Bot Mode's auto-respawn, its segment-boundary resync, its Play Macro
	# restore-to-checkpoint-0) was reproducing an approximation of a real
	# respawn rather than the real thing -- almost certainly a source of
	# the visible teleport/position-off-by-a-lot glitches, on top of the
	# body.position bug fixed above. Calling it here brings every one of
	# those restores in line with the one and only way the game itself
	# ever legitimately teleports a live player mid-run.
	#
	# REVISED (2026-08-30) -- respawn_player() is NOT the only state a real
	# player sits in. The actual GooberDash source (level-start setup code,
	# WPGame.gd) shows every player getting parked at the start of a round
	# with `player.alive = false`, `player.body.enabled = false`, and
	# `player.dead_counter = <ticks until the hold ends>` -- exactly the
	# "wait a few seconds before you can move" hold, and it explains a
	# confirmed repro this session: a checkpoint placed mid-hold, at the
	# very start of a run, replayed with the player free-falling from tick
	# 0 while the live recording sat bit-for-bit frozen (position AND
	# velocity unchanged) for many ticks straight -- exactly what a
	# disabled (unsimulated) Box2D body looks like next to a freshly-
	# restored, simulated one. Searching the ENTIRE decompiled source turns
	# up exactly one call to _reset_object() anywhere, and it's this exact
	# line -- respawn_player()'s own, always preceded by re-enabling
	# everything (alive=true, body.enabled=true, dead_counter=0) first. The
	# real game never calls _reset_object() on a still-disabled player --
	# the level-start code that parks them there doesn't call it at all.
	# This function used to call it here unconditionally regardless, which
	# is a state transition the real game itself never performs. Since
	# body_enabled was already restored above (matching the checkpoint --
	# see the block near `had_body`), skipping _reset_object() whenever
	# that came back false matches the real game's own behavior exactly,
	# rather than guessing at what _reset_object() does to a body it was
	# never designed to be called on.
	#   (An earlier same-day attempt tried forcing the physics body to
	# SLEEP instead, theorizing the freeze was a Box2D sleep/wake artifact.
	# A Restore Drift Diagnostics report confirmed the forced-sleep write
	# genuinely stuck on this build -- read back immediately as applied --
	# yet the fall afterward was byte-for-byte identical to before the
	# attempt. That ruled sleep out cleanly: whatever drives gravity here
	# isn't gated on Box2D's own sleep flag, so that attempt was removed
	# rather than left in as dead weight now that the real mechanism is
	# confirmed from source instead of guessed at.
	var velocity_after_reset_object: Vector2 = velocity_before_reset_object
	# Deliberately reads the SAME snap.get("body_enabled", true) expression
	# used above to set p.body.enabled, not p.body_enabled directly -- a
	# snapshot that doesn't include "body_enabled" at all (an older/partial
	# checkpoint) leaves p.body_enabled un-touched (whatever it happened to
	# be from before this restore) while p.body.enabled still gets the
	# true fallback; keying off p.body_enabled here could read that stale
	# leftover value and wrongly skip _reset_object() on a body that was
	# just correctly (re-)enabled.
	var reset_object_called: bool = snap.get("body_enabled", true)
	if reset_object_called:
		p._reset_object()
		velocity_after_reset_object = p.linear_velocity
	_arm_restore_drift_watch(p, snap, velocity_before_reset_object, velocity_after_reset_object, reset_object_called) # no-op unless Restore Drift Diagnostics is toggled on -- see that function for what/why
	_reset_renderer_smoothing(p)
	_snap_playback_visual_track(p)
	_begin_visual_seam_blend(visual_position_before_restore, p.position)
	# Keep the legacy diagnostic fingerprints scoped to the current restore
	# boundary. Global clock fields are no longer written anywhere in this
	# restore; they remain observation-only metadata (see the comment above).
	_live_tick_last_play_time = -1.0
	# THE TWENTY-THIRD-PASS FIX (2026-08-31, later) -- corrects THE TWENTY-
	# SECOND-PASS FIX's own choke-point reset, which used the same -1.0
	# sentinel as the line above and turned out to reopen the exact bug it
	# was fixing: a real report showed the tick-1 frozen-duplicate symptom
	# STILL happening even with that pass's phantom-call check active (3
	# OTHER phantom calls elsewhere in the same run WERE correctly caught,
	# proving the check itself works) -- because -1.0 means "no usable
	# baseline, process unconditionally," and a catch-up-burst call that
	# lands IMMEDIATELY after a checkpoint-0/boundary restore -- zero real
	# ticks elapsed since play_time was just rewound -- got treated as
	# automatically valid instead of being fingerprinted at all. Unlike the
	# live-recording baseline above (which genuinely can't know what play_
	# time to expect next, since a restore there can happen from a
	# completely different, asynchronous call site relative to recording's
	# own capture cadence), a playback-side restore ALWAYS happens INSIDE
	# this exact function -- so the true next-expected baseline is knowable
	# immediately: whatever play_time reads right now, at the end of this
	# same restore. Storing that instead of -1.0 means the very next call,
	# even one from the same catch-up burst with zero real ticks elapsed,
	# compares against a real, correct value and gets caught as phantom
	# exactly like any other -- closing the gap instead of only narrowing
	# it.
	var g_for_playback_baseline: = _find_game()
	if g_for_playback_baseline != null and g_for_playback_baseline.wp_game_data != null and ("play_time" in g_for_playback_baseline.wp_game_data):
		_playback_tick_last_play_time = g_for_playback_baseline.wp_game_data.play_time
	else:
		_playback_tick_last_play_time = -1.0


# THE EVIDENCE: Divergence Diagnostics (two independent, fully-covered
# live-vs-replay comparisons) showed a reproducible ~1.5 unit downward
# position drift starting 2-3 ticks after EVERY checkpoint restore, with
# inputs matching exactly and the starting position identical -- i.e. not a
# Macro Bot Mode bug, but Box2D itself settling after a hard teleport. A
# body arriving at a resting position via continuous simulation carries
# resolved contact/manifold state into that rest; a body arriving via a hard
# `position =` assignment (a teleport, which is what every restore here is)
# does not, and can visibly fall/settle for a couple of physics ticks before
# new ground contact re-establishes.
# THE IDEA: when checkpoint 0 was ALREADY at rest (near-zero velocity,
# grounded), hold the replayed input at zero for a few ticks before playback
# visibly begins, giving Box2D room to establish contact before frame 0.
# This is deliberately startup-only. It previously ran at every internal
# stitch boundary, where it inserted a neutral physics tick, visibly paused
# the macro, and let the body move before the next recorded frame. The
# authoritative per-frame state path now handles internal boundary accuracy
# without adding any unrecorded time.
# THE GUARD (read this before touching either function below): the FIRST
# version of this shipped with an infinite-loop bug -- arming settling
# unconditionally on every boundary restore, with no way to tell "just
# armed this boundary" apart from "already finished settling this boundary
# and now revisiting the same unmoved _practice_playback_index" -- so once
# settling ended, the very next tick recomputed the SAME boundary_idx
# (nothing had advanced it) and re-armed forever. A first patch only guarded
# the case where that boundary was also the LAST one, which missed every
# mid-macro checkpoint -- any at-rest checkpoint anywhere but the very end
# still looped forever, which is what actually reached the user as a
# real crash (34000+ nodes). The fix is `_practice_playback_settled_boundary`
# at the call site in _advance_practice_playback(). Settling is now only
# armed for checkpoint 0 and remains hard-capped, so it cannot re-arm at an
# internal boundary or reveal a stitch with a pause.
func _snapshot_is_at_rest(snap: Dictionary) -> bool:
	var v: Vector2 = snap.get("linear_velocity", Vector2.ZERO)
	if v.length() >= PLAYBACK_SETTLE_VELOCITY_EPSILON:
		return false
	return snap.get("stick_to_ground_timer", 0.0) > 0.0


func _arm_playback_settle(player: WPPlayer, snap: Dictionary) -> void:
	# INSTRUMENTATION for the "just a wrong/inconsistent delay" theory: tags
	# the restore-drift watch this exact restore already armed (see
	# _arm_restore_drift_watch(), called from _restore_player() immediately
	# before this function runs every time -- checkpoint 0's own call site
	# and the boundary_idx>0 path both restore-then-arm-settle back to back,
	# so _restore_drift_watches.back() is always this restore's own watch
	# here, never some other one) with whether Playback Settle armed at all,
	# and -- once the hold actually ends, see the hold branch in
	# _advance_practice_playback() -- how many ticks it held for and whether
	# it gave up on the hard tick cap (PLAYBACK_SETTLE_MAX_TICKS) instead of
	# genuinely detecting a stable position. A settle that keeps hitting the
	# cap without ever reading "stable" IS an inconsistent, position-
	# dependent startup delay in every meaningful sense -- this is how we'd
	# actually see that, instead of guessing at it from the outside.
	if not _restore_drift_watches.empty():
		_restore_drift_watches.back()["settle_armed"] = _snapshot_is_at_rest(snap)
	if not _snapshot_is_at_rest(snap):
		_practice_playback_settling = false
		return
	_practice_playback_settling = true
	_practice_playback_settle_ticks_left = PLAYBACK_SETTLE_MAX_TICKS
	_practice_playback_settle_last_position = player.position


# DISPLAY ACCURACY: the game's own WPPlayerRenderer (renderers/WPPlayerRenderer.gd,
# _compute_position()) does its own client-side smoothing SEPARATE from the
# player's actual simulated position -- it's built to hide small network
# corrections, not to represent deliberate teleports. It compares where the
# player "should" be (prev_position + prev_velocity * tick_rate) against
# where it actually now is; if that distance lands between 25 and 100 units
# it starts a smooth_damp glide from the old spot to the new one instead of
# snapping, and once started it keeps gliding for as long as it stays more
# than 1 unit off target. A real level checkpoint-to-checkpoint respawn is
# usually a big enough jump to land above that 100-unit ceiling and snap
# instantly, which is almost certainly why this never shows up in normal
# play -- but Macro Bot Mode checkpoints are typically placed close together
# on purpose (that's the point of GD-style segment practice), so a restore
# lands squarely in that 25-100 "please smooth this" zone the renderer
# mistakes our deliberate teleport for a minor correction to glide through.
# That's what "the macro doesn't display correctly" almost certainly is:
# the character visibly sliding to the checkpoint instead of appearing there
# instantly, on every restore.
#   is_smoothing and smoothed_p are plain (non-native) vars declared right
# in WPPlayerRenderer.gd, so writing them is guaranteed to take. prev_position
# and prev_velocity are inherited from its native base class and aren't
# something we can fully verify from the outside -- writing them is
# best-effort (a dynamic Object.set() on an untyped Node reference, which
# Godot no-ops harmlessly rather than erroring if the property turns out not
# to be externally settable), not a guaranteed fix on its own. Together they
# should stop both a smoothing glide already in progress from continuing
# (is_smoothing/smoothed_p, guaranteed) and a fresh one from starting on the
# very next frame because prev_position/prev_velocity still reflect where
# the player was a moment ago (prev_position/prev_velocity, best-effort).
func _reset_renderer_smoothing(player: WPPlayer) -> void:
	var renderer: = _find_player_renderer(player)
	if renderer == null:
		return
	if renderer.get("is_smoothing") != null:
		renderer.is_smoothing = false
	if renderer.get("smoothed_p") != null:
		renderer.smoothed_p = player.linear_velocity
	if renderer.get("prev_position") != null:
		renderer.prev_position = player.position
	if renderer.get("prev_velocity") != null:
		renderer.prev_velocity = player.linear_velocity


# A real hard restore is still required at playback start and for old macros
# which have no per-frame state. Reset the render-only history at the same
# instant so its next interpolation interval starts at the restored point,
# rather than blending from the previous segment's final rendered sample.
func _snap_playback_visual_track(player: WPPlayer) -> void:
	if not _practice_playback or player == null:
		return
	_practice_playback_visual_valid = true
	_practice_playback_visual_player_id = player.get_instance_id()
	_practice_playback_visual_previous = player.position
	_practice_playback_visual_current = player.position
	_practice_playback_visual_renderer = _find_player_renderer(player)
	_practice_playback_visual_camera = _find_playback_camera()
	_practice_playback_visual_sample_usec = OS.get_ticks_usec()


func _begin_visual_seam_blend(from_position: Vector2, to_position: Vector2) -> void:
	if not _practice_playback or not _visual_seam_polish_enabled:
		return
	var correction := from_position - to_position
	if correction.length() <= DIAG_POSITION_EPSILON:
		return
	if correction.length() > VISUAL_SEAM_MAX_DISTANCE:
		# A large correction should remain an honest snap; visually tweening a
		# goober through half the level would be worse than the seam and could
		# conceal a genuinely invalid segment.
		_visual_seam_filter_remaining = 0.0
		_visual_seam_output_valid = false
		return
	# Start the short low-pass window from the exact last displayed point. This
	# smooths the correction's direction/acceleration change without adding an
	# extra positional offset on top of the ordinary physics interpolation.
	_visual_seam_filter_position = _visual_seam_last_output if _visual_seam_output_valid else from_position
	_visual_seam_filter_remaining = VISUAL_SEAM_BLEND_SECONDS


# A checkpoint and the following segment's frame 0 are already identical in
# the saved macro. The remaining visible seam came from WHEN that identical
# state was written: the early playback callback corrects player/body state,
# then native physics advances it and the following tick corrects it again.
# Sampling that post-physics body made the render path alternate between the
# recorded point and the newly-drifted point -- a visible sawtooth even though
# gameplay itself was repaired each tick. Render format-3 macros from their
# authoritative recorded positions instead. This remains visual-only and one
# physics sample behind; legacy input-only macros retain the old body sample.
func _capture_playback_visual_sample() -> void:
	if not _practice_playback:
		return
	var player: = _get_local_player()
	if player == null:
		_reset_playback_visual_track()
		return
	var sampled_position: Vector2 = player.position
	var sampled_frame_index: int = _practice_playback_index - 1
	if sampled_frame_index >= 0 and sampled_frame_index < _practice_playback_frames.size():
		var sampled_frame = _practice_playback_frames[sampled_frame_index]
		if typeof(sampled_frame) == TYPE_DICTIONARY and sampled_frame.has(PRACTICE_FRAME_STATE_KEY):
			var sampled_state = sampled_frame[PRACTICE_FRAME_STATE_KEY]
			if typeof(sampled_state) == TYPE_DICTIONARY:
				if sampled_state.has("position"):
					sampled_position = sampled_state["position"]
				# Native dash input and continuous movement are dispatched by two
				# different paths. Reassert the recorded facing after native physics
				# so a left dash cannot be rendered with the prior right-facing pose.
				if sampled_state.has("facing_dir"):
					player.facing_dir = bool(sampled_state["facing_dir"])
				if _practice_playback_dash_direction_valid and float(sampled_state.get("dash_timer", 0.0)) > 0.0:
					player.facing_dir = _practice_playback_dash_direction
				var was_dash_held: bool = false
				if sampled_frame_index > 0:
					var previous_frame = _practice_playback_frames[sampled_frame_index - 1]
					if typeof(previous_frame) == TYPE_DICTIONARY:
						was_dash_held = bool(previous_frame.get(ACTION_DASH, false))
				if bool(sampled_frame.get(ACTION_DASH, false)) and not was_dash_held and sampled_frame.has(PRACTICE_DASH_DIRECTION_KEY):
					player.facing_dir = bool(sampled_frame[PRACTICE_DASH_DIRECTION_KEY])
	var player_id: int = player.get_instance_id()
	if not _practice_playback_visual_valid or player_id != _practice_playback_visual_player_id:
		_practice_playback_visual_valid = true
		_practice_playback_visual_player_id = player_id
		_practice_playback_visual_previous = sampled_position
		_practice_playback_visual_current = sampled_position
		_practice_playback_visual_renderer = _find_player_renderer(player)
		_practice_playback_visual_camera = _find_playback_camera()
		_practice_playback_visual_sample_usec = OS.get_ticks_usec()
		return
	_practice_playback_visual_previous = _practice_playback_visual_current
	_practice_playback_visual_current = sampled_position
	_practice_playback_visual_sample_usec = OS.get_ticks_usec()


# Called from TASPostPhysicsGuard's very-late idle callback, after both the
# native player renderer and GameCamera have updated themselves. Overriding
# both together is important: GameCamera follows renderer.position_node, so
# fixing only the goober would leave the entire level/camera doing the same
# checkpoint shake around a stable sprite.
func _post_renderer_stitch_guard() -> void:
	if not _practice_playback:
		if _practice_playback_visual_valid:
			var ending_player: = _get_local_player()
			if ending_player != null:
				_reset_renderer_smoothing(ending_player)
			_reset_playback_visual_track()
		return
	if not _practice_playback_visual_valid:
		return
	var player: = _get_local_player()
	if player == null or player.get_instance_id() != _practice_playback_visual_player_id:
		_reset_playback_visual_track()
		return
	if _practice_playback_visual_renderer == null or not is_instance_valid(_practice_playback_visual_renderer):
		_practice_playback_visual_renderer = _find_player_renderer(player)
	if _practice_playback_visual_camera == null or not is_instance_valid(_practice_playback_visual_camera):
		_practice_playback_visual_camera = _find_playback_camera()
	# This build does not expose a reliable interpolation fraction on every
	# renderer backend. Use the actual wall time since the completed sample;
	# otherwise the value often stays at 1 and playback visibly stair-steps.
	var tick_usec := 1000000.0 / max(1.0, float(Engine.iterations_per_second))
	var interpolation := clamp(float(OS.get_ticks_usec() - _practice_playback_visual_sample_usec) / tick_usec, 0.0, 1.0)
	var visual_position: Vector2 = _practice_playback_visual_previous.linear_interpolate(_practice_playback_visual_current, interpolation)
	if _visual_seam_polish_enabled:
		var polish_delta := get_process_delta_time()
		if _visual_seam_filter_remaining > 0.0:
			var follow_alpha := 1.0 - exp(-polish_delta / 0.028)
			_visual_seam_filter_position = _visual_seam_filter_position.linear_interpolate(visual_position, clamp(follow_alpha, 0.0, 1.0))
			visual_position = _visual_seam_filter_position
			_visual_seam_filter_remaining = max(0.0, _visual_seam_filter_remaining - polish_delta)
		else:
			_visual_seam_filter_position = visual_position
	_visual_seam_last_output = visual_position
	_visual_seam_output_valid = true
	var renderer: = _practice_playback_visual_renderer
	var renderer_delta: = Vector2.ZERO
	var has_renderer_delta: = false
	if renderer != null and is_instance_valid(renderer):
		# Prevent the renderer's own correction-oriented smooth_damp from
		# carrying a stale boundary offset into the following frames.
		if renderer.get("is_smoothing") != null:
			renderer.is_smoothing = false
		if renderer.get("smoothed_p") != null:
			renderer.smoothed_p = player.linear_velocity
		if renderer.get("prev_position") != null:
			renderer.prev_position = player.position
		if renderer.get("prev_velocity") != null:
			renderer.prev_velocity = player.linear_velocity
		var position_node = renderer.get("position_node")
		if position_node != null and is_instance_valid(position_node):
			renderer_delta = visual_position - position_node.position
			has_renderer_delta = true
			position_node.position = visual_position
		var ui_node = renderer.get("ui_node")
		if ui_node != null and is_instance_valid(ui_node):
			ui_node.rect_position = visual_position
	var camera: = _practice_playback_visual_camera
	if camera != null and is_instance_valid(camera) and has_renderer_delta:
		# GameCamera already ran at this point and may have applied its own
		# offsets/smoothing. Move its completed result by exactly the same
		# render-only correction as the player instead of replacing it with the
		# player's absolute position. Replacing it (and zeroing its smooth-damp
		# velocity every idle frame) made the camera alternate between its native
		# result and ours, which presented as a small shake at stitch boundaries.
		camera.position += renderer_delta
		camera.force_update_scroll()


func _find_playback_camera() -> Camera2D:
	var game: = _find_game()
	if game == null or game.get_parent() == null:
		return null
	return game.get_parent().get_node_or_null("Camera2D") as Camera2D


func _reset_playback_visual_track() -> void:
	_practice_playback_visual_valid = false
	_practice_playback_visual_player_id = 0
	_practice_playback_visual_previous = Vector2.ZERO
	_practice_playback_visual_current = Vector2.ZERO
	_practice_playback_visual_renderer = null
	_practice_playback_visual_camera = null
	_practice_playback_visual_sample_usec = 0
	_visual_seam_filter_position = Vector2.ZERO
	_visual_seam_last_output = Vector2.ZERO
	_visual_seam_filter_remaining = 0.0
	_visual_seam_output_valid = false


# Duck-typed search for the local player's renderer node (WPPlayerRenderer,
# or whatever future class fills that role) -- no hard class dependency, so
# a scene where it doesn't exist (e.g. this stub/test context, or a future
# build that renames/removes it) just means _reset_renderer_smoothing() is a
# no-op rather than a crash. Matched by get_network_object() identity rather
# than object_id, since that's the most direct "this renders THIS player"
# check available and mirrors how the game's own renderer code (see
# cheers_emit_confetti() in WPPlayerRenderer.gd) fetches its own player.
func _find_player_renderer(player: WPPlayer) -> Node:
	return _search_for_player_renderer(get_tree().root, player)


func _search_for_player_renderer(node: Node, player: WPPlayer) -> Node:
	if node == null:
		return null
	if node.has_method("get_network_object") and node.has_method("get_object_id"):
		if node.get_network_object() == player:
			return node
	for child in node.get_children():
		var found: Node = _search_for_player_renderer(child, player)
		if found != null:
			return found
	return null


# ----------------------------------------------------------------------
#  Macro Bot Mode (GD-style segment practice / macro splicing)
#  -- see the PRACTICE CHECKPOINTS block in the header doc-comment above.
# ----------------------------------------------------------------------
func _on_toggle_practice_pressed() -> void:
	if _practice_active or _practice_start_waiting:
		_practice_start_waiting = false
		_stop_practice_mode()
		return
	# THE FIX (2026-08-30, fourth pass): checkpoint 0's readiness check
	# (_player_ready_for_checkpoint()) and its snapshot (_snapshot_player())
	# used to both happen right here, synchronously, inside this idle-frame
	# Button "pressed" handler -- the exact same class of mistake
	# _on_play_practice_macro_pressed() made with ITS restore (see the big
	# comment there, and _watch_practice_start_request() below). This button
	# doesn't mutate the player the way that one did, so there's no doubled-
	# gravity artifact here -- but the READ of alive/body_enabled this button
	# used to do was still one idle frame removed from _physics_process()'s
	# own read of that same player on the very next physics tick, which is
	# what actually becomes tick 0 of the recorded log. A real divergence
	# report caught the two disagreeing: this button's idle-frame check found
	# the player ready and let Start through, snapshotting checkpoint 0 as
	# alive=true/body_enabled=true, yet the FIRST tick _physics_process()
	# went on to actually record moments later read body_enabled=FALSE --
	# still genuinely inside the level's opening hold. That's precisely the
	# "still-disabled checkpoint" the big comment on _player_ready_for_checkpoint()
	# warns silently corrupts the whole replay from tick 0 on, and precisely
	# why this button's own idle-frame reading of that state can't be trusted
	# to make the call.
	#   The fix: don't check or snapshot anything from this idle-frame
	# handler at all. Just arm a wait, and let _watch_practice_start_request()
	# -- called from _physics_process(), every physics tick, the exact same
	# footing the recording loop right below it already stands on -- do the
	# actual readiness check and hand off to _start_practice_mode() the
	# instant it agrees, tick for tick, no gap. If the player's already
	# ready this fires on the very next physics tick (imperceptible); if not,
	# it just keeps waiting instead of making you keep re-clicking Start --
	# Auto-Activate always worked this way (see _watch_practice_auto_activate()
	# below), and this folds the manual button onto that exact same
	# physics-tick-driven wait instead of a second, idle-frame copy of it.
	_practice_start_waiting = true
	_practice_start_reason = ""
	_log_action("Macro Bot Mode: arming -- will start recording the instant you can actually move", null)
	_refresh_practice_ui()


# Called every physics tick from _physics_process() -- see the big comment
# on _on_toggle_practice_pressed() for why this can't run from an idle frame.
# Shared by both ways a start can get armed: the manual Start button above,
# and Auto-Activate's own fresh-level-entry edge-detect in
# _watch_practice_auto_activate() below (which only sets the wait flags;
# this is the one place that actually watches for ready and fires).
#
# THE SEVENTH-PASS FIX (2026-08-30): a Divergence Diagnostics report caught
# checkpoint 0 snapshotted as alive=true/body_enabled=true (correctly passing
# _player_ready_for_checkpoint()), yet the very NEXT tick of that same LIVE
# recording read body_enabled=FALSE again -- the level's own native logic
# re-disabling the body for several more ticks before real gameplay actually
# began. So the tick this fired on was only ready for exactly one tick, not
# genuinely, stably ready -- and a replay restoring to that snapshot has no
# way to reproduce whatever native, one-time event caused that second
# disable (it isn't in any field this tool captures), so it just keeps
# falling under gravity instead, which is precisely the doubled-velocity
# signature the fifth-pass fix's evidence showed. Requiring
# PRACTICE_READY_STABLE_TICKS_REQUIRED consecutive ready ticks before
# actually trusting "ready" and snapshotting means a transient one-tick
# flicker like that gets waited out instead of latched onto -- by the time
# the count reaches the threshold, whatever native transition was still
# settling has had a few extra ticks to finish for good.
func _watch_practice_start_request() -> void:
	if not _practice_start_waiting:
		_practice_ready_stable_ticks = 0
		return
	if _practice_playback:
		# Never start recording over an in-progress Play Macro run -- wait it
		# out rather than firing mid-playback (mirrors the exact same guard
		# _watch_practice_auto_activate() already had for this).
		_practice_ready_stable_ticks = 0
		return
	var player: = _get_local_player()
	if player == null or not _player_ready_for_checkpoint(player) or not _game_ready_for_practice_start():
		_practice_ready_stable_ticks = 0 # any not-ready tick resets the count -- see THE SEVENTH-PASS FIX above
		return # keep waiting, tick by tick -- nothing to check or snapshot yet
	_practice_ready_stable_ticks += 1
	if _practice_ready_stable_ticks < PRACTICE_READY_STABLE_TICKS_REQUIRED:
		return # looked ready this tick, but not for long enough yet -- keep waiting
	_practice_ready_stable_ticks = 0
	_practice_start_waiting = false
	_practice_auto_activate_waiting_for_alive = false # whichever path armed this, the wait is over now -- Auto-Activate re-arms its own on the next fresh-attempt edge (_watch_practice_auto_activate() above), it doesn't need to keep polling once this fires
	if _practice_active:
		# Already running (armed mid-attempt, or a leftover from before a
		# fresh level/attempt was detected) -- restart clean on top of a
		# genuinely new attempt rather than keeping stale checkpoints.
		_stop_practice_mode()
	_start_practice_mode(_practice_start_reason)


func _start_practice_mode(reason_suffix: String = "") -> void:
	var player: = _get_local_player()
	if player == null:
		_log_action("Macro Bot Mode: no local player found -- get into a level first", null)
		return
	if not _player_ready_for_checkpoint(player):
		# Same guard _on_place_practice_checkpoint_pressed() already has for
		# every OTHER checkpoint -- checkpoint 0 needs it too. Snapshotting a
		# dead player here means every future Play Macro restores that dead
		# state as its very first action and immediately reports "died
		# mid-macro (frame 0)", which looks impossible because it is: nothing
		# about the run caused it. Snapshotting a player who's alive but
		# still in the level's initial "wait a few seconds" hold
		# (body_enabled=false) is worse and less obvious -- see the big
		# comment on _player_ready_for_checkpoint() for why THAT one silently
		# corrupts the entire replay from tick 1 on instead of failing loudly.
		# (Auto-Activate has its own, separate wait for this -- see
		# _watch_practice_auto_activate() -- this covers the manual Start
		# button.)
		var why: String = "while dead -- wait until you respawn" if not player.alive else "until you can actually move -- you're still in the level's opening hold"
		_log_action("Macro Bot Mode: can't start %s, then press Start again" % [why], null)
		return
	if not _game_ready_for_practice_start():
		_log_action("Macro Bot Mode: can't start during the level-start handoff -- wait a moment, then press Start again", null)
		return
	_clear_practice_data()
	_practice_active = true
	_ensure_game_over_submission_guard_runs_first()
	_practice_prev_alive = player.alive
	var snap: = _snapshot_player(player)
	_practice_checkpoints.append(snap)
	_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	_restyle_practice_markers()
	_log_action("Macro Bot Mode: ON%s -- checkpoint 0 placed at your current position" % reason_suffix, null)
	_refresh_practice_ui()


func _stop_practice_mode() -> void:
	_practice_active = false
	_practice_awaiting_native_respawn = false # THE NINTH-PASS FIX -- don't leave a wait armed with nothing left watching it
	_log_action("Macro Bot Mode: OFF (%d checkpoint(s) kept -- Play/Save still work)" % [max(_practice_checkpoints.size() - 1, 0)], null)
	_refresh_practice_ui()


func _is_normal_linked_time_trial_scene(scene: Node) -> bool:
	if scene == null or not ("parameters" in scene):
		return false
	var parameters = scene.get("parameters")
	if parameters == null or not ("level_id" in parameters) or str(parameters.get("level_id")).empty():
		return false
	# TimeTrial (0) and ReplayGhost (1) are both playable/submit-capable race
	# modes. Watching a Replay (2) and a level's required PrepublishRun (3)
	# retain stock behavior.
	if not ("mode" in parameters):
		return false
	var mode: int = int(parameters.get("mode"))
	return mode == 0 or mode == 1


func _finalize_practice_recording_at_finish(player: WPPlayer) -> void:
	if player == null or _practice_checkpoints.empty():
		return
	# Reaching the goal is the natural last checkpoint.  Commit the tail so a
	# user can Save immediately after dismissing the popup instead of losing
	# every frame since their last manually placed checkpoint.
	if not _practice_current_segment.empty():
		_practice_segments.append(_practice_current_segment.duplicate(true))
		_diag_live_committed.append(_diag_live_current.duplicate(true))
		var snap: = _snapshot_player(player)
		_practice_checkpoints.append(snap)
		_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
		_restyle_practice_markers()
	_practice_current_segment = []
	_diag_live_current = []
	_practice_deaths_this_segment = 0
	_practice_place_pending = false
	_practice_place_ready_stable_ticks = 0


# This listener is deliberately ordered before TimeTrialGameplayScene's stock
# listener.  The stock code submits whenever the finish beats the cached PB;
# merely stopping replay recording is not enough.  For this one signal dispatch
# we also make the loaded level fail its RACE eligibility check, then restore
# the original type on the deferred call after all signal listeners have run.
func _on_tas_game_over_before_native(winner_id: int) -> void:
	if not _practice_active:
		return
	var game: = _find_game()
	var scene: = get_tree().current_scene
	if game == null or not _is_normal_linked_time_trial_scene(scene):
		return
	if game.has_method("is_local_player") and not game.is_local_player(winner_id):
		return

	var player: = _get_local_player()
	_finalize_practice_recording_at_finish(player)
	_practice_active = false
	_practice_awaiting_native_respawn = false
	game.set_replay_status(NetworkGame.REPLAY_STATUS_NONE)

	var loaded_level = null
	if ("level" in game) and game.get("level") != null and ("loaded_level" in game.get("level")):
		loaded_level = game.get("level").get("loaded_level")
	if loaded_level != null and ("level_type" in loaded_level):
		var original_level_type = loaded_level.get("level_type")
		loaded_level.set("level_type", -1)
		call_deferred("_restore_macro_recording_level_type", loaded_level, original_level_type)

	_log_action("Replay recorded locally -- the recording run was not submitted to the leaderboard", null)
	_refresh_practice_ui()
	call_deferred("_show_native_notify", "REPLAY RECORDED", "Replay recorded.\n\nIt is ready in Macro Bot and was not submitted to the leaderboard.")


func _restore_macro_recording_level_type(loaded_level, original_level_type) -> void:
	if loaded_level != null and is_instance_valid(loaded_level) and ("level_type" in loaded_level):
		loaded_level.set("level_type", original_level_type)


func _show_native_notify(title: String, message: String) -> void:
	_show_responsive_popup(title, message)


func _show_changelog_if_needed() -> void:
	var seen_version := str(SavedSettings.get_value(SETTING_CHANGELOG_VERSION, ""))
	if seen_version == GOOBPLAYABILITY_VERSION:
		return
	SavedSettings.set_value(SETTING_CHANGELOG_VERSION, GOOBPLAYABILITY_VERSION)
	var message := "Version %s\n\n" % GOOBPLAYABILITY_VERSION
	message += "• Window resizing now keeps the chosen top-left position.\n"
	message += "• Timeline freecam keeps the native SDF/themed level presentation active and includes Center and Reset controls.\n"
	message += "• Cosmetic catalogs receive a bounded readiness retry.\n"
	message += "• Replay Self-Test rejects incomplete diagnostic coverage and identifies the first failing system.\n"
	message += "• Moving platforms and animations are included in Debug Mode determinism checks.\n"
	message += "• Optional verified updates and one-click rollback are available in Goober Dash Settings.\n"
	message += "• Fixed a resize deadlock in the shared window geometry helper that could jump the Timeline or Sandbox panel to a tiny size and lock it there.\n"
	message += "• Fixed levels rendering as hollow shapes with a colored outline and no terrain fill -- this happens when a block/ramp is too thin for the level's theme to round its corners and draw its stroke layers. Goobplayability now always renders every block/ramp's own shape underneath the normal terrain, so nothing is ever left hollow (a tiny square corner may occasionally peek out past a rounded terrain corner as a side effect).\n"
	message += "• Fixed physics blocks and ice blocks still going invisible in the Timeline Editor after jump zones and sawblades were already fixed by the previous update -- physics blocks had their own script actively fighting the fix every frame, which is now turned off during Timeline Editor preview, and ice blocks get an extra targeted safety net on top of the existing fix.\n\n"
	message += "• Extended the invisible-object fix to every remaining object type in the game (backgrounds, cannons, checkpoints, disappearing blocks, gravity fields, lasers, music blocks, pits, rechargers, signs, the start/finish line, and more) instead of only the specific ones reported so far -- scoped strictly to the Timeline Editor preview, so anything that's meant to disappear or change during actual gameplay (like disappearing blocks) still behaves normally when actually playing.\n\n"
	message += "The TAS client is now named Goobplayability. This changelog appears once for each released version."
	_show_responsive_popup("GOOBPLAYABILITY — WHAT'S NEW", message)


func _show_responsive_popup(title: String, message: String, accept_text := "OK", accept_method := "_close_tool_popup", cancel_text := "") -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer):
		_tool_popup_layer.queue_free()
	_tool_popup_layer = CanvasLayer.new()
	_tool_popup_layer.layer = 260
	_tool_popup_layer.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(_tool_popup_layer)
	var root := Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_tool_popup_layer.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.72)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(center)
	var viewport_size: Vector2 = get_viewport().size
	var estimated_lines := message.count("\n") + int(ceil(float(message.length()) / 54.0)) + 2
	var panel := PanelContainer.new()
	var max_popup_width := max(300.0, min(920.0, viewport_size.x - 36.0))
	var max_popup_height := max(240.0, min(720.0, viewport_size.y - 36.0))
	var popup_width := clamp(viewport_size.x * 0.64, min(520.0, max_popup_width), max_popup_width)
	var popup_height := clamp(190.0 + float(estimated_lines) * 31.0, min(300.0, max_popup_height), max_popup_height)
	panel.rect_min_size = Vector2(popup_width, popup_height)
	panel.add_stylebox_override("panel", _make_flat_style(Color(0.015, 0.12, 0.24, 0.98), COLOR_BLUE, 5, 28))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_constant_override("separation", 16)
	margin.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.align = Label.ALIGN_CENTER
	title_label.autowrap = true
	title_label.add_font_override("font", _title_font)
	title_label.add_color_override("font_color", COLOR_WHITE)
	column.add_child(title_label)
	var separator := HSeparator.new()
	column.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.text = message
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_font_override("normal_font", _body_font)
	body.add_color_override("default_color", COLOR_WHITE)
	body.rect_min_size = Vector2(max(420.0, panel.rect_min_size.x - 76.0), max(110.0, float(estimated_lines) * 31.0))
	scroll.add_child(body)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGN_CENTER
	action_row.add_constant_override("separation", 14)
	column.add_child(action_row)
	if not cancel_text.empty():
		var cancel := _make_button(cancel_text, COLOR_BLUE, 220)
		cancel.rect_min_size.y = 58
		cancel.connect("pressed", self, "_close_tool_popup")
		action_row.add_child(cancel)
	var okay := _make_button(accept_text, COLOR_PINK, 220)
	okay.rect_min_size.y = 58
	okay.connect("pressed", self, accept_method)
	action_row.add_child(okay)


func _show_update_choice_popup(title: String, message: String) -> void:
	_show_responsive_popup(title, message, "DOWNLOAD & INSTALL", "_on_updater_install_confirmed", "NOT NOW")


func _show_rollback_choice_popup() -> void:
	_show_responsive_popup("ROLL BACK GOOBPLAYABILITY?", "This restores the scripts backed up immediately before the last updater installation.\n\nNo macros, settings, diagnostics, or unrelated Goober Dash files are changed. Restart the game afterward.", "RESTORE BACKUP", "_on_updater_rollback_confirmed", "CANCEL")


func _close_tool_popup() -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer):
		_tool_popup_layer.queue_free()
	_tool_popup_layer = null


func _unhandled_input(event: InputEvent) -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer) and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		_close_tool_popup()
		get_tree().set_input_as_handled()


func _clear_practice_data() -> void:
	for m in _practice_markers:
		if is_instance_valid(m):
			m.queue_free()
	_practice_markers.clear()
	_practice_checkpoints.clear()
	_practice_segments.clear()
	_practice_current_segment.clear()
	_diag_live_committed.clear()
	_diag_live_current.clear()
	_practice_deaths_this_segment = 0
	_practice_awaiting_native_respawn = false # THE NINTH-PASS FIX -- same reasoning as _stop_practice_mode(); a fresh checkpoint set shouldn't inherit a stale wait from before
	_practice_native_respawn_wait_ticks = 0
	# THE THIRTEENTH-PASS FIX -- fresh baseline and fresh counts for the new
	# recording session about to start; see _live_tick_last_play_time's big
	# comment.
	_live_tick_last_play_time = -1.0
	_live_tick_fingerprint_normal = 0
	_live_tick_fingerprint_phantom = 0
	_live_tick_fingerprint_backfilled = 0
	# THE TWENTY-SECOND-PASS FIX -- same reasoning, playback side; see
	# _playback_tick_last_play_time's big comment.
	_playback_tick_last_play_time = -1.0
	_playback_tick_fingerprint_normal = 0
	_playback_tick_fingerprint_phantom = 0
	_playback_tick_fingerprint_gap = 0
	# THE SIXTEENTH-PASS FIX -- same reasoning: a fresh recording session
	# shouldn't inherit a stale computed speed left over from whatever the
	# last Play Macro run was doing when it stopped.
	_practice_playback_computed_vx = 0.0
	_practice_playback_dash_held = false
	_practice_playback_dash_direction_valid = false
	# Do NOT clear _practice_playback_air_hold_ticks here. This function is
	# called immediately before checkpoint 0 is snapshotted, often midair;
	# clearing it would replace the native airborne phase just observed by
	# _update_practice_live_airborne_clock() with a fabricated zero.


func _on_clear_practice_pressed() -> void:
	_clear_practice_data()
	_practice_active = false
	_practice_start_waiting = false # cancel any in-flight "waiting to start" too -- Clear should leave nothing armed behind it
	_log_action("Macro Bot Mode: cleared", null)
	_refresh_practice_ui()


func _on_place_practice_checkpoint_pressed() -> void:
	if not _practice_active:
		_log_action("Macro Bot Mode is off -- press Start Macro Bot Mode first", null)
		return
	# THE FIX (2026-08-30, fourth pass): same idle-frame-vs-physics-tick gap
	# as _on_toggle_practice_pressed() and _on_play_practice_macro_pressed()
	# -- see the big comment on the first of those for the full story
	# (a divergence report caught this exact class of bug: an idle-frame
	# readiness check/snapshot disagreeing with what the very next physics
	# tick actually goes on to record). This button is just as much an
	# idle-frame Button "pressed" handler as that one, and every checkpoint
	# it places is exactly as replay-sensitive as checkpoint 0 -- there's no
	# reason this one gets to keep reading player state from the wrong
	# frame just because it wasn't the checkpoint the first report happened
	# to catch. Don't check readiness or snapshot anything here; arm a
	# pending flag and let _watch_practice_place_request() -- called from
	# _physics_process(), every physics tick -- do it on solid footing
	# instead. In the overwhelmingly common case (you're actively playing
	# when you press this) it fires on the very next physics tick,
	# imperceptibly; if you happen to press it while dead or mid-hold, it
	# just waits, tick by tick, for the same readiness _start_practice_mode()
	# already requires of checkpoint 0, instead of failing and making you
	# press it again.
	_practice_place_pending = true
	_refresh_practice_ui()


func _watch_practice_place_request() -> void:
	if not _practice_place_pending:
		_practice_place_ready_stable_ticks = 0
		return
	if not _practice_active:
		# Stopped (or Start/Stop toggled off) while a placement was still
		# pending -- nothing sensible left to commit it against.
		_practice_place_pending = false
		_practice_place_ready_stable_ticks = 0
		return
	var player: = _get_local_player()
	if player == null:
		_practice_place_ready_stable_ticks = 0
		return # keep waiting -- no player to check or snapshot yet
	if not _player_ready_for_checkpoint(player):
		_practice_place_ready_stable_ticks = 0 # see THE SEVENTH-PASS FIX on _watch_practice_start_request()
		return # keep waiting, tick by tick -- see the big comment on _on_place_practice_checkpoint_pressed()
	_practice_place_ready_stable_ticks += 1
	if _practice_place_ready_stable_ticks < PRACTICE_READY_STABLE_TICKS_REQUIRED:
		return # looked ready this tick, but not for long enough yet -- see THE SEVENTH-PASS FIX on _watch_practice_start_request()
	_practice_place_ready_stable_ticks = 0
	_practice_place_pending = false
	_practice_segments.append(_practice_current_segment.duplicate())
	_diag_live_committed.append(_diag_live_current.duplicate()) # kept in lockstep with _practice_segments -- see _capture_diag_entry()
	var idx: = _practice_checkpoints.size()
	var snap: = _snapshot_player(player)
	_practice_checkpoints.append(snap)
	_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	_restyle_practice_markers()
	var seg_len: int = _practice_segments.back().size()
	_practice_current_segment = []
	_diag_live_current = []
	_practice_deaths_this_segment = 0
	_log_action("Macro Bot Mode: checkpoint %d placed (segment: %d frame(s))" % [idx, seg_len], null)
	_refresh_practice_ui()


func _on_undo_practice_checkpoint_pressed() -> void:
	if _practice_checkpoints.size() <= 1:
		_log_action("Macro Bot Mode: no placed checkpoints to undo (only the start point remains)", null)
		return
	_practice_checkpoints.pop_back()
	_practice_segments.pop_back()
	if not _diag_live_committed.empty():
		_diag_live_committed.pop_back()
	var m = _practice_markers.pop_back()
	if is_instance_valid(m):
		m.queue_free()
	_restyle_practice_markers()
	_practice_current_segment.clear()
	_diag_live_current.clear()
	_practice_deaths_this_segment = 0
	var player: = _get_local_player()
	if player != null:
		_restore_player(player, _practice_checkpoints.back())
	_log_action("Macro Bot Mode: undid last checkpoint (%d remaining)" % [_practice_checkpoints.size() - 1], null)
	_refresh_practice_ui()


func _on_toggle_practice_auto_respawn_pressed() -> void:
	_practice_auto_respawn = not _practice_auto_respawn
	_style_button(_practice_auto_respawn_button, COLOR_PINK if _practice_auto_respawn else COLOR_BLUE)
	_practice_auto_respawn_button.text = "⟲ Auto-Respawn to Checkpoint: ON" if _practice_auto_respawn else "⟲ Auto-Respawn to Checkpoint: OFF"
	_log_action("Macro Bot Mode: Auto-Respawn to Checkpoint %s" % ("ON" if _practice_auto_respawn else "OFF"), null)


# Arms/disarms auto-activation -- does NOT itself start Macro Bot Mode; that
# only happens the next time _watch_practice_auto_activate() sees a fresh
# level start (see there). Toggling this on mid-level just arms it for the
# NEXT level entry, same as Auto-Record's own arm/disarm button behaves.
func _on_toggle_practice_auto_activate_pressed() -> void:
	_practice_auto_activate = not _practice_auto_activate
	if _practice_auto_activate:
		# Reset the edge-detection state so toggling this on mid-level can
		# fire right away if applicable: _was_pre=false means a level
		# that's ALREADY mid-LEVEL_PRE right now reads as a fresh rising
		# edge next check, and _checked_state_for_game=false re-arms the
		# level-editor first-entry-skip check too.
		_practice_auto_activate_was_pre = false
		_practice_auto_activate_checked_state_for_game = false
	_style_button(_practice_auto_activate_button, COLOR_PINK if _practice_auto_activate else COLOR_BLUE)
	_practice_auto_activate_button.text = "Auto-Activate on Level Entry: ON" if _practice_auto_activate else "Auto-Activate on Level Entry: OFF"
	_log_action("Macro Bot Mode: Auto-Activate on Level Entry %s" % ("ON" if _practice_auto_activate else "OFF"), null)


# Captures whatever's actually reached Input.is_action_pressed() this
# physics frame for each recordable action -- real keyboard (on ANY bound
# key), joypad, touch, Buffered Inputs holds, and Perfect Jumpzone presses
# all land in the same place, so whichever produced this frame's input gets
# captured identically.
func _capture_practice_frame() -> Dictionary:
	var frame: = {}
	for action in PRACTICE_RECORD_ACTIONS:
		frame[action] = Input.is_action_pressed(action)
	if frame.get(ACTION_DASH, false):
		var player: = _get_local_player()
		var move: = sign(Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT))
		var joystick_x: = Input.get_action_strength("player_joystick_move_right") - Input.get_action_strength("player_joystick_move_left")
		if abs(joystick_x) > 0.1:
			move = joystick_x
		if move != 0.0:
			frame[PRACTICE_DASH_DIRECTION_KEY] = move > 0.0
		elif player != null:
			frame[PRACTICE_DASH_DIRECTION_KEY] = bool(player.facing_dir)
	return frame


# ----------------------------------------------------------------------
#  Divergence Diagnostics
# ----------------------------------------------------------------------
# THE POINT: everything Macro Bot Mode does to keep a replay accurate --
# facing_dir, dash-edge tracking, the checkpoint-boundary fixes, the
# _reset_object() call, all of it -- is a THEORY about what the native
# controller and Box2D need to see in order to reproduce the original run.
# Every one of those theories was checked against a stub project standing in
# for the native code, because the native code itself can't be run outside
# the real game. That's the ceiling: no amount of reasoning from outside a
# black box can tell you whether it's now accurately modeled, only playing
# it against the REAL native code can. This is what does that -- not by
# guessing better, but by recording exactly what the real game does on a
# genuine live run and diffing it, tick for tick, field for field, against
# what the exact same recorded inputs produce when fed back through Macro
# Bot Mode's own replay path.
#   The output is no longer "the replay feels a bit off around bouncy
# blocks" -- it's "tick 214, right after a JUMP input, linear_velocity.y
# was 640 live and 480 in replay" (or: it's not, and everything after tick
# 214 was drifting only because 214 already had drifted, which is just as
# useful to know). A concrete tick and field is something a specific fix
# can target, or something to go stand on in the level editor and look at
# with fresh eyes -- "always at this exact tick" narrows it to a boundary
# effect or a native tick-ordering quirk; "different tick every run" points
# at fresh Box2D floating point rather than anything Macro Bot Mode itself
# does. Either way, it replaces guessing with a place to look.
#   HOW TO USE IT: turn on Diagnostic Logging (Macro Bot tab) before you
# record your segments, so the ORIGINAL live run is captured tick by tick as
# you record it -- this is the "ground truth" half. Then Play Macro once
# (also with it on) to capture the "replay" half from the exact same
# recorded inputs. Then press Compare. It writes a full report to disk and
# logs a summary of the first mismatch (if any) right in the action log.
#   WHAT IT DOESN'T DO: if inputs and state both match at every tick right
# up until playback ends, the replay genuinely reproduced the original run
# bit-for-bit as far as this tool can observe -- if it still LOOKS or FEELS
# wrong at that point, whatever's different isn't in any of the fields
# tracked here (camera/renderer-only cosmetics, or state on some other
# native object entirely, e.g. the bouncy block itself rather than the
# player). This narrows the search, it doesn't guarantee there's nothing
# left outside what it's able to see.
func _capture_diag_entry(p: WPPlayer, g: WPGame, frame: Dictionary) -> Dictionary:
	var recorded_input: = {}
	for action in PRACTICE_RECORD_ACTIONS:
		recorded_input[action] = frame.get(action, false)
	var entry: = {
		"input": recorded_input,
		"position": p.position,
		"linear_velocity": p.linear_velocity,
	}
	for field in DIAG_SCALAR_FIELDS:
		entry[field] = p.get(field)
	# Debug-only compact moving-world observation. The expensive scene walk is
	# cached once per loaded level; each physics tick only visits the small set
	# of AnimationPlayers and moving physics bodies. This lets the determinism
	# check distinguish a player/input bug from a moving-platform phase mismatch
	# without serializing a full world snapshot into every diagnostic frame.
	entry["world_fingerprint"] = _diag_moving_world_fingerprint(g)
	if g != null and g.wp_game_data != null and ("play_time" in g.wp_game_data):
		entry["play_time"] = g.wp_game_data.play_time
	return entry


func _diag_moving_world_fingerprint(game: WPGame) -> int:
	if game == null or not ("level" in game) or game.level == null:
		_diag_world_level_instance_id = 0
		_diag_world_nodes.clear()
		return 0
	var level_id := game.level.get_instance_id()
	if _diag_world_level_instance_id != level_id:
		_diag_world_level_instance_id = level_id
		_diag_world_nodes.clear()
		_collect_diag_world_nodes(game.level)
	var fingerprint := 5381
	fingerprint = _diag_hash_mix(fingerprint, _diag_world_nodes.size())
	for tracked in _diag_world_nodes:
		if tracked == null or not is_instance_valid(tracked):
			continue
		fingerprint = _diag_hash_mix(fingerprint, str(game.level.get_path_to(tracked)).hash())
		if tracked is AnimationPlayer:
			var animation := tracked as AnimationPlayer
			fingerprint = _diag_hash_mix(fingerprint, animation.current_animation.hash())
			fingerprint = _diag_hash_mix(fingerprint, int(round(animation.current_animation_position * 1000.0)) if not animation.current_animation.empty() else 0)
			fingerprint = _diag_hash_mix(fingerprint, int(round(animation.playback_speed * 1000.0)))
			fingerprint = _diag_hash_mix(fingerprint, animation.is_playing())
		elif tracked is Node2D:
			var moving := tracked as Node2D
			fingerprint = _diag_hash_mix(fingerprint, int(round(moving.position.x * 1000.0)))
			fingerprint = _diag_hash_mix(fingerprint, int(round(moving.position.y * 1000.0)))
			fingerprint = _diag_hash_mix(fingerprint, int(round(moving.rotation * 10000.0)))
			if "linear_velocity" in moving:
				var velocity: Vector2 = moving.get("linear_velocity")
				fingerprint = _diag_hash_mix(fingerprint, int(round(velocity.x * 1000.0)))
				fingerprint = _diag_hash_mix(fingerprint, int(round(velocity.y * 1000.0)))
			if "angular_velocity" in moving:
				fingerprint = _diag_hash_mix(fingerprint, int(round(float(moving.get("angular_velocity")) * 10000.0)))
	return fingerprint


func _collect_diag_world_nodes(node: Node) -> void:
	if node is AnimationPlayer or (node is Node2D and (node is RigidBody2D or node is KinematicBody2D or node.get_class() == "Box2DPhysicsBody")):
		_diag_world_nodes.append(node)
	for child in node.get_children():
		_collect_diag_world_nodes(child)


func _diag_hash_mix(accumulator: int, value) -> int:
	return int((accumulator * 33 + hash(value)) & 0x7fffffff)


# ----------------------------------------------------------------------
#  Debug Mode -- persisted master switch for the 2026-08-30 tool revamp.
#  See the big comment on `_debug_mode_enabled` above for what turning this
#  on actually does; this section is just the load/save/toggle plumbing.
# ----------------------------------------------------------------------
func _load_debug_mode_from_disk() -> void:
	var f: = File.new()
	if f.file_exists(DEBUG_MODE_SETTINGS_PATH) and f.open(DEBUG_MODE_SETTINGS_PATH, File.READ) == OK:
		var loaded = f.get_var()
		f.close()
		if typeof(loaded) == TYPE_BOOL:
			_debug_mode_enabled = loaded
	if _debug_mode_enabled:
		_diag_enabled = true # keep the two in lockstep on load, same as the toggle handler below does live


func _save_debug_mode_to_disk() -> void:
	var f: = File.new()
	if f.open(DEBUG_MODE_SETTINGS_PATH, File.WRITE) == OK:
		f.store_var(_debug_mode_enabled)
		f.close()


# ----------------------------------------------------------------------
#  Frame Rate Limit -- see the big comment on FPS_LIMIT_SETTINGS_PATH above
#  for why this exists. Persisted/loaded exactly like Debug Mode just above
#  (same File.store_var()/get_var() pattern, same "tiny standalone .cfg,
#  survives a TASTool.gd restart" reasoning), applied via Engine.
#  set_target_fps() -- Godot 3.x's own built-in cap primitive, the same one
#  Project Settings > Application > Run > Max FPS drives, just exposed here
#  at runtime instead of requiring an export/rebuild. fps_limit == 0 is the
#  sentinel for "uncapped," matching Engine.set_target_fps()'s own
#  convention exactly (passing 0 there already means "no limit"), so
#  _apply_fps_limit() never needs a separate on/off flag.
# ----------------------------------------------------------------------
func _load_fps_limit_from_disk() -> void:
	var f: = File.new()
	if f.file_exists(FPS_LIMIT_SETTINGS_PATH) and f.open(FPS_LIMIT_SETTINGS_PATH, File.READ) == OK:
		var loaded = f.get_var()
		f.close()
		if typeof(loaded) == TYPE_INT or typeof(loaded) == TYPE_REAL:
			fps_limit = int(clamp(loaded, FPS_LIMIT_MIN, FPS_LIMIT_MAX))
	_apply_fps_limit()


func _save_fps_limit_to_disk() -> void:
	var f: = File.new()
	if f.open(FPS_LIMIT_SETTINGS_PATH, File.WRITE) == OK:
		f.store_var(fps_limit)
		f.close()


func _apply_fps_limit() -> void:
	Engine.set_target_fps(fps_limit) # 0 == uncapped, Engine's own convention


func _on_fps_limit_delta_pressed(delta: int) -> void:
	fps_limit = int(clamp(fps_limit + delta, FPS_LIMIT_MIN, FPS_LIMIT_MAX))
	_apply_fps_limit()
	_save_fps_limit_to_disk()
	_fps_limit_label.text = ("%d FPS" % fps_limit) if fps_limit > 0 else "Uncapped"
	_log_action("Frame Rate Limit: %s (saved -- stays set across restarts)" % (("%d FPS" % fps_limit) if fps_limit > 0 else "uncapped"), null)


func _set_debug_mode_enabled(value: bool) -> void:
	_debug_mode_enabled = value
	# Debug Mode owns diagnostics completely: disabling it stops background
	# capture as well as hiding the advanced controls.
	_diag_enabled = value
	if not value:
		_log_open = false
		_restore_drift_enabled = false
		_restore_drift_watches.clear()
		if _noclip_enabled and _noclip_toggle_button != null:
			_on_toggle_noclip_pressed()
	_save_debug_mode_to_disk()
	if _debug_tools_container != null:
		_debug_tools_container.visible = value
	if _diag_label != null:
		_diag_label.visible = value
	_log_action("Goobplayability Debug Mode %s" % ("ON" if value else "OFF"), null)
	_apply_log_open_state()
	_refresh_practice_ui()


func _on_toggle_debug_mode_pressed() -> void:
	_set_debug_mode_enabled(not _debug_mode_enabled)


func _on_toggle_diag_pressed() -> void:
	if _debug_mode_enabled:
		_log_action("Diagnostic Logging is forced ON while Debug Mode is on -- turn Debug Mode off first if you want to control it separately.", null)
		return
	_diag_enabled = not _diag_enabled
	_style_button(_diag_toggle_button, COLOR_PINK if _diag_enabled else COLOR_BLUE)
	_diag_toggle_button.text = "Diagnostic Logging: ON" if _diag_enabled else "Diagnostic Logging: OFF"
	_log_action("Divergence Diagnostics %s -- %s" % ["ON" if _diag_enabled else "OFF", "record your segments now, Play Macro once, then press Compare" if _diag_enabled else "existing captured data is kept until Macro Bot data is cleared"], null)
	_refresh_practice_ui()


# Flattens _diag_live_committed (one array per committed segment, same shape
# as _practice_segments) into a single tick-ordered list, exactly mirroring
# what _build_practice_playback_frames() does to _practice_segments to build
# the flat frame list _diag_replay_log is captured against -- this is what
# keeps index i meaning the same tick on both sides of the comparison.
func _flatten_diag_live() -> Array:
	var flat: = []
	for seg in _diag_live_committed:
		for entry in seg:
			flat.append(entry)
	return flat


func _diag_field_matches(field: String, live_val, replay_val) -> bool:
	if field in DIAG_VECTOR_FIELDS:
		var eps: = DIAG_POSITION_EPSILON if field == "position" else DIAG_VELOCITY_EPSILON
		return live_val.distance_to(replay_val) <= eps
	return live_val == replay_val


# Godot 3.5's Dictionary != isn't reliably documented as a deep content
# comparison across every build, so this compares key-by-key explicitly
# rather than trusting it -- input-mismatch detection is the one check here
# that actually points at a bug in Macro Bot Mode itself rather than native
# physics, so it's worth not getting this particular comparison wrong.
func _inputs_differ(live_input: Dictionary, replay_input: Dictionary) -> bool:
	if live_input.size() != replay_input.size():
		return true
	for key in live_input:
		if not replay_input.has(key) or replay_input[key] != live_input[key]:
			return true
	return false


# _diag_live_committed is only guaranteed to correspond index-for-index to
# _practice_segments (and therefore to _practice_playback_frames/_diag_replay_log)
# when Diagnostic Logging was already ON for every tick of every committed
# segment. If it got switched on partway through recording -- entirely
# possible in practice, since nothing stops you from recording some
# checkpoints before ever touching the new toggle -- or a checkpoint got
# undone after already being logged, some _diag_live_committed[k] ends up
# SHORTER than the real _practice_segments[k] it's supposed to mirror (or
# missing entirely). Once that happens, every flattened index from that
# segment onward stops lining up with the same tick on both sides, which
# would silently produce a comparison that looks like scattered, confusing
# divergence when it's actually just misaligned bookkeeping. Returns how
# many leading ticks are still guaranteed aligned -- comparing only up to
# here keeps the report honest instead of quietly wrong.
func _diag_coverage_prefix_ticks() -> int:
	var ticks: = 0
	var n: = min(_diag_live_committed.size(), _practice_segments.size())
	for k in range(n):
		if _diag_live_committed[k].size() != _practice_segments[k].size():
			return ticks
		ticks += _diag_live_committed[k].size()
	if _diag_live_committed.size() != _practice_segments.size():
		return ticks # trailing segment(s) never got any diag data at all
	return ticks


# Phase 0.1 -- Replay Determinism Check. Called once per playback tick
# (right after _diag_replay_log gets this tick's entry appended) so the
# Macro Bot tab can show a live accuracy/first-desync/largest-drift readout
# instead of only finding out after pressing Compare. Reuses the exact same
# per-field comparison _on_compare_diagnostics_pressed() does below, just
# incrementally, one newly-added tick at a time, instead of over the whole
# log at once.
func _advance_replay_determinism_check() -> void:
	var replay_index: = _diag_replay_log.size() - 1
	if replay_index < 0 or replay_index >= _replay_check_live_flat.size() or replay_index >= _replay_check_safe_ticks:
		return # outside what's safely aligned this run -- see _diag_coverage_prefix_ticks()
	var live_entry: Dictionary = _replay_check_live_flat[replay_index]
	var replay_entry: Dictionary = _diag_replay_log[replay_index]
	var tick_matched: = true
	var tick_drift: = 0.0
	var tick_first_field := ""
	for field in (DIAG_VECTOR_FIELDS + DIAG_SCALAR_FIELDS + DIAG_WORLD_FIELDS):
		if not live_entry.has(field) or not replay_entry.has(field):
			continue
		if field in DIAG_VECTOR_FIELDS:
			tick_drift = max(tick_drift, live_entry[field].distance_to(replay_entry[field]))
		if not _diag_field_matches(field, live_entry[field], replay_entry[field]):
			tick_matched = false
			if tick_first_field.empty():
				tick_first_field = field
	_replay_check_compared_ticks += 1
	if tick_matched:
		_replay_check_matched_ticks += 1
	elif _replay_check_first_desync_tick == -1:
		_replay_check_first_desync_tick = replay_index
		_replay_check_first_desync_field = tick_first_field
		_replay_check_first_desync_category = _determinism_field_category(tick_first_field)
	_replay_check_largest_drift = max(_replay_check_largest_drift, tick_drift)
	if not tick_matched and _replay_check_stop_on_desync:
		_log_action("Macro Bot Mode: stopped playback at tick %d -- Replay Determinism Check found a desync (Stop on Desync is ON)." % replay_index, null)
		_practice_playback = false
		Engine.time_scale = 1.0
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1


func _determinism_field_category(field: String) -> String:
	if field == "position":
		return "position"
	if field == "linear_velocity":
		return "velocity"
	if field in ["stick_to_ground_timer", "is_inside_one_way_platform", "coyote_timer"]:
		return "ground/contact"
	if field in ["dash_cooldown", "dash_timer", "facing_dir"]:
		return "dash/facing"
	if field in ["alive", "body_enabled", "dead_counter"]:
		return "life/body"
	if field == "world_fingerprint":
		return "moving world"
	return "player state"


func _set_stop_on_desync_enabled(value: bool) -> void:
	_replay_check_stop_on_desync = value
	SavedSettings.set_value(SETTING_STOP_ON_DESYNC, value)
	_refresh_practice_ui()


func _on_toggle_stop_on_desync_pressed() -> void:
	_set_stop_on_desync_enabled(not _replay_check_stop_on_desync)


# Phase 0.2 -- Replay Self-Test. Repeatedly re-triggers Play Macro, collecting
# one PASS/FAIL result per run from whichever exit path
# _advance_practice_playback() takes (natural finish vs. mid-macro death),
# combined with the Replay Determinism Check's per-run accuracy. See the
# _self_test_active checks inside _advance_practice_playback() for where runs
# actually get chained together.
func _start_replay_self_test(run_count: int) -> void:
	if _practice_segments.empty() or _practice_playback or _self_test_active:
		return
	var expected_ticks := _practice_recorded_frame_count()
	var safe_ticks := _diag_coverage_prefix_ticks()
	if expected_ticks <= 0 or safe_ticks < expected_ticks:
		var coverage_message := "Replay Self-Test: NO DATA -- record the complete macro with Debug Mode enabled first (%d/%d comparable frames)." % [safe_ticks, expected_ticks]
		_log_action(coverage_message, null)
		if _self_test_status_label != null:
			_self_test_status_label.text = coverage_message
		return
	_self_test_active = true
	_self_test_total_runs = run_count
	_self_test_completed_runs = 0
	_self_test_results = []
	_log_action("Replay Self-Test: starting %d run(s)." % run_count, null)
	_refresh_self_test_status()
	_on_play_practice_macro_pressed()


func _practice_recorded_frame_count() -> int:
	var count := 0
	for segment in _practice_segments:
		count += segment.size()
	return count


func _on_replay_self_test_run_finished(passed: bool, fail_frame: int) -> void:
	if not _self_test_active:
		return
	var accuracy: = 0.0
	if _replay_check_compared_ticks > 0:
		accuracy = 100.0 * float(_replay_check_matched_ticks) / float(_replay_check_compared_ticks)
	_self_test_completed_runs += 1
	_self_test_results.append({"run": _self_test_completed_runs, "passed": passed, "fail_frame": fail_frame, "accuracy": accuracy, "compared": _replay_check_compared_ticks, "expected": _practice_recorded_frame_count(), "category": _replay_check_first_desync_category, "field": _replay_check_first_desync_field})
	_refresh_self_test_status()
	if _self_test_completed_runs >= _self_test_total_runs or (not passed and _self_test_stop_on_failure):
		_finish_replay_self_test()
	else:
		_on_play_practice_macro_pressed()


func _finish_replay_self_test() -> void:
	var pass_count: = 0
	for result in _self_test_results:
		if result["passed"]:
			pass_count += 1
	_log_action("Replay Self-Test: finished -- %d/%d run(s) passed." % [pass_count, _self_test_results.size()], null)
	_self_test_active = false
	_refresh_practice_ui()


func _refresh_self_test_status() -> void:
	if _self_test_status_label == null:
		return
	if _self_test_results.empty():
		_self_test_status_label.text = "Replay Self-Test: no runs yet"
		return
	var pass_count: = 0
	for result in _self_test_results:
		if result["passed"]:
			pass_count += 1
	var last: Dictionary = _self_test_results[_self_test_results.size() - 1]
	var last_text: String
	if last["passed"]:
		last_text = "PASS"
	else:
		last_text = "FAIL @ frame %d" % int(last["fail_frame"])
		if not str(last.get("category", "")).empty():
			last_text += " (%s: %s)" % [last["category"], last.get("field", "unknown")]
	_self_test_status_label.text = "Replay Self-Test: %d/%d passed so far -- last run: %s (%.1f%% accuracy)" % [pass_count, _self_test_results.size(), last_text, float(last["accuracy"])]


func _on_self_test_x3_pressed() -> void:
	_start_replay_self_test(3)


func _on_self_test_x5_pressed() -> void:
	_start_replay_self_test(5)


func _on_self_test_x10_pressed() -> void:
	_start_replay_self_test(10)


func _set_self_test_stop_on_failure(value: bool) -> void:
	_self_test_stop_on_failure = value
	SavedSettings.set_value(SETTING_SELF_TEST_STOP_ON_FAILURE, value)
	_refresh_practice_ui()


func _on_toggle_self_test_stop_on_failure_pressed() -> void:
	_set_self_test_stop_on_failure(not _self_test_stop_on_failure)


func _on_compare_diagnostics_pressed() -> void:
	var live: = _flatten_diag_live()
	var replay: = _diag_replay_log
	if live.empty() or replay.empty():
		_log_action("Divergence Diagnostics: nothing to compare yet -- turn on Diagnostic Logging, (re-)record your segments so there's live data, then Play Macro once so there's replay data, then press Compare again.", null)
		return

	var compare_fields: = DIAG_VECTOR_FIELDS + DIAG_SCALAR_FIELDS + DIAG_WORLD_FIELDS
	var overlap_count: = min(live.size(), replay.size())
	var safe_ticks: = _diag_coverage_prefix_ticks()
	var coverage_incomplete: = safe_ticks < overlap_count
	var compared_count: int = safe_ticks if coverage_incomplete else overlap_count
	var first_input_mismatch: = -1
	var first_state_divergence: = -1
	var first_state_field: = ""
	var mismatch_counts: = {}
	for field in compare_fields:
		mismatch_counts[field] = 0

	var report_lines: = []
	var dt: Dictionary = OS.get_datetime()
	report_lines.append("Divergence Diagnostics report -- %04d-%02d-%02d %02d:%02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]])
	report_lines.append("live ticks: %d, replay ticks: %d, compared: %d" % [live.size(), replay.size(), compared_count])
	# One callback is one fixed physics step. These legacy counters remain in
	# the report so old and new logs are easy to compare, but corrected runs
	# never skip/backfill from another node's play_time value.
	report_lines.append("live fixed-step callbacks: %d recorded, %d skipped, %d synthetic (expected skipped=0, synthetic=0)" % [_live_tick_fingerprint_normal, _live_tick_fingerprint_phantom, _live_tick_fingerprint_backfilled])
	report_lines.append("playback fixed-step callbacks: %d consumed, %d skipped, %d fast-forwarded (expected skipped=0, fast-forwarded=0)" % [_playback_tick_fingerprint_normal, _playback_tick_fingerprint_phantom, _playback_tick_fingerprint_gap])
	report_lines.append("authoritative recorded-state corrections applied during playback: %d" % _practice_playback_state_corrections)
	if coverage_incomplete:
		report_lines.append("")
		report_lines.append("WARNING: diagnostic coverage is incomplete -- only the first %d of %d overlapping ticks are guaranteed to line up tick-for-tick. This happens when Diagnostic Logging was switched on partway through recording (some already-recorded segment has fewer logged ticks than it actually has frames), or a checkpoint was undone after being logged. Ticks beyond %d are NOT included below because their numbers may not correspond to the same moment on both sides anymore. For a fully trustworthy report: Clear Macro Bot Mode data, turn Diagnostic Logging ON, then re-record your checkpoints/segments from scratch before Play Macro + Compare." % [safe_ticks, overlap_count, safe_ticks])
	report_lines.append("")

	for i in range(compared_count):
		var l: Dictionary = live[i]
		var r: Dictionary = replay[i]
		if first_input_mismatch == -1 and _inputs_differ(l["input"], r["input"]):
			first_input_mismatch = i
			report_lines.append("[tick %d] INPUT MISMATCH -- live=%s replay=%s (this is a bug in recording/stitching itself, not native physics -- the wrong input got fed back)" % [i, l["input"], r["input"]])
		for field in compare_fields:
			if not _diag_field_matches(field, l[field], r[field]):
				mismatch_counts[field] += 1
				if first_state_divergence == -1:
					first_state_divergence = i
					first_state_field = field
					report_lines.append("[tick %d] FIRST STATE DIVERGENCE -- field '%s': live=%s replay=%s (input this tick: live=%s replay=%s)" % [i, field, l[field], r[field], l["input"], r["input"]])

	report_lines.append("")
	var context_center: = -1
	if first_input_mismatch != -1 and (first_state_divergence == -1 or first_input_mismatch <= first_state_divergence):
		context_center = first_input_mismatch
	elif first_state_divergence != -1:
		context_center = first_state_divergence
	if context_center != -1:
		report_lines.append_array(_build_divergence_context_lines(live, replay, context_center, compared_count))
		report_lines.append("")
	report_lines.append("Per-field mismatch counts (out of %d compared ticks, AFTER the first divergence these largely just cascade from it, not independent problems):" % [compared_count])
	for field in compare_fields:
		if mismatch_counts[field] > 0:
			report_lines.append("  %s: %d" % [field, mismatch_counts[field]])
	if live.size() != replay.size():
		report_lines.append("")
		report_lines.append("NOTE: live and replay run lengths differ (%d vs %d) -- %s" % [live.size(), replay.size(), "replay ended early, likely died mid-macro" if replay.size() < live.size() else "replay ran longer than the live recording, which shouldn't be possible from the same input list -- worth a second look"])

	var report_text: = "\n".join(report_lines)
	var path: = _write_diag_report(report_text)

	var summary: String
	if compared_count == 0:
		summary = "Divergence Diagnostics: no comparable ticks -- diagnostic coverage doesn't even reach checkpoint 0's first tick (Diagnostic Logging almost certainly wasn't on yet when you started recording). Turn it on, re-record from scratch, then try again. Full report: %s" % [path]
		_log_action(summary, null)
		return
	if first_input_mismatch != -1 and (first_state_divergence == -1 or first_input_mismatch <= first_state_divergence):
		summary = "Divergence Diagnostics: input mismatch at tick %d -- that's on Macro Bot Mode's own recording/playback, not native physics. Full report: %s" % [first_input_mismatch, path]
	elif first_state_divergence != -1:
		summary = "Divergence Diagnostics: inputs matched, but '%s' first diverged at tick %d/%d. Full report: %s" % [first_state_field, first_state_divergence, compared_count, path]
	else:
		summary = "Divergence Diagnostics: every tracked field matched for all %d compared ticks -- replay reproduced the recorded run exactly, as far as this tool can see. Full report: %s" % [compared_count, path]
	if coverage_incomplete:
		summary += " (⚠ diagnostic coverage was incomplete -- only checked the first %d/%d overlapping ticks; see report for why)" % [safe_ticks, overlap_count]
	_log_action(summary, null)


# A tick-by-tick window around the first divergence -- both sides' full
# position/velocity/input, plus how many ticks it's been since the most
# recent checkpoint-boundary restore on the replay side (via
# _practice_playback_checkpoint_at, still populated from the Play Macro run
# Compare is reading). A single "[tick N] FIRST DIVERGENCE" line only ever
# showed the moment things had ALREADY gone wrong; this shows whether
# velocity was already off a few ticks earlier (before position visibly
# caught up to it), and whether the divergence tends to land suspiciously
# close to a checkpoint boundary -- both go directly to the "is this a
# checkpoint-restore momentum bug, or something else entirely" question,
# instead of leaving it a guess.
func _build_divergence_context_lines(live: Array, replay: Array, center_tick: int, compared_count: int) -> Array:
	var lines: = []
	lines.append("Context around the first divergence (tick %d), %d tick(s) each side:" % [center_tick, DIAG_CONTEXT_WINDOW])
	var lo: = max(0, center_tick - DIAG_CONTEXT_WINDOW)
	var hi: = min(compared_count - 1, center_tick + DIAG_CONTEXT_WINDOW)
	for i in range(lo, hi + 1):
		var l: Dictionary = live[i]
		var r: Dictionary = replay[i]
		var marker: = " <== FIRST DIVERGENCE" if i == center_tick else ""
		var since_boundary: = _ticks_since_last_playback_boundary(i)
		var boundary_note: = (" [%d tick(s) since last checkpoint boundary]" % since_boundary) if since_boundary >= 0 else ""
		# stick_to_ground_timer + is_inside_one_way_platform specifically --
		# these are what would show whether a restore lands on a one-way
		# platform edge (a very common source of "grounded per script, but
		# a raycast can't find the surface" -- one-way platforms are
		# typically special-cased in collision queries) and whether the
		# grounded flag was already false or freshly went false right in
		# this window, ahead of any visible position change.
		# alive/enabled/dead_counter specifically -- added 2026-08-30, after
		# confirming from GooberDash's own source that a pre-round/hold
		# player sits with alive=false, body.enabled=false, and dead_counter
		# counting down (see the REVISED note on _reset_object() in
		# _restore_player()). Showing these directly here means the NEXT
		# report using this window shows immediately whether that hold state
		# matches between live and replay, instead of only being inferable
		# indirectly from position/velocity staying frozen.
		# THE THIRTEENTH-PASS FIX -- play_time was always captured by
		# _capture_diag_entry() but never shown here. Printing it turns the
		# very next report showing a suspicious repeated tick (like the one
		# that motivated this fix) into a direct, unambiguous test: identical
		# play_time on two consecutive ticks is hard proof the native game
		# hadn't actually ticked between them; different play_time despite
		# identical position/velocity would point somewhere else entirely.
		# .get(..., "n/a") since older report data (or a build that doesn't
		# expose play_time at all -- see _capture_diag_entry()) may not have it.
		lines.append("  tick %d%s: live pos=%s vel=%s play_time=%s ground_timer=%s one_way=%s alive=%s enabled=%s dead_counter=%s input=%s | replay pos=%s vel=%s play_time=%s ground_timer=%s one_way=%s alive=%s enabled=%s dead_counter=%s input=%s%s" % [i, boundary_note, l["position"], l["linear_velocity"], l.get("play_time", "n/a"), l["stick_to_ground_timer"], l["is_inside_one_way_platform"], l["alive"], l["body_enabled"], l["dead_counter"], l["input"], r["position"], r["linear_velocity"], r.get("play_time", "n/a"), r["stick_to_ground_timer"], r["is_inside_one_way_platform"], r["alive"], r["body_enabled"], r["dead_counter"], r["input"], marker])
	return lines


# See _build_divergence_context_lines() -- how many ticks have elapsed
# since the most recent boundary in _practice_playback_checkpoint_at at or
# before `tick`, or -1 if that array is empty (e.g. Compare was pressed
# without a Play Macro run in this session, or checkpoint data has since
# been cleared).
func _ticks_since_last_playback_boundary(tick: int) -> int:
	if _practice_playback_checkpoint_at.empty():
		return -1
	var best: = -1
	for boundary in _practice_playback_checkpoint_at:
		if boundary <= tick and boundary > best:
			best = boundary
	if best == -1:
		return -1
	return tick - best


func _write_diag_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/divergence_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


# ----------------------------------------------------------------------
#  Key Event report -- Debug Mode (2026-08-30 revamp)
# ----------------------------------------------------------------------
# THE POINT: Divergence Diagnostics (above) is complete but dense -- a
# per-tick, per-field dump that answers "is anything different" precisely
# but takes real effort to read as "what did the PLAYER actually do
# differently." This turns the exact same underlying per-tick captures
# (_diag_live_committed / _diag_replay_log -- nothing new is recorded here,
# see _capture_diag_entry()'s "input"/"position"/"play_time" fields) into
# discrete press/release EVENTS per action -- the level a human thinks at
# ("I pressed Jump here, held it this long") instead of the level physics
# thinks at (267 individual booleans). Millisecond timestamps come from
# wp_game_data.play_time * 1000.0 -- confirmed via
# ui/nodes/TimeTrialPill.gd (finish_time = game.wp_game_data.play_time) to
# be the exact field driving the game's own top-left race timer, so these
# timestamps line up with what you'd see on screen while recording.
#   This does NOT replace Divergence Diagnostics -- both stay. This is the
# "read this first" summary; that report is still what you'd dig into next
# if a specific tick/field needs a closer look.
func _build_key_events_for_action(flat: Array, action: String) -> Array:
	var events: = []
	# null, or a full duplicated diag entry (see _capture_diag_entry() --
	# "input"/"position"/"play_time"/every DIAG_SCALAR_FIELDS entry, alive/
	# body_enabled/dead_counter included) plus "tick" -- duplicating the
	# whole entry rather than picking out individual fields means any field
	# _capture_diag_entry() already captures is available to _finish_key_event()
	# below with no further plumbing, alive/body_enabled/dead_counter included.
	var held_since = null
	for i in range(flat.size()):
		var entry: Dictionary = flat[i]
		var input: Dictionary = entry.get("input", {})
		var pressed: bool = input.get(action, false)
		if pressed and held_since == null:
			held_since = entry.duplicate()
			held_since["tick"] = i
		elif not pressed and held_since != null:
			events.append(_finish_key_event(action, held_since, i, entry, false))
			held_since = null
	if held_since != null:
		# Still held when the log ran out (playback ended, or Diagnostic
		# Logging's coverage window stopped) -- reported as such rather than
		# silently dropped, since "was still holding Jump when it cut off" is
		# itself useful information.
		events.append(_finish_key_event(action, held_since, flat.size(), null, true))
	return events


# alive/body_enabled/dead_counter are surfaced here (2026-08-30, after the
# first real Debug Mode report showed press-tick/hold-tick matching
# PERFECTLY on every single event -- proving input timing itself is no
# longer the problem -- while replay position and play_time sat frozen
# identical for hundreds of ticks at a stretch, something live never did at
# the same points) specifically so a frozen stretch that lines up with
# body_enabled=false/dead_counter>0 is visible directly on the press/release
# lines that bracket it, instead of needing a second Divergence Diagnostics
# report to go find that out.
func _finish_key_event(action: String, held_since: Dictionary, release_tick: int, release_entry, still_held_at_end: bool) -> Dictionary:
	var press_time_ms: float = (held_since["play_time"] * 1000.0) if held_since.get("play_time", null) != null else -1.0
	var release_time_ms: float = -1.0
	var release_position = null
	var release_alive = null
	var release_body_enabled = null
	var release_dead_counter = null
	if release_entry != null:
		if release_entry.has("play_time"):
			release_time_ms = release_entry["play_time"] * 1000.0
		release_position = release_entry.get("position", null)
		release_alive = release_entry.get("alive", null)
		release_body_enabled = release_entry.get("body_enabled", null)
		release_dead_counter = release_entry.get("dead_counter", null)
	var hold_time_ms: float = (release_time_ms - press_time_ms) if (press_time_ms >= 0.0 and release_time_ms >= 0.0) else -1.0
	return {
		"action": action,
		"press_tick": held_since["tick"],
		"release_tick": (-1 if still_held_at_end else release_tick),
		"press_time_ms": press_time_ms,
		"release_time_ms": release_time_ms,
		"hold_ticks": release_tick - held_since["tick"],
		"hold_time_ms": hold_time_ms,
		"press_position": held_since.get("position", null),
		"release_position": release_position,
		"press_alive": held_since.get("alive", null),
		"press_body_enabled": held_since.get("body_enabled", null),
		"press_dead_counter": held_since.get("dead_counter", null),
		"release_alive": release_alive,
		"release_body_enabled": release_body_enabled,
		"release_dead_counter": release_dead_counter,
		"still_held_at_end": still_held_at_end,
	}


# Truncates a flat diag log to its first `limit` ticks without relying on
# Array.slice() -- not available on every 3.x build's GDScript Array, so
# this just builds the sub-array by hand. Used to keep the key-event report
# honest about the same "diagnostic coverage" boundary
# _diag_coverage_prefix_ticks() already enforces for Divergence Diagnostics,
# rather than silently comparing events built from ticks that may not
# actually correspond to the same moment on both sides.
func _cap_flat_log(flat: Array, limit: int) -> Array:
	if limit >= flat.size():
		return flat
	var capped: = []
	for i in range(limit):
		capped.append(flat[i])
	return capped


func _format_key_event_ms(ms: float) -> String:
	return ("%.1fms" % ms) if ms >= 0.0 else "unknown"


# One comparison line per matched (live event i, replay event i) pair for a
# single action, plus MISSING/EXTRA lines for either side having more
# presses than the other. Matching is purely positional (live press #0 vs
# replay press #0, etc.) -- correct as long as both sides recorded the same
# NUMBER of presses for this action, which is exactly the thing a MISSING/
# EXTRA line itself flags when it isn't true; once that happens, positions
# after the mismatch are only a best-effort guess, same caveat Divergence
# Diagnostics' own "these largely just cascade" note carries.
func _format_hold_state(alive, body_enabled, dead_counter) -> String:
	if alive == null:
		return "n/a"
	return "alive=%s enabled=%s dead_ctr=%s" % [alive, body_enabled, dead_counter]


func _compare_key_events_for_action(action: String, live_events: Array, replay_events: Array) -> Array:
	var lines: = []
	var n: = max(live_events.size(), replay_events.size())
	for i in range(n):
		if i >= live_events.size():
			var r: Dictionary = replay_events[i]
			lines.append("  [%s #%d] EXTRA IN REPLAY -- replay pressed at tick %d (%s) pos=%s [%s], held %d tick(s) (%s), live never pressed it here" % [action, i, r["press_tick"], _format_key_event_ms(r["press_time_ms"]), r["press_position"], _format_hold_state(r["press_alive"], r["press_body_enabled"], r["press_dead_counter"]), r["hold_ticks"], _format_key_event_ms(r["hold_time_ms"])])
			continue
		if i >= replay_events.size():
			var l: Dictionary = live_events[i]
			lines.append("  [%s #%d] MISSING IN REPLAY -- live pressed at tick %d (%s) pos=%s [%s], held %d tick(s) (%s), replay never pressed it" % [action, i, l["press_tick"], _format_key_event_ms(l["press_time_ms"]), l["press_position"], _format_hold_state(l["press_alive"], l["press_body_enabled"], l["press_dead_counter"]), l["hold_ticks"], _format_key_event_ms(l["hold_time_ms"])])
			continue
		var lv: Dictionary = live_events[i]
		var rv: Dictionary = replay_events[i]
		var tick_delta: int = rv["press_tick"] - lv["press_tick"]
		var ms_delta: float = (rv["press_time_ms"] - lv["press_time_ms"]) if (lv["press_time_ms"] >= 0.0 and rv["press_time_ms"] >= 0.0) else 0.0
		var hold_tick_delta: int = rv["hold_ticks"] - lv["hold_ticks"]
		var pos_delta: float = lv["press_position"].distance_to(rv["press_position"]) if (lv["press_position"] != null and rv["press_position"] != null) else -1.0
		# A hold-state mismatch (one side disabled/dead-counting at press
		# time, the other not) is flagged as its own kind of mismatch even
		# when tick/hold/position all happen to line up -- this is exactly
		# the signal a frozen-replay-stretch leaves on the press bracketing
		# it, see the big comment on _finish_key_event().
		var state_mismatch: bool = lv["press_alive"] != rv["press_alive"] or lv["press_body_enabled"] != rv["press_body_enabled"]
		var mismatched: bool = tick_delta != 0 or hold_tick_delta != 0 or pos_delta > DIAG_POSITION_EPSILON or state_mismatch
		var flag: String = ("  <== MISMATCH%s" % [" (hold-state differs!)" if state_mismatch else ""]) if mismatched else ""
		lines.append("  [%s #%d] live: tick %d (%s) pos=%s [%s] held %d tick(s) (%s) | replay: tick %d (%s) pos=%s [%s] held %d tick(s) (%s) | press-tick Δ=%d press-time Δ=%.1fms hold-tick Δ=%d pos-Δ=%.3f%s" % [action, i, lv["press_tick"], _format_key_event_ms(lv["press_time_ms"]), lv["press_position"], _format_hold_state(lv["press_alive"], lv["press_body_enabled"], lv["press_dead_counter"]), lv["hold_ticks"], _format_key_event_ms(lv["hold_time_ms"]), rv["press_tick"], _format_key_event_ms(rv["press_time_ms"]), rv["press_position"], _format_hold_state(rv["press_alive"], rv["press_body_enabled"], rv["press_dead_counter"]), rv["hold_ticks"], _format_key_event_ms(rv["hold_time_ms"]), tick_delta, ms_delta, hold_tick_delta, pos_delta, flag])
	return lines


# FROZEN STRETCH DETECTION -- added 2026-08-30 alongside the alive/
# body_enabled/dead_counter fields above, after the first real report
# showed EVERY press-tick/hold-tick matching exactly (input timing is
# correct) while replay position AND wp_game_data.play_time both sat
# completely unchanged for hundreds of consecutive ticks at several points
# that live sailed straight through without pausing at all. A per-press
# view only shows the two presses bracketing a stretch like that; this
# scans the whole tick-by-tick log directly for "position AND play_time
# (when known) didn't move at all, `min_ticks` ticks or more in a row" and
# reports each one with its tick range, real-time length, and the
# alive/body_enabled/dead_counter state at its start -- exactly the
# evidence needed to confirm or rule out "stuck in the disabled/dead-
# counter hold" as the cause. min_ticks=10 (~0.17s) is well above normal
# single-tick landing/collision jitter but well below a genuine hold
# (the shortest one seen in that first report was ~127 ticks).
func _find_frozen_stretches(flat: Array, min_ticks: int = 10) -> Array:
	var stretches: = []
	if flat.empty():
		return stretches
	var stretch_start: = 0
	for i in range(1, flat.size() + 1):
		var same_as_prev: = false
		if i < flat.size():
			var prev: Dictionary = flat[i - 1]
			var cur: Dictionary = flat[i]
			var prev_pos = prev.get("position", null)
			var cur_pos = cur.get("position", null)
			var pos_same: bool = (prev_pos != null and cur_pos != null and prev_pos.distance_to(cur_pos) <= DIAG_POSITION_EPSILON)
			var time_same: bool = true # unknown play_time on either side can't disprove "frozen" by itself
			if prev.has("play_time") and cur.has("play_time"):
				time_same = abs(prev["play_time"] - cur["play_time"]) <= 0.0005
			same_as_prev = pos_same and time_same
		if not same_as_prev or i == flat.size():
			var length: = i - stretch_start
			if length >= min_ticks:
				var s: Dictionary = flat[stretch_start]
				stretches.append({
					"start_tick": stretch_start,
					"end_tick": i - 1,
					"length_ticks": length,
					"position": s.get("position", null),
					"play_time_ms": (s["play_time"] * 1000.0) if s.get("play_time", null) != null else -1.0,
					"alive": s.get("alive", null),
					"body_enabled": s.get("body_enabled", null),
					"dead_counter": s.get("dead_counter", null),
				})
			stretch_start = i
	return stretches


func _format_frozen_stretches_section(label: String, flat: Array) -> Array:
	var lines: = []
	var stretches: = _find_frozen_stretches(flat)
	lines.append("-- %s: %d frozen stretch(es) of 10+ consecutive ticks with unchanged position%s --" % [label, stretches.size(), " and play_time" if not flat.empty() and flat[0].has("play_time") else " (play_time not available on this build/entry)"])
	for s in stretches:
		lines.append("  ticks %d-%d (%d tick(s) stuck) at pos=%s, play_time held at %s -- [%s]" % [s["start_tick"], s["end_tick"], s["length_ticks"], s["position"], _format_key_event_ms(s["play_time_ms"]), _format_hold_state(s["alive"], s["body_enabled"], s["dead_counter"])])
	return lines


func _build_key_event_report_text(live_flat: Array, replay_flat: Array, compare_ticks: int, coverage_incomplete: bool) -> String:
	var dt: Dictionary = OS.get_datetime()
	var lines: = []
	lines.append("Key Event report -- %04d-%02d-%02d %02d:%02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]])
	lines.append("Auto-generated by Debug Mode the instant Play Macro playback finished. One line per discrete press/release of each recorded action (Jump/Dash/Left/Right) -- press tick + millisecond timestamp (off wp_game_data.play_time, the same clock the game's own top-left timer reads), hold duration, and position, live vs replay side by side. Same underlying per-tick data as the Divergence Diagnostics report above (see that one for the full per-tick field dump if this doesn't pin things down) -- this just reads at the level of 'what did the player actually press,' not 'what did every field do.'")
	lines.append("live ticks: %d, replay ticks: %d" % [live_flat.size(), replay_flat.size()])
	if coverage_incomplete:
		lines.append("WARNING: diagnostic coverage was incomplete -- comparison below is limited to the first %d tick(s) that are guaranteed to line up tick-for-tick on both sides (see the Divergence Diagnostics report's own warning for why). Events built from anything after that point are not shown." % [compare_ticks])
	lines.append("")
	var live_capped: = _cap_flat_log(live_flat, compare_ticks)
	var replay_capped: = _cap_flat_log(replay_flat, compare_ticks)
	var any_mismatch: = false
	for action in PRACTICE_RECORD_ACTIONS:
		var live_events: = _build_key_events_for_action(live_capped, action)
		var replay_events: = _build_key_events_for_action(replay_capped, action)
		lines.append("== %s -- %d live press(es), %d replay press(es) ==" % [action, live_events.size(), replay_events.size()])
		if live_events.empty() and replay_events.empty():
			lines.append("  (never pressed, either side)")
		else:
			var action_lines: = _compare_key_events_for_action(action, live_events, replay_events)
			for line in action_lines:
				if line.find("MISMATCH") != -1 or line.find("MISSING") != -1 or line.find("EXTRA") != -1:
					any_mismatch = true
			lines.append_array(action_lines)
		lines.append("")
	if not any_mismatch:
		lines.append("Every recorded press/release matched between live and replay -- same tick offset, same hold duration, same position (within %.3f units), for every action. If the replay still looks/feels wrong despite that, whatever's different isn't in the input timing itself -- check the Divergence Diagnostics report above for a state field (velocity, dash_cooldown, etc.) that diverged even with matching input." % [DIAG_POSITION_EPSILON])
	lines.append("")
	lines.append_array(_format_frozen_stretches_section("LIVE", live_capped))
	lines.append_array(_format_frozen_stretches_section("REPLAY", replay_capped))
	lines.append("(A frozen stretch on REPLAY with no similar-length, similar-tick stretch on LIVE -- especially one where alive=False/enabled=False/dead_ctr>0 -- means the replay got stuck in the disabled/respawn-hold state at a point live sailed straight through. That's a real desync, not a settling artifact.)")
	return "\n".join(lines)


func _write_key_event_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/key_event_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


# THE FIX (2026-08-30, user request): called from BOTH of
# _advance_practice_playback()'s exit points -- the clean "finished" branch
# (which already had its own, narrower version of this) and the "died mid-
# macro" branch (which previously auto-saved nothing at all, the exact
# opposite of what you'd want -- a death IS the interesting case). Bundles
# all three auto-savable reports behind their own existing enable toggles, so
# turning one on is still all that's needed for it to fire automatically
# every time a Play Macro run ends, without a single manual button press:
#   - the key-event report, whenever Debug Mode is on (unchanged condition
#     from before this fix -- only the trigger SITES changed)
#   - the Divergence Diagnostics report, whenever Diagnostic Logging is on
#     (a strict superset of Debug Mode being on, since Debug Mode forces
#     this on too -- so this also covers "just Diagnostic Logging by
#     itself, Debug Mode never touched")
#   - the Restore Drift report, whenever Restore Drift Diagnostics is on
#     AND at least one restore has actually been observed (avoids a useless
#     "nothing observed yet" log line firing on every single playback for
#     someone who turned the toggle on but never triggered a restore)
# Each of the three functions this calls already no-ops safely (with its own
# explanatory log line) if its own data happens to be empty, so there's no
# real risk of this spamming useless output when only some are on.
func _auto_generate_playback_reports() -> void:
	if _debug_mode_enabled:
		_auto_generate_key_event_report()
	if _diag_enabled:
		_on_compare_diagnostics_pressed()
	if _restore_drift_enabled and not _restore_drift_log.empty():
		_on_save_restore_drift_report_pressed()


# Called from _advance_practice_playback()'s finish branch, ONLY when Debug
# Mode is on -- see _on_toggle_debug_mode_pressed(). Mirrors
# _on_compare_diagnostics_pressed()'s own live/replay/coverage setup exactly
# (same _flatten_diag_live() / _diag_replay_log / _diag_coverage_prefix_ticks()
# calls) so the two reports are always talking about the same tick range,
# just rendered two different ways.
func _auto_generate_key_event_report() -> void:
	var live: = _flatten_diag_live()
	var replay: = _diag_replay_log
	if live.empty() or replay.empty():
		_log_action("Debug Mode: skipped auto key-event report -- no comparable diagnostic data (live=%d tick(s), replay=%d tick(s)). This shouldn't normally happen while Debug Mode is on, since it forces Diagnostic Logging on automatically -- if you're seeing this, Diagnostic Logging was probably switched off again, or nothing was recorded/played back yet." % [live.size(), replay.size()], null)
		return
	var overlap_count: = min(live.size(), replay.size())
	var safe_ticks: = _diag_coverage_prefix_ticks()
	var coverage_incomplete: = safe_ticks < overlap_count
	var compare_ticks: int = safe_ticks if coverage_incomplete else overlap_count
	var report_text: = _build_key_event_report_text(live, replay, compare_ticks, coverage_incomplete)
	var path: = _write_key_event_report(report_text)
	_log_action("Debug Mode: key-event comparison report auto-saved -- %s" % [path], null)


# ----------------------------------------------------------------------
#  Restore Drift Diagnostics
# ----------------------------------------------------------------------
# THE POINT: Divergence Diagnostics already proved WHERE the problem is
# (position, starting 2-3 ticks after a restore) and Playback Settle proved
# it is NOT a brief, self-correcting wobble -- holding zero input for up to
# 5 extra ticks after a restore changed nothing, the final drift was
# byte-for-byte identical either way. That means whatever Box2D is doing
# after a teleport-style restore, it isn't "still settling, give it more
# time" -- it converges to a genuinely different resting spot than
# continuous simulation would have landed on, and it does so fast.
#   Rather than guess at another physics mitigation (twice was enough),
# this only WATCHES: every time a restore happens (while this is toggled
# on), it records the player's position for RESTORE_DRIFT_WATCH_TICKS
# ticks afterward, with no attempt to influence what happens. Save Restore
# Drift Report dumps everything observed so far -- if the drift really is a
# fixed, deterministic amount (which the two identical divergence reports
# strongly suggest), this is what proves it and measures exactly what it
# is, so it can be directly compensated for -- e.g. nudging a restored
# grounded position by the measured constant BEFORE Box2D ever gets a
# chance to introduce it -- instead of fighting Box2D's behavior after the
# fact. That is future work; this only gathers the evidence.
func _arm_restore_drift_watch(p: WPPlayer, snap: Dictionary, velocity_before_reset_object: Vector2 = Vector2.ZERO, velocity_after_reset_object: Vector2 = Vector2.ZERO, reset_object_called: bool = true) -> void:
	if not _restore_drift_enabled:
		return
	_restore_drift_watches.append({
		"player": p,
		"start_position": p.position,
		"snap_velocity": snap.get("linear_velocity", Vector2.ZERO),
		"snap_grounded": snap.get("stick_to_ground_timer", 0.0) > 0.0,
		"ground_probe": _probe_ground_below(p),
		"sleep_state": _probe_body_sleep_state(p.body), # read-only, informational -- see that function's comment for the (now ruled out) theory it was gathering evidence for
		"reset_object_called": reset_object_called, # see the REVISED note in _restore_player() -- false whenever the restored snapshot leaves the player disabled (still mid a pre-round/hold), matching the real game's own respawn_player()-only usage of _reset_object()
		"velocity_before_reset_object": velocity_before_reset_object,
		"velocity_after_reset_object": velocity_after_reset_object,
		# Filled in later by _arm_playback_settle()/the settle-hold branch in
		# _advance_practice_playback() only for checkpoint 0. Internal stitch
		# restores intentionally never settle because that added unrecorded
		# neutral ticks and made the boundaries visible.
		"settle_armed": false,
		"settle_ticks_used": -1,
		"settle_hit_cap": false,
		"ticks_left": RESTORE_DRIFT_WATCH_TICKS,
		"positions": [p.position],
	})


# THE THEORY THIS IS FOR: live stays at a dead-stop, bit-for-bit identical
# position/velocity, for many ticks in a row at exactly the restores that
# then free-fall on replay (see the comment above _snapshot_is_at_rest()).
# That kind of perfect, unchanging stillness is what a SLEEPING Box2D body
# looks like -- physics engines routinely stop simulating a body once it's
# been at rest for a few frames, so it simply doesn't move even if its
# support is marginal or technically gone, until something wakes it. A
# teleport-restored body can't be "still asleep" -- it's freshly
# repositioned and starts fully awake, which would make it immediately
# discover (correctly, per real physics) that nothing is actually holding
# it up. If that's right, the fix isn't matching more script-level fields
# at restore time, it's suspending the body's simulation for a few ticks
# the way sleep already does -- but that's a real behavior change to test
# properly before shipping, not something to guess at from here. This only
# tries to CONFIRM it's happening: best-effort, since nothing in the
# shipped GDScript source ever reads or names a sleep-state property on
# this native body class, so the exact name (if this build exposes one at
# all) isn't something to guess with confidence -- tries the handful of
# names Box2D/Godot ports commonly use, and reports plainly if none of them
# exist on this build rather than assuming any one is right.
# Takes the body directly (untyped -- it's a native class TASTool.gd
# doesn't declare, always accessed by duck-typing elsewhere in this file
# too) rather than a WPPlayer, so this same probe logic is testable against
# any stand-in body without needing it to satisfy WPPlayer.body's exact
# native type.
#
# RULED OUT (2026-08-30): a Divergence Diagnostics report showed exactly
# this signature at tick 0 of a fresh recording -- live perfectly still,
# bit-for-bit identical position AND velocity=(0,0) for many ticks in a
# row, at a checkpoint whose own script-level grounded check
# (stick_to_ground_timer) said FALSE the whole time; replay free-fell from
# that same restored position and velocity immediately. That looked exactly
# like a sleeping-body signature, so an experiment (_try_sleep_body(),
# since removed) tried forcibly sleeping the body on every near-zero-
# velocity restore. The FOLLOW-UP restore drift report showed the forced
# write genuinely stuck on this build (read back immediately as applied --
# e.g. "awake=False->False") on every single restore, yet the divergence
# report from that same run showed the identical free-fall, unchanged. That
# rules sleep out cleanly: whatever drives gravity/movement here isn't
# gated on Box2D's own sleep flag at all. The REAL mechanism, confirmed
# straight from GooberDash's own decompiled source: a player sitting in a
# pre-round hold has `alive = false` and `body.enabled = false` (see the
# REVISED note on _reset_object() in _restore_player()) -- a genuinely
# disabled, unsimulated body, nothing to do with sleep/wake at all. This
# probe is kept only as a plain, read-only diagnostic (still shown in every
# restore-drift report) in case sleep state becomes relevant to some other
# investigation later -- it no longer backs any active theory or fix.
func _probe_body_sleep_state(body) -> String:
	if body == null:
		return "no body"
	var found: = []
	for prop_name in RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES:
		var val = body.get(prop_name)
		if val != null:
			found.append("%s=%s" % [prop_name, val])
	if found.empty():
		return "not exposed under any known name (tried: %s)" % ", ".join(RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES)
	return ", ".join(found)


# Read-only ground check via the real game's OWN native raycast helper --
# confirmed straight from the shipped source (WPPlayerAI.gd's
# detect_hazards()/_raycast_hazard(): "game.world.intersect_ray_fast(results,
# p, p + v)", and WPGame.gd's "onready var world: = $Box2DWorld as
# UpguysBox2DWorld") -- not a guess at collision layers, the same call the
# game's own AI already relies on. Casts straight down (+Y, matching the
# fall direction actually observed in restore drift data) from the restored
# position, up to RESTORE_DRIFT_GROUND_PROBE_DISTANCE. Returns the distance
# to whatever it hits, or -1.0 if nothing was hit within that range (or the
# native ray API wasn't reachable, e.g. no game/world yet). Never changes
# anything -- purely a measurement for the drift report to correlate
# against, testing the theory that a checkpoint captured the instant
# stick_to_ground_timer expired (grounded=False) but before the player
# actually left real Box2D contact will show a short probe distance right
# next to a since-observed large fall -- i.e. the "drift" is really the
# player correctly falling from a spot that was never truly resting to
# begin with, just still touching (per Box2D) for a moment past when the
# script-level timer said so.
func _probe_ground_below(p: WPPlayer) -> Dictionary:
	var out: = {"distance": -1.0, "label": ""}
	var g: = _find_game()
	if g == null:
		return out
	var world = g.get("world")
	if world == null or not world.has_method("intersect_ray_fast"):
		return out
	var from: = p.position
	var to: = p.position + Vector2(0, RESTORE_DRIFT_GROUND_PROBE_DISTANCE)
	var results: = {}
	if not world.intersect_ray_fast(results, from, to):
		return out
	out["distance"] = from.distance_to(results["position"])
	# Best-effort label of WHAT was hit, mirroring WPPlayerAI.gd's own
	# "f.get_collision_object().get_parent()" pattern (that's how it finds
	# the LevelNode to check collision_type == HAZARD) -- deliberately not
	# guessing at the HAZARD enum value ourselves here (better to show the
	# real node name/class and let a human eyeball it than risk mislabeling
	# something as "ground" when it's actually a hazard, or vice versa).
	var fixture = results.get("fixture")
	if fixture != null and fixture.has_method("get_collision_object"):
		var body = fixture.get_collision_object()
		if body != null and is_instance_valid(body):
			var owner: Node = body.get_parent()
			if owner != null:
				out["label"] = "%s (%s)" % [owner.name, owner.get_class()]
	return out


# Called once per physics tick, unconditionally, BEFORE the enabled/
# _tool_restricted() gate -- see DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN's big
# comment for the full reasoning. Reads state only; never modifies player/
# body fields itself (that stays exclusively the freeze block's own job,
# so this diagnostic can't be accused of changing the very behavior it's
# trying to observe).
#   Split into this "before" half and _death_diag_after_freeze() (called
# once the freeze block has actually run, if it does) rather than one
# single capture here, specifically so the tick death is first detected
# doesn't always show a false-positive "anomaly": this call necessarily
# runs BEFORE the freeze code that's about to zero velocity/disable the
# body THIS SAME tick, so capturing here unconditionally would make every
# death's first tick look identical to a freeze failure whether the real
# freeze worked or not. This half only records the tick's own state
# directly when the freeze block ISN'T going to run at all this tick
# (tool disabled/restricted/noclip on) -- in every other case it just
# handles edge-detection and leaves the actual capture to the "after" half.
func _death_diag_before_gate() -> void:
	var p: = _get_local_player()
	if p == null:
		return
	if not _debug_mode_enabled:
		# Keep edge state current without allocating logs or writing reports.
		_death_diag_active_watch = null
		_death_diag_ticks_since_respawn = -1
		_death_diag_prev_alive = p.alive
		return
	var tool_would_freeze: = enabled and not _tool_restricted() and not _noclip_enabled
	if not p.alive and _death_diag_prev_alive:
		# Death edge -- start a fresh watch. If one was already open
		# somehow (e.g. a death observed again before the previous
		# watch's tail finished -- shouldn't normally happen given the
		# short tail length, but not assumed impossible), finish it first
		# rather than silently discarding it.
		if _death_diag_active_watch != null:
			_finish_death_freeze_watch()
		_death_diag_active_watch = {
			"tool_enabled": enabled,
			"tool_restricted": _tool_restricted(),
			"noclip_enabled": _noclip_enabled,
			"practice_active": _practice_active,
			"practice_playback": _practice_playback,
			"pre_death_position": _freeze_last_alive_position,
			"post_guard_corrections_start": _post_guard_momentum_corrections,
			"entries": [],
		}
		_death_diag_ticks_since_respawn = -1
	if _death_diag_active_watch != null and not tool_would_freeze:
		# The freeze block below won't run at all this tick -- capture the
		# raw, uncorrected state right here, since nothing else will
		# observe this tick otherwise.
		_death_diag_record_tick(p, false)
	_death_diag_prev_alive = p.alive


# Called once per physics tick, only reached once _physics_process() has
# already passed the enabled/_tool_restricted() gate and the freeze block
# above it has had its chance to run -- captures the CORRECTED state for
# any tick the freeze actually applied (or, for a tick where noclip is on,
# defers to _death_diag_before_gate() having already captured it there,
# via the same tool_would_freeze check, to avoid double-counting a tick).
func _death_diag_after_freeze() -> void:
	if _death_diag_active_watch == null:
		return
	var tool_would_freeze: = enabled and not _tool_restricted() and not _noclip_enabled
	if not tool_would_freeze:
		return # already captured by _death_diag_before_gate() this tick
	var p: = _get_local_player()
	if p == null:
		return
	_death_diag_record_tick(p, true)


func _death_diag_record_tick(p: WPPlayer, tool_would_freeze: bool) -> void:
	_death_diag_active_watch["entries"].append({
		"alive": p.alive,
		"position": p.position,
		"linear_velocity": p.linear_velocity,
		"body_linear_velocity": (p.body.linear_velocity if p.body != null else null),
		"body_enabled": p.body_enabled,
		"body_dot_enabled": (p.body.enabled if p.body != null else null),
		"tool_would_freeze_this_tick": tool_would_freeze,
		# THE THIRTY-SIXTH-PASS FIX (2026-08-31, later still) -- user report:
		# "First jump broke this time, the velocity bug remains", sent right
		# after THE THIRTY-FIFTH-PASS FIX (which forced a native
		# _reset_object() call and got reverted for breaking jump). Every
		# single death_freeze_report captured across two full sessions (34
		# deaths) shows ZERO anomalies in position/velocity/body_enabled --
		# this file's own existing NOTE at the bottom of this report already
		# says why that might not be the whole picture: "It cannot see
		# rendering/interpolation... a visual smoothing effect between
		# physics ticks could look like drift even if the underlying physics
		# state above is perfectly static." p.position is a logical/script
		# property THIS FILE ITSELF writes every dead tick -- of course it
		# reads back clean. It says nothing about whether the PHYSICS BODY's
		# own rendered transform actually followed that write. Capturing
		# body.global_position here (previously only body.linear_velocity
		# was captured, never the body's own position) lets the report below
		# compare the two directly and flag it if they ever diverge -- which
		# would mean the corpse is logically frozen but visibly still
		# somewhere else, exactly matching "I saw it get thrown" while every
		# prior report kept coming back clean.
		"body_global_position": (p.body.global_position if p.body != null else null),
	})
	if p.alive:
		if _death_diag_ticks_since_respawn < 0:
			_death_diag_ticks_since_respawn = 0
		else:
			_death_diag_ticks_since_respawn += 1
	var entries_count: int = _death_diag_active_watch["entries"].size()
	var respawn_tail_done: = _death_diag_ticks_since_respawn >= DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN
	if respawn_tail_done or entries_count >= DEATH_DIAG_MAX_ENTRIES:
		_finish_death_freeze_watch()


func _finish_death_freeze_watch() -> void:
	if _death_diag_active_watch == null:
		return
	var watch: Dictionary = _death_diag_active_watch
	_death_diag_active_watch = null
	_death_diag_ticks_since_respawn = -1
	var text: = _build_death_freeze_report_text(watch)
	var path: = _write_death_freeze_report(text)
	_log_action("Death Freeze Diagnostics: report auto-saved -- %s" % path, null)


# Flags exactly the failure modes THE THIRTIETH/THIRTY-FIRST/THIRTY-
# SECOND-PASS FIXES each individually targeted, plus the two "is it even
# running" possibilities neither of them could have caught -- see
# DEATH_DIAG_TAIL_TICKS_AFTER_RESPAWN's own big comment.
func _build_death_freeze_report_text(watch: Dictionary) -> String:
	var lines: = []
	var dt: Dictionary = OS.get_datetime()
	lines.append("Death Freeze Diagnostics report -- %04d-%02d-%02d %02d:%02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]])
	lines.append("tool_enabled=%s tool_restricted=%s noclip_enabled=%s practice_active=%s practice_playback=%s" % [watch["tool_enabled"], watch["tool_restricted"], watch["noclip_enabled"], watch["practice_active"], watch["practice_playback"]])
	lines.append("post-native leaked-momentum corrections during this death window: %d" % [_post_guard_momentum_corrections - int(watch.get("post_guard_corrections_start", _post_guard_momentum_corrections))])
	if watch["tool_enabled"] == false or watch["tool_restricted"] == true or watch["noclip_enabled"] == true:
		lines.append("*** THE FREEZE NEVER RAN AT ALL THIS DEATH *** -- at least one of tool_enabled=false / tool_restricted=true / noclip_enabled=true was true at the moment death was detected, which alone explains unfrozen momentum with no bug in the freeze logic itself needed. See _tool_restricted() (gated by only_active_in_debug_or_solo + OS.is_debug_build() + gd.is_time_trial) if tool_restricted=true is what's showing here.")
	lines.append("pre_death_position=%s" % watch["pre_death_position"])
	lines.append("")
	var entries: Array = watch["entries"]
	var prev_entry = null
	var flagged_nonzero_velocity: = false
	var flagged_body_enabled: = false
	var flagged_position_moved: = false
	var flagged_body_transform_diverged: = false
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var flags: = []
		if not e["alive"]:
			if not e["tool_would_freeze_this_tick"]:
				# Gated off this tick -- the freeze genuinely never ran, so
				# raw velocity/body state here is EXPECTED, not a bug in the
				# freeze logic itself (already called out at the report's
				# top). Flagging it again per-tick here would just be noise
				# on top of that -- the interesting anomaly case is below,
				# for ticks the freeze SHOULD have corrected.
				flags.append("TOOL WOULD NOT FREEZE THIS TICK (gated off)")
			else:
				if not (is_equal_approx(e["linear_velocity"].x, 0.0) and is_equal_approx(e["linear_velocity"].y, 0.0)):
					flags.append("VELOCITY NONZERO WHILE DEAD (freeze should have zeroed this)")
					flagged_nonzero_velocity = true
				if e["body_enabled"] == true or e["body_dot_enabled"] == true:
					flags.append("BODY STILL ENABLED WHILE DEAD (freeze should have disabled this)")
					flagged_body_enabled = true
				if prev_entry != null and not prev_entry["alive"] and prev_entry["tool_would_freeze_this_tick"]:
					var moved: float = e["position"].distance_to(prev_entry["position"])
					if moved > 0.01:
						flags.append("POSITION MOVED %.4f UNITS WHILE DEAD AND SUPPOSEDLY FROZEN" % moved)
						flagged_position_moved = true
				# THE THIRTY-SIXTH-PASS FIX -- see _death_diag_record_tick()'s
				# own comment on body_global_position for why this check
				# exists: p.position being frozen (confirmed clean, every
				# time, for 34 straight deaths) says nothing about whether
				# the physics BODY's own rendered transform actually matches
				# it. If they diverge, the player could be seeing the corpse
				# somewhere other than where this freeze thinks it put it.
				if e["body_global_position"] != null:
					var body_drift: float = e["body_global_position"].distance_to(e["position"])
					if body_drift > 0.5:
						flags.append("BODY TRANSFORM DIVERGED FROM FROZEN POSITION BY %.4f UNITS (rendered corpse may not be where player.position says it is)" % body_drift)
						flagged_body_transform_diverged = true
		var flag_text: = (" <== " + ", ".join(flags)) if not flags.empty() else ""
		lines.append("  tick %d: alive=%s pos=%s body_pos=%s vel=%s body_vel=%s body_enabled=%s body.enabled=%s would_freeze=%s%s" % [i, e["alive"], e["position"], e["body_global_position"], e["linear_velocity"], e["body_linear_velocity"], e["body_enabled"], e["body_dot_enabled"], e["tool_would_freeze_this_tick"], flag_text])
		prev_entry = e
	lines.append("")
	if not flagged_nonzero_velocity and not flagged_body_enabled and not flagged_position_moved and not flagged_body_transform_diverged:
		lines.append("No anomalies flagged above -- velocity stayed zero, the body stayed disabled, position never moved on any tick observed as dead, AND the physics body's own rendered transform (body_pos) matched the frozen logical position every tick. If momentum was still visible to the user during THIS death, it happened somewhere this capture doesn't look (see the note below) or somewhere between two of these ticks that this per-physics-tick capture can't resolve any finer.")
	lines.append("NOTE: this only observes physics-tick state (position/body_pos/velocity/body flags) exactly as _physics_process() and this freeze see them. It cannot see rendering/interpolation happening BETWEEN two physics ticks (a visual smoothing effect there could look like drift even if the physics-tick state above is perfectly static at every sampled instant), and it cannot see native collision response happening to some OTHER object (e.g. if what's actually moving is a hazard/platform the player is attached to, not the player itself).")
	return "\n".join(lines) + "\n"


func _write_death_freeze_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/death_freeze_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


# Called once per physics tick, unconditionally (see the call site in
# _physics_process()) -- independent of Macro Bot Mode / diag / anything
# else being active, so a restore triggered from anywhere (the checkpoint
# editor's Restore button, Macro Bot auto-respawn, Play Macro's boundary
# resync) gets the same fixed-length observation window.
func _advance_restore_drift_watches() -> void:
	if _restore_drift_watches.empty():
		return
	var remaining: = []
	for watch in _restore_drift_watches:
		var p: WPPlayer = watch["player"]
		if not is_instance_valid(p):
			continue # dropped silently -- nothing useful left to measure
		watch["positions"].append(p.position)
		watch["ticks_left"] -= 1
		if watch["ticks_left"] > 0:
			remaining.append(watch)
		else:
			_finish_restore_drift_watch(watch)
	_restore_drift_watches = remaining
	_refresh_restore_drift_ui()


func _finish_restore_drift_watch(watch: Dictionary) -> void:
	var positions: Array = watch["positions"]
	var start: Vector2 = watch["start_position"]
	var stabilized_tick: = -1
	for i in range(1, positions.size()):
		var step: float = positions[i].distance_to(positions[i - 1])
		if stabilized_tick == -1 and step < RESTORE_DRIFT_STABLE_EPSILON:
			stabilized_tick = i
	_restore_drift_log.append({
		"start_position": start,
		"final_position": positions.back(),
		"total_drift": positions.back().distance_to(start),
		"snap_velocity": watch["snap_velocity"],
		"snap_grounded": watch["snap_grounded"],
		"is_stationary": watch["snap_velocity"].length() < PLAYBACK_SETTLE_VELOCITY_EPSILON,
		"ground_probe_distance": watch["ground_probe"]["distance"],
		"ground_probe_label": watch["ground_probe"]["label"],
		"sleep_state": watch["sleep_state"],
		"reset_object_called": watch["reset_object_called"],
		"velocity_before_reset_object": watch["velocity_before_reset_object"],
		"velocity_after_reset_object": watch["velocity_after_reset_object"],
		"settle_armed": watch["settle_armed"],
		"settle_ticks_used": watch["settle_ticks_used"],
		"settle_hit_cap": watch["settle_hit_cap"],
		"stabilized_tick": stabilized_tick,
		"tick_count": positions.size() - 1,
	})


func _on_toggle_restore_drift_pressed() -> void:
	_restore_drift_enabled = not _restore_drift_enabled
	_style_button(_restore_drift_toggle_button, COLOR_PINK if _restore_drift_enabled else COLOR_BLUE)
	_restore_drift_toggle_button.text = "Restore Drift Diagnostics: ON" if _restore_drift_enabled else "Restore Drift Diagnostics: OFF"
	if _restore_drift_enabled:
		_restore_drift_watches = []
		_restore_drift_log = []
	_log_action("Restore Drift Diagnostics %s -- %s" % ["ON" if _restore_drift_enabled else "OFF", "every checkpoint restore from here on is measured for %d ticks afterward" % RESTORE_DRIFT_WATCH_TICKS if _restore_drift_enabled else "existing captured data is kept until you toggle back on"], null)
	_refresh_restore_drift_ui()


# Summarizes total_drift across a set of log entries: count/mean/min/max/
# spread of the drift itself, plus the mean ground-probe distance among
# whichever of those entries actually got a hit (a probe of -1.0 means "no
# ground found within RESTORE_DRIFT_GROUND_PROBE_DISTANCE" and is excluded
# from that average rather than dragging it down).
func _summarize_drift_bucket(entries: Array) -> Dictionary:
	if entries.empty():
		return {"count": 0}
	var total: = 0.0
	var lowest: float = entries[0]["total_drift"]
	var highest: float = entries[0]["total_drift"]
	var probe_total: = 0.0
	var probe_count: = 0
	for e in entries:
		var d: float = e["total_drift"]
		total += d
		lowest = min(lowest, d)
		highest = max(highest, d)
		if e["ground_probe_distance"] >= 0.0:
			probe_total += e["ground_probe_distance"]
			probe_count += 1
	return {
		"count": entries.size(),
		"mean": total / entries.size(),
		"min": lowest,
		"max": highest,
		"spread": highest - lowest,
		"mean_probe": (probe_total / probe_count if probe_count > 0 else -1.0),
		"probe_count": probe_count,
	}


func _on_save_restore_drift_report_pressed() -> void:
	if _restore_drift_log.empty():
		_log_action("Restore Drift Diagnostics: no completed restore(s) observed yet -- turn diagnostics on, then trigger some checkpoint restores (die/respawn, Play Macro, etc.) before saving", null)
		return
	var lines: = []
	lines.append("Restore Drift report -- %s" % _format_time())
	lines.append("%d restore(s) observed, %d watch tick(s) each, stabilized = first tick whose position moved less than %.3f from the tick before, ground probe casts up to %.0f units straight down from the restored position, body_sleep tries reading %s off the player's body (best-effort -- may report \"not exposed\" if this build doesn't have any of them; purely informational now -- forcing sleep was tried and ruled out, see _restore_player()), reset_object_called=<false whenever this restore left the player disabled (body_enabled=false in the snapshot -- a pre-round/hold moment, per the real game's own source) -- the real game's respawn_player() is the ONLY place that ever calls _reset_object(), always with the player enabled first, so this now skips it in that state to match>, reset_object_velocity=<right before p._reset_object() is called>-><right after> (both equal the pre-restore velocity, unchanged, whenever reset_object_called=false above) so a phantom velocity introduced specifically by that one native call is visible as a before!=after mismatch here, settle=<did Playback Settle arm for this restore, and if so did it end because the position genuinely looked stable or because it just gave up at the %d-tick cap> (only checkpoint-0/Play-Macro-boundary restores ever arm it -- manual/editor restores always show \"n/a\")" % [_restore_drift_log.size(), RESTORE_DRIFT_WATCH_TICKS, RESTORE_DRIFT_STABLE_EPSILON, RESTORE_DRIFT_GROUND_PROBE_DISTANCE, RESTORE_DRIFT_SLEEP_PROPERTY_CANDIDATES, PLAYBACK_SETTLE_MAX_TICKS])
	lines.append("")
	# Bucketed by what the snapshot itself said, NOT just the ground flag --
	# a restore into a snapshot that was still genuinely MOVING (e.g. a
	# death mid-run, or the player just continuing to play normally after
	# an auto-respawn) will obviously rack up position change over the next
	# 20 ticks with no relation to this investigation at all, so it's
	# reported but excluded from the drift stats below. The interesting
	# split is between "at rest" (grounded AND ~zero velocity -- what
	# Playback Settle targets) and "stationary but NOT grounded" (~zero
	# velocity but stick_to_ground_timer already expired) -- the latter is
	# exactly the "coyote time just ran out, but Box2D was probably still
	# actually touching the ground a moment longer than the script-level
	# timer says" case this session's data has been pointing at.
	var at_rest: = []
	var airborne_stationary: = []
	var moving_count: = 0
	for i in range(_restore_drift_log.size()):
		var e: Dictionary = _restore_drift_log[i]
		var probe_text: String = "nothing hit within %.0f" % RESTORE_DRIFT_GROUND_PROBE_DISTANCE
		if e["ground_probe_distance"] >= 0.0:
			var probe_label: String = e["ground_probe_label"] if e["ground_probe_label"] != "" else "unlabeled"
			probe_text = "%.3f (%s)" % [e["ground_probe_distance"], probe_label]
		var settle_text: String = "n/a (never armed)"
		if e["settle_armed"]:
			if e["settle_ticks_used"] < 0:
				# Armed but this session's data predates the hold branch ever
				# reporting back (or playback was aborted/interrupted mid-hold)
				# -- shouldn't happen in a normal run, flagged rather than
				# silently shown as 0 ticks.
				settle_text = "armed but outcome unknown"
			elif e["settle_hit_cap"]:
				settle_text = "armed, gave up at the %d-tick cap (never read as stable)" % e["settle_ticks_used"]
			else:
				settle_text = "armed, settled in %d tick(s)" % e["settle_ticks_used"]
		lines.append("[restore %d] start=%s final=%s drift=%.6f stabilized_tick=%s snap_velocity=%s snap_grounded=%s ground_below=%s body_sleep=%s reset_object_called=%s reset_object_velocity=%s->%s settle=%s" % [i, e["start_position"], e["final_position"], e["total_drift"], (str(e["stabilized_tick"]) if e["stabilized_tick"] >= 0 else "never within %d ticks" % e["tick_count"]), e["snap_velocity"], e["snap_grounded"], probe_text, e["sleep_state"], e["reset_object_called"], e["velocity_before_reset_object"], e["velocity_after_reset_object"], settle_text])
		if not e["is_stationary"]:
			moving_count += 1
		elif e["snap_grounded"]:
			at_rest.append(e)
		else:
			airborne_stationary.append(e)
	lines.append("")
	if moving_count > 0:
		lines.append("%d restore(s) were already moving at the moment of restore -- excluded from the stats below as unrelated normal gameplay, not this investigation." % moving_count)
	var at_rest_stats: = _summarize_drift_bucket(at_rest)
	var airborne_stats: = _summarize_drift_bucket(airborne_stationary)
	if at_rest_stats["count"] > 0:
		lines.append("AT REST (grounded + ~zero velocity): %d sample(s), mean drift=%.6f, min=%.6f, max=%.6f, spread=%.6f, mean ground-below=%s" % [at_rest_stats["count"], at_rest_stats["mean"], at_rest_stats["min"], at_rest_stats["max"], at_rest_stats["spread"], ("%.3f" % at_rest_stats["mean_probe"]) if at_rest_stats["probe_count"] > 0 else "n/a"])
	else:
		lines.append("AT REST (grounded + ~zero velocity): no samples.")
	if airborne_stats["count"] > 0:
		lines.append("STATIONARY BUT NOT GROUNDED (~zero velocity, stick_to_ground_timer already expired): %d sample(s), mean drift=%.6f, min=%.6f, max=%.6f, spread=%.6f, mean ground-below=%s" % [airborne_stats["count"], airborne_stats["mean"], airborne_stats["min"], airborne_stats["max"], airborne_stats["spread"], ("%.3f" % airborne_stats["mean_probe"]) if airborne_stats["probe_count"] > 0 else "n/a"])
	else:
		lines.append("STATIONARY BUT NOT GROUNDED: no samples.")
	lines.append("")
	if at_rest_stats["count"] > 0 and at_rest_stats["spread"] < 0.01:
		lines.append("-> AT REST restores drift by a fixed, negligible-spread amount -- consistent with a small, constant, directly-compensable offset.")
	if airborne_stats["count"] > 0 and airborne_stats["spread"] >= 1.0:
		lines.append("-> STATIONARY-BUT-NOT-GROUNDED restores drift by wildly different amounts restore to restore -- NOT a fixed constant. That rules out a single compensation offset for this bucket. If the drift magnitude tracks the ground-below distance (bigger gap = bigger drift), this isn't a settle artifact at all -- it's just correct free-fall from a spot that was never really resting, because Box2D's real contact outlasted the script-level stick_to_ground_timer that our snapshot relied on to call it \"grounded.\"")
	var text: = "\n".join(lines) + "\n"
	var path: = _write_restore_drift_report(text)
	_log_action("Restore Drift Diagnostics: report saved (%d restore(s)) -- %s" % [_restore_drift_log.size(), path], null)


func _write_restore_drift_report(text: String) -> String:
	var dir: = Directory.new()
	if not dir.dir_exists(DIAG_DIR):
		dir.make_dir_recursive(DIAG_DIR)
	var path: = "%s/restore_drift_report_%d.txt" % [DIAG_DIR, OS.get_unix_time()]
	var f: = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()
	return path


func _refresh_restore_drift_ui() -> void:
	if _restore_drift_status_label == null:
		return
	_restore_drift_status_label.text = "restore drift: %d completed observation(s), %d in progress" % [_restore_drift_log.size(), _restore_drift_watches.size()]


# ----------------------------------------------------------------------
#  Debug Noclip -- free flight for investigation only. Disables the
#  player's physics body outright (so nothing here fights the native
#  controller/Box2D) and drives position directly from raw input every
#  tick; toggling off hands control back exactly the way _restore_player()
#  does (a real _reset_object() call), so Box2D gets a clean handoff
#  either way rather than resuming mid-whatever-state noclip left it in.
#  Controls: left/right to move horizontally, Jump to rise, Dash to
#  descend (dash itself is inert while noclip is on -- there's nothing
#  else useful for a fourth direction, and this way no new input action
#  needs to be defined just for this debug tool).
# ----------------------------------------------------------------------
func _on_toggle_noclip_pressed() -> void:
	_noclip_enabled = not _noclip_enabled
	_style_button(_noclip_toggle_button, COLOR_PINK if _noclip_enabled else COLOR_BLUE)
	_noclip_toggle_button.text = "Debug Noclip: ON" if _noclip_enabled else "Debug Noclip: OFF"
	var player: = _get_local_player()
	if player == null:
		_log_action("Debug Noclip: %s (no local player found to apply it to yet)" % ["ON" if _noclip_enabled else "OFF"], null)
		return
	if _noclip_enabled:
		_noclip_prev_body_enabled = player.body_enabled
		player.body_enabled = false
		if player.body != null:
			player.body.enabled = false
			player.body.linear_velocity = Vector2.ZERO
		player.linear_velocity = Vector2.ZERO
	else:
		player.body_enabled = _noclip_prev_body_enabled
		if player.body != null:
			player.body.enabled = _noclip_prev_body_enabled
		player._reset_object()
	var recording_note: String = ""
	if _practice_active:
		# THE ELEVENTH-PASS FIX -- see the big comment in _physics_process()
		# on why noclip and macro recording can't both capture at once.
		recording_note = " -- Macro Bot Mode recording is PAUSED while this is on, resuming automatically once it's off again" if _noclip_enabled else " -- Macro Bot Mode recording has resumed"
	_log_action("Debug Noclip: %s%s" % ["ON" if _noclip_enabled else "OFF", recording_note], null)


# Called every physics tick from _physics_process() -- a no-op unless
# _noclip_enabled. Gated by _tool_restricted() same as everything else
# (see the call site), so it can never fly the player during a real
# competitive match.
func _apply_noclip_movement(delta: float) -> void:
	if not _noclip_enabled:
		return
	var player: = _get_local_player()
	if player == null:
		return
	if not player.alive:
		# Hazards (spikes, etc.) still kill the player even with the
		# physics body disabled -- turning body_enabled/body.enabled off
		# only stops Box2D collision, and hazard detection almost
		# certainly isn't routed through that (it looks like a separate
		# trigger, since noclip visibly doesn't stop it). Best-effort
		# recovery so noclip stays usable for exploring hazard-heavy
		# sections: revive immediately. This can't undo whatever the
		# native death sequence already fired for the one tick alive was
		# false (a sound, a camera shake, a respawn timer starting) --
		# this is a debug tool working around code it can't see inside of,
		# not a guarantee that hazards are truly inert while noclip is on.
		player.alive = true
		player.dead_counter = 0
	var move: = Vector2.ZERO
	if Input.is_action_pressed(ACTION_MOVE_RIGHT):
		move.x += 1.0
	if Input.is_action_pressed(ACTION_MOVE_LEFT):
		move.x -= 1.0
	if Input.is_action_pressed(ACTION_JUMP):
		move.y -= 1.0
	if Input.is_action_pressed(ACTION_DASH):
		move.y += 1.0
	if move != Vector2.ZERO:
		player.position += move.normalized() * NOCLIP_SPEED * delta


func _spawn_checkpoint_marker(player: WPPlayer, pos: Vector2) -> Node2D:
	var parent: = player.get_parent()
	if parent == null:
		return null
	var marker: = CheckpointMarker.new()
	marker.position = pos
	marker.visible = not _overlay_hidden
	parent.add_child(marker)
	return marker


# Keeps the most-recently-placed checkpoint visually distinct (pink) from
# earlier ones (blue) so it's obvious at a glance which one death will send
# you back to.
func _restyle_practice_markers() -> void:
	for i in _practice_markers.size():
		var m = _practice_markers[i]
		if is_instance_valid(m):
			m.setup(COLOR_PINK if i == _practice_markers.size() - 1 else COLOR_BLUE, str(i), _header_font)


func _set_practice_markers_visible(markers_visible: bool) -> void:
	for marker in _practice_markers:
		if is_instance_valid(marker):
			marker.visible = markers_visible


func _set_hitbox_viewer_enabled(value: bool) -> void:
	_hitbox_viewer_enabled = value
	SavedSettings.set_value(SETTING_HITBOX_VIEWER, value)
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.call("set_show_hitboxes", value)
	_refresh_practice_ui()


func _set_hitbox_category(category: String, value: bool) -> void:
	if not _hitbox_categories.has(category):
		return
	_hitbox_categories[category] = value
	SavedSettings.set_value(SETTING_HITBOX_CATEGORY_PREFIX + category, value)
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.call("set_hitbox_category", category, value)
	_refresh_hitbox_category_ui()


func _on_hitbox_category_toggled(value: bool, category: String) -> void:
	_set_hitbox_category(category, value)


func _refresh_hitbox_category_ui() -> void:
	if _hitbox_category_row != null:
		_hitbox_category_row.visible = _hitbox_viewer_enabled
	for category in _hitbox_category_buttons.keys():
		var button: Button = _hitbox_category_buttons[category]
		if button != null:
			button.set_pressed_no_signal(bool(_hitbox_categories.get(category, false)))
			_style_button(button, COLOR_PINK if button.pressed else COLOR_BLUE, 12, 3)


func _on_toggle_hitbox_viewer_pressed() -> void:
	_set_hitbox_viewer_enabled(not _hitbox_viewer_enabled)
	_log_action("Hitbox Viewer %s" % ("ON" if _hitbox_viewer_enabled else "OFF"), null)


func _set_trajectory_preview_enabled(value: bool) -> void:
	_trajectory_preview_enabled = value
	SavedSettings.set_value(SETTING_TRAJECTORY_PREVIEW, value)
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.call("set_show_trajectory", value)
	_refresh_practice_ui()


func _on_toggle_trajectory_preview_pressed() -> void:
	_set_trajectory_preview_enabled(not _trajectory_preview_enabled)
	_log_action("Trajectory Preview %s" % ("ON" if _trajectory_preview_enabled else "OFF"), null)


func _set_input_display_enabled(value: bool) -> void:
	_input_display_enabled = value
	SavedSettings.set_value(SETTING_INPUT_DISPLAY, value)
	if _input_display != null and is_instance_valid(_input_display):
		_input_display.call("set_display_enabled", value)
	_refresh_practice_ui()


func _on_toggle_input_display_pressed() -> void:
	_set_input_display_enabled(not _input_display_enabled)
	_log_action("Input Display %s" % ("ON" if _input_display_enabled else "OFF"), null)


func _set_input_display_detailed(value: bool) -> void:
	_input_display_detailed = value
	SavedSettings.set_value(SETTING_INPUT_DISPLAY_DETAILED, value)
	if _input_display != null and is_instance_valid(_input_display):
		_input_display.call("set_detailed", value)
	_refresh_practice_ui()


func _on_toggle_input_display_detailed_pressed() -> void:
	_set_input_display_detailed(not _input_display_detailed)


func _set_input_display_hold_frames(value: bool) -> void:
	_input_display_hold_frames = value
	SavedSettings.set_value(SETTING_INPUT_DISPLAY_HOLD_FRAMES, value)
	if _input_display != null and is_instance_valid(_input_display):
		_input_display.call("set_show_hold_frames", value)
	_refresh_practice_ui()


func _on_toggle_input_display_hold_frames_pressed() -> void:
	_set_input_display_hold_frames(not _input_display_hold_frames)


func _on_toggle_visual_seam_polish_pressed() -> void:
	_visual_seam_polish_enabled = not _visual_seam_polish_enabled
	SavedSettings.set_value(SETTING_VISUAL_SEAM_POLISH, _visual_seam_polish_enabled)
	if not _visual_seam_polish_enabled:
		_visual_seam_filter_remaining = 0.0
		_visual_seam_output_valid = false
	else:
		call_deferred("_show_native_notify", "VISUAL SEAM POLISH", "Visual Seam Polish only tweens the displayed goober for 120ms. Physics and replay inputs stay unchanged.\n\nUse open, safe checkpoint areas when possible: during the blend the sprite may briefly overlap nearby spikes or walls even though the real hitbox does not.")
	_log_action("Visual Seam Polish %s (render-only)" % ("ON" if _visual_seam_polish_enabled else "OFF"), null)
	_refresh_practice_ui()


func _on_toggle_sync_moving_objects_pressed() -> void:
	_sync_moving_objects_enabled = not _sync_moving_objects_enabled
	SavedSettings.set_value(SETTING_SYNC_MOVING_OBJECTS, _sync_moving_objects_enabled)
	if _sync_moving_objects_enabled:
		call_deferred("_show_native_notify", "MOVING OBJECT SYNC", "Moving-object snapshots will be recorded at new checkpoints and restored during local playback.\n\nExisting macros remain playable, but old slots cannot contain world snapshots that were never recorded.")
	_log_action("Moving Object Sync %s" % ("ON" if _sync_moving_objects_enabled else "OFF"), null)
	_refresh_practice_ui()


# ----------------------------------------------------------------------
#  Macro Bot Mode -- stitched playback ("Play Macro")
# ----------------------------------------------------------------------
func _on_play_practice_macro_pressed() -> void:
	if _practice_segments.empty():
		_log_action("Macro Bot Mode: no committed segments yet -- place at least one checkpoint", null)
		return
	if _practice_playback:
		_log_action("Macro Bot Mode: playback already running", null)
		return
	var player: = _get_local_player()
	if player == null:
		_log_action("No local player found", null)
		return
	_practice_active = false # don't record over ourselves while replaying
	_release_all_injected_actions() # (also clears _practice_playback if it somehow was true; harmless)
	_build_practice_playback_frames()
	_practice_playback_index = 0
	_practice_playback_state_corrections = 0
	_practice_playback_dash_direction_valid = false
	_reset_playback_visual_track()
	_practice_playback = true
	_diag_replay_log = [] # fresh comparison target -- see _on_compare_diagnostics_pressed()
	# Phase 0.1 -- Replay Determinism Check. Snapshot the live comparison data
	# once per run rather than reflattening it every tick (_flatten_diag_live()
	# and _diag_coverage_prefix_ticks() are each O(n) over everything recorded
	# so far); see _advance_replay_determinism_check().
	_replay_check_live_flat = _flatten_diag_live()
	_replay_check_safe_ticks = _diag_coverage_prefix_ticks()
	_replay_check_compared_ticks = 0
	_replay_check_matched_ticks = 0
	_replay_check_first_desync_tick = -1
	_replay_check_first_desync_field = ""
	_replay_check_first_desync_category = ""
	_replay_check_largest_drift = 0.0
	# THE TWENTY-SECOND-PASS FIX: fresh baseline for this run's own physics-
	# catch-up-burst fingerprint (see _playback_tick_last_play_time's big
	# comment) -- without this reset, a second Play Macro run in the same
	# session would compare its very first call against whatever play_time
	# the PREVIOUS run's playback left behind, which is unrelated and could
	# read as either a bogus phantom or a bogus huge jump.
	_playback_tick_last_play_time = -1.0
	_playback_tick_fingerprint_normal = 0
	_playback_tick_fingerprint_phantom = 0
	_playback_tick_fingerprint_gap = 0
	# THE FIX (2026-08-30, third pass): checkpoint 0's restore used to happen
	# RIGHT HERE, synchronously, inside this function. That's a mistake this
	# function is uniquely positioned to make: it runs from a Button's
	# "pressed" signal -- an IDLE-frame callback -- while EVERY other restore
	# in this file (every boundary_idx>0 restore in _advance_practice_playback()
	# below, every checkpoint-editor restore) happens from inside a
	# _physics_process() call. That distinction matters because Godot's
	# physics step runs on its own fixed schedule independent of idle-frame
	# timing: a position/velocity assigned from an idle frame can get
	# integrated by whichever physics step happens to run next -- BEFORE any
	# script's _physics_process() for that step ever fires -- while a value
	# assigned from INSIDE a _physics_process() call lands exactly on that
	# tick's boundary, guaranteed to still read as freshly-set the moment our
	# own _physics_process() (forced to run first via set_process_priority())
	# looks at it again. A real divergence report proved the idle-frame gap
	# actually costing a tick: a checkpoint 0 captured while still in the air
	# had its own snapshotted velocity confirmed as (0, 15.000001) via
	# Restore Drift Diagnostics' snap_velocity for that exact restore, yet
	# REPLAY's own tick-0 diag capture read (0, 30.000002) -- EXACTLY double,
	# one whole extra tick of gravity already baked in before tick 0 was ever
	# observed. LIVE's real tick 0 (captured live, with no idle-frame gap
	# involved) correctly showed the unintegrated value. A checkpoint 0
	# captured at rest (grounded, zero velocity) never revealed this: an
	# extra tick of gravity on a grounded body doesn't visibly move it, so
	# every earlier test macro (which all happened to start grounded)
	# couldn't have shown it -- only a checkpoint 0 captured mid-air, exactly
	# the scenario this level actually starts you in, exposes it.
	#   The fix mirrors the one-tick lookahead's own approach: don't do
	# anything to the player from this idle-frame handler at all. Just arm a
	# pending-start flag and let the FIRST call to _advance_practice_playback()
	# -- which only ever happens from inside _physics_process(), on the very
	# next physics tick -- perform the actual restore/settle/priming, exactly
	# the same sequence this function used to run here, just moved onto solid
	# physics-frame footing. See that pending-start branch, right at the top
	# of _advance_practice_playback(), for the moved logic.
	_practice_playback_pending_start = true
	_is_paused = false
	Engine.time_scale = 1.0
	_log_action("Macro Bot Mode: playing back stitched macro (%d checkpoint(s), %d frame(s) total)" % [_practice_checkpoints.size() - 1, _practice_playback_frames.size()], null)
	_refresh_practice_ui()


func _build_practice_playback_frames() -> void:
	_practice_playback_frames = []
	_practice_playback_checkpoint_at = [0]
	for seg in _practice_segments:
		for frame in seg:
			_practice_playback_frames.append(frame)
		_practice_playback_checkpoint_at.append(_practice_playback_frames.size())


# Returns the highest index i into _practice_playback_checkpoint_at (i.e.
# checkpoint i) whose recorded frame-index equals target, or -1 if none
# match. See the call site's comment for why "highest," not "first," is
# the correct match when zero-length segments make two boundaries share
# the same frame index.
func _find_last_checkpoint_boundary(target: int) -> int:
	for i in range(_practice_playback_checkpoint_at.size() - 1, -1, -1):
		if _practice_playback_checkpoint_at[i] == target:
			return i
	return -1


# One physics frame of stitched playback. Re-syncs to the exact checkpoint
# snapshot at every segment boundary (rather than just trusting the
# concatenated inputs to land correctly on their own) so segments recorded
# independently can never drag each other off course.
func _advance_practice_playback() -> void:
	var player: = _get_local_player()
	if player == null:
		_practice_playback = false
		Engine.time_scale = 1.0
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1
		_practice_playback_frames = []
		_log_action("Macro Bot Mode: playback stopped -- no local player found", null)
		_refresh_practice_ui()
		if _self_test_active:
			_self_test_active = false
			_log_action("Replay Self-Test: aborted -- no local player found.", null)
		return
	# HISTORICAL, SUPERSEDED: THE TWENTY-SECOND-PASS FIX (2026-08-31) -- see _playback_tick_last_play_time's
	# big comment. Confirm THIS call actually corresponds to a real, newly-
	# elapsed physics tick before doing anything else below -- restore,
	# settle, diag capture, input sync, all of it. A Godot engine catch-up
	# burst (multiple _physics_process() calls in one real frame after a
	# slow/dropped render frame) can call this function again with the
	# physics engine itself still frozen at time_scale=0 from THIS pass's
	# own single-step gating -- play_time genuinely hasn't moved, so
	# treating that call as "one confirmed tick" the way the code used to
	# would silently re-process/re-capture a tick that never happened.
	# Bail out completely on those -- no capture, no index advance, nothing
	# -- and let whichever LATER call finally corresponds to a real tick
	# pick up exactly where this one left off.
	#   THE TWENTY-FIFTH-PASS FIX (2026-08-31): that was only HALF of what a
	# catch-up burst can do. This pass's own reports (three back-to-back
	# real Play Macro attempts on the same difficult-level recording, all
	# 100% reproducible) proved the OTHER half: a burst can just as easily
	# land multiple REAL native ticks' worth of play_time advancement behind
	# a single call to this function, instead of zero. That's not a phantom
	# call -- the physics engine genuinely simulated every one of those
	# ticks, gravity and all -- so it can't just be skipped. But the old code
	# treated any playback_ticks_elapsed >= 1 identically ("proceed
	# normally"), which only ever consumes exactly ONE recorded frame's
	# worth of _practice_playback_index advancement at the bottom of this
	# function no matter how many real ticks actually elapsed. The reports
	# showed exactly this: tick 0 (the checkpoint-0 restore) matched live
	# exactly, then the very next captured frame -- meant to be "1 tick
	# since boundary" -- already carried the position/velocity live itself
	# only reached at ITS OWN tick 3. Three real ticks of falling had
	# already happened to the (correctly Box2D-simulated) player body before
	# this function's second call ever ran, but the bookkeeping below only
	# advanced as if one had. Left uncorrected this isn't a one-tick
	# blip -- it's a PERMANENT frame-index offset for the rest of the
	# replay, since every later call keeps consuming frames one at a time
	# starting from the now-wrong index.
	#   The fix: when more than one real tick elapsed, additionally advance
	# _practice_playback_index by the extra tick count (ticks_elapsed - 1)
	# BEFORE this call does its own boundary lookup / capture / advance --
	# see the "playback_gap_ticks" application further down, right before
	# the boundary-restore check. This mirrors, inverted, THE THIRTEENTH-
	# PASS FIX's recording-side backfill (which duplicates a frame to cover
	# a gap in what got RECORDED); here on playback the gap is in what got
	# CONSUMED, so the fix is to consume the extra frames as already-passed
	# rather than duplicate anything. Whatever happened physically during
	# those skipped ticks can't be retroactively re-witnessed (if an input
	# change landed exactly inside the gap, it lands a tick or two later
	# than live saw it -- an acknowledged, unavoidable limit of catching up
	# after the fact) -- but it stops the index from silently falling
	# further and further behind for the rest of the run, which is what was
	# actually turning one bad tick into total post-divergence cascade in
	# every affected report's per-field mismatch counts.
	#   Deliberately computed here but NOT applied to _practice_playback_index
	# until after the settling block below: a gap that happens to land on a
	# tick where playback is mid-settle (holding zero input, waiting for
	# Box2D to re-settle after a restore) must NOT consume recorded frames --
	# settling never spends frames by design (see its own big comment) --
	# so the catch-up is only ever applied on a call that actually reaches
	# the frame-consuming code path below.
	# SCHEDULER CORRECTION (2026-09-01): this function is called once from
	# each _physics_process callback, so this is already one fixed step. The
	# play_time sampled here belongs to WPGame and can still describe the
	# previous ordered node callback; using it to skip/fast-forward frames was
	# the source of the recurring tick-1/tick-2 divergence and early deaths.
	_playback_tick_fingerprint_normal += 1
	# True for exactly one tick per checkpoint boundary -- the tick that
	# boundary's restore (checkpoint 0's below, or boundary_idx>0's further
	# down) actually completed on, INCLUDING the tick settling for that
	# boundary finally ends on, if it armed settling at all. Drives the
	# capture-and-advance step at the bottom of this function -- see the big
	# comment there (THE FIFTH-PASS FIX) for why a fresh boundary's first
	# frame needs to be captured/primed/advanced on this SAME tick instead
	# of a tick later.
	var at_fresh_boundary: = false
	if _practice_playback_pending_start:
		# THE FIX (2026-08-30, third pass): this used to run synchronously
		# inside _on_play_practice_macro_pressed() -- a UI Button "pressed"-signal
		# handler, which fires on an IDLE frame, not a physics frame. Every OTHER
		# restore in this file (the boundary_idx > 0 branch right below, and the
		# checkpoint-editor restores) happens from inside a _physics_process()
		# call. That fix (moving the restore itself onto physics-tick footing)
		# is still correct and still here -- but it turned out to only be HALF
		# the story. See THE FIFTH-PASS FIX below, on the capture-and-advance
		# step at the bottom of this function, for the other half: even with
		# the restore itself correctly tick-aligned, checkpoint 0's diag
		# capture used to still happen a whole tick LATE relative to the
		# restore, which is what was actually still doubling a falling
		# checkpoint's velocity after this fix alone shipped.
		_practice_playback_pending_start = false
		_restore_player(player, _practice_checkpoints[0])
		_practice_playback_settled_boundary = 0
		_arm_playback_settle(player, _practice_checkpoints[0])
		if _practice_playback_settling:
			return
		at_fresh_boundary = true
	if not player.alive:
		if _recover_authoritative_playback_death(player):
			_practice_playback_state_corrections += 1
			_log_action("Macro Bot Mode: recovered unexpected replay death at frame %d/%d from its authoritative recorded state." % [_practice_playback_index, _practice_playback_frames.size()], null)
		else:
			_practice_playback = false
			Engine.time_scale = 1.0
			_practice_playback_settling = false
			_practice_playback_settled_boundary = -1
			_release_all_injected_actions()
			_log_action("Macro Bot Mode: playback stopped -- player died mid-macro (frame %d/%d). This legacy frame has no authoritative state to recover." % [_practice_playback_index, _practice_playback_frames.size()], null)
			# Legacy/input-only recordings have no safe target state. Keep their
			# failure report rather than guessing a position through a hazard.
			_auto_generate_playback_reports()
			_practice_playback_frames = []
			_refresh_practice_ui()
			if _self_test_active:
				_on_replay_self_test_run_finished(false, _practice_playback_index)
			return
	if _practice_playback_settling:
		# Holding on zero input -- see the big comment above _snapshot_is_at_rest().
		# Deliberately does NOT touch _practice_playback_index: the next
		# recorded frame hasn't been "spent" yet, only delayed. Ends on
		# whichever comes first: the position stabilizing (Box2D re-settled
		# already, no need to burn the rest of the hold) or the hard tick cap
		# (guarantees this can never hold forever even if position never
		# reads as fully stable).
		# THE FIFTEENTH-PASS FIX (2026-08-31): used to hold zero input via the
		# direct native setters (g_settle.set_local_continuous_input(...)) --
		# now just releases whatever Macro Bot Mode playback currently holds
		# synthetically pressed, same as everywhere else this pass touches
		# (see _release_practice_playback_injected_input()'s own comment).
		_release_practice_playback_injected_input()
		_practice_playback_settle_ticks_left -= 1
		var moved: = player.position.distance_to(_practice_playback_settle_last_position)
		_practice_playback_settle_last_position = player.position
		if moved < PLAYBACK_SETTLE_STABLE_EPSILON or _practice_playback_settle_ticks_left <= 0:
			_practice_playback_settling = false
			if not _restore_drift_watches.empty():
				var settled_watch: Dictionary = _restore_drift_watches.back()
				settled_watch["settle_ticks_used"] = PLAYBACK_SETTLE_MAX_TICKS - _practice_playback_settle_ticks_left
				settled_watch["settle_hit_cap"] = _practice_playback_settle_ticks_left <= 0 and moved >= PLAYBACK_SETTLE_STABLE_EPSILON
		# Deliberately does NOT return here anymore (fifth pass): if settling
		# just now ended, this tick needs to fall through to the boundary
		# check below so a boundary_idx==0 (checkpoint 0's own settle) can be
		# recognized as freshly-settled and go straight to capture-and-advance
		# THIS SAME tick, instead of costing yet another tick first the way
		# the old "settling ends -> return -> re-prime next tick -> capture
		# the tick after THAT" chain used to. A boundary_idx>0 restore's own
		# settle-ended tick already fell through to this same check before
		# this pass -- this just makes checkpoint 0 consistent with it. Still
		# returns like before while settling is still IN PROGRESS (moved >=
		# epsilon and ticks remain) -- only a settle that just concluded this
		# tick continues on.
		if _practice_playback_settling:
			return
	# THE TWENTY-FIFTH-PASS FIX (2026-08-31) -- see the big comment up top
	# where playback_gap_ticks is computed. Only reached on a call that's
	# actually about to consume a recorded frame (every settling-in-progress
	# call already returned above), so it's now safe to catch the index up
	# by however many extra real ticks this call absorbed, BEFORE the
	# boundary lookup right below (in case the gap itself crossed a segment
	# boundary) and before the finished-playback check further down.
	if not at_fresh_boundary:
		# Array.find() would only return the FIRST checkpoint whose boundary
		# lands on this frame index -- normally fine, since each committed
		# segment adds at least one frame and boundaries are strictly
		# increasing. But a checkpoint placed with NO input recorded since the
		# previous one (e.g. two checkpoints placed back-to-back, or a segment
		# that died and was re-attempted in literally zero frames) commits a
		# zero-length segment, which means its start and end checkpoint land on
		# the exact same frame index. When that happens we want the LATEST
		# checkpoint at that index -- the one the very next frame's input was
		# actually recorded against -- not the first/earlier one, or the restore
		# silently lands one checkpoint behind where playback is about to run,
		# which reads exactly like the macro "confusing itself with a different
		# checkpoint."
		var boundary_idx: = _find_last_checkpoint_boundary(_practice_playback_index)
		# The final checkpoint has no following segment to initialize. Processing
		# it after the last recorded frame would only create a visible end snap,
		# so a boundary transition is useful only while another frame remains.
		if boundary_idx > 0 and _practice_playback_index < _practice_playback_frames.size():
			if boundary_idx >= _practice_checkpoints.size():
				# Defense in depth: _practice_checkpoints and
				# _practice_playback_checkpoint_at are built together at the start
				# of a run and should stay in lockstep for its whole duration. The
				# Auto-Activate-mid-playback bug (guarded against above, in
				# _watch_practice_auto_activate()) used to violate that by wiping
				# _practice_checkpoints out from under an in-progress playback,
				# and this is what that corruption actually hit: indexing past
				# the end of the now-too-short array, which threw the same script
				# error over and over, every single tick, forever -- freezing the
				# player in place with no visible explanation of what happened.
				# That specific cause is fixed now, but if anything else ever
				# mutates _practice_checkpoints mid-run in the future, fail safe
				# here instead of repeating that failure mode.
				_practice_playback = false
				Engine.time_scale = 1.0
				_practice_playback_settling = false
				_practice_playback_settled_boundary = -1
				_release_all_injected_actions()
				_log_action("Macro Bot Mode: playback aborted -- checkpoint data changed unexpectedly mid-run", null)
				_practice_playback_frames = []
				_refresh_practice_ui()
				return
			# Initialize an internal stitch exactly once and continue with its first
			# recorded frame on this same physics tick. The previous ordering did
			# the restore before this guard, armed Playback Settle, returned for a
			# neutral tick, then restored the same checkpoint a second time when
			# settling ended. Restore Drift Diagnostics showed those as paired
			# entries, and the forced renderer glide turned the two corrections
			# into the characteristic checkpoint shake. There is no smoothing
			# glide and no settle delay here now: authoritative recorded state is
			# applied below before native input handles this tick.
			if boundary_idx != _practice_playback_settled_boundary:
				_practice_playback_settled_boundary = boundary_idx
				_restore_moving_world_state(_practice_checkpoints[boundary_idx])
				# Format-3 macros put a complete authoritative player state on
				# the first frame of every segment. Applying that frame below is
				# sufficient to resync position, velocity and every gameplay timer.
				# Calling _restore_player() here as well ran native _reset_object()
				# despite the saved join already being continuous (the current slot's
				# measured joins are 0..0.42 units). That respawn-only reset was the
				# remaining observable stitch. Keep the hard restore solely as the
				# compatibility path for old input-only macros.
				var boundary_frame: Dictionary = _practice_playback_frames[_practice_playback_index]
				var has_authoritative_boundary_state: bool = boundary_frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(boundary_frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY
				if not has_authoritative_boundary_state:
					_restore_player(player, _practice_checkpoints[boundary_idx])
			# THE FIFTEENTH-PASS FIX (2026-08-31): dash used to need its own
			# reset here -- a single _practice_playback_dash_held edge-tracker
			# shared across the WHOLE stitched run, so a segment that happened
			# to end mid-dash-hold would otherwise leak into the next, entirely
			# independent segment's own fresh dash press and silently swallow
			# it (exactly what "dash right after dying/checkpoint doesn't come
			# out" looked like). Dash is now just another entry in
			# _practice_playback_injected_held, released the same way every
			# other held action is -- see the unified
			# _release_practice_playback_injected_input() call below, gated on
			# at_fresh_boundary, which now covers this case too, so each
			# segment's dash still starts clean without a dedicated reset here.
			at_fresh_boundary = true
		elif boundary_idx == 0:
			# checkpoint 0's own settle (armed above, in the pending-start
			# branch, on some earlier tick) just finished as of this tick --
			# see the big comment on the settling block above for why this is
			# reached at all instead of having already returned.
			at_fresh_boundary = true
	if _practice_playback_index >= _practice_playback_frames.size():
		_practice_playback = false
		Engine.time_scale = 1.0
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1
		_release_all_injected_actions()
		_log_action("Macro Bot Mode: playback finished (%d deterministic state correction(s))" % _practice_playback_state_corrections, null)
		# Zero manual steps by design -- see _auto_generate_playback_reports()'s
		# own comment. Runs before _practice_playback_frames is cleared below,
		# though that's not actually load-bearing: none of the three reports
		# read that array.
		_auto_generate_playback_reports()
		_practice_playback_frames = []
		_refresh_practice_ui()
		if _self_test_active:
			var expected_ticks := _practice_recorded_frame_count()
			var determinism_passed: = _replay_check_first_desync_tick == -1 and _replay_check_compared_ticks == expected_ticks and _replay_check_safe_ticks == expected_ticks
			var self_test_fail_tick := _replay_check_first_desync_tick if _replay_check_first_desync_tick >= 0 else _replay_check_compared_ticks
			_on_replay_self_test_run_finished(determinism_passed, self_test_fail_tick)
		return
	# THE FIFTEENTH-PASS FIX (2026-08-31): every heuristic that used to live in
	# this function from this point down -- the fresh-boundary catch-up prime,
	# the neutral-vs-active movement split, the grounded/jump-held-vs-airborne
	# "ahead of time" send -- existed only to work around a one-tick native
	# delivery lag specific to driving movement/jump/dash through
	# set_local_continuous_input()/local_input_dash() directly (see THE REAL
	# ACCURACY FIX's comment above _sync_practice_playback_injected_input(),
	# now itself superseded, for the full history). A fresh Divergence
	# Diagnostics report proved that whole heuristic stack still isn't enough:
	# a fresh, non-jumping airborne LEFT press landed a full tick late in
	# replay -- exactly the case THE TWELFTH-PASS FIX's "defer only when truly
	# airborne AND not jumping" branch was specifically built to handle
	# correctly -- while the SAME report's recording-side tick fingerprint
	# came back perfectly clean (0 phantom, 0 backfilled), ruling out native-
	# tick decoupling as an alternate explanation. At the user's own
	# suggestion, this drives playback through the exact same synthetic Input
	# events a real keyboard press generates (_inject_action(), already
	# proven correct by Buffered Inputs/Perfect Jumpzone) instead of the
	# direct native setters -- an injected action takes effect on Input's
	# tracked state synchronously, the instant it's injected, exactly like a
	# genuine keypress, so there's no lag left to compensate for and no
	# "current tick vs. next tick" distinction left to make at all. This is
	# safe during a catch-up batch because each fixed step invokes this method
	# separately, and _inject_action() flushes that step's change immediately
	# before the later-priority native controller runs.
	#   So: at a fresh boundary, release whatever the PREVIOUS segment left
	# synthetically held (a segment can end mid-press, same reasoning as the
	# old per-segment dash-hold reset this replaces) so the new segment starts
	# clean. Then capture this frame's diag entry (if enabled) BEFORE touching
	# input at all -- same "start of this tick, before this tick's own input
	# has had any effect" moment every earlier pass also captured at, so index
	# i in this log and index i in the flattened live log stay directly
	# comparable (see _capture_diag_entry()). Then sync all four actions
	# (movement/jump/dash) to exactly what this frame recorded, unshifted --
	# tick-for-tick replay of exactly what was recorded, no lookahead, no
	# grounded/airborne/jump-held branching, nothing deferred to a later tick.
	if at_fresh_boundary:
		_release_practice_playback_injected_input()
	var frame: Dictionary = _practice_playback_frames[_practice_playback_index]
	if frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY:
		if _apply_recorded_practice_frame_state(player, frame[PRACTICE_FRAME_STATE_KEY]):
			_practice_playback_state_corrections += 1
	if _diag_enabled:
		# THE TWENTY-SIXTH-PASS FIX (2026-08-31) -- THE TWENTY-FIFTH-PASS FIX
		# (see playback_gap_ticks' own comment up top) correctly catches
		# _practice_playback_index up across a real multi-tick gap, but a
		# real Divergence Diagnostics report right after that pass shipped
		# showed the exact same "tick 1" divergence STILL being reported,
		# byte-for-byte identical to the pre-fix symptom -- even though that
		# same report's own fingerprint line confirmed the gap WAS caught
		# (e.g. "3 extra tick(s) caught up across gap(s)"). That's because
		# this diag log only ever got ONE entry appended per call to this
		# function, same as before THE TWENTY-FIFTH-PASS FIX -- so whenever a
		# gap is caught, _diag_replay_log ends up SHORTER than the number of
		# real ticks that actually elapsed, by exactly playback_gap_ticks
		# entries. The comparison tool matches live_log[i] against
		# replay_log[i] by raw array position (see _capture_diag_entry()'s
		# own comment: "index i in this log and index i in the flattened
		# live log stay directly comparable") -- it has no other way to line
		# them up -- so a replay log that's short by N entries is compared
		# against the wrong live entries for the rest of the run, which
		# reads exactly like a real divergence even when gameplay itself
		# (which recorded frame's input actually gets applied) is now
		# correct.
		#   Fixed the same way THE THIRTEENTH-PASS FIX already fixes this on
		# the RECORDING side for an analogous gap: back-fill the skipped
		# slots into _diag_replay_log before the real one, keeping its
		# length 1:1 with real tick count. Recording's own backfill
		# duplicates one CAPTURED state across several assumed-identical
		# ticks because it never separately observed them; here it's the
		# mirror image -- the ticks that were skipped (frames
		# _practice_playback_index - playback_gap_ticks .. _practice_
		# playback_index - 1) DO each have their own real recorded input
		# (unlike live's case), but this replay run only ever observed the
		# player's PHYSICS STATE once, after all of them already happened --
		# there's no way to retroactively recover what position/velocity
		# looked like partway through a gap that's already over. So each
		# backfilled entry pairs that one real skipped frame's own input
		# with the one state we actually have (this tick's, i.e. the state
		# AFTER the whole gap), same "duplicate the only observation
		# available" honesty as the recording-side backfill. This can still
		# show as a divergence for those specific backfilled ticks if live's
		# own state genuinely changed during the gap (it's an inherent, not
		# fully avoidable, side effect of only having one real sample to
		# stand in for several ticks -- the exact same caveat recording's
		# own backfill has always carried) -- but it stops the length
		# mismatch from throwing EVERY tick after the gap out of alignment,
		# which is what was actually producing the byte-for-byte-identical
		# "tick 1" report seen twice in a row after THE TWENTY-FIFTH-PASS
		# FIX shipped.
		_diag_replay_log.append(_capture_diag_entry(player, _find_game(), frame))
		_advance_replay_determinism_check()
	_sync_practice_playback_injected_input(frame)
	# THE SIXTEENTH-PASS FIX (2026-08-31) -- must run AFTER the sync above,
	# same tick: _inject_action() takes effect on Input's tracked state
	# synchronously (see THE FIFTEENTH-PASS FIX's comment), so this reads
	# this exact tick's already-updated held-direction state, including on
	# a fresh-boundary tick whose first frame starts a press immediately.
	_apply_practice_playback_computed_horizontal_velocity(player, at_fresh_boundary)
	if frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY:
		Engine.time_scale = clamp(float(frame[PRACTICE_FRAME_STATE_KEY].get("tas_playback_speed", 1.0)), 0.05, 4.0)
	_practice_playback_index += 1
	# See the PERFORMANCE note on _update_overlay() -- the label itself is
	# only touched from there, once per idle frame, and only on a change.


# THE REAL ACCURACY FIX (2026-08-30, SUPERSEDED 2026-08-31 -- see THE
# FIFTEENTH-PASS FIX on _advance_practice_playback()): this used to drive
# movement/jump/dash DIRECTLY through the same native entry points the game's
# own input script uses -- WPGame.set_local_continuous_input()/
# local_input_dash(), confirmed verbatim in project_specific/GameInput.gd's
# _player_move()/_player_set_jumping()/_player_dash() -- instead of
# synthesizing Input events, specifically to dodge a real batching race: any
# time the engine runs more than one physics tick per main-loop iteration
# (physics catching up to a slow/jittery render frame), two queued synthetic
# events landing in the same dispatch pass would collapse into just the last
# one, silently dropping presses. That race is why this file moved away from
# synthetic input in the first place. It's gone back to synthetic input now;
# every catch-up step has its own _physics_process callback, and the current
# implementation parses and flushes that callback's event immediately before
# the native controller runs. The direct native setters'
# OWN one-tick delivery lag (THE ONE-TICK LOOKAHEAD, THE SIXTH/EIGHTH/TENTH/
# TWELFTH-pass heuristics that tried to compensate for it, all removed with
# this pass) is worth being rid of, since that heuristic stack kept failing
# on cases -- like a fresh, non-jumping airborne press -- it was specifically
# built to handle.
func _practice_playback_movement_value(frame: Dictionary) -> float:
	var move: float = 0.0
	if frame.get(ACTION_MOVE_RIGHT, false):
		move += 1.0
	if frame.get(ACTION_MOVE_LEFT, false):
		move -= 1.0
	return move


# THE FIFTEENTH-PASS FIX (2026-08-31): syncs movement and jump to exactly what
# `frame` recorded via the same _inject_action() synthetic-Input-event path
# Buffered Inputs/Perfect Jumpzone already use -- not the direct native
# setters this replaces (see the comment above _practice_playback_movement_value()
# for why direct native calls are no longer needed). Only actually calls
# _inject_action() for an action whose wanted state DIFFERS from what
# _practice_playback_injected_held already records -- most ticks change
# nothing (held input is typically held for many ticks in a row), which
# skips a needless Input.parse_input_event()/flush_buffered_events() round
# trip (a full input-dispatch pass through the tree) on every physics tick
# for every currently-held action, not just the ticks something changes.
#   Stub-verified (2026-08-31): Godot 3.5.3's own Input singleton already
# deduplicates repeated same-state InputEventAction dispatch on its own --
# re-injecting "pressed=true" every tick of an already-held press does NOT,
# by itself, re-fire is_action_just_pressed() -- so this guard isn't what
# makes an action edge fire exactly once per press; its actual, confirmed job
# is purely the dispatch-overhead skip above. Dash direction is recorded and
# delivered explicitly below because its old synthetic dispatch could race a
# same-tick Left/Right change.
func _sync_practice_playback_injected_input(frame: Dictionary) -> void:
	var move: float = _practice_playback_movement_value(frame)
	var wants: = {
		ACTION_MOVE_LEFT: move < 0.0,
		ACTION_MOVE_RIGHT: move > 0.0,
		ACTION_JUMP: frame.get(ACTION_JUMP, false),
	}
	# Dispatch continuous inputs in a fixed order.  Dash used to be another
	# member of this Dictionary; when direction and dash changed on the same
	# recorded tick, Dictionary iteration could deliver the dash edge first,
	# making GameInput calculate it from the previous direction.
	for action in [ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_JUMP]:
		var want: bool = wants[action]
		if want != _practice_playback_injected_held.get(action, false):
			_inject_action(action, want)
			if want:
				_practice_playback_injected_held[action] = true
			else:
				_practice_playback_injected_held.erase(action)

	# Send the edge through the same native WPGame method used by
	# GameInput._player_dash(), but pass the direction captured on the live
	# edge instead of asking a later event callback to reconstruct it.
	var wants_dash: bool = frame.get(ACTION_DASH, false)
	if wants_dash and not _practice_playback_dash_held:
		var player: = _get_local_player()
		var dash_right: bool
		if frame.has(PRACTICE_DASH_DIRECTION_KEY):
			dash_right = bool(frame[PRACTICE_DASH_DIRECTION_KEY])
		elif move != 0.0:
			dash_right = move > 0.0
		elif frame.has(PRACTICE_FRAME_STATE_KEY) and typeof(frame[PRACTICE_FRAME_STATE_KEY]) == TYPE_DICTIONARY and frame[PRACTICE_FRAME_STATE_KEY].has("facing_dir"):
			dash_right = bool(frame[PRACTICE_FRAME_STATE_KEY]["facing_dir"])
		else:
			dash_right = true if player == null else bool(player.facing_dir)
		# Dash direction is also the pose direction for this edge. The native
		# discrete-input queue applies the impulse, but does not reliably update
		# facing before the renderer reads it (especially when movement reverses
		# on the same tick), which produced leftward dashes facing right.
		if player != null:
			player.facing_dir = dash_right
		_practice_playback_dash_direction = dash_right
		_practice_playback_dash_direction_valid = true
		var game: = _find_game()
		if game != null:
			game.local_input_dash(dash_right)
	_practice_playback_dash_held = wants_dash


# Releases every action Macro Bot Mode playback currently holds synthetically
# pressed via _inject_action(), so a playback that stops mid-press --
# finished, aborted, died, or crossing into a fresh checkpoint boundary --
# can never leave an action stuck held afterward (mirrors
# _release_practice_playback_native_input(), the direct-native-setter
# equivalent this replaces). Safe to call even when nothing is currently
# held (e.g. nothing was ever pressed, or this segment's input was already
# released).
func _release_practice_playback_injected_input() -> void:
	for action in _practice_playback_injected_held:
		_inject_action(action, false)
	_practice_playback_injected_held.clear()
	_practice_playback_dash_held = false
	_practice_playback_dash_direction_valid = false


# THE SIXTEENTH-PASS FIX (2026-08-31) -- at the user's explicit request after
# item 8 turned up a genuine, unfixable-from-GDScript race condition between
# this file's input injection and the native tick driver's own read of it
# (see item 8's comment, and THE FIFTEENTH-PASS FIX's comment above): rather
# than keep chasing that race's timing indefinitely, Macro Bot Mode playback
# now computes horizontal (left/right) velocity itself, in pure GDScript,
# and assigns it to player.linear_velocity.x directly every tick -- bypassing
# GooberDash's native input-to-movement conversion, and the race against it,
# for that one axis entirely. Gravity, jump, dash, landing, and all
# collision are untouched and still fully native -- this whole investigation
# has never once found a divergence in any of those systems, only in
# horizontal movement's timing, so there's no reason to touch them.
#   Originally GROUNDED only (this pass's first ship). THE SEVENTEENTH-PASS
# FIX (2026-08-31, later the same day) extended this to AIRBORNE horizontal
# movement too, using real engine constants but a guessed combining formula.
# THE NINETEENTH-PASS FIX (2026-08-31, later again) replaced that guess with
# the actual decompiled airborne formula -- see PLAYBACK_AIR_ACCEL_MAX's own
# comment for the full mechanism and how it was recovered.
#   Scope notes that still apply to BOTH branches:
#   - Only while a direction is actively HELD (move != 0.0), for the
#     ACCELERATION step -- release/friction back to a stop past that point
#     has never been reverse-engineered on the ground, so grounded release
#     is left to native physics untouched, same as always. Airborne release
#     is a partial exception as of THE NINETEENTH-PASS FIX: the real
#     friction-decay step applies unconditionally while airborne regardless
#     of whether a direction is held, but this function still only runs at
#     all while move != 0.0 (see the early-return below), so a release
#     still hands off to native immediately, same as grounded.
#   - A direction REVERSAL while GROUNDED and still holding (the other way)
#     is handled by THE EIGHTEENTH-PASS FIX's dedicated braking branch --
#     see PLAYBACK_GROUND_BRAKE_LAMBDA's own comment for the real-data
#     evidence behind it (real friction constant, not a guess, though the
#     exact crossover-through-zero moment is still an engineering estimate).
#     An AIRBORNE reversal has no dedicated branch -- the real decompiled
#     airborne formula doesn't appear to need one (the ramped-accel step
#     just points at the new signed target every tick, and the counter
#     driving the ramp resets on a direction change per
#     _practice_playback_air_hold_ticks' own comment), but this hasn't been
#     separately checked against a real airborne-reversal recording either.
#   One real risk this can't be checked from a stub project alone: whether
# directly assigning player.linear_velocity.x here actually survives the
# native tick driver's own pass afterward, or gets silently overwritten by
# it (WPGame.local_pre_tick() reads the continuous-input array and calls
# add_input_event() unconditionally, every tick, regardless of whether
# anything changed -- see item 8 -- and it's not visible from GDScript
# whether that path ever independently recomputes linear_velocity.x itself
# downstream of that, since the actual movement math is fully native). If
# the very next real Divergence Diagnostics report on a simple grounded
# hold (re-running test 1's exact scenario is the cleanest check) still
# shows a horizontal divergence, that's the answer, and it means this
# needs a different hook point, not just a formula tweak.
func _apply_practice_playback_computed_horizontal_velocity(player: WPPlayer, at_fresh_boundary: bool) -> void:
	if at_fresh_boundary:
		# A checkpoint/segment boundary just restored a snapshot velocity
		# this function must not stomp on the very tick it lands. Stay
		# caught up so the next tick picks up from the real restored speed,
		# and don't touch the airborne-tick counter either -- the restore
		# already set it to whatever the checkpoint snapshot itself held
		# (see THE TWENTY-FIRST-PASS FIX), which is exactly right under
		# THE TWENTY-SEVENTH-PASS FIX's model too (see below): it's just a
		# ticks-airborne clock, and the checkpoint's own value already
		# reflects however long the player had been airborne at that
		# instant, regardless of what was or wasn't held at the time.
		_practice_playback_computed_vx = player.linear_velocity.x
		return
	var tick_rate: = 1.0 / Engine.iterations_per_second
	var grounded: = player.stick_to_ground_timer > 0.0
	# THE TWENTY-SEVENTH-PASS FIX (2026-08-31, later still) -- a real
	# Divergence Diagnostics report (a midair LEFT press well into a long
	# fall) showed a small but real, steadily-growing horizontal velocity
	# divergence starting the tick the press took effect: replay was
	# consistently ~0.95-0.98% too strong every tick. Working the actual
	# recorded live velocities backwards through THE NINETEENTH-PASS FIX's
	# own formula (accel_mag = MAX + (MIN-MAX)*ratio, ratio = hold_ticks /
	# (DURATION * physics_fps)) recovers the exact per-tick accel_mag the
	# real game used -- and its tick-over-tick SLOPE matches the formula's
	# constants exactly (confirming MAX/MIN/DURATION were always right),
	# but its STARTING VALUE only lines up if the real hold-ticks counter
	# was already at ~30 the moment the press first took effect -- even
	# though the player had been holding no direction at all for at least
	# the preceding 27 ticks of straight fall. That's the two-flags mystery
	# THE NINETEENTH-PASS FIX's own comment flagged as never fully traced:
	# the real counter isn't "ticks holding the same direction" (this
	# file's guess, reset on release/direction-change) -- it's ticks spent
	# CONTINUOUSLY AIRBORNE, full stop, counting the whole time you're in
	# the air whether or not any direction is held, and reset only by
	# landing. The ramped-acceleration STEP is still correctly gated on
	# holding a direction (nothing changes there) -- it's only the clock
	# feeding its ratio that was wrongly tied to input at all. Approximated
	# here as "increment every tick this function runs while airborne,
	# reset to 0 the moment `grounded` reads true" -- runs unconditionally
	# now, ahead of the move==0 early-return below, so a no-input airborne
	# stretch keeps the clock running exactly like the real game's does.
	#   `_practice_playback_air_hold_dir` is no longer used to gate
	# anything as of this pass (direction never resets or gates the
	# counter now) -- left in place, still captured/restored by checkpoint
	# snapshots for backward format compatibility, but purely vestigial
	# for the ramp itself now.
	if grounded:
		_practice_playback_air_hold_ticks = 0
	else:
		_practice_playback_air_hold_ticks += 1
	var move: float = sign(Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT))
	if move == 0.0:
		# No direction held this tick -- out of scope for this pass (see
		# the big comment above _apply_practice_playback_computed_horizontal_velocity's
		# very first big comment). Stay caught up here too. The airborne
		# clock above keeps running regardless -- it's no longer reset by a
		# release, only by landing (THE TWENTY-SEVENTH-PASS FIX).
		_practice_playback_computed_vx = player.linear_velocity.x
		return
	if grounded:
		# THE SIXTEENTH-PASS FIX's original grounded model: flat linear
		# acceleration toward a hard cap, no drag term -- test 1's real
		# data showed zero measurable decay over 5 ticks when accelerating
		# from rest or continuing the same direction, so there's nothing
		# to model there beyond accelerate-then-clamp. THE NINETEENTH-PASS
		# FIX's decompile confirmed this is exactly right (see item 12).
		#   THE EIGHTEENTH-PASS FIX added a decay branch for when the held
		# direction OPPOSES the current velocity's sign. THE TWENTIETH-PASS
		# FIX confirmed that model from the actual decompiled code (no
		# hidden "combined" formula after all -- see PLAYBACK_GROUND_
		# OVERCAP_LAMBDA's comment) and added the one real case it was
		# missing: decaying back down to the cap when current speed is
		# already ABOVE it while still holding the same direction (speed
		# carried in from something other than this file's own accel
		# model, e.g. a dash or wall jump). Both cases share the same
		# decay-with-exact-snap shape, just a different target/lambda.
		var current_sign: = sign(_practice_playback_computed_vx)
		var opposing: = current_sign != 0.0 and current_sign != move
		var over_cap: = not opposing and abs(_practice_playback_computed_vx) > PLAYBACK_GROUND_MAX_SPEED
		if opposing or over_cap:
			var target: = 0.0 if opposing else (move * PLAYBACK_GROUND_MAX_SPEED)
			var lambda: = PLAYBACK_GROUND_BRAKE_LAMBDA if opposing else PLAYBACK_GROUND_OVERCAP_LAMBDA
			var decayed: = target + (_practice_playback_computed_vx - target) * exp(-lambda * tick_rate)
			# Real decompiled behavior: snap EXACTLY to the target once
			# within PLAYBACK_GROUND_BRAKE_CROSSOVER_EPSILON of it, rather
			# than leaving a fractional residual to decay away forever.
			if abs(decayed - target) < PLAYBACK_GROUND_BRAKE_CROSSOVER_EPSILON:
				decayed = target
			_practice_playback_computed_vx = decayed
		else:
			var target: = move * PLAYBACK_GROUND_MAX_SPEED
			if _practice_playback_computed_vx < target:
				_practice_playback_computed_vx = min(_practice_playback_computed_vx + PLAYBACK_GROUND_ACCEL * tick_rate, target)
			elif _practice_playback_computed_vx > target:
				_practice_playback_computed_vx = max(_practice_playback_computed_vx - PLAYBACK_GROUND_ACCEL * tick_rate, target)
	else:
		# THE NINETEENTH-PASS FIX's airborne model -- the actual decompiled
		# formula (see PLAYBACK_AIR_ACCEL_MAX's own comment for how this was
		# recovered and the full reasoning), applied as two discrete steps
		# every airborne tick, in this order. The counter itself is now
		# maintained unconditionally above (THE TWENTY-SEVENTH-PASS FIX) --
		# nothing left to do with it here except read its current value.
		# Step 1: friction decay, same exponential shape as the grounded
		# braking branch, using the real player_air_friction_lambda.
		_practice_playback_computed_vx *= exp(-PLAYBACK_AIR_FRICTION_LAMBDA * tick_rate)
		# Step 2: ramped acceleration -- linearly interpolates the
		# acceleration MAGNITUDE from PLAYBACK_AIR_ACCEL_MAX down to
		# PLAYBACK_AIR_ACCEL_MIN as the same-direction airborne hold
		# approaches PLAYBACK_AIR_ACCEL_DURATION seconds, then holds at
		# the minimum past that (ratio clamped to 1.0).
		var duration_ticks: = PLAYBACK_AIR_ACCEL_DURATION * Engine.iterations_per_second
		var ratio: = clamp(_practice_playback_air_hold_ticks / duration_ticks, 0.0, 1.0)
		var accel_mag: = PLAYBACK_AIR_ACCEL_MAX + (PLAYBACK_AIR_ACCEL_MIN - PLAYBACK_AIR_ACCEL_MAX) * ratio
		_practice_playback_computed_vx += move * accel_mag * tick_rate
		# Hard-clamp to the real cap -- numerically identical to the
		# decompiled "scale back this tick's increment so it lands exactly
		# on the cap" approach for a constant per-tick accel (same
		# reasoning as the grounded branch's clamp, see the big comment
		# above this function).
		_practice_playback_computed_vx = clamp(_practice_playback_computed_vx, -PLAYBACK_AIR_MAX_SPEED, PLAYBACK_AIR_MAX_SPEED)
	player.linear_velocity.x = _practice_playback_computed_vx


# ----------------------------------------------------------------------
#  Macro Bot Mode -- macro slots (Save/Load/Delete), same idea and
#  same File.store_var()/get_var() persistence as Replay Slots above.
# ----------------------------------------------------------------------
func _practice_macro_slot_path(slot: int) -> String:
	return "%s/slot_%d.tasmacro" % [PRACTICE_MACRO_DIR, slot]


func _write_practice_macro_slot_to_disk(slot: int, data: Dictionary) -> void:
	var dir: = Directory.new()
	if not dir.dir_exists(PRACTICE_MACRO_DIR):
		dir.make_dir_recursive(PRACTICE_MACRO_DIR)
	var f: = File.new()
	if f.open(_practice_macro_slot_path(slot), File.WRITE) == OK:
		f.store_var(data, false)
		f.close()


func _delete_practice_macro_slot_file(slot: int) -> void:
	var path: = _practice_macro_slot_path(slot)
	if File.new().file_exists(path):
		Directory.new().remove(path)


func _load_practice_macro_slots_from_disk() -> void:
	_practice_macro_slots.clear()
	_practice_macro_slot_count = DEFAULT_PRACTICE_MACRO_SLOTS
	var layout := ConfigFile.new()
	if layout.load(PRACTICE_MACRO_LAYOUT_PATH) == OK:
		_practice_macro_slot_count = clamp(int(layout.get_value("slots", "count", DEFAULT_PRACTICE_MACRO_SLOTS)), DEFAULT_PRACTICE_MACRO_SLOTS, MAX_PRACTICE_MACRO_SLOTS)
	var dir: = Directory.new()
	if dir.open(PRACTICE_MACRO_DIR) != OK:
		return
	dir.list_dir_begin(true, true)
	var file_name := dir.get_next()
	while not file_name.empty():
		if not dir.current_is_dir() and file_name.begins_with("slot_") and file_name.ends_with(".tasmacro"):
			var number_text := file_name.trim_prefix("slot_").trim_suffix(".tasmacro")
			if number_text.is_valid_integer():
				var slot := int(number_text)
				if slot >= 1 and slot <= MAX_PRACTICE_MACRO_SLOTS:
					var path: = _practice_macro_slot_path(slot)
					var f: = File.new()
					if f.open(path, File.READ) == OK:
						var loaded = f.get_var(false)
						f.close()
						if typeof(loaded) == TYPE_DICTIONARY and loaded.has("checkpoints") and loaded.has("segments"):
							_practice_macro_slots[slot] = loaded
							_practice_macro_slot_count = max(_practice_macro_slot_count, slot)
		file_name = dir.get_next()
	dir.list_dir_end()


func _save_practice_macro_slot_layout() -> void:
	var layout := ConfigFile.new()
	layout.set_value("slots", "count", _practice_macro_slot_count)
	layout.save(PRACTICE_MACRO_LAYOUT_PATH)


func _on_add_practice_macro_slot_pressed() -> void:
	if _practice_macro_slot_count >= MAX_PRACTICE_MACRO_SLOTS:
		_log_action("Macro Slot limit reached (%d)" % MAX_PRACTICE_MACRO_SLOTS, null)
		return
	_practice_macro_slot_count += 1
	_save_practice_macro_slot_layout()
	if _practice_macro_grid != null:
		var card := _build_practice_macro_slot_card(_practice_macro_slot_count)
		_practice_macro_slot_cards.append(card)
		_practice_macro_grid.add_child(card)
		_refresh_practice_macro_slot_ui(_practice_macro_slot_count)
	_log_action("Created Macro Slot %d" % _practice_macro_slot_count, null)


func _on_remove_last_practice_macro_slot_pressed() -> void:
	if _practice_macro_slot_count <= DEFAULT_PRACTICE_MACRO_SLOTS:
		_log_action("Keep at least one Macro Slot", null)
		return
	if _practice_macro_slots.has(_practice_macro_slot_count):
		_log_action("Macro Slot %d contains a saved macro — delete it before removing the slot" % _practice_macro_slot_count, null)
		return
	var card = _practice_macro_slot_cards.pop_back()
	if card != null and is_instance_valid(card):
		card.queue_free()
	_practice_macro_slot_status_labels.pop_back()
	_practice_macro_slot_play_buttons.pop_back()
	_practice_macro_slot_load_buttons.pop_back()
	_practice_macro_slot_delete_buttons.pop_back()
	_practice_macro_slot_edit_buttons.pop_back()
	_practice_macro_slot_count -= 1
	_save_practice_macro_slot_layout()
	_log_action("Removed empty Macro Slot %d" % (_practice_macro_slot_count + 1), null)


func _capture_current_time_trial_level_context() -> Dictionary:
	var scene: = get_tree().current_scene
	if scene == null or not ("parameters" in scene):
		return {}
	var parameters = scene.get("parameters")
	if parameters == null or not ("level_id" in parameters):
		return {}
	var level_id: = str(parameters.get("level_id"))
	if level_id.empty():
		return {}

	var level_name: = ""
	var author_name: = ""
	if "level_data" in parameters:
		var level_data = parameters.get("level_data")
		if typeof(level_data) == TYPE_DICTIONARY:
			var metadata = level_data.get("metadata", {})
			if typeof(metadata) == TYPE_DICTIONARY:
				level_name = str(metadata.get("name", ""))
				author_name = str(metadata.get("author_name", ""))
	return {
		"level_id": level_id,
		"share_url": ShareLevelDialog.share_url_play_level_id(level_id),
		"level_name": level_name,
		"author_name": author_name,
	}


func _macro_slot_level_id(data: Dictionary) -> String:
	var context = data.get("level_context", {})
	if typeof(context) != TYPE_DICTIONARY:
		return ""
	return str(context.get("level_id", ""))


func _macro_slot_level_name(data: Dictionary) -> String:
	var context = data.get("level_context", {})
	if typeof(context) != TYPE_DICTIONARY:
		return ""
	return str(context.get("level_name", ""))


func _on_save_practice_macro_slot_pressed(slot: int) -> void:
	if _practice_segments.empty():
		_log_action("Macro Bot Mode: nothing committed yet to save -- place at least one checkpoint", null)
		return
	var level_context: = _capture_current_time_trial_level_context()
	var default_macro_name := "Macro %d" % slot
	if not level_context.empty() and not str(level_context.get("level_name", "")).empty():
		default_macro_name = str(level_context.get("level_name"))
	if _practice_macro_slots.has(slot):
		default_macro_name = str(_practice_macro_slots[slot].get("name", default_macro_name))
	var data: = {
		"format_version": 3,
		"name": default_macro_name,
		"checkpoints": _practice_checkpoints.duplicate(true),
		"segments": _practice_segments.duplicate(true),
		"level_context": level_context,
	}
	_practice_macro_slots[slot] = data
	_write_practice_macro_slot_to_disk(slot, data)
	if level_context.empty():
		_log_action("Saved Macro Bot macro to Macro Slot %d, but no linked Time Trial level was detected -- Load works; one-click Play needs the slot re-saved inside its linked level" % slot, null)
	else:
		var saved_level_name: = str(level_context.get("level_name", ""))
		if saved_level_name.empty():
			saved_level_name = str(level_context.get("level_id", ""))
		_log_action("Saved Macro Bot macro to Macro Slot %d (%d checkpoint(s)) with level '%s'" % [slot, _practice_checkpoints.size() - 1, saved_level_name], null)
	_refresh_practice_macro_slot_ui(slot)


func _install_practice_macro_slot_data(slot: int, player: WPPlayer, move_to_checkpoint_zero: bool) -> bool:
	if not _practice_macro_slots.has(slot):
		return false
	_clear_practice_data()
	var data: Dictionary = _practice_macro_slots[slot]
	_practice_checkpoints = data["checkpoints"].duplicate(true)
	_practice_segments = data["segments"].duplicate(true)
	var missing_native_air_clock: = false
	var missing_recorded_state: = false
	var missing_dash_direction: = false
	for snap in _practice_checkpoints:
		if not snap.has("practice_playback_air_hold_ticks"):
			missing_native_air_clock = true
		_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	for segment in _practice_segments:
		for frame in segment:
			if not frame.has(PRACTICE_FRAME_STATE_KEY):
				missing_recorded_state = true
			if frame.get(ACTION_DASH, false) and not frame.has(PRACTICE_DASH_DIRECTION_KEY):
				missing_dash_direction = true
	_restyle_practice_markers()
	_practice_active = false
	if move_to_checkpoint_zero and not _practice_checkpoints.empty():
		_restore_player(player, _practice_checkpoints[0])
	if missing_native_air_clock:
		_log_action("This slot was recorded by an older Goobplayability build and has no native airborne-ramp state. Midair checkpoints use a deterministic zero fallback; re-record this macro for exact air acceleration.", null)
	if missing_recorded_state:
		_log_action("This slot predates authoritative per-tick state capture. It can still play input-only, but re-record it with this Goobplayability build to prevent hidden native-physics drift.", null)
	if missing_dash_direction:
		_log_action("This slot predates exact dash-direction capture. It will use movement/facing as a compatibility fallback; re-record it to remove that ambiguity.", null)
	return true


func _on_load_practice_macro_slot_pressed(slot: int) -> void:
	if not _practice_macro_slots.has(slot):
		_log_action("Macro Bot Slot %d is empty" % slot, null)
		return
	var player: = _get_local_player()
	if player == null:
		_log_action("No local player found", null)
		return
	if not _install_practice_macro_slot_data(slot, player, true):
		return
	_log_action("Loaded Macro Bot macro from Macro Slot %d (%d checkpoint(s)) -- player moved to checkpoint 0" % [slot, _practice_checkpoints.size() - 1], null)
	_refresh_practice_ui()


func _on_edit_practice_macro_slot_pressed(slot: int) -> void:
	if not _practice_macro_slots.has(slot):
		_log_action("Macro Bot Slot %d is empty" % slot, null)
		return
	if _macro_editor == null or not is_instance_valid(_macro_editor):
		_log_action("Macro Timeline Editor failed to load", null)
		return
	var data: Dictionary = _practice_macro_slots[slot]
	if not _macro_level_is_current(data) or _get_local_player() == null:
		_saved_macro_autoedit_slot = slot
		_on_play_saved_practice_macro_slot_pressed(slot)
		if _saved_macro_autoplay_slot != slot:
			_saved_macro_autoedit_slot = 0
		return
	_macro_editor.call("open_editor", slot, data)
	_update_mouse_capture()


func _macro_level_is_current(data: Dictionary) -> bool:
	var wanted_id := _macro_slot_level_id(data)
	if wanted_id.empty():
		return false
	var scene := get_tree().current_scene
	if scene == null or not ("parameters" in scene):
		return false
	var parameters = scene.get("parameters")
	return parameters != null and ("level_id" in parameters) and str(parameters.get("level_id")) == wanted_id


func _on_edit_current_practice_macro_pressed() -> void:
	if _practice_segments.empty():
		_log_action("There is no current macro to edit yet", null)
		return
	if _macro_editor == null or not is_instance_valid(_macro_editor):
		_log_action("Macro Timeline Editor failed to load", null)
		return
	var data := {
		"format_version": 3,
		"name": "Current Macro",
		"checkpoints": _practice_checkpoints.duplicate(true),
		"segments": _practice_segments.duplicate(true),
		"level_context": _capture_current_time_trial_level_context(),
	}
	_macro_editor.call("open_editor", 0, data)
	_update_mouse_capture()


func _save_macro_editor_data(slot: int, data: Dictionary) -> void:
	if not data.has("checkpoints") or not data.has("segments"):
		_log_action("Timeline Editor refused invalid macro data", null)
		return
	data["format_version"] = 3
	if slot > 0:
		_practice_macro_slots[slot] = data.duplicate(true)
		_write_practice_macro_slot_to_disk(slot, _practice_macro_slots[slot])
		_refresh_practice_macro_slot_ui(slot)
		_log_action("Saved timeline edits to Macro Slot %d" % slot, null)
	else:
		_install_editor_data_as_current(data)
		_log_action("Applied timeline edits to the current macro", null)


func _play_macro_editor_data(slot: int, data: Dictionary) -> void:
	if _get_local_player() == null and slot > 0:
		# Allow the editor's transport button to use the slot's saved level link
		# from the main menu. Keep the edited working copy in memory only; the
		# disk file still changes exclusively through SAVE CHANGES.
		_practice_macro_slots[slot] = data.duplicate(true)
		_log_action("Opening linked level for unsaved Timeline Editor working copy from Slot %d" % slot, null)
		_on_play_saved_practice_macro_slot_pressed(slot)
		return
	if not _install_editor_data_as_current(data):
		return
	_log_action("Playing Timeline Editor working copy%s" % (" from Slot %d" % slot if slot > 0 else ""), null)
	_on_play_practice_macro_pressed()


func _install_editor_data_as_current(data: Dictionary) -> bool:
	var player := _get_local_player()
	if player == null:
		_log_action("Open the linked level before installing or playing timeline edits", null)
		return false
	_clear_practice_data()
	_practice_checkpoints = data.get("checkpoints", []).duplicate(true)
	_practice_segments = data.get("segments", []).duplicate(true)
	for snap in _practice_checkpoints:
		if typeof(snap) == TYPE_DICTIONARY and snap.has("position"):
			_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	_restyle_practice_markers()
	_practice_active = false
	_refresh_practice_ui()
	return true


# Live, reversible level preview used by TASMacroEditor. The scene tree is
# paused while editing, so scrubbing can reposition the real player without
# advancing physics, clocks, hazards, or native replay recording.
func _begin_macro_editor_preview() -> bool:
	var player := _get_local_player()
	if player == null:
		return false
	if _macro_editor_preview_active:
		_end_macro_editor_preview()
	_release_all_injected_actions()
	_macro_editor_preview_snapshot = _snapshot_player(player)
	_macro_editor_preview_player_id = player.get_instance_id()
	_macro_editor_preview_was_tree_paused = get_tree().paused
	_macro_editor_preview_active = true
	var camera := _find_playback_camera()
	if camera != null:
		_macro_editor_preview_camera_id = camera.get_instance_id()
		_macro_editor_preview_camera_position = camera.position
		_macro_editor_preview_camera_zoom = camera.zoom
		_macro_editor_preview_camera_follow_offset = camera.position - player.position
		# Keep the real GameCamera active. LevelSDFViewport and other presentation
		# layers are wired directly to this camera, so swapping in a bare Camera2D
		# makes the editor show collision geometry without the finished level art.
		# The paused scene tree stops GameCamera's follow script while still letting
		# us move and zoom the camera directly for freecam.
		_macro_editor_camera = camera
		camera.current = true
	else:
		_macro_editor_preview_camera_id = 0
	var renderer := _find_player_renderer(player)
	if renderer != null:
		_macro_editor_preview_renderer = renderer
		_macro_editor_preview_renderer_pause_mode = renderer.pause_mode
		renderer.pause_mode = Node.PAUSE_MODE_PROCESS
	_enable_macro_editor_presentation_processing()
	_macro_editor_freecam_detached = false
	get_tree().paused = true
	_refresh_macro_editor_presentation()
	return true


# The native level presentation is camera-driven. Besides the SDF/fullscreen
# terrain pair, backgrounds, physics-block culling and ice shader uniforms all
# normally update in _process(). The Timeline Editor pauses gameplay, so these
# visual-only scripts must keep processing or freecam reveals a stale/incomplete
# level. Never add gameplay renderers here: several of them also drive sounds,
# particles or collision state.
func _enable_macro_editor_presentation_processing() -> void:
	_restore_macro_editor_presentation_processing()
	_collect_macro_editor_presentation_nodes(get_tree().root)
	for entry in _macro_editor_preview_presentation_nodes:
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node):
			node.pause_mode = Node.PAUSE_MODE_PROCESS


func _collect_macro_editor_presentation_nodes(node: Node) -> void:
	if node == null:
		return
	var script = node.get_script()
	if script != null:
		var script_path: String = str(script.get_path())
		if script_path in MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS:
			_macro_editor_preview_presentation_nodes.append({"node": node, "pause_mode": node.pause_mode, "script_path": script_path})
	for child in node.get_children():
		_collect_macro_editor_presentation_nodes(child)


func _refresh_macro_editor_presentation() -> void:
	# GameCamera normally updates this singleton after moving. Timeline freecam
	# moves the paused camera directly, so refresh it first; otherwise block
	# renderers continue culling against the rectangle from editor entry.
	_refresh_macro_editor_visible_rect()
	# Preserve the camera-dependent presentation pipeline order even if tree
	# order differs.
	for wanted_path in MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS:
		for entry in _macro_editor_preview_presentation_nodes:
			if entry["script_path"] != wanted_path:
				continue
			var node: Node = entry["node"]
			if node != null and is_instance_valid(node) and node.has_method("_process"):
				node.call("_process", 0.0)

	# Phase 0.9 -- Thin-Block Terrain Fallback. THIS is why every previous
	# version of this fix showed zero effect no matter what: TASTool's own
	# node never sets its own pause_mode away from the PAUSE_MODE_INHERIT
	# default, and _begin_macro_editor_preview() above pauses the whole
	# scene tree (get_tree().paused = true) for the Timeline Editor preview
	# Len has been testing in. A paused node with inherited pause_mode does
	# not receive _process() calls at all -- so _maintain_terrain_fallback_rendering(),
	# called from the top of TASTool's own _process(), was never running
	# during any of the previous attempts, regardless of what its detection
	# logic did or didn't find. This is the exact same failure mode already
	# solved for PolygonTerrain.gd itself right above (see that entry's own
	# comment in MACRO_EDITOR_PRESENTATION_SCRIPT_PATHS) -- a dirty/pending
	# visual update that only ever gets processed on an unpaused _process()
	# tick, which the Timeline Editor may never deliver. Forcing TASTool's
	# entire _process() to PAUSE_MODE_PROCESS was deliberately avoided (it
	# also drives input injection, replay recording and hotkeys, which
	# should NOT keep running just because a visual refresh is needed) --
	# calling just this one function here, synchronously, every time the
	# Timeline Editor actually refreshes its presentation (preview start,
	# freecam move/zoom/center/reset), is the same targeted fix already
	# used for PolygonTerrain, applied to this fallback too.
	_maintain_terrain_fallback_rendering(_find_game())


func _refresh_macro_editor_visible_rect() -> void:
	var calculator: Node = get_tree().root.get_node_or_null("ViewportRectCalculator")
	if calculator == null:
		return
	# The shipped game exposes the public name; some extracted source builds use
	# the underscored implementation name. Supporting both keeps the mod portable.
	if calculator.has_method("calculate_viewport_visible_rect"):
		calculator.call("calculate_viewport_visible_rect")
	elif calculator.has_method("_calculate_viewport_visible_rect"):
		calculator.call("_calculate_viewport_visible_rect")


func _restore_macro_editor_presentation_processing() -> void:
	for entry in _macro_editor_preview_presentation_nodes:
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node):
			node.pause_mode = int(entry["pause_mode"])
	_macro_editor_preview_presentation_nodes = []


func _preview_macro_editor_frame(frame: Dictionary) -> bool:
	if not _macro_editor_preview_active:
		return false
	var player := _get_local_player()
	if player == null or player.get_instance_id() != _macro_editor_preview_player_id:
		return false
	var state = frame.get(PRACTICE_FRAME_STATE_KEY, {})
	if typeof(state) != TYPE_DICTIONARY or not state.has("position"):
		return false
	var old_position: Vector2 = player.position
	_apply_recorded_practice_frame_state(player, state)
	_reset_renderer_smoothing(player)
	_set_macro_editor_preview_visual(player, old_position, player.position)
	return true


func _set_macro_editor_preview_visual(player: WPPlayer, from_position: Vector2, to_position: Vector2) -> void:
	var renderer := _find_player_renderer(player)
	if renderer != null:
		var position_node = renderer.get("position_node")
		if position_node != null and is_instance_valid(position_node):
			position_node.position = to_position
		var ui_node = renderer.get("ui_node")
		if ui_node != null and is_instance_valid(ui_node):
			ui_node.rect_position = to_position
	var camera := _macro_editor_camera
	if camera != null and is_instance_valid(camera) and not _macro_editor_freecam_detached:
		camera.position += to_position - from_position
		camera.force_update_scroll()
		_refresh_macro_editor_presentation()


func _move_macro_editor_freecam(screen_delta: Vector2) -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	if camera == null or not is_instance_valid(camera):
		return
	_macro_editor_freecam_detached = true
	camera.position += screen_delta * max(camera.zoom.x, camera.zoom.y)
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


func _zoom_macro_editor_freecam(factor: float) -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	if camera == null or not is_instance_valid(camera):
		return
	var next_zoom := clamp(camera.zoom.x * factor, 0.18, 4.0)
	camera.zoom = Vector2(next_zoom, next_zoom)
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


func _center_macro_editor_freecam() -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	var player := _get_local_player()
	if camera == null or not is_instance_valid(camera) or player == null:
		return
	_macro_editor_freecam_detached = false
	camera.position = player.position + _macro_editor_preview_camera_follow_offset
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


# Phase 0.4 -- Freecam Stability Pass. "Reset Camera" -- unlike
# _center_macro_editor_freecam() above (position only, keeps whatever zoom the
# user set), this also puts zoom back to what it was the moment preview began,
# so a lost/zoomed-out freecam can be recovered without closing the editor.
func _reset_macro_editor_freecam() -> void:
	if not _macro_editor_preview_active:
		return
	var camera := _macro_editor_camera
	var player := _get_local_player()
	if camera == null or not is_instance_valid(camera) or player == null:
		return
	_macro_editor_freecam_detached = false
	camera.position = player.position + _macro_editor_preview_camera_follow_offset
	camera.zoom = _macro_editor_preview_camera_zoom
	camera.force_update_scroll()
	_refresh_macro_editor_presentation()


func _get_macro_editor_freecam_zoom_percent() -> int:
	var camera := _macro_editor_camera
	if camera == null or not is_instance_valid(camera) or is_zero_approx(camera.zoom.x):
		return 100
	return int(round(100.0 / camera.zoom.x))


func _end_macro_editor_preview() -> void:
	if not _macro_editor_preview_active:
		return
	var player := _get_local_player()
	if player != null and player.get_instance_id() == _macro_editor_preview_player_id and not _macro_editor_preview_snapshot.empty():
		var preview_position: Vector2 = player.position
		_restore_player(player, _macro_editor_preview_snapshot)
		_set_macro_editor_preview_visual(player, preview_position, player.position)
	if _macro_editor_preview_renderer != null and is_instance_valid(_macro_editor_preview_renderer):
		_macro_editor_preview_renderer.pause_mode = _macro_editor_preview_renderer_pause_mode
	_macro_editor_preview_renderer = null
	if _macro_editor_camera != null and is_instance_valid(_macro_editor_camera) and _macro_editor_camera.get_instance_id() == _macro_editor_preview_camera_id:
		_macro_editor_camera.position = _macro_editor_preview_camera_position
		_macro_editor_camera.zoom = _macro_editor_preview_camera_zoom
		_macro_editor_camera.current = true
		_macro_editor_camera.force_update_scroll()
		_refresh_macro_editor_presentation()
	_restore_macro_editor_presentation_processing()
	_macro_editor_camera = null
	_macro_editor_preview_active = false
	_macro_editor_preview_player_id = 0
	_macro_editor_preview_snapshot = {}
	_macro_editor_preview_camera_id = 0
	_macro_editor_freecam_detached = false
	get_tree().paused = _macro_editor_preview_was_tree_paused


func _reset_saved_macro_autoplay_state() -> void:
	_saved_macro_autoplay_slot = 0
	_saved_macro_autoplay_level_id = ""
	_saved_macro_autoplay_source_game_id = 0
	_saved_macro_autoplay_elapsed = 0.0
	_saved_macro_autoplay_ready_ticks = 0
	_saved_macro_autoedit_slot = 0
	_saved_macro_editor_visual_signature = ""


func _macro_editor_level_visuals_ready(game: Node) -> bool:
	# The gameplay state can become playable before every deferred renderer and
	# level decoration has completed its first idle passes. Pausing the tree at
	# that moment leaves the editor looking like a bare collision-only level.
	if game == null or not ("level" in game) or game.get("level") == null:
		return false
	if ("has_loaded_level" in game) and not bool(game.get("has_loaded_level")):
		return false
	var level = game.get("level")
	if not ("loaded_level" in level) or level.get("loaded_level") == null:
		return false
	var loaded_level: Node = level.get("loaded_level")
	if not loaded_level.is_inside_tree() or loaded_level.get_child_count() == 0:
		return false
	if not ("client_renderer" in game) or game.get("client_renderer") == null:
		return false
	var renderer: Node = game.get("client_renderer")
	if not renderer.is_inside_tree() or renderer.get_node_or_null("Level_InterpolateRenderers") == null:
		return false
	var camera := _find_playback_camera()
	return camera != null and camera.is_inside_tree()


func _macro_editor_visual_signature(game: Node) -> String:
	if not _macro_editor_level_visuals_ready(game):
		return ""
	var level = game.get("level")
	var loaded_level: Node = level.get("loaded_level")
	var renderer: Node = game.get("client_renderer")
	return "%d:%d:%d:%d" % [loaded_level.get_instance_id(), _count_scene_nodes(loaded_level), renderer.get_instance_id(), _count_scene_nodes(renderer)]


func _count_scene_nodes(node: Node) -> int:
	if node == null:
		return 0
	var count := 1
	for child in node.get_children():
		count += _count_scene_nodes(child)
	return count


func _cancel_saved_macro_autoplay(message: String) -> void:
	_reset_saved_macro_autoplay_state()
	_log_action(message, null)
	_refresh_practice_ui()


func _on_play_saved_practice_macro_slot_pressed(slot: int) -> void:
	if not _practice_macro_slots.has(slot):
		_log_action("Macro Bot Slot %d is empty" % slot, null)
		return
	if _saved_macro_autoplay_slot > 0:
		_log_action("A saved Macro Bot level is already opening", null)
		return
	var data: Dictionary = _practice_macro_slots[slot]
	var level_id: = _macro_slot_level_id(data)
	if level_id.empty():
		_log_action("Macro Bot Slot %d has no saved level link -- load it inside the correct linked Time Trial and press Save once to upgrade the slot" % slot, null)
		return

	var packed_scene = GoodResourceLoader.load_resource("res://scenes/TimeTrialGameplayScene.tscn")
	if packed_scene == null:
		_log_action("Couldn't open the saved Macro Bot level: Time Trial scene is unavailable", null)
		return
	var game_scene = packed_scene.instance()
	if game_scene == null:
		_log_action("Couldn't open the saved Macro Bot level: Time Trial scene could not be created", null)
		return
	var parameters: = TimeTrialSceneParameters.new()
	parameters.mode = TimeTrialSceneParameters.TimeTrialSceneMode.TimeTrial
	parameters.level_id = level_id
	game_scene.set("parameters", parameters)

	var current_game: = _find_game()
	_saved_macro_autoplay_slot = slot
	_saved_macro_autoplay_level_id = level_id
	_saved_macro_autoplay_source_game_id = current_game.get_instance_id() if current_game != null else 0
	_saved_macro_autoplay_elapsed = 0.0
	_practice_active = false
	_practice_start_waiting = false
	_practice_place_pending = false
	_release_all_injected_actions()
	_is_paused = false
	Engine.time_scale = 1.0
	var level_name: = _macro_slot_level_name(data)
	if level_name.empty():
		level_name = level_id
	_log_action("Opening '%s' for one-click Macro Slot %d playback..." % [level_name, slot], null)
	_refresh_practice_ui()
	# This is the game's own level-browser transition path. The TASTool node
	# is outside current_scene, so it and the pending slot survive the swap.
	ScreenTransitions.fade_to_scene_node(game_scene)


func _watch_saved_macro_autoplay(delta: float) -> void:
	if _saved_macro_autoplay_slot <= 0:
		return
	_saved_macro_autoplay_elapsed += delta
	if _saved_macro_autoplay_elapsed > SAVED_MACRO_AUTOPLAY_TIMEOUT_SECONDS:
		_cancel_saved_macro_autoplay("Saved Macro Bot playback timed out while waiting for the level to become playable")
		return

	var scene: = get_tree().current_scene
	if scene == null or not ("parameters" in scene):
		return
	var parameters = scene.get("parameters")
	if parameters == null or not ("level_id" in parameters):
		return
	if str(parameters.get("level_id")) != _saved_macro_autoplay_level_id:
		return
	var game: = _find_game()
	if game == null or not scene.is_a_parent_of(game):
		return
	if _saved_macro_autoplay_source_game_id != 0 and game.get_instance_id() == _saved_macro_autoplay_source_game_id:
		return
	if not _game_ready_for_practice_start():
		_saved_macro_autoplay_ready_ticks = 0
		_saved_macro_editor_visual_signature = ""
		return
	var player: = _get_local_player()
	if player == null or not _player_ready_for_checkpoint(player):
		_saved_macro_autoplay_ready_ticks = 0
		_saved_macro_editor_visual_signature = ""
		return
	var waiting_for_editor_visuals: bool = _saved_macro_autoedit_slot == _saved_macro_autoplay_slot
	if waiting_for_editor_visuals and not _macro_editor_level_visuals_ready(game):
		_saved_macro_autoplay_ready_ticks = 0
		_saved_macro_editor_visual_signature = ""
		return
	if waiting_for_editor_visuals:
		# Level deserialization is synchronous, but several renderer/decor nodes
		# join the tree during following idle passes. Wait until both the loaded
		# level and renderer trees stop changing instead of sleeping for an
		# arbitrary 45 ticks and hoping every machine is finished by then.
		var visual_signature := _macro_editor_visual_signature(game)
		if visual_signature.empty() or visual_signature != _saved_macro_editor_visual_signature:
			_saved_macro_editor_visual_signature = visual_signature
			_saved_macro_autoplay_ready_ticks = 0
			return

	var slot: = _saved_macro_autoplay_slot
	if not _practice_macro_slots.has(slot):
		_cancel_saved_macro_autoplay("Saved Macro Bot slot disappeared while its level was opening")
		return
	var data: Dictionary = _practice_macro_slots[slot]
	var target_play_time: = 0.0
	var saved_checkpoints: Array = data.get("checkpoints", [])
	if not saved_checkpoints.empty() and typeof(saved_checkpoints[0]) == TYPE_DICTIONARY:
		target_play_time = max(0.0, float(saved_checkpoints[0].get("play_time", 0.0)))
	var current_play_time: = float(game.wp_game_data.play_time)
	var physics_tick: = 1.0 / max(1.0, float(Engine.iterations_per_second))
	if current_play_time + physics_tick * 0.25 < target_play_time:
		_saved_macro_autoplay_ready_ticks = 0
		return
	_saved_macro_autoplay_ready_ticks += 1
	var required_ready_ticks := PRACTICE_READY_STABLE_TICKS_REQUIRED
	if _saved_macro_autoplay_ready_ticks < required_ready_ticks:
		return

	# Clear the pending launch before calling the ordinary Play handler so a
	# failure cannot repeatedly re-enter it on every following physics tick.
	var open_editor_after_load := _saved_macro_autoedit_slot == slot
	_reset_saved_macro_autoplay_state()
	if open_editor_after_load:
		_saved_macro_autoedit_slot = 0
		if _macro_editor == null or not is_instance_valid(_macro_editor):
			_log_action("Macro Timeline Editor failed to load after opening the level", null)
			return
		_log_action("Opened the linked level for Macro Slot %d editing" % slot, null)
		_macro_editor.call("open_editor", slot, data)
		_update_mouse_capture()
		return
	if not _install_practice_macro_slot_data(slot, player, false):
		_log_action("Couldn't load Macro Bot Slot %d after opening its level" % slot, null)
		_refresh_practice_ui()
		return
	_log_action("Macro Bot Slot %d level is ready at %.3fs (recorded start %.3fs) -- starting automatically" % [slot, current_play_time, target_play_time], null)
	_on_play_practice_macro_pressed()


func _on_delete_practice_macro_slot_pressed(slot: int) -> void:
	if not _practice_macro_slots.has(slot):
		_log_action("Macro Bot Slot %d is already empty" % slot, null)
		return
	_practice_macro_slots.erase(slot)
	_delete_practice_macro_slot_file(slot)
	_log_action("Deleted Macro Bot Slot %d" % slot, null)
	_refresh_practice_macro_slot_ui(slot)


# ----------------------------------------------------------------------
#  Macro Bot Mode -- UI refresh
# ----------------------------------------------------------------------
func _refresh_practice_ui() -> void:
	if _debug_tools_container != null:
		_debug_tools_container.visible = _debug_mode_enabled
	if _diag_label != null:
		_diag_label.visible = _debug_mode_enabled
	if _hitbox_viewer_button != null:
		_hitbox_viewer_button.text = "◫ Hitbox Viewer: %s" % ("ON" if _hitbox_viewer_enabled else "OFF")
		_style_button(_hitbox_viewer_button, COLOR_PINK if _hitbox_viewer_enabled else COLOR_BLUE)
	if _trajectory_preview_button != null:
		_trajectory_preview_button.text = "⌁ Trajectory Preview: %s" % ("ON" if _trajectory_preview_enabled else "OFF")
		_style_button(_trajectory_preview_button, COLOR_PINK if _trajectory_preview_enabled else COLOR_BLUE)
	if _input_display_button != null:
		_input_display_button.text = "⌨ Input Display: %s" % ("ON" if _input_display_enabled else "OFF")
		_style_button(_input_display_button, COLOR_PINK if _input_display_enabled else COLOR_BLUE)
	if _input_display_detailed_button != null:
		_input_display_detailed_button.visible = _input_display_enabled
		_input_display_detailed_button.text = "Detailed" if _input_display_detailed else "Compact"
		_style_button(_input_display_detailed_button, COLOR_PINK if _input_display_detailed else COLOR_BLUE, 12, 3)
	if _input_display_hold_frames_button != null:
		_input_display_hold_frames_button.visible = _input_display_enabled
		_input_display_hold_frames_button.text = "Frame Holds: %s" % ("ON" if _input_display_hold_frames else "OFF")
		_style_button(_input_display_hold_frames_button, COLOR_PINK if _input_display_hold_frames else COLOR_BLUE, 12, 3)
	_refresh_hitbox_category_ui()
	if _visual_seam_polish_button != null:
		_visual_seam_polish_button.text = "◇ Visual Seam Polish: %s" % ("ON" if _visual_seam_polish_enabled else "OFF")
		_style_button(_visual_seam_polish_button, COLOR_PINK if _visual_seam_polish_enabled else COLOR_BLUE)
	if _sync_moving_objects_button != null:
		_sync_moving_objects_button.text = "↻ Moving Object Sync: %s" % ("ON" if _sync_moving_objects_enabled else "OFF")
		_style_button(_sync_moving_objects_button, COLOR_PINK if _sync_moving_objects_enabled else COLOR_BLUE)
	if _debug_mode_toggle_button != null:
		_debug_mode_toggle_button.text = "Debug Mode: ON" if _debug_mode_enabled else "Debug Mode: OFF"
		_style_button(_debug_mode_toggle_button, COLOR_PINK if _debug_mode_enabled else COLOR_BLUE)
	if _diag_toggle_button != null:
		_diag_toggle_button.text = "Diagnostic Logging: ON" if _diag_enabled else "Diagnostic Logging: OFF"
		_style_button(_diag_toggle_button, COLOR_PINK if _diag_enabled else COLOR_BLUE)
		_diag_toggle_button.disabled = _debug_mode_enabled # Debug Mode owns this while it's on -- see _on_toggle_debug_mode_pressed()/_on_toggle_diag_pressed()
	if _practice_toggle_button != null:
		_practice_toggle_button.text = "■ Stop Macro Bot Mode" if (_practice_active or _practice_start_waiting) else "▶ Start Macro Bot Mode"
		_style_button(_practice_toggle_button, COLOR_PINK if (_practice_active or _practice_start_waiting) else COLOR_BLUE)
	var checkpoint_count: = max(_practice_checkpoints.size() - 1, 0)
	if _practice_status_label != null:
		var practice_text: String
		if _practice_playback:
			practice_text = "Playing back... (%d/%d frames)" % [_practice_playback_index, _practice_playback_frames.size()]
		elif _saved_macro_autoplay_slot > 0:
			practice_text = "Opening saved level for Macro Slot %d..." % _saved_macro_autoplay_slot
		elif _practice_start_waiting:
			practice_text = "waiting for you to be able to move (e.g. the level's opening hold) before recording checkpoint 0..."
		elif _practice_place_pending:
			practice_text = "placing checkpoint %d as soon as you're able to move..." % [_practice_checkpoints.size()]
		elif _practice_active:
			practice_text = "%d checkpoint(s) -- segment: %d frame(s), %d death(s)" % [checkpoint_count, _practice_current_segment.size(), _practice_deaths_this_segment]
		else:
			practice_text = "%d checkpoint(s) placed" % [checkpoint_count]
		_practice_status_label.text = practice_text
		_ui_last_practice_status = practice_text # keep _update_overlay()'s cache in sync so it doesn't immediately re-write the same text
	if _practice_place_button != null:
		_practice_place_button.disabled = not _practice_active
	if _practice_undo_button != null:
		_practice_undo_button.disabled = _practice_checkpoints.size() <= 1
	if _practice_play_button != null:
		_practice_play_button.disabled = _practice_segments.empty() or _practice_playback
	if _practice_clear_button != null:
		_practice_clear_button.disabled = _practice_checkpoints.empty()
	if _diag_status_label != null:
		var live_ticks: = 0
		for seg in _diag_live_committed:
			live_ticks += seg.size()
		_diag_status_label.text = "diagnostics: %d live tick(s) captured, %d replay tick(s) captured" % [live_ticks, _diag_replay_log.size()]
	if _stop_on_desync_button != null:
		_stop_on_desync_button.text = "Stop on Desync: %s" % ("ON" if _replay_check_stop_on_desync else "OFF")
		_style_button(_stop_on_desync_button, COLOR_PINK if _replay_check_stop_on_desync else COLOR_BLUE)
	if _self_test_stop_on_failure_button != null:
		_self_test_stop_on_failure_button.text = "Stop on Failure: %s" % ("ON" if _self_test_stop_on_failure else "OFF")
		_style_button(_self_test_stop_on_failure_button, COLOR_PINK if _self_test_stop_on_failure else COLOR_BLUE)
	if _self_test_x3_button != null:
		var self_test_disabled: = _practice_segments.empty() or _practice_playback
		_self_test_x3_button.disabled = self_test_disabled
		_self_test_x5_button.disabled = self_test_disabled
		_self_test_x10_button.disabled = self_test_disabled
	for i in range(1, _practice_macro_slot_count + 1):
		_refresh_practice_macro_slot_ui(i)


func _refresh_practice_macro_slot_ui(slot: int) -> void:
	if _practice_macro_slot_status_labels.size() <= slot:
		return
	var has_data: = _practice_macro_slots.has(slot)
	var has_level_link: = false
	if has_data:
		var slot_data: Dictionary = _practice_macro_slots[slot]
		has_level_link = not _macro_slot_level_id(slot_data).empty()
		var macro_name := str(slot_data.get("name", ""))
		var level_name: = _macro_slot_level_name(slot_data)
		if not macro_name.empty():
			if macro_name.length() > 15:
				macro_name = macro_name.substr(0, 14) + "…"
			_practice_macro_slot_status_labels[slot].text = "%s · %d cp" % [macro_name, slot_data["checkpoints"].size() - 1]
		elif not level_name.empty():
			if level_name.length() > 15:
				level_name = level_name.substr(0, 14) + "…"
			_practice_macro_slot_status_labels[slot].text = "Saved (%d cp) · %s" % [slot_data["checkpoints"].size() - 1, level_name]
		elif has_level_link:
			_practice_macro_slot_status_labels[slot].text = "Saved (%d cp) · linked" % [slot_data["checkpoints"].size() - 1]
		else:
			_practice_macro_slot_status_labels[slot].text = "Saved (%d cp) · re-save to link" % [slot_data["checkpoints"].size() - 1]
	else:
		_practice_macro_slot_status_labels[slot].text = "Empty"
	_practice_macro_slot_play_buttons[slot].disabled = not has_level_link or _saved_macro_autoplay_slot > 0 or _practice_playback
	_practice_macro_slot_load_buttons[slot].disabled = not has_data
	_practice_macro_slot_delete_buttons[slot].disabled = not has_data
	_practice_macro_slot_edit_buttons[slot].disabled = not has_data
	var card: PanelContainer = _practice_macro_slot_cards[slot]
	if has_data:
		card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_FILLED, COLOR_SLOT_FILLED_BORDER, 3, 16))
		_practice_macro_slot_status_labels[slot].add_color_override("font_color", Color(0, 0.15, 0.3))
	else:
		card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, COLOR_WHITE, 3, 16))
		_practice_macro_slot_status_labels[slot].add_color_override("font_color", COLOR_TEXT_DIM)


# ----------------------------------------------------------------------
#  Input edge-detection helper (so holding a key only fires once)
# ----------------------------------------------------------------------
func _just_pressed(keycode: int) -> bool:
	var pressed: = Input.is_key_pressed(keycode)
	var was_pressed: bool = _prev_key_state.get(keycode, false)
	_prev_key_state[keycode] = pressed
	return pressed and not was_pressed


# Synthesizes a real action press/release via Input.parse_input_event() --
# the same mechanism this game's OWN touch-screen buttons use to drive
# gameplay (see goodoh/ui/components/TouchableButton.gd /
# InputActionOnPress.gd, which do exactly this for player_up/left/right/
# dash), so the native player controller -- which reads these through
# Input.get_action_strength()/is_action_pressed()/is_action_just_pressed(),
# confirmed verbatim in project_specific/GameInput.gd -- can't tell an
# injected press from a real one, on ANY of the physical keys/joypad
# buttons/touch controls this game's InputMap actually binds to that action
# (see the ACTION_* constants above for why recording raw keycodes instead
# of actions was the real reason macros used to reproduce none of what was
# actually done). Used by Buffered Inputs (step feature) and Perfect
# Jumpzone mode, as well as Macro Bot Mode recording/playback below.
# Godot updates Input's tracked action state synchronously when this is
# called, so a step's physics tick(s) immediately after see it as held.
func _inject_action(action: String, pressed: bool) -> void:
	var ev: = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)
	# parse_input_event() alone only QUEUES the event -- Godot normally
	# flushes queued input once per frame, but that timing isn't
	# guaranteed to land before the very next physics tick (the one a
	# frame-step is about to run). Flushing explicitly makes the new
	# action state take effect immediately instead of a frame late.
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


# Safety net so an action TASTool synthetically pressed can never stay stuck
# held once the tool is disabled or becomes restricted (e.g. you were mid
# frame-step or had Perfect Jumpzone armed and then joined a live match).
func _release_all_injected_actions() -> void:
	for action in _injected_actions_held:
		_inject_action(action, false)
	_injected_actions_held.clear()
	_release_practice_playback_injected_input()
	_stop_jumpzone_key()
	if _practice_playback:
		_practice_playback = false
		_practice_playback_settling = false
		_practice_playback_settled_boundary = -1
		_practice_playback_frames = []
		_log_action("Macro Bot Mode: playback aborted (tool became inactive/restricted)", null)
		_refresh_practice_ui()


# ----------------------------------------------------------------------
#  Window open/close + dragging (also handles forcing the mouse cursor
#  visible so you can actually click things)
# ----------------------------------------------------------------------
func _toggle_overlay_hidden() -> void:
	_overlay_hidden = not _overlay_hidden
	if _overlay_layer != null:
		_overlay_layer.visible = _tas_gui_enabled and not _overlay_hidden
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.visible = not _overlay_hidden
	# Checkpoint markers live in world space under WPGame rather than under the
	# overlay CanvasLayer, so F1 must explicitly mirror their visibility too.
	_set_practice_markers_visible(_tas_gui_enabled and not _overlay_hidden)
	_update_mouse_capture()


func _set_menu_open(open: bool) -> void:
	_menu_open = open
	if open:
		_ui_next_diag_refresh_msec = 0 # refresh immediately after reopening, then return to the throttled cadence below
	_apply_menu_open_state()


func _apply_menu_open_state() -> void:
	if _menu_panel != null:
		_menu_panel.visible = _menu_open
	if _tab_button != null:
		_tab_button.text = _tab_text()
	_update_mouse_capture()


func _set_log_open(open: bool) -> void:
	_log_open = open and _debug_mode_enabled
	_apply_log_open_state()


func _apply_log_open_state() -> void:
	if _log_panel != null:
		_log_panel.visible = _log_open and _debug_mode_enabled
	if _log_tab_row != null:
		_log_tab_row.visible = _debug_mode_enabled and enabled and _tas_gui_enabled and not _overlay_hidden
	if _log_tab_button != null:
		_log_tab_button.text = _log_tab_text()
	_update_mouse_capture()


func _update_mouse_capture() -> void:
	var editor_open: bool = _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("is_open") and bool(_macro_editor.call("is_open"))
	var want_visible: = ((_menu_open or (_log_open and _debug_mode_enabled)) and _tas_gui_enabled and not _overlay_hidden) or editor_open
	if want_visible:
		if _prev_mouse_mode == -1:
			_prev_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _prev_mouse_mode != -1:
			Input.mouse_mode = _prev_mouse_mode
			_prev_mouse_mode = -1


func _on_tab_pressed() -> void:
	_set_menu_open(not _menu_open)


func _on_log_tab_pressed() -> void:
	_set_log_open(not _log_open)


func _on_drag_gui_input(event: InputEvent, which: String) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_dragging[which] = event.pressed
		if not event.pressed:
			_save_main_window_layout(which)
	elif event is InputEventMouseMotion and _dragging.get(which, false):
		var window: Control = _menu_window if which == "menu" else _log_window
		# The drag grip is a descendant of `window`, which carries
		# rect_scale from the UI Scale control -- Godot reports
		# event.relative already divided by that scale (it's in the
		# grip's own scaled-down local space), so it has to be multiplied
		# back out here or dragging would move slower/faster than the
		# mouse at anything other than 100%.
		var viewport_size: Vector2 = get_viewport().size
		var scaled_size: Vector2 = window.rect_size * ui_scale
		var screen_delta: Vector2 = event.relative * ui_scale
		if _window_geometry != null:
			window.rect_position = _window_geometry.moved_position(window.rect_position, scaled_size, screen_delta, viewport_size, 120.0, 48.0)
		else:
			var next: Vector2 = window.rect_position + screen_delta
			next.x = clamp(next.x, -scaled_size.x + 120.0, viewport_size.x - 120.0)
			next.y = clamp(next.y, 0.0, viewport_size.y - 48.0)
			window.rect_position = next


func _on_resize_gui_input(event: InputEvent, which: String) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_resizing[which] = event.pressed
		if not event.pressed:
			_save_main_window_layout(which)
	elif event is InputEventMouseMotion and _resizing.get(which, false):
		var window: Control = _menu_window if which == "menu" else _log_window
		var viewport_size: Vector2
		if _window_geometry != null:
			viewport_size = _window_geometry.available_local_size(get_viewport().size, window.rect_position, ui_scale)
		else:
			viewport_size = (get_viewport().size - window.rect_position) / max(ui_scale, 0.01)
		if which == "menu":
			var menu_max_w := max(520.0, viewport_size.x - 30.0)
			var menu_max_h := max(260.0, viewport_size.y - 150.0)
			_menu_panel.rect_min_size.x = clamp(_menu_panel.rect_min_size.x + event.relative.x, 520.0, menu_max_w)
			for scroll in _tool_tab_scrolls:
				if scroll != null:
					scroll.rect_min_size.y = clamp(scroll.rect_min_size.y + event.relative.y, 240.0, menu_max_h)
		else:
			var log_max_w := max(420.0, viewport_size.x - 30.0)
			var log_max_h := max(150.0, viewport_size.y - 140.0)
			_log_panel.rect_min_size.x = clamp(_log_panel.rect_min_size.x + event.relative.x, 420.0, log_max_w)
			if _log_scroll != null:
				_log_scroll.rect_min_size.y = clamp(_log_scroll.rect_min_size.y + event.relative.y, 140.0, log_max_h)


func _make_resize_handle(which: String) -> Button:
	var handle := _make_small_button("↘", Color(0.08, 0.34, 0.55, 0.78), 48)
	handle.rect_min_size = Vector2(48, 38)
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.hint_tooltip = "Drag to resize this window."
	handle.connect("gui_input", self, "_on_resize_gui_input", [which])
	return handle


func _apply_ui_scale() -> void:
	ui_scale = clamp(ui_scale, UI_SCALE_MIN, UI_SCALE_MAX)
	if _menu_window != null:
		_menu_window.rect_scale = Vector2(ui_scale, ui_scale)
	if _log_window != null:
		_log_window.rect_scale = Vector2(ui_scale, ui_scale)
	if _scale_label != null:
		_scale_label.text = "%d%%" % round(ui_scale * 100)


func _on_ui_scale_delta_pressed(delta: float) -> void:
	ui_scale = clamp(ui_scale + delta, UI_SCALE_MIN, UI_SCALE_MAX)
	_apply_ui_scale()


# ----------------------------------------------------------------------
#  Shared UI building helpers. Everything is built from real
#  Control/Button nodes, styled after GooberDash's own UI: thick
#  white-bordered, heavily rounded pill buttons over a dark rounded panel,
#  in the game's Baloo font.
# ----------------------------------------------------------------------
func _make_font(size: int) -> DynamicFont:
	var data: = load(FONT_PATH)
	if data == null or not (data is DynamicFontData):
		return null
	var f: = DynamicFont.new()
	var crisp_data: DynamicFontData = data.duplicate()
	crisp_data.antialiased = true
	crisp_data.override_oversampling = 2.0
	f.font_data = crisp_data
	f.size = size
	f.outline_size = 1
	f.outline_color = Color(0, 0.02, 0.05, 0.95)
	f.use_filter = true
	f.use_mipmaps = true
	return f


func _make_flat_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	var s: = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_w
	s.border_width_top = border_w
	s.border_width_right = border_w
	s.border_width_bottom = border_w
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_detail = 12
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_label(text: String, font: DynamicFont, color: Color) -> Label:
	var l: = Label.new()
	l.text = text
	if font != null:
		l.add_font_override("font", font)
	l.add_color_override("font_color", color)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	l.add_constant_override("shadow_offset_x", 1)
	l.add_constant_override("shadow_offset_y", 1)
	return l


# Applies GooberDash-style pill/rounded button visuals across all states.
func _style_button(btn: Button, bg: Color, corner: int = 18, border_w: int = 4) -> void:
	btn.add_stylebox_override("normal", _make_flat_style(bg, COLOR_WHITE, border_w, corner))
	btn.add_stylebox_override("hover", _make_flat_style(bg.lightened(0.15), COLOR_WHITE, border_w, corner))
	btn.add_stylebox_override("pressed", _make_flat_style(bg.darkened(0.2), COLOR_WHITE, border_w, corner))
	btn.add_stylebox_override("focus", _make_flat_style(bg.lightened(0.15), COLOR_WHITE, border_w, corner))
	btn.add_stylebox_override("disabled", _make_flat_style(COLOR_DISABLED, Color(1, 1, 1, 0.3), border_w, corner))
	if _body_font != null:
		btn.add_font_override("font", _body_font)
	btn.add_color_override("font_color", COLOR_WHITE)
	btn.add_color_override("font_color_hover", COLOR_WHITE)
	btn.add_color_override("font_color_pressed", COLOR_WHITE)
	btn.add_color_override("font_color_disabled", Color(1, 1, 1, 0.5))


func _make_button(text: String, bg: Color, min_w: int = 0) -> Button:
	var btn: = Button.new()
	btn.text = text
	_style_button(btn, bg)
	btn.rect_min_size = Vector2(min_w, BUTTON_H)
	# No keyboard focus -- otherwise a clicked button stays focused and the
	# game's own Space/Enter-bound actions (e.g. dash on Space) would
	# re-trigger it via Godot's default ui_accept-activates-focused-control
	# behavior instead of reaching the game.
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _make_small_button(text: String, bg: Color, min_w: int = 0) -> Button:
	var btn: = Button.new()
	btn.text = text
	_style_button(btn, bg, 12, 3)
	if _small_font != null:
		btn.add_font_override("font", _small_font)
	btn.rect_min_size = Vector2(min_w, 40)
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _add_section_header(parent: VBoxContainer, title: String) -> void:
	var spacer: = Control.new()
	spacer.rect_min_size = Vector2(0, 12)
	parent.add_child(spacer)
	parent.add_child(_make_label(title, _header_font, COLOR_BLUE))


# Creates one page of the section-tab menu: a fixed-height ScrollContainer
# (so a tall section scrolls internally instead of growing the window past
# the screen or pushing the tab strip out of view) wrapping a VBoxContainer
# that the section's own controls get added to. The ScrollContainer's
# `name` becomes that tab's visible title in the TabContainer.
func _add_tab_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll: = ScrollContainer.new()
	scroll.name = title
	scroll.rect_min_size = Vector2(0, MENU_TAB_CONTENT_H)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_tab_scrolls.append(scroll)
	var page: = VBoxContainer.new()
	page.add_constant_override("separation", 4)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	tabs.add_child(scroll)
	return page


# A small draggable grip bar. Connect its gui_input to move `which` window.
func _make_drag_handle(which: String) -> PanelContainer:
	var grip: = PanelContainer.new()
	grip.add_stylebox_override("panel", _make_flat_style(COLOR_GRIP, COLOR_WHITE, 3, 999))
	grip.rect_min_size = GRIP_SIZE
	var label: = _make_label("::::", _header_font, COLOR_TEXT_DIM)
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip.add_child(label)
	grip.connect("gui_input", self, "_on_drag_gui_input", [which])
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	return grip


func _tab_text() -> String:
	var arrow: = "▴" if _menu_open else "▾"
	if not enabled:
		return "GOOBPLAYABILITY — DISABLED"
	var speed: float = _saved_time_scale if _is_paused else Engine.time_scale
	var bits: = "GOOBPLAYABILITY %s   %.2fx" % [arrow, speed]
	if _is_paused:
		bits += "  STOPPED"
	if _is_recording():
		bits += "  ● REC"
	return bits


func _log_tab_text() -> String:
	var arrow: = "▴" if _log_open else "▾"
	return "LOG %s   (%d)" % [arrow, _log_entries.size()]


func _is_recording() -> bool:
	var g: = _find_game()
	if g == null:
		return false
	return g.get_replay_status() != NetworkGame.REPLAY_STATUS_NONE


func _build_overlay() -> void:
	_title_font = _make_font(SIZE_TITLE)
	_header_font = _make_font(SIZE_HEADER)
	_body_font = _make_font(SIZE_BODY)
	_small_font = _make_font(SIZE_SMALL)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	add_child(_overlay_layer)

	_build_menu_window()
	_build_log_window()

	_menu_window.rect_position = Vector2(24, 24)
	_log_window.rect_position = Vector2(24, 24 + TAB_SIZE.y + 16)


func _build_menu_window() -> void:
	_menu_window = VBoxContainer.new()
	_menu_window.add_constant_override("separation", 10)
	# Pure layout wrapper -- must never itself catch clicks aimed at the
	# game/menu underneath. Only actual controls (the tab button, drag
	# grip, scale buttons, and the panel background while it's open)
	# should intercept anything.
	_menu_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_menu_window)

	# --- the drop-down tab, with its own drag grip and a UI Scale control
	# (applies to both windows -- reachable without opening the panel) ---
	_tab_row = HBoxContainer.new()
	_tab_row.add_constant_override("separation", 6)
	_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_row.add_child(_make_drag_handle("menu"))

	_tab_button = Button.new()
	_tab_button.text = _tab_text()
	_style_button(_tab_button, COLOR_PANEL_BG, 999, 4)
	if _header_font != null:
		_tab_button.add_font_override("font", _header_font)
	_tab_button.rect_min_size = TAB_SIZE
	_tab_button.align = Button.ALIGN_CENTER
	_tab_button.focus_mode = Control.FOCUS_NONE # see _make_button -- keeps Space free for the game
	_tab_button.connect("pressed", self, "_on_tab_pressed")
	_tab_row.add_child(_tab_button)

	var scale_minus: = _make_small_button("−", COLOR_BLUE, 40)
	scale_minus.connect("pressed", self, "_on_ui_scale_delta_pressed", [-UI_SCALE_STEP])
	_tab_row.add_child(scale_minus)
	_scale_label = _make_label("%d%%" % round(ui_scale * 100), _small_font, COLOR_WHITE)
	_scale_label.rect_min_size = Vector2(56, 0)
	_scale_label.align = Label.ALIGN_CENTER
	_scale_label.valign = Label.VALIGN_CENTER
	_tab_row.add_child(_scale_label)
	var scale_plus: = _make_small_button("+", COLOR_BLUE, 40)
	scale_plus.connect("pressed", self, "_on_ui_scale_delta_pressed", [UI_SCALE_STEP])
	_tab_row.add_child(scale_plus)

	# Performance readout is part of Debug Mode and stays completely hidden
	# during ordinary use.
	_diag_label = _make_label("", _small_font, COLOR_TEXT_DIM)
	_diag_label.visible = _debug_mode_enabled
	_tab_row.add_child(_diag_label)

	_menu_window.add_child(_tab_row)

	# --- transient status toast ---
	# THE TWENTY-NINTH-PASS FIX (2026-08-31, user report: "the GUI keeps
	# moving up and down... sometimes I accidentally click the wrong
	# button"): this pill sits directly inside _menu_window, a
	# VBoxContainer, right above _menu_panel (which holds every section
	# page -- including the Place Checkpoint/Undo/Clear row). Toggling a
	# direct child of a BoxContainer's own `.visible` doesn't just hide it
	# in place -- Godot's BoxContainer skips invisible children entirely
	# when it re-sorts, so the toast popping in and out of existence
	# (every ~2.5s, driven by _status_message_timer, and Macro Bot Mode
	# fires a fresh status message on nearly every action -- checkpoint
	# placed, died, respawned, ...) yanked _menu_panel and everything in it
	# up and down by the toast's own height each time. That's exactly what
	# was landing clicks on the wrong button while placing checkpoints
	# rapidly. Fixed by never touching `.visible` again -- the toast now
	# stays permanently present in the layout (a constant-height slot,
	# same as any other row) and shows/hides purely via `modulate.a`, which
	# affects only how it DRAWS, not how BoxContainer sizes/sorts around
	# it. Everything below it now stays put regardless of how often status
	# messages fire.
	_toast_pill = PanelContainer.new()
	_toast_pill.add_stylebox_override("panel", _make_flat_style(COLOR_PINK_DARK, COLOR_WHITE, 3, 999))
	var toast_label: = _make_label(" ", _body_font, COLOR_WHITE) # single space, not "" -- keeps the reserved slot's height identical to a real one-line message even before anything's ever been shown
	# Fixed width + clipped, no autowrap: a long status message (plenty of
	# them run a full sentence or more) would otherwise stretch this pill --
	# and therefore the whole window's width -- out to fit it, which is the
	# same "things keep shifting under my cursor" problem this whole pass is
	# about, just sideways instead of vertically. Clipping trades showing
	# the tail of a very long message for a window that never moves.
	toast_label.rect_min_size.x = TAB_SIZE.x - 40
	toast_label.clip_text = true
	_toast_pill.add_child(toast_label)
	_toast_pill.set_meta("label", toast_label)
	_toast_pill.modulate.a = 0.0
	_menu_window.add_child(_toast_pill)

	# --- the drop-down panel itself -- background alpha is configurable
	# (menu_background_opacity) so the game stays visible through it ---
	var panel_bg: = Color(COLOR_PANEL_BG.r, COLOR_PANEL_BG.g, COLOR_PANEL_BG.b, menu_background_opacity)

	_menu_panel = PanelContainer.new()
	_menu_panel.add_stylebox_override("panel", _make_flat_style(panel_bg, COLOR_PANEL_BORDER, 3, 26))
	_menu_panel.rect_min_size = Vector2(MENU_PANEL_MIN_W, 0)
	_menu_window.add_child(_menu_panel)

	var vb: = VBoxContainer.new()
	vb.add_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_panel.add_child(vb)

	vb.add_child(_make_label("GOOBPLAYABILITY", _title_font, COLOR_BLUE))

	_inactive_label = _make_label("Goobplayability is unavailable in live multiplayer matches.", _body_font, COLOR_TEXT_DIM)
	_inactive_label.visible = false
	_inactive_label.autowrap = true
	_inactive_label.rect_min_size = Vector2(MENU_PANEL_MIN_W - 60, 0)
	vb.add_child(_inactive_label)

	# Each heading below is now its own tab/page instead of one long
	# scrolling wall of every section stacked on top of each other -- and
	# each page is individually height-capped and independently scrollable
	# (see _add_tab_page), so a tall one (Macro Bot) can never push the tab
	# strip itself off-screen or make the window taller than the viewport.
	_section_tabs = TabContainer.new()
	_section_tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	_section_tabs.add_stylebox_override("panel", _make_flat_style(panel_bg, COLOR_PANEL_BORDER, 2, 16))
	_section_tabs.add_stylebox_override("tab_fg", _make_flat_style(COLOR_PINK, COLOR_WHITE, 2, 12))
	_section_tabs.add_stylebox_override("tab_bg", _make_flat_style(COLOR_BLUE.darkened(0.35), Color(1, 1, 1, 0.3), 2, 12))
	if _body_font != null:
		_section_tabs.add_font_override("font", _body_font)
	_section_tabs.add_color_override("font_color_fg", COLOR_WHITE)
	_section_tabs.add_color_override("font_color_bg", COLOR_TEXT_DIM)
	vb.add_child(_section_tabs)

	# TOOLS -- speed/frame-step/buffered-input controls (formerly their own
	# "Playback" tab) plus Perfect Jumpzone (formerly its own "Jumpzone" tab),
	# consolidated per the user's 2026-08-30 request: Macro Bot Mode is now
	# the only macro/checkpoint system this file has, so everything that
	# isn't specifically part of IT lives here instead of its own tab.
	var playback_page: = _add_tab_page(_section_tabs, "Tools")

	# FRAME RATE LIMIT (2026-09-01, added directly per the user's own
	# request -- see FPS_LIMIT_SETTINGS_PATH's big comment above for why:
	# OPEN INVESTIGATION NOTES item 1 has pointed at unstable render frame
	# timing as a likely contributor to real Divergence Diagnostics
	# residuals, and testing that theory needed an in-game way to cap the
	# frame rate that didn't exist until now). Same +/-/label pattern as
	# Perfect Jumpzone's interval/hold controls below.
	var fps_limit_row: = HBoxContainer.new()
	fps_limit_row.add_constant_override("separation", 10)
	fps_limit_row.add_child(_make_label("Frame Rate Limit:", _body_font, COLOR_TEXT_DIM))
	var fps_limit_minus: = _make_button("−", COLOR_BLUE, 54)
	fps_limit_minus.hint_tooltip = "Lower the render FPS limit."
	fps_limit_minus.connect("pressed", self, "_on_fps_limit_delta_pressed", [-FPS_LIMIT_STEP])
	fps_limit_row.add_child(fps_limit_minus)
	_fps_limit_label = _make_label(("%d FPS" % fps_limit) if fps_limit > 0 else "Uncapped", _header_font, COLOR_WHITE)
	_fps_limit_label.rect_min_size = Vector2(110, 0)
	_fps_limit_label.align = Label.ALIGN_CENTER
	_fps_limit_label.valign = Label.VALIGN_CENTER
	fps_limit_row.add_child(_fps_limit_label)
	var fps_limit_plus: = _make_button("+", COLOR_BLUE, 54)
	fps_limit_plus.hint_tooltip = "Raise the render FPS limit. 0 is uncapped."
	fps_limit_plus.connect("pressed", self, "_on_fps_limit_delta_pressed", [FPS_LIMIT_STEP])
	fps_limit_row.add_child(fps_limit_plus)
	playback_page.add_child(fps_limit_row)

	var visual_debug_row := HBoxContainer.new()
	visual_debug_row.add_constant_override("separation", 10)
	_hitbox_viewer_button = _make_button("◫ Hitbox Viewer: OFF", COLOR_BLUE, 250)
	_hitbox_viewer_button.hint_tooltip = "Show selected collision shapes."
	_hitbox_viewer_button.connect("pressed", self, "_on_toggle_hitbox_viewer_pressed")
	visual_debug_row.add_child(_hitbox_viewer_button)
	_trajectory_preview_button = _make_button("⌁ Trajectory Preview: OFF", COLOR_BLUE, 280)
	_trajectory_preview_button.hint_tooltip = "Preview the current ballistic path."
	_trajectory_preview_button.connect("pressed", self, "_on_toggle_trajectory_preview_pressed")
	visual_debug_row.add_child(_trajectory_preview_button)
	playback_page.add_child(visual_debug_row)
	_hitbox_category_row = HBoxContainer.new()
	_hitbox_category_row.add_constant_override("separation", 7)
	_hitbox_category_row.visible = _hitbox_viewer_enabled
	_hitbox_category_row.add_child(_make_label("Show:", _small_font, COLOR_TEXT_DIM))
	for entry in HITBOX_CATEGORIES:
		var category: String = entry[0]
		var category_button := _make_small_button(entry[1], COLOR_BLUE, 92)
		category_button.toggle_mode = true
		category_button.pressed = bool(_hitbox_categories.get(category, false))
		category_button.hint_tooltip = entry[2]
		category_button.connect("toggled", self, "_on_hitbox_category_toggled", [category])
		_hitbox_category_buttons[category] = category_button
		_hitbox_category_row.add_child(category_button)
	playback_page.add_child(_hitbox_category_row)
	_refresh_hitbox_category_ui()

	# INPUT DISPLAY (Phase 1.2) -- shows recorded/live input state in a small
	# overlay (TASInputDisplay.gd). Compact by default; Detailed adds a
	# LIVE/REPLAY tag, and Frame Holds adds a per-action held-tick counter.
	var input_display_row: = HBoxContainer.new()
	input_display_row.add_constant_override("separation", 10)
	_input_display_button = _make_button("⌨ Input Display: OFF", COLOR_BLUE, 250)
	_input_display_button.hint_tooltip = "Show a small overlay of recorded/live input state."
	_input_display_button.connect("pressed", self, "_on_toggle_input_display_pressed")
	input_display_row.add_child(_input_display_button)
	_input_display_detailed_button = _make_small_button("Compact", COLOR_BLUE, 90)
	_input_display_detailed_button.hint_tooltip = "Toggle between a compact and a detailed (LIVE/REPLAY tag) overlay."
	_input_display_detailed_button.connect("pressed", self, "_on_toggle_input_display_detailed_pressed")
	_input_display_detailed_button.visible = _input_display_enabled
	input_display_row.add_child(_input_display_detailed_button)
	_input_display_hold_frames_button = _make_small_button("Frame Holds: OFF", COLOR_BLUE, 130)
	_input_display_hold_frames_button.hint_tooltip = "Show how many ticks each held input has been down."
	_input_display_hold_frames_button.connect("pressed", self, "_on_toggle_input_display_hold_frames_pressed")
	_input_display_hold_frames_button.visible = _input_display_enabled
	input_display_row.add_child(_input_display_hold_frames_button)
	playback_page.add_child(input_display_row)

	var playback_row: = HBoxContainer.new()
	playback_row.add_constant_override("separation", 10)
	_play_stop_button = _make_button("■ STOP", COLOR_BLUE, 160)
	_play_stop_button.connect("pressed", self, "_toggle_pause")
	playback_row.add_child(_play_stop_button)
	var slower_btn: = _make_button("−", COLOR_BLUE, 54)
	slower_btn.connect("pressed", self, "_adjust_time_scale", [-TIME_SCALE_STEP])
	playback_row.add_child(slower_btn)
	_speed_label = _make_label("1.00x", _header_font, COLOR_WHITE)
	_speed_label.rect_min_size = Vector2(110, 0)
	_speed_label.align = Label.ALIGN_CENTER
	_speed_label.valign = Label.VALIGN_CENTER
	playback_row.add_child(_speed_label)
	var faster_btn: = _make_button("+", COLOR_BLUE, 54)
	faster_btn.connect("pressed", self, "_adjust_time_scale", [TIME_SCALE_STEP])
	playback_row.add_child(faster_btn)
	var reset_btn: = _make_button("Reset", COLOR_BLUE, 110)
	reset_btn.connect("pressed", self, "_on_reset_speed_pressed")
	playback_row.add_child(reset_btn)
	playback_page.add_child(playback_row)

	var step_row: = HBoxContainer.new()
	step_row.add_constant_override("separation", 10)
	_frame_step_checkbox = CheckBox.new()
	_frame_step_checkbox.text = "Frame-Step Mode"
	_frame_step_checkbox.pressed = enable_frame_step
	if _body_font != null:
		_frame_step_checkbox.add_font_override("font", _body_font)
	_frame_step_checkbox.add_color_override("font_color", COLOR_TEXT_DIM)
	_frame_step_checkbox.focus_mode = Control.FOCUS_NONE
	_frame_step_checkbox.connect("toggled", self, "_on_enable_frame_step_toggled")
	_frame_step_checkbox.hint_tooltip = "Pause physics and advance it manually."
	step_row.add_child(_frame_step_checkbox)
	_step_button = _make_button("Step ▸", COLOR_BLUE, 110)
	_step_button.disabled = not enable_frame_step
	_step_button.connect("pressed", self, "_request_frame_step")
	_step_button.hint_tooltip = "Advance the configured number of physics frames."
	step_row.add_child(_step_button)
	var step_config_btn: = _make_button("Configure", COLOR_BLUE, 140)
	step_config_btn.connect("pressed", self, "_on_toggle_step_config_pressed")
	step_row.add_child(step_config_btn)
	playback_page.add_child(step_row)

	_step_config_row = HBoxContainer.new()
	_step_config_row.add_constant_override("separation", 10)
	_step_config_row.visible = false
	_step_config_row.add_child(_make_label("Steps per press:", _body_font, COLOR_TEXT_DIM))
	var step_minus: = _make_button("−", COLOR_BLUE, 54)
	step_minus.connect("pressed", self, "_on_step_count_delta_pressed", [-1])
	_step_config_row.add_child(step_minus)
	_step_count_label = _make_label("%d" % frame_step_count, _header_font, COLOR_WHITE)
	_step_count_label.rect_min_size = Vector2(60, 0)
	_step_count_label.align = Label.ALIGN_CENTER
	_step_config_row.add_child(_step_count_label)
	var step_plus: = _make_button("+", COLOR_BLUE, 54)
	step_plus.connect("pressed", self, "_on_step_count_delta_pressed", [1])
	_step_config_row.add_child(step_plus)
	playback_page.add_child(_step_config_row)

	var buffered_label := _make_label("BUFFERED INPUTS", _small_font, COLOR_TEXT_DIM)
	buffered_label.hint_tooltip = "Armed actions stay held during the next frame step."
	playback_page.add_child(buffered_label)
	var buffer_row: = HBoxContainer.new()
	buffer_row.add_constant_override("separation", 8)
	for entry in BUFFERABLE_ACTIONS:
		var label: String = entry[0]
		var action: String = entry[1]
		var buf_btn: = _make_button(label, COLOR_BLUE, 0)
		buf_btn.hint_tooltip = "Hold %s during the next frame step." % label.capitalize()
		buf_btn.connect("pressed", self, "_on_toggle_buffered_action_pressed", [action])
		_buffer_action_buttons[action] = buf_btn
		buffer_row.add_child(buf_btn)
	playback_page.add_child(buffer_row)

	# PERFECT JUMPZONE -- folded into the same "Tools" page as the speed/
	# frame-step controls above (see the comment on playback_page's creation).
	var jumpzone_page: = playback_page
	jumpzone_page.add_child(HSeparator.new())
	var jumpzone_row: = HBoxContainer.new()
	jumpzone_row.add_constant_override("separation", 10)
	_jumpzone_button = _make_button("⤒ Perfect Jumpzone: OFF", COLOR_BLUE, 300)
	_jumpzone_button.hint_tooltip = "Repeat Jump using the configured rhythm."
	_jumpzone_button.connect("pressed", self, "_on_toggle_jumpzone_pressed")
	jumpzone_row.add_child(_jumpzone_button)
	var jumpzone_config_btn: = _make_button("Configure", COLOR_BLUE, 140)
	jumpzone_config_btn.connect("pressed", self, "_on_toggle_jumpzone_config_pressed")
	jumpzone_row.add_child(jumpzone_config_btn)
	jumpzone_page.add_child(jumpzone_row)

	_jumpzone_config_row = VBoxContainer.new()
	_jumpzone_config_row.add_constant_override("separation", 8)
	_jumpzone_config_row.visible = false

	var jz_interval_row: = HBoxContainer.new()
	jz_interval_row.add_constant_override("separation", 10)
	jz_interval_row.add_child(_make_label("Interval:", _body_font, COLOR_TEXT_DIM))
	var jz_interval_minus: = _make_button("−", COLOR_BLUE, 54)
	jz_interval_minus.connect("pressed", self, "_on_jumpzone_interval_delta_pressed", [-JUMPZONE_TIMING_STEP_MS])
	jz_interval_row.add_child(jz_interval_minus)
	_jumpzone_interval_label = _make_label("%.0fms" % jumpzone_interval_ms, _header_font, COLOR_WHITE)
	_jumpzone_interval_label.rect_min_size = Vector2(90, 0)
	_jumpzone_interval_label.align = Label.ALIGN_CENTER
	jz_interval_row.add_child(_jumpzone_interval_label)
	var jz_interval_plus: = _make_button("+", COLOR_BLUE, 54)
	jz_interval_plus.connect("pressed", self, "_on_jumpzone_interval_delta_pressed", [JUMPZONE_TIMING_STEP_MS])
	jz_interval_row.add_child(jz_interval_plus)
	_jumpzone_config_row.add_child(jz_interval_row)

	var jz_hold_row: = HBoxContainer.new()
	jz_hold_row.add_constant_override("separation", 10)
	jz_hold_row.add_child(_make_label("Hold time:", _body_font, COLOR_TEXT_DIM))
	var jz_hold_minus: = _make_button("−", COLOR_BLUE, 54)
	jz_hold_minus.connect("pressed", self, "_on_jumpzone_hold_delta_pressed", [-JUMPZONE_TIMING_STEP_MS])
	jz_hold_row.add_child(jz_hold_minus)
	_jumpzone_hold_label = _make_label("%.0fms" % jumpzone_hold_ms, _header_font, COLOR_WHITE)
	_jumpzone_hold_label.rect_min_size = Vector2(90, 0)
	_jumpzone_hold_label.align = Label.ALIGN_CENTER
	jz_hold_row.add_child(_jumpzone_hold_label)
	var jz_hold_plus: = _make_button("+", COLOR_BLUE, 54)
	jz_hold_plus.connect("pressed", self, "_on_jumpzone_hold_delta_pressed", [JUMPZONE_TIMING_STEP_MS])
	jz_hold_row.add_child(jz_hold_plus)
	_jumpzone_config_row.add_child(jz_hold_row)

	jumpzone_page.add_child(_jumpzone_config_row)

	# PRACTICE CHECKPOINTS
	var practice_page: = _add_tab_page(_section_tabs, "Macro Bot")

	var practice_row: = HBoxContainer.new()
	practice_row.add_constant_override("separation", 10)
	_practice_toggle_button = _make_button("▶ Start Macro Bot Mode", COLOR_BLUE, 300)
	_practice_toggle_button.hint_tooltip = "Record a run in checkpointed segments."
	_practice_toggle_button.connect("pressed", self, "_on_toggle_practice_pressed")
	practice_row.add_child(_practice_toggle_button)
	_practice_auto_respawn_button = _make_button("⟲ Auto-Respawn to Checkpoint: ON", COLOR_PINK, 320)
	_practice_auto_respawn_button.hint_tooltip = "Retry only the current segment after dying."
	_practice_auto_respawn_button.connect("pressed", self, "_on_toggle_practice_auto_respawn_pressed")
	practice_row.add_child(_practice_auto_respawn_button)
	practice_page.add_child(practice_row)

	var practice_auto_activate_row: = HBoxContainer.new()
	practice_auto_activate_row.add_constant_override("separation", 10)
	_practice_auto_activate_button = _make_button("Auto-Activate on Level Entry: OFF", COLOR_BLUE, 340)
	_practice_auto_activate_button.hint_tooltip = "Start recording when the player becomes controllable."
	_practice_auto_activate_button.connect("pressed", self, "_on_toggle_practice_auto_activate_pressed")
	practice_auto_activate_row.add_child(_practice_auto_activate_button)
	practice_page.add_child(practice_auto_activate_row)

	_debug_tools_container = VBoxContainer.new()
	_debug_tools_container.add_constant_override("separation", 4)
	_debug_tools_container.visible = _debug_mode_enabled
	practice_page.add_child(_debug_tools_container)
	var debug_heading := _make_label("DEBUG TOOLS", _small_font, COLOR_PINK)
	debug_heading.hint_tooltip = "Enable or disable this section in Goober Dash Settings."
	_debug_tools_container.add_child(debug_heading)

	var diag_row: = HBoxContainer.new()
	diag_row.add_constant_override("separation", 10)
	_diag_toggle_button = _make_button("Diagnostic Logging: OFF", COLOR_BLUE, 300)
	_diag_toggle_button.hint_tooltip = "Capture live and playback state for comparison."
	_diag_toggle_button.connect("pressed", self, "_on_toggle_diag_pressed")
	diag_row.add_child(_diag_toggle_button)
	_diag_compare_button = _make_button("Compare Live vs Replay", COLOR_BLUE, 260)
	_diag_compare_button.hint_tooltip = "Save a report for the first mismatch."
	_diag_compare_button.connect("pressed", self, "_on_compare_diagnostics_pressed")
	diag_row.add_child(_diag_compare_button)
	_debug_tools_container.add_child(diag_row)
	_diag_status_label = _make_label("no diagnostic data captured yet", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_diag_status_label)

	# Phase 0.1 -- Replay Determinism Check. Live readout, updated in
	# _update_overlay() while Play Macro is running -- see
	# _advance_replay_determinism_check() for where the numbers come from.
	_stop_on_desync_button = _make_button("Stop on Desync: OFF", COLOR_BLUE, 300)
	_stop_on_desync_button.hint_tooltip = "Automatically stop Play Macro the first time replay state diverges from the recorded run."
	_stop_on_desync_button.connect("pressed", self, "_on_toggle_stop_on_desync_pressed")
	_debug_tools_container.add_child(_stop_on_desync_button)
	_replay_check_status_label = _make_label("Replay Accuracy: --  |  First Desync: --  |  Largest Drift: --", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_replay_check_status_label)

	# Phase 0.2 -- Replay Self-Test. Repeats Play Macro N times and reports
	# PASS/FAIL per run using the Replay Determinism Check above -- see
	# _start_replay_self_test() / _on_replay_self_test_run_finished().
	var self_test_row: = HBoxContainer.new()
	self_test_row.add_constant_override("separation", 8)
	_self_test_x3_button = _make_small_button("Self-Test x3", COLOR_BLUE)
	_self_test_x3_button.connect("pressed", self, "_on_self_test_x3_pressed")
	self_test_row.add_child(_self_test_x3_button)
	_self_test_x5_button = _make_small_button("x5", COLOR_BLUE)
	_self_test_x5_button.connect("pressed", self, "_on_self_test_x5_pressed")
	self_test_row.add_child(_self_test_x5_button)
	_self_test_x10_button = _make_small_button("x10", COLOR_BLUE)
	_self_test_x10_button.connect("pressed", self, "_on_self_test_x10_pressed")
	self_test_row.add_child(_self_test_x10_button)
	_self_test_stop_on_failure_button = _make_small_button("Stop on Failure: OFF", COLOR_BLUE)
	_self_test_stop_on_failure_button.connect("pressed", self, "_on_toggle_self_test_stop_on_failure_pressed")
	self_test_row.add_child(_self_test_stop_on_failure_button)
	_debug_tools_container.add_child(self_test_row)
	_self_test_status_label = _make_label("Replay Self-Test: no runs yet", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_self_test_status_label)

	var restore_drift_row: = HBoxContainer.new()
	restore_drift_row.add_constant_override("separation", 10)
	_restore_drift_toggle_button = _make_button("Restore Drift Diagnostics: OFF", COLOR_BLUE, 300)
	_restore_drift_toggle_button.hint_tooltip = "Measure movement immediately after restores."
	_restore_drift_toggle_button.connect("pressed", self, "_on_toggle_restore_drift_pressed")
	restore_drift_row.add_child(_restore_drift_toggle_button)
	_restore_drift_save_button = _make_button("Save Restore Drift Report", COLOR_BLUE, 260)
	_restore_drift_save_button.hint_tooltip = "Save the captured restore measurements."
	_restore_drift_save_button.connect("pressed", self, "_on_save_restore_drift_report_pressed")
	restore_drift_row.add_child(_restore_drift_save_button)
	_debug_tools_container.add_child(restore_drift_row)
	_restore_drift_status_label = _make_label("no restore drift data captured yet", _small_font, COLOR_TEXT_DIM)
	_debug_tools_container.add_child(_restore_drift_status_label)

	var noclip_row: = HBoxContainer.new()
	noclip_row.add_constant_override("separation", 10)
	_noclip_toggle_button = _make_button("Debug Noclip: OFF", COLOR_BLUE, 300)
	_noclip_toggle_button.hint_tooltip = "Fly with Left/Right, Jump up and Dash down."
	_noclip_toggle_button.connect("pressed", self, "_on_toggle_noclip_pressed")
	noclip_row.add_child(_noclip_toggle_button)
	_debug_tools_container.add_child(noclip_row)

	_practice_status_label = _make_label("0 checkpoint(s) placed", _body_font, COLOR_TEXT_DIM)
	practice_page.add_child(_practice_status_label)

	var practice_action_row: = HBoxContainer.new()
	practice_action_row.add_constant_override("separation", 10)
	_practice_place_button = _make_button("Place Checkpoint", COLOR_BLUE, 220)
	_practice_place_button.hint_tooltip = "Commit the current segment and start the next one."
	_practice_place_button.disabled = true
	_practice_place_button.connect("pressed", self, "_on_place_practice_checkpoint_pressed")
	practice_action_row.add_child(_practice_place_button)
	_practice_undo_button = _make_button("↩ Undo Last", COLOR_BLUE, 170)
	_practice_undo_button.hint_tooltip = "Remove the most recent checkpoint and segment."
	_practice_undo_button.disabled = true
	_practice_undo_button.connect("pressed", self, "_on_undo_practice_checkpoint_pressed")
	practice_action_row.add_child(_practice_undo_button)
	_practice_clear_button = _make_button("✕ Clear", COLOR_PINK_DARK, 130)
	_practice_clear_button.hint_tooltip = "Clear the current unsaved Macro Bot run."
	_practice_clear_button.disabled = true
	_practice_clear_button.connect("pressed", self, "_on_clear_practice_pressed")
	practice_action_row.add_child(_practice_clear_button)
	practice_page.add_child(practice_action_row)

	var practice_play_row: = HBoxContainer.new()
	practice_play_row.add_constant_override("separation", 10)
	_practice_play_button = _make_button("▶ Play Macro (stitched)", COLOR_BLUE, 260)
	_practice_play_button.hint_tooltip = "Play the current checkpointed macro."
	_practice_play_button.disabled = true
	_practice_play_button.connect("pressed", self, "_on_play_practice_macro_pressed")
	practice_play_row.add_child(_practice_play_button)
	var edit_current_button := _make_button("▤ Edit Current Timeline", COLOR_PURPLE, 250)
	edit_current_button.hint_tooltip = "Open the detailed frame timeline."
	edit_current_button.connect("pressed", self, "_on_edit_current_practice_macro_pressed")
	practice_play_row.add_child(edit_current_button)
	practice_page.add_child(practice_play_row)
	var polish_row := HBoxContainer.new()
	polish_row.add_constant_override("separation", 10)
	_visual_seam_polish_button = _make_button("◇ Visual Seam Polish: OFF", COLOR_BLUE, 300)
	_visual_seam_polish_button.hint_tooltip = "Smooth render-only checkpoint corrections. Use safe checkpoint areas."
	_visual_seam_polish_button.connect("pressed", self, "_on_toggle_visual_seam_polish_pressed")
	polish_row.add_child(_visual_seam_polish_button)
	_sync_moving_objects_button = _make_button("↻ Moving Object Sync: OFF", COLOR_BLUE, 300)
	_sync_moving_objects_button.hint_tooltip = "Capture moving platforms/hazards at checkpoints for local playback."
	_sync_moving_objects_button.connect("pressed", self, "_on_toggle_sync_moving_objects_pressed")
	polish_row.add_child(_sync_moving_objects_button)
	practice_page.add_child(polish_row)

	var slots_heading := HBoxContainer.new()
	slots_heading.add_child(_make_label("MACRO SLOTS", _body_font, COLOR_TEXT_DIM))
	var slots_heading_spacer := Control.new()
	slots_heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_heading.add_child(slots_heading_spacer)
	var add_slot_button := _make_button("＋ CREATE MACRO SLOT", COLOR_PLAY_GREEN, 230)
	add_slot_button.hint_tooltip = "Add another persistent macro slot."
	add_slot_button.connect("pressed", self, "_on_add_practice_macro_slot_pressed")
	slots_heading.add_child(add_slot_button)
	var remove_slot_button := _make_button("− REMOVE LAST EMPTY", COLOR_BLUE, 220)
	remove_slot_button.hint_tooltip = "Remove the final slot if it is empty."
	remove_slot_button.connect("pressed", self, "_on_remove_last_practice_macro_slot_pressed")
	slots_heading.add_child(remove_slot_button)
	practice_page.add_child(slots_heading)
	_practice_macro_grid = GridContainer.new()
	_practice_macro_grid.columns = 3
	_practice_macro_grid.add_constant_override("hseparation", 10)
	_practice_macro_grid.add_constant_override("vseparation", 10)
	_practice_macro_slot_status_labels = [null]
	_practice_macro_slot_play_buttons = [null]
	_practice_macro_slot_load_buttons = [null]
	_practice_macro_slot_delete_buttons = [null]
	_practice_macro_slot_edit_buttons = [null]
	_practice_macro_slot_cards = [null]
	for i in range(1, _practice_macro_slot_count + 1):
		var mcard: = _build_practice_macro_slot_card(i)
		_practice_macro_slot_cards.append(mcard)
		_practice_macro_grid.add_child(mcard)
	practice_page.add_child(_practice_macro_grid)
	for i in range(1, _practice_macro_slot_count + 1):
		_refresh_practice_macro_slot_ui(i)
	var resize_row := HBoxContainer.new()
	var resize_spacer := Control.new()
	resize_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resize_row.add_child(resize_spacer)
	resize_row.add_child(_make_resize_handle("menu"))
	vb.add_child(resize_row)


func _build_practice_macro_slot_card(slot: int) -> PanelContainer:
	var card: = PanelContainer.new()
	card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, COLOR_WHITE, 3, 16))
	card.rect_min_size = Vector2(220, 184)

	var vb: = VBoxContainer.new()
	vb.add_constant_override("separation", 3)
	card.add_child(vb)

	vb.add_child(_make_label("MACRO %d" % slot, _body_font, COLOR_WHITE))
	var status_label: = _make_label("Empty", _body_font, COLOR_TEXT_DIM)
	vb.add_child(status_label)
	_practice_macro_slot_status_labels.append(status_label)

	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	var save_btn: = _make_button("Save", COLOR_BLUE, 58)
	save_btn.rect_min_size.y = 42
	save_btn.connect("pressed", self, "_on_save_practice_macro_slot_pressed", [slot])
	row.add_child(save_btn)
	var load_btn: = _make_button("Load", COLOR_BLUE, 58)
	load_btn.rect_min_size.y = 42
	load_btn.disabled = true
	load_btn.connect("pressed", self, "_on_load_practice_macro_slot_pressed", [slot])
	row.add_child(load_btn)
	_practice_macro_slot_load_buttons.append(load_btn)
	var delete_btn: = _make_button("✕", COLOR_PINK_DARK, 46)
	delete_btn.rect_min_size.y = 42
	delete_btn.disabled = true
	delete_btn.connect("pressed", self, "_on_delete_practice_macro_slot_pressed", [slot])
	row.add_child(delete_btn)
	_practice_macro_slot_delete_buttons.append(delete_btn)
	vb.add_child(row)
	var edit_btn: = _make_button("EDIT TIMELINE", COLOR_PURPLE, 0)
	edit_btn.rect_min_size.y = 42
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.disabled = true
	edit_btn.hint_tooltip = "Open the detailed frame/input timeline editor"
	edit_btn.connect("pressed", self, "_on_edit_practice_macro_slot_pressed", [slot])
	vb.add_child(edit_btn)
	_practice_macro_slot_edit_buttons.append(edit_btn)

	# A separate full-width launch action keeps the destructive delete icon
	# away from Play and gives the requested one-click workflow a clear visual
	# hierarchy. Reuse Goober Dash's own white play asset so it fits the game's
	# visual language instead of introducing an unrelated icon style.
	var play_btn: = _make_button("PLAY LEVEL", COLOR_PLAY_GREEN, 0)
	var play_icon = load("res://project_specific/gfx/icons/icon_play.png")
	if play_icon != null:
		play_btn.icon = play_icon
		play_btn.expand_icon = true
	else:
		play_btn.text = "▶  PLAY LEVEL"
	play_btn.rect_min_size.y = 44
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.disabled = true
	play_btn.hint_tooltip = "Open this macro's saved level and start playback automatically"
	play_btn.connect("pressed", self, "_on_play_saved_practice_macro_slot_pressed", [slot])
	vb.add_child(play_btn)
	_practice_macro_slot_play_buttons.append(play_btn)

	return card


func _build_log_window() -> void:
	_log_window = VBoxContainer.new()
	_log_window.add_constant_override("separation", 10)
	_log_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_log_window)

	_log_tab_row = HBoxContainer.new()
	_log_tab_row.add_constant_override("separation", 6)
	_log_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_tab_row.add_child(_make_drag_handle("log"))

	_log_tab_button = Button.new()
	_log_tab_button.text = _log_tab_text()
	_style_button(_log_tab_button, COLOR_PANEL_BG, 999, 4)
	if _header_font != null:
		_log_tab_button.add_font_override("font", _header_font)
	_log_tab_button.rect_min_size = TAB_SIZE
	_log_tab_button.align = Button.ALIGN_CENTER
	_log_tab_button.focus_mode = Control.FOCUS_NONE # see _make_button -- keeps Space free for the game
	_log_tab_button.connect("pressed", self, "_on_log_tab_pressed")
	_log_tab_row.add_child(_log_tab_button)
	_log_window.add_child(_log_tab_row)

	_log_panel = PanelContainer.new()
	_log_panel.add_stylebox_override("panel", _make_flat_style(Color(COLOR_PANEL_BG.r, COLOR_PANEL_BG.g, COLOR_PANEL_BG.b, menu_background_opacity), COLOR_PANEL_BORDER, 3, 26))
	_log_panel.rect_min_size = Vector2(LOG_PANEL_MIN_W, 0)
	_log_window.add_child(_log_panel)

	var vb: = VBoxContainer.new()
	vb.add_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_panel.add_child(vb)

	var header_row: = HBoxContainer.new()
	var log_heading := _make_label("ACTION LOG", _title_font, COLOR_BLUE)
	log_heading.hint_tooltip = "Tool actions appear here. Entries can be undone or cleared."
	header_row.add_child(log_heading)
	var spacer: = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var clear_btn: = _make_small_button("Clear Log", COLOR_BLUE, 130)
	clear_btn.connect("pressed", self, "_on_clear_log_pressed")
	header_row.add_child(clear_btn)
	vb.add_child(header_row)

	_log_scroll = ScrollContainer.new()
	_log_scroll.rect_min_size = Vector2(0, 320)
	_log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_log_scroll)

	_log_list_vbox = VBoxContainer.new()
	_log_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list_vbox.add_constant_override("separation", 4)
	_log_scroll.add_child(_log_list_vbox)
	var resize_row := HBoxContainer.new()
	var resize_spacer := Control.new()
	resize_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resize_row.add_child(resize_spacer)
	resize_row.add_child(_make_resize_handle("log"))
	vb.add_child(resize_row)


func _add_log_row(entry: Dictionary) -> void:
	var row: = PanelContainer.new()
	row.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, Color(1, 1, 1, 0.25), 2, 10))

	var hb: = HBoxContainer.new()
	hb.add_constant_override("separation", 10)
	row.add_child(hb)

	var time_label: = _make_label(entry["time"], _small_font, COLOR_TEXT_DIM)
	time_label.rect_min_size = Vector2(80, 0)
	hb.add_child(time_label)

	var text_label: = _make_label(entry["text"], _small_font, COLOR_WHITE)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.autowrap = true
	hb.add_child(text_label)

	var undo_btn: = _make_small_button("Undo", COLOR_BLUE, 90)
	undo_btn.disabled = (entry["undo"] == null)
	undo_btn.connect("pressed", self, "_on_undo_pressed", [entry])
	hb.add_child(undo_btn)

	var del_btn: = _make_small_button("✕", COLOR_PINK_DARK, 46)
	del_btn.connect("pressed", self, "_on_log_delete_pressed", [entry])
	hb.add_child(del_btn)

	entry["row"] = row
	_log_list_vbox.add_child(row)


func _set_status(msg: String) -> void:
	_status_message = msg
	_status_message_timer = 2.5
	print("[TASTool] %s" % msg)


func _update_overlay() -> void:
	if _tab_button == null:
		return
	if not _tas_gui_enabled:
		return

	# F1-hidden: the whole overlay CanvasLayer is already invisible (and
	# therefore free to render), so there's nothing on screen for any of
	# the below to usefully update -- skip the work entirely. Everything
	# picks back up correctly the moment it's shown again, since every
	# update below is itself guarded by an actual-value comparison rather
	# than assuming what state the UI was last left in.
	if _overlay_hidden:
		return

	if not enabled:
		# Fully disabled means fully out of the way -- hide the tab bars
		# themselves too, not just the dropdown panels, so there's nothing
		# left sitting over the game (or another menu) blocking clicks.
		_tab_row.visible = false
		_log_tab_row.visible = false
		_menu_panel.visible = false
		_toast_pill.modulate.a = 0.0
		return

	_tab_row.visible = true
	_log_tab_row.visible = _debug_mode_enabled
	if not _debug_mode_enabled:
		_log_panel.visible = false

	# The diagnostic is useful while the panel is open, but rewriting a Label
	# every rendered frame invalidates the surrounding Container layout. On an
	# uncapped main menu that can happen hundreds of times per second even while
	# the whole panel is closed. Sample it at 4 Hz, only while visible, and only
	# assign when its text actually changed; this measures FPS without lowering
	# or capping it.
	if _diag_label != null and _debug_mode_enabled and _menu_open:
		var now_msec: = OS.get_ticks_msec()
		if now_msec >= _ui_next_diag_refresh_msec:
			_ui_next_diag_refresh_msec = now_msec + DIAGNOSTIC_UI_REFRESH_MSEC
			var diag_text: = "FPS %d | Nodes %d | Log %d | Seg %d | Play %d/%d" % [Engine.get_frames_per_second(), get_tree().get_node_count(), _log_entries.size(), _practice_current_segment.size(), _practice_playback_index, _practice_playback_frames.size()]
			if _ui_last_diag_text != diag_text:
				_ui_last_diag_text = diag_text
				_diag_label.text = diag_text

	# Every .text/.disabled/stylebox write below is gated on the displayed
	# value actually having changed -- reassigning them unconditionally
	# every idle frame (60/sec) was the real source of the lag reported
	# once the menu grew: Label/Button property writes invalidate that
	# Control's layout and force a container re-sort even when the new
	# value is identical to the old one, and that cost scales with how
	# many Controls are now in the tree.
	var tab_text: = _tab_text()
	if _ui_last_tab_text != tab_text:
		_ui_last_tab_text = tab_text
		_tab_button.text = tab_text
	var log_tab_text: = _log_tab_text()
	if _ui_last_log_tab_text != log_tab_text:
		_ui_last_log_tab_text = log_tab_text
		_log_tab_button.text = log_tab_text

	if _tool_restricted():
		_menu_panel.visible = _menu_open
		_inactive_label.visible = true
		_section_tabs.visible = false
		_toast_pill.modulate.a = 0.0
		return

	_menu_panel.visible = _menu_open
	_inactive_label.visible = false
	_section_tabs.visible = true

	if _ui_last_paused != _is_paused:
		_ui_last_paused = _is_paused
		if _is_paused:
			_play_stop_button.text = "▶ PLAY"
			_style_button(_play_stop_button, COLOR_PINK)
		else:
			_play_stop_button.text = "■ STOP"
			_style_button(_play_stop_button, COLOR_BLUE)

	var speed: float = _saved_time_scale if _is_paused else Engine.time_scale
	var speed_text: = "%.2fx" % speed
	if _ui_last_speed_text != speed_text:
		_ui_last_speed_text = speed_text
		_speed_label.text = speed_text

	var step_disabled: = not enable_frame_step
	if _ui_last_step_disabled != step_disabled:
		_ui_last_step_disabled = step_disabled
		_step_button.disabled = step_disabled

	# Macro Bot Mode's live status line -- the underlying numbers are
	# updated every physics frame by _physics_process()/_advance_practice_
	# playback(), but the Label itself is only ever touched here, once per
	# idle frame, and only when the text actually changed.
	if _practice_status_label != null:
		var practice_text: String
		if _practice_playback:
			practice_text = "Playing back... (%d/%d frames)" % [_practice_playback_index, _practice_playback_frames.size()]
		elif _practice_active:
			practice_text = "%d checkpoint(s) -- segment: %d frame(s), %d death(s)" % [max(_practice_checkpoints.size() - 1, 0), _practice_current_segment.size(), _practice_deaths_this_segment]
		else:
			practice_text = "%d checkpoint(s) placed" % [max(_practice_checkpoints.size() - 1, 0)]
		if _ui_last_practice_status != practice_text:
			_ui_last_practice_status = practice_text
			_practice_status_label.text = practice_text

	# Phase 0.1 -- Replay Determinism Check's live readout. Same "recompute
	# every idle frame, only assign on change" pattern as the practice status
	# line just above; the underlying counters are updated every physics
	# tick by _advance_replay_determinism_check().
	if _replay_check_status_label != null and _debug_mode_enabled:
		var replay_check_text: String
		if _replay_check_compared_ticks <= 0:
			if _practice_playback and _replay_check_safe_ticks <= 0:
				replay_check_text = "Replay Accuracy: NO DATA  |  Record with Debug Mode enabled"
			else:
				replay_check_text = "Replay Accuracy: --  |  First Desync: --  |  Largest Drift: --"
		else:
			var accuracy: float = 100.0 * float(_replay_check_matched_ticks) / float(_replay_check_compared_ticks)
			var desync_text: String = ("tick %d · %s/%s" % [_replay_check_first_desync_tick, _replay_check_first_desync_category, _replay_check_first_desync_field]) if _replay_check_first_desync_tick >= 0 else "none"
			replay_check_text = "Replay Accuracy: %.1f%%  |  First Desync: %s  |  Largest Drift: %.3f units" % [accuracy, desync_text, _replay_check_largest_drift]
		if _ui_last_replay_check_status != replay_check_text:
			_ui_last_replay_check_status = replay_check_text
			_replay_check_status_label.text = replay_check_text

	if not _status_message.empty():
		_toast_pill.modulate.a = 1.0
		_toast_pill.get_meta("label").text = _status_message
	else:
		_toast_pill.modulate.a = 0.0


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
