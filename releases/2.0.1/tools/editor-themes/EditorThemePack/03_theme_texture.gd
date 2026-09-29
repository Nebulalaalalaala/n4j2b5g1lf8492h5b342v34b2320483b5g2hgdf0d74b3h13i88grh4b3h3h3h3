extends "user://mod/tools/editor-themes/EditorThemePack/02_level_theme.gd"

func _inject_into_theme_dialog(dialog) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	if not dialog.is_connected("select_theme", self, "_remember_theme_choice"):
		dialog.connect("select_theme", self, "_remember_theme_choice")
	if _themes.empty():
		for level in _levels:
			if is_instance_valid(level):
				_inject_into_level(level)
				if not _themes.empty():
					break
	if _themes.empty():
		return
	var themes_parent = dialog.get("themes_parent")
	if themes_parent == null or not is_instance_valid(themes_parent):
		return
	_prepare_dialog_grid(themes_parent)
	var injected_count: = 0
	for theme_key in _themes.keys():
		var button_name: String = "GoobplayabilityTheme_" + theme_key
		var existing = themes_parent.get_node_or_null(button_name)
		if existing != null:
			existing.visible = gui_enabled
			injected_count += 1
			continue
		if not gui_enabled:
			continue
		var theme = _themes.get(theme_key, null)
		if theme == null or theme.get_script() == null:
			continue
		# Build the stock theme button directly. Besides avoiding the exported
		# build's dynamic-call type coercion above, this lets us name the button
		# before it can be discovered by the next polling pass.
		var button_scene = dialog.get("theme_button_scene")
		if button_scene == null or not button_scene is PackedScene:
			continue
		var button = button_scene.instance()
		if button == null:
			continue
		button.name = button_name
		button.rect_min_size = Vector2(150, 150)
		themes_parent.add_child(button)
		button.set("label_text", str(theme.resource_name).to_upper())
		var texture_rect: TextureRect = button.get_node_or_null("ThemeTexture") as TextureRect
		if texture_rect != null:
			texture_rect.texture = theme.get("terrain_texture")
		button.connect("pressed", self, "_on_custom_theme_button_pressed", [dialog, theme])
		button.hint_tooltip = "Goobplayability visual theme. Uses stock block physics."
		injected_count += 1
		var dialog_buttons = dialog.get("buttons")
		if typeof(dialog_buttons) == TYPE_ARRAY:
			dialog_buttons.append(button)
			dialog.set("buttons", dialog_buttons)
	_update_theme_page(themes_parent, 0)
	# The stock dialog is authored at roughly 1000x1200 logical pixels.
	# Fit its entire coordinate space, including close/page buttons.
	var ui = dialog.get("dialog")
	if ui != null:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var factor: float = min(1.0, min(viewport_size.x / 1100.0, viewport_size.y / 1300.0))
		ui.anchor_right = 0.0
		ui.anchor_bottom = 0.0
		ui.rect_position = Vector2.ZERO
		ui.rect_scale = Vector2.ONE * factor
		ui.rect_size = viewport_size / factor
	if injected_count == THEME_DEFINITIONS.size() and not dialog.has_meta("goobplayability_theme_pack_ready"):
		dialog.set_meta("goobplayability_theme_pack_ready", true)
		_log("Editor Theme Pack: %d visual themes available" % THEME_DEFINITIONS.size())


func _remember_theme_choice(theme) -> void:
	if not _is_actual_editor_session():
		return
	for level in _levels:
		if not is_instance_valid(level):
			continue
		var loaded = level.get("loaded_level")
		if loaded == null:
			continue
		var id = str(loaded.get("level_id"))
		if id.empty():
			continue
		if theme != null and theme.has_meta("goobplayability_theme_key"):
			_local_theme_choices[id] = str(theme.get_meta("goobplayability_theme_key"))
		else:
			_local_theme_choices.erase(id)
	SavedSettings.set_value("client_tools_level_themes", _local_theme_choices)


