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
var elapsed = 0.0

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
	match_xp = load(ModPaths.path("JourneyMatchXP.gd")).new()
	match_xp.controller = self
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
	pages.connect("page_changed",self,"_page_changed")

func _page_changed(page):
	if page == screen:
		_sync_account()
		screen._select_section("Overview")

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

func has_screen() -> bool:
	return is_instance_valid(screen) and screen.is_inside_tree()
