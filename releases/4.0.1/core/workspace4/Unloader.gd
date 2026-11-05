extends Reference

# Unload Goobplayability for this game session: every Goobplayability node
# stops processing and listening, its windows and overlays are hidden, and
# the game is put back to normal speed. Nothing is deleted or uninstalled;
# restarting the game loads Goobplayability again.

const ROOT = "user://mod/"
const SKIP = "user://mod/moonlight/" # replacements for the game's own scripts

static func is_mod_object(object) -> bool:
	if object == null or not is_instance_valid(object):
		return false
	var script = object.get_script()
	if script == null:
		return false
	var path = str(script.resource_path)
	return path.begins_with(ROOT) and not path.begins_with(SKIP)

# Nodes with a Goobplayability script; nodes under them are ours too.
static func mod_roots(tree: SceneTree) -> Array:
	var found = []
	var stack = [tree.root]
	while not stack.empty():
		var node = stack.pop_back()
		if is_mod_object(node):
			found.append(node)
			continue
		for child in node.get_children():
			stack.append(child)
	return found

static func unload(tree: SceneTree, tas_tool) -> int:
	# Leave the game in a normal state first.
	if tas_tool != null and is_instance_valid(tas_tool):
		for method in ["_release_all_injected_actions", "_end_macro_editor_preview"]:
			if tas_tool.has_method(method):
				tas_tool.call(method)
		var limit = tas_tool.get("fps_limit")
		if limit != null and int(limit) > 0:
			Engine.target_fps = 0
		# Put other players and particles back the way the game draws them
		# (without changing the saved FPS boost / ping optimizer settings).
		var game_tools = tas_tool.get("_game_tools")
		if game_tools != null and is_instance_valid(game_tools):
			var boost = game_tools.get("_fps_boost")
			if boost != null and is_instance_valid(boost) and boost.has_method("_restore_all"):
				boost.call("_restore_all")
			var optimizer = game_tools.get("_ping_optimizer")
			if optimizer != null and is_instance_valid(optimizer) and optimizer.has_method("_update_renderers"):
				tas_tool.set("_ping_optimizer_enabled", false)
				optimizer.call("_update_renderers")
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var roots = mod_roots(tree)
	# Private name text and borrowed native bars live on game-owned controls.
	# Restore them before silencing their owning presentation service.
	for root in roots:
		var presentation = [root]
		while not presentation.empty():
			var node = presentation.pop_back()
			if is_mod_object(node) and node.has_method("restore_native_presentation"):
				node.call("restore_native_presentation")
			for child in node.get_children(): presentation.append(child)
	var count = 0
	var ours = {}
	for root in roots:
		var stack = [root]
		while not stack.empty():
			var node = stack.pop_back()
			if not is_instance_valid(node):
				continue
			count += 1
			ours[node.get_instance_id()] = true
			# The instant replay recorder runs as its own program; ask it to stop.
			if is_mod_object(node) and str(node.get_script().resource_path).ends_with("/ClipService.gd") and node.has_method("stop"):
				node.call("stop")
			if is_mod_object(node) and str(node.get_script().resource_path).ends_with("/OverlaySources.gd") and node.has_method("stop"):
				node.call("stop")
			_silence(node)
			for child in node.get_children():
				stack.append(child)
	# Game signals connected to Goobplayability (tree watchers, game events).
	for root in roots:
		var stack = [root]
		while not stack.empty():
			var node = stack.pop_back()
			if not is_instance_valid(node):
				continue
			var incoming = node.get_incoming_connections() if is_mod_object(node) else []
			for connection in incoming:
				var source = connection.get("source")
				if source == null or not is_instance_valid(source) or (source is Node and ours.has(source.get_instance_id())):
					continue
				if not _script_has(node, connection.method_name):
					continue # the engine's own connection (containers, buttons)
				if source.is_connected(connection.signal_name, node, connection.method_name):
					source.disconnect(connection.signal_name, node, connection.method_name)
			for child in node.get_children():
				stack.append(child)
	Engine.set_meta("goobplayability_unloaded", true)
	print("[Goobplayability] unloaded %d nodes for this session" % count)
	return count

static func _script_has(node: Object, method: String) -> bool:
	var script = node.get_script()
	while script != null:
		for entry in script.get_script_method_list():
			if entry.name == method:
				return true
		script = script.get_base_script()
	return false

static func _silence(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	# These engines tick internally even when script callbacks are disabled.
	if node is SpineSprite: node.update_mode = SpineConstant.UpdateMode_Manual
	if node is CPUParticles2D or node is Particles2D: node.speed_scale = 0.0
	if node is Viewport: node.render_target_update_mode = Viewport.UPDATE_DISABLED
	if node is AnimationPlayer: node.set_active(false)
	if node is Timer:
		node.stop()
	elif node is Tween:
		node.stop_all()
	elif node is CanvasLayer:
		node.visible = false
	elif node is CanvasItem:
		node.visible = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.stop()
	if node is HTTPRequest:
		node.cancel_request()
