extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Goobplayability's own cosmetics (local only, worn through Avatar Studio).
# Each item borrows a native "carrier" skin for its Spine attachments and
# replaces that skin's atlas regions with new art from ATLAS. Nothing is sent
# to the server: native skins, equips and other players never see these ids.

const ATLAS = "user://mod/tools/avatar-studio/assets/custom/level15_atlas.png"
const LEVEL = 15
# Level 15: 4 colours, 4 suits, 4 hats, 4 hand items, 4 emotes. Every item is
# its own drawing; the carrier only decides where it can be drawn:
#   hats   head/Unicorn, head/Flyhead (big regions over the head and face)
#   suits  suit/Robot (body, sleeves, legs), suit/Viking (body + collar)
#   hands  hand/Scythe   (large region around the idle hold)
#   colours body/Normal
# Emotes ("atlas": "anim") keep only the carrier's bubble and play their own
# animation on top (CustomEmoteAnim.gd).
# region path -> [native atlas rect px (x, y, w, h), custom atlas rect px]
const ITEMS = {}
const ATLAS_SIZE = Vector2(2048, 2592)
const EMOTE_ANIM = "user://mod/shared/scripts/CustomEmoteAnim.gd"
# Native bubble art in the emote atlas (base, tint, shine); the rest is hidden.
const BUBBLE_RECTS = [[653, 441, 109, 79], [887, 441, 109, 79], [770, 441, 109, 79]]
const EMOTE_SHADER = "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV) * COLOR;\n}\n"
const SHARED = "goob_custom_cosmetics"
const PALETTES = 6
# Same palette fit as Avatar Studio's item shader: the main colour turns next to
# the palette hue, other colours keep their place around it; greys stay.
const PALETTE_CODE = """vec3 goob_rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}
vec3 goob_hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec3 goob_fit(vec3 rgb, vec3 pal) {
	if (pal.x < 0.5) { return rgb; }
	vec3 h = goob_rgb2hsv(rgb);
	if (h.y <= 0.08) { return rgb; }
	float base = fract(pal.z + 0.1);
	float turned = fract(h.x + pal.y);
	h.x = fract(base + (fract(turned - base + 0.5) - 0.5) * 0.65);
	return goob_hsv2rgb(h);
}
"""

static func is_custom(id) -> bool:
	return ITEMS.has(str(id))

# Catalog rows in the native shape, so Studio code can read type/name/spine.
static func catalog_entries() -> Dictionary:
	var out = {}
	for id in ITEMS:
		var item = ITEMS[id]
		out[id] = {"type": item.type, "name": item.name, "rarity": item.rarity, "level": LEVEL, "spine": item.carrier, "goobplayability": true}
		if str(item.type) == "color":
			out[id]["color"] = "blue"
	return out

# The native cosmetic id that owns the carrier skin (cached per catalog).
static func carrier(id: String, native_catalog: Dictionary) -> String:
	if not ITEMS.has(id):
		return id
	var cache = _state().carriers
	if cache.has(id):
		return cache[id]
	var spine = str(ITEMS[id].carrier)
	var found = ""
	if spine == "body/Normal":
		cache[id] = "color_default"
		return "color_default"
	for key in native_catalog:
		var data = native_catalog[key]
		if data is Dictionary and str(data.get("spine", "")) == spine and not ITEMS.has(key):
			found = str(key)
			break
	if not found.empty():
		cache[id] = found
	return found

static func _state() -> Dictionary:
	var tree = Engine.get_main_loop()
	if not tree.has_meta(SHARED):
		tree.set_meta(SHARED, {"carriers": {}, "shaders": {}, "texture": null, "emote": {}})
	return tree.get_meta(SHARED)

static func texture():
	var state = _state()
	if state.texture == null:
		var image = Image.new()
		if image.load(ATLAS) != OK:
			return null
		var t = ImageTexture.new()
		t.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		state.texture = t
	return state.texture

