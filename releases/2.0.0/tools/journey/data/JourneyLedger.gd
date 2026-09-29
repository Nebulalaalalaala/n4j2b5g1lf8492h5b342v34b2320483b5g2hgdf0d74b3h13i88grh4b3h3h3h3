extends Reference

# Internal transaction store. Event adapters must establish eligibility before
# calling award; source labels are provenance, not server-side anti-cheat.
const MAX_RECORDS = 50000
const MAX_BYTES = 33554432
const CATEGORIES = ["win","placement","exploration","challenge","activity","record"]
var account_id = ""
var path = ""
var entries = []
var ids = {}
var total_xp = 0
var writable = false
var error = ""
var revision = 0

func configure(owner: String,directory = "user://goobplayability/journey") -> bool:
	account_id = owner
	path = directory.plus_file(owner.sha256_text()+".json")
	entries = []
	ids = {}
	total_xp = 0
	revision = 0
	error = ""
	writable = false
	if owner.empty():
		error = "Sign in to save Journey progress."
		return false
	if not File.new().file_exists(path):
		if File.new().file_exists(path+".bak"):
			error = "Journey needs recovery from backup; original data preserved."
			return false
		writable = true
		return true
	var data = _read()
	if data.empty():
		error = "Journey data unreadable; no progress overwritten."
		return false
	for entry in data.entries:
		if not _valid(entry) or ids.has(entry.id):
			error = "Invalid or duplicate Journey transaction; file preserved."
			entries = []
			ids = {}
			total_xp = 0
			return false
		entries.append(entry)
		ids[entry.id] = true
		total_xp += int(entry.amount)
	revision = int(data.revision)
	writable = true
	return true

func _valid(entry) -> bool:
	if not entry is Dictionary:
		return false
	for key in ["id","player_id","category","reason","related_id","source"]:
		if not entry.get(key) is String or entry[key].empty() or entry[key].length()>512:
			return false
	if entry.player_id!=account_id or not entry.category in CATEGORIES or not entry.source in ["server_event","verified_local_activity"]:
		return false
	for key in ["amount","timestamp"]:
		var value = entry.get(key)
		if not typeof(value) in [TYPE_INT,TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)) or value!=floor(value) or value<=0 or value>10000000000:
			return false
	return entry.amount<=1000000

func _read() -> Dictionary:
	var file = File.new()
	if file.open(path,File.READ)!=OK:
		return {}
	if file.get_len()>MAX_BYTES:
		file.close()
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error!=OK or not parsed.result is Dictionary:
		return {}
	var data = parsed.result
	if data.get("format")!=1 or data.get("account_id")!=account_id or not data.get("entries") is Array or data.entries.size()>MAX_RECORDS:
		return {}
	var rev = data.get("revision")
	if not typeof(rev) in [TYPE_INT,TYPE_REAL] or rev<0 or rev!=floor(rev):
		return {}
	return data

func award(entry: Dictionary) -> bool:
	if not writable or not _valid(entry):
		error = "Unsupported, invalid or unverified transaction."
		return false
	if ids.has(entry.id):
		error = "Already awarded."
		return false
	if entries.size()>=MAX_RECORDS:
		error = "Ledger capacity reached; archive migration required. Progress preserved."
		return false
	# Guard stale sequential writers. Runtime must have one ledger owner/account.
	if File.new().file_exists(path):
		var disk = _read()
		if disk.empty() or int(disk.revision)!=revision:
			error = "Journey changed elsewhere; reload before awarding."
			return false
	elif revision!=0:
		error = "Journey file disappeared; progress preserved in memory."
		return false
	var candidate = entries.duplicate(true)
	candidate.append(entry.duplicate(true))
	var text = JSON.print({"format":1,"account_id":account_id,"revision":revision+1,"entries":candidate})
	if text.to_utf8().size()>MAX_BYTES:
		error = "Journey capacity reached."
		return false
	var directory = Directory.new()
	if directory.make_dir_recursive(path.get_base_dir())!=OK:
		error = "Cannot create Journey folder."
		return false
	var file = File.new()
	if file.open(path+".tmp",File.WRITE)!=OK:
		error = "Cannot save Journey."
		return false
	file.store_string(text)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error!=OK:
		error = "Journey write failed."
		return false
	if file.file_exists(path) and directory.copy(path,path+".bak")!=OK:
		error = "Cannot back up Journey; award not committed."
		return false
	if directory.rename(path+".tmp",path)!=OK:
		error = "Cannot commit Journey; award not committed."
		return false
	entries = candidate
	ids[entry.id] = true
	total_xp += int(entry.amount)
	revision += 1
	error = ""
	return true

# Several awards in one write (map rewards, claim all). Already-awarded ids are
# skipped; any invalid entry rejects the whole batch. Returns XP added (-1 on error).
func award_batch(batch: Array) -> int:
	if not writable:
		error = "Unsupported, invalid or unverified transaction."
		return -1
	var fresh = []
	var seen = {}
	for entry in batch:
		if not _valid(entry):
			error = "Unsupported, invalid or unverified transaction."
			return -1
		if not ids.has(entry.id) and not seen.has(entry.id):
			seen[entry.id] = true
			fresh.append(entry.duplicate(true))
	if fresh.empty():
		return 0
	if entries.size()+fresh.size()>MAX_RECORDS:
		error = "Ledger capacity reached; archive migration required. Progress preserved."
		return -1
	if File.new().file_exists(path):
		var disk = _read()
		if disk.empty() or int(disk.revision)!=revision:
			error = "Journey changed elsewhere; reload before awarding."
			return -1
	elif revision!=0:
		error = "Journey file disappeared; progress preserved in memory."
		return -1
	var candidate = entries.duplicate(true)
	candidate.append_array(fresh)
	var text = JSON.print({"format":1,"account_id":account_id,"revision":revision+1,"entries":candidate})
	if text.to_utf8().size()>MAX_BYTES:
		error = "Journey capacity reached."
		return -1
	var directory = Directory.new()
	if directory.make_dir_recursive(path.get_base_dir())!=OK:
		error = "Cannot create Journey folder."
		return -1
	var file = File.new()
	if file.open(path+".tmp",File.WRITE)!=OK:
		error = "Cannot save Journey."
		return -1
	file.store_string(text)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error!=OK:
		error = "Journey write failed."
		return -1
	if file.file_exists(path) and directory.copy(path,path+".bak")!=OK:
		error = "Cannot back up Journey; award not committed."
		return -1
	if directory.rename(path+".tmp",path)!=OK:
		error = "Cannot commit Journey; award not committed."
		return -1
	var added = 0
	entries = candidate
	for entry in fresh:
		ids[entry.id] = true
		added += int(entry.amount)
	total_xp += added
	revision += 1
	error = ""
	return added

func category_totals(from_utc: int = 0,to_utc: int = 9223372036854775807) -> Dictionary:
	var result = {}
	for entry in entries:
		if entry.timestamp>=from_utc and entry.timestamp<to_utc:
			result[entry.category] = int(result.get(entry.category,0))+int(entry.amount)
	return result