func _on_custom_theme_button_pressed(dialog, theme) -> void:
	if dialog == null or not is_instance_valid(dialog) or theme == null:
		return
	# Use the editor's normal selection route, then apply the same real BaseTheme
	# to every editor Level we registered. The latter is a fallback for the
	# playable editor scene, which contains both an embedded editor level and the
	# live game level and can otherwise send the dialog signal to only one of them.
	dialog.call("on_theme_button_pressed", theme)
	for level in _levels:
		if is_instance_valid(level) and level.get("level_theme") != theme:
			level.call("set_level_theme", theme)
	var key: String = str(theme.get_meta("goobplayability_theme_key")) if theme.has_meta("goobplayability_theme_key") else "custom"
	_log("Editor Theme Pack: selected %s (%s)" % [str(theme.resource_name), key])


func _prepare_dialog_grid(themes_parent) -> void:
	# Seven stock themes plus three custom ones need four rows in the native
	# three-column layout, which extends below its fixed-height dialog. Use a
	# compact four-column grid so all ten choices are visible and clickable.
	if themes_parent is GridContainer:
		themes_parent.columns = 4
		themes_parent.add_constant_override("hseparation", 18)
		themes_parent.add_constant_override("vseparation", 14)
	for child in themes_parent.get_children():
		if child is Control:
			child.rect_min_size = Vector2(150, 150)


func _update_theme_page(grid, step: int) -> void:
	var choices = []
	for child in grid.get_children():
		if child is BaseButton and not child.has_meta("theme_page_navigation"):
			if gui_enabled or not str(child.name).begins_with("GoobplayabilityTheme_"):
				choices.append(child)
	var pages: int = max(1, int(ceil(float(choices.size()) / 12.0)))
	var page: int = int(grid.get_meta("theme_page")) if grid.has_meta("theme_page") else 0
	page = posmod(page + step, pages)
	grid.set_meta("theme_page", page)
	for i in choices.size():
		choices[i].visible = int(i / 12) == page
	for direction in [-1, 1]:
		var name: String = "ThemePagePrevious" if direction == -1 else "ThemePageNext"
		var button = grid.get_node_or_null(name)
		if button == null:
			button = Button.new()
			button.name = name
			button.set_meta("theme_page_navigation", true)
			button.rect_min_size = Vector2(150, 48)
			grid.add_child(button)
			button.connect("pressed", self, "_update_theme_page", [grid, direction])
		button.text = ("< " if direction == -1 else "> ") + str(page + 1) + " / " + str(pages)
		button.visible = pages > 1
		grid.move_child(button, grid.get_child_count() - 1)


func _set_dialog_buttons_visible(dialog, value: bool) -> void:
	var themes_parent = dialog.get("themes_parent")
	if themes_parent == null:
		return
	for theme_key in THEME_DEFINITIONS.keys():
		var button = themes_parent.get_node_or_null("GoobplayabilityTheme_" + theme_key)
		if button != null:
			button.visible = value
	_update_theme_page(themes_parent, 0)


func _theme_key_for_level(level) -> String:
	var theme = level.get("level_theme")
	if theme != null and theme.has_meta("goobplayability_theme_key"):
		return str(theme.get_meta("goobplayability_theme_key"))
	return ""


func _apply_themed_block_variants(level) -> void:
	if level == null or not is_instance_valid(level):
		return
	var loaded_level = level.get("loaded_level")
	if loaded_level == null:
		return
	for level_node in loaded_level.get_children():
		_apply_themed_variant_to_node(level_node, level)


