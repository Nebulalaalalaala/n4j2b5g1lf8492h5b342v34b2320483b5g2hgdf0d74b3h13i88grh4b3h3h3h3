extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# One account-scoped owner. No match joins, credential writes or native XP writes.
var profile_service
var ledger
var screen
var navigation
var activity
var hud
var match_xp
var looks
var promotions
var custom_badges
var home_stats
var map_notices = {}
var moment_sound
var elapsed = 0.0
var look_timer = 0

func _ready():
	ledger = load(ModPaths.path("JourneyLedger.gd")).new()
	ledger.configure("")
	# Active-time tracking must run all session, not only while Journey is open.
	activity = load(ModPaths.path("JourneyActivity.gd")).new()
	add_child(activity)
	add_child(load(ModPaths.path("JourneyCertified.gd")).new())
	# In-match Journey button under the settings cog.
	hud = load(ModPaths.path("JourneyHud.gd")).new()
	hud.controller = self
	add_child(hud)
	looks = load(ModPaths.path("JourneyLooks.gd")).new()
	add_child(looks)
	promotions = load(ModPaths.path("JourneyMatchPromotions.gd")).new()
	promotions.controller = self
	add_child(promotions)
	custom_badges = load(ModPaths.path("JourneyCustomBadges.gd")).new()
	add_child(custom_badges)
	match_xp = load(ModPaths.path("JourneyMatchXP.gd")).new()
	match_xp.controller = self
	match_xp.connect("qualified", self, "_qualified", [], CONNECT_DEFERRED)
	add_child(match_xp)
	get_tree().connect("node_added",self,"_consider_home")
	call_deferred("_scan_existing",get_tree().root)

func _scan_existing(node):
	_consider_home(node)
	for child in node.get_children():
		_scan_existing(child)

func _consider_home(node):
	if node.name == "HomeScene":
		call_deferred("_attach_home",weakref(node))

func _attach_home(reference):
	var home = reference.get_ref()
	if not is_instance_valid(home) or is_instance_valid(screen):
		return
	var content = home.get_node_or_null("MainContentContainer")
	if content == null:
		content = home.get_node_or_null("HomeScene/MainContentContainer")
	if content == null:
		return
	var tabs = content.get_node_or_null("BottomPanel/Tabs")
	var pages = content.get_node_or_null("SafeArea/FocusGroup/Paginator")
	if tabs == null or pages == null:
		return
	_sync_account()
	var candidate = load(ModPaths.path("JourneyScreen.gd")).new()
	candidate.profile_service = profile_service
	candidate.activity = activity
	candidate.custom_badges = custom_badges
	candidate.build(ledger)
	# Paginator fills the screen; reserve native identity and navigation bars.
	candidate.add_constant_override("margin_top",112)
	candidate.add_constant_override("margin_bottom",120)
	var adapter = load(ModPaths.path("JourneyNavigation.gd")).new()
	home.add_child(adapter)
	if not adapter.attach(tabs,pages,candidate):
		candidate.free()
		adapter.queue_free()
		push_warning("Journey navigation unavailable: native layout did not match.")
		return
	screen = candidate
	navigation = adapter
	var home_page = pages.get_node_or_null("HOME")
	if home_page != null:
		home_stats = load(ModPaths.path("JourneyHomeStats.gd")).new()
		home_stats.controller = self
		home_page.add_child(home_stats)
	pages.connect("page_changed",self,"_page_changed")

func _page_changed(page):
	if is_instance_valid(home_stats) and home_stats.get_parent() == page:
		home_stats.refresh()
	if page == screen:
		_sync_account()
		screen._select_section("Overview")
		screen.call_deferred("start_intro")
		screen.call_deferred("refresh_native_stats")

func _sync_account():
	var owner = ""
	if profile_service != null and profile_service.store != null:
		owner = profile_service.store.account_id
	activity.configure(owner)
	if owner == ledger.account_id:
		return
	ledger.configure(owner)
	if is_instance_valid(screen):
		screen._select_section("Overview")

