extends Moonlight_AuthBase

# Keep the game's authenticator for its original account, but never fall back
# to Steam/main saved credentials after a managed account has been selected.
var original
var manager
var managed = false
var signed_out = false

func authenticate(signal_on_success = true):
	if manager == null or not is_instance_valid(manager):
		last_authentication_time = OS.get_unix_time()
		return
	if is_attempting_authentication or signed_out:
		return
	if managed:
		if manager.resume_failed:
			last_authentication_time = OS.get_unix_time()
			return
		var pending = manager.refresh_session(signal_on_success)
		if pending is GDScriptFunctionState:
			yield(pending,"completed")
		return
	is_attempting_authentication = true
	var result = original.authenticate(false)
	if result is GDScriptFunctionState:
		yield(result,"completed")
	is_attempting_authentication = false
	last_authentication_time = original.last_authentication_time
	if signal_on_success and original.is_logged_in():
		Moonlight.emit_signal("on_authentication_succeeded")

func log_out():
	if manager == null or not is_instance_valid(manager) or manager.busy:
		return
	manager.local_sign_out()

func is_logged_in():
	return not is_attempting_authentication and not signed_out and Moonlight.session != null and not Moonlight.session.is_expired() and original.is_logged_in()

func is_guest_account():
	return original.is_guest_account()

func is_platform_auth_supported():
	return original.is_platform_auth_supported()

func is_account_linked_to_platform():
	return original.is_account_linked_to_platform()

func is_account_linked_to_email():
	return original.is_account_linked_to_email()
