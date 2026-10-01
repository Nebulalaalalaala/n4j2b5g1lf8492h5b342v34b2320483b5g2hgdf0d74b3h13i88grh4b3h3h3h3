extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")

# Account-scoped presentation queue; XP still belongs exclusively to the ledger.
var controller
var account = ""
var pending = {}
var age = 0.0
var elapsed = 0.0
var shown_rank = -1

func observe(before, after):
	_sync()
	var definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
	var old = definitions.rank_at(before)
	var rank = definitions.rank_at(after)
	if int(rank.id) <= int(old.id): return
	var mode = str(Data.preference(self, controller, "celebrations", "all"))
	if mode == "off" or str(Data.preference(self, controller, "notify", "after_match")) == "inbox": return
	if mode == "leagues" and old.art == rank.art and str(rank.league) != "King League": return
	pending = rank
	age = 0.0

func _sync():
	var owner = str(controller.ledger.account_id)
	if owner != account:
		account = owner
		pending = {}
		age = 0.0
		shown_rank = -1

func already_shown(rank_id):
	return int(rank_id) <= shown_rank

func consume(rank_id):
	shown_rank = max(shown_rank,int(rank_id))
	if not pending.empty() and int(pending.id) <= int(rank_id): pending = {}

func _process(delta):
	_sync()
	if pending.empty(): return
	age += delta
	elapsed += delta
	if elapsed < 0.25 or age < 2.8: return
	elapsed = 0.0
	var mode = str(Data.preference(self, controller, "celebrations", "all"))
	if mode == "off" or str(Data.preference(self, controller, "notify", "after_match")) == "inbox":
		pending = {}
		return
	var game = controller.profile_service.game if controller.profile_service != null else null
	var target = controller.screen
	var in_match = is_instance_valid(game)
	if in_match:
		# Never interrupt an active race. Wins, elimination, and returning home are safe.
		if not controller.match_xp.terminal or controller.match_xp.terminal_age < 1.0: return
		var scene = get_tree().current_scene
		var hud = scene.find_node("GameHUD", true, false) if scene != null else null
		if not is_instance_valid(hud): return
		if is_instance_valid(controller.hud.layer):
			# The player may already be inspecting Details. Let its Continue handle it.
			return
		controller.hud.open(weakref(hud))
		target = null
		if is_instance_valid(controller.hud.layer):
			for child in controller.hud.layer.get_children():
				if child.has_method("celebrate"): target = child
	if not is_instance_valid(target) or not target.is_inside_tree() or target.design_preview: return
	if is_instance_valid(target.overlay): return
	var rank = pending
	target.refresh()
	target.celebrate(rank)
	if not is_instance_valid(target.overlay): return
	consume(rank.id)
	if in_match: target.set_meta("close_after_celebration", true)
