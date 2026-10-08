extends Control

# Presentation only: never restores inputs, velocities, or game objects.
var tracks = []
var layout = []
var geometry = []
var selected = []
var time = 0.0
var duration = 0.0
var playing = false
var overview = false
var hotspots = []
var zoom_factor = 1.0
var pan = Vector2.ZERO
var phase = 0.0
var dragging = false
var native_view = null
var native_level = null
var review_game = null
var native_background = null
var visual_status = "Legacy capture · collision view"
var decoration_players = []
var saw_spins = []
var last_visual_time = -1.0
var speed = 1.0
var world_tracks = {}
var avatars = {}
var show_names = true
var name_font = null
var analysis_end = 0.0
var bounds = Rect2(Vector2.ZERO, Vector2.ONE)
var frame_signature = ""
var follow_id = ""
var rendered_frames = 0
var result_data = {}
var death_effects = []
const COLORS = [Color("55d9bb"), Color("ffc66d"), Color("72b6ff"), Color("f48e93")]

func _ready():
	# Changing clipping from _draw schedules another draw in Godot 3.
	# Configure it once, outside the rendering callback.
	rect_clip_content = true

func configure(round_data):
	result_data = round_data
	frame_signature = ""
	follow_id = ""
	tracks = round_data.tracks
	world_tracks = round_data.get("world_tracks",{})
	layout = round_data.get("layout", [])
	geometry = round_data.get("geometry",[])
	selected = []
	duration = 0.0
	var first = true
	for track in tracks:
		selected.append(track.id)
		for sample in track.samples:
			var point = Vector2(sample[1], sample[2])
			if first:
				bounds = Rect2(point, Vector2.ONE)
				first = false
			else:
				bounds = bounds.expand(point)
			duration = max(duration, sample[0])
	bounds = bounds.grow(40)
	for shape in layout:
		if not str(shape[0]).begins_with("background"):
			bounds = bounds.expand(Vector2(shape[1],shape[2]))
			bounds = bounds.expand(Vector2(shape[1]+shape[3],shape[2]+shape[4]))
	time = 0.0
	analysis_end = float(round_data.get("analysis_end_time",max(0,duration-0.25)))
	death_effects = load(get_script().resource_path.get_base_dir().plus_file("ObservedOverview.gd")).new().episodes(tracks,analysis_end)
	if round_data.has("winner_time"):
		# Signals can arrive between the last observation and the next 20 Hz sample.
		if float(round_data.winner_time)<=duration+0.3:
			duration = float(round_data.winner_time)
	playing = false
	zoom_factor = 1.0
	pan = Vector2.ZERO
	build_native(round_data.get("level_visual",{}))
	if native_view==null:
		visual_status = "Simplified view · " + str(round_data.get("visual_capture_error","detailed level data missing or unsupported"))
	if bool(round_data.get("world_truncated",false)):
		visual_status = "Partial object states · recording limit reached"
	if native_view != null:
		for track in tracks:
			var goober = load("res://project_specific/gfx/spine/upguy/upguy.tscn").instance()
			goober.enable_sounds = false
			goober.enable_blink = false
			goober.apply_defaults = true
			goober.z_index = 200
			native_view.add_child(goober)
			goober.scale = Vector2.ONE*0.04
			goober.set_goober_skin_data(track.get("skin",{"color":"color_default"}))
			goober.get_animation_state().set_animation("Idle",true,0)
			goober.get_animation_state().set_time_scale(0)
			goober.set_meta("review_animation","Idle")
			avatars[track.id] = goober
	var analytics = load(get_script().resource_path.get_base_dir().plus_file("ObservedOverview.gd")).new()
	hotspots = analytics.clusters(analytics.episodes(tracks,analysis_end))
	mouse_filter = Control.MOUSE_FILTER_STOP
	hint_tooltip = "Drag to pan; mouse wheel to zoom. New captures retain observed object states and avatar poses. Client coverage is not an authoritative server replay. Old captures cannot recover unrecorded interactions."
	update()

func position_at(samples, at):
	# Binary search; no extrapolation or interpolation across missing observations.
	var low = 0
	var high = samples.size() - 1
	var found = -1
	while low <= high:
		var middle = (low + high) / 2
		if samples[middle][0] <= at:
			found = middle
			low = middle + 1
		else:
			high = middle - 1
	if found < 0 or at - samples[found][0] > 0.15 or not samples[found][5]:
		return null
	var point = Vector2(samples[found][1], samples[found][2])
	if found + 1 < samples.size():
		var next = samples[found+1]
		var gap = next[0] - samples[found][0]
		var target = Vector2(next[1],next[2])
		# Smooth ordinary observations, never bridge death, gaps or teleports.
		if next[5] and gap <= 0.15 and point.distance_to(target) <= 100:
			return point.linear_interpolate(target,clamp((at-samples[found][0])/gap,0,1))
	return point

