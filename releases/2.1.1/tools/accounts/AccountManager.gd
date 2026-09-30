extends Node

signal changed()
var store
var backend
var proxy
var owner_access
var view
var busy = false
var status = ""
var startup_restored = false
var desired_startup = ""
var expected_login = ""
var resume_failed = false
var protected_session_hash = ""
var remember_login = false

func _ready():
	if store != null:
		return
	var base = get_script().resource_path.get_base_dir()
	store = load(base.plus_file("AccountStore.gd")).new()
	store.load_records()
	desired_startup = store.active_id
	backend = load(base.plus_file("AccountBackend.gd")).new()
	Moonlight.connect("on_authentication_succeeded",self,"authenticated")
	call_deferred("authenticated")

func tool():
	return owner_access.get_parent().tas_tool if owner_access != null else null

func can_switch():
	if busy or Moonlight.auth.is_attempting_authentication:
		return false
	var scene = get_tree().current_scene
	return scene != null and scene.filename in ["res://scenes/HomeScene.tscn","res://scenes/ConnectingScene.tscn"] and (Moonlight.party == null or Moonlight.party.party_id.empty())

func attach_proxy():
	if proxy != null:
		return
	if Moonlight.auth.get_script().resource_path == get_script().resource_path.get_base_dir().plus_file("AccountAuthProxy.gd"):
		proxy = Moonlight.auth
		proxy.manager = self
		return
	proxy = load(get_script().resource_path.get_base_dir().plus_file("AccountAuthProxy.gd")).new()
	proxy.original = Moonlight.auth
	proxy.manager = self
	proxy.last_authentication_time = Moonlight.auth.last_authentication_time
	Moonlight.auth = proxy

func authenticated():
	if busy or not Moonlight.is_logged_in():
		return
	attach_proxy()
	if cache_current():
		store.find(current_id()).last_used = OS.get_unix_time()
		store.save()
	if not startup_restored:
		startup_restored = true
		if not desired_startup.empty() and desired_startup != current_id():
			call_deferred("restore_when_home")

func restore_when_home():
	for _attempt in 30:
		if can_switch():
			switch_account(desired_startup)
			return
		yield(get_tree().create_timer(1.0),"timeout")
	status = "Saved account can be restored from Accounts when you return home."
	emit_signal("changed")

func current_id():
	return Moonlight.session.user_id if Moonlight.session != null and Moonlight.session.is_valid() else ""

func is_current_usable(id):
	return id == current_id() and Moonlight.is_logged_in()

func cache_current():
	if not Moonlight.is_logged_in() or Moonlight.local_account == null or Moonlight.local_account.user.id != current_id():
		return false
	var digest = Moonlight.session.token.sha256_text()
	if digest != protected_session_hash:
		if not store.save_session(Moonlight.session):
			status = "Session could not be protected; your current account is unchanged."
			return false
		protected_session_hash = digest
	var user = Moonlight.local_account.user
	var name = user.display_name if not user.display_name.empty() else user.username
	var previous = store.find(current_id())
	var stamp = OS.get_unix_time() if previous.empty() else previous.last_used
	return store.upsert(current_id(),name,Moonlight.storage.storage_get("player.profile.level",1),Moonlight.storage.storage_get("player.profile.skin",{}),stamp)

func open():
	if view == null:
		view = load(get_script().resource_path.get_base_dir().plus_file("AccountManagerView.gd")).new()
		view.manager = self
		add_child(view)
	if not store.unchanged_on_disk():
		store.load_records()
	cache_current()
	view.open()

func fail(message):
	busy = false
	if proxy != null:
		proxy.is_attempting_authentication = false
	status = message
	emit_signal("changed")

func switch_account(id):
	if id == current_id() and Moonlight.is_logged_in():
		return
	if not can_switch():
		status = "Return to the home screen and leave your party before switching."
		emit_signal("changed")
		return
	attach_proxy()
	busy = true
	proxy.is_attempting_authentication = true
	status = "Checking saved session…"
	emit_signal("changed")
	var session = store.session_for(id)
	if session==null or (session.would_expire_in(60) and (session.refresh_token.empty() or session.is_refresh_expired())):
		var saved_login = store.vault("Get",id)
		if saved_login.get("email","") is String and saved_login.get("password","") is String and not str(saved_login.get("password","")).empty():
			var request = backend.email_session(saved_login.email,saved_login.password)
			saved_login.clear()
			session = yield(request,"completed") if request is GDScriptFunctionState else request
			if session==null or session.is_exception() or not session.is_valid() or session.user_id!=id:
				signin_required(id)
				return
		else:
			saved_login.clear()
			signin_required(id)
			return
	if session == null:
		signin_required(id)
		return
	var pending = activate(session,id)
	if pending is GDScriptFunctionState:
		yield(pending,"completed")

func signin_required(id):
	var record = store.find(id)
	if not record.empty():
		record.signin_required = true
		store.save()
	fail("Sign in required. Your previous account is still active.")
	open_login(id)

func activate(session,expected):
	if not store.can_add(expected):
		fail("Account list is full, changed elsewhere, or unavailable. Reopen Accounts to refresh.")
		return false
	var prepared = backend.prepare(session)
	if prepared is GDScriptFunctionState:
		prepared = yield(prepared,"completed")
	if prepared.has("error"):
		if prepared.error == "signin_required":
			signin_required(expected)
		else:
			fail("Could not switch account. Your previous account is unchanged.")
		return false
	if prepared.session.user_id != expected:
		backend.discard(prepared)
		fail("Different account returned. Switch cancelled.")
		return false
	if not store.save_session(prepared.session):
		backend.discard(prepared)
		fail("Could not protect the session. Switch cancelled.")
		return false
	var drained = backend.drain(get_tree())
	if drained is GDScriptFunctionState:
		drained = yield(drained,"completed")
	if not drained:
		backend.discard(prepared)
		fail("Another account request is still running. Try again shortly.")
		return false
	var previous_id = current_id()
	if not backend.commit(prepared):
		backend.discard(prepared)
		fail("Could not switch account. Try again.")
		return false
	complete_switch(previous_id,expected)
	return true

