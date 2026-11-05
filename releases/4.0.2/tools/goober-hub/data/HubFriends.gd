extends Node
# Native friendships only. Hub keys never create or accept friendships.
signal changed
signal notice(message)
const FRIENDS = 0
const SENT = 1
const INCOMING = 2
var hub
var rows = []
var busy = false
var refreshing = false
var loaded = false
var error = ""
var _owner = ""
var _module_ref
var _fetched = 0
var _code_result = -1
var _active_code = ""

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(false)

func _moonlight(): return get_node_or_null("/root/Moonlight")

func _module():
	var moon = _moonlight()
	return moon.get("friends") if moon != null else null

func sync(owner):
	if str(owner) != _owner:
		_owner = str(owner)
		rows = []
		loaded = false
		busy = false
		refreshing = false
		error = ""
		_fetched = 0
		_active_code = ""
		emit_signal("changed")
	var source = _module()
	if source != _module_ref:
		_disconnect()
		_module_ref = source
		if source != null:
			if source.has_signal("query_friends_successful"): source.connect("query_friends_successful", self, "_native_changed")
			if source.has_signal("friend_status_changed"): source.connect("friend_status_changed", self, "_presence_changed")
			if source.has_signal("send_friend_request_complete"):
				source.connect("send_friend_request_complete", self, "_code_done")
	if not loaded and source != null:
		_capture(source.get("friend_list_unfiltered"))

func _disconnect():
	if not is_instance_valid(_module_ref): return
	if _module_ref.is_connected("query_friends_successful", self, "_native_changed"): _module_ref.disconnect("query_friends_successful", self, "_native_changed")
	if _module_ref.is_connected("friend_status_changed", self, "_presence_changed"): _module_ref.disconnect("friend_status_changed", self, "_presence_changed")
	if _module_ref.is_connected("send_friend_request_complete", self, "_code_done"):
		_module_ref.disconnect("send_friend_request_complete", self, "_code_done")

func _exit_tree(): _disconnect()

func _native_changed(_a = null, _b = null, _c = null):
	if hub.account() != _owner: return
	if not loaded and not refreshing: _capture(_module_ref.get("friend_list_unfiltered"))
	emit_signal("changed")
	if hub.is_interface_open() and hub.screen.page in ["Profile", "Messages"]:
		refresh(true)

func _presence_changed(_id, _online, _status):
	if hub.account() == _owner: emit_signal("changed")

func _capture(entries):
	if not entries is Array: return
	var found = []
	for entry in entries:
		var user = entry.get("user") if entry != null else null
		if user == null: continue
		var id = str(user.get("id"))
		var name = str(user.get("display_name")).strip_edges()
		if name.empty(): name = str(user.get("username")).strip_edges()
		found.append({"id": id, "name": name if not name.empty() else id.left(12), "state": int(entry.get("state"))})
		if hub.profiles != null: hub.profiles.remember(id, name)
	rows = found

func state_for(id) -> int:
	for row in rows:
		if row.id == str(id): return int(row.state)
	return -1

func requests(state = INCOMING) -> Array:
	var out = []
	for row in rows:
		if int(row.state) == state: out.append(row.duplicate())
	return out

func accepted() -> Array:
	var out = requests(FRIENDS)
	var source = _module()
	var statuses = source.get("friend_statuses") if source != null else {}
	for row in out:
		row.online = statuses is Dictionary and statuses.has(row.id)
		row.status = str(statuses.get(row.id, "")) if row.online else ""
	return out

func _can_act() -> bool:
	var moon = _moonlight()
	return moon != null and moon.call("is_logged_in") and moon.get("auth") != null and not moon.auth.call("is_guest_account") and hub.account() == _owner and not _owner.empty()