# Gives target its own material that draws these items' art over the carrier
# regions. Call after anything else has replaced the Goober's material. A later
# id wins a shared carrier region (the last selected hat is the one worn).
# palettes: id -> [hue turn, palette hue] (Avatar Studio "Fit to Goober palette").
static func patch(target, ids: Array, palettes: Dictionary = {}) -> void:
	if target == null or not is_instance_valid(target):
		return
	var regions = []
	var taken = {}
	var tint = null
	var slots = []
	for i in range(ids.size() - 1, -1, -1):
		var item = ITEMS.get(str(ids[i]))
		if item == null or str(item.atlas) != "body":
			continue
		if str(item.type) == "color" and tint == null:
			tint = item.tint
		# Each worn item gets a palette slot (up to PALETTES) the shader can recolour.
		var slot = -1
		if str(item.type) != "color" and slots.size() < PALETTES:
			slot = slots.size()
			slots.append(str(ids[i]))
		for path in item.regions:
			if not taken.has(path):
				taken[path] = true
				regions.append([item.regions[path][0], item.regions[path][1], slot])
	var base = target.get("normal_material")
	if regions.empty() or not base is ShaderMaterial or base.shader == null:
		return
	var material = _material(base, regions)
	if material == null:
		return
	target.set("normal_material", material)
	if target.get("gradient_material") != null:
		target.set("gradient_material", material)
	for k in PALETTES:
		var fit = palettes.get(slots[k], []) if k < slots.size() else []
		material.set_shader_param("goob_pal%d" % k, Vector3(1.0, fit[0], fit[1]) if fit.size() == 2 else Vector3.ZERO)
	# Particles, dash bar and trail follow the item's colours (Goober.get_tint).
	if tint != null and target.get("gradient") != null:
		var gradient = Gradient.new()
		gradient.offsets = PoolRealArray([0.0, 1.0])
		gradient.colors = PoolColorArray([Color(str(tint[0])), Color(str(tint[1]))])
		target.set("gradient", gradient)

static func _material(base: ShaderMaterial, regions: Array):
	if base.has_meta("goob_custom"):
		if str(base.get_meta("goob_custom")) == str(regions):
			return base
		base = base.get_meta("goob_custom_base")
	var atlas = texture()
	if atlas == null:
		return null
	var code = base.shader.code
	var key = str([code.hash(), regions])
	var shaders = _state().shaders
	if not shaders.has(key):
		var injected = inject(code, regions)
		if injected.empty():
			return null
		var shader = Shader.new()
		shader.code = injected
		shaders[key] = shader
	var material: ShaderMaterial = base.duplicate()
	material.shader = shaders[key]
	material.set_shader_param("goob_custom_atlas", atlas)
	material.set_meta("goob_custom", str(regions))
	material.set_meta("goob_custom_base", base)
	return material

# Emote bubbles: one item at a time on an EmoteSpineSprite; "" restores it.
static func patch_emote(sprite, id: String) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if not sprite.has_meta("goob_native_material"):
		sprite.set_meta("goob_native_material", sprite.get("normal_material"))
	var old = sprite.get_node_or_null("GoobEmoteAnim")
	if old != null:
		sprite.remove_child(old)
		old.queue_free()
	var item = ITEMS.get(id)
	if item == null or not str(item.atlas) in ["emote", "anim"]:
		sprite.set("normal_material", sprite.get_meta("goob_native_material"))
		return
	if str(item.atlas) == "anim":
		sprite.set("normal_material", _bubble_only())
		var anim = load(EMOTE_ANIM).new()
		anim.name = "GoobEmoteAnim"
		anim.setup(id)
		sprite.add_child(anim)
		return
	var base = ShaderMaterial.new()
	base.shader = Shader.new()
	base.shader.code = EMOTE_SHADER
	var regions = []
	for path in item.regions:
		regions.append(item.regions[path])
	var material = _material(base, regions)
	if material != null:
		sprite.set("normal_material", material)

