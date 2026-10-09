extends Node

# One native hardware cursor family, independent of any tool window or scene.
# No mouse-mode/input changes, software sprite, process loop or per-frame scans.
const ModPaths = preload("user://mod/core/ModPaths.gd")
var textures = []
var hotspots = []
var installed = false
var cursor_size = 32
var _buttons = {}
var _atlas = null
var _specs = []

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if OS.has_feature("server") or not _load_art(): return
	_rebuild()
	if not installed: return
	get_tree().connect("node_added", self, "_node_added")
	get_tree().connect("node_removed", self, "_node_removed")
	get_viewport().connect("size_changed", self, "_resize")
	_watch_existing(get_tree().root)

func _load_art() -> bool:
	var file = File.new()
	if file.open(ModPaths.path("GoobCursorArt.json"), File.READ) != OK: return false
	if file.get_len() > 131072:
		file.close()
		return false
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary: return false
	var data = parsed.result
	if data.get("format") != 1 or not data.get("shapes") is Array or data.shapes.size() != 17: return false
	var image = Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(str(data.get("png", "")))) != OK: return false
	if image.get_size() != Vector2(384, 192): return false
	for spec in data.shapes:
		if not spec is Dictionary or not spec.get("hotspot") is Array or spec.hotspot.size() != 2: return false
		for axis in spec.hotspot:
			if not axis is float and not axis is int: return false
			if axis < 0 or axis >= 32: return false
	_atlas = image
	_specs = data.shapes
	return true

func _desired_size() -> int:
	# Keep web cursors within the browser's 32px boundary-safe size.
	if OS.has_feature("HTML5"): return 32
	return int(clamp(round(32.0 * max(96, OS.get_screen_dpi()) / 96.0), 32, 64))

func _resize() -> void:
	if _desired_size() != cursor_size: _rebuild()

func _rebuild() -> void:
	cursor_size = _desired_size()
	textures.clear()
	hotspots.clear()
	for shape in range(17):
		var image = _atlas.get_rect(Rect2(Vector2((shape % 6) * 64, int(shape / 6) * 64), Vector2(64, 64)))
		image.resize(cursor_size, cursor_size, Image.INTERPOLATE_LANCZOS)
		var texture = ImageTexture.new()
		texture.create_from_image(image, 0)
		var spec = _specs[shape].hotspot
		var hotspot = Vector2(round(spec[0] * cursor_size / 32.0), round(spec[1] * cursor_size / 32.0))
		textures.append(texture)
		hotspots.append(hotspot)
		Input.set_custom_mouse_cursor(texture, shape, hotspot)
	installed = true

func _watch_existing(node: Node) -> void:
	if node is BaseButton: _register_button(weakref(node))
	for child in node.get_children(): _watch_existing(child)

func _node_added(node: Node) -> void:
	# Let native/mod _ready set any intentional drag/resize cursor first.
	if node is BaseButton: call_deferred("_register_button", weakref(node))

func _register_button(reference) -> void:
	var button = reference.get_ref()
	if not is_instance_valid(button) or not button is BaseButton or not button.is_inside_tree(): return
	var id = button.get_instance_id()
	if _buttons.has(id) or button.mouse_default_cursor_shape != Control.CURSOR_ARROW: return
	_buttons[id] = reference
	button.connect("mouse_entered", self, "_refresh_button", [id])
	button.connect("draw", self, "_refresh_button", [id])
	_refresh_button(id)

func _refresh_button(id: int) -> void:
	if not _buttons.has(id): return
	var button = _buttons[id].get_ref()
	if not is_instance_valid(button):
		_buttons.erase(id)
		return
	if not button.mouse_default_cursor_shape in [Control.CURSOR_ARROW, Control.CURSOR_POINTING_HAND]:
		_unwatch_button(button)
		return
	var desired = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
	if button.mouse_default_cursor_shape != desired: button.mouse_default_cursor_shape = desired

func _node_removed(node: Node) -> void:
	if _buttons.has(node.get_instance_id()): _unwatch_button(node)

func _unwatch_button(button: BaseButton) -> void:
	_buttons.erase(button.get_instance_id())
	for signal_name in ["mouse_entered", "draw"]:
		if button.is_connected(signal_name, self, "_refresh_button"): button.disconnect(signal_name, self, "_refresh_button")
	if button.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND:
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _exit_tree() -> void:
	if not installed: return
	var tree = get_tree()
	for spec in [["node_added", "_node_added"], ["node_removed", "_node_removed"]]:
		if tree.is_connected(spec[0], self, spec[1]): tree.disconnect(spec[0], self, spec[1])
	if get_viewport().is_connected("size_changed", self, "_resize"):
		get_viewport().disconnect("size_changed", self, "_resize")
	for id in _buttons.keys():
		var button = _buttons[id].get_ref()
		if is_instance_valid(button): _unwatch_button(button)
	_buttons.clear()
	for shape in range(17): Input.set_custom_mouse_cursor(null, shape)
	textures.clear()
	hotspots.clear()
	installed = false
