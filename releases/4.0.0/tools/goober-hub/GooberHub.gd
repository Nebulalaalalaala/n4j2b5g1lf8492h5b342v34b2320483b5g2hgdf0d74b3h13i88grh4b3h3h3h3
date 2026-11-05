extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Goober Hub: the social side of Goobplayability. Journey is your progression;
# the Hub is you next to everyone else (feed, profiles, clans, passport, messages).
signal unread_changed(count)
const ADMIN_ID = "96c5a97d-63c9-4dd7-bf47-d5ad48bb6cf2"
const TEST_ID = "00000000-0000-4000-8000-00000000e171"
var from_hud = false

var tool
var api
var identity
var profiles
var feed
var clans
var chat
var friend_service
var moderation
var shared_creations
var store
var encounters
var screen
var entry_navigation = null
var profile_service
var journey
var elapsed = 0.0
var _ticks = 0
var _published = ""

func configure(owner):
	tool = owner
	pause_mode = Node.PAUSE_MODE_PROCESS
	store = load(ModPaths.path("HubStore.gd")).new()
	api = load(ModPaths.path("HubApi.gd")).new()
	add_child(api)
	identity = _service("HubIdentity.gd")
	profiles = _service("HubProfiles.gd")
	feed = _service("HubFeed.gd")
	clans = _service("HubClans.gd")
	chat = _service("HubChat.gd")
	friend_service = load(ModPaths.path("HubFriends.gd")).new()
	friend_service.hub = self
	add_child(friend_service)
	moderation = _service("HubModeration.gd")
	moderation.hub = self
	shared_creations = _service("HubCreations.gd")
	shared_creations.hub = self
	encounters = load(ModPaths.path("HubEncounters.gd")).new()
	encounters.hub = self
	add_child(encounters)
	chat.connect("changed", self, "_chat_changed")
	identity.connect("changed", self, "_identity_changed")
	screen = load(ModPaths.path("HubScreen.gd")).new()
	screen.hub = self
	add_child(screen)

func _service(file):
	var node = load(ModPaths.path(file)).new()
	node.api = api
	if "identity" in node:
		node.identity = identity
	add_child(node)
	return node

func _process(delta):
	elapsed += delta
	if elapsed < 1.0:
		return
	elapsed = 0.0
	_ticks += 1
	_discover()
	var owner = account()
	if owner != store.account:
		store.configure(owner)
		_published = ""
	friend_service.sync(owner)
	identity.configure(owner)
	if identity.state == "banned" and _ticks % 30 == 0:
		moderation.refresh_self()
	if owner.empty():
		return
	# Friends feed the server's friends-only check; send them again when they change.
	if _ticks % 10 == 3:
		var ids = []
		for f in friends():
			if f.id != TEST_ID: ids.append(f.id)
		ids.sort()
		if PoolStringArray(ids).join(",") != PoolStringArray(identity.friend_ids).join(",") and (identity.signed_in() or identity.state == "checking") and not api.pending("verify"):
			identity.friend_ids = ids
			identity.verify()
	if _ticks % 600 == 2:
		profiles.load_native(owner)
	if (identity.state == "checking" and _ticks % 15 == 0) or (identity.state == "failed" and _ticks % 600 == 30):
		if not api.pending("verify"):
			identity.verify()
	if identity.signed_in() and _ticks % 60 == 5:
		feed.check(self)
		_publish_profile()

func account() -> String:
	var moonlight = get_node_or_null("/root/Moonlight")
	var session = moonlight.get("session") if moonlight != null else null
	return str(session.user_id) if session != null and not str(session.user_id).empty() else ""

func _discover():
	if is_instance_valid(profile_service) and is_instance_valid(journey):
		return
	for child in tool.get_children():
		var script = child.get_script()
		var file = script.resource_path.get_file() if script != null else ""
		if file == "ProfileObserver.gd":
			profile_service = child
		elif file == "JourneyHandler.gd":
			journey = child
	if not is_instance_valid(profile_service) or not is_instance_valid(journey):
		_scan(tool.get_tree().root, 0)

func _scan(node, depth):
	if depth > 4:
		return
	for child in node.get_children():
		var script = child.get_script()
		var file = script.resource_path.get_file() if script != null else ""
		if file == "ProfileObserver.gd" and not is_instance_valid(profile_service):
			profile_service = child
		elif file == "JourneyHandler.gd" and not is_instance_valid(journey):
			journey = child
		_scan(child, depth + 1)

func journey_model() -> Dictionary:
	if is_instance_valid(journey) and is_instance_valid(journey.get("screen")) and journey.screen.model is Dictionary and not journey.screen.model.get("preview", false):
		if str(journey.ledger.account_id) == store.account:
			return journey.screen.model
	return {}

func history_store():
	return profile_service.store if is_instance_valid(profile_service) and profile_service.store != null and str(profile_service.store.account_id) == store.account else null

func history_records() -> Array:
	var history = history_store()
	return history.records if history != null else []

