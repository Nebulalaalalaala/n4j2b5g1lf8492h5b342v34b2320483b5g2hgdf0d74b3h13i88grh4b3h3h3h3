extends "user://mod/core/TASTool/02_placeholders.gd"

func _ready() -> void:
	var moved_data = load(ModPaths.path("DataMigration.gd")).run()
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
	# can_instance() is false when a script failed to compile. Without it a
	# single broken optional module takes the ENTIRE tool down: load() still
	# hands back a GDScript object, .new() then fails, and the exception
	# aborts the rest of _ready() -- so no overlay, no menu, no GUI at all,
	# even though the other modules were fine. Guarding each one means a bad
	# module is simply skipped and everything else still comes up.
	var window_geometry_script = ModPaths.try_load(WINDOW_GEOMETRY_SCRIPT_PATH)
	if window_geometry_script != null and window_geometry_script.can_instance():
		_window_geometry = window_geometry_script.new()
	var first_launch := _check_first_launch()
	_load_client_tool_preferences()
	call_deferred("_start_onboarding", first_launch == "new")
	_load_gui_layout_store()
	_load_practice_macro_slots_from_disk()
	var updater_script = ModPaths.try_load(UPDATER_SCRIPT_PATH)
	if updater_script != null and updater_script.can_instance():
		_updater = updater_script.new()
		add_child(_updater)
		_updater.connect("status_changed", self, "_on_updater_status_changed")
		_updater.connect("latest_version_changed", self, "_on_updater_latest_version_changed")
		_updater.connect("update_available", self, "_on_updater_update_available")
		_updater.connect("update_installed", self, "_on_updater_update_installed")
		_updater.connect("rollback_changed", self, "_on_updater_rollback_changed")
		_updater.call_deferred("configure", GOOBPLAYABILITY_VERSION, _update_checks_enabled)
	var post_guard_script = ModPaths.try_load(POST_PHYSICS_GUARD_SCRIPT_PATH)
	if post_guard_script != null and post_guard_script.can_instance():
		_post_physics_guard = post_guard_script.new()
		_post_physics_guard.set("tas_tool", self)
		add_child(_post_physics_guard)
	var cosmetic_sandbox_script = ModPaths.try_load(COSMETIC_SANDBOX_SCRIPT_PATH)
	if cosmetic_sandbox_script != null and cosmetic_sandbox_script.can_instance():
		_cosmetic_sandbox = cosmetic_sandbox_script.new()
		add_child(_cosmetic_sandbox)
		if _cosmetic_sandbox.has_method("configure"):
			_cosmetic_sandbox.call("configure", self)
		if _cosmetic_sandbox.has_method("set_gui_enabled"):
			_cosmetic_sandbox.call("set_gui_enabled", _sandbox_gui_enabled)
	var world_overlay_script = ModPaths.try_load(WORLD_OVERLAY_SCRIPT_PATH)
	if world_overlay_script != null and world_overlay_script.can_instance():
		_world_overlay = world_overlay_script.new()
		add_child(_world_overlay)
		_world_overlay.call("configure", self)
		for category in _hitbox_categories.keys():
			_world_overlay.call("set_hitbox_category", category, bool(_hitbox_categories[category]))
		_world_overlay.call("set_show_hitboxes", _hitbox_viewer_enabled)
		_world_overlay.call("set_show_trajectory", _trajectory_preview_enabled)
	var input_display_script = ModPaths.try_load(INPUT_DISPLAY_SCRIPT_PATH)
	if input_display_script != null and input_display_script.can_instance():
		_input_display = input_display_script.new()
		add_child(_input_display)
		_input_display.call("configure", self)
		_input_display.call("set_display_enabled", _input_display_enabled)
		_input_display.call("set_detailed", _input_display_detailed)
		_input_display.call("set_show_hold_frames", _input_display_hold_frames)
	var macro_editor_script = ModPaths.try_load(MACRO_EDITOR_SCRIPT_PATH)
	if macro_editor_script != null and macro_editor_script.can_instance():
		_macro_editor = macro_editor_script.new()
		add_child(_macro_editor)
		_macro_editor.call("configure", self)
		if _macro_editor.has_signal("editor_closed"):
			_macro_editor.connect("editor_closed", self, "_update_mouse_capture")
	var autoplay_bot_script = ModPaths.try_load(AUTOPLAY_BOT_SCRIPT_PATH)
	if autoplay_bot_script != null and autoplay_bot_script.can_instance():
		_autoplay_bot = autoplay_bot_script.new()
		add_child(_autoplay_bot)
		_autoplay_bot.call("configure", self)
	var replay_hub_script = ModPaths.try_load(REPLAY_HUB_SCRIPT_PATH)
	if replay_hub_script != null and replay_hub_script.can_instance():
		_replay_hub = replay_hub_script.new()
		add_child(_replay_hub)
		if _replay_hub.has_method("configure"):
			_replay_hub.call("configure", self)
		if _replay_hub.has_method("set_gui_enabled"):
			_replay_hub.call("set_gui_enabled", _replay_hub_gui_enabled)
	var game_tools_script = ModPaths.try_load(GAME_TOOLS_SCRIPT_PATH)
	if game_tools_script != null and game_tools_script.can_instance():
		_game_tools = game_tools_script.new()
		add_child(_game_tools)
		if _game_tools.has_method("configure"):
			_game_tools.call("configure", self)
		if _game_tools.has_method("set_gui_enabled"):
			_game_tools.call("set_gui_enabled", _game_tools_gui_enabled)
	var social_hub_script = ModPaths.try_load(SOCIAL_HUB_SCRIPT_PATH)
	if social_hub_script != null and social_hub_script.can_instance():
		_social_hub = social_hub_script.new()
		add_child(_social_hub)
		if _social_hub.has_method("configure"):
			_social_hub.call("configure", self)
		if _social_hub.has_method("set_gui_enabled"):
			_social_hub.call("set_gui_enabled", _social_hub_gui_enabled)
	var cosmetic_loadouts_script = ModPaths.try_load(COSMETIC_LOADOUTS_SCRIPT_PATH)
	if cosmetic_loadouts_script != null and cosmetic_loadouts_script.can_instance():
		_cosmetic_loadouts = cosmetic_loadouts_script.new()
		add_child(_cosmetic_loadouts)
		if _cosmetic_loadouts.has_method("configure"):
			_cosmetic_loadouts.call("configure", self)
		if _cosmetic_loadouts.has_method("set_gui_enabled"):
			_cosmetic_loadouts.call("set_gui_enabled", _cosmetic_loadouts_gui_enabled)
	var editor_theme_pack_script = ModPaths.try_load(EDITOR_THEME_PACK_SCRIPT_PATH)
	if editor_theme_pack_script != null and editor_theme_pack_script.can_instance():
		_editor_theme_pack = editor_theme_pack_script.new()
		add_child(_editor_theme_pack)
		if _editor_theme_pack.has_method("configure"):
			_editor_theme_pack.call("configure", self)
		if _editor_theme_pack.has_method("set_gui_enabled"):
			_editor_theme_pack.call("set_gui_enabled", _editor_theme_pack_enabled)
	var match_map_preview_script = ModPaths.try_load(MATCH_MAP_PREVIEW_SCRIPT_PATH)
	if match_map_preview_script != null and match_map_preview_script.can_instance():
		_match_map_preview = match_map_preview_script.new()
		add_child(_match_map_preview)
		if _match_map_preview.has_method("configure"):
			_match_map_preview.call("configure", self)
		if _match_map_preview.has_method("set_gui_enabled"):
			_match_map_preview.call("set_gui_enabled", _match_map_preview_enabled)
	var wins_leaderboard_script = ModPaths.try_load(WINS_LEADERBOARD_SCRIPT_PATH)
	if wins_leaderboard_script != null and wins_leaderboard_script.can_instance():
		_wins_leaderboard = wins_leaderboard_script.new()
		add_child(_wins_leaderboard)
		if _wins_leaderboard.has_method("configure"):
			_wins_leaderboard.call("configure", self)
		if _wins_leaderboard.has_method("set_gui_enabled"):
			_wins_leaderboard.call("set_gui_enabled", _wins_leaderboard_enabled)
	_build_overlay()
	_apply_ui_scale()
	_load_debug_mode_from_disk()
	_load_fps_limit_from_disk()
	_apply_menu_open_state()
	_apply_log_open_state()
	_apply_tas_gui_visibility()
	# The menu stays hidden until F1; hitboxes and other world overlays still show.
	_toggle_overlay_hidden()
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.visible = true
	_refresh_practice_ui() # picks up the just-loaded Debug Mode state on the buttons built in _build_overlay() above
	call_deferred("_initialize_main_gui_layout")
	call_deferred("_show_changelog_if_needed")
	# Deferred so _cosmetic_sandbox/_macro_editor (created further above in
	# this same _ready(), after _build_overlay()) both already exist by the
	# time this runs.
	call_deferred("_apply_claude_experimental_icons")


