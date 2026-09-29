extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Goobplayability -- Game Tools
#
# Accessed through the main Goobplayability GUI. Local Mode owns its own
# local server/client scene; other tools still target the discovered player.
#
# WHERE THESE TOOLS RUN
# ---------------------
# The tools target whichever current game and local player TASTool discovers.
# There is deliberately no local-simulation or server-authority gate. Online
# matches remain server-authoritative, so their snapshots may overwrite a
# client-side change, but Game Tools itself does not exclude those matches.
# Missing game/player objects or properties still fail closed.

const FONT_PATH: = "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"

# Mirrors of Goobplayability's classic palette. These are passed straight to
# TASTool's own style helpers, which remap them by value when Claude
# Experimental Mode is on -- so this window follows the theme for free
# without duplicating the whole theming block.
const COLOR_PANEL_BG: = Color(0, 0.129412, 0.262745, 0.9)
const COLOR_PANEL_BORDER: = Color(0, 0, 0, 0.55)
const COLOR_BLUE: = Color(0.211765, 0.541176, 0.854902)
const COLOR_PLAY_GREEN: = Color(0.117647, 0.690196, 0.423529)
const COLOR_PINK_DARK: = Color(0.8, 0.117647, 0.439216)
const COLOR_WHITE: = Color(1, 1, 1)
const COLOR_TEXT_DIM: = Color(0.72, 0.8, 0.95)

var tas_tool = null

var gui_enabled: = false
var _infinite_dash_enabled: = false
var _infinite_dash_script = null
var _last_status_text: = ""

var _access_button: Button = null
var _modal_root: Control = null
var _dash_button: Button = null
var _status_label: Label = null
var _account_access = null
var _local_session = null
var _local_status: Label = null
var _solo_queue = null
var _emote_wheel = null
var _editor_plus = null
var _ping_optimizer = null
var _status_elapsed = 0.0
var _tool_grid
var _tool_cards = {}
var _tool_details = {}
var _details_root
var _tools_scroll
var _emote_picker


func _ready() -> void:
	layer = 152
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_physics_process(true)
	# Same trick TASPostPhysicsGuard.gd uses: run at the very end of the
	# physics callback order, after Goober Dash's native tick has already
	# written whatever it was going to write to the player this tick.
	set_process_priority(1000000)


# The UI is built here rather than in _ready() because TASTool creates this
# node with add_child() (which fires _ready) and only calls configure()
# afterwards -- so tas_tool, and therefore its style helpers, don't exist yet
# during _ready().
func configure(tool_ref) -> void:
	tas_tool = tool_ref
	tas_tool._ping_optimizer_enabled = bool(SavedSettings.get_value("ping_optimizer_enabled",true))
	var account_script = ModPaths.try_load(ModPaths.path("AccountAccess.gd"))
	if account_script != null and account_script.can_instance():
		_account_access = account_script.new()
		add_child(_account_access)
	var effects_script = load(ModPaths.path("ClientEffectFixes.gd"))
	if effects_script != null and effects_script.can_instance():
		add_child(effects_script.new())
	_emote_wheel = load(ModPaths.path("EmoteWheel.gd")).new()
	_emote_wheel.tool = tas_tool
	add_child(_emote_wheel)
	add_child(load(ModPaths.path("SeasonDeals.gd")).new())
	var profile_script = ModPaths.try_load(ModPaths.path("ProfileObserver.gd"))
	if profile_script != null and profile_script.can_instance():
		var profile_observer = profile_script.new()
		profile_observer.tool = tas_tool
		add_child(profile_observer)
		var journey_script = ModPaths.try_load(ModPaths.JOURNEY_HANDLER)
		if journey_script != null and journey_script.can_instance():
			var journey = journey_script.new()
			journey.profile_service = profile_observer
			profile_observer.journey = journey
			add_child(journey)
	_build_ui()
	var editor_script = ModPaths.try_load(ModPaths.path("EditorPlus.gd"))
	if editor_script != null and editor_script.can_instance():
		_editor_plus = editor_script.new()
		_editor_plus.tool = tas_tool
		add_child(_editor_plus)


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if _access_button != null and is_instance_valid(_access_button):
		_access_button.visible = false
	if not value:
		close_window()


