extends Node

var tool = null
var store = null
var game = null
var capture = {}
var round_key = ""
var elapsed = 0.0
var samples = 0
var last_saved = ""
var world_cache = {}
var world_samples = 0
var world_bytes = 0
var elimination_times = {}
var last_world_time = -1.0
var status = "Public spectator admission is not exposed by this client."
var quality = {}
var last_callback_ms = -1
var last_observation_time = -1.0
var last_save_ms = 0
var last_snapshot_ms = 0
var capture_filename = ""
var diagnostic_phase = ""
var save_thread = null
var active_save = {}
var queued_save = {}
var latest_save = {}
var save_failed = false

func background_saves():
	return OS.get_user_data_dir().replace("\\","/").ends_with("/GoobplayabilityCouncilWorker")

func is_saving():
	return save_thread != null or not queued_save.empty()

func save_on_thread(job):
	var started = OS.get_ticks_msec()
	var filename = job.store.save(job.data,job.filename)
	return {"name":filename,"error":job.store.error,"ms":OS.get_ticks_msec()-started}

func begin_save(job):
	active_save = job
	save_thread = Thread.new()
	if save_thread.start(self,"save_on_thread",job,Thread.PRIORITY_LOW)!=OK:
		save_thread = null
		finish_save({"name":"","error":"Could not start capture writer.","ms":0})

func finish_save(result):
	store.error = result.error
	save_failed = result.name.empty()
	last_save_ms = result.ms
	if not result.name.empty():
		last_saved = result.name
	elif game==null and queued_save.empty():
		capture = active_save.data
	for report in active_save.reports:
		write_round_report(report.round,report.kind,str(active_save.data.id),not result.name.empty())
	if queued_save.empty():
		latest_save = {}
	active_save = {}
	if not queued_save.empty():
		var next = queued_save
		queued_save = {}
		begin_save(next)

func poll_save():
	if save_thread!=null and not save_thread.is_alive():
		var result = save_thread.wait_to_finish()
		save_thread = null
		finish_save(result)

func capture_stage(value):
	if diagnostic_phase==value:
		return
	diagnostic_phase = value
	if not OS.get_user_data_dir().replace("\\","/").ends_with("/GoobplayabilityCouncilWorker"):
		return
	var slot = int(tool.slot) if tool!=null and "slot" in tool else 1
	var file = File.new()
	if file.open("user://capture-stage-"+str(slot)+".json",File.WRITE)==OK:
		file.store_string(JSON.print({"stage":value,"slot":slot,"at":OS.get_unix_time()}))
		file.close()

func persist_capture():
	var started = OS.get_ticks_msec()
	if background_saves():
		var writer = load(get_script().resource_path.get_base_dir().plus_file("ObservedCaptureStore.gd")).new()
		writer.directory = store.directory
		var job = {"data":capture.duplicate(true),"filename":capture_filename,"store":writer,"reports":[]}
		last_snapshot_ms = OS.get_ticks_msec()-started
		# At most one in-flight snapshot and one newer pending snapshot.
		# The newer snapshot contains the older completed rounds as well.
		if not queued_save.empty():
			job.reports = queued_save.reports
		latest_save = job
		if save_thread!=null:
			queued_save = job
		else:
			begin_save(job)
		return ""
	var name = store.save(capture,capture_filename)
	last_save_ms = OS.get_ticks_msec()-started
	if not name.empty():
		last_saved = name
	return name

func report_round(round_data,kind):
	if background_saves() and is_saving() and not latest_save.empty():
		latest_save.reports.append({"round":{"round_id":round_data.round_id,"map":round_data.map.duplicate(),"mode":round_data.mode,"qualification_goal":round_data.get("qualification_goal",0),"qualified_count":round_data.get("qualified_count",0)},"kind":kind})
		return
	write_round_report(round_data,kind,str(capture.id),not last_saved.empty() and store.error.empty())

