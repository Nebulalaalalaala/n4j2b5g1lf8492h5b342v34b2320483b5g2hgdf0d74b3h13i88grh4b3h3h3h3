extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
const TYPES = ["alert","arrow","background","background2","background3","background_ramp","background_ramp2","block","bouncy_block","checkpoint","disappearing_block","finish_line","floor","gravity_field","ice_block","jump_zone","laser","music_block","physics_block","pit","ramp","recharger","sawblade","sign","start"]
const LIMIT = 100
const MAX_BYTES = 524288
var path = ModPaths.DATA_DIR + "editor_stamps.json"
var entries = []
var error = ""
var healthy = true

static func data_only(value, depth = 0) -> bool:
	if depth > 16: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL: return true
		TYPE_INT, TYPE_REAL: return not is_nan(float(value)) and not is_inf(float(value)) and abs(float(value)) <= 1e12
		TYPE_STRING: return value.length() <= 8192
		TYPE_ARRAY:
			if value.size() > 4096: return false
			for item in value:
				if not data_only(item, depth + 1): return false
		TYPE_DICTIONARY:
			if value.size() > 256: return false
			for key in value:
				if not key is String or key.length() > 160 or not data_only(value[key], depth + 1): return false
		_: return false
	return true

static func valid(payload) -> bool:
	if not payload is Dictionary or not data_only(payload) or JSON.print(payload).to_utf8().size() > MAX_BYTES: return false
	if payload.get("version") != 1 or not payload.get("nodes") is Array or payload.nodes.empty() or payload.nodes.size() > 256: return false
	for node in payload.nodes:
		if not node is Dictionary or not node.get("type") in TYPES: return false
		for key in ["x","y","width","height","rotation","shape_rotation","pivot_x","pivot_y"]:
			if not typeof(node.get(key)) in [TYPE_INT,TYPE_REAL]: return false
		if abs(node.x)>500000 or abs(node.y)>500000 or node.width<0.25 or node.height<0.25 or node.width>10000 or node.height>10000: return false
		if not _integer(node.shape_rotation,0,3) or abs(node.rotation)>360000 or abs(node.pivot_x)>10000 or abs(node.pivot_y)>10000: return false
		if not node.get("properties",{}) is Dictionary: return false
		for key in node.get("properties",{}):
			var value = node.properties[key]
			match key:
				"reappear", "one_time_use":
					if not value is bool: return false
				"strength", "recharge_time":
					if not _number(value) or abs(value)>10000: return false
				"note":
					if not _integer(value,0,255): return false
				"message":
					if not value is String: return false
				_: return false
		if node.has("animation") and not _animation(node.animation): return false
	return true

static func _number(value) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value))

static func _integer(value, low, high) -> bool:
	return _number(value) and int(value)==value and value>=low and value<=high

static func _animation(animation) -> bool:
	if not animation is Dictionary or not animation.get("tween_sequences") is Dictionary or animation.tween_sequences.size()>2: return false
	if not animation.get("repeat",false) is bool or not _number(animation.get("offset",0)) or abs(animation.get("offset",0))>3600: return false
	for property in animation.tween_sequences:
		if not property in ["position","rotation_degrees"]: return false
		var sequence = animation.tween_sequences[property]
		if not sequence is Dictionary or sequence.get("property")!=property or not sequence.get("tweens") is Array or sequence.tweens.size()>4096: return false
		if not _number(sequence.get("total_duration",0)) or sequence.get("total_duration",0)<0: return false
		for frame in sequence.tweens:
			if not frame is Dictionary or not _number(frame.get("duration")) or frame.duration<0 or frame.duration>3600: return false
			if not _integer(frame.get("transition"),0,10) or not _integer(frame.get("ease_type"),0,3): return false
			var type = frame.get("value_type")
			if not _integer(type,0,TYPE_VECTOR2): return false
			if type==TYPE_NIL: continue # Native delay key.
			if property=="position":
				if type!=TYPE_VECTOR2 or not _number(frame.get("value_x")) or not _number(frame.get("value_y")): return false
			elif not type in [TYPE_INT,TYPE_REAL] or not _number(frame.get("value")): return false
	return true

func load_local() -> void:
	entries = []
	healthy = true
	var file = File.new()
	if not file.file_exists(path): return
	if file.open(path,File.READ) != OK:
		healthy = false
		return
	if file.get_len() > MAX_BYTES * LIMIT:
		file.close()
		healthy = false
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or not parsed.result is Dictionary or parsed.result.get("version") != 1 or not parsed.result.get("entries") is Array or parsed.result.entries.size() > LIMIT:
		healthy = false
		return
	for entry in parsed.result.entries:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("name") is String or not valid(entry.get("payload")):
			healthy = false
			entries.clear()
			return
		entries.append(entry)

func add(title, payload) -> String:
	if not healthy: return "Stamp library is damaged. It was preserved; restore its backup first."
	if not valid(payload): return "Unsupported stamp. Nothing imported."
	if entries.size() >= LIMIT: return "100 stamps saved. Remove one before saving another."
	var entry = {"id":Crypto.new().generate_random_bytes(16).hex_encode(),"name":str(title).strip_edges().substr(0,60),"payload":payload.duplicate(true),"created":OS.get_unix_time()}
	if entry.name.empty(): entry.name = "Untitled stamp"
	entries.append(entry)
	if not _save():
		entries.pop_back()
		return error
	return "Saved stamp: " + entry.name

func remove(id) -> bool:
	for i in entries.size():
		if entries[i].id == id:
			var before = entries.duplicate(true)
			entries.remove(i)
			if _save(): return true
			entries = before
	return false

func _save() -> bool:
	error = "Couldn't save the stamp library; previous library preserved."
	var dir = Directory.new()
	dir.make_dir_recursive(path.get_base_dir())
	var file = File.new()
	if file.open(path+".tmp",File.WRITE) != OK: return false
	file.store_string(JSON.print({"version":1,"entries":entries}))
	file.close()
	if file.file_exists(path) and dir.copy(path,path+".bak") != OK: return false
	if dir.rename(path+".tmp",path) != OK: return false
	error = ""
	return true