func set_claude_experimental_icons_enabled(_value: bool) -> void:
	# Nothing to do: this window is styled entirely through TASTool's own
	# helpers, which already apply the active theme when the controls are
	# built. Kept so TASTool's pass-through call has something to land on.
	pass


func is_open() -> bool:
	return _modal_root != null and is_instance_valid(_modal_root) and _modal_root.visible


func open_window() -> void:
	if tas_tool != null and tas_tool.has_method("_open_module_page") and tas_tool._open_module_page("game"):
		return
	if _modal_root != null and is_instance_valid(_modal_root):
		_modal_root.visible = true
		_refresh_status(true)


func close_window() -> void:
	if _modal_root != null and is_instance_valid(_modal_root):
		_modal_root.visible = false


# ----------------------------------------------------------------------
#  UI
# ----------------------------------------------------------------------
func _build_ui() -> void:
	if tas_tool == null or not is_instance_valid(tas_tool):
		return

	# Workspace owns module access; do not create an in-game launcher.

	var root: = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	_modal_root = root

	var shade: = ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.72)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)

	var panel: = PanelContainer.new()
	panel.anchor_left = 0.24
	panel.anchor_top = 0.16
	panel.anchor_right = 0.76
	panel.anchor_bottom = 0.84
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_PANEL_BG, COLOR_PANEL_BORDER, 4, 24))
	root.add_child(panel)

	var margin: = MarginContainer.new()
	margin.add_constant_override("margin_left", 28)
	margin.add_constant_override("margin_right", 28)
	margin.add_constant_override("margin_top", 24)
	margin.add_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var column: = VBoxContainer.new()
	column.add_constant_override("separation", 16)
	var scroll = ScrollContainer.new()
	_tools_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	margin.add_child(scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var title_font: DynamicFont = tas_tool.call("_make_font", 34)
	var title: Label = tas_tool.call("_make_label", "GAME TOOLS", title_font, COLOR_WHITE)
	column.add_child(title)
	_tool_grid = GridContainer.new()
	_tool_grid.columns = 3
	_tool_grid.add_constant_override("hseparation",12)
	_tool_grid.add_constant_override("vseparation",12)
	_tool_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_tool_grid)
	_tool_grid.connect("resized",self,"_resize_cards")
	_add_tool_card("optimizer","Optimizer","optimizer","Toggle performance optimization",true)
	if ModPaths.has("InfiniteDash.gd"):
		_add_tool_card("dash","Infinite dash","dash","Toggle infinite dash; online authority may override it",true)
	if ModPaths.has("LocalSession.gd"):
		_add_tool_card("local","Local mode","local","Open local play controls",true)
	if ModPaths.has("AccountAccess.gd"):
		_add_tool_card("accounts","Accounts","accounts","Open your saved accounts",false)
	_add_tool_card("settings","Account settings","settings","Open native account settings",false)
	_add_tool_card("name","Change name","name","Open native name change",false)
	_add_tool_card("emotes","Emote wheel","emotes","Toggle the emote wheel; configure its key with the dots",true)
	var details = VBoxContainer.new()
	_details_root = details
	details.add_constant_override("separation",12)
	column.add_child(details)
	var back = tas_tool._make_button("<  ALL TOOLS",COLOR_BLUE,180)
	back.connect("pressed",self,"_show_tool_grid")
	details.add_child(back)
	_ping_optimizer = load(ModPaths.path("PingOptimizer.gd")).new()
	details.add_child(_ping_optimizer)
	_ping_optimizer.build(tas_tool)
	_ping_optimizer.connect("settings_changed",self,"_sync_cards")
	_tool_details["optimizer"] = _ping_optimizer
	var small_font: DynamicFont = tas_tool.call("_make_font", 18)
	var status: Label = tas_tool.call("_make_label", "", small_font, COLOR_TEXT_DIM)
	status.autowrap = true
	details.add_child(status)
	_status_label = status
	_tool_details["dash"] = status
	var local_details = VBoxContainer.new()
	details.add_child(local_details)
	_tool_details["local"] = local_details
	var local_row = HBoxContainer.new()
	local_details.add_child(local_row)
	var local_title: Label = tas_tool.call("_make_label", "LOCAL MODE", small_font, COLOR_WHITE)
	local_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_row.add_child(local_title)
	for entry in [["PLAY", "_play_local_mode"], ["REQUEUE", "_retry_local_mode"], ["STOP", "_stop_local_mode"]]:
		var local_button: Button = tas_tool.call("_make_button", entry[0], COLOR_PLAY_GREEN, 110)
		local_button.connect("pressed", self, entry[1])
		local_row.add_child(local_button)
	_local_status = tas_tool.call("_make_label", "Solo matchmaking · Only you · No online rewards", small_font, COLOR_TEXT_DIM)
	_local_status.autowrap = true
	local_details.add_child(_local_status)
	var emote_row = HBoxContainer.new()
	details.add_child(emote_row)
	_tool_details["emotes"] = emote_row
	emote_row.add_child(tas_tool.call("_make_label", "Emote wheel · hold key, point, release", small_font, COLOR_TEXT_DIM))
	var emote_binding = OptionButton.new()
	_emote_picker = emote_binding
	for text in ["Off", "F8", "F9", "F10"]:
		emote_binding.add_item(text)
	emote_binding.selected = _emote_wheel.KEYS.find(_emote_wheel.binding)
	emote_binding.connect("item_selected", self, "_wheel_binding_changed", [emote_binding])
	emote_row.add_child(emote_binding)

	var spacer: = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var close_button: Button = tas_tool.call("_make_button", "CLOSE", COLOR_PINK_DARK, 200)
	close_button.connect("pressed", self, "close_window")
	column.add_child(close_button)
	for section in _tool_details.values():
		section.hide()
	details.hide()
	_sync_cards()
	_refresh_status(true)