# ----------------------------------------------------------------------
#  Main loop
# ----------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _macro_hotkeys_allowed():
		_prev_key_state[KEY_PLACE_CHECKPOINT] = Input.is_key_pressed(KEY_PLACE_CHECKPOINT)
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
	if not _ping_optimizer_enabled or _macro_editor_preview_active:
		call_deferred("_force_dynamic_object_visibility_late", _find_game())

	if _status_message_timer > 0.0:
		_status_message_timer -= delta
		if _status_message_timer <= 0.0:
			_status_message = ""
	if _autoplay_bot != null and is_instance_valid(_autoplay_bot):
		_autoplay_bot.call("on_tool_gate", enabled)

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

	if _macro_editor_preview_active:
		_update_overlay()
		return
	if _tool_restricted():
		_release_all_injected_actions()
		_update_overlay()
		return
	# Autoplay owns movement while it is training or replaying. Keep the
	# ordinary TAS hotkeys and timed jump injector from layering human/tool
	# inputs over a learning attempt.
	if _autoplay_bot != null and is_instance_valid(_autoplay_bot) and bool(_autoplay_bot.call("is_active")):
		_update_overlay()
		return

	_process_frame_step_watch()
	_handle_speed_hotkeys()
	_handle_macro_bot_hotkeys()
	_watch_practice_auto_activate()
	_watch_jumpzone(delta)

	_update_overlay()
