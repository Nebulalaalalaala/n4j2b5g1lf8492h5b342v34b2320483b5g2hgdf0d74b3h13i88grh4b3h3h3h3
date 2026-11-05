extends Node

# Hover a Goober in a match to see its name and ping (it turns slightly see-through);
# click it to open a small player card. Works offline: everything comes from the
# match itself. Nicknames are private to you and keyed by the player's id.
# Ping: the game only measures your own connection, so other players show "-"
# unless the match data carries a value.
# Private nicknames use the native name label. Other-player recharge uses the
# native bar under that player (setting player_dash_meters).

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const ModPaths = preload("user://mod/core/ModPaths.gd")
const NICKS = "user://goobplayability/nicknames.json"
const HOVER_ALPHA = 0.55
const RADIUS = 40.0

var tas_tool
var menu
var layer: CanvasLayer
var tip: PanelContainer
var tip_name: Label
var tip_ping: Label
var card: PanelContainer
var card_tween: Tween
var hovered = {}
var nicks = {}
var remote_meters = {}
var name_overrides = {}
var _diag_next = 0
var _diag_count = 0
var _diag_game = null
var _name_cache = {}

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	nicks = Kit.read_json(NICKS, {})
	layer = CanvasLayer.new()
	layer.layer = 72
	add_child(layer)
	tip = PanelContainer.new()
	var style = Galaxy.box(Color(0.08, 0.086, 0.18, 0.92), Color("a68bff"), 10, 10)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	tip.add_stylebox_override("panel", style)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	layer.add_child(tip)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(row)
	tip_name = menu.label("", 15, Color("f5f3ff"))
	row.add_child(tip_name)
	tip_ping = menu.label("", 13, Color("b8b7d6"))
	row.add_child(tip_ping)
	card_tween = Tween.new()
	add_child(card_tween)

static func enabled() -> bool:
	return bool(SavedSettings.get_value("player_cards_enabled", true))

static func meters_enabled() -> bool:
	return bool(SavedSettings.get_value("player_dash_meters", true))

# True while the mouse is over the open Goobplayability window.
func _over_menu(mouse: Vector2) -> bool:
	if not bool(tas_tool.get("_menu_open")) or bool(tas_tool.get("_overlay_hidden")):
		return false
	var window = tas_tool.get("_menu_window")
	return window != null and is_instance_valid(window) and window.is_visible_in_tree() and window.get_global_rect().has_point(mouse)

func _game():
	var game = tas_tool.call("_find_game") if tas_tool.has_method("_find_game") else null
	return game if game != null and is_instance_valid(game) else null

var _next_tick = 0

func _process(_delta):
	var tick = OS.get_ticks_msec()
	if tick < _next_tick: return
	_next_tick = tick + 16
	var game = _game()
	var card_open = card != null and is_instance_valid(card)
	var best = {}
	var seen_names = {}
	var seen_meters = {}
	var show_meters = meters_enabled()
	var debug = bool(tas_tool.get("_debug_mode_enabled"))
	if game != _diag_game:
		_diag_game = game
		_diag_count = 0
		_name_cache.clear()
	if game != null and game.get("client_renderer") != null:
		var renderer_root = game.client_renderer
		var mouse = get_viewport().get_mouse_position()
		var can_hover = enabled() and not card_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not _over_menu(mouse)
		var best_distance = RADIUS
		var local_player = game.get_local_player()
		for index in game.get_player_count():
			var player = game.get_player_at_index(index)
			if player == null: continue
			var renderer = renderer_root.get_renderer_for_object_id(player.object_id)
			if not is_instance_valid(renderer): continue
			if not nicks.empty() or not name_overrides.empty():
				_sync_name(renderer,_name_info(game,player,renderer,tick),seen_names)
			if show_meters and player != local_player and not game.is_local_player(player.object_id):
				_sync_recharge(renderer,seen_meters)
			if not can_hover: continue
			var visual = _visual(renderer)
			if visual == null or not visual.is_visible_in_tree(): continue
			var transform = _screen_transform(visual)
			var scale = max(0.05,abs(_screen_scale(visual)))
			var center = transform.origin + Vector2(0,-18)*scale
			var distance = mouse.distance_to(center)/scale
			if distance < best_distance:
				best_distance = distance
				best = {"renderer":visual,"id":player.object_id,"game":game}
		if debug: _diagnose(game,renderer_root,mouse,can_hover,best_distance,local_player)
		if not best.empty():
			tip.rect_scale = Vector2.ONE*tas_tool.get_gui_scale_factor()
			tip.rect_position = mouse+Vector2(16,14)
	_prune_presentation(seen_names,seen_meters)
	if not card_open: _set_hover(best)

