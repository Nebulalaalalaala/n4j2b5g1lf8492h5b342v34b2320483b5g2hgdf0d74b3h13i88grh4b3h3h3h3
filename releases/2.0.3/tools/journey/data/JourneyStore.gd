extends Reference

# Per-account Journey UI state: pinned goals, featured badges, claimed
# achievement tiers, the inbox and what has already been announced. Lives next
# to the ledger as <account sha256>.ui.json. Never holds XP; claiming XP stays
# with the ledger owner, who calls mark_claimed() after a successful award.
const VERSION = 1
const MAX_PINS = 3
const MAX_FEATURED = 3
const MAX_INBOX = 100
const KINDS = ["achievement","quest","rank","map","reward","session"]
const STATES = ["claimable","unread","read","claimed"]
# Flip to true once achievement XP claims go through the ledger; until then
# reached tiers are shown as earned, never as claimable.
var claims_enabled = true
var account_id = ""
var path = ""
var writable = false
var pins = []
var featured = []
var claimed = {}
var inbox = []
var seen = {}
var baseline = false
# Today's/this week's quest picks, rerolls and claimed quest ids (JourneyQuests).
var quests = {}
# Test tools state (triple-click the Journey gear): {xp, done: {quest id: true}}.
# Display-only; never written to the XP ledger. Cleared by "Reset to normal".
var test = {}
# Calculate XP (JourneyXPBackfill): {"wins": n, "maps": n, "time": unix} counted before tracking began.
var backfill = {}
# The account's own GooberDash stats (Winstreak, CurrentWinstreak, time fetched) for Win Streak.
var native = {}

func configure(owner: String,directory = "user://goobplayability/journey") -> bool:
	if owner==account_id and (writable or owner.empty()):
		return writable
	account_id = owner
	_pc = null
	pins = []
	featured = []
	claimed = {}
	inbox = []
	seen = {"ranks":{},"tiers":{},"maps":{}}
	baseline = false
	quests = {}
	test = {}
	backfill = {}
	native = {}
	writable = false
	path = ""
	if owner.empty():
		return false
	path = directory.plus_file(owner.sha256_text()+".ui.json")
	writable = true
	var file = File.new()
	if not file.file_exists(path):
		return true
	if file.open(path,File.READ)!=OK:
		writable = false
		return false
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error!=OK or not parsed.result is Dictionary or parsed.result.get("version")!=VERSION or parsed.result.get("account_id")!=owner:
		# Unreadable state is left untouched on disk rather than overwritten.
		writable = false
		return false
	var data = parsed.result
	for pin in data.get("pins",[]):
		if pin is Dictionary and str(pin.get("kind","")) in ["achievement","map","rank","quest","milestone"] and pins.size()<MAX_PINS:
			pins.append({"kind":str(pin.kind),"key":str(pin.get("key",""))})
	for key in data.get("featured",[]):
		if featured.size()<MAX_FEATURED and not str(key) in featured:
			featured.append(str(key))
	var saved_claims = data.get("claimed",{})
	if saved_claims is Dictionary:
		for key in saved_claims:
			claimed[str(key)] = int(clamp(int(saved_claims[key]),0,10000))
	for item in data.get("inbox",[]):
		var clean = _item(item)
		if not clean.empty() and inbox.size()<MAX_INBOX:
			inbox.append(clean)
	var saved_seen = data.get("seen",{})
	if saved_seen is Dictionary:
		for group in seen:
			if saved_seen.get(group) is Dictionary:
				seen[group] = saved_seen[group]
	baseline = bool(data.get("baseline",false))
	if data.get("quests") is Dictionary:
		quests = data.quests
	if data.get("test") is Dictionary:
		test = data.test
	if data.get("backfill") is Dictionary:
		backfill = data.backfill
	if data.get("native") is Dictionary:
		native = data.native
	return true

