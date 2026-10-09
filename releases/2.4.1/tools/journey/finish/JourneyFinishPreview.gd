extends Control
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Isolated rendering only: no started game, network, qualification or XP.
# Terrain, hazards, finish lines and background come from the real game.
const RUN = 2.4
const SHOW = 10.0
const COUNT = 5.0
const FADE = 1.3
var finish = {}
var skin = {}
var big
var small
var viewport
var world
var level
var review_game
var runner
var player
var phase = "idle"
var clock = 0.0
var shade = 0.0
var banner = 0.0
var unit = 50.0
var anchor = Vector2(575,-700)
var studio
var top
var error = ""
var height_units = 14.0
var fitted_size = Vector2.ZERO

func setup(_base, data, look, height, font_big, font_small):
	finish = data
	skin = look.duplicate(true)
	big = font_big
	small = font_small
	var choreography = load(ModPaths.path(str(finish.script))).new()
	height_units = max(14.0,float(choreography.preview_units()) if choreography.has_method("preview_units") else 14.0)
	rect_min_size = Vector2(0,height)
	rect_clip_content = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder = ViewportContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.stretch = true
	add_child(holder)
	holder.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	viewport = Viewport.new()
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	holder.add_child(viewport)
	world = Node2D.new()
	viewport.add_child(world)
	top = Control.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	top.connect("draw",self,"_draw_top")
	call_deferred("_load_showcase")

func _load_showcase():
	var file = File.new()
	if file.open(ModPaths.path("finish-showcase.json"),File.READ)!=OK:
		error = "Showcase level unavailable"
		top.update()
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error!=OK or not parsed.result is Dictionary:
		error = "Showcase level could not be loaded"
		top.update()
		return
	var factory = LevelNodeFactory.new()
	factory._load_nodes(false)
	# The engine's terrain requires a Box2D/native-game context even for
	# artwork. Same unstarted review context as Replay Hub: never start_game.
	# Install siblings before _ready resolves renderer paths.
	viewport.remove_child(world)
	world.name = "ReviewContext"
	review_game = load("res://nodes/WPGame.tscn").instance()
	review_game.set_meta("goobplayability_review_only",true)
	review_game.type = 1
	review_game.client_renderer_path = NodePath("../ReviewRenderer")
	world.add_child(review_game)
	var renderer_context = NetworkGameRenderer.new()
	renderer_context.name = "ReviewRenderer"
	renderer_context.game_path = NodePath("../WPGame")
	world.add_child(renderer_context)
	level = review_game.get_node("Level")
	level.load_themes = true
	# Preview visibility is not a global hide-level setting.
	var binding = level.get_node("LinkVisibilityToSetting")
	level.remove_child(binding)
	binding.free()
	viewport.add_child(world)
	level.visible = true
	review_game.set_process(false)
	review_game.set_physics_process(false)
	review_game.wp_game_data.gameplay_state = WPGameData.GameplayState_LEVEL_PLAY
	# load_themes must be set before ready (WPGame entered above).
	if level.theme_loader==null: level.theme_loader = LevelThemeLoader.new()
	var instance = LevelJson.deserialize_level(parsed.result,factory)
	level.loaded_level.free()
	level.loaded_level = instance
	level.add_child(instance)
	level._parse_level_nodes()
	for node in instance.get_children():
		node.emit_signal("apply_bounding_box")
		# Native editor objects otherwise cull against the live match camera.
		if node.renderer != null:
			if "enable_off_screen_visibility" in node.renderer: node.renderer.enable_off_screen_visibility = false
			node.renderer.show()
	level.set_level_theme(level.theme_loader.load_theme(instance.level_theme))
	level.emit_signal("loaded_level")
	var background = load("res://project_specific/background/Background.tscn").instance()
	# Both are direct Viewport children; an absolute path is stable here.
	background.set("_level",level.get_path())
	background.set("_game",NodePath(""))
	viewport.add_child(background)
	background.apply_theme(level.level_theme)
	# Cosmetic actors draw above the native PolygonTerrain z-index.
	world.z_index = 0
	_fit()
	restart()

