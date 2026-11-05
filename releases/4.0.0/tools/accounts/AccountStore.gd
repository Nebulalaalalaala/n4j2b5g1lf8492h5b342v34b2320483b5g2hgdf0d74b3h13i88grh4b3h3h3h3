extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

var directory = "user://goobplayability/accounts"
var records = []
var active_id = ""
var error = ""
var read_only = false
var disk_signature = ""

func valid_id(value):
	if not value is String or value.length() != 36:
		return false
	for i in value.length():
		if i in [8,13,18,23]:
			if value[i] != "-":
				return false
		elif not value[i].to_lower() in "0123456789abcdef":
			return false
	return true

func load_records():
	var file = File.new()
	var path = directory.plus_file("profiles.json")
	if not file.file_exists(path):
		return
	if file.open(path,File.READ) != OK:
		read_only = true
		return
	var parsed = JSON.parse(file.get_as_text() if file.get_len() <= 2097152 else "")
	file.close()
	if parsed.error != OK or not valid_metadata(parsed.result):
		read_only = true
		error = "Saved account list needs attention; nothing overwritten."
		return
	records = parsed.result.accounts
	active_id = parsed.result.get("active_id","")
	disk_signature = file.get_sha256(path)
	read_only = false
	error = ""

func unchanged_on_disk():
	var file = File.new()
	var path = directory.plus_file("profiles.json")
	return (not file.file_exists(path) and disk_signature.empty()) or (file.file_exists(path) and file.get_sha256(path) == disk_signature)

func can_add(id):
	return not read_only and unchanged_on_disk() and (not find(id).empty() or records.size() < 32)

func valid_metadata(data):
	if not data is Dictionary or data.get("version") != 1 or not data.get("accounts") is Array or data.accounts.size() > 32:
		return false
	var ids = []
	for record in data.accounts:
		if not record is Dictionary or not valid_id(record.get("id")) or ids.has(record.id):
			return false
		ids.append(record.id)
		if not record.get("name") is String or record.name.length() > 256 or not record.get("skin") is Dictionary:
			return false
		for key in record.skin:
			if not key is String or not record.skin[key] is String or key.length() > 128 or record.skin[key].length() > 256:
				return false
		for key in ["level","last_used"]:
			if not typeof(record.get(key)) in [TYPE_INT,TYPE_REAL] or is_nan(float(record[key])) or is_inf(float(record[key])) or record[key] < 0:
				return false
		for key in record:
			if not key in ["id","name","skin","level","last_used","signin_required","draft"]:
				return false
		if not record.get("draft",{}) is Dictionary or JSON.print(record.skin).length() > 16384 or JSON.print(record.get("draft",{})).length() > 32768:
			return false
		if not valid_draft(record.get("draft",{})):
			return false
	var active = data.get("active_id","")
	return active is String and (active.empty() or ids.has(active))

func valid_draft(draft):
	if not draft.get("selected",[]) is Array or draft.get("selected",[]).size() > 128:
		return false
	for item in draft.get("selected",[]):
		if not item is String or item.length() > 160:
			return false
	for key in ["enabled","custom","base"]:
		if draft.has(key) and not draft[key] is bool:
			return false
	for key in ["color","texture","emote"]:
		if draft.has(key) and (not draft[key] is String or draft[key].length() > 256):
			return false
	if not draft.get("effects",{}) is Dictionary:
		return false
	for key in draft.get("effects",{}):
		if not key in ["dash","trail","color"] or not draft.effects[key] is String or draft.effects[key].length() > 64:
			return false
	var transforms = load(ModPaths.path("CosmeticTransforms.gd"))
	return transforms.valid(draft.get("transforms",{}))

func save():
	var data = {"version":1,"active_id":active_id,"accounts":records}
	if read_only or not unchanged_on_disk() or not valid_metadata(data):
		error = "Cannot safely save account list."
		return false
	if Directory.new().make_dir_recursive(directory) != OK:
		return false
	var file = File.new()
	var path = directory.plus_file("profiles.json")
	if file.open(path+".tmp",File.WRITE) != OK:
		return false
	file.store_string(JSON.print(data))
	file.flush()
	var ok = file.get_error() == OK
	file.close()
	if not ok or Directory.new().rename(path+".tmp",path) != OK:
		return false
	disk_signature = file.get_sha256(path)
	return true

func find(id):
	for record in records:
		if record.id == id:
			return record
	return {}

func upsert(id,name,level,skin,at):
	if not valid_id(id) or read_only:
		return false
	var record = find(id)
	if record.empty():
		if records.size() >= 32:
			return false
		record = {"id":id,"draft":{}}
		records.append(record)
	record.name = str(name).substr(0,256)
	record.level = max(0,int(level))
	record.skin = skin.duplicate(true) if skin is Dictionary else {}
	record.last_used = at
	record.signin_required = false
	return save()

func vault(action,id,payload = {}):
	if not valid_id(id) or OS.get_name() != "Windows" or read_only:
		return {}
	var helper = ProjectSettings.globalize_path(get_script().resource_path.get_base_dir().plus_file("AccountVault.ps1"))
	if not File.new().file_exists(helper):
		return {}
	var args = ["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",helper,"-Action",action,"-Directory",ProjectSettings.globalize_path(directory),"-AccountId",id]
	var variable = "GOOB_ACCOUNT_IPC_%d_%d" % [OS.get_process_id(),OS.get_ticks_usec()]
	if action in ["Put","PutLogin"]:
		OS.set_environment(variable,JSON.print(payload))
		args += ["-PayloadVariable",variable]
	var output = []
	var code = OS.execute("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",PoolStringArray(args),true,output,false,false)
	if action in ["Put","PutLogin"]:
		OS.set_environment(variable,"")
	if code != 0 or output.empty():
		error = "Protected session storage unavailable."
		return {}
	var parsed = JSON.parse(str(output[0]))
	output.clear()
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}

func save_session(session):
	return bool(vault("Put",session.user_id,{"id":session.user_id,"token":session.token,"refresh_token":session.refresh_token}).get("ok",false))

func save_login(id,email,password):
	return bool(vault("PutLogin",id,{"id":id,"email":email,"password":password}).get("ok",false))

func session_for(id):
	var secret = vault("Get",id)
	if secret.get("id","") != id or not secret.get("token") is String or not secret.get("refresh_token") is String:
		return null
	var session = NakamaSession.new(secret.token,false,secret.refresh_token)
	secret.clear()
	return session if session.is_valid() and session.user_id == id else null

func remove(id):
	if find(id).empty() or not bool(vault("Remove",id).get("ok",false)):
		return false
	for i in range(records.size()-1,-1,-1):
		if records[i].id == id:
			records.remove(i)
	if active_id == id:
		active_id = ""
	return save()
