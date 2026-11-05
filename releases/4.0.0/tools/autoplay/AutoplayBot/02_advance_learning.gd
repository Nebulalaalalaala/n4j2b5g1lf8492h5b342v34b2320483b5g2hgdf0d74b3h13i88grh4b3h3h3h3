extends "user://mod/tools/autoplay/AutoplayBot/01_placeholders.gd"

func configure(owner: Node) -> void:
	tas_tool = owner
	rng.randomize()


func build_tab(tab_root: Control) -> void:
	if tas_tool == null or tab_root == null:
		return
	var intro = tas_tool.call("_open_card", tab_root, "Autoplay")
	var body_font = tas_tool.get("_body_font")
	var intro_label: Label = tas_tool.call("_make_label", "Searches the level through real Goober Dash physics. From every position it genuinely reaches, Autoplay tries several short run, jump, wall-jump, reversal and dash sequences, keeps useful new states, and expands from them. Geometry helps prioritize the search but never pretends an untested route is playable.", body_font, COLOR_TEXT)
	intro_label.autowrap = true
	intro_label.rect_min_size = Vector2(610, 0)
	intro.add_child(intro_label)

	var local_label: Label = tas_tool.call("_make_label", "Local Time Trial, editor test, or tutorial only. Public matches are server-authoritative, so Autoplay will refuse to start there.", body_font, COLOR_PINK)
	local_label.autowrap = true
	local_label.rect_min_size = Vector2(610, 0)
	intro.add_child(local_label)

	var training = tas_tool.call("_open_card", tab_root, "Training")
	var primary_row := HBoxContainer.new()
	primary_row.add_constant_override("separation", 10)
	_start_button = tas_tool.call("_make_button", "▶ Start Learning", COLOR_BLUE, 230)
	_start_button.connect("pressed", self, "_on_start_pressed")
	primary_row.add_child(_start_button)
	_stop_button = tas_tool.call("_make_button", "■ Stop", COLOR_RED, 130)
	_stop_button.connect("pressed", self, "_on_stop_pressed")
	primary_row.add_child(_stop_button)
	training.add_child(primary_row)

	_status_label = tas_tool.call("_make_label", _status_text, body_font, COLOR_DIM)
	training.add_child(_status_label)

	var settings_row := HBoxContainer.new()
	settings_row.add_constant_override("separation", 8)
	settings_row.add_child(tas_tool.call("_make_label", "Attempt length:", body_font, COLOR_DIM))
	var duration_minus = tas_tool.call("_make_button", "−", COLOR_BLUE, 52)
	duration_minus.connect("pressed", self, "_on_duration_delta", [-ATTEMPT_SECONDS_STEP])
	settings_row.add_child(duration_minus)
	_duration_label = tas_tool.call("_make_label", "%ds" % _attempt_seconds, tas_tool.get("_header_font"), COLOR_TEXT)
	_duration_label.rect_min_size = Vector2(64, 0)
	_duration_label.align = Label.ALIGN_CENTER
	settings_row.add_child(_duration_label)
	var duration_plus = tas_tool.call("_make_button", "+", COLOR_BLUE, 52)
	duration_plus.connect("pressed", self, "_on_duration_delta", [ATTEMPT_SECONDS_STEP])
	settings_row.add_child(duration_plus)
	_speed_button = tas_tool.call("_make_button", "Training Speed: 2×", COLOR_BLUE, 210)
	_speed_button.hint_tooltip = "Cycles 1×, 2×, and 4×. Physics still advances one real fixed tick at a time."
	_speed_button.connect("pressed", self, "_on_speed_pressed")
	settings_row.add_child(_speed_button)
	training.add_child(settings_row)

	var results = tas_tool.call("_open_card", tab_root, "Best Attempt")
	_result_label = tas_tool.call("_make_label", "No attempts yet.", body_font, COLOR_DIM)
	results.add_child(_result_label)
	var result_row := HBoxContainer.new()
	result_row.add_constant_override("separation", 8)
	_play_button = tas_tool.call("_make_button", "▶ Play Best", COLOR_GREEN, 170)
	_play_button.connect("pressed", self, "_on_play_best_pressed")
	result_row.add_child(_play_button)
	_install_button = tas_tool.call("_make_button", "Send to Macro Bot", COLOR_PURPLE, 220)
	_install_button.hint_tooltip = "Replaces the current unsaved Macro Bot run with this attempt. Saved slots are untouched."
	_install_button.connect("pressed", self, "_on_install_pressed")
	result_row.add_child(_install_button)
	_reset_button = tas_tool.call("_make_button", "Reset Learning", COLOR_RED, 180)
	_reset_button.connect("pressed", self, "_on_reset_pressed")
	result_row.add_child(_reset_button)
	results.add_child(result_row)
	_refresh_ui(true)