func _name_info(game, player, renderer, now: int) -> Dictionary:
	# Name labels still reconcile at display cadence. Identity/aliases do not
	# need a complete native metadata/RTT lookup for every player at 60 Hz.
	var id=renderer.get_instance_id()
	var cached=_name_cache.get(id,{})
	if not cached.empty() and cached.uuid==str(player.uuid) and now<int(cached.until): return cached.info
	var value=info(game,player.object_id)
	_name_cache[id]={"uuid":str(player.uuid),"until":now+1000,"info":value}
	if _name_cache.size()>256: _name_cache.clear()
	return value

func _nickname(player: Dictionary) -> String:
	if nicks.has(player.id): return str(nicks[player.id])
	# Older builds keyed entries by metadata.name instead of native uuid.
	for alias in player.get("aliases",[]):
		if nicks.has(alias): return str(nicks[alias])
	return ""

func _sync_name(renderer,player: Dictionary,seen: Dictionary) -> void:
	var label = renderer.get("username_label")
	if not label is Label: return
	var id = label.get_instance_id()
	var state = name_overrides.get(id,{})
	var nick = _nickname(player)
	if nick.empty():
		_restore_name(id)
		return
	if state.empty():
		state = {"ref":weakref(label),"original":label.text,"applied":"","player":player.id}
		name_overrides[id] = state
	elif label.text != state.applied:
		# Preserve newer native/Discord metadata for Clear and session unload.
		state.original = label.text
	state.player = player.id
	state.applied = nick
	if label.text != nick: label.text = nick
	seen[id] = true

func _restore_name(id) -> void:
	if not name_overrides.has(id): return
	var state = name_overrides[id]
	var label = state.ref.get_ref()
	if is_instance_valid(label) and label.text == state.applied:
		label.text = state.original
	name_overrides.erase(id)

func _sync_recharge(renderer,seen: Dictionary) -> void:
	var id = renderer.get_instance_id()
	if not remote_meters.has(id) or not is_instance_valid(remote_meters[id]):
		var driver = load("user://mod/core/workspace4/RemoteDashBar.gd").new()
		driver.renderer = renderer
		driver.name = "GoobRemoteDashBar"
		renderer.add_child(driver)
		remote_meters[id] = driver
	seen[id] = true

func _prune_presentation(names: Dictionary,bars: Dictionary) -> void:
	for id in name_overrides.keys():
		if not names.has(id): _restore_name(id)
	for id in remote_meters.keys():
		if bars.has(id): continue
		var driver = remote_meters[id]
		if is_instance_valid(driver):
			driver.restore_native_presentation()
			driver.queue_free()
		remote_meters.erase(id)

func restore_native_presentation() -> void:
	_prune_presentation({},{})

func _nickname_changed() -> void:
	_name_cache.clear()
	_next_tick = 0
	_process(0.0)
	if not hovered.empty(): tip_name.text = display_name(hovered.info)

# The drawn part of a player renderer. UpGuys_PlayerRenderer is a plain Node;
# its Goober is drawn under its "Position" Node2D.
func _visual(renderer):
	if renderer == null or not is_instance_valid(renderer):
		return null
	if renderer is CanvasItem:
		return renderer
	var node = renderer.get("position_node")
	if not (node is CanvasItem):
		node = renderer.get_node_or_null("Position")
	return node if node is CanvasItem else null

func _screen_scale(visual) -> float:
	var scale = visual.get_canvas_transform().get_scale().x
	var view = visual.get_viewport()
	if view != null and view != get_viewport():
		var holder = view.get_parent()
		if holder is ViewportContainer and view.size.x > 0:
			scale *= holder.get_global_rect().size.x / view.size.x
	return scale

# Where the renderer is on screen. The world can be drawn in its own Viewport
# (inside a ViewportContainer); map that back to this viewport.
func _screen_transform(renderer) -> Transform2D:
	var transform = renderer.get_global_transform_with_canvas()
	var view = renderer.get_viewport()
	if view == null or view == get_viewport():
		return transform
	var holder = view.get_parent()
	if holder is ViewportContainer and view.size.x > 0 and view.size.y > 0:
		var rect = holder.get_global_rect()
		var ratio = rect.size / view.size
		return Transform2D(transform.x * ratio.x, transform.y * ratio.y, rect.position + transform.origin * ratio)
	return transform