func _apply_themed_variant_to_node(level_node, level) -> void:
	if level_node == null or not is_instance_valid(level_node) or level == null or not is_instance_valid(level):
		return
	if not _has_property(level_node, "node_type"):
		return
	var custom_key: String = _theme_key_for_level(level) if gui_enabled else ""
	var node_type: String = str(level_node.get("node_type"))
	if node_type == "physics_block":
		_apply_physics_block_texture(level_node, custom_key)
	elif node_type == "bouncy_block" or node_type == "music_block" or node_type == "recharger":
		_apply_special_block_tint(level_node, custom_key)
	elif node_type == "sign":
		_apply_sign_tint(level_node, custom_key)
	elif node_type == "jump_zone":
		var mesh = level_node.get_node_or_null("Renderer/MeshInstance2D")
		if mesh != null:
			if not mesh.has_meta("goobplayability_original_texture"):
				mesh.set_meta("goobplayability_original_texture", mesh.texture)
			mesh.texture = _neutral_jump_texture if not custom_key.empty() else mesh.get_meta("goobplayability_original_texture")


func _apply_physics_block_texture(level_node, custom_key: String) -> void:
	var mesh = level_node.get_node_or_null("Renderer/MeshInstance2D")
	var shadow = level_node.get_node_or_null("Renderer/UpGuys_LevelNodeShadow/Shadow")
	for target in [mesh, shadow]:
		if target == null or not _has_property(target, "texture"):
			continue
		if not target.has_meta("goobplayability_original_texture"):
			target.set_meta("goobplayability_original_texture", target.get("texture"))
		if not custom_key.empty() and _crate_textures.has(custom_key):
			target.set("texture", _crate_textures[custom_key])
		else:
			target.set("texture", target.get_meta("goobplayability_original_texture"))


func _apply_special_block_tint(level_node, custom_key: String) -> void:
	var definition: Dictionary = THEME_DEFINITIONS.get(custom_key, {})
	var renderer = level_node.get_node_or_null("Renderer")
	if renderer == null:
		return
	if renderer is CanvasItem:
		if not renderer.has_meta("goobplayability_original_modulate"):
			renderer.set_meta("goobplayability_original_modulate", renderer.modulate)
		if definition.empty():
			renderer.modulate = renderer.get_meta("goobplayability_original_modulate")
		else:
			var original: Color = renderer.get_meta("goobplayability_original_modulate")
			renderer.modulate = original * Color(definition["accent"].r, definition["accent"].g, definition["accent"].b, 1.0)


func _apply_sign_tint(level_node, custom_key: String) -> void:
	# Signs have no BaseTheme texture slots, so tint their existing icon, speech
	# box, and pointer in place. Cosmic keeps the stock navy sign because it
	# already belongs in that palette; Neon and Sunset receive a restrained tint.
	var definition: Dictionary = THEME_DEFINITIONS.get(custom_key, {})
	var tint_sign: bool = not definition.empty() and custom_key != "cosmic_dots"
	var icon = level_node.get_node_or_null("Renderer/MeshInstance2D")
	var message_box = level_node.get_node_or_null("Renderer/MessageAnchor/NinePatchRect")
	var pointer = level_node.get_node_or_null("Renderer/MessageAnchor/NinePatchRect/TextureRect")
	_apply_canvas_item_tint(icon, definition.get("accent", Color.white), 0.58 if tint_sign else 0.0)
	_apply_canvas_item_tint(message_box, definition.get("accent_dark", Color.white), 0.46 if tint_sign else 0.0)
	_apply_canvas_item_tint(pointer, definition.get("accent", Color.white), 0.58 if tint_sign else 0.0)


func _apply_canvas_item_tint(target, tint: Color, strength: float) -> void:
	if target == null or not target is CanvasItem:
		return
	if not target.has_meta("goobplayability_original_self_modulate"):
		target.set_meta("goobplayability_original_self_modulate", target.self_modulate)
	var original: Color = target.get_meta("goobplayability_original_self_modulate")
	if strength <= 0.0:
		target.self_modulate = original
		return
	var multiplier: Color = Color.white.linear_interpolate(tint, clamp(strength, 0.0, 1.0))
	target.self_modulate = Color(original.r * multiplier.r, original.g * multiplier.g, original.b * multiplier.b, original.a)