func save() -> bool:
	if not writable or path.empty():
		return false
	var directory = Directory.new()
	directory.make_dir_recursive(path.get_base_dir())
	var temporary = path+".tmp"
	var file = File.new()
	if file.open(temporary,File.WRITE)!=OK:
		return false
	file.store_string(JSON.print({"version":VERSION,"account_id":account_id,"pins":pins,"featured":featured,
		"claimed":claimed,"inbox":inbox,"seen":seen,"baseline":baseline,"quests":quests,"test":test,"backfill":backfill,"native":native}))
	file.close()
	directory.remove(path)
	return directory.rename(temporary,path)==OK

func _item(item) -> Dictionary:
	if not item is Dictionary or str(item.get("id","")).empty() or str(item.get("id","")).length()>128:
		return {}
	if not str(item.get("kind","")) in KINDS or not str(item.get("state","")) in STATES:
		return {}
	return {"id":str(item.id),"kind":str(item.kind),"state":str(item.state),"title":str(item.get("title","")).left(120),
		"detail":str(item.get("detail","")).left(160),"xp":int(max(0,int(item.get("xp",0)))),"time":int(item.get("time",OS.get_unix_time())),
		"target":item.get("target",{}) if item.get("target",{}) is Dictionary else {}}

# ---------------------------------------------------------------- pins
func has_pin(kind,key) -> bool:
	for pin in pins:
		if pin.kind==kind and pin.key==str(key):
			return true
	return false

# Returns "added", "removed" or "full".
func toggle_pin(kind,key) -> String:
	for pin in pins:
		if pin.kind==kind and pin.key==str(key):
			pins.erase(pin)
			save()
			return "removed"
	if pins.size()>=MAX_PINS:
		return "full"
	pins.append({"kind":str(kind),"key":str(key)})
	save()
	return "added"

# ---------------------------------------------------------------- featured badges
func toggle_featured(key) -> String:
	if str(key) in featured:
		featured.erase(str(key))
		save()
		return "removed"
	if featured.size()>=MAX_FEATURED:
		return "full"
	featured.append(str(key))
	save()
	return "added"

# ---------------------------------------------------------------- claims
# Claims are per account (each account has its own progress). The older shared
# journey/pc-claims.json is left on disk but no longer consulted.
var _pc = null

func _pc_wide(_key) -> bool:
	return false

func _pc_claims() -> Dictionary:
	if _pc != null:
		return _pc
	_pc = {}
	var directory = path.get_base_dir() if not path.empty() else "user://goobplayability/journey"
	var file = File.new()
	if file.open(directory.plus_file("pc-claims.json"),File.READ)==OK:
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error==OK and parsed.result is Dictionary and parsed.result.get("claimed") is Dictionary:
			_pc = parsed.result.claimed
			return _pc
	var dir = Directory.new()
	if dir.open(directory)==OK:
		dir.list_dir_begin(true,true)
		var name = dir.get_next()
		while name!="":
			if name.ends_with(".ui.json") and file.open(directory.plus_file(name),File.READ)==OK:
				var parsed = JSON.parse(file.get_as_text())
				file.close()
				if parsed.error==OK and parsed.result is Dictionary and parsed.result.get("claimed") is Dictionary:
					for key in parsed.result.claimed:
						if _pc_wide(key):
							_pc[key] = max(int(_pc.get(key,0)),int(parsed.result.claimed[key]))
			name = dir.get_next()
	_save_pc()
	return _pc

func _save_pc() -> void:
	if _pc==null:
		return
	var directory = path.get_base_dir() if not path.empty() else "user://goobplayability/journey"
	Directory.new().make_dir_recursive(directory)
	var file = File.new()
	if file.open(directory.plus_file("pc-claims.json"),File.WRITE)==OK:
		file.store_string(JSON.print({"version":1,"claimed":_pc}))
		file.close()

# One-off reward flags: "map:<map id>:<objective>", "streak:…", "certified:…", "play:…".
func flag(key) -> bool:
	return int(claimed.get(str(key),0))>0 or (_pc_wide(key) and int(_pc_claims().get(str(key),0))>0)

# Records a flag without saving (callers batch, then save()).
func note(key, value = 1) -> void:
	claimed[str(key)] = max(int(claimed.get(str(key),0)),int(value))
	if _pc_wide(key):
		_pc_claims()[str(key)] = max(int(_pc.get(str(key),0)),int(value))
		_save_pc()