func _add_tool_card(key,title,symbol,tooltip,configurable):
	var card = load(ModPaths.path("GameToolCard.gd")).new()
	card.symbol = symbol
	card.name = "Tool_"+key
	card.rect_min_size = Vector2(160,160)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.hint_tooltip = tooltip
	card.add_stylebox_override("normal",tas_tool._make_flat_style(Color("182631"),Color("344653"),1,12))
	card.add_stylebox_override("hover",tas_tool._make_flat_style(Color("223642"),Color("65d5bc"),1,12))
	card.add_stylebox_override("pressed",tas_tool._make_flat_style(Color("28483f"),Color("65d5bc"),1,12))
	_tool_grid.add_child(card)
	var label = tas_tool._make_label(title,tas_tool._make_font(19),COLOR_WHITE)
	label.align = Label.ALIGN_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_top = 0.64
	label.anchor_bottom = 0.84
	label.anchor_right = 1.0
	card.add_child(label)
	var state = tas_tool._make_label("Open",tas_tool._make_font(16),COLOR_TEXT_DIM)
	state.align = Label.ALIGN_CENTER
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.anchor_top = 0.84
	state.anchor_bottom = 1.0
	state.anchor_right = 1.0
	card.add_child(state)
	if configurable:
		var config = Button.new()
		config.text = "..."
		config.hint_tooltip = "Configure "+title
		config.add_font_override("font",tas_tool._make_font(20))
		config.anchor_left = 1.0
		config.anchor_right = 1.0
		config.margin_left = -40
		config.margin_right = -6
		config.margin_top = 4
		config.margin_bottom = 36
		card.add_child(config)
		config.connect("pressed",self,"_show_tool_details",[key])
	card.connect("pressed",self,"_tool_card_pressed",[key])
	_tool_cards[key] = {"button":card,"state":state}

func _resize_cards():
	var columns = int(clamp(floor((_tool_grid.rect_size.x+12)/172),1,9))
	_tool_grid.columns = columns
	var side = max(160,floor((_tool_grid.rect_size.x-12*(columns-1))/columns))
	for entry in _tool_cards.values():
		entry.button.rect_min_size = Vector2(160,side)

func _show_tool_details(key):
	for section in _tool_details.values():
		section.hide()
	_tool_details[key].show()
	_tool_grid.hide()
	_details_root.show()
	_tools_scroll.scroll_vertical = 0
	if key == "dash":
		_refresh_status(true)

func _show_tool_grid():
	_details_root.hide()
	_tool_grid.show()
	_tools_scroll.scroll_vertical = 0

