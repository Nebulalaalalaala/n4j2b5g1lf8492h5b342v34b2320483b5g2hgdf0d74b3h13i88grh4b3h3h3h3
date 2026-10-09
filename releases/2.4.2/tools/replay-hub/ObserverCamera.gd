extends CanvasLayer

# Dedicated presentation camera; original camera and game state stay untouched.
var service
var hub
var camera = null
var previous = null
var target = null
var panel
var info
var picker
var speed = 900.0
var observed_players = []
var refresh_time = 0.0

func start(owner, observer) -> bool:
	hub = owner
	service = observer
	var game = service.tool._find_game() if service.tool != null else null
	if not service.eligible(game):
		return false
	previous = service.tool._find_playback_camera()
	if previous == null or not is_instance_valid(previous):
		return false
	previous = weakref(previous)
	camera = Camera2D.new()
	previous.get_ref().get_parent().add_child(camera)
	camera.global_position = previous.get_ref().global_position
	camera.zoom = previous.get_ref().zoom
	camera.current = true
	layer = 151
	set_process_priority(1000003)
	panel = PanelContainer.new()
	panel.rect_position = Vector2(12,12)
	panel.add_stylebox_override("panel", hub._flat_style(Color("182329"), Color("6ab59d"), 1, 8))
	add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	info = hub._make_label("Observer · local camera", hub._small_font, hub.WHITE)
	box.add_child(info)
	var row = HBoxContainer.new()
	box.add_child(row)
	for spec in [["Freecam", "freecam"], ["Previous", "previous_player"], ["Next", "next_player"], ["Reset", "reset"], ["Close", "close"]]:
		var button = hub._make_button(spec[0], hub.BLUE, 12)
		button.rect_min_size.y = 30
		button.connect("pressed",self,spec[1])
		row.add_child(button)
	picker = OptionButton.new()
	picker.add_font_override("font", hub._small_font)
	picker.get_popup().add_font_override("font", hub._small_font)
	picker.connect("item_selected",self,"follow")
	box.add_child(picker)
	var speed_slider = HSlider.new()
	speed_slider.min_value = 100
	speed_slider.max_value = 4000
	speed_slider.value = speed
	speed_slider.connect("value_changed",self,"set_speed")
	box.add_child(speed_slider)
	box.add_child(hub._make_label("Arrow keys: fly · wheel: zoom · H: hide HUD · Esc: exit camera", hub._small_font, hub.DIM))
	_refresh(game)
	return true

func set_speed(value):
	speed = value

func _refresh(game):
	observed_players = []
	picker.clear()
	for index in game.get_player_count():
		var player = game.get_player_at_index(index)
		if player != null and player.type != NetworkPlayer.SPECTATOR:
			observed_players.append(weakref(player))
			picker.add_item(str(game.get_metadata_for_player(player.object_id).get("name", "Unknown")).substr(0,32))
			if target != null and target.get_ref() == player:
				picker.select(picker.get_item_count()-1)

func follow(index):
	if index >= 0 and index < observed_players.size():
		target = observed_players[index]

func next_player():
	if not observed_players.empty():
		picker.select((picker.selected + 1) % observed_players.size())
		follow(picker.selected)

func previous_player():
	if not observed_players.empty():
		picker.select((picker.selected + observed_players.size() - 1) % observed_players.size())
		follow(picker.selected)

func freecam():
	target = null

func reset():
	target = null
	if previous != null and previous.get_ref() != null:
		camera.global_position = previous.get_ref().global_position
		camera.zoom = previous.get_ref().zoom

func _process(delta):
	if camera == null:
		return
	var game = service.tool._find_game() if service.tool != null else null
	if not is_instance_valid(camera) or not service.eligible(game) or previous.get_ref() == null:
		close()
		return
	refresh_time += delta
	if refresh_time >= 1.0:
		_refresh(game)
		refresh_time = 0
	var player = target.get_ref() if target != null else null
	if player != null:
		camera.global_position = player.position
	else:
		var keys = service.tool._keybinds
		var direction = Vector2(int(keys.held("camera_right"))-int(keys.held("camera_left")), int(keys.held("camera_down"))-int(keys.held("camera_up")))
		camera.global_position += direction.normalized() * speed * delta * camera.zoom.x
	info.text = "Observer · " + ("Freecam" if player == null else "Following " + picker.get_item_text(picker.selected)) + " · speed %d" % speed
	camera.force_update_scroll()
	ViewportRectCalculator.calculate_viewport_visible_rect()

func _unhandled_input(event):
	if camera == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_ESCAPE:
			close()
		elif service.tool._keybinds.matches(event,"observer_hide"):
			panel.visible = not panel.visible
		else:
			return
		get_tree().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [BUTTON_WHEEL_UP,BUTTON_WHEEL_DOWN]:
		var factor = 0.9 if event.button_index == BUTTON_WHEEL_UP else 1.1
		camera.zoom = Vector2.ONE * clamp(camera.zoom.x * factor,0.18,4.0)
		get_tree().set_input_as_handled()

func close():
	if camera != null and is_instance_valid(camera):
		camera.queue_free()
	camera = null
	if previous != null and previous.get_ref() != null:
		previous.get_ref().current = true
	queue_free()

func _exit_tree():
	if camera != null and is_instance_valid(camera):
		camera.queue_free()
	if previous != null and previous.get_ref() != null:
		previous.get_ref().current = true
