extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")

# Reads the existing goal resolvers only when history/XP changes. No awards,
# claims, profile requests, history edits or extra achievement system.
class ReadOnlyStore:
	extends "user://mod/tools/journey/data/JourneyStore.gd"
	func save() -> bool: return false
class GoalView:
	extends Reference
	var model = {}
	var journey_store
	var ledger

var controller
var account = ""
var last_record = ""
var revision = -1
var baseline = []
var pending = []
var elapsed = 0.0
var ui
var definitions
var models
var achievements
var quests
var pages
var view
var pin_stamp = -1
var previewing = false

func _ready():
	definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
	models = load(ModPaths.path("JourneyModel.gd")).new()
	achievements = load(ModPaths.path("JourneyAchievements.gd")).new()
	quests = load(ModPaths.path("JourneyQuests.gd")).new()
	view = GoalView.new()
	view.journey_store = ReadOnlyStore.new()
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	pages = load(ModPaths.path("JourneyPages.gd")).new(view, ui)

func _process(delta):
	elapsed += delta
	if elapsed < 0.5: return
	elapsed = 0.0
	var service = controller.profile_service
	if service == null or service.store == null: return
	var owner = str(service.store.account_id)
	if owner.empty() or owner != str(controller.ledger.account_id): return
	var records = service.store.records
	var newest = str(records[-1].id) if not records.empty() else ""
	var stamp = File.new().get_modified_time("user://goobplayability/journey".plus_file(owner.sha256_text() + ".ui.json"))
	if is_instance_valid(controller.screen) and controller.screen.design_preview:
		previewing = true
		pending = []
		account = owner
		last_record = newest
		revision = int(controller.ledger.revision)
		baseline = []
		return
	if previewing:
		previewing = false
		baseline = snapshot()
		return
	if owner != account:
		account = owner
		last_record = newest
		revision = int(controller.ledger.revision)
		pin_stamp = stamp
		pending = []
		baseline = snapshot()
		return # Never celebrate historical imports or another account's progress.
	if stamp != pin_stamp and newest == last_record and revision == int(controller.ledger.revision):
		pin_stamp = stamp
		baseline = snapshot() # Newly pinned goals need a baseline before playing.
	if newest != last_record or revision != int(controller.ledger.revision):
		var next = snapshot()
		merge_changes(changes(baseline, next))
		baseline = next
		if newest != last_record and not newest.empty():
			var pb = personal_best(records, records[-1])
			var saved_this_launch = false
			for record in service.store.session:
				saved_this_launch = saved_this_launch or str(record.id) == newest
			if not pb.empty() and saved_this_launch:
				pb.account = account
				pending.append(pb)
		last_record = newest
		revision = int(controller.ledger.revision)
	if pending.empty() or not safe_to_show(service): return
	if str(Data.preference(self, controller, "notify", "after_match")) == "inbox":
		pending = []
		return
	var scene = get_tree().current_scene
	if scene == null or scene.get_node_or_null("JourneyMapToast") != null: return
	var event = pending.pop_front()
	var toast = load(ModPaths.path("JourneyMapToast.gd")).new()
	toast.name = "JourneyMapToast"
	toast.controller = controller
	toast.event = event
	scene.add_child(toast)

func snapshot() -> Array:
	# Reload UI choices read-only, including pins changed by an in-match screen.
	view.journey_store.account_id = ""
	view.journey_store.configure(account)
	view.journey_store.test = {} # display-only test quest completions are not progress
	if view.journey_store.pins.empty(): return []
	view.ledger = controller.ledger
	view.model = models.build(view.ledger, definitions, controller.profile_service)
	if view.model.stats == null: return []
	view.model.stats.records = view.model.stats.store.records
	var derived = achievements.build(view.model.stats.records, view.journey_store)
	view.model.achievements = derived.achievements
	view.model.milestones = derived.milestones
	var activity = controller.activity.snapshot() if is_instance_valid(controller.activity) and controller.activity.writable else null
	view.model.quests = quests.build(view.model.stats.records, view.journey_store, activity)
	return pages.resolve_pins(view.model, view.journey_store.pins)

static func changes(before, after) -> Array:
	var old = {}
	for pin in before: old[str(pin.spec.kind) + ":" + str(pin.spec.key)] = pin
	var out = []
	for pin in after:
		var key = str(pin.spec.kind) + ":" + str(pin.spec.key)
		if not old.has(key): continue
		var previous = old[key]
		# Tier targets may advance when an achievement is reached. Preserve the
		# previous target for that announcement (94 → 100 / 100, not 100 / 350).
		var target = int(previous.target)
		var from = min(target, int(previous.value))
		var to = min(target, int(pin.value))
		if to <= from: continue
		out.append({"kind": "goal", "key": key, "account": "", "name": str(previous.name), "icon": str(pin.icon),
			"from": from, "to": to, "target": target, "moment": "goal"})
	return out

func merge_changes(items):
	for item in items:
		item.account = account
		var merged = false
		for existing in pending:
			if str(existing.get("key", "")) == str(item.key) and int(existing.get("target", -1)) == int(item.target):
				existing.to = item.to
				merged = true
				break
		if not merged: pending.append(item)

static func personal_best(records, newest) -> Dictionary:
	if newest.get("custom", false) or str(newest.get("mode", "")) != "time_trial" or str(newest.get("result", "")) != "finish" or float(newest.get("finish_time", 0)) <= 0: return {}
	var best = -1.0
	for record in records:
		if str(record.id) == str(newest.id) or record.get("custom", false): continue
		if str(record.mode) == "time_trial" and str(record.map_id) == str(newest.map_id) and str(record.result) == "finish" and float(record.finish_time) > 0:
			best = float(record.finish_time) if best < 0 else min(best, float(record.finish_time))
	if best < 0 or float(newest.finish_time) >= best - 0.000001: return {}
	return {"moment": "pb", "account": "", "name": str(newest.get("map_name", "Level")), "time": float(newest.finish_time),
		"gain": best - float(newest.finish_time), "record_id": str(newest.id)}

func safe_to_show(service):
	if service._synthetic(): return false
	var game = service.game
	if not is_instance_valid(game): return true
	if game.wp_game_data.is_replay or game.wp_game_data.is_level_editor or game.wp_game_data.is_tutorial or game.is_custom_game: return false
	if game.wp_game_data.is_time_trial: return game.is_game_over()
	return is_instance_valid(controller.match_xp) and controller.match_xp.terminal and controller.match_xp.terminal_age >= 1.0