func set_flag(key) -> void:
	note(key)
	save()

func claimed_tier(key) -> int:
	return int(claimed.get(str(key),0))

# Called by the XP owner after the ledger accepted the tier award.
func mark_claimed(key,tier:int) -> void:
	note(key,int(clamp(max(tier,claimed_tier(key)),0,10000)))
	var id = "ach_%s_%d" % [str(key),tier]
	for item in inbox:
		if item.id==id:
			item.state = "claimed"
	save()

func quest_claimed(id) -> bool:
	return bool(quests.get("claimed",{}).get(str(id),false))

# Called by the XP owner after the ledger accepted a quest award.
func mark_quest(id) -> void:
	if not quests.get("claimed") is Dictionary:
		quests.claimed = {}
	quests.claimed[str(id)] = true
	for item in inbox:
		if item.id=="quest_"+str(id):
			item.state = "claimed"
	save()

# ---------------------------------------------------------------- inbox
# Adds an item once (by id). Returns true when it is new.
func push(item:Dictionary) -> bool:
	var clean = _item(item)
	if clean.empty():
		return false
	for existing in inbox:
		if existing.id==clean.id:
			return false
	inbox.push_front(clean)
	while inbox.size()>MAX_INBOX:
		inbox.pop_back()
	save()
	return true

func mark_read(id) -> void:
	for item in inbox:
		if item.id==str(id) and item.state=="unread":
			item.state = "read"
	save()

func mark_all_read() -> void:
	for item in inbox:
		if item.state=="unread":
			item.state = "read"
	save()

# Diff current progress against what was already announced and queue inbox
# items for anything new. The first run only records a baseline so existing
# progress doesn't flood the inbox. Returns the newly queued items.
func sync(model:Dictionary) -> Array:
	if not writable:
		return []
	var fresh = []
	var now = OS.get_unix_time()
	var changed = false
	for rank in model.get("roadmap",[]):
		var id = str(int(rank.id))
		if int(model.get("real_xp",model.get("xp",0)))>=int(rank.xp) and int(rank.xp)>0 and not seen.ranks.has(id):
			seen.ranks[id] = true
			changed = true
			if baseline:
				fresh.append({"id":"rank_"+id,"kind":"rank","state":"unread","title":"Promoted to "+str(rank.name),
					"detail":"New league reached" if int(rank.id)<18 and int(rank.id)%3==0 else "New division reached","time":now,"target":{"view":"roadmap"}})
	var achievements = model.get("achievements")
	if achievements!=null:
		for c in achievements.collections:
			if c.get("unsupported",false):
				continue
			for tier in range(1,int(c.tier)+1):
				var id = "%s_%d" % [c.key,tier]
				if seen.tiers.has(id):
					continue
				seen.tiers[id] = true
				changed = true
				if baseline:
					fresh.append({"id":"ach_"+id,"kind":"achievement","state":"claimable" if claims_enabled and tier>claimed_tier(c.key) else "unread",
						"title":"%s · %s" % [c.name,c.tier_names[tier-1] if tier-1<c.get("tier_names",[]).size() else "Kingly %d" % (tier-5)],"detail":"%d recorded" % int(c.value),
						"xp":int(c.xp[tier-1]) if claims_enabled else 0,"time":now,"target":{"view":"achievement","key":c.key}})
	var stats = model.get("stats")
	if stats!=null:
		for map in stats.maps:
			var id = str(map.key).split(":",true,1)[-1]
			if int(map.get("plays",0))>0 and not seen.maps.has(id):
				seen.maps[id] = true
				changed = true
				if baseline:
					fresh.append({"id":"map_"+id,"kind":"map","state":"unread","title":"New map discovered",
						"detail":str(map.name),"time":now,"target":{"view":"map","key":str(map.key)}})
	if not baseline:
		baseline = true
		changed = true
	var added = []
	for item in fresh:
		var clean = _item(item)
		if not clean.empty():
			inbox.push_front(clean)
			added.append(clean)
	while inbox.size()>MAX_INBOX:
		inbox.pop_back()
	if changed or not added.empty():
		save()
	return added