func complete_switch(previous_id,expected):
	proxy.managed = true
	proxy.signed_out = false
	proxy.is_attempting_authentication = false
	proxy.last_authentication_time = OS.get_unix_time()
	store.active_id = expected
	protected_session_hash = Moonlight.session.token.sha256_text()
	var user = Moonlight.local_account.user
	var saved = store.upsert(expected,user.display_name if not user.display_name.empty() else user.username,Moonlight.storage.storage_get("player.profile.level",1),Moonlight.storage.storage_get("player.profile.skin",{}),OS.get_unix_time())
	refresh_local_tools(previous_id,expected)
	Moonlight.emit_signal("on_authentication_succeeded")
	busy = false
	resume_failed = false
	status = "Switched to " + str(store.find(expected).get("name","account"))
	if not saved:
		status = "Account switched, but its local profile could not be saved. Check storage."
	# Rebuild account-bound native UI, while keeping the mod and device settings.
	get_tree().call_deferred("change_scene","res://scenes/HomeScene.tscn")
	emit_signal("changed")

func refresh_local_tools(previous,id):
	var tas = tool()
	if tas == null:
		return
	var sandbox = tas.get("_cosmetic_sandbox")
	if is_instance_valid(sandbox) and sandbox._studio != null:
		var studio = sandbox._studio
		var old = store.find(previous)
		if not old.empty():
			old.draft = studio.capture()
		studio.close()
		studio.history.clear()
		studio.future.clear()
		var draft = store.find(id).get("draft",{})
		studio._restore(draft if not draft.empty() else {"base":true,"enabled":false})
		studio.changed()
		store.save()
	var social = tas.get("_social_hub")
	if is_instance_valid(social):
		social._modules_connected = false
		social._connect_social_modules()

func refresh_session(signal_on_success):
	if busy or resume_failed or Moonlight.session == null:
		return
	busy = true
	proxy.is_attempting_authentication = true
	# Refresh uses only the selected session, never main-account/Steam credentials.
	var client = backend.create_client()
	var before = Moonlight.session
	if before.refresh_token.empty() or before.is_refresh_expired():
		resume_failed = true
		fail("Session expired. Open Accounts to sign in again.")
		return
	var session = yield(client.session_refresh_async(before),"completed")
	if session == null or session.is_exception() or not session.is_valid() or session.user_id != before.user_id:
		resume_failed = true
		fail("Session refresh failed. Open Accounts to retry.")
		return
	Moonlight.session = session
	store.save_session(session)
	if Moonlight.socket == null or not Moonlight.socket.is_connected_to_host():
		var reconnected = proxy._post_auth()
		if reconnected is GDScriptFunctionState:
			reconnected = yield(reconnected,"completed")
		if not reconnected:
			resume_failed = true
			fail("Connection failed. Open Accounts to retry this account.")
			return
	proxy.last_authentication_time = OS.get_unix_time()
	proxy.is_attempting_authentication = false
	busy = false
	if signal_on_success:
		Moonlight.emit_signal("on_authentication_succeeded")

func open_login(expected = ""):
	if not can_switch():
		status = "Return home and leave your party before signing in."
		emit_signal("changed")
		return
	attach_proxy()
	expected_login = expected
	var dialog = make_login_dialog()
	get_tree().current_scene.add_child(dialog)
	if view != null:
		view.close()

func make_login_dialog():
	var dialog = load("res://goodoh/ui/nodes/UISigninEmailDialog.tscn").instance()
	var form = dialog.find_node("EmailSigninForm",true,false)
	var paths = {}
	for property in form.get_property_list():
		if property.type == TYPE_NODE_PATH:
			paths[property.name] = form.get(property.name)
	form.set_script(load(get_script().resource_path.get_base_dir().plus_file("AccountSigninForm.gd")))
	for key in paths:
		form.set(key,paths[key])
	form.manager = self
	return dialog

func sign_in(email,password):
	if not can_switch():
		return false
	busy = true
	proxy.is_attempting_authentication = true
	var session = yield(backend.email_session(email,password),"completed")
	if session == null or session.is_exception() or not session.is_valid():
		fail("Sign-in failed. No account was changed or created.")
		return false
	if not expected_login.empty() and session.user_id != expected_login:
		fail("That is a different account. Use Add account to save it separately.")
		return false
	var result = activate(session,session.user_id)
	if result is GDScriptFunctionState:
		result = yield(result,"completed")
	if result:
		if not store.save_login(session.user_id,email if remember_login else "",password if remember_login else ""):
			status = "Signed in, but Remember login could not be saved securely."
			emit_signal("changed")
	password = ""
	return result

func local_sign_out():
	if busy:
		return
	cache_current()
	proxy.signed_out = true
	proxy.managed = true
	store.active_id = ""
	store.save()
	Moonlight.session = null
	Moonlight.local_account = null
	Moonlight.socket.close()
	Moonlight.storage._storage_clear()
	Moonlight.emit_signal("on_log_out")
	status = "Signed out locally. Saved accounts remain available."
	emit_signal("changed")

func _exit_tree():
	if proxy != null and proxy.get("manager") == self:
		proxy.manager = null