func visual_pose_at(poses,index,at):
	var pose = poses[index]
	if pose.size()!=6 or index+1>=poses.size():
		return pose
	var next = poses[index+1]
	var gap = next[0]-pose[0]
	if next.size()!=6 or next[1]!=pose[1] or gap<=0 or gap>0.15 or sign(pose[4])!=sign(next[4]) or sign(pose[5])!=sign(next[5]):
		return pose
	var result = pose.duplicate()
	var weight = clamp((at-pose[0])/gap,0,1)
	result[3] = lerp_angle(pose[3],next[3],weight)
	result[4] = lerp(pose[4],next[4],weight)
	result[5] = lerp(pose[5],next[5],weight)
	return result

func build_native(data):
	if native_view != null:
		remove_child(native_view)
		native_view.queue_free()
	native_view = null
	native_level = null
	review_game = null
	native_background = null
	avatars = {}
	decoration_players = []
	saw_spins = []
	last_visual_time = -1.0
	visual_status = "Legacy capture · collision view"
	var validator = load(get_script().resource_path.get_base_dir().plus_file("ObservedCaptureStore.gd")).new()
	if not validator.valid_level_visual(data):
		return
	var factory = LevelNodeFactory.new()
	factory._load_nodes(false)
	# Only built-in factory types can be instantiated; capture strings are never paths.
	var safe = data.duplicate(true)
	safe.nodes = []
	for node in data.nodes:
		if factory.scene_cache.has(node.type):
			safe.nodes.append(node)
	native_view = Viewport.new()
	native_view.disable_3d = true
	native_view.world_2d = World2D.new()
	native_view.transparent_bg = false
	native_view.render_target_v_flip = true
	native_view.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(native_view)
	# Use the complete native context required by special-object renderers.
	# Never start_game: this container has no connection, input or simulation loop.
	var context = Node2D.new()
	context.name = "ReviewContext"
	review_game = load("res://nodes/WPGame.tscn").instance()
	review_game.set_meta("goobplayability_review_only",true)
	review_game.type = 1
	review_game.client_renderer_path = NodePath("../ReviewRenderer")
	context.add_child(review_game)
	var renderer_context = NetworkGameRenderer.new()
	renderer_context.name = "ReviewRenderer"
	renderer_context.game_path = NodePath("../WPGame")
	context.add_child(renderer_context)
	native_level = review_game.get_node("Level")
	native_level.load_themes = true
	native_view.add_child(context)
	review_game.set_process(false)
	review_game.set_physics_process(false)
	review_game.wp_game_data.is_level_editor = false
	review_game.wp_game_data.gameplay_state = WPGameData.GameplayState_LEVEL_PLAY
	var instance = LevelJson.deserialize_level(safe,factory)
	# Level.load_level unloads network objects and expects a live WPGame.
	# Review owns no game: install artwork without that gameplay lifecycle.
	native_level.loaded_level.free()
	native_level.loaded_level = instance
	native_level.add_child(instance)
	native_level._parse_level_nodes()
	for node in instance.get_children():
		# Renderers connect their sizing signals in _ready, after deserialization.
		# Re-apply the native bounds once those connections exist.
		node.emit_signal("apply_bounding_box")
		var renderer = node.renderer
		if renderer == null:
			renderer = node.get_node_or_null("DisappearingBlockRenderer")
		if renderer != null and node.node_type in ["disappearing_block","laser"]:
			renderer.set_process(false)
			renderer.set_process_internal(false)
		if renderer != null and node.node_type == "music_block":
			# The native music renderer's physics callback requires a live game.
			renderer.set_physics_process(false)
			renderer.set_physics_process_internal(false)
			renderer.set_process_internal(false)
		if renderer != null:
			if "enable_off_screen_visibility" in renderer:
				renderer.enable_off_screen_visibility = false
			if node.node_type == "physics_block":
				renderer.set_process(false)
			renderer.show()
	native_level.set_level_theme(native_level.theme_loader.load_theme(instance.level_theme))
	native_level.emit_signal("loaded_level")
	for node in instance.get_children():
		var artwork = artwork_for(node)
		if node.body!=null and artwork!=null:
			node.set_meta("review_art_rest",artwork.global_transform)
			node.set_meta("review_body_rest",node.body.global_transform)
	bounds = bounds.merge(native_level.aabb).grow(30)
	collect_decorations(instance)
	native_background = load("res://project_specific/background/Background.tscn").instance()
	native_background._level = NodePath("../ReviewContext/WPGame/Level")
	native_view.add_child(native_background)
	native_background.level = native_level
	native_background.apply_theme(native_level.level_theme)
	native_background.set_process(false)
	visual_status = "Recorded object states" if not world_tracks.empty() else "Legacy capture · object interactions not recorded"