func _apply_background_visuals(level, theme) -> void:
	if level == null or not is_instance_valid(level) or theme == null:
		return
	var custom_key: String = ""
	if theme.has_meta("goobplayability_theme_key"):
		custom_key = str(theme.get_meta("goobplayability_theme_key"))
	var scene = get_tree().current_scene
	if scene != null:
		_apply_background_visuals_in_tree(scene, level, theme, custom_key)


func _apply_background_visuals_in_tree(node: Node, level, theme, custom_key: String) -> void:
	# Background.gd keeps the tiling layer at 3.5% opacity for stock patterns.
	# That is too faint for isolated stars, so custom themes get their own layer
	# opacity and stock themes restore the original value exactly.
	if node.has_method("apply_theme") and _has_property(node, "level") and node.get("level") == level and _has_property(node, "tiling_texture_tint"):
		if not node.has_meta("goobplayability_original_tiling_tint"):
			node.set_meta("goobplayability_original_tiling_tint", node.get("tiling_texture_tint"))
		if custom_key in ["cosmic_dots", "moon"]:
			node.set("tiling_texture_tint", Color(1.0, 1.0, 1.0, 0.82))
		elif THEME_DEFINITIONS.has(custom_key):
			node.set("tiling_texture_tint", Color.white)
		else:
			node.set("tiling_texture_tint", node.get_meta("goobplayability_original_tiling_tint"))
		node.call("apply_theme", theme)
		_apply_fixed_scenery(node, theme, custom_key)
		var tiling_layer = node.get("tiling_background") if _has_property(node, "tiling_background") else null
		if tiling_layer != null and is_instance_valid(tiling_layer):
			tiling_layer.self_modulate = node.get("tiling_texture_tint")
	for child in node.get_children():
		_apply_background_visuals_in_tree(child, level, theme, custom_key)


func _apply_fixed_scenery(background, theme, key: String) -> void:
	var parent = background.get_node_or_null("Background")
	if parent == null:
		return
	var custom: bool = THEME_DEFINITIONS.has(key)
	var illustrated: bool = custom and theme.has_meta("background_art")
	var full_art = parent.get_node_or_null("ThemeIllustration")
	if full_art == null and illustrated:
		full_art = TextureRect.new()
		full_art.name = "ThemeIllustration"
		full_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full_art.expand = true
		full_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		parent.add_child(full_art)
		full_art.anchor_right = 1.0
		full_art.anchor_bottom = 1.0
	if full_art != null:
		full_art.visible = illustrated
		if illustrated:
			full_art.texture = theme.get_meta("background_art")
	# Native sky/horizon follow the level's extreme Y coordinates. Tall maps
	# can leave both completely off-screen. Keep distant scenery in screen space.
	for name in ["AnchorTop", "BackgroundHorizon"]:
		var native_layer = parent.get_node_or_null(name)
		if native_layer != null:
			if not native_layer.has_meta("theme_original_visible"):
				native_layer.set_meta("theme_original_visible", native_layer.visible)
			native_layer.visible = false if custom else native_layer.get_meta("theme_original_visible")
	for name in ["ThemeSky", "ThemeHorizon"]:
		var art = parent.get_node_or_null(name)
		if art == null and custom:
			art = TextureRect.new()
			art.name = name
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.expand = true
			art.stretch_mode = TextureRect.STRETCH_SCALE if name == "ThemeHorizon" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
			parent.add_child(art)
			art.anchor_right = 1.0
			art.anchor_top = 0.52 if name == "ThemeHorizon" else 0.0
			art.anchor_bottom = 1.0 if name == "ThemeHorizon" else 0.6
		if art != null:
			art.visible = custom and not illustrated
			if custom:
				art.texture = theme.get("horizon_texture" if name == "ThemeHorizon" else "clouds_texture")


func _load_background_art(key: String) -> Texture:
	# Painterly illustrations are retained on disk but no longer used:
	# native-style silhouette scenery shares the game's flat visual language.
	return null


