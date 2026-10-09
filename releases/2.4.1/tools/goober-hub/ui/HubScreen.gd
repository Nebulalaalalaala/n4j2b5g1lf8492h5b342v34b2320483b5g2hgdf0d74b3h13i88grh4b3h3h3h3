extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
const SECTIONS = [["Home", "activity"], ["Profile", "goober"], ["Clans", "crown"], ["Passport", "compass"], ["Messages", "inbox"]]
const BUILDERS = {"Home": "HubHome.gd", "Profile": "HubProfile.gd", "Clans": "HubClanPage.gd", "Passport": "HubPassport.gd", "Messages": "HubMessages.gd"}
const DISPLAY_ZOOM = 0.86
var hub
var ui
var root
var frame
var content
var scroll
var notice
var status_pill
var nav = {}
var builders = {}
var page = "Home"
# Page state, kept while you move around the Hub.
var profile_id = ""
var profile_tab = "Overview"
var clan_id = ""
var clan_tab = "Overview"
var passport_tab = "Overview"
var feed_scope = "Friends & clan"
var thread = ""
var query = ""
var _notice_until = 0

# hub_identity.png: white silhouette for the native bottom bar; hub_logo.png: coloured, for the header.
static func icon_texture(file = "hub_identity.png"):
	# Older update packages omitted the home/HUD variants. Their existing pink-bean
	# header logo keeps the Hub reachable instead of silently dropping its buttons.
	var candidates = [file]
	if file != "hub_logo.png": candidates.append("hub_logo.png")
	for candidate in candidates:
		var path = ModPaths.ROOT + "tools/goober-hub/assets/" + candidate
		if not File.new().file_exists(path): continue
		var pixels = Image.new()
		if pixels.load(path) != OK: continue
		var result = ImageTexture.new()
		result.create_from_image(pixels, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		return result
	return null

func _ready():
	layer = 205
	pause_mode = Node.PAUSE_MODE_PROCESS
	ui = load(ModPaths.path("HubUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	for key in BUILDERS:
		var builder = load(ModPaths.path(BUILDERS[key])).new()
		builder.screen = self
		builder.ui = ui
		builder.hub = hub
		builders[key] = builder
	root = Control.new()
	root.name = "GooberHubInterface"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	frame = PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var clear = StyleBoxEmpty.new()
	for edge in ["left", "right", "top", "bottom"]: clear.set("content_margin_" + edge, 16)
	frame.add_stylebox_override("panel", clear)
	root.add_child(frame)
	var all = ui.box(frame, true, 16)
	var header = ui.box(all, false, 16)
	var mark = ui.inset(header, 6, 16, Color("f2f7ff"))
	var logo = TextureRect.new()
	logo.texture = icon_texture("hub_logo.png")
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.rect_min_size = Vector2(44, 44)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(logo)
	var brand = ui.title(header, "Goober Hub", 40)
	brand.add_color_override("font_color_shadow", ui.BASE)
	brand.add_constant_override("shadow_offset_y", 3)
	ui.spacer(header)
	status_pill = ui.box(header, false, 0)
	ui.action(header, "", self, "reload", null, "secondary", "session").hint_tooltip = "Refresh"
	ui.action(header, "", hub, "back", null, "secondary", "close").hint_tooltip = "Close Goober Hub"
	var dock = ui.surface(all, ui.PANEL, 6, 24)
	var tabs = ui.box(dock, false, 6)
	tabs.alignment = BoxContainer.ALIGN_CENTER
	for entry in SECTIONS:
		var b = ui.action(tabs, entry[0], self, "select", entry[0], "tab", entry[1], ui.page_color(entry[0]))
		ui.grow(b)
		b.rect_min_size.y = 50
		nav[entry[0]] = b
	notice = ui.text(all, "", 18, ui.GOLD)
	notice.autowrap = true
	notice.hide()
	scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	ui.grow(scroll, true, true)
	all.add_child(scroll)
	var bar = scroll.get_v_scrollbar()
	bar.rect_min_size.x = 12
	bar.add_stylebox_override("scroll", ui.flat(ui.BASE, 6, 3, 0, ui.BASE, false))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_stylebox_override(state, ui.flat(ui.SKY if state == "grabber" else ui.HUB_PINK, 6, 4, 0, ui.BASE, false))
	var room = MarginContainer.new()
	room.add_constant_override("margin_right", 24)
	room.add_constant_override("margin_bottom", 12)
	ui.grow(room)
	scroll.add_child(room)
	content = ui.box(room, true, 22)
	ui.grow(content)
	for source in [hub.feed, hub.clans, hub.chat, hub.profiles, hub.shared_creations]:
		source.connect("changed", self, "_data_changed")
	hub.shared_creations.connect("completed",self,"show_notice")
	hub.clans.connect("acted", self, "_clan_acted")
	hub.chat.connect("failed", self, "show_notice")
	get_viewport().connect("size_changed", self, "fit")
	fit()
	root.hide()
	set_process(false)

func fit():
	var size = get_viewport().get_visible_rect().size
	var factor = max(0.1, min(size.x / 1920.0, size.y / 1080.0))
	root.rect_scale = Vector2.ONE * factor * DISPLAY_ZOOM
	root.rect_size = size / (factor * DISPLAY_ZOOM)
	frame.rect_position = Vector2(60, 116) / DISPLAY_ZOOM
	frame.rect_size = Vector2(1800, 824) / DISPLAY_ZOOM
	var navigation = hub.entry_navigation
	if is_instance_valid(navigation) and navigation.has_method("frame_rect"):
		var native_rect = navigation.frame_rect(factor)
		if native_rect is Rect2:
			frame.rect_position = native_rect.position / DISPLAY_ZOOM
			frame.rect_size = native_rect.size / DISPLAY_ZOOM

func is_open():
	return is_instance_valid(root) and root.visible

func open():
	root.show()
	hub.chat.open = true
	fit()
	_load_page()
	render()
	set_process(true)

func close():
	hub.chat.open = false
	if is_instance_valid(root): root.hide()
	set_process(false)

func select(section):
	page = str(section)
	if page == "Profile": profile_id = ""
	if page == "Clans": clan_id = ""
	query = ""
	_load_page()
	render()

func show_profile(user_id):
	if str(user_id) == hub.TEST_ID:
		return
	page = "Profile"
	profile_id = "" if str(user_id) == hub.store.account else str(user_id)
	profile_tab = "Overview"
	_load_page()
	render()

func show_clan(id):
	page = "Clans"
	clan_id = str(id)
	clan_tab = "Overview"
	_load_page()
	render()

func message(user_id):
	page = "Messages"
	thread = str(user_id)
	_load_page()
	render()

# Fetch what the page shows; results arrive through _data_changed.
func _load_page():
	var me = hub.store.account
	if page == "Home":
		hub.feed.fetch("friends", _circle())
		hub.feed.fetch("everyone")
		hub.clans.fetch()
		var ids = _circle()
		ids.append(me)
		hub.profiles.lookup(ids)
		_colors(ids)
	elif page == "Profile":
		var id = me if profile_id.empty() else profile_id
		hub.profiles.lookup([id])
		hub.profiles.load_native(id)
		hub.feed.fetch("player", [id], true)
		hub.clans.fetch()
	elif page == "Clans":
		hub.clans.fetch()
		var target = clan_id if not clan_id.empty() else hub.clans.mine
		if not target.empty():
			var ids = hub.clans.member_ids(target)
			ids += hub.clans.requests.get(target, [])
			hub.profiles.lookup(ids)
			_colors(ids)
			hub.feed.fetch("clan", hub.clans.member_ids(target), true)
	elif page == "Messages":
		hub.chat.poll()
		var ids = []
		for f in hub.friends(): ids.append(f.id)
		hub.profiles.lookup(ids)
		_colors(ids)
	elif page == "Passport":
		var ids = []
		for e in hub.store.encounters():
			if ids.size() < 40: ids.append(e.id)
		hub.profiles.lookup(ids)
		hub.profiles.load_native(me)
		if passport_tab == "Encounters": _colors(ids)

# Goober colours come from each player's game profile: one request per player,
# cached 10 minutes, at most 20 per page.
func _colors(ids):
	var n = 0
	for id in ids:
		if n >= 20: return
		if str(id) != hub.store.account and not hub.profiles.native.has(str(id)):
			hub.profiles.load_native(id)
			n += 1

# Friends plus clanmates: whose events "Friends & clan" shows.
func _circle() -> Array:
	var ids = []
	for f in hub.friends(): ids.append(f.id)
	for id in hub.clans.member_ids(hub.clans.mine):
		if not ids.has(id): ids.append(id)
	var me = hub.store.account
	if not me.empty() and not ids.has(me): ids.append(me)
	return ids

func render():
	if not is_open():
		return
	var keep_scroll = scroll.scroll_vertical
	if page == "Messages":
		builders.Messages._save_draft()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for key in nav:
		var selected = key == page
		var tint = ui.page_color(key)
		ui.paint_action(nav[key], "selected" if selected else "tab", tint)
		if selected:
			for state in ["normal", "hover", "focus", "pressed"]:
				nav[key].add_color_override("icon_color_" + state, tint.darkened(0.35))
	var unread = hub.chat.total_unread(hub.store.data.muted)
	nav.Messages.caption_label.text = "Messages" + (" (%d)" % unread if unread > 0 else "")
	status_changed()
	builders[page].build(content)
	scroll.scroll_vertical = keep_scroll

func status_changed():
	if not is_instance_valid(status_pill):
		return
	for child in status_pill.get_children():
		child.queue_free()
	var state = hub.identity.state
	var look = {"ready": ["Online", ui.MINT], "checking": ["Connecting", ui.SKY], "signed_out": ["Not signed in", ui.DIM],
		"missing": ["Server setup needed", ui.GOLD], "failed": ["Offline", ui.HUB_PINK]}.get(state, ["Offline", ui.HUB_PINK])
	var pill = ui.tag(status_pill, look[0], look[1])
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.hint_tooltip = {"missing": "Run docs/sql/GOOBER_HUB.sql and deploy the hub-verify function in Supabase.",
		"failed": "Couldn't reach Goober Hub: " + str(hub.identity.error)}.get(state, "")

func reload():
	hub.feed._fetched = {"friends": 0, "everyone": 0}
	hub.clans.fetch(true)
	hub.chat.poll()
	if hub.identity.state in ["failed", "missing"]: hub.identity.verify()
	_load_page()
	render()

func _data_changed():
	if is_open() and (page == "Messages" or not _typing()):
		render()

# Don't rebuild the page under someone typing a message or a clan name.
func _typing():
	var focus = root.get_focus_owner() if is_instance_valid(root) else null
	return focus is LineEdit or focus is TextEdit

func _clan_acted(action, ok, text):
	if ok:
		var done = {"create": "Clan founded.", "join": "Request sent." if str(text) == "requested" else "Welcome to the clan.", "leave": "You left the clan.",
			"accept": "Request accepted.", "decline": "Request declined.", "kick": "Member removed.", "promote": "Promoted to officer.",
			"demote": "Now a member.", "lead": "Leadership handed over.", "edit": "Clan updated."}
		show_notice(done.get(action, "Done."))
		var post = hub.clans.pending_post
		if action in ["create", "join"] and not post.empty() and str(text) != "requested":
			hub.feed.post(post.kind, post.kind + ":" + str(post.clan).to_lower(), {"clan": post.clan, "tag": post.tag})
		if action == "create" or action == "join":
			clan_id = ""
	else:
		show_notice(text)
	hub.clans.pending_post = {}
	_load_page()
	render()

# Opens a level as a time trial (shared level cards, Creations).
func play_level(level_id):
	var packed = GoodResourceLoader.load_resource("res://scenes/TimeTrialGameplayScene.tscn") if not str(level_id).empty() else null
	if packed == null:
		return
	var scene = packed.instance()
	var parameters = TimeTrialSceneParameters.new()
	parameters.mode = TimeTrialSceneParameters.TimeTrialSceneMode.TimeTrial
	parameters.level_id = str(level_id)
	scene.set("parameters", parameters)
	close()
	ScreenTransitions.fade_to_scene_node(scene)

func show_notice(text):
	notice.text = str(text)
	notice.visible = not str(text).empty()
	_notice_until = OS.get_unix_time() + 6

func _process(_delta):
	if notice.visible and OS.get_unix_time() >= _notice_until:
		notice.hide()

func _input(event):
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_ESCAPE:
		hub.back()
		get_tree().set_input_as_handled()
