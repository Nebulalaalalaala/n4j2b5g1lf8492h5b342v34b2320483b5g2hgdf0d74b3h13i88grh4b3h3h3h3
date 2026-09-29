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
# The equipped Journey finish animation (Rewards > Finishes). Client-local and
# cosmetic only: on the local player's own finish it hides that player's
# Goober sprite and plays a JourneyFinishPlayer (its own Goober copy and props)
# where the player settled. Physics, collision, input, timing, rewards and
# network state are never touched; other players keep seeing the normal finish
# dance. The outro is asked for when the round starts to transition and is
# fitted into the time left, so it never delays anything.
const FADE_AT = 1.3        # GameplaySceneTransitionMonitor.TRANSITION_TIME
var _fx = null
var _hidden = null
var _game = null
var _anchor = Vector2.ZERO
var _unit = 60.0
var _pending = null         # waiting for the Goober to land before starting
var _settle = 0.0
var _age = 0.0              # seconds since the finish started playing
var _ui = null              # the player's name / place / dash bar (renderer UIHolder)
var _ui_set = null          # where we last put it, and by how much it was moved
var _ui_delta = Vector2.ZERO
var _last_pos = Vector2.ZERO
var _keep_hidden = false

var _renderers = []

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

func _skip(reason):
	print("[Journey] finish animation skipped: %s" % reason)

func _on_finish(player_id,_rank,_out_of,_line,_position,reference):
	var game = reference.get_ref()
	if game == null or not is_instance_valid(game) or not game.is_local_player(player_id):
		return
	if _busy():
		return _skip("already playing")
	var d = game.wp_game_data
	if d.get("is_replay_ghost") or d.get("is_level_editor") or d.get("is_tutorial") or d.get("is_time_trial"):
		return _skip("not a regular match")
	var finish = equipped_finish()
	if finish.empty():
		return _skip("no unlocked finish equipped")
	var renderer = _renderer_for(game, player_id)
	var spine = renderer.get("spine") if renderer != null else null
	if spine == null or not is_instance_valid(spine) or not spine.is_inside_tree():
		return _skip("player sprite not found")
	_game = weakref(game)
	_pending = {"finish": finish, "spine": weakref(spine), "renderer": weakref(renderer)}
	_settle = 0.0
	_last_pos = spine.global_position
	set_process(true)

func _busy():
	return _pending != null or (_fx != null and is_instance_valid(_fx))

# The equipped finish if it's still unlocked, else {}.
func equipped_finish() -> Dictionary:
	var settings = get_node_or_null("/root/SavedSettings")
	var key = str(settings.get_value("journey_pref_finish","")) if settings != null else ""
	if key == "" or controller == null or controller.ledger == null:
		return {}
	var base = get_script().resource_path.get_base_dir()
	var definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
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
	for f in screen_script.FINISHES:
		if str(f.key) == key and xp >= int(definitions.king_rank(int(f.rank_id)-17).xp):
			return f
	return {}

func _process(delta):
	var game = _game.get_ref() if _game != null else null
	if game == null or not is_instance_valid(game):
		_stop()
		return
	if _pending != null:
		_wait_to_start(game, delta)
		return
	if _fx == null or not is_instance_valid(_fx):
		_stop()
		return
	if game.is_in_regular_pre_play():
		# A new round started without a scene change: clean up right away.
		print("[Journey] finish animation ended: new round")
		_stop()
		return
	if game.is_in_regular_post_play():
		_fx.request_outro(max(0.2, float(game.wp_game_data.state_time) - FADE_AT))
	elif game.is_game_over():
		_fx.request_outro(2.5)
	# Walking well away from the spot ends it (the real Goober reappears).
	# Finishing mid-air or while sliding is normal: for the first 1.5 s the
	# finish follows the body as it lands / slides to a stop.
	var spine = _hidden.get_ref() if _hidden != null else null
	if spine != null and is_instance_valid(spine):
		_age += delta
		var pos = spine.global_position
		if _age < 1.5:
			_fx.global_position += pos - _anchor
			_anchor = pos
		var off = pos - _anchor
		# _unit is a third of the Goober's height: ~3 Goober heights sideways,
		# ~10 down (fell off / respawned).
		if abs(off.x) > _unit * 9.0 or abs(off.y) > _unit * 30.0:
			print("[Journey] finish animation ended: moved away")
			_stop()