func _fit():
	if viewport==null or rect_size.y<20 or fitted_size==rect_size: return
	# Keep the central platform readable and leave headroom for UFO/portal
	# outros. No letterboxing or stretched textures on wider windows.
	fitted_size = rect_size
	var scale_value = rect_size.y/(height_units*unit)
	var origin = Vector2(rect_size.x*.54,rect_size.y*.86)-anchor*scale_value
	viewport.canvas_transform = Transform2D(Vector2(scale_value,0),Vector2(0,scale_value),origin)

func restart(_arg = null):
	if not is_instance_valid(level): return
	if is_instance_valid(player): player.queue_free()
	player = null
	if not is_instance_valid(runner):
		runner = load(ModPaths.path("JourneyFinishPuppet.gd")).new()
		runner.skin = skin.duplicate(true)
		runner.size = unit
		runner.z_index = 200
		world.add_child(runner)
		_apply_look(runner)
	runner.visible = true
	runner.position = Vector2(-375,anchor.y)
	phase = "run"
	clock = 0.0
	shade = 0.0
	banner = 0.0
	_fit()

func _apply_look(actor):
	if is_instance_valid(studio) and is_instance_valid(actor.spine):
		studio._render_look(actor.spine,studio.capture())
		actor._bind()

func skip(_arg = null):
	if phase=="loop": _countdown()

func _process(delta):
	if not is_visible_in_tree() or not is_instance_valid(runner): return
	_fit()
	delta = min(delta,.1)
	clock += delta
	banner = max(0.0,banner-delta*.7)
	match phase:
		"run":
			var u = clamp(clock/RUN,0.0,1.0)
			var x = lerp(-375.0,anchor.x,u)
			if runner.position.x<300 and x>=300: banner = 1.0
			runner.clear_pose()
			runner.position = Vector2(x,anchor.y)
			# Cosmetic approach follows the real showcase's small pit gap.
			if x>-250 and x<225:
				runner.position.y -= sin(clamp((x+250)/475.0,0,1)*PI)*230.0
			runner.anim = "Run" if u<.94 else "Idle"
			runner.facing = 1.0
			runner.step(delta)
			if clock>=RUN: _start()
		"loop":
			if clock>=SHOW: _countdown()
		"count":
			var left = COUNT-clock
			shade = clamp((FADE-left)/.7,0,1)
			if left<=0:
				phase = "dark"
				clock = 0.0
		"dark":
			shade = 1.0 if clock<.7 else clamp(1.0-(clock-.7)/.5,0,1)
			if clock>=1.6: restart()
	if runner.visible and phase!="run":
		runner.clear_pose()
		runner.anim = "Idle"
		runner.step(delta)
	top.update()

func _start():
	runner.visible = false
	player = load(ModPaths.path("JourneyFinishPlayer.gd")).new()
	player.position = anchor
	player.z_index = 200
	world.add_child(player)
	player.setup(load(ModPaths.path(str(finish.script))).new(),skin,unit)
	_apply_look(player.puppet)
	player.connect("finished",self,"_done")
	phase = "loop"
	clock = 0.0

func _countdown():
	phase = "count"
	clock = 0.0
	if is_instance_valid(player): player.request_outro(COUNT-FADE)

func _done():
	if is_instance_valid(player) and not player.choreo.keep_hidden_after():
		runner.visible = true
		player.queue_free()
		player = null

func _draw_top():
	if small==null: return
	if not error.empty():
		_draw_text(error,small,rect_size.y*.5,Color.white)
	if banner>0:
		_draw_text("QUALIFIED!",big,80,Color(1,1,1,banner))
	if phase=="count":
		_draw_text("NEXT ROUND IN %d" % max(0,int(ceil(COUNT-clock))),small,44,Color.white)
	if shade>0: top.draw_rect(Rect2(Vector2.ZERO,rect_size),Color(0,.035,.09,shade))

func _draw_text(value,font,y,color):
	top.draw_string(font,Vector2((rect_size.x-font.get_string_size(value).x)*.5,y),value,color)