func collect_decorations(node):
	if node is AnimationPlayer and not node.current_animation.empty():
		decoration_players.append([node,node.current_animation])
		node.stop(false)
	if node is LevelNode and node.node_type == "sawblade":
		var renderer = node.get_node_or_null("Renderer")
		if renderer != null and renderer.has_node("Spin"):
			renderer._process(0.0)
			renderer.set_process(false)
			saw_spins.append(renderer.get_node("Spin"))
	for child in node.get_children():
		collect_decorations(child)

func seek_native():
	if native_level == null or last_visual_time == time:
		return
	last_visual_time = time
	review_game.wp_game_data.play_time = time
	for node in native_level.animated_nodes:
		var old_position = node.animation.position
		var old_rotation = node.animation.rotation
		node.animation.seek(time,1.0/60.0,node.body,true)
		node.position += node.animation.position-old_position
		node.rotation += node.animation.rotation-old_rotation
		if node.body != null:
			node.body.global_transform = node.global_transform
	for entry in decoration_players:
		var animation = entry[0].get_animation(entry[1])
		entry[0].assigned_animation = entry[1]
		entry[0].seek(fposmod(time,animation.length) if animation.loop and animation.length > 0 else min(time,animation.length),true)
	for spin in saw_spins:
		spin.rotation = time * 0.33 * TAU
	for key in world_tracks:
		var states = world_tracks[key]
		var index = state_index(states,time)
		if index < 0 or int(key)>=native_level.loaded_level.get_child_count():
			continue
		var node = native_level.loaded_level.get_child(int(key))
		var state = states[index][1]
		apply_special_visual(node,state)
		var object = review_game.get_object_for_object_id(node.network_object_id) if node.network_object_id>0 else null
		for field in state:
			if field != "pose" and object != null and field in object:
				object.set(field,state[field])
		if state.has("pose") and node.body != null:
			var pose = state.pose
			var transform = Transform2D(Vector2(pose[0],pose[1]),Vector2(pose[2],pose[3]),Vector2(pose[4],pose[5]))
			if index+1<states.size() and states[index+1][1].has("pose"):
				var gap = states[index+1][0]-states[index][0]
				var next = states[index+1][1].pose
				var next_transform = Transform2D(Vector2(next[0],next[1]),Vector2(next[2],next[3]),Vector2(next[4],next[5]))
				if gap>0 and gap<=0.15 and transform.origin.distance_to(next_transform.origin)<100:
					transform = transform.interpolate_with(next_transform,clamp((time-states[index][0])/gap,0,1))
			node.body.global_transform = transform
			if artwork_for(node) != null:
				apply_art_pose(node,transform)

func artwork_for(node):
	return node.renderer if node.renderer!=null else node.get_node_or_null("DisappearingBlockRenderer")

func apply_art_pose(node,pose):
	if not node.has_meta("review_art_rest"):
		return
	var art = node.get_meta("review_art_rest")
	var body = node.get_meta("review_body_rest")
	# Apply a rigid motion to the original artwork basis. Separate rotation/scale
	# setters decompose a nonuniform parent transform and can accumulate shear.
	var motion = Transform2D(pose.get_rotation()-body.get_rotation(),Vector2.ZERO)
	motion.origin = pose.origin-motion.basis_xform(body.origin)
	var artwork = artwork_for(node)
	if artwork!=null:
		artwork.global_transform = motion*art