func write_round_report(round_data,kind,capture_id,saved):
	if not OS.get_user_data_dir().replace("\\","/").ends_with("/GoobplayabilityCouncilWorker"):
		return
	var directory = store.directory.plus_file("reports")
	Directory.new().make_dir_recursive(directory)
	var id = (capture_id+"|"+str(round_data.round_id)+"|"+kind).md5_text()
	var path = directory.plus_file(id+".json")
	if File.new().file_exists(path):
		return
	var record = {"event_id":id,"kind":kind,"map":str(round_data.map.name).substr(0,128),"mode":round_data.mode,"qualified":round_data.get("qualified_count",0),"goal":round_data.get("qualification_goal",0),"saved":saved,"save_error":store.error,"save_ms":last_save_ms,"created_at":OS.get_unix_time()}
	if store.write_json(path+".tmp",record):
		Directory.new().rename(path+".tmp",path)

func reset_quality():
	quality = {"callback_stalls":0,"max_callback_gap_ms":0,"observation_gaps":0,"max_observation_gap_ms":0,"large_alive_steps":0,"events":[],"network_latency_measured":false}
	last_callback_ms = -1
	last_observation_time = -1.0

func note_gap(kind,milliseconds,at):
	var count_key = "callback_stalls" if kind=="callback" else "observation_gaps"
	var max_key = "max_callback_gap_ms" if kind=="callback" else "max_observation_gap_ms"
	quality[max_key] = max(int(quality[max_key]),milliseconds)
	if milliseconds>150:
		quality[count_key] += 1
		if quality.events.size()<64:
			quality.events.append({"kind":kind,"gap_ms":milliseconds,"round":round_key,"time":at})

func _ready():
	store = load(get_script().resource_path.get_base_dir().plus_file("ObservedCaptureStore.gd")).new()

func eligible(current) -> bool:
	if current == null or not is_instance_valid(current) or current.is_server():
		return false
	var local = current.get_local_player()
	return local != null and local.type == NetworkPlayer.SPECTATOR and not current.wp_game_data.is_replay and not current.wp_game_data.is_level_editor

func start() -> bool:
	if not capture.empty() or is_saving():
		return false
	var current = tool._find_game() if tool != null else null
	if not eligible(current):
		status = "Requires a server-assigned spectator. Ordinary players and eliminated racers are not eligible."
		return false
	game = current
	reset_quality()
	capture = {"version":1, "kind":"observed_match_capture", "id":str(OS.get_unix_time()) + "-" + str(OS.get_ticks_usec()), "created_at":OS.get_unix_time(), "game_version":"unknown", "source":"client_samples", "rounds":[]}
	capture["recording_quality"] = quality
	capture_filename = "capture-"+str(capture.id).md5_text()+".json"
	round_key = ""
	samples = 0
	world_samples = 0
	world_bytes = 0
	game.connect("player_hit_finish_line", self, "_finish")
	game.connect("player_eliminated", self, "_eliminated")
	game.connect("game_over",self,"_winner")
	status = "Recording exposed client positions at up to 20 Hz; coverage may be partial."
	return true

