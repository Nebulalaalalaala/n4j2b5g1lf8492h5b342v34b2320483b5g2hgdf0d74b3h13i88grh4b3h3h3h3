extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
const MAX_BYTES = 1048576
const MAX_IMAGE = 131072

static func pack(studio, state) -> Dictionary:
	if not is_instance_valid(studio) or not studio.valid_state(state): return {}
	var copy = state.duplicate(true)
	# Resolve this creator's profile base now, not the recipient's equipped skin.
	if copy.get("base",false):
		var moonlight = studio.get_node_or_null("/root/Moonlight")
		var skin = moonlight.storage.storage_get("player.profile.skin",{}) if moonlight != null else {}
		var selected = []
		if skin is Dictionary:
			var catalog = studio.sandbox._all_cosmetics()
			for id in skin.values():
				var kind = catalog.get(str(id),{}).get("type","")
				var replaced = false
				for item in copy.selected:
					if catalog.get(item,{}).get("type","") == kind: replaced = true
				if not replaced and not str(id).empty() and not selected.has(id): selected.append(id)
		selected += copy.selected
		copy.selected = selected
		copy.base = false
	var assets = {}
	var wanted = [str(copy.get("texture","default"))]
	wanted += copy.get("item_textures",{}).values()
	for id in wanted:
		if not str(id).begins_with("import_") or assets.has(id): continue
		var texture = studio._load_texture(str(id))
		if texture == null: return {}
		var image = texture.get_data().duplicate()
		if image.get_width()>256 or image.get_height()>256: image.resize(256,256,Image.INTERPOLATE_LANCZOS)
		var bytes = image.save_png_to_buffer()
		if bytes.size()>MAX_IMAGE: return {}
		assets[id] = Marshalls.raw_to_base64(bytes)
	var payload = {"version":1,"state":copy,"textures":assets}
	return payload if valid(studio,payload) else {}

static func image_from(encoded):
	if not encoded is String or encoded.length()>MAX_IMAGE*2: return null
	var bytes = Marshalls.base64_to_raw(encoded)
	if bytes.size()<33 or bytes.size()>MAX_IMAGE or bytes.subarray(0,7) != PoolByteArray([137,80,78,71,13,10,26,10]): return null
	if bytes.subarray(8,15) != PoolByteArray([0,0,0,13,73,72,68,82]): return null
	var w = int(bytes[16])*16777216+int(bytes[17])*65536+int(bytes[18])*256+int(bytes[19])
	var h = int(bytes[20])*16777216+int(bytes[21])*65536+int(bytes[22])*256+int(bytes[23])
	if w<1 or h<1 or w>256 or h>256: return null
	var image = Image.new()
	return image if image.load_png_from_buffer(bytes)==OK else null

static func valid(studio, payload) -> bool:
	# Data-only validation here does not require Editor+ to be installed.
	if not payload is Dictionary or not _data_only(payload) or payload.get("version") != 1 or JSON.print(payload).to_utf8().size()>MAX_BYTES: return false
	if not studio.valid_state(payload.get("state")) or not payload.get("textures",{}) is Dictionary or payload.get("textures",{}).size()>8: return false
	for id in payload.get("textures",{}):
		if not id is String or not id.begins_with("import_") or id.length()>100 or not id.is_valid_identifier(): return false
		if image_from(payload.textures[id])==null: return false
	var wanted = [str(payload.state.get("texture","default"))] + payload.state.get("item_textures",{}).values()
	for id in wanted:
		if str(id).begins_with("import_") and not payload.get("textures",{}).has(id): return false
	return true

static func _data_only(value, depth = 0) -> bool:
	if depth>16: return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL: return true
		TYPE_INT,TYPE_REAL: return not is_nan(float(value)) and not is_inf(float(value))
		TYPE_STRING: return value.length()<=MAX_IMAGE*2
		TYPE_ARRAY:
			if value.size()>256: return false
			for entry in value:
				if not _data_only(entry,depth+1): return false
		TYPE_DICTIONARY:
			if value.size()>256: return false
			for key in value:
				if not key is String or key.length()>160 or not _data_only(value[key],depth+1): return false
		_: return false
	return true

static func save_to(studio, payload, title, equip = false) -> String:
	if not is_instance_valid(studio) or not valid(studio,payload): return "This outfit is unsupported. Nothing imported."
	if studio.library.looks.size()>=40: return "40 Looks saved. Free a Look slot first."
	var state = payload.state.duplicate(true)
	var assets = {}
	for old in payload.get("textures",{}):
		var image = image_from(payload.textures[old])
		var id = "import_" + str(payload.textures[old]).sha256_text().substr(0,24)
		Directory.new().make_dir_recursive(studio.TEXTURE_DIR)
		if image.save_png(studio.TEXTURE_DIR.plus_file(id+".png"))!=OK: return "Couldn't save the outfit texture. Appearance unchanged."
		assets[old] = id
		if state.texture == old: state.texture = id
		for key in state.get("item_textures",{}):
			if state.item_textures[key] == old: state.item_textures[key] = id
	var id = "hub_" + Crypto.new().generate_random_bytes(16).hex_encode()
	studio.library.looks.append({"id":id,"name":str(title).substr(0,60),"state":state,"favorite":false,"created":OS.get_unix_time(),"updated":OS.get_unix_time()})
	studio._save()
	# The old Studio writer returns void. Verify before reporting success.
	var file = File.new()
	if file.open(studio.DATA_PATH,File.READ)!=OK:
		studio.library.looks.pop_back()
		return "Couldn't save this Look. Appearance unchanged."
	var text = file.get_as_text()
	file.close()
	if text.find(id)<0:
		studio.library.looks.pop_back()
		return "Couldn't save this Look. Appearance unchanged."
	if is_instance_valid(studio.looks_grid): studio._build_look_cards()
	if equip: studio._equip_look(id)
	return "Equipped and saved to Avatar Studio." if equip else "Saved to Avatar Studio. Your appearance is unchanged."