func _process(delta):
	elapsed += delta
	if elapsed >= 1.0:
		elapsed = 0.0
		_sync_account()
		if is_instance_valid(home_stats) and home_stats.get_parent().is_visible_in_tree():
			home_stats.refresh()
		look_timer += 1
		if look_timer >= 30:
			look_timer = 0
			_publish_look()

# Your featured badges and equipped finish, for other players' clients.
func _publish_look():
	if not is_instance_valid(screen) or screen.model.empty() or screen.model.get("preview", false) or screen.model.get("achievements") == null:
		return
	var moonlight = get_node_or_null("/root/Moonlight")
	var storage = moonlight.storage if moonlight != null and moonlight.get("storage") != null else null
	if storage == null or str(storage.storage_get("account.user.id", "")) != str(ledger.account_id):
		return
	var badges = []
	for key in screen.model.achievements.get("featured", []):
		for c in screen.model.achievements.collections:
			if c.key == key and int(c.tier) > 0:
				badges.append({"key": c.key, "tier": int(c.tier)})
	looks.publish(str(ledger.account_id), badges, str(hud.equipped_finish().get("key", "")))

func has_screen() -> bool:
	return is_instance_valid(screen) and screen.is_inside_tree()

func _qualified(event):
	var presentation = load(ModPaths.path("JourneyMomentData.gd"))
	if event.account != ledger.account_id or str(presentation.preference(self, self, "notify", "after_match")) == "inbox" or not bool(presentation.preference(self, self, "qualification_toast", true)):
		return
	var service = profile_service
	if service == null or service.store == null or str(service.store.account_id) != str(event.account):
		return
	var active_game = service.game
	if not is_instance_valid(active_game) or service._synthetic() or active_game.is_server() or active_game.is_custom_game:
		return
	var data = active_game.wp_game_data
	if data.is_replay or data.is_time_trial or data.is_level_editor or data.is_tutorial or active_game.is_in_lobby():
		return
	var level = active_game.level.loaded_level
	if level == null or str(level.level_id) != str(event.map_id):
		return
	# Trust the local player's confirmed finish, not the rank replica that may
	# arrive later. The observer also checks game/account/match/round identity.
	if not is_instance_valid(match_xp) or not match_xp.is_qualification_current(event, active_game):
		return
	var progress = load(ModPaths.path("JourneyMomentData.gd")).previous_completion(service.store.records, event.map_id)
	var objective = "first" if int(event.rank) == 1 else "finish"
	var key = "%s:%s:%s" % [event.account, event.get("match_id", event.map_id), event.get("round", event.rank)]
	if map_notices.has(key):
		return
	var parent = get_tree().current_scene
	if parent == null:
		return
	map_notices[key] = true
	# Bound this launch-only deduplication set. A finished round is also marked
	# by the match observer, so old keys do not need to be retained forever.
	if map_notices.size() > 256:
		map_notices.clear()
		map_notices[key] = true
	var old = parent.get_node_or_null("JourneyMapToast")
	if old != null:
		old.queue_free()
	var toast = load(ModPaths.path("JourneyMapToast.gd")).new()
	toast.name = "JourneyMapToast"
	toast.controller = self
	toast.event = event.duplicate()
	toast.event.name = str(level.level_name)
	toast.event.new_objective = not bool(progress[objective])
	parent.add_child(toast)

func play_moment(key, pitch = 1.0):
	if is_instance_valid(screen):
		screen.play(key, pitch)
		return
	if not is_instance_valid(moment_sound):
		moment_sound = load(ModPaths.path("JourneySound.gd")).new("")
		add_child(moment_sound)
	var presentation = load(ModPaths.path("JourneyMomentData.gd"))
	moment_sound.enabled = bool(presentation.preference(self, self, "sounds", true))
	moment_sound.volume = float(presentation.preference(self, self, "volume", 0.8))
	moment_sound.play(key, pitch)