func _process(delta):
	poll_save()
	if capture.empty() or game == null:
		return
	var callback_ms = OS.get_ticks_msec()
	if last_callback_ms>=0:
		note_gap("callback",callback_ms-last_callback_ms,float(game.wp_game_data.play_time))
	last_callback_ms = callback_ms
	if not eligible(game):
		stop()
		return
	elapsed += delta
	if elapsed < 0.05:
		return
	elapsed = 0.0
	if game.level.loaded_level == null or not game.is_in_regular_play():
		if not capture.rounds.empty() and not capture.rounds.back().has("analysis_end_time"):
			var end = 0.0
			for track in capture.rounds.back().tracks:
				if not track.samples.empty():
					end = max(end,track.samples.back()[0])
			capture.rounds.back()["analysis_end_time"] = max(0,end-0.05)
		return
	var level = game.level.loaded_level
	var key = str(level.get_instance_id()) + ":" + str(game.wp_game_data.gameplay_round_counter)
	if key != round_key:
		capture_stage("map_geometry")
		if not capture.rounds.empty():
			capture.rounds.back()["completion"] = "round_transition"
			persist_capture()
			report_round(capture.rounds.back(),"map_finished")
		if capture.rounds.size() >= store.MAX_ROUNDS:
			stop()
			return
		round_key = key
		last_observation_time = -1.0
		world_cache = {}
		last_world_time = -1.0
		elimination_times = {}
		var mode = "unknown"
		var count = int(game.wp_game_data.total_start_players)
		if game is WPGame:
			count = int(game.wp_game_data.level_key)
		if count in [8, 16, 32]:
			mode = str(count) + "P"
		if level.level_type == LevelUtils.LevelType.LAST_ONE_STANDING:
			mode = "Elimination"
		var layout = []
		var geometry = []
		for child in level.get_children():
			if child is LevelNode and layout.size() < 12000:
				var rect = child.world_rect
				if rect.size.x > 0 and rect.size.y > 0:
					var node_data = child.serialize_level_node()
					layout.append([str(node_data.get("type","bounds")), rect.position.x, rect.position.y, rect.size.x, rect.size.y, float(node_data.get("shape_rotation",0))])
					capture_geometry(child,str(node_data.get("type","bounds")),geometry)
		capture.rounds.append({"round_id":key, "started_at":OS.get_unix_time(), "map":{"id":str(level.level_id).substr(0,256), "name":str(level.level_name).substr(0,256), "author":str(level.author_name).substr(0,256), "theme":str(level.level_theme).substr(0,256)}, "mode":mode, "layout":layout, "tracks":[]})
		capture.rounds.back()["geometry"] = geometry
		# Preserve the game's artwork and animation definitions, not only fixtures.
		capture_stage("map_artwork_serialization")
		var visual = LevelJson.serialize_level(level)
		if store.valid_level_visual(visual):
			capture.rounds.back()["level_visual"] = visual
		else:
			capture.rounds.back()["visual_capture_error"] = store.validation_error if not store.validation_error.empty() else "Unsupported level value"
		capture_stage("sampling")
	var round_data = capture.rounds.back()
	if game is WPGame:
		round_data["qualification_goal"] = max(0,int(game.wp_game_data.players_qualify))
		round_data["qualified_count"] = max(0,int(game.wp_game_data.players_finished))
	var at = max(0.0, float(game.wp_game_data.play_time))
	if last_observation_time>=0 and at>last_observation_time:
		note_gap("observation",int(round((at-last_observation_time)*1000)),at)
	last_observation_time = at
	if game is WPGame:
		capture_world(round_data,at)
	for index in game.get_player_count():
		var player = game.get_player_at_index(index)
		if not allow_player(player):
			continue
		# An existing native object may outlive the renderer's observable region.
		# Never turn such cached objects into purported fresh observations.
		if game is WPGame and (game.client_renderer == null or game.client_renderer.get_renderer_for_object_id(player.object_id) == null):
			continue
		var id = str(player.object_id)
		var track = _track(id)
		if track.empty():
			if round_data.tracks.size() >= store.MAX_PLAYERS:
				continue
			var metadata = game.get_metadata_for_player(player.object_id)
			track = {"id":id, "name":str(metadata.get("name", "Unknown")).substr(0,256), "outcome":"unknown", "finish_time":-1, "placement":0, "samples":[]}
			var skin = metadata.get("skin",{})
			if skin is Dictionary and store.safe_visual_value(skin,0):
				track["skin"] = skin.duplicate(true)
			round_data.tracks.append(track)
			decorate_track(track,player)
		if not track.samples.empty() and at <= track.samples.back()[0]:
			continue
		if not track.samples.empty() and player.alive and track.samples.back()[5]:
			var previous = track.samples.back()
			if Vector2(previous[1],previous[2]).distance_squared_to(player.position)>10000:
				quality.large_alive_steps += 1
		track.samples.append([at, player.position.x, player.position.y, 0, (1 if player.facing_dir else -1) if player is WPPlayer else 1, bool(player.alive)])
		if game is WPGame:
			if round_data.mode=="Elimination" and player.rank>0:
				track.placement = int(player.rank)
			var renderer = game.client_renderer.get_renderer_for_object_id(player.object_id)
			var spine = renderer.get_node_or_null("Position/SpineHolder/SpineSprite") if renderer != null else null
			if spine != null:
				if not spine.goober_skin_data.empty() and store.safe_visual_value(spine.goober_skin_data,0):
					track["skin"] = spine.goober_skin_data.duplicate(true)
				var entry = spine.get_animation_state().get_current(0)
				if entry != null and entry.get_animation() != null:
					if not track.has("poses"):
						track["poses"] = []
					track.poses.append([at,entry.get_animation().get_name(),entry.get_track_time(),spine.global_rotation,spine.global_scale.x,spine.global_scale.y])
		samples += 1
		if samples >= store.MAX_SAMPLES:
			stop()
			return