func friends() -> Array:
	if friend_service != null and friend_service.loaded:
		var loaded = friend_service.accepted()
		loaded.sort_custom(self, "_online_first")
		if account() == ADMIN_ID:
			profiles.remember(TEST_ID, "Test account")
			loaded.append({"id": TEST_ID, "name": "Test account", "online": true, "status": "Test"})
		return loaded
	var moonlight = get_node_or_null("/root/Moonlight")
	var module = moonlight.get("friends") if moonlight != null else null
	var list = []
	if module == null or not module.get("friend_list_unfiltered") is Array:
		return list
	var statuses = module.get("friend_statuses")
	for entry in module.friend_list_unfiltered:
		var user = entry.get("user") if entry != null else null
		if user == null or int(entry.get("state")) != 0:
			continue
		var id = str(user.get("id"))
		var name = str(user.get("display_name")).strip_edges()
		if name.empty():
			name = str(user.get("username")).strip_edges()
		profiles.remember(id, name)
		var online = statuses is Dictionary and statuses.has(id)
		list.append({"id": id, "name": name, "online": online, "status": str(statuses.get(id, "")) if online else ""})
	list.sort_custom(self, "_online_first")
	# The admin's private test account (see hub_test_pair in GOOBER_HUB.sql).
	if account() == ADMIN_ID:
		profiles.remember(TEST_ID, "Test account")
		list.append({"id": TEST_ID, "name": "Test account", "online": true, "status": "Test"})
	return list

func _online_first(a, b):
	return a.online and not b.online if a.online != b.online else a.name.to_lower() < b.name.to_lower()

func is_friend(user_id) -> bool:
	for f in friends():
		if f.id == str(user_id):
			return true
	return false

# Certified levels this player made (Journey's cached certified list + catalog).
func creations(user_id) -> Array:
	var list = []
	var seen = {}
	var certified = ModPaths.try_load(ModPaths.path("JourneyCertified.gd"))
	var levels = certified.load_cache().get("levels", []) if certified != null else []
	for level in levels:
		if level is Dictionary and str(level.get("author_id", "")) == str(user_id) and not seen.has(str(level.get("id", ""))):
			seen[str(level.id)] = true
			list.append({"id": str(level.id), "name": str(level.get("name", "")), "mode": str(level.get("mode", "")), "at": int(level.get("certified_at", 0))})
	return list

func featured_badges() -> Array:
	var model = journey_model()
	var list = []
	if model.get("achievements") != null:
		for key in model.achievements.get("featured", []):
			for c in model.achievements.collections:
				if c.key == key and int(c.tier) > 0:
					list.append({"key": c.key, "tier": int(c.tier)})
	return list

func _publish_profile():
	var model = journey_model()
	var records = history_records()
	var maps = {}
	for r in records:
		maps[str(r.map_id)] = true
	var data = {"bio": str(store.data.profile.get("bio", "")), "favorites": store.data.profile.get("favorites", []), "maps": maps.size(),
		"activity": str(store.data.profile.get("activity", "everyone"))}
	if not model.empty():
		data.xp = int(model.get("xp", 0))
		data.rank = str(model.rank.name) if model.get("rank") != null else ""
	var wins = profiles.stat(store.account, profiles.stat_key("Stat_GamesWon"))
	if wins > 0:
		data.wins = wins
		data.games = profiles.stat(store.account, profiles.stat_key("Stat_GamesPlayed"))
	if is_instance_valid(journey) and journey.get("hud") != null and journey.hud.has_method("equipped_finish"):
		data.finish = str(journey.hud.equipped_finish().get("key", ""))
	var body = JSON.print(data)
	if body != _published:
		_published = body
		api.call_fn("hub_update_profile", identity.auth({"p_data": data}), "profile")

# everyone / friends (friends and clanmates) / nobody. The server hides older events too.
func set_activity_shown(value):
	store.data.profile.activity = value
	store.save()
	_publish_profile()

func save_profile(bio, favorites):
	store.data.profile = {"activity": str(store.data.profile.get("activity", "everyone")), "bio": str(bio).strip_edges().substr(0, 120), "favorites": favorites.slice(0, min(5, favorites.size()) - 1) if not favorites.empty() else []}
	store.save()
	if identity.signed_in():
		_publish_profile()

func _identity_changed():
	if identity.signed_in():
		clans.fetch(true)
		_publish_profile()
	if is_instance_valid(screen):
		screen.status_changed()

func _chat_changed():
	emit_signal("unread_changed", chat.total_unread(store.data.muted))

func encounters_changed():
	if is_instance_valid(screen) and screen.is_open() and screen.page == "Passport":
		screen.render()

func is_interface_open():
	return is_instance_valid(screen) and screen.is_open()

func open():
	from_hud = false
	tool._set_menu_open(false)
	screen.open()
	tool._update_mouse_capture()

# From the match HUD button: closing goes straight back to the game.
func open_from_hud():
	if is_interface_open():
		return
	from_hud = true
	entry_navigation = null
	screen.open()
	tool._update_mouse_capture()

func back():
	screen.close()
	if from_hud:
		from_hud = false
		tool._update_mouse_capture()
		return
	if is_instance_valid(entry_navigation):
		entry_navigation.return_home()
		entry_navigation = null
	else:
		tool._set_menu_open(true)
	tool._update_mouse_capture()

# From elsewhere (e.g. the Journey leaderboard): switch to the Hub tab and show this player.
func open_profile(user_id):
	var navigation = tool.get_node_or_null("GooberHubNavigation")
	if is_instance_valid(navigation) and is_instance_valid(navigation.get("paginator")) and navigation.paginator.is_inside_tree():
		navigation.open_page("GOOBER_HUB")
	elif not is_interface_open():
		open()
	screen.call_deferred("show_profile", str(user_id))

# The game's own profile dialog, as the native leaderboards open it.
func open_native_profile(user_id):
	var scene = get_tree().current_scene
	var dialog = load("res://project_specific/ui/UIPlayerProfileDialog.tscn")
	if scene == null or not dialog is PackedScene:
		return
	var profile = dialog.instance()
	profile.layer = 210   # above the Hub (205)
	scene.add_child(profile)
	profile.call("show_player_profile_dialog", str(user_id))

func open_journey():
	if is_instance_valid(entry_navigation):
		entry_navigation.open_page("JOURNEY")
