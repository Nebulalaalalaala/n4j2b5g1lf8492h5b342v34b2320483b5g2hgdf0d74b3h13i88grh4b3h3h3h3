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
func _current_macro_level_editor() -> LevelEditor:
	var game = _find_game()
	var scene = get_tree().current_scene
	if game == null or scene == null or not game.is_server() or game.wp_game_data == null or not game.wp_game_data.is_level_editor:
		return null
	if not scene.is_a_parent_of(game):
		return null
	var editor = scene.find_node("LevelEditor",true,false)
	if editor is LevelEditor and editor.game == game and editor.level == game.level and editor.is_playable():
		return editor
	return null


func _current_macro_time_trial() -> Node:
	var scene = get_tree().current_scene
	if scene != null and scene.filename == "res://scenes/TimeTrialGameplayScene.tscn" and _is_normal_linked_time_trial_scene(scene):
		return scene
	return null


func _current_macro_verification() -> Node:
	var scene = get_tree().current_scene
	if scene != null and scene.filename == "res://scenes/TimeTrialGameplayScene.tscn" and scene.parameters != null and scene.parameters.mode == TimeTrialSceneParameters.TimeTrialSceneMode.PrepublishRun:
		return scene
	return null


func _connect_macro_level_editor_controls(editor: LevelEditor) -> void:
	for entry in [[editor.play_button,"pressed",false],[editor.game_hud,"show_level_editor_button_pressed",false],[editor.reset_button,"pressed",true]]:
		var control = entry[0]
		if control != null and not control.is_connected(entry[1],self,"_on_macro_level_editor_control"):
			control.connect(entry[1],self,"_on_macro_level_editor_control",[editor,entry[2]],CONNECT_DEFERRED)


func _on_macro_level_editor_control(editor: LevelEditor, reset: bool) -> void:
	# Run deferred so native callbacks have applied their resulting mode.
	# Returning to building/resetting must not leave TAS input running there.
	if not is_instance_valid(editor) or not _practice_playback or (not reset and editor.is_playing):
		return
	_release_all_injected_actions()
	_practice_playback_pending_start = false
	_reset_playback_visual_track()
	_is_paused = false
	Engine.time_scale = 1.0
	_log_action("Stopped macro playback in the level editor",null)


func _on_play_working_run_pressed() -> void:
	if _macro_launch_pending() or _practice_playback:
		return
	var trial = _current_macro_time_trial()
	if trial != null:
		var data = _practice_macro_slots.get(_loaded_macro_slot, {})
		if data.empty() and is_instance_valid(_tas_studio_node) and _tas_studio_node.workflow_mode == "sections":
			_tas_studio_node.play_run()
			return
		if data.empty():
			var segments = _practice_segments.duplicate()
			segments.append(_practice_current_segment)
			_restart_working_time_trial(trial, segments, _practice_working_level_id)
			return
		if _macro_level_is_current(data):
			_restart_working_time_trial(trial, data.get("segments", []), _macro_slot_level_id(data))
			return
	_on_play_practice_macro_pressed()


func _on_play_practice_macro_pressed(resimulating := false) -> void:
	var verification = _current_macro_verification()
	if verification != null:
		if _loaded_macro_slot > 0 and not resimulating:
			_on_play_saved_practice_macro_slot_pressed(_loaded_macro_slot)
		else:
			_show_responsive_popup("LOAD A MACRO","Load a saved macro and press Play working run to try its inputs in this verification.")
		return
	var level_editor = _current_macro_level_editor()
	if not resimulating and _loaded_macro_slot > 0 and _practice_macro_slots.has(_loaded_macro_slot):
		if _macro_load_opens_level and level_editor == null:
			_on_play_saved_practice_macro_slot_pressed(_loaded_macro_slot)
			return
		if not _prepare_loaded_macro_for_current_level():
			return
	_continue_resimulating = false
	if not resimulating and _tas_run_options().needs_resimulation(_practice_segments):
		_log_action("Inputs edited: use Timeline Editor → Continue From Here to re-simulate to your cursor before playback. Saved positions are stale; saved slot unchanged.", null)
		return
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
	if level_editor != null:
		if not level_editor.is_playing:
			level_editor.on_play_pressed()
		_connect_macro_level_editor_controls(level_editor)
	_practice_active = false # don't record over ourselves while replaying
	_release_all_injected_actions() # (also clears _practice_playback if it somehow was true; harmless)
	_continue_resimulating = resimulating
	_build_practice_playback_frames()
	_tas_run_options().begin_join_check(_practice_playback_checkpoint_at, _practice_playback_frames.size())
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
	Engine.time_scale = 1.0 if resimulating or _practice_playback_frames.empty() else _tas_run_options().playback_speed(_practice_playback_frames[0])
	_log_action("Macro Bot Mode: playing back stitched macro (%d checkpoint(s), %d frame(s) total)" % [_practice_checkpoints.size() - 1, _practice_playback_frames.size()], null)
	_refresh_practice_ui()


