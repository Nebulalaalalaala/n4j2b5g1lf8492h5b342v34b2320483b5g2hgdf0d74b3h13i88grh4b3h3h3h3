extends "user://mod/tools/editor-themes/EditorThemePack/03_theme_texture.gd"

func _make_background_block_texture(mode: String, background: Color, accent: Color) -> Texture:
	# These are decorations for the editor's stock background-wall nodes. Cosmic
	# uses restrained spacecraft hull panels instead of duplicating the stars.
	var size: int = 128
	var image: = Image.new()
	image.create(size, size, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in size:
		for x in size:
			var color: Color = background
			if mode == "panels":
				if x <= 2 or y <= 2 or x >= size - 3 or y >= size - 3:
					color = background.linear_interpolate(accent, 0.35)
				elif x == size / 2 or y == size / 2:
					color = background.linear_interpolate(accent, 0.18)
				for rivet in [Vector2(10, 10), Vector2(size - 11, 10), Vector2(10, size - 11), Vector2(size - 11, size - 11)]:
					if Vector2(x, y).distance_squared_to(rivet) <= 3.0:
						color = background.linear_interpolate(accent, 0.58)
			elif mode in ["crescents", "ripples", "chevrons", "leaves", "diamonds"]:
				var px = float(posmod(x, 64)) - 32.0
				var py = float(posmod(y, 64)) - 32.0
				var ink = false
				if mode == "crescents":
					ink = Vector2(px, py).length() < 20.0 and Vector2(px - 9.0, py - 5.0).length() > 19.0
				elif mode == "ripples":
					ink = abs(py - 5.0 * sin(float(x) * PI / 32.0)) < 2.0
				elif mode == "chevrons":
					ink = abs(py - abs(px) * 0.65 + 10.0) < 2.0
				elif mode == "leaves":
					ink = pow((px + py) / 27.0, 2) + pow((px - py) / 11.0, 2) < 1.0
				else:
					ink = abs(abs(px) + abs(py) - 21.0) < 1.5
				if ink:
					color = background.linear_interpolate(accent, 0.26)
			elif mode == "grid":
				if posmod(x, 32) <= 1 or posmod(y, 32) <= 1:
					color = background.linear_interpolate(accent, 0.42)
			elif mode == "circuit":
				var trace: bool = (posmod(y, 32) <= 1 and posmod(x + 12, 64) < 46) or (posmod(x, 64) <= 1 and posmod(y + 8, 64) < 34)
				if trace:
					color = background.linear_interpolate(accent, 0.42)
				elif Vector2(posmod(x, 64) - 48, posmod(y, 32) - 16).length_squared() <= 10.0:
					color = background.linear_interpolate(accent, 0.58)
			image.set_pixel(x, y, color)
	image.unlock()
	return _texture_from_image(image, true)


func _make_ambient_texture(mode: String, accent: Color) -> Texture:
	# Neon and Sunset retain a subtle permanent motif. Low opacity keeps the
	# gradient dominant and prevents the background from becoming visual noise.
	var size: int = 512
	var image: = Image.new()
	image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	var faint: Color = Color(accent.r, accent.g, accent.b, 0.045)
	if mode == "diamonds":
		faint.a = 0.025
	for y in size:
		for x in size:
			if mode == "grid":
				if posmod(x, 128) == 0 or posmod(y, 128) == 0:
					image.set_pixel(x, y, faint)
			elif mode == "circuit":
				var trace: bool = (posmod(y, 128) == 0 and posmod(x + 32, 256) < 176) or (posmod(x, 256) == 0 and posmod(y + 16, 256) < 112)
				if trace:
					image.set_pixel(x, y, faint)
			else:
				var px: float = float(posmod(x, 256)) - 128.0
				var py: float = float(posmod(y + int(x / 256) * 112, 256)) - 128.0
				var ink: bool = false
				if mode == "ripples":
					ink = abs(py - 10.0 * sin(float(x) * TAU / 256.0)) < 1.5 and abs(px) < 70.0
				elif mode == "chevrons":
					ink = abs(px) + abs(py * 0.6) < 3.0
				elif mode == "leaves":
					ink = pow((px + py) / 32.0, 2) + pow((px - py) / 13.0, 2) < 1.0
				elif mode == "panels":
					ink = Vector2(px, py).length_squared() < 9.0
				elif mode == "diamonds":
					ink = abs(abs(px) + abs(py) - 25.0) < 1.3
				if ink:
					image.set_pixel(x, y, faint)
	image.unlock()
	return _texture_from_image(image, true)


func _make_scenery_texture(key: String, definition: Dictionary) -> Texture:
	if key == "cosmic_dots":
		return _make_solid_texture(Color.transparent, 128)
	var cached: Texture = _load_scenery_cache(key, "horizon")
	if cached != null:
		return cached
	if definition.has("scenery"):
		return _make_reference_scenery(str(definition["scenery"]), definition)
	# Built once per cached theme. Native Background handles parallax; nothing
	# is generated per frame and these silhouettes have no collision nodes.
	var image: = Image.new()
	image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	for x in 2048:
		var logical_x: float = x / 4.0
		var phase: float = logical_x * TAU / 512.0
		for layer in 3:
			var edge: float = 85.0 + layer * 48.0
			if key == "neon_grid":
				edge += float(posmod(int(logical_x / 32) * 37 + layer * 19, 71)) - 35.0
			elif key in ["moon", "ember"]:
				edge += abs(sin(phase * 3.0 + layer)) * 55.0
			elif key == "porcelain":
				edge += abs(sin(phase * 4.0 + layer)) * 28.0
			elif key == "orchard":
				edge -= sqrt(max(0.0, 1.0 - pow((fposmod(logical_x + layer * 21, 64.0) - 32.0) / 32.0, 2))) * 28.0
			else:
				edge += sin(phase * 2.0 + layer) * 17.0 + sin(phase * 5.0 + layer) * 8.0
			var color: Color = definition["bottom"].linear_interpolate(definition["terrain"], 0.35 + layer * 0.2)
			color.a = 0.55 + layer * 0.15
			for y in range(int(edge * 4.0), 1024):
				image.set_pixel(x, y, color)
	image.unlock()
	return _texture_from_image(image, true)


func _make_sky_texture(key: String, definition: Dictionary) -> Texture:
	if key == "cosmic_dots":
		return _make_solid_texture(Color.transparent, 128)
	var cached: Texture = _load_scenery_cache(key, "sky")
	if cached != null:
		return cached
	if key == "wild_jungle":
		return _make_jungle_canopy(definition)
	var image: = Image.new()
	image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	for pixel_y in 1024:
		for pixel_x in 2048:
			var x: float = pixel_x / 4.0
			var y: float = pixel_y / 4.0
			var point: = Vector2(x - 350, y - 120)
			var ink: bool = false
			var color: Color = definition["accent"]
			color.a = 0.18
			if key in ["cosmic_dots", "moon", "sunset_circuit", "night_plain", "holy_night", "summer_beach", "animal_kingdom"]:
				ink = point.length_squared() < 46.0 * 46.0
				if key == "moon":
					# Full moon with subdued crater shading, clearly visible at any map height.
					color = Color("e1e7dc")
					if (point - Vector2(-16, -11)).length_squared() < 100.0 or (point - Vector2(15, 16)).length_squared() < 160.0:
						color = Color("b9c4c8")
				elif key == "cosmic_dots":
					ink = ink or abs(pow(point.x / 79.0, 2) + pow((point.y + point.x * 0.25) / 14.0, 2) - 1.0) < 0.16
				color.a = 0.8 if key == "moon" else 0.3
			elif key == "neon_grid":
				ink = abs(y - 85.0 - fposmod(x, 256.0) * 0.25) < 1.5
			else:
				# Wide, soft-edged cloud banks; transparent lower edge matches the
				# native top-layer shader's vertical clamping.
				var ridge: float = 70.0 + sin(float(x) * TAU / 512.0) * 18.0 + sin(float(x) * TAU / 128.0) * 7.0
				ink = abs(float(y) - ridge) < 18.0
				color.a = 0.12 * max(0.0, 1.0 - abs(float(y) - ridge) / 18.0)
			if ink:
				image.set_pixel(pixel_x, pixel_y, color)
	image.unlock()
	return _texture_from_image(image, true)


func _paint_ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	center *= 3.0
	radius *= 3.0
	for y in range(max(0, int(center.y - radius.y)), min(image.get_height(), int(center.y + radius.y) + 1)):
		for x in range(max(0, int(center.x - radius.x)), min(image.get_width(), int(center.x + radius.x) + 1)):
			if pow((x - center.x) / radius.x, 2) + pow((y - center.y) / radius.y, 2) <= 1.0:
				image.set_pixel(x, y, color)


func _load_scenery_cache(key: String, layer: String) -> Texture:
	var suffix: String = "-flat-v3.png" if key in ["mushroom_valley", "wild_jungle", "animal_kingdom"] else "-hd.png"
	var path: String = ModPaths.THEME_BACKGROUNDS_DIR + key + "-" + layer + suffix
	if not File.new().file_exists(path):
		return null
	var image: = Image.new()
	if image.load(path) != OK:
		return null
	return _texture_from_image(image, true)


func set_menu_theme(key: String) -> void:
	menu_theme = key if key in ["follow", "default"] or THEME_DEFINITIONS.has(key) else "follow"
	SavedSettings.set_value("client_tools_menu_theme", menu_theme)
	_refresh_main_menu()


func _refresh_main_menu() -> void:
	var scene = get_tree().current_scene
	if scene == null or not scene.filename.ends_with("/HomeScene.tscn"):
		return
	var native = scene.find_node("UIBackground", true, false)
	if native == null:
		return
	var holder = native.get_node_or_null("GoobMenuTheme")
	var key: String = menu_theme if gui_enabled else "follow"
	if key != "default" and not THEME_DEFINITIONS.has(key):
		if holder != null:
			for child in holder.get_children():
				if child is CanvasItem:
					child.visible = false
			holder.set_meta("selection", "follow")
		return
	if holder != null and holder.get_meta("selection") == key:
		return
	if holder == null:
		holder = Control.new()
		holder.name = "GoobMenuTheme"
		native.add_child(holder)
		holder.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
	holder.set_meta("selection", key)
	var root = Control.new()
	root.name = "Background"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	# Stay in the native background's draw order, behind buttons and dialogs.
	holder.show_behind_parent = false
	holder.add_child(root)
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var backdrop = TextureRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.expand = true
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	root.add_child(backdrop)
	backdrop.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	if key == "default":
		backdrop.texture = load("res://gfx/cloudsky.png")
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return
	_ensure_themes(load("res://project_specific/level_themes/green/theme.tres"), key)
	var theme = _themes[key]
	var gradient = GradientTexture2D.new()
	gradient.gradient = theme.background_gradient
	gradient.fill_to = Vector2(0, 1)
	backdrop.texture = gradient
	var stars = TextureRect.new()
	stars.texture = theme.tiling_bg_texture
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.anchor_right = 1.0
	stars.anchor_bottom = 1.0
	stars.expand = true
	stars.stretch_mode = TextureRect.STRETCH_TILE
	root.add_child(stars)
	stars.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_apply_fixed_scenery(holder, theme, key)


func _make_jungle_canopy(definition: Dictionary) -> Texture:
	var image = Image.new()
	image.create(2304, 1152, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	var ink: Color = definition["terrain"].lightened(0.12)
	ink.a = 0.35
	for i in 9:
		var x: float = i * 96.0
		_paint_ellipse(image, Vector2(x, 0), Vector2(85, 38 + posmod(i * 17, 30)), ink)
		var length: int = 90 + posmod(i * 43, 110)
		for y in length:
			var vx: float = x + sin(float(y) * 0.022 + i) * 14.0
			_paint_ellipse(image, Vector2(vx, y), Vector2(1.3, 1.0), ink)
			if y > 35 and y % 26 == 0:
				_paint_ellipse(image, Vector2(vx + 5, y), Vector2(7, 3), ink)
	image.unlock()
	return _texture_from_image(image, true)


func _paint_rect(image: Image, rect: Rect2, color: Color) -> void:
	rect.position *= 3.0
	rect.size *= 3.0
	for y in range(max(0, int(rect.position.y)), min(image.get_height(), int(rect.end.y))):
		for x in range(max(0, int(rect.position.x)), min(image.get_width(), int(rect.end.x))):
			image.set_pixel(x, y, color)


func _paint_triangle(image: Image, center: Vector2, width: float, height: float, color: Color) -> void:
	for row in range(max(0, int(center.y * 3)), min(image.get_height(), int((center.y + height) * 3))):
		var y: float = row / 3.0
		var half: float = width * (y - center.y) / height * 0.5
		_paint_rect(image, Rect2(center.x - half, y, half * 2.0 + 0.34, 0.34), color)


func _make_reference_scenery(mode: String, definition: Dictionary) -> Texture:
	var image: = Image.new()
	image.create(2304, 1152, false, Image.FORMAT_RGBA8)
	image.fill(Color.transparent)
	image.lock()
	for layer in 2:
		var color: Color = definition["bottom"].linear_interpolate(definition["terrain"], 0.38 + layer * 0.18)
		color.a = 0.65
		var base: float = 265.0 + layer * 64.0
		if not mode in ["islands", "clouds"]:
			_paint_rect(image, Rect2(0, base, 768, 384 - base), color)
		for i in 6:
			var x: float = i * 151.0 + layer * 47.0 - 20.0
			var height: float = 64.0 + posmod(i * 31 + layer * 17, 63)
			if mode == "mushrooms":
				_paint_rect(image, Rect2(x - 7, base - height, 14, height), color)
				_paint_ellipse(image, Vector2(x, base - height), Vector2(48, 25), color)
				var spot: Color = color.lightened(0.15)
				_paint_ellipse(image, Vector2(x - 18, base - height - 7), Vector2(5, 4), spot)
				_paint_ellipse(image, Vector2(x + 13, base - height - 10), Vector2(7, 5), spot)
			elif mode == "islands":
				var y: float = base - height
				_paint_ellipse(image, Vector2(x, y), Vector2(52, 12), color)
				for j in 45:
					_paint_rect(image, Rect2(x - 40 + j * 0.7, y + j, 80 - j * 1.4, 1), color)
			elif mode == "clouds":
				_paint_ellipse(image, Vector2(x, base - height), Vector2(92, 27), color.lightened(0.2))
				_paint_ellipse(image, Vector2(x - 25, base - height - 20), Vector2(34, 29), color.lightened(0.2))
			elif mode == "ruins":
				_paint_rect(image, Rect2(x - 38, base - height, 76, height), color)
				for window in 3:
					_paint_rect(image, Rect2(x - 25 + window * 20, base - height + 18, 7, 12), color.lightened(0.13))
			elif mode in ["forest", "winter"]:
				_paint_rect(image, Rect2(x - 4, base - height, 8, height), color)
				for branch in 3:
					_paint_triangle(image, Vector2(x, base - height + branch * 20), 40 + branch * 20, 52, color)
				if mode == "winter":
					_paint_triangle(image, Vector2(x, base - height), 19, 24, definition["accent"].darkened(0.15))
			elif mode in ["savanna", "jungle", "beach"]:
				_paint_rect(image, Rect2(x - 4, base - height, 8, height), color)
				if mode == "beach":
					for leaf in 5:
						_paint_ellipse(image, Vector2(x + (leaf - 2) * 17, base - height + abs(leaf - 2) * 8), Vector2(27, 6), color)
				else:
					_paint_ellipse(image, Vector2(x, base - height), Vector2(60 if mode == "savanna" else 46, 14 if mode == "savanna" else 45), color)
					for branch in [-1, 1]:
						for segment in 32:
							_paint_ellipse(image, Vector2(x + branch * segment, base - height + 28 - segment * 0.8), Vector2(3, 3), color)
						if mode == "jungle":
							_paint_ellipse(image, Vector2(x + branch * 32, base - height + 8), Vector2(34, 28), color)
				if mode == "savanna" and layer == 1 and i in [1, 3]:
					# Small distant giraffe/elephant silhouettes, not foreground props.
					var ax: float = x + 58
					_paint_ellipse(image, Vector2(ax, base - 20), Vector2(20, 10), color)
					for leg in [-12, -5, 7, 14]:
						_paint_rect(image, Rect2(ax + leg, base - 19, 3, 20), color)
					if i == 1:
						_paint_rect(image, Rect2(ax + 12, base - 57, 6, 39), color)
						_paint_ellipse(image, Vector2(ax + 21, base - 56), Vector2(10, 5), color)
						_paint_rect(image, Rect2(ax + 15, base - 65, 2, 8), color)
					else:
						_paint_ellipse(image, Vector2(ax + 20, base - 22), Vector2(10, 13), color)
						_paint_rect(image, Rect2(ax + 26, base - 22, 5, 19), color)
			else:
				_paint_ellipse(image, Vector2(x, base), Vector2(150, height * 0.45), color)
	image.unlock()
	return _texture_from_image(image, true)


func _recolor_stock_crate_texture(source, accent: Color, accent_dark: Color) -> Texture:
	if source == null or not source is Texture:
		return source
	var image: Image = source.get_data()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return source
	image.convert(Image.FORMAT_RGBA8)
	image.lock()
	var theme_tint: Color = accent_dark.linear_interpolate(accent, 0.32)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var original: Color = image.get_pixel(x, y)
			if original.a <= 0.001:
				continue
			var brightness: float = original.r * 0.299 + original.g * 0.587 + original.b * 0.114
			var mapped: Color = Color(theme_tint.r * (0.35 + brightness * 0.65), theme_tint.g * (0.35 + brightness * 0.65), theme_tint.b * (0.35 + brightness * 0.65), original.a)
			# Preserve the stock white star and rivets; recolour mostly the metal
			# panels underneath them. This retains the native shading and borders.
			var strength: float = 0.08 if brightness >= 0.82 else 0.38
			var result: Color = original.linear_interpolate(mapped, strength)
			result.a = original.a
			image.set_pixel(x, y, result)
	image.unlock()
	return _texture_from_image(image, false)


func _make_solid_texture(color: Color, size: int) -> Texture:
	var image: = Image.new()
	image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return _texture_from_image(image, true)


func _texture_from_image(image: Image, repeating: bool) -> Texture:
	var texture: = ImageTexture.new()
	var flags: int = Texture.FLAG_FILTER
	if repeating:
		flags |= Texture.FLAG_REPEAT
	texture.create_from_image(image, flags)
	return texture


func _log(message: String) -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_log_action"):
		tas_tool.call("_log_action", message, null)
