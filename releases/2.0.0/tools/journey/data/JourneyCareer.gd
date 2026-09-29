extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Career: recorded rounds and active time from every account that has signed in
# on this PC (profile_history/*.json and journey/*.activity.json), merged.
# Journey XP and rank stay per account. Read-only: never writes, moves or
# deletes anything in profile_history, journey/ or the account manager.
const HISTORY_DIR = ModPaths.PROFILE_HISTORY_DIR
const JOURNEY_DIR = "user://goobplayability/journey"

var _cache = {}

# Every recorded round from every account on this PC, oldest first. The
# signed-in account's live records replace its own (possibly older) file.
# Other accounts' files are re-read only when they change.
func merged_records(owner:String,live:Array) -> Array:
	var own = owner.sha256_text()+".json" if not owner.empty() else ""
	var records = []
	var ids = {}
	for r in live:
		if r is Dictionary and not ids.has(str(r.get("id",""))):
			ids[str(r.get("id",""))] = true
			records.append(r)
	for name in _files(HISTORY_DIR,".json"):
		if name==own:
			continue
		var path = HISTORY_DIR.plus_file(name)
		var stamp = File.new().get_modified_time(path)
		if not _cache.has(name) or _cache[name].stamp!=stamp:
			var data = _read(path)
			_cache[name] = {"stamp":stamp,"records":data.records if data.get("records") is Array else []}
		for r in _cache[name].records:
			if r is Dictionary and r.has("date") and r.has("mode") and r.has("map_id") and not ids.has(str(r.get("id",""))):
				ids[str(r.get("id",""))] = true
				records.append(r)
	records.sort_custom(self,"_earlier")
	return records

func _earlier(a,b) -> bool:
	return int(a.date)<int(b.date)

func account_count() -> int:
	return _files(HISTORY_DIR,".json").size()

# owner: the signed-in account id (its live tracker snapshot replaces its file).
func build(owner:String,snapshot,records = null) -> Dictionary:
	if records==null:
		records = merged_records(owner,[])
	var accounts = account_count()
	var days = {}
	var lifetime = 0.0
	var own = owner.sha256_text()+".activity.json" if not owner.empty() else ""
	for name in _files(JOURNEY_DIR,".activity.json"):
		if name==own and snapshot!=null:
			continue
		var data = _read(JOURNEY_DIR.plus_file(name))
		lifetime += float(data.get("lifetime",0))
		var saved = data.get("days",{})
		if saved is Dictionary:
			for key in saved:
				if saved[key] is Dictionary:
					days[key] = float(days.get(key,0.0))+float(saved[key].get("active",0))
	# Last 7 local days, oldest first, plus the live snapshot of this account.
	var week = []
	var now = OS.get_unix_time()
	for i in range(6,-1,-1):
		var d = OS.get_datetime_from_unix_time(now-i*86400+int(OS.get_time_zone_info().get("bias",0))*60)
		week.append(int(days.get("%04d-%02d-%02d" % [d.year,d.month,d.day],0.0)))
	if snapshot!=null:
		for i in week.size():
			week[i] += int(snapshot.days[i]) if i<snapshot.days.size() else 0
		lifetime += float(snapshot.lifetime_seconds)
	return {"records":records,"accounts":accounts,"days":week,"today_seconds":week[6],"lifetime_seconds":int(lifetime)}

func _files(directory,suffix) -> Array:
	var out = []
	var dir = Directory.new()
	if dir.open(directory)!=OK:
		return out
	dir.list_dir_begin(true,true)
	var name = dir.get_next()
	while name!="":
		if not dir.current_is_dir() and name.ends_with(suffix):
			out.append(name)
		name = dir.get_next()
	return out

func _read(path) -> Dictionary:
	var file = File.new()
	if file.open(path,File.READ)!=OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error==OK and parsed.result is Dictionary else {}
