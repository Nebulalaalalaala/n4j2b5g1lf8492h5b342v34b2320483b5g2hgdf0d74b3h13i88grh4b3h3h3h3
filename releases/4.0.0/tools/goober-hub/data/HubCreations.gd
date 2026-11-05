extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
signal changed
signal completed(message)
signal outfit_ready(code)
signal item_saved(code)
const KINDS = ["outfit","stamp","macro"]
const CODE_PREFIX = {"outfit":"GP-O-","stamp":"GP-S-","macro":"GP-M-"}
var hub
var api
var identity
var profile_owner = ""
var kind = "outfit"
var offset = 0
var rows = []
var status = "idle"
var error = ""
var _requests = {}
var _serial = 0
var _loaded = ""
var _fetched = 0
var pending_item = {}
var last_code = ""
const PREVIEW_CACHE_LIMIT = 24
var _outfit_cache = {}
var _outfit_order = []

func _ready(): api.connect("done",self,"_done")

func studio():
	var sandbox = hub.tool.get("_cosmetic_sandbox")
	if not is_instance_valid(sandbox): return null
	if not is_instance_valid(sandbox._studio) and sandbox.has_method("_ensure_studio"): sandbox._ensure_studio()
	return sandbox._studio if is_instance_valid(sandbox._studio) else null

func can_macros() -> bool:
	return ModPaths.has("TasHandler.gd") and ModPaths.has("TASMacroEditor.gd")

func local_items(which) -> Array:
	if which == "macro" and not can_macros(): return []
	var list = []
	if which == "outfit":
		var source = studio()
		if source != null:
			for look in source.library.looks: list.append({"key":str(look.id),"name":str(look.name),"raw":look.state.duplicate(true)})
	elif which == "stamp":
		var script = ModPaths.try_load(ModPaths.path("EditorStampStore.gd"))
		if script != null:
			var source = script.new()
			source.load_local()
			for entry in source.entries: list.append({"key":entry.id,"name":entry.name,"raw":entry.payload.duplicate(true)})
	elif which == "macro" and hub.tool.has_method("_get_practice_macro_share_items"):
		list = hub.tool._get_practice_macro_share_items()
	return list

func prepare(which, item) -> Dictionary:
	if which == "macro" and not can_macros(): return {}
	if not which in KINDS or not item is Dictionary: return {}
	var payload = {}
	match which:
		"outfit":
			var source = studio()
			if source != null: payload = load(ModPaths.path("StudioSharedLooks.gd")).pack(source,item.raw)
		"stamp":
			var rules = ModPaths.try_load(ModPaths.path("EditorStampStore.gd"))
			if rules != null and rules.valid(item.raw): payload = item.raw.duplicate(true)
		"macro":
			if hub.tool.has_method("_get_practice_macro_share_data"):
				payload = load(ModPaths.path("HubCreationCodec.gd")).new().encode(hub.tool._get_practice_macro_share_data(int(item.key)))
	if payload.empty(): return {}
	return {"kind":which,"name":str(item.name).substr(0,60),"payload":payload,"source_key":str(item.key),"owner":identity.user_id}

func fetch(user_id, which, page_offset = 0, force = false):
	if not str(user_id).length()==36 or not which in KINDS: return
	var previous_view = profile_owner+":"+kind+":"+str(offset)
	if profile_owner!=str(user_id): pending_item = {}
	profile_owner = str(user_id)
	kind = which
	offset = max(0,int(page_offset))
	var key = profile_owner+":"+kind+":"+str(offset)
	if not force and key == previous_view and key == _loaded and OS.get_unix_time()-_fetched<60: return
	if api.pending("creations:list:"+key): return
	if force:
		# Refresh can retry unavailable artwork; redraws never retry failures.
		_outfit_cache.clear()
		_outfit_order.clear()
	status = "loading"
	error = ""
	if key != _loaded: rows = []
	_requests["creations:list:"+key] = {"operation":"list","view":key}
	api.call_fn("hub_creation_list",{"p_owner":profile_owner,"p_kind":kind,"p_offset":offset},"creations:list:"+key)

func publish(item) -> void:
	if not identity.signed_in() or not item is Dictionary or item.empty() or item.get("owner") != identity.user_id:
		emit_signal("completed","Sign in to publish your own creation.")
		return
	if _has_write():
		emit_signal("completed","Wait for the current upload to finish.")
		return
	_request("publish",identity.auth({"p_kind":item.kind,"p_title":item.name,"p_payload":item.payload}),{"account":identity.user_id})

func unpublish(row) -> void:
	if not identity.signed_in() or row.get("owner") != identity.user_id or _has_write(): return
	_request("remove",identity.auth({"p_id":row.id}),{"account":identity.user_id})

func download(row, equip = false):
	if not _metadata(row) or not _can_download(): return
	_request("get",{"p_code":code(row)}, {"account":identity.user_id,"equip":equip,"mode":"save"})

func lookup_code(text):
	if str(text).strip_edges().to_upper().begins_with("GP-M-") and not can_macros():
		emit_signal("completed","TAS replay sharing requires the Advanced installer.")
		return
	if not valid_code(str(text).strip_edges()):
		emit_signal("completed","Paste a GP-O-, GP-S- or GP-M- sharing code.")
		return
	if not _can_download(): return
	_request("get",{"p_code":str(text).strip_edges()}, {"account":identity.user_id,"view_owner":profile_owner,"equip":false,"mode":"preview"})

