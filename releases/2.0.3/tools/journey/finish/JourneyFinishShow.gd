extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# One Journey finish animation on one player's Goober (JourneyHud starts one per
# player who finishes: yours, and other Goobplayability players' equipped ones).
# Client-local and cosmetic only: hides that Goober's sprite and plays a
# JourneyFinishPlayer (its own Goober copy and props) where it settled. Physics,
# collision, input, timing, rewards and network state are never touched. The
# outro is asked for when the round starts to transition and is fitted into the
# time left, so it never delays anything. Frees itself when done.
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

func start(game, finish, renderer, spine):
	_game = weakref(game)
	_pending = {"finish": finish, "spine": weakref(spine), "renderer": weakref(renderer)}
	_last_pos = spine.global_position

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
		_stop()
		return
	if game.is_in_regular_post_play():
		_fx.request_outro(max(0.2, float(game.wp_game_data.state_time) - FADE_AT))
	elif game.is_game_over():
		_fx.request_outro(2.5)
	# Moving away from the spot ends it, so the real Goober (and the camera)
	# are never somewhere else. Finishing mid-air or while sliding is normal:
	# for the first 1.5 s the finish follows the body as it lands / slides, but
	# a sudden jump (respawn, teleport) ends it instead of flinging it along.
	var spine = _hidden.get_ref() if _hidden != null else null
	if spine != null and is_instance_valid(spine):
		_age += delta
		var pos = spine.global_position
		if _age < 1.5:
			if (pos - _anchor).length() > _unit * 3.0:
				_stop()
				return
			_fx.global_position += pos - _anchor
			_anchor = pos
		# _unit is a third of the Goober's height: 1 Goober height sideways, 2 up or down.
		var off = pos - _anchor
		if abs(off.x) > _unit * 3.0 or abs(off.y) > _unit * 6.0:
			_stop()

# Starts once the Goober has come to rest (not sliding or falling), or after
# 1.2 s whatever it is doing.
func _wait_to_start(game, delta):
	var spine = _pending.spine.get_ref()
	if spine == null or not is_instance_valid(spine) or not spine.is_inside_tree() or game.is_in_regular_pre_play():
		_stop()
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
		_stop()
		return
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

func _on_fx_finished():
	if not _keep_hidden:
		_stop()
	elif _fx != null and is_instance_valid(_fx):
		# Went through the portal / flew off: stay gone until the round changes.
		_fx.visible = false

func _stop():
	_cleanup()
	set_process(false)
	queue_free()

func _exit_tree():
	_cleanup()

func _cleanup():
	if _fx != null and is_instance_valid(_fx):
		if _fx.is_connected("tree_exiting",self,"_restore"):
			_fx.disconnect("tree_exiting",self,"_restore")
		_fx.queue_free()
	_fx = null
	_pending = null
	_restore()

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