func refresh(force = false):
	if refreshing or not _can_act() or OS.get_unix_time() - _fetched < (2 if force else 60): return
	var moon = _moonlight()
	var owner = _owner
	var session = moon.session
	var cursor = ""
	var seen = {}
	var entries = []
	refreshing = true
	error = ""
	emit_signal("changed")
	# Native query_friends_list stops after its first page. Walk the cursor so
	# requests are not hidden behind a large existing friend list.
	for _page in range(100):
		var result = moon.client.list_friends_async(session, null, 100, cursor if not cursor.empty() else null)
		if result is GDScriptFunctionState: result = yield(result, "completed")
		if hub.account() != owner or _owner != owner: return
		if result == null or result.is_exception():
			error = "Couldn't refresh friends. Try again."
			break
		entries.append_array(result.friends)
		cursor = str(result.cursor) if result.cursor != null else ""
		if cursor.empty():
			_capture(entries)
			loaded = true
			break
		if seen.has(cursor):
			error = "The friends list returned a repeated page. Try refreshing."
			break
		seen[cursor] = true
	if not cursor.empty() and error.empty(): error = "The friends list is too large to load in one refresh."
	refreshing = false
	_fetched = OS.get_unix_time()
	emit_signal("changed")

static func user_id(value) -> String:
	var id = str(value).strip_edges().to_lower()
	if id.begins_with("gp-"): id = id.substr(3)
	if id.length() != 36: return ""
	for i in range(36):
		if i in [8, 13, 18, 23]:
			if id[i] != "-": return ""
		elif "0123456789abcdef".find(id[i]) < 0: return ""
	return "" if id == "00000000-0000-0000-0000-000000000000" else id

func add(value):
	var code = str(value).strip_edges()
	var id = user_id(code)
	if code.empty(): return emit_signal("notice", "Enter a friend code or player ID.")
	if code.to_lower().begins_with("gp-") and id.empty(): return emit_signal("notice", "Copy the complete GP- friend code.")
	if id == _owner: return emit_signal("notice", "That's your own friend code.")
	if id == hub.TEST_ID: return emit_signal("notice", "The test account is not a real player.")
	if not id.empty() and state_for(id) == FRIENDS: return emit_signal("notice", "You're already friends.")
	if not id.empty() and state_for(id) == SENT: return emit_signal("notice", "A request is already pending.")
	if not id.empty() and state_for(id) == INCOMING: return act(id, "accept")
	if not _begin(): return
	var owner = _owner
	var source = _module()
	var result
	if not id.empty():
		result = source.add_friend(id)
		if result is GDScriptFunctionState: result = yield(result, "completed")
	else:
		_active_code = code
		_code_result = -1
		result = source.send_friend_request(code)
		if result is GDScriptFunctionState: yield(result, "completed")
		result = _code_result == 0
		_active_code = ""
	if hub.account() != owner or _owner != owner: return
	_finish(result == true, "Friend request sent.")

func act(id, action):
	var state = state_for(id)
	if (action == "accept" and state != INCOMING) or (action == "decline" and state != INCOMING) or (action == "cancel" and state != SENT): return
	if not action in ["accept", "decline", "cancel"] or not _begin(): return
	var owner = _owner
	var source = _module()
	var result = source.add_friend(str(id)) if action == "accept" else source.delete_friend(str(id))
	if result is GDScriptFunctionState: result = yield(result, "completed")
	if hub.account() != owner or _owner != owner: return
	_finish(result == true, {"accept": "Friend request accepted.", "decline": "Friend request declined.", "cancel": "Request cancelled."}[action])

func _begin() -> bool:
	if busy:
		emit_signal("notice", "Wait for the current friend request.")
		return false
	if _module() == null or not _can_act():
		emit_signal("notice", "Sign in with a linked GooberDash account to add friends.")
		return false
	busy = true
	emit_signal("changed")
	return true

func _finish(ok, message):
	busy = false
	if ok:
		loaded = false
		_capture(_module().get("friend_list_unfiltered"))
		_fetched = 0
		refresh(true)
	emit_signal("notice", message if ok else "The game server didn't confirm that request. Check the code and try again.")
	emit_signal("changed")

func _code_done(code, _id, response):
	if str(code) == _active_code and hub.account() == _owner: _code_result = int(response)
