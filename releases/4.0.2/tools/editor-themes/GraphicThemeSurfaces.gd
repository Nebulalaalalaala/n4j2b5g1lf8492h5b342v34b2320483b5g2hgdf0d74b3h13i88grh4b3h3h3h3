extends Reference

# Only new graphic specials. Native sprites, alpha, UVs and shaders stay intact;
# recoloring a shared cached copy prevents purple/brown mixing with white/lime.
const KEYS = ["voltage", "prism_break", "ink_shift"]
const ORIGINAL = "goobplayability_graphic_original_texture"
var _neutral = {}

func apply(renderer: Node, key: String) -> void:
	# BouncyBlock_Renderer owns its mesh under TweenRoot. Keep that hierarchy
	# and its color/scale tweens; only the cached texture is neutralized.
	var mesh = renderer.get_node_or_null("TweenRoot/MeshInstance2D")
	if mesh == null:
		return
	if not key in KEYS:
		if mesh.has_meta(ORIGINAL):
			mesh.texture = mesh.get_meta(ORIGINAL)
		return
	var source: Texture = mesh.get_meta(ORIGINAL) if mesh.has_meta(ORIGINAL) else mesh.texture
	if source == null:
		return
	var id: int = source.get_instance_id()
	if not _neutral.has(id):
		var image: Image = source.get_data()
		if image == null or image.get_width() <= 0 or image.get_height() <= 0:
			return
		image.convert(Image.FORMAT_RGBA8)
		image.lock()
		for y in image.get_height():
			for x in image.get_width():
				var color: Color = image.get_pixel(x, y)
				var value: float = max(color.r, max(color.g, color.b))
				image.set_pixel(x, y, Color(value, value, value, color.a))
		image.unlock()
		var texture = ImageTexture.new()
		texture.create_from_image(image, source.flags)
		_neutral[id] = texture
	if not mesh.has_meta(ORIGINAL):
		mesh.set_meta(ORIGINAL, source)
	mesh.texture = _neutral[id]
