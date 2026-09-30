extends CanvasLayer

# Reuses the native emote event and ownership data; no new network requests.
const ACTION = "goob_emote_wheel"
const KEYS = [0, KEY_F8, KEY_F9, KEY_F10]
var tool
var root: Control
var center: Label
var cards = []
var entries = []
var page = 0
var selected = -1
var opened_game = null
var binding = 0
var last_sent = -1000

func _ready() -> void:
	layer = 240
	root = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.hide()
	center = Label.new()
	center.align = Label.ALIGN_CENTER
	center.valign = Label.VALIGN_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_font_override("font", _font(15))
	center.add_color_override("font_color_shadow", Color.black)
	center.add_constant_override("shadow_offset_x", 1)
	center.add_constant_override("shadow_offset_y", 1)
	root.add_child(center)
	set_binding(int(SavedSettings.get_value("emote_wheel_key", KEY_F8)))

func _font(size: int) -> DynamicFont:
	var font = DynamicFont.new()
	font.font_data = load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
	font.size = size
	return font

func set_binding(key: int) -> void:
	cancel()
	if not key in KEYS:
		key = 0
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
	InputMap.action_erase_events(ACTION)
	binding = key
	if key != 0:
		var event = InputEventKey.new()
		event.scancode = key
		for action in InputMap.get_actions():
			if action != ACTION and InputMap.event_is_action(event, action):
				binding = 0
				break
		if binding != 0:
			InputMap.action_add_event(ACTION, event)
	SavedSettings.set_value("emote_wheel_key", binding)

func _typing() -> bool:
	var focus = root.get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func _game():
	if tool == null or _typing():
		return null
	var game = tool.call("_find_game")
	if game == null or game.wp_game_data == null or game.is_game_over():
		return null
	var data = game.wp_game_data
	if data.is_time_trial or data.is_tutorial or data.is_replay:
		return null
	var player = game.get_local_player()
	if player == null or not player.alive or player.spectator_object_id != 0:
		return null
	return game

func _available() -> Array:
	var catalog = CosmeticsCollection.filter_cosmetics_type("emote")
	var owned = Moonlight.storage.storage_get("player.profile.cards", {})
	var equipped = Moonlight.storage.storage_get("player.profile.emotes", [])
	var ordered = []
	var studio = _studio()
	if studio != null:
		ordered += studio.library.get("favorites", [])
		ordered += studio.library.get("recent", [])
	ordered += equipped
	var other = catalog.keys()
	other.sort()
	ordered += other
	var seen = {}
	var result = []
	for id in ordered:
		if seen.has(id) or not catalog.has(id):
			continue
		seen[id] = true
		if not equipped.has(id) and not bool(owned.get(id, {}).get("unlocked", false)):
			continue
		if str(catalog[id].get("spine", "")).empty():
			continue
		result.append({"id": id, "name": str(catalog[id].get("name", id)), "spine": str(catalog[id].spine)})
	return result

func _studio():
	if tool == null:
		return null
	var sandbox = tool.get("_cosmetic_sandbox")
	return sandbox.get("_studio") if sandbox != null else null

func open() -> void:
	opened_game = _game()
	if opened_game == null:
		return
	entries = _available()
	page = 0
	root.show()
	_render_page()

func cancel() -> void:
	if root != null:
		root.hide()
	opened_game = null
	selected = -1
	for card in cards:
		card.queue_free()
	cards.clear()

func _render_page() -> void:
	for card in cards:
		card.hide()
		card.queue_free()
	cards.clear()
	selected = -1
	var midpoint = get_viewport().get_visible_rect().size * 0.5
	center.rect_position = midpoint - Vector2(90, 55)
	center.rect_size = Vector2(180, 110)
	center.text = "No owned emotes" if entries.empty() else "EMOTES  %d / %d\nScroll: page\nRelease: play\nEsc: cancel" % [page + 1, int(ceil(entries.size() / 8.0))]
	for index in range(min(8, entries.size() - page * 8)):
		var entry = entries[page * 8 + index]
		var card = Panel.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.rect_size = Vector2(108, 88)
		var angle = -PI * 0.5 + index * TAU / 8.0
		card.rect_position = midpoint + Vector2(cos(angle), sin(angle)) * 180.0 - card.rect_size * 0.5
		root.add_child(card)
		cards.append(card)
		var icon = load("res://project_specific/gfx/spine/upguy/emote.tscn").instance()
		card.add_child(icon)
		icon.position = Vector2(54, 30)
		icon.scale = Vector2.ONE * 0.32
		icon.show_static_frame(entry.spine)
		var label = Label.new()
		label.text = entry.name
		label.add_font_override("font", _font(14))
		label.align = Label.ALIGN_CENTER
		label.rect_position = Vector2(4, 60)
		label.rect_size = Vector2(100, 24)
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(label)
	_update_highlight()

func _update_highlight() -> void:
	for i in cards.size():
		var style = StyleBoxFlat.new()
		style.bg_color = Color("365b4c") if i == selected else Color("22282c")
		style.border_color = Color("9dd6bd") if i == selected else Color("526069")
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		cards[i].add_stylebox_override("panel", style)

func _confirm() -> void:
	var index = page * 8 + selected
	if selected < 0 or index >= entries.size() or _game() != opened_game or OS.get_ticks_msec() - last_sent < 800:
		cancel()
		return
	var id = entries[index].id
	var valid = false
	for entry in _available():
		if entry.id == id:
			valid = true
	cancel()
	if not valid:
		return
	last_sent = OS.get_ticks_msec()
	GlobalEvent.emit_signal("UI_EMOTE_BUTTON_PRESSED", id)
	var studio = _studio()
	if studio != null:
		studio.library.recent.erase(id)
		studio.library.recent.push_front(id)
		studio.library.recent.resize(min(40, studio.library.recent.size()))
		studio._save()

func _input(event: InputEvent) -> void:
	if _typing():
		cancel()
		return
	if event.is_action_pressed(ACTION) and not event.is_echo():
		open()
		if root.visible:
			get_tree().set_input_as_handled()
		return
	if not root.visible:
		return
	if event.is_action_released(ACTION) or event.is_action_pressed("ui_accept"):
		_confirm()
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN] and entries.size() > 8:
			page = posmod(page + (1 if event.button_index == BUTTON_WHEEL_DOWN else -1), int(ceil(entries.size() / 8.0)))
			_render_page()
		elif event.button_index == BUTTON_LEFT:
			_confirm()
		elif event.button_index == BUTTON_RIGHT:
			cancel()
	get_tree().set_input_as_handled()

func _process(_delta: float) -> void:
	if not root.visible:
		return
	if _game() != opened_game or not Input.is_action_pressed(ACTION):
		cancel()
		return
	var direction = root.get_global_mouse_position() - get_viewport().get_visible_rect().size * 0.5
	var next = -1
	if direction.length() > 75:
		next = posmod(int(round((direction.angle() + PI * 0.5) / (TAU / 8.0))), 8)
		if next >= cards.size():
			next = -1
	if next != selected:
		selected = next
		_update_highlight()
		if selected >= 0:
			center.text = entries[page * 8 + selected].name + "\nRelease to play\nEsc: cancel"
