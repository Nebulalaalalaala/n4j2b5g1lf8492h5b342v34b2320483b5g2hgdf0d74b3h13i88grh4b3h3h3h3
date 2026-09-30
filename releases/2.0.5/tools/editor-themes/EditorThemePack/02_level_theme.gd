extends "user://mod/tools/editor-themes/EditorThemePack/01_placeholders.gd"

func _ready() -> void:
	menu_theme = str(SavedSettings.get_value("client_tools_menu_theme", "follow"))
	var choices = SavedSettings.get_value("client_tools_level_themes", {})
	if typeof(choices) == TYPE_DICTIONARY:
		_local_theme_choices = choices.duplicate()
	_setup_sync()
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)
	if not get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().connect("node_added", self, "_on_tree_node_added")


func _exit_tree() -> void:
	if get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().disconnect("node_added", self, "_on_tree_node_added")


func configure(owner_tool) -> void:
	tas_tool = owner_tool
	call_deferred("_scan_current_scene")


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	_refresh_main_menu()
	_mark_rows()
	for dialog in _theme_dialogs:
		if is_instance_valid(dialog):
			_set_dialog_buttons_visible(dialog, value)
	if value:
		call_deferred("_scan_current_scene")
	else:
		for level in _levels:
			if is_instance_valid(level):
				var loader = level.get("theme_loader")
				if loader != null and not _theme_key_for_level(level).empty():
					level.set("level_theme", loader.get("default_theme"))
					level.call("_apply_level_theme", loader.get("default_theme"))
					_apply_background_visuals(level, loader.get("default_theme"))
				_apply_themed_block_variants(level)


func set_claude_experimental_icons_enabled(_value: bool) -> void:
	pass


func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer < 1.0:
		return
	_scan_timer = 0.0
	_refresh_main_menu()
	var editor_session: bool = gui_enabled and _is_theme_session()
	if not editor_session:
		_was_editor_session = false
		_levels.clear()
		_theme_dialogs.clear()
		return
	if not _was_editor_session:
		_was_editor_session = true
		_scan_current_scene()
	_cleanup_cache()
	for level in _levels:
		if is_instance_valid(level):
			_inject_into_level(level)
	for dialog in _theme_dialogs:
		if is_instance_valid(dialog):
			_inject_into_theme_dialog(dialog)


func _on_tree_node_added(node: Node) -> void:
	if node == null or not gui_enabled:
		return
	if node is Control and node.has_method("show_level_data"):
		call_deferred("_watch_row", node)
		return
	# This signal fires for every node spawned in a match. Do the two cheap
	# capability checks first so normal gameplay never performs game/editor
	# discovery for players, effects, UI labels, or network objects.
	if not node.has_method("set_level_theme") and not node.has_method("parse_themes"):
		return
	if _is_theme_session():
		call_deferred("_consider_node", node)


func _consider_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree() or not _is_theme_session():
		return
	if _is_level(node):
		var is_new_level: bool = _register_unique(_levels, node)
		if is_new_level:
			_connect_level_events(node)
		_inject_into_level(node)
		_apply_themed_block_variants(node)
		_apply_background_visuals(node, node.get("level_theme"))
	if _is_theme_dialog(node):
		_register_unique(_theme_dialogs, node)
		_inject_into_theme_dialog(node)


func _scan_current_scene() -> void:
	if not gui_enabled or not _is_theme_session():
		return
	var scene = get_tree().current_scene
	if scene != null:
		_scan_node(scene)


func _scan_node(node: Node) -> void:
	_consider_node(node)
	for child in node.get_children():
		_scan_node(child)


func _is_level(node: Node) -> bool:
	return node != null and node.has_method("set_level_theme") and node.has_method("load_level") and node.has_signal("theme_changed") and _has_property(node, "theme_loader")


func _is_theme_dialog(node: Node) -> bool:
	return node != null and node.has_method("parse_themes") and node.has_method("_create_button") and node.has_signal("select_theme")


