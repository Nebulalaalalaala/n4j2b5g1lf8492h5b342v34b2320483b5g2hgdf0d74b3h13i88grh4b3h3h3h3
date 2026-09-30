extends "user://mod/core/TASTool/01_state_2.gd"

# Placeholders for functions that live in another file of the TASTool chain. Earlier files and core
# can call them; when the tool that defines one is installed, the real function replaces it at runtime.
# When that tool is not installed, the placeholder runs instead (does nothing, returns an empty value).

func _advance_practice_playback() -> void:
	pass

func _advance_restore_drift_watches() -> void:
	pass

func _apply_claude_experimental_icons() -> void:
	pass

func _apply_log_open_state() -> void:
	pass

func _apply_menu_open_state() -> void:
	pass

func _apply_noclip_movement(delta: float) -> void:
	pass

func _apply_practice_playback_computed_horizontal_velocity(player: WPPlayer, at_fresh_boundary: bool) -> void:
	pass

func _apply_tas_gui_visibility() -> void:
	pass

func _apply_ui_scale() -> void:
	pass

func _apply_undo(undo: Dictionary) -> void:
	pass

func _arm_restore_drift_watch(p: WPPlayer, snap: Dictionary, velocity_before_reset_object: Vector2 = Vector2.ZERO, velocity_after_reset_object: Vector2 = Vector2.ZERO, reset_object_called: bool = true) -> void:
	pass

func _auto_generate_playback_reports() -> void:
	pass

func _begin_visual_seam_blend(from_position: Vector2, to_position: Vector2) -> void:
	pass

func _build_macro_bot_page(practice_page: VBoxContainer) -> void:
	pass

func _build_overlay() -> void:
	pass

func _build_practice_macro_slot_card(slot: int) -> PanelContainer:
	return null

func _build_practice_playback_frames() -> void:
	pass

func _build_tools_page(playback_page: VBoxContainer) -> void:
	pass

func _cap_flat_log(flat: Array, limit: int) -> Array:
	return []

func _capture_diag_entry(p: WPPlayer, g: WPGame, frame: Dictionary) -> Dictionary:
	return {}

func _capture_playback_visual_sample() -> void:
	pass

func _capture_practice_native_frame(player: WPPlayer) -> void:
	pass

func _clear_practice_data() -> void:
	pass

func _collect_macro_editor_timers(node: Node, result: Array) -> void:
	pass

func _connect_game_over_submission_guard(game: WPGame) -> void:
	pass

func _continue_macro_editor_data(data: Dictionary, frame_index: int, auto_resume := false) -> bool:
	return false

func _death_diag_after_freeze() -> void:
	pass

func _death_diag_before_gate() -> void:
	pass

func _diag_coverage_prefix_ticks() -> int:
	return 0

func _diag_field_matches(field: String, live_val, replay_val) -> bool:
	return false

func _end_macro_editor_preview() -> void:
	pass

func _ensure_practice_native_tick_hooks(game: WPGame) -> bool:
	return false

func _finalize_practice_recording_at_finish(player: WPPlayer) -> void:
	pass

func _find_game() -> WPGame:
	return null

func _find_playback_camera() -> Camera2D:
	return null

func _find_player_renderer(player: WPPlayer) -> Node:
	return null

func _flatten_diag_live() -> Array:
	return []

func _format_time() -> String:
	return ""

func _get_local_player() -> WPPlayer:
	return null

func _handle_macro_bot_hotkeys() -> void:
	pass

func _handle_speed_hotkeys() -> void:
	pass

func _initialize_game_discovery() -> void:
	pass

func _inject_action(action: String, pressed: bool) -> void:
	pass

func _inputs_differ(live_input: Dictionary, replay_input: Dictionary) -> bool:
	return false

func _install_editor_data_as_current(data: Dictionary) -> bool:
	return false

func _is_game_candidate(node: Node) -> bool:
	return false

func _is_normal_linked_time_trial_scene(scene: Node) -> bool:
	return false

func _is_recording() -> bool:
	return false

func _just_pressed(keycode: int) -> bool:
	return false

func _load_claude_icon(icon_name: String, size: int = 40) -> Texture:
	return null

func _load_client_tool_preferences() -> void:
	pass

func _load_debug_mode_from_disk() -> void:
	pass

func _load_fps_limit_from_disk() -> void:
	pass

func _load_gui_layout_store() -> void:
	pass

func _load_practice_macro_slots_from_disk() -> void:
	pass

func _log_action(text: String, undo_data) -> void:
	pass