func is_active() -> bool:
	return _learning or _replaying or _waiting_for_ready


func on_tool_gate(tool_enabled: bool) -> void:
	if not is_active():
		return
	if not tool_enabled:
		_stop_internal("Autoplay stopped because Goobplayability was disabled.", false)
	elif not _is_supported_game():
		_stop_internal("Autoplay stopped: this is not a local Time Trial/editor test.", true)


# Called at the start of TASTool's very-early physics callback. Returning true
# means Autoplay owns this tick and normal Macro Bot recording/playback should
# not run on top of it.
func physics_tick() -> bool:
	if not is_active():
		return false
	if not _is_supported_game():
		_stop_internal("Autoplay stopped: public matches and other server-controlled modes are unsupported.", true)
		return true
	var current_game = tas_tool.call("_find_game")
	if _game_id != 0 and current_game != null and current_game.get_instance_id() != _game_id:
		_stop_internal("Autoplay stopped because the level changed. Start it again on the new attempt.", true)
		return true
	if _waiting_for_ready:
		_advance_ready_wait()
		return true
	if _settle_ticks > 0:
		_release_inputs()
		_settle_ticks -= 1
		if _settle_ticks == 0:
			_status_text = "Replaying best attempt..." if _replaying else "Attempt %d running..." % _attempt
			_refresh_ui()
		return true
	if _replaying:
		_advance_replay()
	else:
		_advance_learning_trial()
	return true


func _on_start_pressed() -> void:
	if _learning or _waiting_for_ready:
		_stop_internal("Learning stopped. Best attempt kept.", true)
		return
	if _replaying:
		_stop_internal("Best-attempt replay stopped.", false)
	if not _is_supported_game():
		_status_text = "Can't start here. Open a local Time Trial, editor test, or tutorial; public matches run on the server."
		_log(_status_text)
		_refresh_ui(true)
		return
	_stop_other_input_modes()
	var current_game = tas_tool.call("_find_game")
	_resume_existing = not _best_frames.empty() and not _start_snapshot.empty() and current_game != null and current_game.get_instance_id() == _game_id
	_saved_time_scale = Engine.time_scale
	_saved_time_scale_valid = true
	Engine.time_scale = _training_speed
	_learning = true
	_waiting_for_ready = true
	_ready_ticks = 0
	_status_text = "Waiting for the level-start hold to finish..."
	_refresh_ui(true)


func _advance_ready_wait() -> void:
	var player = tas_tool.call("_get_local_player")
	var ready: bool = player != null and bool(tas_tool.call("_player_ready_for_checkpoint", player)) and bool(tas_tool.call("_game_ready_for_practice_start"))
	if not ready:
		_ready_ticks = 0
		return
	_ready_ticks += 1
	if _ready_ticks < READY_TICKS_REQUIRED:
		return
	_waiting_for_ready = false
	_ready_ticks = 0
	_begin_learning_session(player)


