extends SceneTree
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Journey finish animations: renders contact sheets with the real Goober rig.
# Run RunFinishCapture.bat; sheets land in mod/finish-captures/.
const CHOREOS = ["Dance", "StarRide", "TinyGoobers", "RocketRide"]
const DT = 1.0 / 30.0
var base = "user://mod/tools/journey"
var out = "user://mod/finish-captures"
var vp

func _initialize():
	if not Directory.new().file_exists(ModPaths.path("JourneyFinishPlayer.gd")):
		base = "res://mod"
		out = "res://finish-captures"
	Directory.new().make_dir_recursive(out)
	vp = Viewport.new()
	vp.size = Vector2(800, 600)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	vp.render_target_v_flip = true
	root.add_child(vp)
	var bg = ColorRect.new()
	bg.rect_size = Vector2(800, 600)
	bg.color = Color("7ec8f5")
	vp.add_child(bg)
	var ground = ColorRect.new()
	ground.rect_position = Vector2(0, 540)
	ground.rect_size = Vector2(800, 60)
	ground.color = Color("3f9e4d")
	vp.add_child(ground)
	call_deferred("_run")

func _run():
	yield(_faces(), "completed")
	for name in CHOREOS:
		yield(_capture(name), "completed")
	print("Finish captures saved to ", ProjectSettings.globalize_path(out))
	quit()

# Face check: normal / both eyes shut / wink, large.
func _faces():
	var sheet = []
	for face in ["normal", "wince", "wink"]:
		var p = load(ModPaths.path("JourneyFinishPuppet.gd")).new()
		p.size = 420.0
		p.position = Vector2(400, 560)
		vp.add_child(p)
		for i in range(4):
			p.clear_pose()
			p.face = face
			p.step(DT)
			yield(VisualServer, "frame_post_draw")
		var img = vp.get_texture().get_data()
		img.resize(400, 300)
		sheet.append(img)
		p.queue_free()
		yield(self, "idle_frame")
	_save("faces", sheet)

func _capture(name):
	var player = load(ModPaths.path("JourneyFinishPlayer.gd")).new()
	player.position = Vector2(400, 540)
	player.set_process(false)
	vp.add_child(player)
	player.setup(load(ModPaths.path("JourneyFinish%s.gd" % name)).new(), {}, 95.0, 7)
	var frames = {"intro": [], "loop": [], "outro": []}
	var every = {"intro": 0.2, "loop": 0.4, "outro": 0.2}
	var next_shot = 0.0
	var last_state = ""
	var n = 0
	while player.state != "done" and n < 1200:
		n += 1
		if player.elapsed >= 16.0 and not player.outro_wanted:
			player.request_outro(6.0)
		player._process(DT)
		if player.state != last_state:
			next_shot = 0.0
			last_state = player.state
		if player.state in frames and player.elapsed >= next_shot:
			if next_shot == 0.0:
				next_shot = player.elapsed
			next_shot += every[player.state]
			yield(VisualServer, "frame_post_draw")
			var img = vp.get_texture().get_data()
			img.resize(400, 300)
			frames[player.state].append(img)
		else:
			yield(self, "idle_frame")
	for st in frames:
		_save("%s_%s" % [name, st], frames[st])
	player.queue_free()
	yield(self, "idle_frame")

func _save(name, list):
	if list.empty():
		return
	var cols = 5
	var sheet = Image.new()
	sheet.create(cols * 400, int(ceil(list.size() / float(cols))) * 300, false, Image.FORMAT_RGBA8)
	for i in range(list.size()):
		list[i].convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(list[i], Rect2(0, 0, 400, 300), Vector2((i % cols) * 400, (i / cols) * 300))
	sheet.save_png(out.plus_file(name + ".png"))