func apply_special_visual(node,state):
	var renderer = node.renderer
	if renderer==null:
		renderer = node.get_node_or_null("DisappearingBlockRenderer")
	if renderer==null:
		return
	renderer.show()
	if node.node_type=="disappearing_block":
		var alpha = float(state.get("visual_alpha",1.0))
		if not state.has("visual_alpha"):
			var counter = float(state.get("disappearing_counter",0))
			var absent_ticks = review_game.time_to_ticks(review_game.wp_game_data.disappearing_block_reappear_after)
			if counter>0 and counter<=absent_ticks:
				alpha = renderer.not_there_color.a
		renderer.modulate.a = clamp(alpha,0,1)
	elif node.node_type=="laser" and renderer.has_node("Laser"):
		var active = false
		var glow = 0.0
		var charge = review_game.wp_game_data.laser_charge_ticks
		var pause = int(state.get("pause_duration_ticks",0))
		var duration_ticks = max(charge,int(state.get("lasing_duration_ticks",charge)))
		var tick = review_game.time_to_ticks(time)
		var cycle = (tick+int(state.get("timing_offset",0))) % max(1,duration_ticks+pause)
		active = pause==0 or cycle>=pause+charge
		glow = 1.0 if active else (0.7 if cycle>=pause else 0.0)
		renderer.get_node("Laser").visible = bool(state.get("laser_visible",active))
		renderer.get_node("Glow").modulate.a = clamp(float(state.get("laser_glow",glow)),0,1)
		if state.has("laser_length"):
			renderer.get_node("Laser").scale.x = state.laser_length
		elif state.has("raycast_length"):
			renderer.get_node("Laser").scale.x = state.raycast_length+5+renderer.get_node("Laser").scale.y*2
		var total_length = renderer.get_node("Laser").scale.x-renderer.get_node("Laser").scale.y*2
		renderer.get_node("Glow").scale.x = total_length+renderer.get_node("Glow").scale.y*2
		if renderer.has_node("Sight"):
			renderer.get_node("Sight").scale.x = total_length+renderer.get_node("Sight").scale.y*2+4
		if renderer.has_node("Particles2D"):
			renderer.get_node("Particles2D").emitting = false

func state_index(states,at):
	var low = 0
	var high = states.size()-1
	var found = -1
	while low <= high:
		var middle = (low+high)/2
		if states[middle][0]<=at:
			found = middle
			low = middle+1
		else:
			high = middle-1
	return found

func _process(delta):
	if not is_visible_in_tree():
		frame_signature = ""
		if native_view != null:
			native_view.render_target_update_mode = Viewport.UPDATE_DISABLED
		return
	if playing and is_visible_in_tree():
		time = min(time + delta * speed, duration)
		if time >= duration:
			playing = false
		update()
	if not follow_id.empty():
		for track in tracks:
			if track.id==follow_id:
				var point = display_position(track,time)
				if point!=null:
					pan += rect_size*0.5-project(point)
				break
	var signature = str([time,rect_size,zoom_factor,pan,selected,show_names])
	if native_view != null and frame_signature != signature:
		frame_signature = signature
		rendered_frames += 1
		native_view.render_target_update_mode = Viewport.UPDATE_ONCE
		var factor = min((rect_size.x-20)/max(1,bounds.size.x),(rect_size.y-20)/max(1,bounds.size.y))*zoom_factor
		native_view.size = Vector2(max(2,rect_size.x),max(2,rect_size.y))
		native_view.canvas_transform = Transform2D(Vector2(factor,0),Vector2(0,factor),project(Vector2.ZERO))
		if is_visible_in_tree():
			seek_native()
			native_background._process(0.0)
			for track in tracks:
				var goober = avatars.get(track.id)
				if goober == null:
					continue
				var point = display_position(track,time)
				goober.visible = point != null and selected.has(track.id)
				if point != null:
					goober.position = point+Vector2(0,40)
					var index = state_index(track.samples,time)
					goober.scale.x = -abs(goober.scale.x)*track.samples[index][4]
					var pose_index = state_index(track.get("poses",[]),time)
					if pose_index >= 0:
						var pose = visual_pose_at(track.poses,pose_index,time)
						if death_visible(track,time):
							pose = [time,"Death",max(0,time-track.eliminated_at)]
						if pose.size()==6:
							goober.rotation = pose[3]
							goober.scale = Vector2(pose[4],pose[5])
						if pose[1] != goober.get_meta("review_animation"):
							goober.get_animation_state().clear_tracks()
							goober.get_animation_state().set_animation(pose[1],pose[1] in ["Idle","Run","MovingUp","Fall","WallSlide"],0).set_mix_duration(0)
							goober.set_meta("review_animation",pose[1])
						var entry = goober.get_animation_state().get_current(0)
						if entry != null:
							entry.set_track_time(pose[2]+min(0.15,max(0,time-pose[0])))
					goober.get_skeleton().set_to_setup_pose()
					# Setup pose resets the gradient shader's slot-color coordinates.
					goober.apply_gradient_tint()
					goober.update_skeleton(0.0)
		update()
	if overview and is_visible_in_tree():
		phase = fmod(phase + delta * 3.0, PI * 2)
		update()

