extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# In-match Journey button: sits in the match HUD's top-right column right under
# the settings cog, in the same native button style. Opens Journey over the
# match on its own layer; the close button or Esc returns to the game.
var controller
var art
var layer = null

func _ready():
	set_process(false)
	art = load(ModPaths.path("JourneyArt.gd")).new()
	get_tree().connect("node_added",self,"_consider")

func _consider(node):
	if node.name == "GameHUD" and node is Control:
		call_deferred("_attach",weakref(node))
	elif node is UpGuys_PlayerRenderer:
		call_deferred("_watch_renderer",weakref(node))

func _attach(reference):
	var hud = reference.get_ref()
	if not is_instance_valid(hud) or hud.has_node("JourneyLayer"):
		return
	var column = hud.get_node_or_null("Container/TopRight/VBoxContainer")
	var settings = column.get_node_or_null("SettingsButton") if column != null else null
	if settings == null or column.has_node("JourneyButton"):
		return
	var icon = art.texture("journey_hud")
	var scene = load("res://project_specific/ui/button_styles/FlatButtonWhite.tscn")
	if icon == null or scene == null:
		return
	var button = scene.instance()
	button.name = "JourneyButton"
	button.rect_min_size = settings.rect_min_size
	button.set("swatch",settings.get("swatch"))
	button.set("icon_tex",icon)
	button.hint_tooltip = "Journey"
	column.add_child(button)
	column.move_child(button,settings.get_index()+1)
	button.connect("pressed",self,"open",[weakref(hud)])

func open(reference):
	var hud = reference.get_ref()
	if not is_instance_valid(hud) or (layer != null and is_instance_valid(layer)):
		return
	layer = CanvasLayer.new()
	layer.name = "JourneyLayer"
	layer.layer = 90
	var shade = ColorRect.new()
	shade.color = Color(0.0,0.08,0.2,0.88)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(shade)
	var screen = load(ModPaths.path("JourneyScreen.gd")).new()
	screen.profile_service = controller.profile_service
	screen.activity = controller.activity
	screen.closable = true
	screen.build(controller.ledger)
	screen.add_constant_override("margin_top",24)
	screen.add_constant_override("margin_bottom",24)
	layer.add_child(screen)
	screen.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	screen.connect("close_requested",self,"close")
	hud.add_child(layer)
	screen.play("open")

func close():
	if layer != null and is_instance_valid(layer):
		layer.queue_free()
	layer = null

# ---------------------------------------------------------------- finish animations
# Journey finish animations (Rewards > Finishes), played by JourneyFinishShow:
# yours on your own finish, and other Goobplayability players' equipped ones on
# theirs (looked up once per player through JourneyLooks when they appear).
var _renderers = []
var _shows = {}             # player object id -> JourneyFinishShow
var _lookup_ids = []

# Player renderers are tracked the same way ClientEffectFixes does; each one's
# game gets the finish-line hook (once).
func _watch_renderer(reference):
	var renderer = reference.get_ref()
	if renderer == null or not is_instance_valid(renderer) or not renderer.is_inside_tree():
		return
	if not _renderers.has(renderer):
		_renderers.append(renderer)
	var game = renderer.get_network_game()
	if game == null or not is_instance_valid(game) or not game.has_signal("player_hit_finish_line"):
		return
	if not game.is_connected("player_hit_finish_line",self,"_on_finish"):
		game.connect("player_hit_finish_line",self,"_on_finish",[weakref(game)])
	var uuid = _uuid(game, renderer.get_object_id())
	if not uuid.empty() and not game.is_local_player(renderer.get_object_id()) and not _lookup_ids.has(uuid):
		_lookup_ids.append(uuid)
		if _lookup_ids.size() == 1:
			call_deferred("_flush_lookups")

func _flush_lookups():
	if controller != null and controller.get("looks") != null:
		controller.looks.lookup(_lookup_ids)
	_lookup_ids = []

func _uuid(game, player_id) -> String:
	var metadata = game.get_metadata_for_player(player_id) if game.has_method("get_metadata_for_player") else null
	return str(metadata.get("uuid", "")) if metadata is Dictionary else ""

func _renderer_for(game, player_id):
	var live = []
	var found = null
	for renderer in _renderers:
		if not is_instance_valid(renderer) or not renderer.is_inside_tree():
			continue
		live.append(renderer)
		if found == null and renderer.get_object_id() == player_id and renderer.get_network_game() == game:
			found = renderer
	_renderers = live
	return found

func _on_finish(player_id,_rank,_out_of,_line,_position,reference):
	var game = reference.get_ref()
	if game == null or not is_instance_valid(game):
		return
	var d = game.wp_game_data
	if d.get("is_replay_ghost") or d.get("is_level_editor") or d.get("is_tutorial") or d.get("is_time_trial"):
		return
	var show = _shows.get(player_id)
	if show != null and is_instance_valid(show):
		return
	var finish = equipped_finish() if game.is_local_player(player_id) else _their_finish(game, player_id)
	if finish.empty():
		return
	var renderer = _renderer_for(game, player_id)
	var spine = renderer.get("spine") if renderer != null else null
	if spine == null or not is_instance_valid(spine) or not spine.is_inside_tree():
		return
	show = load(ModPaths.path("JourneyFinishShow.gd")).new()
	add_child(show)
	show.start(game, finish, renderer, spine)
	_shows[player_id] = show

# Another player's equipped finish, if their Journey XP has unlocked it.
func _their_finish(game, player_id) -> Dictionary:
	var looks = controller.get("looks") if controller != null else null
	var look = looks.look(_uuid(game, player_id)) if looks != null else null
	if look == null or str(look.finish).empty():
		return {}
	return _unlocked(str(look.finish), int(look.xp))

func _unlocked(key, xp) -> Dictionary:
	var definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
	for f in load(ModPaths.path("JourneyScreen.gd")).FINISHES:
		if str(f.key) == key and xp >= int(definitions.king_rank(int(f.rank_id)-17).xp):
			return f
	return {}

# The equipped finish if it's still unlocked, else {}.
func equipped_finish() -> Dictionary:
	var settings = get_node_or_null("/root/SavedSettings")
	var key = str(settings.get_value("journey_pref_finish","")) if settings != null else ""
	if key == "" or controller == null or controller.ledger == null:
		return {}
	var screen_script = load(ModPaths.path("JourneyScreen.gd"))
	var xp = int(controller.ledger.total_xp)
	var screen = controller.get("screen")
	if screen != null and is_instance_valid(screen) and screen.has_method("_finish_xp"):
		xp = screen._finish_xp()
	elif str(controller.ledger.account_id) == str(screen_script.ADMIN_ID):
		# In a match the home screen is gone; the admin's test XP (read only)
		# still counts, the same as JourneyScreen._finish_xp().
		var store = load(ModPaths.path("JourneyStore.gd")).new()
		if store.configure(str(controller.ledger.account_id)):
			xp += int(store.test.get("xp", 0))
	return _unlocked(key, xp)
