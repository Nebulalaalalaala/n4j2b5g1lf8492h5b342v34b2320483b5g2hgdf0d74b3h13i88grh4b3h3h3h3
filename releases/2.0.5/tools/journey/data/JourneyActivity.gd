extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Evidence-based activity; old input-only history is preserved separately.
const VERSION = 2
const IDLE_AFTER = 300.0
const KEEP_DAYS = 90
const SAVE_EVERY = 30.0
var account_id = ""
var path = ""
var writable = false
var days = {}
var lifetime = 0.0
var held = 0.0
var since_input = IDLE_AFTER
var idle = true
var save_timer = 0.0
var dirty = false
var evidence
var sample_timer = 0.0
var legacy_lifetime = 0.0
var milestone_dates = {}
var verified_since = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)
	evidence = load(ModPaths.path("JourneyActivityEvidence.gd")).new()
	add_child(evidence)

func configure(owner:String,directory = "user://goobplayability/journey") -> bool:
	if owner==account_id:
		return writable
	if dirty and not save():
		return false
	account_id = owner
	days = {}
	lifetime = 0.0
	legacy_lifetime = 0.0
	milestone_dates = {}
	verified_since = OS.get_unix_time()
	sample_timer = 0.0
	dirty = false
	idle = true
	if is_instance_valid(evidence):
		evidence.reset()
	held = 0.0
	writable = false
	path = ""
	if owner.empty():
		return false
	path = directory.plus_file(owner.sha256_text()+".activity.json")
	writable = true
	var file = File.new()
	if not file.file_exists(path):
		return true
	if file.open(path,File.READ)!=OK:
		writable = false
		return false
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error!=OK or not parsed.result is Dictionary or not int(parsed.result.get("version",0)) in [1,VERSION] or parsed.result.get("account_id")!=owner:
		writable = false
		return false
	var legacy = int(parsed.result.version) == 1
	var saved = parsed.result.get("days",{})
	if saved is Dictionary:
		for key in saved:
			var day = saved[key]
			if day is Dictionary:
				days[str(key)] = {"active":0.0 if legacy else max(0.0,float(day.get("active",0))),"open":max(0.0,float(day.get("open",0))),"legacy_active":max(0.0,float(day.get("active",0) if legacy else day.get("legacy_active",0)))}
	lifetime = 0.0 if legacy else max(0.0,float(parsed.result.get("lifetime",0)))
	legacy_lifetime = max(0.0,float(parsed.result.get("lifetime",0) if legacy else parsed.result.get("legacy_lifetime",0)))
	milestone_dates = parsed.result.get("milestone_dates",{}).duplicate()
	verified_since = int(parsed.result.get("verified_since",OS.get_unix_time()))
	dirty = legacy
	return true

func _process(delta):
	if not writable:
		return
	_add("open",min(delta,1.0))
	if delta > 1.0 or not OS.is_window_focused() or get_tree().paused:
		sample_timer = 0.0
		idle = true
		evidence.reset()
	else:
		sample_timer += delta
		if sample_timer >= 0.25:
			evidence.service = get_parent().get("profile_service")
			var earned = evidence.sample(sample_timer, account_id)
			since_input = 0.0 if earned > 0.0 else since_input + sample_timer
			idle = earned <= 0.0
			credit(earned)
			sample_timer = 0.0
	save_timer += delta
	if save_timer>=SAVE_EVERY:
		save_timer = 0.0
		save()

func credit(seconds):
	if not writable or seconds <= 0.0 or is_nan(seconds) or is_inf(seconds):
		return
	_add("active",seconds)
	lifetime += seconds
	for hours in [50,100]:
		if lifetime >= hours * 3600 and not milestone_dates.has(str(hours)):
			milestone_dates[str(hours)] = OS.get_unix_time()

func _add(field,seconds):
	var key = _day_key(OS.get_unix_time())
	if not days.has(key):
		days[key] = {"active":0.0,"open":0.0}
	days[key][field] += seconds
	dirty = true

func _day_key(unix:int) -> String:
	var bias = int(OS.get_time_zone_info().get("bias",0))*60
	var d = OS.get_datetime_from_unix_time(unix+bias)
	return "%04d-%02d-%02d" % [d.year,d.month,d.day]

func save() -> bool:
	if not writable or path.empty() or not dirty:
		return false
	var keys = days.keys()
	keys.sort()
	while keys.size()>KEEP_DAYS:
		days.erase(keys.pop_front())
	var directory = Directory.new()
	directory.make_dir_recursive(path.get_base_dir())
	var file = File.new()
	if file.open(path+".tmp",File.WRITE)!=OK:
		return false
	file.store_string(JSON.print({"version":VERSION,"account_id":account_id,"days":days,"lifetime":lifetime,"legacy_lifetime":legacy_lifetime,"milestone_dates":milestone_dates,"verified_since":verified_since}))
	file.close()
	if file.file_exists(path):
		directory.remove(path+".bak")
		if directory.rename(path,path+".bak")!=OK:
			return false
	if directory.rename(path+".tmp",path)!=OK:
		if file.file_exists(path+".bak"):
			directory.rename(path+".bak",path)
		return false
	dirty = false
	return true

func _exit_tree():
	save()

# Local day keys (YYYY-MM-DD) with at least a minute of active time.
func active_days() -> Dictionary:
	var out = {}
	for key in days:
		if float(days[key].get("active",0.0))>=60.0:
			out[key] = true
	return out

# Shape JourneyModel/UI expect for `activity`. Held (not yet confirmed) time is
# included for today so the counter doesn't jump when the next input arrives.
func snapshot() -> Dictionary:
	var now = OS.get_unix_time()
	var week = []
	for i in range(6,-1,-1):
		var day = days.get(_day_key(now-i*86400),{})
		week.append(int(day.get("active",0.0)+(held if i==0 else 0.0)))
	var today = days.get(_day_key(now),{})
	return {"today_seconds":week[6],"open_seconds":int(today.get("open",0.0)),"lifetime_seconds":int(lifetime+held),
		"inactive":idle,"days":week,"idle_after":int(IDLE_AFTER),"verified_since":verified_since,"legacy_seconds":int(legacy_lifetime),"milestone_dates":milestone_dates.duplicate()}