# ----------------------------------------------------------------------
#  Macro Bot Mode -- macro slots (Save/Load/Delete), same idea and
#  same File.store_var()/get_var() persistence as Replay Slots above.
# ----------------------------------------------------------------------
func _practice_macro_slot_path(slot: int) -> String:
	return "%s/slot_%d.tasmacro" % [PRACTICE_MACRO_DIR, slot]


func _macro_slot_frame_count(data: Dictionary) -> int:
	var count = 0
	for segment in data.get("segments",[]):
		if not segment is Array:
			return -1
		count += segment.size()
	return count


func _write_practice_macro_slot_to_disk(slot: int, data: Dictionary) -> bool:
	var dir: = Directory.new()
	if not dir.dir_exists(PRACTICE_MACRO_DIR):
		if dir.make_dir_recursive(PRACTICE_MACRO_DIR) != OK:
			return false
	var path = _practice_macro_slot_path(slot)
	var temporary = path + ".tmp"
	var previous = path + ".previous"
	var f: = File.new()
	if f.open(temporary, File.WRITE) != OK:
		return false
	f.store_var(data, false)
	var error = f.get_error()
	f.close()
	if error != OK or f.open(temporary,File.READ) != OK:
		return false
	var checked = f.get_var(false)
	f.close()
	if not checked is Dictionary or not checked.get("checkpoints") is Array or not checked.get("segments") is Array:
		dir.remove(temporary)
		return false
	if checked.checkpoints.size() != data.get("checkpoints",[]).size() or _macro_slot_frame_count(checked) != _macro_slot_frame_count(data):
		dir.remove(temporary)
		return false
	# Keep the last successful file until its verified replacement is ready.
	var had_previous = f.file_exists(path)
	if had_previous:
		if f.file_exists(previous) and dir.remove(previous) != OK:
			return false
		if dir.rename(path,previous) != OK:
			return false
	if dir.rename(temporary,path) != OK:
		if had_previous:
			dir.rename(previous,path)
		return false
	return true


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

# Hub's picker needs names only, not a deep copy of every world snapshot.
# Copy one selected slot only after explicit Prepare; existing data stays private.
func _get_practice_macro_share_items() -> Array:
	var result = []
	var slots = _practice_macro_slots.keys()
	slots.sort()
	for slot in slots:
		result.append({"key":str(slot),"name":str(_practice_macro_slots[slot].get("name","Macro slot %d" % slot))})
	return result