func project(point):
	var factor = min((rect_size.x - 20) / max(1, bounds.size.x), (rect_size.y - 20) / max(1, bounds.size.y))
	return (point - bounds.position - bounds.size * 0.5) * factor * zoom_factor + rect_size * 0.5 + pan

func death_visible(track,at):
	return track.has("eliminated_at") and (track.get("elimination_confirmed",false) or track.eliminated_at<analysis_end) and at>=track.eliminated_at and at<track.eliminated_at+0.8

func display_position(track,at):
	if death_visible(track,at):
		return Vector2(track.death_position[0],track.death_position[1])
	var point = position_at(track.samples,at)
	if point != null:
		return point
	if at>=duration and result_data.get("completion","") in ["match_finished","round_transition"]:
		for i in range(track.samples.size()-1,-1,-1):
			var sample = track.samples[i]
			if at-sample[0]>0.3:
				break
			if sample[5] and sample[0]<=at:
				return Vector2(sample[1],sample[2])
	var pose_index = state_index(track.get("poses",[]),at)
	if pose_index < 0 or track.poses[pose_index][1] != "Death" or at >= analysis_end:
		return null
	var index = state_index(track.samples,at)
	if index < 0 or at-track.samples[index][0]>0.15:
		return null
	return Vector2(track.samples[index][1],track.samples[index][2])

func _gui_input(event):
	if event is InputEventMouseButton and event.control:
		return
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			var old = zoom_factor
			zoom_factor = clamp(old * (1.15 if event.button_index == BUTTON_WHEEL_UP else 1.0 / 1.15), 0.25, 16.0)
			pan = event.position - rect_size * 0.5 - (event.position - rect_size * 0.5 - pan) * zoom_factor / old
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		if event.button_mask & BUTTON_MASK_LEFT:
			follow_id = ""
			pan += event.relative
		else:
			dragging = false
		accept_event()
	update()

