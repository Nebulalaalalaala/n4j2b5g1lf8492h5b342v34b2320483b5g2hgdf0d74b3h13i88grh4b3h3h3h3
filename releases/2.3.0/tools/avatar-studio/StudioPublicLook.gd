extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
const MAX_BYTES = 98304
const MAX_PNG = 49152

static func valid_id(value) -> bool:
	if not value is String or value.length() != 36: return false
	for i in value.length():
		if i in [8,13,18,23]:
			if value[i] != "-": return false
		elif not value.substr(i,1).is_valid_hex_number(false): return false
	return true

# Never deserialize scripts, resources, filenames, URLs or arbitrary shader code.
static func clean(raw, catalog: Dictionary) -> Dictionary:
	if not raw is Dictionary or JSON.print(raw).to_utf8().size() > MAX_BYTES: return {}
	var version = raw.get("version",0)
	if not typeof(version) in [TYPE_INT,TYPE_REAL] or version != 1: return {}
	if not raw.get("enabled",false) is bool: return {}
	if not raw.enabled: return {"version":1,"enabled":false}
	var skin = raw.get("skin")
	var selected = raw.get("selected",[])
	var edits = raw.get("transforms",{})
	if not skin is Dictionary or skin.size()>32 or not selected is Array or selected.size()>32: return {}
	var validator = ModPaths.try_load(ModPaths.COSMETIC_TRANSFORMS)
	if validator == null or not validator.valid(edits): return {}
	var safe_skin = {}
	for slot in skin:
		var id = skin[slot]
		if not slot is String or slot.length()>80: return {}
		if id == null or (id is String and id.empty()): continue
		if not _cosmetic(id,catalog): return {}
		safe_skin[slot] = id
	if not safe_skin.has("color") or catalog[safe_skin.color].get("type","") != "color": return {}
	var safe_ids = []
	for id in selected:
		if not _cosmetic(id,catalog): return {}
		if not safe_ids.has(id): safe_ids.append(id)
	for id in edits:
		if not _cosmetic(id,catalog) or not (id in safe_ids or id in safe_skin.values()): return {}
	var color = raw.get("color","40b8ff")
	var size = raw.get("avatar_size",1.0)
	if not color is String or color.length()!=6 or not color.is_valid_hex_number(false): return {}
	if not typeof(size) in [TYPE_INT,TYPE_REAL] or is_nan(float(size)) or is_inf(float(size)): return {}
	# Public appearances cannot cover the whole level. Local Studio remains unrestricted.
	var texture = raw.get("texture","default")
	if not texture is String or not texture in ["default","dots","stripes","grid","import_public"]: return {}
	var png = raw.get("png", "")
	if texture == "import_public" and png_image(png) == null: return {}
	if not raw.get("custom",false) is bool: return {}
	return {"version":1,"enabled":true,"skin":safe_skin,"selected":safe_ids,"custom":raw.get("custom",false),"color":color,"avatar_size":clamp(float(size),0.1,4.0),"texture":texture,"png":png if texture=="import_public" else "","transforms":edits.duplicate(true)}

static func _cosmetic(id, catalog) -> bool:
	return id is String and id.length()<=160 and catalog.get(id) is Dictionary and catalog[id].get("type","") in ["color","hat","suit","hand","emote"]

static func png_image(encoded):
	if not encoded is String or encoded.length()>65536 or encoded.length()<44: return null
	var bytes = Marshalls.base64_to_raw(encoded)
	if bytes.size()<33 or bytes.size()>MAX_PNG: return null
	if bytes[0]!=137 or bytes[1]!=80 or bytes[2]!=78 or bytes[3]!=71 or bytes[4]!=13 or bytes[5]!=10 or bytes[6]!=26 or bytes[7]!=10: return null
	if bytes[8]!=0 or bytes[9]!=0 or bytes[10]!=0 or bytes[11]!=13 or bytes[12]!=73 or bytes[13]!=72 or bytes[14]!=68 or bytes[15]!=82: return null
	# Read dimensions BEFORE allocating/decoding a remotely supplied image.
	var width = _u32(bytes,16)
	var height = _u32(bytes,20)
	if width<1 or height<1 or width>128 or height>128: return null
	var image = Image.new()
	if image.load_png_from_buffer(bytes)!=OK: return null
	return image

static func _u32(bytes, at):
	return int(bytes[at])*16777216 + int(bytes[at+1])*65536 + int(bytes[at+2])*256 + int(bytes[at+3])

static func capture(sandbox) -> Dictionary:
	if not is_instance_valid(sandbox) or not sandbox.sandbox_enabled: return {"version":1,"enabled":false}
	var studio = sandbox._studio
	if not is_instance_valid(studio): return {}
	var state = studio.capture()
	var result = {"version":1,"enabled":true,"skin":sandbox._build_local_skin(),"selected":state.selected,"custom":state.custom,"color":state.color,"avatar_size":state.avatar_size,"transforms":state.transforms,"texture":state.texture}
	if str(state.texture).begins_with("import_"):
		var texture = studio._load_texture(state.texture)
		if texture == null: return {}
		var image = texture.get_data().duplicate()
		image.resize(128,128,Image.INTERPOLATE_LANCZOS)
		var bytes = image.save_png_to_buffer()
		if bytes.size()>MAX_PNG: return {}
		result.texture = "import_public"
		result.png = Marshalls.raw_to_base64(bytes)
	return clean(result,sandbox._all_cosmetics())
