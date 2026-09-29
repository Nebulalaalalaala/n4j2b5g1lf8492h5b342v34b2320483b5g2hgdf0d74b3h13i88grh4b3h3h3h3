extends "user://mod/tools/tas/TASTool/18_gameplay_fixes.gd"

# Shows/hides one of the small title-icon TextureRects built into
# _build_menu_window()/_build_log_window(), based on the current toggle state.
# No-ops (rect stays hidden) if the named icon isn't available. `size` must
# match that TextureRect's own rect_min_size (set where it's built) so the
# resample in _load_claude_icon() comes out crisp at exactly that size.
func _set_claude_icon_slot(rect: TextureRect, icon_name: String, size: int) -> void:
	if rect == null:
		return
	if not _claude_experimental_icons_enabled:
		rect.visible = false
		return
	var texture: = _load_claude_icon(icon_name, size)
	rect.texture = texture
	rect.visible = texture != null


# ----------------------------------------------------------------------
#  Macro Bot Mode -- stitched playback ("Play Macro")
# ----------------------------------------------------------------------
func _on_play_practice_macro_pressed() -> void:
	_continue_resimulating = false
	_ensure_game_over_submission_guard_runs_first()
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
	_macro_playback_timer_pills.clear()
	_collect_macro_editor_timers(get_tree().root, _macro_playback_timer_pills)
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


# Bridge for ReplayHub.gd's "SHARE A MACRO SLOT" picker. Returns a
# duplicate, never the live dictionary, so the picker UI can't mutate a
# slot's actual saved data.
func _get_practice_macro_slots_snapshot() -> Dictionary:
	return _practice_macro_slots.duplicate(true)


# Bridge for ReplayHub.gd's Download/Play buttons -- imports an
# already-decoded, already-validated replay Dictionary (checkpoints/
# segments/level_context) into a brand new Macro Slot using the exact same
# steps as pressing "+ CREATE MACRO SLOT" followed by a save, so every
# existing Macro Slot control (Play/Edit/Delete) works on it afterward
# exactly like any macro recorded locally. Returns the new slot number, or
# 0 if the import was refused.
func _import_downloaded_replay(data: Dictionary, display_name: String) -> int:
	if not (data.has("checkpoints") and data.has("segments")):
		_log_action("Replay Hub import rejected -- missing checkpoints/segments", null)
		return 0
	if _practice_macro_slot_count >= MAX_PRACTICE_MACRO_SLOTS:
		_log_action("Macro Slot limit reached (%d) -- delete a slot before downloading another replay" % MAX_PRACTICE_MACRO_SLOTS, null)
		return 0
	_practice_macro_slot_count += 1
	var slot: = _practice_macro_slot_count
	var imported: Dictionary = data.duplicate(true)
	var slot_name: = display_name if not display_name.empty() else str(imported.get("name", "Downloaded Replay"))
	imported["name"] = slot_name
	_practice_macro_slots[slot] = imported
	_write_practice_macro_slot_to_disk(slot, imported)
	_save_practice_macro_slot_layout()
	if _practice_macro_grid != null:
		var card := _build_practice_macro_slot_card(slot)
		_practice_macro_slot_cards.append(card)
		_practice_macro_grid.add_child(card)
		_refresh_practice_macro_slot_ui(slot)
	_log_action("Replay Hub: imported '%s' into Macro Slot %d" % [slot_name, slot], null)
	return slot


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
	# Installed snapshots and recorded frames are read-only during playback.
	# Copy the editable containers, not tens of MB of immutable world states.
	# Timeline edits already use their own deep-copied working_data.
	_practice_checkpoints = data["checkpoints"].duplicate()
	_practice_segments = data["segments"].duplicate()
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
	if _practice_continue_buttons.has(slot) and is_instance_valid(_practice_continue_buttons[slot]):
		_practice_continue_buttons[slot].disabled = not _practice_macro_slots.has(slot)
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
		# Classic COLOR_SLOT_FILLED is a light card needing dark text; the
		# modern remap turns it into a dark elevated card instead, so the
		# text needs to flip to light rather than being remapped by value.
		var filled_text_color: = Color(0, 0.15, 0.3)
		if _modern_theme_active():
			filled_text_color = COLOR_MODERN_WHITE
		_practice_macro_slot_status_labels[slot].add_color_override("font_color", filled_text_color)
	else:
		card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, COLOR_WHITE, 3, 16))
		_practice_macro_slot_status_labels[slot].add_color_override("font_color", _theme_text(COLOR_TEXT_DIM))
