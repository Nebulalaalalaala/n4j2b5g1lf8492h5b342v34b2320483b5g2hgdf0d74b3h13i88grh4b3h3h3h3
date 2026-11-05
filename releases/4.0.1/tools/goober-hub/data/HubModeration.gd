extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# No background report polling and no saved admin credential. Server checks the
# fixed admin ID, its Hub capability AND Journey's private admin passphrase.
signal changed
signal completed(ok, message)
var api
var identity
var hub
var rows = []
var self_state = {}
var status = "idle"
var error = ""
var has_more = false
var reviewed = false
var before = 0
var busy = false
var _pass = ""
var _owner = ""
var _requests = {}
var _serial = 0
var _generation = 0
var _self_at = 0

func _ready():
	api.connect("done", self, "_done")
	identity.connect("changed", self, "_identity_changed")

func is_admin() -> bool:
	return hub != null and hub.account() == hub.ADMIN_ID and identity.user_id == hub.ADMIN_ID and identity.signed_in()

func _identity_changed():
	if _owner != identity.user_id:
		_owner = identity.user_id
		self_state = {}
		_self_at = 0
		lock()
		emit_signal("changed")
	if identity.signed_in() or identity.state == "banned": refresh_self()

func lock():
	_pass = ""
	_generation += 1
	rows = []
	status = "idle"
	error = ""
	busy = false
	has_more = false
	for tag in _requests.keys():
		if _requests[tag].kind != "self": _requests.erase(tag)

func unlock(value): _pass = str(value).strip_edges()

func _request(kind, fn, extra):
	_serial += 1
	var tag = "hubmod:" + str(_serial)
	_requests[tag] = {"kind": kind, "owner": identity.user_id, "generation": _generation}
	api.call_fn(fn, identity.auth(extra), tag)

func refresh_self():
	if not (identity.signed_in() or identity.state == "banned") or OS.get_unix_time() - _self_at < 2: return
	for job in _requests.values():
		if job.kind == "self" and job.owner == identity.user_id: return
	_self_at = OS.get_unix_time()
	_request("self", "hub_self_restrictions", {})

static func _unix(value) -> int:
	return load(ModPaths.path("HubFeed.gd")).unix(value) if value != null else 0

func banned() -> bool: return _unix(self_state.get("banned_until")) > OS.get_unix_time()
func muted() -> bool: return _unix(self_state.get("muted_until")) > OS.get_unix_time()

static func until_text(value) -> String:
	var stamp = _unix(value)
	if stamp <= 0: return "—"
	var date = OS.get_datetime_from_unix_time(stamp)
	return "%04d-%02d-%02d %02d:%02d UTC" % [date.year, date.month, date.day, date.hour, date.minute]

func fetch(show_reviewed = false, cursor = 0):
	if busy: return
	if not is_admin() or _pass.empty():
		emit_signal("completed", false, "Enter your Journey admin passphrase first.")
		return
	reviewed = bool(show_reviewed)
	before = int(cursor)
	busy = true
	status = "loading"
	error = ""
	rows = []
	_request("list", "hub_admin_reports", {"p_pass": _pass, "p_reviewed": reviewed, "p_before": before})
	emit_signal("changed")

func act(report_id, action, days = 0):
	if busy: return
	if not is_admin() or _pass.empty(): return emit_signal("completed", false, "Enter your Journey admin passphrase first.")
	if not action in ["dismiss", "ban", "mute", "unban", "unmute"]: return
	busy = true
	var nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	_request("act", "hub_admin_moderate", {"p_pass": _pass, "p_report": int(report_id), "p_action": action, "p_days": int(days), "p_nonce": nonce})
	emit_signal("changed")

func _done(tag, ok, data, message):
	if tag in ["send", "inbox"] and not ok and (message.find("not allowed") >= 0 or message.find("hub muted") >= 0 or message.find("hub banned") >= 0):
		refresh_self()
	if not _requests.has(tag): return
	var job = _requests[tag]
	_requests.erase(tag)
	if hub == null: return
	if job.owner != hub.account() or job.owner != identity.user_id:
		lock()
		self_state = {}
		emit_signal("changed")
		return
	if job.kind == "self":
		if ok and data is Dictionary:
			self_state = data
			if identity.state == "banned" and not banned(): identity.verify()
			emit_signal("changed")
		return
	if job.generation != _generation or not is_admin(): return
	busy = false
	if not ok:
		status = "missing" if message == "missing" else "error"
		error = "Run GOOBER_HUB_MODERATION.sql in Supabase first." if status == "missing" else "Couldn't load or update reports. Check your admin passphrase and connection."
		if message.find("already reviewed") >= 0: error = "This report was already reviewed. Refresh the list."
		emit_signal("completed", false, error)
	elif job.kind == "list" and data is Array:
		status = "ready"
		has_more = data.size() > 20
		rows = data.slice(0, 19) if has_more else data
	elif job.kind == "act":
		emit_signal("completed", true, "Moderation saved.")
		fetch(reviewed, before)
	emit_signal("changed")