# Starts once the Goober has come to rest (not sliding or falling), or after
# 1.2 s whatever it is doing.
func _wait_to_start(game, delta):
	var spine = _pending.spine.get_ref()
	if spine == null or not is_instance_valid(spine) or not spine.is_inside_tree() or game.is_in_regular_pre_play():
		_pending = null
		set_process(false)
		return
	var pos = spine.global_position
	_settle += delta
	var still = abs(pos.y - _last_pos.y) < 0.5 and abs(pos.x - _last_pos.x) < 0.5
	_last_pos = pos
	if not (still and _settle > 0.12) and _settle < 1.2:
		return
	var finish = _pending.finish
	var renderer = _pending.renderer.get_ref()
	_ui = weakref(renderer.get_node_or_null("UIHolder")) if renderer != null and is_instance_valid(renderer) else null
	_ui_set = null
	_pending = null
	# Parented beside the Goober sprite (not to the player), so it stays at the
	# finish even though the player body can still move.
	var world = spine.get_parent()
	if world == null:
		set_process(false)
		return _skip("player sprite has no parent")
	var base = get_script().resource_path.get_base_dir()
	_fx = load(ModPaths.path("JourneyFinishPlayer.gd")).new()
	_fx.name = "JourneyFinish"
	world.add_child(_fx)
	world.move_child(_fx, spine.get_index()+1)
	_fx.global_position = pos
	_anchor = pos
	_age = 0.0
	_unit = 700.0 * abs(spine.global_scale.y)
	var skin = spine.get("goober_skin_data")
	_fx.setup(load(ModPaths.path(str(finish.script))).new(), skin if skin is Dictionary else {}, 700.0 * abs(spine.global_scale.y) / max(0.0001, abs(world.global_scale.y)))
	_keep_hidden = _fx.keep_hidden_after()
	_hidden = weakref(spine)
	spine.visible = false
	if not VisualServer.is_connected("frame_pre_draw",self,"_pre_draw"):
		VisualServer.connect("frame_pre_draw",self,"_pre_draw")
	_fx.connect("finished",self,"_on_fx_finished")
	_fx.connect("tree_exiting",self,"_restore")
	print("[Journey] finish animation: %s" % finish.key)

func _on_fx_finished():
	if not _keep_hidden:
		_stop()
	elif _fx != null and is_instance_valid(_fx):
		# Went through the portal / flew off: stay gone until the round changes.
		_fx.visible = false

func _stop():
	if _fx != null and is_instance_valid(_fx):
		if _fx.is_connected("tree_exiting",self,"_restore"):
			_fx.disconnect("tree_exiting",self,"_restore")
		_fx.queue_free()
	_fx = null
	_pending = null
	_restore()
	set_process(false)

# The native renderer turns the sprite back on during its update, so it is
# hidden again right before every draw, after all game updates have run.
func _pre_draw():
	var spine = _hidden.get_ref() if _hidden != null else null
	if spine != null and is_instance_valid(spine):
		spine.visible = false
		_follow_ui(spine)

# The name / place / dash bar go with the finish's Goober (e.g. riding the
# star), offset the same as they are from the real one. Re-applied right before
# each draw and undone when the finish ends.
func _follow_ui(spine):
	var ui = _ui.get_ref() if _ui != null else null
	if ui == null or not is_instance_valid(ui):
		return
	_unfollow_ui(ui)
	var pup = _fx.get("puppet") if _fx != null and is_instance_valid(_fx) else null
	if pup == null or not is_instance_valid(pup) or not _fx.visible or not pup.is_visible_in_tree():
		return
	_ui_delta = pup.global_position - spine.global_position
	ui.rect_global_position += _ui_delta
	_ui_set = ui.rect_global_position

func _unfollow_ui(ui):
	# Only undo our own move; if the game re-placed it this frame, leave it.
	if _ui_set != null and ui.rect_global_position.distance_to(_ui_set) < 0.01:
		ui.rect_global_position -= _ui_delta
	_ui_set = null

func _restore():
	if VisualServer.is_connected("frame_pre_draw",self,"_pre_draw"):
		VisualServer.disconnect("frame_pre_draw",self,"_pre_draw")
	var ui = _ui.get_ref() if _ui != null else null
	if ui != null and is_instance_valid(ui):
		_unfollow_ui(ui)
	_ui = null
	var spine = _hidden.get_ref() if _hidden != null else null
	if spine != null and is_instance_valid(spine):
		spine.visible = true
	_hidden = null