func _begin_learning_session(player) -> void:
	_game = tas_tool.call("_find_game")
	if _game == null:
		_stop_internal("Autoplay couldn't find the running level.", true)
		return
	_game_id = _game.get_instance_id()
	_connect_finish_signal(_game)
	if _resume_existing:
		_resume_existing = false
		Engine.time_scale = _training_speed
		_prepare_next_trial()
		_log("Autoplay: continuing learning from the saved start and elite routes")
		return
	_start_snapshot = tas_tool.call("_snapshot_player", player).duplicate(true)
	_capture_autoplay_world_state(_start_snapshot)
	_finish_rects = _collect_finish_rects(_game)
	if _finish_rects.empty():
		_stop_internal("Autoplay needs a race level with at least one finish line.", true)
		return
	_initial_finish_distance = max(1.0, _distance_to_finish(player.position))
	var target := _nearest_finish_point(player.position)
	_preferred_direction = 1 if target.x >= player.position.x else -1
	_start_checkpoint = int(player.last_checkpoint) if "last_checkpoint" in player else 0
	_status_text = "Reading level geometry, then starting real-physics search..."
	_refresh_ui(true)
	var mapped_route := _build_navigation_route(_game, player.position)
	var route_flags := ""
	if _route_is_relaxed:
		route_flags += ", relaxed"
	if _route_is_partial:
		route_flags += ", partial"
	_log("Autoplay mapper: %d solids, %d hazards, %d checkpoints, %d sampled points, %d route points toward %s%s" % [_solid_rects.size(), _hazard_rects.size(), _checkpoint_nav_points.size(), _nav_sampled_point_count, _navigation_route.size(), _route_goal_kind, route_flags])
	_dump_current_level_for_diagnostics()
	if not mapped_route:
		_navigation_route = [player.position]
		_rebuild_route_lengths()
	_attempt = 0
	_elites.clear()
	_novelty_archive.clear()
	_novelty_order.clear()
	_locked_frames.clear()
	_locked_finish_distance = _initial_finish_distance
	_locked_projection = 0.0
	_locked_checkpoint = 0
	_best_score = -INF
	_best_genome.clear()
	_best_frames.clear()
	_best_end_snapshot.clear()
	_best_progress_tick = 0
	_best_finish_distance = INF
	_best_checkpoint = 0
	_solved = false
	_solved_ticks = 0
	_search_frontier.clear()
	_search_visited.clear()
	_search_visited_order.clear()
	_search_source.clear()
	_search_pending_actions.clear()
	_search_action.clear()
	_search_expansions = 0
	_search_accepted = 0
	_search_best_route_progress = 0.0
	_search_best_finish_distance = _initial_finish_distance
	var root := {
		"snapshot": _start_snapshot.duplicate(true),
		"segments": [],
		"path_ticks": 0,
		"checkpoint_ids": [_start_checkpoint],
		"checkpoint_depth": 0,
		"score": _search_state_score(_start_snapshot, 0, 0),
		"route_index": 1 if _navigation_route.size() > 1 else 0,
	}
	_search_frontier.append(root)
	_remember_search_state(_search_state_key(_start_snapshot), float(root["score"]))
	_resume_existing = false
	if not _saved_time_scale_valid:
		_saved_time_scale = Engine.time_scale
		_saved_time_scale_valid = true
	Engine.time_scale = _training_speed
	_prepare_next_trial()
	_log("Autoplay: started real-physics frontier search%s" % (" with a geometry heuristic" if mapped_route else " without assuming a geometric route is playable"))


func _prepare_next_trial() -> void:
	if _search_pending_actions.empty():
		_search_source = _pop_search_frontier()
		while not _search_source.empty() and int(_search_source.get("path_ticks", 0)) >= _horizon_ticks():
			_search_source = _pop_search_frontier()
		if _search_source.empty():
			_stop_internal("Autoplay exhausted the current physics frontier. Increase Attempt length or Reset Learning to search again.", true)
			return
		_search_pending_actions = _make_search_actions(_search_source["snapshot"])
		_search_expansions += 1
	if _search_pending_actions.empty():
		_stop_internal("Autoplay couldn't generate movement branches for this state.", true)
		return
	_search_action = _search_pending_actions.pop_front()
	_attempt += 1
	_trial_genome = []
	_trial_frames = []
	_trial_tick = 0
	var source_snapshot: Dictionary = _search_source["snapshot"]
	var source_position: Vector2 = source_snapshot.get("position", _start_snapshot.get("position", Vector2.ZERO))
	_trial_min_finish_distance = _distance_to_finish(source_position)
	_trial_max_projection = _route_progress_at(source_position)
	_trial_max_checkpoint = 0
	_trial_max_route_index = int(_search_source.get("route_index", 0))
	_trial_progress_tick = 0
	_trial_last_snapshot = source_snapshot.duplicate(true)
	_trial_last_alive_position = source_position
	_trial_source_position = source_position
	_trial_last_saved_position = source_position
	_trial_prev_grounded = float(source_snapshot.get("stick_to_ground_timer", 0.0)) > 0.0
	_trial_prev_wall = bool(source_snapshot.get("wallslide_counter", false))
	var source_velocity: Vector2 = source_snapshot.get("linear_velocity", Vector2.ZERO)
	_trial_prev_velocity_y = source_velocity.y
	_trial_prev_checkpoint = int(source_snapshot.get("last_checkpoint", _start_checkpoint))
	_route_index = int(_search_source.get("route_index", 0))
	_route_stall_ticks = 0
	_route_last_position = _trial_last_alive_position
	_finish_hit = false
	_release_inputs()
	var player = tas_tool.call("_get_local_player")
	if player == null:
		_stop_internal("Autoplay lost the local player.", true)
		return
	tas_tool.call("_restore_player", player, source_snapshot)
	_restore_autoplay_world_state(source_snapshot)
	# _restore_player deliberately mirrors a real respawn and therefore ends in
	# the game's opaque _reset_object(). That is correct for reviving the body,
	# but a frontier node may be mid-jump, mid-wall-slide, or mid-dash rather
	# than a spawn. Reapply its captured beginning-of-tick physics fields after
	# the revive so the next branch truly continues from the reached state.
	tas_tool.call("_apply_recorded_practice_frame_state", player, source_snapshot)
	player.alive = true
	player.body_enabled = true
	player.dead_counter = 0
	if player.body != null:
		player.body.enabled = true
		player.body.global_position = source_position
		player.body.linear_velocity = source_snapshot.get("linear_velocity", Vector2.ZERO)
	# TASTool's independent death-momentum guard saw the failed attempt's dead
	# edge earlier in this same callback. Mark this deliberate restore alive so
	# it does not mistake the next learning tick for a native respawn and erase
	# a non-zero starting velocity.
	tas_tool.set("_freeze_prev_alive", true)
	tas_tool.set("_freeze_last_alive_position", source_position)
	# Frontier states are allowed to be mid-jump or mid-dash. A settle delay
	# would change that state before its branch even starts, so probes continue
	# on the very next fixed tick.
	_settle_ticks = 0
	Engine.time_scale = _training_speed
	_status_text = "Physics probe %d  •  frontier %d  •  proven path %.1fs" % [_attempt, _search_frontier.size(), float(int(_search_source.get("path_ticks", 0))) / _physics_fps()]
	_refresh_ui()
	_apply_search_probe_frame(player)