func _recolor_stock_surface_texture(source, background: Color, foreground: Color) -> Texture:
	if source == null or not source is Texture:
		return source
	var image: Image = source.get_data()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return source
	image.convert(Image.FORMAT_RGBA8)
	image.lock()
	var minimum_brightness: float = 1.0
	var maximum_brightness: float = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var sample: Color = image.get_pixel(x, y)
			if sample.a <= 0.001:
				continue
			var brightness: float = sample.r * 0.299 + sample.g * 0.587 + sample.b * 0.114
			minimum_brightness = min(minimum_brightness, brightness)
			maximum_brightness = max(maximum_brightness, brightness)
	var brightness_range: float = max(0.001, maximum_brightness - minimum_brightness)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var original: Color = image.get_pixel(x, y)
			if original.a <= 0.001:
				continue
			var brightness: float = original.r * 0.299 + original.g * 0.587 + original.b * 0.114
			# In the stock terrain texture the darker pixels form the motif. Keep
			# that exact motif, but make it subtle against the theme's base colour.
			var motif: float = 1.0 - clamp((brightness - minimum_brightness) / brightness_range, 0.0, 1.0)
			var result: Color = background.linear_interpolate(foreground, 0.10 + motif * 0.30)
			result.a = original.a
			image.set_pixel(x, y, result)
	image.unlock()
	return _texture_from_image(image, true)


func _recolor_stock_floor_texture(source, terrain: Color, accent_dark: Color, accent: Color) -> Texture:
	if source == null or not source is Texture:
		return source
	var image: Image = source.get_data()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return source
	image.convert(Image.FORMAT_RGBA8)
	image.lock()
	var minimum_brightness: float = 1.0
	var maximum_brightness: float = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var sample: Color = image.get_pixel(x, y)
			if sample.a <= 0.001:
				continue
			var brightness: float = sample.r * 0.299 + sample.g * 0.587 + sample.b * 0.114
			minimum_brightness = min(minimum_brightness, brightness)
			maximum_brightness = max(maximum_brightness, brightness)
	var brightness_range: float = max(0.001, maximum_brightness - minimum_brightness)
	var darkest: Color = terrain.darkened(0.62)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var original: Color = image.get_pixel(x, y)
			if original.a <= 0.001:
				continue
			var brightness: float = original.r * 0.299 + original.g * 0.587 + original.b * 0.114
			var normalized: float = clamp((brightness - minimum_brightness) / brightness_range, 0.0, 1.0)
			var result: Color
			if normalized < 0.34:
				result = darkest.linear_interpolate(terrain, normalized / 0.34)
			elif normalized < 0.68:
				result = terrain.linear_interpolate(accent_dark, (normalized - 0.34) / 0.34)
			else:
				result = accent_dark.linear_interpolate(accent, (normalized - 0.68) / 0.32)
			result.a = original.a
			image.set_pixel(x, y, result)
	image.unlock()
	return _texture_from_image(image, false)


func _make_starfield_texture(star_color: Color, seed_value: int, star_count: int) -> Texture:
	# Transparent, sparse, and large enough that repetition is not obvious. The
	# gradient remains visible underneath and the game's normal parallax renderer
	# keeps these stars present without needing placeable background blocks.
	var size: int = 1024
	var image: = Image.new()
	image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	var state: int = abs(seed_value) + 17
	for index in max(1, star_count):
		state = int((state * 1103515245 + 12345) & 0x7fffffff)
		var x: int = 3 + state % (size - 6)
		state = int((state * 1103515245 + 12345) & 0x7fffffff)
		var y: int = 3 + state % (size - 6)
		var radius: int = 2 if index % 11 == 0 else 1
		var color: Color = star_color.lightened(float(index % 4) * 0.06)
		color.a = 0.58 + float(index % 5) * 0.085
		for py in range(y - radius, y + radius + 1):
			for px in range(x - radius, x + radius + 1):
				if Vector2(px - x, py - y).length_squared() <= radius * radius:
					image.set_pixel(px, py, color)
	image.unlock()
	return _texture_from_image(image, true)