# A few log lines per match so hover problems can be read from godot.log.
func _diagnose(game, renderer_root, mouse, can_hover, best_distance, local_player) -> void:
	var now = OS.get_ticks_msec()
	if now < _diag_next or _diag_count >= 6:
		return
	_diag_next = now + 4000
	_diag_count += 1
	var found = 0
	var nearest = -1.0
	var sample = ""
	for index in range(game.get_player_count()):
		var player = game.get_player_at_index(index)
		var renderer = renderer_root.get_renderer_for_object_id(player.object_id) if player != null else null
		if renderer == null or not is_instance_valid(renderer):
			continue
		found += 1
		var visual = _visual(renderer)
		if visual != null:
			var at = _screen_transform(visual).origin
			var d = mouse.distance_to(at)
			if nearest < 0 or d < nearest:
				nearest = d
				sample = "%s zoom=%.2f node_scale=%.2f vis=%s own_vp=%s" % [str(at.round()), _screen_scale(visual), visual.get_global_transform().get_scale().x, str(visual.is_visible_in_tree()), str(visual.get_viewport() == get_viewport())]
		else:
			sample = "no visual under " + renderer.get_class()
	print("[PlayerCards] players=%d renderers=%d mouse=%s mode=%d hover=%s nearest=%.0f %s cooldown=%s" % [game.get_player_count(), found, str(mouse.round()), Input.mouse_mode, str(can_hover), nearest, sample, str(local_player.get("dash_cooldown")) if local_player != null else "-"])

func _set_hover(target: Dictionary) -> void:
	if not hovered.empty() and (target.empty() or hovered.renderer != target.get("renderer")):
		if is_instance_valid(hovered.renderer):
			hovered.renderer.modulate.a = hovered.alpha
		hovered = {}
		tip.visible = false
	if target.empty() or not hovered.empty():
		return
	hovered = target
	hovered["alpha"] = target.renderer.modulate.a
	hovered["info"] = info(target.game, target.id)
	target.renderer.modulate.a = hovered.alpha * HOVER_ALPHA
	tip_name.text = display_name(hovered.info)
	tip_ping.text = hovered.info.ping
	tip.visible = true

# What we know about a player from the match itself.
func info(game, object_id) -> Dictionary:
	var meta = game.get_metadata_for_player(object_id) if game.has_method("get_metadata_for_player") else {}
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	var name = str(meta.get("name", "Goober"))
	var local = game.has_method("is_local_player") and game.is_local_player(object_id)
	var ping = "ping -"
	for key in ["ping", "latency", "rtt"]:
		if meta.has(key) and float(meta[key]) > 0.0:
			ping = "%d ms" % int(round(float(meta[key]) * (1000.0 if float(meta[key]) < 5.0 else 1.0)))
	if local:
		if game.has_method("is_server") and game.is_server():
			ping = "local"
		elif game.has_method("get_client_round_trip_time") and float(game.get_client_round_trip_time()) > 0.0:
			ping = "%d ms" % int(round(float(game.get_client_round_trip_time()) * 1000.0))
	var id = ""
	var aliases = []
	for key in ["uuid","user_id","id"]:
		var value = meta.get(key,"")
		if value is String and not value.empty():
			if id.empty(): id = value
			elif not aliases.has(value): aliases.append(value)
	if id.empty(): id = name
	elif not aliases.has(name): aliases.append(name)
	return {"name":name,"id":id,"aliases":aliases,"local":local,"ping":ping,"skin":meta.get("skin",{})}

func display_name(player: Dictionary) -> String:
	var nick = _nickname(player)
	return nick if not nick.empty() else player.name

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		if not hovered.empty() and (card == null or not is_instance_valid(card)):
			open_card(hovered.info, event.position)
			get_tree().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE and card != null and is_instance_valid(card):
		close_card()
		get_tree().set_input_as_handled()