func _get_practice_macro_share_data(slot: int) -> Dictionary:
	if not _practice_macro_slots.has(slot): return {}
	var file = File.new()
	if file.open(_practice_macro_slot_path(slot),File.READ)==OK:
		var size = file.get_len()
		file.close()
		if size>16777220: return {} # Same 16 MiB uncompressed Hub limit, plus File header.
	return _practice_macro_slots[slot].duplicate(true)


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
	if not _write_practice_macro_slot_to_disk(slot, imported):
		_practice_macro_slot_count -= 1
		_log_action("Replay import could not be saved; no slot was replaced",null)
		return 0
	_practice_macro_slots[slot] = imported
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
	if _loaded_macro_slot > 0 and _practice_macro_slots.has(_loaded_macro_slot):
		# A held macro still belongs to its saved level, not the menu/current
		# unrelated game. Never replace that context with a new native snapshot.
		var held_data = _practice_macro_slots[_loaded_macro_slot].duplicate(true)
		if not _write_practice_macro_slot_to_disk(slot, held_data):
			_show_responsive_popup("SAVE FAILED","The previous saved file is unchanged.")
			return
		_practice_macro_slots[slot] = held_data
		_loaded_macro_slot = slot
		_log_action("Saved loaded macro to Macro Slot %d" % slot,null)
		_refresh_practice_ui()
		return
	var working_studio = _tas_studio()
	# Section projects own the complete run, including the live tail and any
	# timeline suffix beyond a scrubbed cursor. Legacy Save only keeps segments.
	if _practice_segments.empty() or (working_studio != null and not working_studio.sections.empty()):
		var studio = working_studio
		var previous_slot = studio.loaded_slot
		studio.loaded_slot = slot
		var result = studio.save_run()
		if not result.begins_with("Saved to Macro Slot "):
			studio.loaded_slot = previous_slot
		_log_action(result,null)
		_show_responsive_popup("PROJECT SAVED" if result.begins_with("Saved to Macro Slot ") else "SAVE NOT COMPLETED",result)
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
	# Sections and their tries travel with the run, so they come back on load.
	var studio = _tas_studio()
	if studio != null and not studio.sections.empty():
		data["studio_project"] = studio.project_for_slot()
	if not _write_practice_macro_slot_to_disk(slot, data):
		_show_responsive_popup("SAVE FAILED","The previous saved file is unchanged. Check free space and folder access, then try again.")
		return
	_practice_macro_slots[slot] = data
	if studio != null:
		studio.loaded_slot = slot
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
	var studio = _tas_studio()
	if studio != null:
		if not studio.job.empty() or (studio.bots != null and studio.bots.busy()) or is_instance_valid(studio.zone_editor):
			_log_action("Finish the current section edit or job before loading a slot", null)
			return false
		# A saved project replaces the live attempt as well as its frame data.
		# Otherwise its deferred retry keeps writing into the newly loaded run.
		studio.cancel_practice_request()
		studio._leave_timeline_preview()
		studio.stop_practice()
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
	if studio != null:
		studio.loaded_slot = slot
		if data.get("studio_project") is Dictionary:
			studio.call_deferred("load_saved_project", data.studio_project, slot)
		else:
			studio.sections = []
			studio.segmented = false
	return true


func _on_load_practice_macro_slot_pressed(slot: int) -> void:
	if not _practice_macro_slots.has(slot):
		_log_action("Macro Bot Slot %d is empty" % slot, null)
		return
	# A native editor is an explicit current-level target, even when it has
	# forked away the published ID. Loading must not replace it with Time Trial.
	if not _macro_load_opens_level or _current_macro_level_editor() != null or _current_macro_verification() != null:
		_load_macro_without_level(slot)
		return
	var player: = _get_local_player()
	# Not in this slot's level (or not in a level at all): open it, then load.
	if (player == null or not call("_macro_level_is_current", _practice_macro_slots[slot])) and not _macro_slot_level_id(_practice_macro_slots[slot]).empty():
		_on_play_saved_practice_macro_slot_pressed(slot, true)
		if _saved_macro_autoplay_slot == slot:
			set("_saved_macro_autoload_slot", slot)
		return
	if player == null:
		_log_action("No local player found", null)
		return
	if not _game_ready_for_practice_start() or not _player_ready_for_checkpoint(player):
		var level_id = _macro_slot_level_id(_practice_macro_slots[slot])
		if level_id.empty():
			_log_action("Wait for this level's countdown before loading this unlinked slot",null)
			return
		_saved_macro_autoplay_slot = slot
		_saved_macro_autoplay_level_id = level_id
		_saved_macro_autoplay_source_game_id = 0
		_saved_macro_autoplay_elapsed = 0.0
		_saved_macro_autoplay_ready_ticks = 0
		set("_saved_macro_autoload_slot",slot)
		_practice_active = false
		_practice_start_waiting = false
		_practice_auto_activate_waiting_for_alive = false
		_tas_run_options().pause_boundary.cancel(self)
		_is_paused = false
		Engine.time_scale = 1.0
		_log_action("Waiting for the level countdown before loading Macro Slot %d" % slot,null)
		return
	if not _install_practice_macro_slot_data(slot, player, true):
		return
	var detail = "section project" if _practice_checkpoints.empty() else "%d checkpoint(s) -- player moved to checkpoint 0" % max(0, _practice_checkpoints.size() - 1)
	_log_action("Loaded Macro Slot %d (%s)" % [slot, detail], null)
	_refresh_practice_ui()


