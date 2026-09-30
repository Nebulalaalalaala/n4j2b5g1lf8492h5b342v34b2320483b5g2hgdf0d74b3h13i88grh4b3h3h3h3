extends "user://mod/tools/social/SocialHub/02_friends_friend.gd"

func _refresh_party_list() -> void:
	_clear_list(_party_list)
	if _party_list == null:
		return
	var party = _party_module()
	if party == null:
		_party_list.add_child(_make_label("Party module is not ready.", 17, COLOR_TEXT_DIM))
		return

	var invites = party.get("party_invites")
	if invites is Dictionary and not invites.empty():
		_party_list.add_child(_make_label("PARTY INVITES", 19, COLOR_ORANGE))
		for inviter_id in invites:
			var invite_data: Dictionary = invites[inviter_id]
			_add_party_invite_row(inviter_id, invite_data)
		_party_list.add_child(HSeparator.new())

	if not bool(party.call("is_in_party")):
		_party_list.add_child(_make_label("You are not in a party.", 18, COLOR_TEXT_DIM))
		var create: Button = _make_button("CREATE PARTY", COLOR_GREEN, 220)
		create.connect("pressed", self, "_create_party")
		_party_list.add_child(create)
		_party_list.add_child(_make_label("Create a squad, invite friends, then use the normal PLAY button. Goober Dash's matchmaker will queue the squad together.", 16, COLOR_TEXT_DIM))
		return

	var members = party.get("party_members")
	var member_count: int = members.size() if members is Dictionary else 0
	var leader_text: = "leader" if bool(party.get("is_leader")) else "member"
	_party_list.add_child(_make_label("ACTIVE PARTY · %d/%d · %s" % [member_count, DEFAULT_PARTY_SIZE, leader_text], 19, COLOR_GREEN))
	var leave: Button = _make_button("LEAVE PARTY", COLOR_PINK, 190)
	leave.connect("pressed", self, "_leave_party")
	_party_list.add_child(leave)

	if members is Dictionary:
		var member_data_all = party.get("party_member_data")
		for user_id in members:
			var member: Dictionary = members[user_id]
			var live_data: Dictionary = member_data_all.get(user_id, {}) if member_data_all is Dictionary else {}
			_add_party_member_row(user_id, member, live_data, bool(party.get("is_leader")))