func open_card(player: Dictionary, at: Vector2) -> void:
	close_card()
	card = PanelContainer.new()
	var style = Galaxy.box(Color(0.08, 0.086, 0.18, 0.97), Color("a68bff"), 16, 16)
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(0.25, 0.12, 0.55, 0.5)
	style.shadow_size = 18
	card.add_stylebox_override("panel", style)
	card.rect_min_size = Vector2(300, 0)
	layer.add_child(card)
	var body = Kit.column(card, 10)
	var top = Kit.row(body, 12)
	var mini_script = ModPaths.try_load(ModPaths.path("HubMiniGoober.gd"))
	if mini_script != null:
		var mini = mini_script.new()
		mini.rect_min_size = Vector2(52, 52)
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var look = look_for(player.skin)
		mini.body = look.body
		mini.dark = look.dark
		mini.hat = look.hat
		mini.hat_color = look.hat_color
		top.add_child(mini)
	var names = Kit.column(top, 1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(menu.label(display_name(player), 19, Color("f5f3ff")))
	names.add_child(menu.label(("You · " if player.local else "") + "GooberDash name: " + player.name, 13, Color("b8b7d6")))
	var close = Kit.action(menu, top, "", "close", self, "close_card")
	close.rect_min_size = Vector2(32, 32)
	var stats = Kit.row(body, 8)
	stats.add_child(_chip("signal", player.ping))
	if not _nickname(player).empty():
		stats.add_child(_chip("user", "Nickname set"))
	var nick_row = Kit.row(body, 8)
	var field = Kit.field(menu, nick_row, _nickname(player), "Nickname (only you see it)", null, "")
	Kit.action(menu, nick_row, "Save", "check", self, "_save_nick", [player, field], true)
	var actions = Kit.row(body, 8)
	Kit.action(menu, actions, "Copy name", "copy", self, "_copy", [player.name])
	Kit.action(menu, actions, "Clear nickname", "trash", self, "_clear_nick", [player])
	var factor = tas_tool.get_gui_scale_factor()
	card.rect_scale = Vector2.ONE * factor * 0.92
	card.modulate.a = 0.0
	var size = get_viewport().get_visible_rect().size
	card.rect_position = Vector2(min(at.x + 12, size.x - 320 * factor), min(at.y + 12, size.y - 220 * factor))
	card_tween.interpolate_property(card, "rect_scale", card.rect_scale, Vector2.ONE * factor, 0.16, Tween.TRANS_BACK, Tween.EASE_OUT)
	card_tween.interpolate_property(card, "modulate:a", 0.0, 1.0, 0.12)
	card_tween.start()

func _chip(icon_name: String, text: String) -> PanelContainer:
	var chip = PanelContainer.new()
	var style = Galaxy.box(Color(0.125, 0.141, 0.255), Color(0.173, 0.184, 0.333), 10, 12)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_stylebox_override("panel", style)
	var row = Kit.row(chip, 6)
	var glyph = TextureRect.new()
	glyph.texture = Galaxy.icon(icon_name, Color("f5f3ff"), 16)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	row.add_child(menu.label(text, 14, Color("f5f3ff")))
	return chip

func close_card() -> void:
	if card != null and is_instance_valid(card):
		card.queue_free()
	card = null

func _save_nick(player: Dictionary, field: LineEdit) -> void:
	var value = field.text.strip_edges().left(24)
	var clean = ""
	for character in value:
		if ord(character) >= 32:
			clean += character
	for alias in player.get("aliases",[]): nicks.erase(alias)
	if clean.empty():
		nicks.erase(player.id)
	else:
		nicks[player.id] = clean
	Kit.write_json(NICKS, nicks)
	_nickname_changed()
	open_card(player, card.rect_position - Vector2(12, 12) if card != null else Vector2(200, 200))

func _clear_nick(player: Dictionary) -> void:
	for alias in player.get("aliases",[]): nicks.erase(alias)
	nicks.erase(player.id)
	Kit.write_json(NICKS, nicks)
	_nickname_changed()
	open_card(player, card.rect_position - Vector2(12, 12) if card != null else Vector2(200, 200))

func _copy(text: String) -> void:
	OS.clipboard = text

# Body colour and hat shape from the player's skin (same mapping as Goober Hub).
static func look_for(skin) -> Dictionary:
	var result = {"body": Color("7cc4ff"), "dark": Color("3a6ec2"), "hat": "", "hat_color": Color.white}
	if not skin is Dictionary or not ResourceLoader.exists("res://project_specific/data/CosmeticsCollection.gd"):
		return result
	var cosmetics = load("res://project_specific/data/CosmeticsCollection.gd")
	var color = cosmetics.lookup_cosmetic_id(str(skin.get("color", "color_default")))
	var gradient_name = str(color.get("color", "blue")) if color is Dictionary else "blue"
	var path = "res://project_specific/gfx/player_gradients/%s.tres" % gradient_name
	var gradient = load(path) if ResourceLoader.exists(path) else null
	if gradient is Gradient and gradient.colors.size() > 0:
		result.body = gradient.colors[gradient.colors.size() - 1]
		result.dark = gradient.colors[0]
	var hat_id = str(skin.get("hat", ""))
	var hat = cosmetics.lookup_cosmetic_id(hat_id) if not hat_id.empty() else {}
	var mini = ModPaths.try_load(ModPaths.path("HubMiniGoober.gd"))
	if hat is Dictionary and hat.has("spine") and mini != null:
		var shape = mini.hat_for(hat.spine)
		result.hat = shape[0]
		result.hat_color = shape[1]
	return result

func _exit_tree():
	restore_native_presentation()
	_set_hover({})