func _tool_card_pressed(key):
	match key:
		"optimizer": _ping_optimizer.set_enabled(not tas_tool._ping_optimizer_enabled)
		"dash": _on_infinite_dash_pressed()
		"local": _show_tool_details(key)
		"accounts": _open_account("open_signin")
		"settings": _open_account("open_settings")
		"name": _open_account("open_name_change")
		"emotes":
			if _emote_wheel.binding != 0:
				SavedSettings.set_value("game_tools_last_emote_key",_emote_wheel.binding)
				_emote_wheel.set_binding(0)
			else:
				_emote_wheel.set_binding(int(SavedSettings.get_value("game_tools_last_emote_key",KEY_F8)))
	_sync_cards()

func _sync_cards():
	if _ping_optimizer == null:
		return
	if _emote_picker != null:
		_emote_picker.selected = _emote_wheel.KEYS.find(_emote_wheel.binding)
	for key in _tool_cards:
		var entry = _tool_cards[key]
		var enabled = false
		match key:
			"optimizer": enabled = tas_tool._ping_optimizer_enabled
			"dash": enabled = _infinite_dash_enabled
			"emotes": enabled = _emote_wheel.binding != 0
		entry.button.active = enabled
		entry.button.update()
		if key in ["optimizer","dash","emotes"]:
			entry.state.text = "On" if enabled else "Off"
		if key == "optimizer" and enabled:
			entry.state.text = "On · "+_ping_optimizer.LEVELS[_ping_optimizer.level-1]

func _wheel_binding_changed(index: int, picker: OptionButton) -> void:
	_emote_wheel.set_binding(_emote_wheel.KEYS[index])
	picker.selected = _emote_wheel.KEYS.find(_emote_wheel.binding)
	picker.hint_tooltip = "Conflicting bindings are disabled automatically."
	_sync_cards()


func _open_account(method: String) -> void:
	if _account_access != null:
		close_window()
		_account_access.call(method)

func _play_local_mode() -> void:
	if is_instance_valid(_solo_queue) and (_solo_queue.waiting or _solo_queue.action != ""):
		return
	if is_instance_valid(_local_session):
		_local_status.text = "Local mode is already open. Stop it before restarting."
		return
	if _current_game() != null:
		_local_status.text = "Return to the home screen before starting Local Mode."
		return
	if _solo_queue == null:
		var queue_script = ModPaths.try_load(ModPaths.path("SoloQueue.gd"))
		if queue_script == null or not queue_script.can_instance():
			_local_status.text = "Matchmaking service could not load."
			return
		_solo_queue = queue_script.new()
		add_child(_solo_queue)
		_solo_queue.connect("allocated", self, "_solo_allocated")
		_solo_queue.connect("failed", self, "_solo_failed")
	_local_status.text = "Queuing for your own match..."
	_solo_queue.join_queue()

func _solo_allocated(data) -> void:
	var session_script = ModPaths.try_load(ModPaths.path("LocalSession.gd"))
	if session_script == null or not session_script.can_instance():
		_local_status.text = "Local Mode could not load."
		_solo_queue.cancel()
		return
	var session = session_script.new()
	var error = session.prepare_match(data)
	if not error.empty():
		_local_status.text = error
		session.free()
		_solo_queue.cancel()
		return
	_local_session = session
	session.connect("status_changed", self, "_local_status_changed")
	session.connect("tree_exiting", self, "_solo_scene_exited", [session])
	close_window()
	ScreenTransitions.fade_to_scene_node(session)

func _solo_failed(message) -> void:
	if is_instance_valid(_local_session):
		_local_session.stop()
	_local_status.text = message
	open_window()

func _solo_scene_exited(session) -> void:
	if _local_session == session:
		_local_session = null
		if is_instance_valid(_solo_queue):
			_solo_queue.cancel()

func _local_status_changed(text) -> void:
	_local_status.text = text
	if is_instance_valid(_local_session) and _local_session.playing and not _local_session.stopping and is_instance_valid(_solo_queue):
		_solo_queue.mark_ready()
	if is_instance_valid(_local_session) and _local_session.stopping:
		if is_instance_valid(_solo_queue):
			_solo_queue.cancel()
		open_window()