func _log_tab_text() -> String:
	return ""

func _macro_editor_level_visuals_ready(game: Node) -> bool:
	return false

func _macro_editor_visual_signature(game: Node) -> String:
	return ""

func _macro_hotkeys_allowed() -> bool:
	return false

func _macro_level_is_current(data: Dictionary) -> bool:
	return false

func _maintain_terrain_fallback_rendering(game: WPGame) -> void:
	pass

func _make_button(text: String, bg: Color, min_w: int = 0) -> Button:
	return null

func _make_drag_handle(which: String) -> PanelContainer:
	return null

func _make_flat_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	return null

func _make_font(size: int) -> DynamicFont:
	return null

func _make_label(text: String, font: DynamicFont, color: Color) -> Label:
	return null

func _make_resize_handle(which: String) -> Button:
	return null

func _make_small_button(text: String, bg: Color, min_w: int = 0) -> Button:
	return null

func _mark_tas_timer_labels(pill) -> void:
	pass

func _modern_theme_active() -> bool:
	return false

func _moving_phase_shift(game: WPGame) -> float:
	return 0.0

func _on_play_practice_macro_pressed() -> void:
	pass

func _on_replay_self_test_run_finished(passed: bool, fail_frame: int) -> void:
	pass

func _on_toggle_noclip_pressed() -> void:
	pass

func _open_card(parent: VBoxContainer, title: String) -> VBoxContainer:
	return null

func _post_native_death_momentum_guard() -> void:
	pass

func _practice_playback_movement_value(frame: Dictionary) -> float:
	return 0.0

func _practice_playback_uses_native_clock() -> bool:
	return false

func _practice_recorded_frame_count() -> int:
	return 0

func _process_frame_step_watch() -> void:
	pass

func _recover_authoritative_playback_death(p: WPPlayer) -> bool:
	return false

func _refresh_hitbox_category_ui() -> void:
	pass

func _refresh_practice_ui() -> void:
	pass

func _release_all_injected_actions() -> void:
	pass

func _reset_playback_visual_track() -> void:
	pass

func _reset_renderer_smoothing(player: WPPlayer) -> void:
	pass

func _restore_main_window_layout(which: String) -> void:
	pass

func _restore_player(p: WPPlayer, snap: Dictionary) -> void:
	pass

func _restyle_practice_markers() -> void:
	pass

func _save_main_window_layout(which: String) -> void:
	pass

func _set_cached_game(game: WPGame) -> void:
	pass

func _set_claude_icon_slot(rect: TextureRect, icon_name: String, size: int) -> void:
	pass

func _set_debug_mode_enabled(value: bool) -> void:
	pass

func _set_status(msg: String) -> void:
	pass

func _set_stop_on_desync_enabled(value: bool) -> void:
	pass

func _show_responsive_popup(title: String, message: String, accept_text := "OK", accept_method := "_close_tool_popup", cancel_text := "", extra_text := "", extra_method := "") -> void:
	pass

func _snap_playback_visual_track(player: WPPlayer) -> void:
	pass

func _snapshot_engine_state() -> Dictionary:
	return {}

func _snapshot_moving_world_state(game: WPGame) -> Array:
	return []

func _snapshot_player(p: WPPlayer) -> Dictionary:
	return {}

func _spawn_checkpoint_marker(player: WPPlayer, pos: Vector2) -> Node2D:
	return null

func _strip_icon_background(image: Image) -> void:
	pass

func _style_button(btn: Button, bg: Color, corner: int = 18, border_w: int = 4) -> void:
	pass

func _sync_practice_playback_injected_input(frame: Dictionary) -> void:
	pass

func _theme_fill(color: Color) -> Color:
	return Color()

func _theme_text(color: Color) -> Color:
	return Color()

func _ticks_since_last_playback_boundary(tick: int) -> int:
	return 0

func _toggle_overlay_hidden() -> void:
	pass

func _tool_restricted() -> bool:
	return false

func _update_macro_playback_timer() -> void:
	pass

func _update_mouse_capture() -> void:
	pass

func _update_overlay() -> void:
	pass

func _update_practice_live_airborne_clock() -> void:
	pass

func _watch_jumpzone(delta: float) -> void:
	pass

func _watch_practice_auto_activate() -> void:
	pass

func _watch_practice_place_request() -> void:
	pass

func _watch_practice_start_request() -> void:
	pass

func _watch_saved_macro_autoplay(delta: float) -> void:
	pass

func _check_first_launch() -> String:
	return ""

func _start_onboarding(hide_overlay: bool) -> void:
	pass