func _track(id):
	if not capture.empty() and not capture.rounds.empty():
		for track in capture.rounds.back().tracks:
			if track.id == str(id):
				return track
	return {}

func capture_world(round_data,at):
	# Limit by simulation time as well as wall time (catch-up ticks can run faster).
	if last_world_time>=0 and at-last_world_time<0.049:
		return
	last_world_time = at
	if not round_data.has("world_tracks"):
		round_data["world_tracks"] = {}
	var ordinal = -1
	for node in game.level.loaded_level.get_children():
		if not node is LevelNode:
			continue
		ordinal += 1
		var object = game.get_object_for_object_id(node.network_object_id) if node.network_object_id > 0 else null
		if object == null and node.animation == null:
			continue
		var state = {}
		if node.body != null:
			var pose = node.body.global_transform
			state["pose"] = [pose.x.x,pose.x.y,pose.y.x,pose.y.y,pose.origin.x,pose.origin.y]
		if object != null:
			for field in store.WORLD_FIELDS:
				if field in object:
					var value = object.get(field)
					if value is bool or store.number(value,-50000000,50000000):
						state[field] = value
		var key = str(ordinal)
		var renderer = node.renderer
		if renderer == null:
			renderer = node.get_node_or_null("DisappearingBlockRenderer")
		if renderer != null and node.node_type == "disappearing_block":
			state["visual_alpha"] = renderer.modulate.a
		if renderer != null and node.node_type == "laser" and renderer.has_node("Laser"):
			state["laser_visible"] = renderer.get_node("Laser").visible
			state["laser_length"] = renderer.get_node("Laser").scale.x
			state["laser_glow"] = renderer.get_node("Glow").modulate.a
		if round_data.world_tracks.has(key) and not round_data.world_tracks[key].empty() and at <= round_data.world_tracks[key].back()[0]:
			continue
		var fingerprint = JSON.print(state)
		if world_cache.get(key,"") == fingerprint:
			continue
		if world_samples >= store.MAX_WORLD_SAMPLES or world_bytes+fingerprint.length()+32>33554432:
			round_data["world_truncated"] = true
			return
		world_cache[key] = fingerprint
		if not round_data.world_tracks.has(key):
			round_data.world_tracks[key] = []
		round_data.world_tracks[key].append([at,state])
		world_samples += 1
		world_bytes += fingerprint.length()+32

func allow_player(player) -> bool:
	if player == null or player.type == NetworkPlayer.SPECTATOR:
		return false
	if player is WPPlayer and player.eliminated:
		var id = str(player.object_id)
		return elimination_times.has(id) and float(game.wp_game_data.play_time)-elimination_times[id] < 1.0 and not _track(id).empty()
	return true