func _load_macro_without_level(slot: int) -> void:
	if _macro_launch_pending() or _practice_playback:
		_log_action("Finish the current playback or level launch before loading another macro",null)
		return
	var studio = _tas_studio_node
	if is_instance_valid(studio) and studio.busy():
		_log_action("Finish the current section edit or practice before loading another macro",null)
		return
	if is_instance_valid(studio) and studio.bots != null and studio.bots.busy():
		_log_action("Finish the current TAS job before loading another macro",null)
		return
	if is_instance_valid(_macro_editor) and _macro_editor.is_open():
		_log_action("Close the timeline editor before loading another macro",null)
		return
	if _practice_active:
		_stop_practice_mode()
	_clear_practice_data()
	_practice_start_waiting = false
	_practice_auto_activate_waiting_for_alive = false
	if _tas_run_workflow != null:
		_tas_run_workflow.pause_boundary.cancel(self)
	if is_instance_valid(studio):
		studio.recording_cleared()
		studio.sections = []
		studio.segmented = false
		studio.guide_points = PoolVector2Array()
	# This is the active saved working run. Its immutable native frames remain
	# in the slot cache until an explicit action installs them in their level.
	_loaded_macro_slot = slot
	_log_action("Loaded Macro Slot %d into Macro Bot without opening its level" % slot,null)
	_refresh_practice_ui()


func _prepare_loaded_macro_for_current_level() -> bool:
	if _macro_launch_pending() or _practice_playback:
		_log_action("Wait for the current playback or level launch to finish",null)
		return false
	var slot = _loaded_macro_slot
	var data = _practice_macro_slots[slot]
	if _macro_slot_frame_count(data) <= 0 or data.get("checkpoints",[]).empty():
		_show_responsive_popup("NOTHING TO PLAY","This project has no recorded run yet. Open its level to practise the sections.")
		return false
	if _tas_run_options().needs_resimulation(data.get("segments",[])):
		_show_responsive_popup("CHECK EDITED INPUTS","Re-simulate the edited inputs with Continue From Here in the timeline before playing this run.")
		return false
	var game = _find_game()
	var player = _get_local_player()
	var scene = get_tree().current_scene
	var editor = _current_macro_level_editor()
	var valid_scene = editor != null or (_macro_level_is_current(data) and _is_normal_linked_time_trial_scene(scene))
	if game == null or player == null or not game.is_server() or _tool_restricted() or not valid_scene or not scene.is_a_parent_of(game):
		var level_name = _macro_slot_level_name(data)
		if level_name.empty():
			level_name = "this macro's linked level"
		_show_responsive_popup("OPEN THE LEVEL FIRST","Open %s, then press Play working run. Open level enters it without starting playback." % level_name)
		return false
	if game.is_game_over():
		_show_responsive_popup("RESTART THE LEVEL FIRST","Restart this level, then press Play working run after its countdown.")
		return false
	if not _game_ready_for_practice_start() or not _player_ready_for_checkpoint(player):
		_show_responsive_popup("WAIT FOR THE START","Let the current level's countdown or respawn finish, then press Play working run.")
		return false
	# Keep the exact current game. Checkpoint zero is still restored by the
	# ordinary playback's native pending-start tick, not this idle callback.
	return _install_practice_macro_slot_data(slot,player,false)