func _advance_learning_trial() -> void:
	var player = tas_tool.call("_get_local_player")
	if player == null:
		_stop_internal("Autoplay lost the local player.", true)
		return
	if _finish_hit:
		_observe_player(player)
		_finish_trial(true, false)
		return
	if not player.alive:
		_finish_trial(false, true)
		return
	var segment_ticks := int(_search_action.get("ticks", SEARCH_DEFAULT_SEGMENT_TICKS))
	if _trial_tick >= segment_ticks or int(_search_source.get("path_ticks", 0)) + _trial_tick >= _horizon_ticks():
		_observe_player(player)
		_finish_trial(false, false)
		return

	_apply_search_probe_frame(player)
	if _trial_tick % 10 == 0:
		_status_text = "Physics probe %d  •  branch %s  •  %d states kept  •  best path %.1fs" % [_attempt, str(_search_action.get("name", "movement")), _search_accepted, float(_locked_frames.size()) / _physics_fps()]
		_refresh_ui()


func _apply_search_probe_frame(player) -> void:
	_observe_player(player)
	var grounded := float(player.stick_to_ground_timer) > 0.0 if "stick_to_ground_timer" in player else false
	var on_wall := bool(player.wallslide_counter) if "wallslide_counter" in player else false
	var velocity_y := float(player.linear_velocity.y) if "linear_velocity" in player else 0.0
	var checkpoint_id := int(player.last_checkpoint) if "last_checkpoint" in player else _start_checkpoint
	if _trial_tick >= 4:
		var decision_reason := ""
		if checkpoint_id != 0 and checkpoint_id != _trial_prev_checkpoint:
			decision_reason = "new checkpoint"
		elif grounded and not _trial_prev_grounded:
			decision_reason = "landing"
		elif on_wall and not _trial_prev_wall:
			decision_reason = "wall contact"
		elif _trial_prev_wall and not on_wall and player.position.y < _trial_source_position.y - 8.0:
			decision_reason = "wall launch"
		elif _trial_prev_velocity_y < -45.0 and velocity_y >= -45.0:
			decision_reason = "jump apex"
		elif _trial_tick % SEARCH_DECISION_INTERVAL_TICKS == 0 and player.position.distance_to(_trial_last_saved_position) >= SEARCH_DECISION_MIN_DISTANCE:
			decision_reason = "mid-air state" if not grounded else "movement state"
		if not decision_reason.empty() and not _trial_frames.empty():
			var decision_snapshot := _light_snapshot(player)
			var decision_node := _build_search_node(decision_snapshot, _trial_frames)
			if _accept_search_node(decision_node, false, decision_reason):
				_trial_last_saved_position = player.position
	var frame: Dictionary = _search_frame_for_tick(_search_action, _trial_tick, player)
	frame[FRAME_STATE_KEY] = tas_tool.call("_capture_practice_frame_state", player, _game)
	_trial_frames.append(frame)
	tas_tool.call("_sync_practice_playback_injected_input", frame)
	_trial_tick += 1
	_trial_prev_grounded = grounded
	_trial_prev_wall = on_wall
	_trial_prev_velocity_y = velocity_y
	_trial_prev_checkpoint = checkpoint_id