func _has_property(object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _register_unique(array: Array, object) -> bool:
	for existing in array:
		if is_instance_valid(existing) and existing == object:
			return false
	array.append(object)
	return true


func _connect_level_events(level) -> void:
	if level.has_signal("theme_changed") and not level.is_connected("theme_changed", self, "_on_level_theme_changed"):
		level.connect("theme_changed", self, "_on_level_theme_changed", [level])
	if level.has_signal("added_node") and not level.is_connected("added_node", self, "_on_level_node_added"):
		level.connect("added_node", self, "_on_level_node_added", [level])
	if level.has_signal("loaded_level") and not level.is_connected("loaded_level", self, "_on_level_loaded"):
		level.connect("loaded_level", self, "_on_level_loaded", [level])


func _on_level_theme_changed(_theme, level) -> void:
	if gui_enabled and _is_theme_session() and is_instance_valid(level):
		_apply_themed_block_variants(level)
		_apply_background_visuals(level, _theme)


func _on_level_node_added(level_node, level) -> void:
	if gui_enabled and _is_theme_session():
		call_deferred("_apply_themed_variant_to_node", level_node, level)


func _on_level_loaded(level) -> void:
	if gui_enabled and _is_theme_session() and is_instance_valid(level):
		call_deferred("_refresh_loaded_editor_level", level)


func _refresh_loaded_editor_level(level) -> void:
	if level == null or not is_instance_valid(level) or not _is_theme_session():
		return
	_inject_into_level(level)
	_apply_themed_block_variants(level)
	_apply_background_visuals(level, level.get("level_theme"))


func _is_theme_session() -> bool:
	# Theme resources are client-side visuals in both editor and gameplay.
	# Keep the existing discovery/event path, including direct level loads.
	return get_tree().current_scene != null


func _is_actual_editor_session() -> bool:
	var scene = get_tree().current_scene
	if scene != null:
		if scene.name == "LevelEditor" or scene.has_method("on_theme_dialog_theme_selected"):
			return true
	var game = null
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_find_game"):
		game = tas_tool.call("_find_game")
	if game != null and is_instance_valid(game):
		var game_data = game.get("wp_game_data")
		if typeof(game_data) == TYPE_DICTIONARY:
			return bool(game_data.get("is_level_editor", false))
		if game_data != null and game_data is Object and _has_property(game_data, "is_level_editor"):
			return bool(game_data.get("is_level_editor"))
	return false


func _cleanup_cache() -> void:
	var clean_levels: = []
	for level in _levels:
		if is_instance_valid(level) and level.is_inside_tree():
			clean_levels.append(level)
	_levels = clean_levels
	var clean_dialogs: = []
	for dialog in _theme_dialogs:
		if is_instance_valid(dialog) and dialog.is_inside_tree():
			clean_dialogs.append(dialog)
	_theme_dialogs = clean_dialogs


func _ensure_themes(base_theme, requested_key: String = "") -> void:
	if base_theme == null:
		return
	if _neutral_jump_texture == null:
		_neutral_jump_texture = _tint_texture(load("res://project_specific/level_editor/nodes/jump_zone/pattern.png"), Color.white, 1.0)
	var stock_crate: Texture = load("res://project_specific/level_editor/nodes/physics_block/crate.png")
	for theme_key in THEME_DEFINITIONS.keys():
		if _themes.has(theme_key) or (not requested_key.empty() and theme_key != requested_key):
			continue
		var definition: Dictionary = THEME_DEFINITIONS[theme_key]
		# Resource.duplicate(true) does not preserve the script-backed BaseTheme
		# type in this exported Godot 3 build. Passing that duplicate to the
		# editor's typed `_create_button(t: BaseTheme)` silently coerces it to
		# null, then the native code crashes on `t.resource_name`. Construct an
		# actual instance from the stock theme's script and copy its stored
		# properties instead, so every native typed call receives a real
		# BaseTheme resource.
		var theme = _clone_base_theme(base_theme)
		if theme == null:
			continue
		theme.resource_name = str(definition["name"])
		theme.set_meta("goobplayability_theme_key", theme_key)
		var gradient: = Gradient.new()
		gradient.offsets = PoolRealArray([0.0, 1.0])
		gradient.colors = PoolColorArray([definition["bottom"], definition["top"]])
		theme.set("background_gradient", gradient)
		theme.set("background_gradient_texture", null)
		theme.set("ui_accent_color", definition["accent"])
		theme.set("ui_accent_color_dark", definition["accent_dark"])
		theme.set("terrain_color_1", definition["accent"])
		theme.set("terrain_color_2", definition["accent_dark"])
		theme.set("terrain_color_3", Color(0.018, 0.022, 0.052))
		# Keep the stock platform construction: corner radii and outline
		# thicknesses come straight from the base Goober Dash theme. Only its
		# colours and surface art change.
		theme.set("rear_grass_color", definition["accent_dark"])
		theme.set("front_grass_color", definition["accent"])
		theme.set("jump_zone_tint", Color(definition["accent"].r, definition["accent"].g, definition["accent"].b, 0.38))
		theme.set("jump_zone_outline_tint", definition["accent"])
		theme.set("gravity_field_tint", definition["accent"])
		theme.set("gravity_field", _tint_texture(base_theme.get("gravity_field"), Color.white, 1.0))
		theme.set("gravity_field_outline_tint", definition["pattern"])
		theme.set("disappearing_block_tint", definition["accent"])
		theme.set("disappearing_outline_tint", definition["pattern"])
		theme.set("laser_color", definition["laser"])
		theme.set("start_pattern_tint", Color(definition["accent"].r, definition["accent"].g, definition["accent"].b, 0.52))
		theme.set("start_outline_tint", definition["pattern"])
		# Preserve the game's own platform artwork and UV behavior. Recolour its
		# native terrain pattern instead of replacing it with a synthetic grid or
		# dot texture, which made platforms read like foreign geometry.
		var terrain_source: Texture = base_theme.get("terrain_texture")
		if THEME_TERRAIN_SOURCE_PATHS.has(theme_key):
			terrain_source = load(str(THEME_TERRAIN_SOURCE_PATHS[theme_key]))
		if terrain_source == null:
			terrain_source = base_theme.get("terrain_texture")
		var terrain_texture: Texture = _recolor_stock_surface_texture(terrain_source, definition["terrain"], definition["terrain"].lightened(0.16))
		if theme_key == "porcelain":
			terrain_texture = _recolor_stock_surface_texture(terrain_source, definition["terrain"], definition["terrain"].lightened(0.12))
		if terrain_texture != null:
			theme.set("terrain_texture", terrain_texture)
		# Retain the exact native one-way/checkpoint/finish artwork but remap its
		# stock green/brown palette so it belongs to the selected custom theme.
		var floor_texture: Texture = _recolor_stock_floor_texture(base_theme.get("floor_texture"), definition["terrain"], definition["accent_dark"], definition["accent"])
		if floor_texture != null:
			theme.set("floor_texture", floor_texture)
			theme.set("checkpoint_texture", floor_texture)
			theme.set("finish_line_texture", floor_texture)
		var block_mode: String = "panels"
		theme.set("background_block", _make_background_block_texture(block_mode, definition["bottom"].darkened(0.18), definition["bottom"]))
		theme.set("background_block2", _make_background_block_texture(block_mode, definition["bottom"].darkened(0.12), definition["bottom"]))
		theme.set("background_block3", _make_background_block_texture("panels", definition["terrain"], definition["accent_dark"]))
		if theme_key == "porcelain":
			# Quiet ceramic walls, not a second field of competing symbols.
			for property in ["background_block", "background_block2", "background_block3"]:
				theme.set(property, _make_background_block_texture("panels", Color("c7c7bd"), Color("b9bec0")))
		# The star field belongs to the permanent parallax layer, not to a
		# placeable background wall. Its 1024px tile deliberately contains only
		# a few dozen small stars, avoiding the previous confetti-like density.
		if theme_key in ["cosmic_dots", "moon", "holy_night", "night_plain", "black_forest"]:
			theme.set("tiling_bg_texture", _make_starfield_texture(definition["pattern"], theme_key.hash(), 22 if theme_key == "moon" else 36))
		else:
			theme.set("tiling_bg_texture", _make_ambient_texture(str(definition["pattern_mode"]), definition["accent"]))
		theme.set("horizon_texture", _make_scenery_texture(theme_key, definition))
		theme.set("clouds_texture", _make_sky_texture(theme_key, definition))
		_apply_native_detail_tints(theme, base_theme, theme_key, definition)
		var artwork: Texture = _load_background_art(theme_key)
		if artwork != null:
			theme.set_meta("background_art", artwork)
		_themes[theme_key] = theme
		_crate_textures[theme_key] = _recolor_stock_crate_texture(stock_crate, definition["accent"], definition["accent_dark"])


func _clone_base_theme(base_theme):
	if base_theme == null:
		return null
	var theme_script = base_theme.get_script()
	if theme_script == null or not theme_script.can_instance():
		return null
	var theme = theme_script.new()
	if theme == null:
		return null
	for property in base_theme.get_property_list():
		var property_name: String = str(property.get("name", ""))
		var usage: int = int(property.get("usage", 0))
		if property_name.empty() or property_name == "script" or property_name == "resource_name" or property_name == "resource_path":
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		theme.set(property_name, base_theme.get(property_name))
	return theme


func _apply_native_detail_tints(theme, base_theme, theme_key: String, definition: Dictionary) -> void:
	# Arrows and alert marks are explicitly theme-backed by the stock game.
	# Recolour their existing artwork rather than replacing its silhouette.
	var detail_strength: float = 0.62 if theme_key == "cosmic_dots" else 0.78
	if theme_key == "sunset_circuit":
		detail_strength = 0.72
	for property_name in ["ornament_texture_arrow", "ornament_texture_alert"]:
		var tinted: Texture = _tint_texture(base_theme.get(property_name), definition["accent"], detail_strength)
		if tinted != null:
			theme.set(property_name, tinted)
	# The stock white/blue saws and spike pits already fit Space. Neon
	# and Sunset get only a colour pass, retaining the exact native art.
	if theme_key == "cosmic_dots":
		return
	for property_name in ["saw_100", "saw_200", "saw_300", "pit_texture"]:
		var tinted: Texture = _tint_texture(base_theme.get(property_name), definition["accent"], 0.52)
		if tinted != null:
			theme.set(property_name, tinted)


func _tint_texture(source, tint: Color, amount: float) -> Texture:
	if source == null or not source is Texture:
		return null
	var image: Image = source.get_data()
	# This shipped Godot build predates Image.empty()/is_empty(). Width and
	# height are the compatible validity check used by the game itself.
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return source
	image.convert(Image.FORMAT_RGBA8)
	image.lock()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var original: Color = image.get_pixel(x, y)
			if original.a <= 0.001:
				continue
			var brightness: float = max(original.r, max(original.g, original.b))
			var target: Color = Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, original.a)
			var result: Color = original.linear_interpolate(target, clamp(amount, 0.0, 1.0))
			result.a = original.a
			image.set_pixel(x, y, result)
	image.unlock()
	# Jump zones and gravity fields scroll UVs beyond [0, 1]. Without
	# repeating, their transparent border is clamped across the entire fill.
	return _texture_from_image(image, (source.flags & Texture.FLAG_REPEAT) != 0)