static func _bubble_only() -> ShaderMaterial:
	var state = _state()
	if not state.has("bubble") or state.bubble == null:
		var code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 px = UV / TEXTURE_PIXEL_SIZE;\n\tbool keep = false;\n"
		for r in BUBBLE_RECTS:
			code += "\tkeep = keep || (px.x >= %.1f && px.y >= %.1f && px.x <= %.1f && px.y <= %.1f);\n" % [r[0], r[1], r[0] + r[2], r[1] + r[3]]
		code += "\tCOLOR = texture(TEXTURE, UV) * COLOR;\n\tif (!keep) { COLOR.a = 0.0; }\n}\n"
		var material = ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = code
		state.bubble = material
	return state.bubble

# The emote wheel plays a custom emote as its carrier; the next local emote
# sprite that starts that animation (within a second) shows the custom art.
static func set_pending_emote(animation: String, id: String) -> void:
	_state().emote = {"animation": animation, "id": id, "until": OS.get_ticks_msec() + 1000}

static func take_pending_emote(animation: String) -> String:
	var pending = _state().emote
	if pending.empty() or str(pending.animation) != animation or OS.get_ticks_msec() > int(pending.until):
		return ""
	_state().emote = {}
	return str(pending.id)

# Adds a lookup to the shader's fragment(): inside a carrier region the colour
# comes from the custom atlas (alpha from the art, slot alpha kept).
static func inject(code: String, regions: Array) -> String:
	var at = code.find("void fragment()")
	if at < 0:
		return ""
	var open = code.find("{", at)
	var depth = 0
	var close = -1
	for i in range(open, code.length()):
		var ch = code[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				close = i
				break
	if close < 0:
		return ""
	var lookup = "uniform sampler2D goob_custom_atlas;\n"
	for k in PALETTES:
		lookup += "uniform vec3 goob_pal%d = vec3(0.0);\n" % k
	lookup += PALETTE_CODE + "vec4 goob_custom_lookup(vec2 px, out float slot) {\n"
	for r in regions:
		var a = r[0]
		var b = r[1]
		var slot = float(r[2]) if r.size() > 2 else -1.0
		lookup += "\tif (px.x >= %.1f && px.y >= %.1f && px.x <= %.1f && px.y <= %.1f) { slot = %.1f; return texture(goob_custom_atlas, (vec2(%.1f, %.1f) + (px - vec2(%.1f, %.1f)) * vec2(%.4f, %.4f)) / vec2(%.1f, %.1f)); }\n" % [
			a[0], a[1], a[0] + a[2], a[1] + a[3], slot, b[0], b[1], a[0], a[1], float(b[2]) / a[2], float(b[3]) / a[3], ATLAS_SIZE.x, ATLAS_SIZE.y]
	lookup += "\tslot = -1.0;\n\treturn vec4(-1.0);\n}\n"
	var head = code.substr(0, at)
	var body = code.substr(open + 1, close - open - 1)
	var start = "\n\tvec4 goob_in = COLOR;\n\tfloat goob_slot = -1.0;\n\tvec4 goob_c = goob_custom_lookup(UV / TEXTURE_PIXEL_SIZE, goob_slot);\n"
	lookup += "vec3 goob_pick(float slot) {\n\tif (slot < -0.5) { return vec3(0.0); }\n"
	for k in PALETTES:
		lookup += "\tif (slot < %.1f) { return goob_pal%d; }\n" % [k + 0.5, k]
	lookup += "\treturn vec3(0.0);\n}\n"
	var finish = "\n\tif (goob_c.a >= 0.0) { COLOR = vec4(goob_fit(goob_c.rgb, goob_pick(goob_slot)), goob_c.a * goob_in.a); }\n"
	return head + lookup + "void fragment() {" + start + body + finish + "}" + code.substr(close + 1)

# Native skin dictionary value for an id (custom ids wear their carrier).
static func skin_id(id: String, native_catalog: Dictionary) -> String:
	return carrier(id, native_catalog) if ITEMS.has(id) else id

static func custom_ids(ids: Array) -> Array:
	var out = []
	for id in ids:
		if ITEMS.has(str(id)):
			out.append(str(id))
	return out