func _on_open_loaded_macro_level_pressed() -> void:
	if _loaded_macro_slot <= 0 or not _practice_macro_slots.has(_loaded_macro_slot):
		return
	var slot = _loaded_macro_slot
	_on_play_saved_practice_macro_slot_pressed(slot, true)
	if _saved_macro_autoplay_slot == slot:
		set("_saved_macro_autoload_slot",slot)


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
	if _loaded_macro_slot > 0 and _practice_macro_slots.has(_loaded_macro_slot):
		_on_edit_practice_macro_slot_pressed(_loaded_macro_slot)
		return
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
		if not _write_practice_macro_slot_to_disk(slot,data):
			_show_responsive_popup("SAVE FAILED","Timeline edits could not be written. The previous saved slot is unchanged.")
			return
		_practice_macro_slots[slot] = data.duplicate(true)
		_refresh_practice_macro_slot_ui(slot)
		_log_action("Saved timeline edits to Macro Slot %d" % slot, null)
	else:
		_install_editor_data_as_current(data)
		_log_action("Applied timeline edits to the current macro", null)


func _on_play_saved_practice_macro_slot_pressed(slot: int, load_only := false) -> void:
	if not _practice_macro_slots.has(slot):
		_log_action("Macro Bot Slot %d is empty" % slot, null)
		return
	if _macro_launch_pending():
		_log_action("A Macro Bot level is already opening", null)
		return
	var verification = _current_macro_verification()
	if verification != null:
		if load_only:
			_load_macro_without_level(slot)
		else:
			_restart_with_verification_macro(verification,slot)
		return
	var data: Dictionary = _practice_macro_slots[slot]
	if not load_only and (_macro_slot_frame_count(data) <= 0 or data.get("checkpoints",[]).empty()):
		_log_action("This slot is a section project. Load it to practise and build the run before playback.",null)
		return
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
	if _loaded_macro_slot == slot:
		_loaded_macro_slot = 0
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
		_practice_toggle_button.text = ("■ Stop recording" if _practice_active else "■ Stop · waiting to start") if (_practice_active or _practice_start_waiting) else "● Start recording"
		_style_button(_practice_toggle_button, COLOR_PINK if (_practice_active or _practice_start_waiting) else COLOR_BLUE)
	var checkpoint_count: = max(_practice_checkpoints.size() - 1, 0)
	if _practice_status_label != null:
		var practice_text: String
		if _practice_playback:
			practice_text = "Playing back... (%d/%d frames)" % [_practice_playback_index, _practice_playback_frames.size()]
		elif _saved_macro_verification_parameters != null:
			practice_text = "Restarting from the native countdown…"
		elif _saved_macro_autoplay_slot > 0:
			practice_text = "Opening saved level for Macro Slot %d..." % _saved_macro_autoplay_slot
		elif _loaded_macro_slot > 0 and _practice_macro_slots.has(_loaded_macro_slot):
			practice_text = _loaded_macro_status()
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
		_practice_undo_button.visible = _loaded_macro_slot <= 0
	if _practice_open_loaded_level_button != null:
		_practice_open_loaded_level_button.visible = _loaded_macro_slot > 0 and _current_macro_verification() == null
		_practice_open_loaded_level_button.disabled = _loaded_macro_slot <= 0 or not _practice_macro_slots.has(_loaded_macro_slot) or _macro_slot_level_id(_practice_macro_slots.get(_loaded_macro_slot,{})).empty() or _macro_launch_pending()
	if _practice_play_button != null:
		var trial = _current_macro_time_trial()
		var has_working_inputs = not _practice_segments.empty() or (trial != null and not _practice_current_segment.empty())
		if trial != null and is_instance_valid(_tas_studio_node) and _tas_studio_node.workflow_mode == "sections":
			has_working_inputs = has_working_inputs or not _tas_studio_node.full.empty()
		_practice_play_button.disabled = not has_working_inputs or _practice_playback or _macro_launch_pending()
		_practice_play_button.hint_tooltip = "Restart this Time Trial and play from its native start." if trial != null else "Play the working run in the current level."
		if _loaded_macro_slot > 0 and _practice_macro_slots.has(_loaded_macro_slot):
			var loaded = _practice_macro_slots[_loaded_macro_slot]
			var in_verification = _current_macro_verification() != null
			var in_level_editor = _current_macro_level_editor() != null
			var in_linked_trial = trial != null and _macro_level_is_current(loaded)
			_practice_play_button.disabled = _macro_slot_frame_count(loaded) <= 0 or (not in_verification and not in_linked_trial and loaded.get("checkpoints",[]).empty()) or (_macro_slot_level_id(loaded).empty() and not in_level_editor and not in_verification) or _macro_launch_pending() or _practice_playback
			if in_verification:
				_practice_play_button.hint_tooltip = "Restart this verification and play the loaded inputs from the native start."
			elif not in_linked_trial:
				_practice_play_button.hint_tooltip = "Play the loaded macro in this level editor's playtest." if in_level_editor else ("Open the linked level and play the loaded macro." if _macro_load_opens_level else "Play in the current linked level. Open it first; this button will not change levels.")
	if _practice_clear_button != null:
		_practice_clear_button.disabled = _practice_checkpoints.empty() and _loaded_macro_slot <= 0
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
	var playable = false
	if has_data:
		var slot_data: Dictionary = _practice_macro_slots[slot]
		has_level_link = not _macro_slot_level_id(slot_data).empty()
		playable = _macro_slot_frame_count(slot_data) > 0 and not slot_data.get("checkpoints",[]).empty()
		var macro_name := str(slot_data.get("name", ""))
		var level_name: = _macro_slot_level_name(slot_data)
		# Rows have room for the full name and the linked level.
		if level_name.length() > 32:
			level_name = level_name.substr(0, 31) + "…"
		if not macro_name.empty():
			if macro_name.length() > 32:
				macro_name = macro_name.substr(0, 31) + "…"
			_practice_macro_slot_status_labels[slot].text = "%s · %d cp%s" % [macro_name, slot_data["checkpoints"].size() - 1, (" · " + level_name) if not level_name.empty() else ""]
		elif not level_name.empty():
			_practice_macro_slot_status_labels[slot].text = "Saved (%d cp) · %s" % [slot_data["checkpoints"].size() - 1, level_name]
		elif has_level_link:
			_practice_macro_slot_status_labels[slot].text = "Saved (%d cp) · linked" % [slot_data["checkpoints"].size() - 1]
		else:
			_practice_macro_slot_status_labels[slot].text = "Saved (%d cp) · re-save to link" % [slot_data["checkpoints"].size() - 1]
	else:
		_practice_macro_slot_status_labels[slot].text = "Empty"
	if has_data and not playable:
		_practice_macro_slot_status_labels[slot].text = "Section project · %d goals" % _practice_macro_slots[slot].get("studio_project",{}).get("sections",[]).size()
	var in_verification = _current_macro_verification() != null
	var play = _practice_macro_slot_play_buttons[slot]
	play.text = "Play in verification" if in_verification else "Play level"
	play.hint_tooltip = "Restart the current verification and play this macro's inputs." if in_verification else "Open this macro's saved level and start playback automatically."
	play.disabled = not playable or (not has_level_link and not in_verification) or _macro_launch_pending() or _practice_playback
	_practice_macro_slot_load_buttons[slot].disabled = not has_data
	_practice_macro_slot_delete_buttons[slot].disabled = not has_data
	_practice_macro_slot_edit_buttons[slot].disabled = not has_data or not playable
	_practice_macro_slot_load_buttons[slot].hint_tooltip = "Open the linked level and load the run" if _macro_load_opens_level and not in_verification else "Load into Macro Bot without opening the level"
	if _loaded_macro_slot == slot:
		_practice_macro_slot_status_labels[slot].text = "Loaded · " + _practice_macro_slot_status_labels[slot].text
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
