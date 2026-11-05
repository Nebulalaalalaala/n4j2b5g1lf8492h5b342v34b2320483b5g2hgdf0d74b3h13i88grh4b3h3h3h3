extends Reference

# Goobplayability 4.0 look: colour tokens for the dark and light themes, and
# loaders for the 4.0 art (line icons, planet orbs, the Arctic Fox).
# Art lives in shared/assets/v4/. Icons are white on transparent and get tinted.

const DIR = "user://mod/shared/assets/v4/"
const CACHE = "goob_v4_textures"

const DARK = {
	"bg": "14162d", "surface": "1a1d38", "raised": "202441", "hover": "2a2e52", "border": "2c2f55", "line": "484b70",
	"ink": "f5f3ff", "muted": "b8b7d6", "dim": "9493b8", "accent": "a68bff", "accent_ink": "171027", "star": "ffd86b",
	"success": "8ce0ba", "warning": "ffd28a", "danger": "ffa9b9", "record": "ff6b8a", "playback": "7fd0ff",
	"band_a": "3a2a9e", "band_b": "6d4bda", "band_c": "c477da", "band_ink": "ffffff", "band_sub": "ede6ff",
	"dot": "ffffff", "glow": "bea0ff",
}
const LIGHT = {
	"bg": "f8f6ff", "surface": "ffffff", "raised": "eeebff", "hover": "e7e2ff", "border": "e2dcf5", "line": "b6acd4",
	"ink": "252047", "muted": "625a7a", "dim": "6b6486", "accent": "6240ca", "accent_ink": "ffffff", "star": "9a6a00",
	"success": "17633f", "warning": "795000", "danger": "a52044", "record": "c8234a", "playback": "0b67a8",
	"band_a": "f1e8ff", "band_b": "e3d3ff", "band_c": "ffddf0", "band_ink": "241d52", "band_sub": "5b5480",
	"dot": "9a84f0", "glow": "6240ca",
}
const ORBS = {"violet": "8e6bff", "cyan": "2fa7e0", "blue": "5a7bff", "pink": "e066b0", "mint": "2fb585", "gold": "eba23a"}

static func theme_name() -> String:
	var value = str(SavedSettings.get_value("workspace_theme", "dark"))
	return "light" if value == "light" else "dark"

static func is_light() -> bool:
	return theme_name() == "light"

static func color(key: String) -> Color:
	var table = LIGHT if is_light() else DARK
	return Color(str(table.get(key, "ff00ff")).replace(" ", ""))

static func _cache() -> Dictionary:
	if not Engine.has_meta(CACHE):
		Engine.set_meta(CACHE, {})
	return Engine.get_meta(CACHE)

# A PNG from shared/assets/v4 (user:// files are not imported, so load the image).
static func texture(name: String) -> Texture:
	var cache = _cache()
	if cache.has(name):
		return cache[name]
	var image = Image.new()
	if image.load(DIR + name) != OK:
		return null
	var result = ImageTexture.new()
	result.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	cache[name] = result
	return result

# A line icon (icons/<name>.png) tinted to the colour, at the given pixel size.
static func icon(name: String, tint: Color, pixels: int = 24) -> Texture:
	var key = "icon:%s:%s:%d" % [name, tint.to_html(true), pixels]
	var cache = _cache()
	if cache.has(key):
		return cache[key]
	var image = Image.new()
	if image.load(DIR + "icons/" + name + ".png") != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != pixels:
		image.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
	image.lock()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a = image.get_pixel(x, y).a
			image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a * tint.a))
	image.unlock()
	var result = ImageTexture.new()
	result.create_from_image(image, Texture.FLAG_FILTER)
	cache[key] = result
	return result

static func box(fill: Color, line: Color, padding: int = 14, corner: int = 10) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner)
	style.corner_detail = 10
	style.anti_aliasing = true
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

# Glossy primary button face: lighter top edge over the accent.
static func primary_box(accent: Color, padding: int = 14) -> StyleBoxFlat:
	var style = box(accent, accent.lightened(0.4), padding, 10)
	style.set_border_width_all(0)
	style.border_width_top = 1
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	style.shadow_size = 6
	return style