func decorate_track(_track_data,_player):
	pass

func capture_geometry(node,kind,output):
	if output.size() >= 12000:
		return
	if node is WPBox2DFixture:
		var points = []
		if node.shape is Box2DPolygonShape:
			points = Array(node.shape.points)
		elif node.shape is Box2DRectShape:
			var half = node.shape.size / 2
			points = [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]
		elif node.shape is Box2DCircleShape:
			for i in 16:
				points.append(Vector2(cos(i*TAU/16),sin(i*TAU/16))*node.shape.radius)
		if points.size() >= 3 and points.size() <= 64:
			var vertices = []
			for point in points:
				var world = node.global_transform.xform(point)
				vertices.append([world.x,world.y])
			output.append({"type":kind,"points":vertices})
	for child in node.get_children():
		capture_geometry(child,kind,output)

func _winner(id):
	if not capture.empty() and not capture.rounds.empty():
		capture.rounds.back()["completion"] = "match_finished"
		capture.rounds.back()["winner"] = str(id)
		capture.rounds.back()["winner_time"] = max(0.0,float(game.wp_game_data.play_time))
	if not capture.empty() and not capture.rounds.empty() and capture.rounds.back().mode == "Elimination":
		var track = _track(id)
		if not track.empty():
			track.outcome = "finish"
			track.placement = 1
			track.finish_time = -1

func _finish(id, rank, _out_of, _line, _position):
	var track = _track(id)
	if not track.empty():
		track.outcome = "finish"
		track.placement = int(rank)
		track.finish_time = max(0.0, float(game.wp_game_data.play_time))
		# The final finish signal can precede the next sampling tick / transition.
		capture.rounds.back()["qualified_count"] = max(int(capture.rounds.back().get("qualified_count",0)),int(rank))

func _eliminated(id):
	var track = _track(id)
	if not track.empty() and track.outcome != "finish":
		track.outcome = "dnf"
		elimination_times[str(id)] = max(0.0,float(game.wp_game_data.play_time))
		var round_data = capture.rounds.back()
		var player = game.get_player_for_object_id(int(id)) if game is WPGame else null
		var confirmed = player!=null and player.eliminated and player.rank>1 and round_data.mode=="Elimination"
		if confirmed:
			track.placement = int(player.rank)
		# Ignore teardown/timeout removals. Only locate observed eliminations.
		if round_data.mode=="Elimination" and round_data.get("completion","")!="match_finished" and (confirmed or game.is_in_regular_play()) and not track.samples.empty():
			var last = track.samples.back()
			if elimination_times[str(id)]-last[0]<=0.15:
				track["eliminated_at"] = elimination_times[str(id)]
				track["death_position"] = [last[1],last[2]]
				track["elimination_confirmed"] = confirmed

func stop():
	if game==null and save_failed and not capture.empty():
		return
	if game != null and is_instance_valid(game):
		for pair in [["player_hit_finish_line", "_finish"], ["player_eliminated", "_eliminated"], ["game_over","_winner"]]:
			if game.is_connected(pair[0], self, pair[1]):
				game.disconnect(pair[0], self, pair[1])
	game = null
	if capture.empty():
		return
	if capture.rounds.empty():
		capture = {}
		status = "No observable rounds were received."
		return
	var name = persist_capture()
	if capture.rounds.back().get("completion","")=="match_finished":
		report_round(capture.rounds.back(),"match_finished")
	if background_saves() and is_saving():
		capture = {}
		status = "Finalizing replay in background…"
		return
	status = "Saved " + name if not name.empty() else store.error + " Capture retained; retry saving."
	if not name.empty():
		last_saved = name
		capture = {}

func _exit_tree():
	stop()
	# Explicit shutdown waits for local IO, never abandons a writer or frees
	# its owner while the thread is still running.
	while save_thread!=null:
		var result = save_thread.wait_to_finish()
		save_thread = null
		finish_save(result)