func _inject_into_level(level) -> void:
	if not gui_enabled or not _is_theme_session() or level == null or not is_instance_valid(level):
		return
	var loader = level.get("theme_loader")
	if loader == null:
		return
	var base_theme = loader.get("default_theme")
	var loaded_level = level.get("loaded_level")
	var saved_key: String = str(loaded_level.get("level_theme")) if loaded_level != null and _has_property(loaded_level, "level_theme") else ""
	if not _is_actual_editor_session() and loaded_level != null:
		var remote = _remote_theme(loaded_level.get("level_id"))
		saved_key = str(_local_theme_choices.get(str(loaded_level.get("level_id")), remote if not remote.empty() else saved_key))
	if _is_actual_editor_session():
		_ensure_themes(base_theme)
		# Share the theme the editor level has. This also covers a theme picked
		# before the level's first save (no id yet) and levels themed earlier.
		var level_id = str(loaded_level.get("level_id")) if loaded_level != null else ""
		var key = _theme_key_for_level(level)
		if not level_id.empty() and not key.empty():
			if str(_local_theme_choices.get(level_id, "")) != key:
				_local_theme_choices[level_id] = key
				SavedSettings.set_value("client_tools_level_themes", _local_theme_choices)
			_publish_theme_choice(loaded_level, key)
	elif THEME_DEFINITIONS.has(saved_key):
		_ensure_themes(base_theme, saved_key)
	else:
		# Stock/public maps do not need any generated custom textures.
		return
	if _themes.empty():
		return
	var loader_themes = loader.get("themes")
	if typeof(loader_themes) != TYPE_DICTIONARY:
		return
	var themes_changed: = false
	for theme_key in _themes.keys():
		if loader_themes.get(theme_key, null) != _themes[theme_key]:
			loader_themes[theme_key] = _themes[theme_key]
			themes_changed = true
	if themes_changed:
		loader.set("themes", loader_themes)
	if loaded_level == null or not _has_property(loaded_level, "level_theme"):
		return
	if _themes.has(saved_key) and level.get("level_theme") != _themes[saved_key]:
		if _is_actual_editor_session():
			level.call("set_level_theme", _themes[saved_key])
		else:
			# This is a local render override, not an edit to the loaded map.
			level.set("level_theme", _themes[saved_key])
			level.call("_apply_level_theme", _themes[saved_key])