# Read-only card artwork. Called only by visible outfit holders. Payloads are
# immutable after publication, bounded in memory, and never imported/equipped.
func outfit_preview(row) -> Dictionary:
	if not _metadata(row) or row.kind!="outfit": return {}
	var key = code(row)
	if _outfit_cache.has(key):
		_outfit_order.erase(key)
		_outfit_order.append(key)
		return _outfit_cache[key]
	for context in _requests.values():
		if context.operation=="get" and context.get("code")==key: return {}
	if _download_count()>=2: return {}
	_request("get",{"p_code":key},{"account":identity.user_id,"expected_owner":row.owner,"mode":"card"})
	return {}

func _cache_outfit(key, item):
	_outfit_order.erase(key)
	_outfit_order.append(key)
	_outfit_cache[key] = item
	while _outfit_order.size()>PREVIEW_CACHE_LIMIT:
		_outfit_cache.erase(_outfit_order.pop_front())
	emit_signal("outfit_ready",key)

static func code(row) -> String:
	return CODE_PREFIX.get(str(row.get("kind","")),"")+str(row.get("id","")).replace("-","").to_upper()

static func valid_code(text) -> bool:
	return text.length()==37 and text.substr(0,5) in CODE_PREFIX.values() and text.substr(5).is_valid_hex_number(false)

func _request(operation, args, context):
	_serial += 1
	var tag = "creations:"+operation+":"+str(_serial)
	context.operation = operation
	if operation=="get": context.code = args.p_code
	_requests[tag] = context
	api.call_fn("hub_creation_"+operation,args,tag)

func _can_download() -> bool:
	if _download_count()>=2:
		emit_signal("completed","Wait for the current download to finish.")
		return false
	return true

func _download_count() -> int:
	var count = 0
	for context in _requests.values():
		if context.operation=="get": count += 1
	return count

static func _metadata(row) -> bool:
	if not row is Dictionary or not row.get("kind") in KINDS or not row.get("title") is String or row.title.length()>60: return false
	if not row.get("owner") is String or row.owner.length()!=36: return false
	return valid_code(code(row)) and str(row.get("id","")).length()==36

func _has_write() -> bool:
	for tag in _requests:
		if _requests[tag].operation in ["publish","remove"]: return true
	return false

func _done(tag, ok, data, message):
	if not _requests.has(tag): return
	var context = _requests[tag]
	_requests.erase(tag)
	if context.operation == "list":
		if context.view != profile_owner+":"+kind+":"+str(offset): return
		status = "ready" if ok else "missing" if message=="missing" else "error"
		error = str(message)
		# Cache failures too. changed→render must never immediately retry missing
		# SQL/offline requests in a loop; only Refresh or a later visit retries.
		_loaded = context.view
		_fetched = OS.get_unix_time()
		if ok:
			rows = []
			if data is Array:
				for row in data:
					if rows.size()>=24: break
					if _metadata(row) and row.owner==profile_owner and row.kind==kind: rows.append(row)
		emit_signal("changed")
		return
	if context.account != identity.user_id: return
	if context.operation=="get" and context.mode=="card":
		var source = studio()
		var valid = ok and _metadata(data) and code(data)==context.code and data.owner==context.expected_owner
		valid = valid and source!=null and data.get("payload") is Dictionary
		if valid: valid = load(ModPaths.path("StudioSharedLooks.gd")).valid(source,data.payload)
		_cache_outfit(context.code,data if valid else {"error":"Preview unavailable"})
		return
	if not ok:
		emit_signal("completed","Creations need the Supabase setup SQL." if message=="missing" else "Couldn't complete this action: "+str(message))
		return
	if context.operation == "publish":
		if not _metadata(data):
			emit_signal("completed","The server didn't confirm publication. Refresh your creations before trying again.")
			return
		last_code = code(data)
		emit_signal("completed","Published to your profile. Use Copy code to share it.")
		fetch(profile_owner,kind,offset,true)
	elif context.operation == "remove":
		emit_signal("completed","Removed from your public profile. Local saved item is unchanged." if data==true else "This creation is already removed or isn't yours.")
		fetch(profile_owner,kind,offset,true)
	elif context.operation == "get":
		if not _metadata(data) or code(data)!=str(context.code).to_upper() or not data.get("payload") is Dictionary:
			emit_signal("completed","Unsupported creation.")
			return
		if context.mode == "preview":
			if context.view_owner!=profile_owner: return
			pending_item = data
			emit_signal("changed")
			return
		emit_signal("completed",save_item(data,context.equip))

func save_item(item, equip = false) -> String:
	var result = _save_item(item,equip)
	if result.begins_with("Saved") or result.begins_with("Equipped"):
		emit_signal("item_saved",code(item))
	return result

func _save_item(item, equip = false) -> String:
	if item is Dictionary and item.get("kind") == "macro" and not can_macros():
		return "TAS replay sharing requires the Advanced installer. Nothing imported."
	if not _metadata(item) or not item.get("payload") is Dictionary: return "Unsupported creation. Nothing imported."
	if item.kind == "outfit":
		var target = studio()
		if target == null: return "Enable Avatar Studio to save this outfit."
		return load(ModPaths.path("StudioSharedLooks.gd")).save_to(target,item.payload,item.title,equip)
	if item.kind == "stamp":
		var script = ModPaths.try_load(ModPaths.path("EditorStampStore.gd"))
		if script == null: return "Enable Editor+ to save this stamp."
		var target = script.new()
		target.load_local()
		return target.add(item.title,item.payload)
	if item.kind == "macro":
		var decoded = load(ModPaths.path("HubCreationCodec.gd")).new().decode(item.payload)
		if decoded.empty(): return "Macro failed its safety/compatibility checks. Nothing imported."
		if not hub.tool.has_method("_import_downloaded_replay"): return "Enable Macro Bot to save this replay."
		var slot = hub.tool._import_downloaded_replay(decoded,str(item.title))
		return "Saved to new Macro slot %d." % slot if slot>0 else "No free Macro slot. Existing recordings were preserved."
	return "Unsupported creation."
