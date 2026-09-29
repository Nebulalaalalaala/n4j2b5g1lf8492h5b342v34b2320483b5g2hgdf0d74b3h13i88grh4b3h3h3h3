extends Reference

const VERSION = 1
const MAX_FILES = 10000
const MAX_BYTES = 67108864
const MAX_TOTAL_BYTES = 274877906944
const MAX_SAMPLES = 200000
const MAX_WORLD_SAMPLES = 400000
const MAX_ROUNDS = 16
const MAX_PLAYERS = 64
const WORLD_FIELDS = ["disappearing_counter","recharge_counter","timing_offset","lasing_duration_ticks","pause_duration_ticks","raycast_length","rotation","angular_velocity","body_enabled","visual_alpha","laser_visible","laser_glow","laser_length"]
var directory = "user://goobplayability/observed_captures"
var error = ""
var validation_error = ""

func invalid(reason):
	validation_error = reason
	return false

func number(value, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and value >= low and value <= high

func short_text(value, limit: int = 256) -> bool:
	return value is String and value.length() <= limit

func valid(data) -> bool:
	validation_error = ""
	if not data is Dictionary or data.get("version") != VERSION or data.get("kind") != "observed_match_capture":
		return invalid("capture rule 1")
	if not short_text(data.get("id"), 96) or not number(data.get("created_at"), 0, 99999999999) or not short_text(data.get("game_version")):
		return invalid("capture rule 2")
	if data.get("source") != "client_samples" or not data.get("rounds") is Array or data.rounds.empty() or data.rounds.size() > MAX_ROUNDS:
		return invalid("capture rule 3")
	var sample_count = 0
	var world_count = 0
	for round_data in data.rounds:
		if not round_data is Dictionary or not round_data.get("map") is Dictionary or not round_data.get("tracks") is Array or round_data.tracks.size() > MAX_PLAYERS:
			return invalid("capture rule 4")
		for key in ["id", "name", "author", "theme"]:
			if not short_text(round_data.map.get(key)):
				return invalid("capture rule 5")
		if not short_text(round_data.get("mode"), 64) or not short_text(round_data.get("round_id"), 128) or not number(round_data.get("started_at"), 0, 99999999999):
			return invalid("capture rule 6")
		if not round_data.get("completion","") in ["","round_transition","match_finished"] or not short_text(round_data.get("winner",""),96):
			return invalid("capture rule 7")
		for field in ["analysis_end_time","qualification_goal","qualified_count","winner_time"]:
			if round_data.has(field) and not number(round_data[field],0,86400):
				return invalid("capture rule 8")
		if not round_data.get("layout", []) is Array or round_data.get("layout", []).size() > 12000:
			return invalid("capture rule 9")
		if not round_data.get("geometry",[]) is Array or round_data.get("geometry",[]).size() > 12000:
			return invalid("capture rule 10")
		for polygon in round_data.get("geometry",[]):
			if not polygon is Dictionary or not short_text(polygon.get("type"),48) or not polygon.get("points") is Array or polygon.points.size() < 3 or polygon.points.size() > 64:
				return invalid("capture rule 11")
			for point in polygon.points:
				if not point is Array or point.size() != 2 or not number(point[0],-50000000,50000000) or not number(point[1],-50000000,50000000):
					return invalid("capture rule 12")
		for shape in round_data.get("layout", []):
			if not shape is Array or shape.size() != 6 or not short_text(shape[0], 48):
				return invalid("capture rule 13")
			for i in range(1, 6):
				if not number(shape[i], -1000000, 1000000):
					return invalid("capture rule 14")
			if shape[3] <= 0 or shape[4] <= 0:
				return invalid("capture rule 15")
		var ids = []
		if not round_data.get("world_tracks",{}) is Dictionary or round_data.get("world_tracks",{}).size() > 12000:
			return invalid("capture rule 16")
		for key in round_data.get("world_tracks",{}):
			if not key is String or not key.is_valid_integer() or int(key)<0 or int(key)>=12000 or not round_data.world_tracks[key] is Array:
				return invalid("capture rule 17")
			var previous_time = -1.0
			for sample in round_data.world_tracks[key]:
				world_count += 1
				if world_count > MAX_WORLD_SAMPLES or not sample is Array or sample.size()!=2 or not number(sample[0],0,86400) or sample[0]<=previous_time or not sample[1] is Dictionary:
					return invalid("capture rule 18")
				previous_time = sample[0]
				for field in sample[1]:
					var value = sample[1][field]
					if field == "pose":
						if not value is Array or value.size()!=6:
							return invalid("capture rule 19")
						for component in value:
							if not number(component,-50000000,50000000):
								return invalid("capture rule 20")
					elif not field in WORLD_FIELDS or not (value is bool or number(value,-50000000,50000000)):
						return invalid("capture rule 21")
		if round_data.has("level_visual") and not valid_level_visual(round_data.level_visual):
			return invalid("capture rule 22")
		for track in round_data.tracks:
			if not track is Dictionary or not short_text(track.get("id"), 96) or ids.has(track.id) or not short_text(track.get("name")) or not track.get("samples") is Array:
				return invalid("capture rule 23")
			ids.append(track.id)
			if not short_text(track.get("account_id",""),96):
				return invalid("capture rule 24")
			if track.has("eliminated_at"):
				if not track.get("elimination_confirmed",false) is bool:
					return invalid("capture rule 25")
				var point = track.get("death_position")
				if not number(track.eliminated_at,0,86400) or not point is Array or point.size()!=2 or not number(point[0],-50000000,50000000) or not number(point[1],-50000000,50000000):
					return invalid("capture rule 26")
			if not track.get("skin",{}) is Dictionary or not safe_visual_value(track.get("skin",{}),0):
				return invalid("capture rule 27")
			if not track.get("poses",[]) is Array or track.get("poses",[]).size()>track.samples.size():
				return invalid("capture rule 28")
			var pose_time = -1.0
			for pose in track.get("poses",[]):
				if not pose is Array or not pose.size() in [3,6] or not number(pose[0],0,86400) or pose[0]<=pose_time or not short_text(pose[1],128) or not number(pose[2],0,86400):
					return invalid("capture rule 29")
				if pose.size()==6:
					for i in range(3,6):
						if not number(pose[i],-100,100):
							return invalid("capture rule 30")
				pose_time = pose[0]
			if not track.get("player_kind","unknown") in ["account","bot","unknown"] or not track.get("profile",{}) is Dictionary:
				return invalid("capture rule 31")
			for key in track.get("profile",{}):
				if not key in ["games","wins","level","observed_at"] or not number(track.profile[key],0,99999999999):
					return invalid("capture rule 32")
			if not track.get("outcome") in ["unknown", "finish", "dnf"] or not number(track.get("finish_time"), -1, 86400) or not number(track.get("placement"), 0, 1024):
				return invalid("capture rule 33")
			if track.outcome != "finish" and track.finish_time != -1:
				return invalid("capture rule 34")
			var last = -1.0
			for sample in track.samples:
				if not sample is Array or sample.size() != 6 or not number(sample[0], 0, 86400) or sample[0] <= last:
					return invalid("capture rule 35")
				last = sample[0]
				for i in [1, 2]:
					if not number(sample[i], -50000000, 50000000):
						return invalid("capture rule 36")
				if not number(sample[3], -100000, 100000) or not sample[4] in [-1, 1] or not sample[5] is bool:
					return invalid("capture rule 37")
				sample_count += 1
				if sample_count > MAX_SAMPLES:
					return invalid("capture rule 38")
	return true

func valid_level_visual(data):
	if not data is Dictionary or not data.get("metadata") is Dictionary or not data.get("nodes") is Array or data.nodes.size() > 12000:
		return invalid("level visual rule 1")
	for key in ["name","theme","published","game_mode"]:
		if not short_text(data.metadata.get(key)):
			return invalid("level visual rule 2")
	if not number(data.metadata.get("player_count"),0,1024):
		return invalid("level visual rule 3")
	for key in ["id","author_id","author_name"]:
		if not short_text(data.metadata.get(key,"")):
			return invalid("level visual rule 4")
	for key in ["rating","rating_count"]:
		if not number(data.metadata.get(key,0),0,1000000):
			return invalid("level visual rule 5")
	for node in data.nodes:
		if not node is Dictionary or not short_text(node.get("type"),48):
			return invalid("level visual rule 6")
		for key in ["x","y","width","height","rotation","shape_rotation","pivot_x","pivot_y"]:
			if not number(node.get(key),-1000000,1000000):
				return invalid("level visual rule 7")
		var bounded_node = node.duplicate()
		bounded_node.erase("animation")
		if node.width <= 0 or node.height <= 0 or not safe_visual_value(bounded_node,0):
			return invalid("level visual rule 8")
		if node.has("properties") and not node.properties is Dictionary:
			return invalid("level visual rule 9")
		if node.has("animation") and not valid_visual_animation(node.animation):
			return invalid("level visual rule 10")
	return safe_visual_value(data.metadata,0)

func valid_visual_animation(data):
	if not data is Dictionary or not data.get("repeat") is bool or not number(data.get("offset"),-86400,86400) or not data.get("tween_sequences") is Dictionary:
		return invalid("level visual rule 11")
	# Some shipped maps use extremely long pauses as a permanent hold.
	# Only durations get this allowance; positions/scales retain their limits.
	var bounded = data.duplicate(true)
	for key in data.tween_sequences:
		if not key in ["position","rotation_degrees","scale","modulate"]:
			return invalid("level visual rule 12")
		var sequence = data.tween_sequences[key]
		if not sequence is Dictionary or sequence.get("property") != key or not number(sequence.get("total_duration"),0,1000000000000) or not sequence.get("tweens") is Array or sequence.tweens.size() > 256:
			return invalid("level visual rule 13")
		bounded.tween_sequences[key].total_duration = 0
		for tween in sequence.tweens:
			if not tween is Dictionary:
				return invalid("level visual rule 14")
			for field in ["duration","ease_type","transition","value_type"]:
				if not number(tween.get(field),0,1000000000000 if field == "duration" else 32):
					return invalid("level visual rule 15")
		for tween in bounded.tween_sequences[key].tweens:
			tween.duration = 0
	return safe_visual_value(bounded,0)

func safe_visual_value(value,depth):
	if depth > 10:
		return false
	if value is Dictionary:
		if value.size() > 128:
			return false
		for key in value:
			if not short_text(key,128) or not safe_visual_value(value[key],depth+1):
				return false
		return true
	if value is Array:
		if value.size() > 256:
			return false
		for item in value:
			if not safe_visual_value(item,depth+1):
				return false
		return true
	if value is String:
		return value.length() <= 2048
	return value == null or value is bool or number(value,-1000000,1000000)

func files() -> Array:
	var result = []
	var dir = Directory.new()
	if dir.open(directory) != OK:
		return result
	dir.list_dir_begin(true, true)
	var file = dir.get_next()
	while not file.empty():
		if not dir.current_is_dir() and safe_name(file):
			result.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	result.sort()
	result.invert()
	return result

func safe_name(name: String) -> bool:
	return name == name.get_file() and name.begins_with("capture-") and name.ends_with(".json") and not ".meta." in name and name.length() < 128

func read_json(path: String, max_bytes: int):
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return null
	if file.get_len() > max_bytes:
		file.close()
		return null
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK else null

func read(name: String) -> Dictionary:
	if not safe_name(name):
		return {}
	var data = read_json(directory.plus_file(name), MAX_BYTES)
	return data if valid(data) else {}

func summary(data: Dictionary) -> Dictionary:
	var rounds = []
	for item in data.rounds:
		var tracks = []
		for track in item.tracks:
			tracks.append({"id": track.id, "name": track.name, "outcome": track.outcome, "finish_time": track.finish_time, "placement": track.placement, "samples": track.samples.size(), "profile":track.get("profile",{}),"player_kind":track.get("player_kind","unknown")})
		rounds.append({"map": item.map, "mode": item.mode, "round_id": item.round_id, "started_at": item.started_at, "tracks": tracks,"completion":item.get("completion",""),"qualification_goal":item.get("qualification_goal",0),"qualified_count":item.get("qualified_count",0)})
		for i in item.tracks.size():
			tracks[i]["account_id"] = item.tracks[i].get("account_id","")
		if item.has("winner_time"):
			rounds.back()["winner_time"] = item.winner_time
		rounds.back()["winner"] = item.get("winner","")
	return {"id": data.id, "created_at": data.created_at, "rounds": rounds, "source": "client_samples"}

func write_json(path: String, data) -> bool:
	var file = File.new()
	if file.open(path, File.WRITE) != OK:
		return false
	file.store_string(JSON.print(data))
	file.flush()
	var ok = file.get_error() == OK
	file.close()
	return ok

func save(data: Dictionary, stable_name: String = "") -> String:
	error = ""
	if not stable_name.empty() and not safe_name(stable_name):
		error = "Invalid capture filename."
		return ""
	if not valid(data):
		error = "Invalid observed capture: " + validation_error + "."
		# Keep rejected observations outside the playable library for diagnosis.
		# Never replace an earlier recovery file or weaken import validation.
		var recovery = directory.plus_file("recovery")
		var payload = JSON.print(data)
		var disk = Directory.new()
		if payload.to_utf8().size()<=MAX_BYTES and disk.make_dir_recursive(recovery)==OK and disk.open(recovery)==OK and disk.get_space_left()>MAX_BYTES+1073741824:
			var path = recovery.plus_file("rejected-"+str(OS.get_unix_time())+"-"+str(OS.get_ticks_usec())+".json")
			if not File.new().file_exists(path) and write_json(path,data):
				error += " Recovery copy saved."
		return ""
	var payload = JSON.print(data)
	var bytes = payload.to_utf8().size()
	if bytes > MAX_BYTES:
		error = "Capture exceeds the 64 MB limit."
		return ""
	var existing = files()
	var total = bytes
	for name in existing:
		if name==stable_name:
			continue
		var file = File.new()
		if file.open(directory.plus_file(name), File.READ) == OK:
			total += file.get_len()
			file.close()
	if (existing.size() >= MAX_FILES and not stable_name in existing) or total > MAX_TOTAL_BYTES:
		error = "Capture storage limit reached (10,000 files / 256 GB). Nothing deleted."
		return ""
	if Directory.new().make_dir_recursive(directory) != OK:
		error = "Cannot create capture folder."
		return ""
	var disk = Directory.new()
	if disk.open(directory) != OK or disk.get_space_left() < bytes + 1073741824:
		error = "Less than 1 GB free after saving. Recording stopped; nothing deleted."
		return ""
	var name = stable_name if not stable_name.empty() else "capture-%d-%d.json" % [OS.get_unix_time(), OS.get_ticks_usec()]
	var path = directory.plus_file(name)
	if stable_name.empty() and File.new().file_exists(path):
		error = "Capture filename collision; try again."
		return ""
	if not write_json(path + ".tmp", data) or not valid(read_json(path + ".tmp", MAX_BYTES)):
		error = "Could not verify capture write."
		return ""
	if Directory.new().rename(path + ".tmp", path) != OK:
		error = "Could not finalize capture."
		return ""
	write_index(name,summary(data))
	return name

func entries() -> Array:
	var result = []
	for name in files():
		if result.size() >= MAX_FILES:
			break
		var meta = indexed_summary(name)
		if meta.empty():
			continue
		meta.file = name
		result.append(meta)
	result.sort_custom(self,"newest_entry")
	return result

func newest_entry(a,b):
	return a.created_at>b.created_at if a.created_at!=b.created_at else a.file<b.file

func write_index(name,meta):
	var file = File.new()
	var path = directory.plus_file(name)
	if file.open(path,File.READ) != OK:
		return
	var size = file.get_len()
	file.close()
	write_json(path+".meta",{"index_version":3,"size":size,"modified":file.get_modified_time(path),"summary":meta})

func indexed_summary(name):
	var path = directory.plus_file(name)
	var file = File.new()
	if file.open(path,File.READ)!=OK:
		return {}
	var size = file.get_len()
	file.close()
	var index = read_json(path+".meta",2097152)
	if index is Dictionary and index.get("index_version")==3 and index.get("size")==size and index.get("modified")==file.get_modified_time(path) and valid_summary(index.get("summary")):
		return index.summary
	var data = read(name)
	if data.empty():
		return {}
	var meta = summary(data)
	write_index(name,meta)
	return meta

func valid_summary(meta):
	if not meta is Dictionary or not meta.get("rounds") is Array or meta.rounds.size()>MAX_ROUNDS:
		return false
	var check = {"version":VERSION,"kind":"observed_match_capture","id":meta.get("id"),"created_at":meta.get("created_at"),"game_version":"index","source":"client_samples","rounds":[]}
	for item in meta.rounds:
		if not item is Dictionary or not item.get("tracks") is Array or item.tracks.size()>MAX_PLAYERS:
			return false
		var row = item.duplicate(true)
		for track in row.tracks:
			if not track is Dictionary or not number(track.get("samples"),0,MAX_SAMPLES):
				return false
			track.samples = []
		check.rounds.append(row)
	return valid(check)

func remove(name: String) -> bool:
	if not safe_name(name):
		return false
	var path = directory.plus_file(name)
	if Directory.new().remove(path) != OK:
		return false
	if File.new().file_exists(path + ".meta"):
		Directory.new().remove(path + ".meta")
	return true

func extract(data: Dictionary, round_index: int, ids: Array) -> Dictionary:
	if not valid(data) or round_index < 0 or round_index >= data.rounds.size():
		return {}
	var output = data.duplicate(true)
	# Preserve source identity so extracted runs do not inflate map statistics.
	output.rounds = [data.rounds[round_index].duplicate(true)]
	output.rounds[0].tracks = []
	for track in data.rounds[round_index].tracks:
		if ids.has(track.id):
			output.rounds[0].tracks.append(track.duplicate(true))
	return output if not output.rounds[0].tracks.empty() else {}

func research(entries: Array, map_id: String, mode: String = "", outcome: String = "", date_from: int = 0) -> Array:
	var rows = []
	var seen = {}
	for capture in entries:
		for index in capture.rounds.size():
			var round_data = capture.rounds[index]
			var identity = round_data.map.id if not round_data.map.id.empty() else round_data.map.name + "|" + round_data.map.author
			if identity != map_id or (not mode.empty() and round_data.mode != mode) or capture.created_at < date_from:
				continue
			if outcome=="dnf":
				var goal = int(round_data.get("qualification_goal",0))
				if round_data.mode=="Elimination" or not round_data.get("completion","") in ["round_transition","match_finished"] or goal<=0 or int(round_data.get("qualified_count",0))>=goal:
					continue
			for track in round_data.tracks:
				if not outcome.empty() and track.outcome != outcome:
					continue
				var key = JSON.print([capture.id, round_data.round_id, track.id])
				if seen.has(key):
					continue
				seen[key] = true
				rows.append({"capture_id":capture.id, "file": capture.file, "round": index, "track": track.id, "name": track.name, "outcome": track.outcome, "time": track.finish_time, "mode": round_data.mode, "date": capture.created_at})
	return rows
