extends Reference
# Binary DATA ONLY, not str2var/resources/scripts. Preserve typed physics snapshots.
const RAW_LIMIT = 16777216
const WIRE_LIMIT = 4194304
var budget = 0
var scan_budget = 0

func safe(value, depth = 0) -> bool:
	budget += 1
	if budget>1000000 or depth>24: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL: return true
		TYPE_INT, TYPE_REAL: return not is_nan(float(value)) and not is_inf(float(value))
		TYPE_STRING: return value.length()<=1048576
		TYPE_VECTOR2: return safe(value.x,depth+1) and safe(value.y,depth+1)
		TYPE_RECT2: return safe(value.position,depth+1) and safe(value.size,depth+1)
		TYPE_COLOR: return safe(value.r,depth+1) and safe(value.g,depth+1) and safe(value.b,depth+1) and safe(value.a,depth+1)
		TYPE_DICTIONARY:
			if value.size()>20000: return false
			for key in value:
				if not typeof(key) in [TYPE_INT,TYPE_STRING]: return false
				if str(key).to_lower() in ["password","session","session_token","auth_token","apikey","api_key","hub_key","refresh_token"]: return false
				if not safe(value[key],depth+1): return false
		TYPE_ARRAY, TYPE_RAW_ARRAY, TYPE_INT_ARRAY, TYPE_REAL_ARRAY, TYPE_VECTOR2_ARRAY:
			if value.size()>500000: return false
			for entry in value:
				if not safe(entry,depth+1): return false
		_: return false
	return true

func valid_macro(data) -> bool:
	budget = 0
	if not data is Dictionary or not safe(data): return false
	if not data.get("checkpoints") is Array or data.checkpoints.empty() or data.checkpoints.size()>4096 or not data.get("segments") is Array or data.segments.size()>4096: return false
	if data.segments.size()<data.checkpoints.size()-1 or data.segments.size()>data.checkpoints.size(): return false
	for checkpoint in data.checkpoints:
		if not checkpoint is Dictionary or not checkpoint.get("position") is Vector2: return false
	for segment in data.segments:
		if not segment is Array: return false
		for frame in segment:
			if not frame is Dictionary: return false
			for action in ["player_left","player_right","player_up","player_dash","__tas_dash_right"]:
				if frame.has(action) and not frame[action] is bool: return false
			if frame.has("__tas_recorded_state"):
				var state = frame.__tas_recorded_state
				if not state is Dictionary: return false
				for vector in ["position","linear_velocity","ground_normal"]:
					if state.has(vector) and not state[vector] is Vector2: return false
	return data.get("level_context",{}) is Dictionary

func encode(data) -> Dictionary:
	if not valid_macro(data): return {}
	var bytes = var2bytes(data,false)
	if bytes.size()>RAW_LIMIT: return {}
	var compressed = bytes.compress(File.COMPRESSION_GZIP)
	var text = Marshalls.raw_to_base64(compressed)
	if text.length()>WIRE_LIMIT: return {}
	var package = {"version":1,"format":"macro-binary-gzip","bytes":bytes.size(),"data":text,"sha256":bytes.hex_encode().sha256_text()}
	var frames = 0
	for segment in data.segments: frames += segment.size()
	package.summary = {"level":str(data.get("level_context",{}).get("level_name","")).substr(0,100),"frames":frames,"checkpoints":data.checkpoints.size()}
	return package if JSON.print(package).to_utf8().size()<WIRE_LIMIT-4096 else {}

func decode(payload) -> Dictionary:
	if not payload is Dictionary or payload.get("version")!=1 or payload.get("format")!="macro-binary-gzip": return {}
	if not typeof(payload.get("bytes")) in [TYPE_INT,TYPE_REAL] or payload.bytes<1 or payload.bytes>RAW_LIMIT or int(payload.bytes)!=payload.bytes: return {}
	if not payload.get("data") is String or payload.data.empty() or payload.data.length()>WIRE_LIMIT: return {}
	var bytes = Marshalls.base64_to_raw(payload.data).decompress(int(payload.bytes),File.COMPRESSION_GZIP)
	if bytes.size()!=int(payload.bytes) or bytes.hex_encode().sha256_text()!=payload.get("sha256"): return {}
	scan_budget = 0
	if _scan(bytes,0,0)!=bytes.size(): return {}
	var data = bytes2var(bytes,false)
	return data if valid_macro(data) else {}

# Preflight counts/types/depth BEFORE the native decoder allocates anything.
# Matches Godot 3.5 core/io/marshalls.cpp; objects and resource paths rejected.
func _u32(bytes,at):
	return int(bytes[at])+int(bytes[at+1])*256+int(bytes[at+2])*65536+int(bytes[at+3])*16777216
func _scan(bytes, at, depth) -> int:
	scan_budget += 1
	if depth>24 or scan_budget>1000000 or at<0 or at+4>bytes.size(): return -1
	var header = _u32(bytes,at)
	var kind = header & 255
	if header != kind and not (kind in [TYPE_INT,TYPE_REAL] and header==kind+65536): return -1
	at += 4
	var fixed = {TYPE_NIL:0,TYPE_BOOL:4,TYPE_INT:8 if header>255 else 4,TYPE_REAL:8 if header>255 else 4,TYPE_VECTOR2:8,TYPE_RECT2:16,TYPE_COLOR:16}
	if fixed.has(kind): return at+fixed[kind] if at+fixed[kind]<=bytes.size() else -1
	if at+4>bytes.size(): return -1
	var count = _u32(bytes,at)
	at += 4
	if kind==TYPE_STRING:
		if count>1048576: return -1
		var end = at+count+((4-count%4)%4)
		return end if end<=bytes.size() else -1
	if kind in [TYPE_ARRAY,TYPE_DICTIONARY]:
		if count>500000 or (kind==TYPE_DICTIONARY and count>20000): return -1
		for _i in range(count*(2 if kind==TYPE_DICTIONARY else 1)):
			at = _scan(bytes,at,depth+1)
			if at<0: return -1
		return at
	var widths = {TYPE_RAW_ARRAY:1,TYPE_INT_ARRAY:4,TYPE_REAL_ARRAY:4,TYPE_VECTOR2_ARRAY:8}
	if not widths.has(kind) or count>500000: return -1
	var size = count*widths[kind]
	var end = at+size+((4-size%4)%4)
	return end if end<=bytes.size() else -1