func _draw():
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color("15212b"))
	if native_view != null:
		draw_texture_rect(native_view.get_texture(),Rect2(Vector2.ZERO,rect_size),false)
	# Clip overlays/panning to the review viewport, never over other UI controls.
	for polygon in geometry if native_view == null else []:
		var points = PoolVector2Array()
		for point in polygon.points:
			points.append(project(Vector2(point[0],point[1])))
		var color = Color("516879")
		if polygon.type in ["pit","sawblade","laser"]:
			color = Color("cb7a77")
		elif polygon.type in ["finish_line","start","checkpoint"]:
			color = Color("6bb89f")
		draw_colored_polygon(points,color)
	# Schematic bounds only, not collision geometry or animated object states.
	for shape in layout if geometry.empty() and native_view == null else []:
		var start = project(Vector2(shape[1], shape[2]))
		var end = project(Vector2(shape[1] + shape[3], shape[2] + shape[4]))
		var color = Color("526b7b")
		if shape[0] in ["pit","sawblade","laser"]:
			color = Color("c67371")
		elif shape[0] in ["start","finish_line","checkpoint"]:
			color = Color("61b59c")
		elif str(shape[0]).begins_with("background"):
			color = Color(0.25,0.35,0.42,0.2)
		if shape[0] == "sawblade":
			draw_circle((start+end)*0.5,max(1.0,(end.x-start.x)*0.5),color)
		else:
			draw_rect(Rect2(start, end - start), color, shape[0] != "bounds")
	for index in tracks.size():
		var track = tracks[index]
		if not selected.has(track.id):
			continue
		var point = position_at(track.samples, time)
		if point != null and not avatars.has(track.id):
			var marker = project(point)
			draw_circle(marker,8,Color("17242e"))
			draw_circle(marker,6,COLORS[index % COLORS.size()])
			draw_circle(marker+Vector2(-2,-1),1.3,Color("17242e"))
			draw_circle(marker+Vector2(2,-1),1.3,Color("17242e"))
			if track.outcome == "finish" and track.placement > 0 and track.placement <= 3 and track.finish_time >= 0 and time >= track.finish_time:
				var center = project(point) + Vector2(0,-15)
				var tint = [Color("ffd166"),Color("c9d7e3"),Color("d89b72")][int(track.placement)-1]
				draw_colored_polygon(PoolVector2Array([center+Vector2(-8,4),center+Vector2(-10,-5),center+Vector2(-3,-1),center+Vector2(0,-8),center+Vector2(3,-1),center+Vector2(10,-5),center+Vector2(8,4)]),tint)
	# Timeline-driven presentation only: scrubbing cannot spawn physics bodies
	# or replay death events into the live game. Use the same conservative
	# observed episodes as analysis, excluding end-of-round removals.
	for event in death_effects:
		var age = time-float(event.time)
		if age<0 or age>0.55 or not selected.has(event.player):
			continue
		var center = project(event.position)
		var fade = 1.0-age/0.55
		for particle in range(8):
			var angle = particle*TAU/8.0
			var offset = Vector2(cos(angle),sin(angle))*(6+age*55)+Vector2(0,age*age*55)
			draw_circle(center+offset,max(0.5,3*fade),Color(0.9,0.95,1.0,fade))
	if overview:
		for hotspot in hotspots:
			var point = project(hotspot.position)
			var radius = min(32.0, 10.0 + sqrt(float(hotspot.count)) * 6.0)
			draw_circle(point, radius + sin(phase) * 2, Color(0.98, 0.36, 0.32, 0.14))
			draw_circle(point, 7, Color("f48e93"))
			draw_rect(Rect2(point + Vector2(-4,3), Vector2(8,6)), Color("f48e93"))
			draw_circle(point + Vector2(-2.5,-1), 1.6, Color("15212b"))
			draw_circle(point + Vector2(2.5,-1), 1.6, Color("15212b"))
	if show_names and name_font != null:
		var occupied = []
		for track in tracks:
			var point = display_position(track,time)
			if point == null or not selected.has(track.id):
				continue
			var title = track.name.substr(0,24)
			var width = name_font.get_string_size(title).x
			var origin = project(point)+Vector2(-width/2,-20)
			var label_rect = Rect2(origin-Vector2(4,name_font.get_ascent()),Vector2(width+8,name_font.get_height()+3))
			for attempt in 5:
				var overlaps = false
				for other in occupied:
					if label_rect.intersects(other):
						overlaps = true
						break
				if not overlaps:
					break
				origin.y -= name_font.get_height()+5
				label_rect.position.y -= name_font.get_height()+5
			var blocked = false
			for other in occupied:
				blocked = blocked or label_rect.intersects(other)
			if blocked:
				continue
			if not Rect2(Vector2.ZERO,rect_size).has_point(origin+Vector2(width/2,0)):
				continue
			var games = track.get("profile",{}).get("games",-1)
			var color = Color("97a9b6") if games < 0 else (Color("ffd166") if games>=1000 else Color("72d9bd"))
			occupied.append(label_rect)
			draw_line(project(point),origin+Vector2(width/2,3),Color(0.7,0.8,0.85,0.35),1,true)
			draw_rect(label_rect,Color(0.05,0.08,0.11,0.85))
			draw_string(name_font,origin,title,color)

	if time>=duration and duration>0 and name_font!=null:
		var results = []
		for track in tracks:
			if track.placement>0:
				results.append(track)
		results.sort_custom(self,"rank_order")
		var title = "Round complete" if result_data.get("completion","") in ["match_finished","round_transition"] else "Capture ended · partial"
		var height = min(rect_size.y-12,42+results.size()*24)
		draw_rect(Rect2(6,6,min(310,rect_size.x-12),height),Color(0.04,0.07,0.1,0.93))
		draw_string(name_font,Vector2(16,30),title,Color("9dd6bd"))
		for i in results.size():
			if 54+i*24>height:
				break
			var track = results[i]
			var winner = result_data.get("winner","")==track.id
			draw_string(name_font,Vector2(16,54+i*24),("WINNER · " if winner else "#%d · " % track.placement)+track.name.substr(0,22),Color("ffd166") if track.placement==1 else Color("d8e8ee"))

func rank_order(a,b):
	return a.placement<b.placement

func _get_tooltip(position):
	var result = []
	for track in tracks:
		var point = display_position(track,time)
		if point != null and selected.has(track.id) and project(point).distance_to(position)<22:
			var profile = track.get("profile",{})
			result.append("%s · games %s · wins %s · level %s" % [track.name,str(profile.get("games","?")),str(profile.get("wins","?")),str(profile.get("level","?"))])
	return PoolStringArray(result).join("\n")