func _retry_local_mode() -> void:
	if is_instance_valid(_local_session) and _local_session.playing and not _local_session.stopping:
		_local_session.stop()
		_local_session = null
		_solo_queue.cancel()
		close_window()
		var transition = ScreenTransitions.fade_to_scene_node(Node.new())
		if transition is GDScriptFunctionState:
			yield(transition, "completed")
		yield(get_tree(), "idle_frame")
		_play_local_mode()
	else:
		_local_status.text = "Start Local Mode before retrying."

func _stop_local_mode() -> void:
	if is_instance_valid(_solo_queue):
		_solo_queue.cancel()
	if is_instance_valid(_local_session):
		_local_session.stop()
		_local_session = null
		close_window()
		ScreenTransitions.fade_to_scene_path("res://scenes/HomeScene.tscn")
	_local_status.text = "Solo matchmaking · Only you · No online rewards"

func _on_infinite_dash_pressed() -> void:
	_infinite_dash_enabled = not _infinite_dash_enabled
	if _dash_button != null and is_instance_valid(_dash_button):
		_dash_button.text = "INFINITE DASH:  ON" if _infinite_dash_enabled else "INFINITE DASH:  OFF"
	if tas_tool != null and is_instance_valid(tas_tool):
		tas_tool.call("_log_action", "Game Tools: Infinite Dash %s" % ("enabled" if _infinite_dash_enabled else "disabled"), null)
	_refresh_status(true)


# Reports each link in the chain separately rather than a single pass/fail,
# so when a tool doesn't take effect it's obvious whether no game was found,
# no local player exists, or dash_cooldown isn't going where we put it.
func _refresh_status(force: bool) -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	var lines: = []
	lines.append("Infinite Dash: %s" % ("ON" if _infinite_dash_enabled else "off"))

	var game = _current_game()
	if game == null:
		lines.append("Game: none found (not in a match or level right now)")
	else:
		var type_text: = "?"
		if "type" in game:
			type_text = str(game.type)
		lines.append("Game: found, type=%s" % type_text)
		var player = null
		if tas_tool != null and is_instance_valid(tas_tool):
			player = tas_tool.call("_get_local_player")
		if player == null or not is_instance_valid(player):
			lines.append("Local player: not found yet (still loading, or spectating)")
		elif not ("dash_cooldown" in player):
			lines.append("Local player: found, but it has no dash_cooldown property")
		else:
			var timer_text: = "n/a"
			if "dash_timer" in player:
				timer_text = str(player.dash_timer)
			lines.append("Local player: found -- dash_cooldown=%s, dash_timer=%s" % [str(player.dash_cooldown), timer_text])

	var text: String = PoolStringArray(lines).join("\n")
	if force or text != _last_status_text:
		_last_status_text = text
		_status_label.text = text


func _current_game():
	if tas_tool == null or not is_instance_valid(tas_tool):
		return null
	var game = tas_tool.call("_find_game")
	if game == null or not is_instance_valid(game):
		return null
	return game


func _physics_process(_delta: float) -> void:
	var optimized = tas_tool != null and tas_tool._ping_optimizer_enabled
	if not optimized or _infinite_dash_enabled:
		_apply_infinite_dash(_current_game())
	_status_elapsed += _delta
	if is_open() and (not optimized or (_status_label != null and _status_label.is_visible_in_tree())):
		if not optimized or _status_elapsed >= 0.25:
			_status_elapsed = 0.0
			_refresh_status(false)


# Goober Dash steps its own deterministic tick loop rather than relying only
# on Godot's physics callback, so apply from both callbacks. The write is
# skipped whenever the cooldown is already zero.
func _process(_delta: float) -> void:
	if tas_tool == null or not tas_tool._ping_optimizer_enabled or _infinite_dash_enabled:
		_apply_infinite_dash(_current_game())


func _apply_infinite_dash(game) -> void:
	if not _infinite_dash_enabled:
		return
	if game == null or not is_instance_valid(game):
		return
	if _infinite_dash_script == null:
		_infinite_dash_script = ModPaths.try_load(ModPaths.path("InfiniteDash.gd"))
	if _infinite_dash_script != null:
		_infinite_dash_script.apply(tas_tool)