func _advance_replay() -> void:
	var player = tas_tool.call("_get_local_player")
	if player == null:
		_stop_internal("Best-attempt replay stopped: no local player found.", true)
		return
	if _finish_hit:
		_stop_internal("Best attempt reached the finish again.", true)
		return
	if not player.alive:
		if not _recover_autoplay_replay_death(player):
			_stop_internal("Best-attempt replay died before its recorded endpoint.", true)
			return
	if _trial_tick >= _best_frames.size():
		_stop_internal("Solved run replay reached its recorded endpoint." if _solved else "Learned prefix ended here; Continue Learning to reach the finish.", true)
		return
	var frame: Dictionary = _best_frames[_trial_tick]
	if frame.has(FRAME_STATE_KEY) and typeof(frame[FRAME_STATE_KEY]) == TYPE_DICTIONARY:
		tas_tool.call("_apply_recorded_practice_frame_state", player, frame[FRAME_STATE_KEY])
		Engine.time_scale = clamp(float(frame[FRAME_STATE_KEY].get("tas_playback_speed", 1.0)), 0.05, 4.0)
	tas_tool.call("_sync_practice_playback_injected_input", frame)
	_trial_tick += 1
	if _trial_tick % 15 == 0:
		_status_text = "%s %.1fs / %.1fs" % ["Replaying solved run..." if _solved else "Replaying learned prefix...", float(_trial_tick) / _physics_fps(), float(_best_frames.size()) / _physics_fps()]
		_refresh_ui()


func _recover_autoplay_replay_death(player) -> bool:
	if _trial_tick < 0 or _trial_tick >= _best_frames.size():
		return false
	var frame = _best_frames[_trial_tick]
	if typeof(frame) != TYPE_DICTIONARY or not frame.has(FRAME_STATE_KEY):
		return false
	var state = frame[FRAME_STATE_KEY]
	if typeof(state) != TYPE_DICTIONARY or not state.has("position") or not state.has("linear_velocity"):
		return false
	var recovery: Dictionary = state.duplicate(true)
	recovery["alive"] = true
	recovery["body_enabled"] = true
	recovery["dead_counter"] = 0
	tas_tool.call("_restore_player", player, recovery)
	_restore_autoplay_world_state(recovery)
	tas_tool.call("_apply_recorded_practice_frame_state", player, state)
	player.alive = true
	player.body_enabled = true
	player.dead_counter = 0
	if player.body != null:
		player.body.enabled = true
		player.body.global_position = state["position"]
		player.body.linear_velocity = state["linear_velocity"]
	_log("Autoplay replay: corrected a moving-layout timing death from the next verified frame")
	return true


func _observe_player(player) -> void:
	_trial_last_alive_position = player.position
	var distance := _distance_to_finish(player.position)
	_update_route_index(player.position)
	var projection := _route_progress_at(player.position)
	var checkpoint_progress := int(_search_source.get("checkpoint_depth", 0))
	if "last_checkpoint" in player:
		var checkpoint_id := int(player.last_checkpoint)
		var checkpoint_ids: Array = _search_source.get("checkpoint_ids", [])
		if checkpoint_id != 0 and not checkpoint_ids.has(checkpoint_id):
			checkpoint_progress += 1
	if player.position.distance_to(_route_last_position) < 1.5 and projection <= _trial_max_projection + 1.0:
		_route_stall_ticks += 1
	else:
		_route_stall_ticks = 0
	_route_last_position = player.position
	if distance < _trial_min_finish_distance or projection > _trial_max_projection + 1.0 or checkpoint_progress > _trial_max_checkpoint or _route_index > _trial_max_route_index:
		_trial_progress_tick = _trial_tick
		_trial_last_snapshot = _light_snapshot(player)
	_trial_min_finish_distance = min(_trial_min_finish_distance, distance)
	_trial_max_projection = max(_trial_max_projection, projection)
	_trial_max_checkpoint = max(_trial_max_checkpoint, checkpoint_progress)
	_trial_max_route_index = max(_trial_max_route_index, _route_index)
