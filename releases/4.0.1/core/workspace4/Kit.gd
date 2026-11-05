extends Reference

# Small building blocks for the 4.0 pages, so every page shares one look.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")

static func row(parent: Control, separation: int = 8) -> HBoxContainer:
	var result = HBoxContainer.new()
	result.add_constant_override("separation", separation)
	parent.add_child(result)
	return result

static func column(parent: Control, separation: int = 8) -> VBoxContainer:
	var result = VBoxContainer.new()
	result.add_constant_override("separation", separation)
	parent.add_child(result)
	return result

# A button that calls target.method(args) instead of routing through the menu.
static func action(menu, parent: Control, text: String, icon_name: String, target: Object, method: String, args: Array = [], primary: bool = false) -> Button:
	var result = Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.rect_min_size = Vector2(0, 34)
	result.add_font_override("font", menu.font(15))
	var ink = Galaxy.color("accent_ink") if primary else Galaxy.color("ink")
	result.add_color_override("font_color", ink)
	result.add_color_override("font_color_hover", ink)
	result.add_color_override("font_color_pressed", ink)
	result.add_color_override("font_color_disabled", Galaxy.color("dim"))
	result.add_constant_override("hseparation", 7)
	var accent = Galaxy.color("accent")
	if primary:
		result.add_stylebox_override("normal", Galaxy.primary_box(accent, 12))
		result.add_stylebox_override("hover", Galaxy.primary_box(accent.lightened(0.08), 12))
		result.add_stylebox_override("pressed", Galaxy.primary_box(accent.darkened(0.1), 12))
	else:
		result.add_stylebox_override("normal", Galaxy.box(Galaxy.color("raised"), Galaxy.color("line"), 12))
		result.add_stylebox_override("hover", Galaxy.box(Galaxy.color("hover"), accent, 12))
		result.add_stylebox_override("pressed", Galaxy.box(Galaxy.color("hover"), accent, 12))
	result.add_stylebox_override("disabled", Galaxy.box(Galaxy.color("surface"), Galaxy.color("border"), 12))
	result.add_stylebox_override("focus", StyleBoxEmpty.new())
	if not icon_name.empty():
		result.icon = Galaxy.icon(icon_name, ink, 18)
	if target != null:
		result.connect("pressed", target, method, args)
	parent.add_child(result)
	load("user://mod/core/workspace4/ControlMotion.gd").bind_control(result)
	return result

static func hint(menu, parent: Control, text: String) -> Label:
	var result = menu.label(text, 14, Galaxy.color("muted"))
	result.autowrap = true
	parent.add_child(result)
	return result

static func field(menu, parent: Control, text: String, placeholder: String, target: Object, method: String) -> LineEdit:
	var result = LineEdit.new()
	result.text = text
	result.placeholder_text = placeholder
	result.rect_min_size = Vector2(160, 34)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_font_override("font", menu.font(15))
	result.add_stylebox_override("normal", Galaxy.box(Galaxy.color("surface"), Galaxy.color("line"), 10))
	result.add_stylebox_override("focus", Galaxy.box(Galaxy.color("surface"), Galaxy.color("accent"), 10))
	result.add_color_override("font_color", Galaxy.color("ink"))
	result.add_color_override("cursor_color", Galaxy.color("accent"))
	if target != null:
		result.connect("text_changed", target, method)
	parent.add_child(result)
	return result

static func slider(parent: Control, low: float, high: float, step: float, value: float, target: Object, method: String) -> HSlider:
	var result = HSlider.new()
	result.min_value = low
	result.max_value = high
	result.step = step
	result.value = value
	result.rect_min_size = Vector2(160, 24)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.focus_mode = Control.FOCUS_NONE
	var track = Galaxy.box(Galaxy.color("raised"), Galaxy.color("border"), 0, 4)
	# Native game slider knobs are much larger than the 4.0 tool controls.
	result.add_icon_override("grabber", slider_thumb())
	result.add_icon_override("grabber_highlight", slider_thumb())
	result.add_icon_override("grabber_disabled", slider_thumb())
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	result.add_stylebox_override("slider", track)
	var fill = Galaxy.box(Galaxy.color("accent"), Galaxy.color("accent"), 0, 4)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	result.add_stylebox_override("grabber_area", fill)
	result.add_stylebox_override("grabber_area_highlight", fill)
	if target != null:
		result.connect("value_changed", target, method)
	parent.add_child(result)
	return result

static func slider_thumb() -> Texture:
	var key = "tool-slider-thumb:"+Galaxy.color("accent").to_html()
	var cache = Engine.get_meta("goob_v4_textures") if Engine.has_meta("goob_v4_textures") else {}
	if cache.has(key): return cache[key]
	var pixels = Image.new()
	pixels.create(64,64,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.transparent)
	pixels.lock()
	for y in 64:
		for x in 64:
			var distance = Vector2(x+0.5,y+0.5).distance_to(Vector2(32,32))
			var alpha = clamp(28-distance,0,1)
			if alpha<=0: continue
			var color = Galaxy.color("accent") if distance>21 else Color.white
			color.a = alpha
			pixels.set_pixel(x,y,color)
	pixels.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(pixels,Texture.FLAG_FILTER)
	texture.set_size_override(Vector2(16,16))
	cache[key] = texture
	Engine.set_meta("goob_v4_textures",cache)
	return texture

static func labeled(menu, parent: Control, text: String) -> HBoxContainer:
	var line = row(parent, 10)
	var name_label = menu.label(text, 14, Galaxy.color("muted"))
	name_label.rect_min_size.x = 92
	line.add_child(name_label)
	return line

static func color_button(parent: Control, value: Color, target: Object, method: String) -> ColorPickerButton:
	var result = ColorPickerButton.new()
	result.color = value
	result.rect_min_size = Vector2(64, 30)
	result.focus_mode = Control.FOCUS_NONE
	result.edit_alpha = false
	if target != null:
		result.connect("color_changed", target, method)
	parent.add_child(result)
	return result

static func read_json(path: String, fallback):
	var file = File.new()
	if not file.file_exists(path) or file.open(path, File.READ) != OK:
		return fallback
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != typeof(fallback):
		return fallback
	return parsed.result

# Write a temp file first so a crash mid-write never leaves a broken file.
static func write_json(path: String, value) -> bool:
	var dir = Directory.new()
	dir.make_dir_recursive(path.get_base_dir())
	var file = File.new()
	if file.open(path + ".tmp", File.WRITE) != OK:
		return false
	file.store_string(JSON.print(value, "\t"))
	file.close()
	if dir.file_exists(path):
		dir.remove(path)
	return dir.rename(path + ".tmp", path) == OK