func _add_party_invite_row(inviter_id: String, data: Dictionary) -> void:
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 7)
	_party_list.add_child(row)
	var display_name: = str(data.get("display_name", inviter_id.left(12)))
	var label: Label = _make_label("%s invited you" % display_name, 17, COLOR_WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var accept: Button = _make_button("JOIN", COLOR_GREEN, 100)
	accept.connect("pressed", self, "_accept_party_invite", [inviter_id, str(data.get("party_id", "")), display_name])
	row.add_child(accept)
	var deny: Button = _make_button("IGNORE", COLOR_PINK, 105)
	deny.connect("pressed", self, "_deny_party_invite", [inviter_id, str(data.get("party_id", ""))])
	row.add_child(deny)


func _add_party_member_row(user_id: String, member: Dictionary, live_data: Dictionary, local_is_leader: bool) -> void:
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 7)
	_party_list.add_child(row)
	var name: = str(member.get("display_name", user_id.left(12)))
	var details: = []
	if bool(member.get("is_leader", false)):
		details.append("leader")
	if bool(member.get("is_self", false)):
		details.append("you")
	var status: = str(live_data.get("status", "")).strip_edges()
	if not status.empty():
		details.append(status.replace("_", " "))
	var suffix: = " · " + PoolStringArray(details).join(" · ") if not details.empty() else ""
	var label: Label = _make_label(name + suffix, 17, COLOR_WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if local_is_leader and not bool(member.get("is_self", false)):
		var kick: Button = _make_button("KICK", COLOR_PINK, 90)
		kick.connect("pressed", self, "_kick_party_member", [user_id, name])
		row.add_child(kick)


func _set_status(text: String, is_error: bool = false) -> void:
	if _status_label != null:
		_status_label.text = text
		_status_label.add_color_override("font_color", COLOR_PINK if is_error else COLOR_TEXT_DIM)
	if tas_tool != null and is_instance_valid(tas_tool):
		tas_tool.call("_log_action", "Social: " + text, null)


func _set_busy_controls(value: bool) -> void:
	if _refresh_button != null:
		_refresh_button.disabled = value
	if _friend_code_input != null:
		_friend_code_input.editable = not value


func _begin_action(message: String) -> bool:
	if _busy:
		_set_status("Another social action is still in progress.", true)
		return false
	var moonlight = _moonlight()
	if moonlight == null or not bool(moonlight.call("is_logged_in")) or moonlight.get("auth") == null or bool(moonlight.get("auth").call("is_guest_account")):
		_set_status("Sign in with a linked account first.", true)
		return false
	_busy = true
	_set_busy_controls(true)
	_set_status(message)
	return true


func _finish_action(message: String, failed: bool = false) -> void:
	_busy = false
	_set_busy_controls(false)
	_set_status(message, failed)
	_refresh_all()


func _refresh_friends_from_server() -> void:
	var friends = _friends_module()
	if friends == null:
		_set_status("Friends module is not ready.", true)
		return
	if not _begin_action("Refreshing friends…"):
		return
	_friend_query_failed = false
	var result = friends.call("query_friends_list")
	if result is GDScriptFunctionState:
		yield(result, "completed")
	if _friend_query_failed:
		_finish_action("The friends list could not be refreshed.", true)
	else:
		_finish_action("Friends and presence refreshed.")


func _copy_friend_code() -> void:
	var code: = _repair_local_friend_code()
	if code.empty():
		_set_status("No friend code was returned for this account.", true)
		return
	OS.clipboard = code
	_set_status("Friend code copied to the clipboard.")


func _on_friend_code_entered(_text: String) -> void:
	_send_friend_request()


func _send_friend_request() -> void:
	var friends = _friends_module()
	if friends == null:
		_set_status("Friends module is not ready.", true)
		return
	var code: = _friend_code_input.text.strip_edges() if _friend_code_input != null else ""
	if code.empty():
		_set_status("Enter a friend code first.", true)
		return
	if not _begin_action("Sending friend request…"):
		return
	var result = friends.call("send_friend_request", code)
	if result is GDScriptFunctionState:
		yield(result, "completed")
	# The module normally finishes through send_friend_request_complete. Keep a
	# fallback for server versions which return without emitting that signal.
	if _busy:
		_finish_action("Friend request finished.")


func _accept_friend_request(user_id: String, display_name: String) -> void:
	var friends = _friends_module()
	if friends == null or not _begin_action("Accepting %s…" % display_name):
		return
	var result = friends.call("add_friend", user_id)
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	_finish_action("%s is now your friend." % display_name, result == false)


func _remove_friend(user_id: String, display_name: String) -> void:
	var friends = _friends_module()
	if friends == null or not _begin_action("Updating %s…" % display_name):
		return
	var result = friends.call("delete_friend", user_id)
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	_finish_action("Friend entry for %s removed." % display_name, result == false)


func _create_party() -> void:
	var party = _party_module()
	if party == null or not _begin_action("Creating party…"):
		return
	var result = party.call("create_party", DEFAULT_PARTY_SIZE)
	if result is GDScriptFunctionState:
		yield(result, "completed")
	var ok: = bool(party.call("is_in_party"))
	_finish_action("Party created. Invite friends, then press PLAY." if ok else "Party creation failed.", not ok)


func _leave_party() -> void:
	var party = _party_module()
	if party == null or not _begin_action("Leaving party…"):
		return
	var result = party.call("leave_party")
	if result is GDScriptFunctionState:
		yield(result, "completed")
	var failed: = bool(party.call("is_in_party"))
	_finish_action("Could not leave the party." if failed else "Left the party.", failed)


func _invite_friend_to_party(user_id: String, display_name: String) -> void:
	var party = _party_module()
	if party == null or not _begin_action("Preparing invite for %s…" % display_name):
		return
	if not bool(party.call("is_in_party")):
		var create_result = party.call("create_party", DEFAULT_PARTY_SIZE)
		if create_result is GDScriptFunctionState:
			yield(create_result, "completed")
	if not bool(party.call("is_in_party")):
		_finish_action("Could not create a party.", true)
		return
	if not bool(party.get("is_leader")):
		_finish_action("Only the party leader can send invites.", true)
		return
	var result = party.call("invite_player_to_party", user_id)
	if result is GDScriptFunctionState:
		yield(result, "completed")
	_finish_action("Party invite sent to %s." % display_name)


func _accept_party_invite(inviter_id: String, party_id: String, display_name: String) -> void:
	var party = _party_module()
	if party == null:
		return
	if bool(party.call("is_in_party")):
		_set_status("Leave your current party before joining another one.", true)
		return
	if party_id.empty() or not _begin_action("Joining %s's party…" % display_name):
		return
	var result = party.call("accept_invite_to_party", inviter_id, party_id)
	if result is GDScriptFunctionState:
		yield(result, "completed")
	var ok: = bool(party.call("is_in_party"))
	_finish_action("Joined %s's party." % display_name if ok else "Could not join that party.", not ok)


func _deny_party_invite(inviter_id: String, party_id: String) -> void:
	var party = _party_module()
	if party == null:
		return
	party.call("deny_invite_to_party", inviter_id, party_id)
	_set_status("Party invite ignored.")
	_refresh_all()


func _kick_party_member(user_id: String, display_name: String) -> void:
	var party = _party_module()
	if party == null or not _begin_action("Removing %s from the party…" % display_name):
		return
	var result = party.call("remove_player_from_party", user_id)
	if result is GDScriptFunctionState:
		yield(result, "completed")
	_finish_action("Removed %s from the party." % display_name)
