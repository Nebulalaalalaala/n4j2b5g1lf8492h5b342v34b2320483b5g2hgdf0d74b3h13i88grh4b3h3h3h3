extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Loads Journey artwork from journey-assets/<key>.png. Keys are restricted to
# lowercase letters, digits and underscores so no path can escape the folder.
var textures = {}
var base_dir = ""

func _init():
	base_dir = get_script().resource_path.get_base_dir()

func texture(key: String):
	if key.empty() or key.length() > 48:
		return null
	for i in key.length():
		var c = key.ord_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return null
	if textures.has(key):
		return textures[key]
	var image = Image.new()
	if image.load(ModPaths.JOURNEY_ASSETS_DIR + key + ".png") != OK:
		textures[key] = null
		return null
	var result = ImageTexture.new()
	result.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	textures[key] = result
	return result
