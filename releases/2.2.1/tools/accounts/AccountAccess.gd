extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Keeps the game's log-out button in step and routes switching through the guarded Account
# Manager (opened from the Goobplayability menu → Accounts).
const SETTINGS_SCENE = "res://ui/nodes/UISettingsDialog.tscn"
var _settings = []
var _signin_groups = []
var _refreshing = false
var _dialog = null
var _manager = null

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("node_added", self, "_node_added")
	for signal_name in ["on_authentication_succeeded", "on_log_out"]:
		if Moonlight.has_signal(signal_name):
			Moonlight.connect(signal_name, self, "_refresh")
	call_deferred("_scan", get_tree().root)
	_manager = load(get_script().resource_path.get_base_dir().plus_file("AccountManager.gd")).new()
	_manager.owner_access = self
	add_child(_manager)

func _scan(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_consider(node)
	for child in node.get_children():
		_scan(child)

func _node_added(node: Node) -> void:
	if node.has_method("update_auth_buttons_visibility") or node.name == "LoginSignup":
		call_deferred("_consider", node)

func _consider(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node.has_method("update_auth_buttons_visibility") and node.has_method("on_log_out_button_pressed"):
		if not _settings.has(node):
			_settings.append(node)
			var logout = node.get("log_out_button")
			if logout != null and not logout.is_connected("visibility_changed", self, "_refresh"):
				logout.connect("visibility_changed", self, "_refresh")
	elif node.name == "LoginSignup" and node is CanvasItem:
		if not _signin_groups.has(node):
			_signin_groups.append(node)
			if not node.is_connected("visibility_changed", self, "_refresh"):
				node.connect("visibility_changed", self, "_refresh")
	_refresh()

func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var live_settings = []
	for settings in _settings:
		if not is_instance_valid(settings):
			continue
		live_settings.append(settings)
		var logout = settings.get("log_out_button")
		if logout != null and is_instance_valid(logout):
			logout.visible = Moonlight.is_logged_in()
	var live_signin = []
	for group in _signin_groups:
		if is_instance_valid(group):
			live_signin.append(group)
			group.visible = true
	_settings = live_settings
	_signin_groups = live_signin
	_refreshing = false

func open_settings() -> void:
	_open_scene(SETTINGS_SCENE)

func open_name_change() -> void:
	if not Moonlight.is_logged_in() or Moonlight.local_account == null:
		open_signin()
		return
	_open_scene("res://project_specific/ui/EnterDisplayNameDialog.tscn")

func open_signin() -> void:
	var tool = _manager.tool()
	if tool != null and tool.has_method("_open_module_page") and tool._open_module_page("accounts"):
		return
	_manager.open()

func _open_scene(path: String) -> void:
	if _dialog != null and is_instance_valid(_dialog) and _dialog.is_inside_tree():
		# An already-open settings dialog may be the source of this button.
		if _dialog.filename == path:
			return
	var packed = load(path)
	if not packed is PackedScene or get_tree().current_scene == null:
		return
	_dialog = packed.instance()
	get_tree().current_scene.add_child(_dialog)
