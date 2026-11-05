extends "user://mod/tools/social/SocialHub/01_placeholders.gd"

func _ready() -> void:
	layer = 154
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)


func configure(owner_tool) -> void:
	tas_tool = owner_tool
	_build_ui()
	call_deferred("_connect_social_modules")


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if _access_button != null and is_instance_valid(_access_button):
		_access_button.visible = false
	if not value:
		close_window()


func set_claude_experimental_icons_enabled(_value: bool) -> void:
	pass


func is_open() -> bool:
	return _modal_root != null and is_instance_valid(_modal_root) and _modal_root.visible


func open_window() -> void:
	if tas_tool != null and tas_tool.has_method("_open_module_page") and tas_tool._open_module_page("social"):
		return
	if _modal_root == null or not is_instance_valid(_modal_root):
		return
	_modal_root.visible = true
	_connect_social_modules()
	_repair_local_friend_code()
	_refresh_all()
	_refresh_friends_from_server()


func close_window() -> void:
	if _modal_root != null and is_instance_valid(_modal_root):
		_modal_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		close_window()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	if _modules_connected:
		return
	_retry_timer += delta
	if _retry_timer >= 1.0:
		_retry_timer = 0.0
		_connect_social_modules()


func _moonlight():
	return get_node_or_null("/root/Moonlight")


func _friends_module():
	var moonlight = _moonlight()
	if moonlight == null:
		return null
	return moonlight.get("friends")


func _party_module():
	var moonlight = _moonlight()
	if moonlight == null:
		return null
	return moonlight.get("party")


func _connect_social_modules() -> void:
	if _modules_connected:
		return
	var friends = _friends_module()
	var party = _party_module()
	if friends == null or party == null:
		return

	_connect_if_needed(friends, "query_friends_successful", "_on_social_data_changed")
	_connect_if_needed(friends, "query_friends_error", "_on_friends_query_error")
	_connect_if_needed(friends, "friend_status_changed", "_on_social_data_changed")
	_connect_if_needed(friends, "send_friend_request_complete", "_on_friend_request_complete")
	_connect_if_needed(friends, "local_friend_code_changed", "_on_social_data_changed")

	_connect_if_needed(party, "party_invites_changed", "_on_social_data_changed")
	_connect_if_needed(party, "party_members_changed", "_on_social_data_changed")
	_connect_if_needed(party, "party_id_changed", "_on_social_data_changed")
	_connect_if_needed(party, "party_member_data_changed", "_on_social_data_changed")
	_connect_if_needed(party, "party_leader_changed", "_on_social_data_changed")

	var moonlight = _moonlight()
	_connect_if_needed(moonlight, "on_authentication_succeeded", "_on_authentication_changed")
	_connect_if_needed(moonlight, "on_log_out", "_on_authentication_changed")
	_connect_if_needed(moonlight, "on_account_update", "_on_social_data_changed")
	_modules_connected = true
	_repair_local_friend_code()
	_refresh_all()


func _connect_if_needed(object, signal_name: String, method_name: String) -> void:
	if object == null or not object.has_signal(signal_name):
		return
	if not object.is_connected(signal_name, self, method_name):
		object.connect(signal_name, self, method_name)


func _on_authentication_changed() -> void:
	_repair_local_friend_code()
	_refresh_all()
	var moonlight = _moonlight()
	if moonlight != null and bool(moonlight.call("is_logged_in")):
		_refresh_friends_from_server()


func _on_social_data_changed(_a = null, _b = null, _c = null) -> void:
	_repair_local_friend_code()
	_refresh_all()


func _on_friends_query_error() -> void:
	_friend_query_failed = true
	var moonlight = _moonlight()
	if moonlight == null or not bool(moonlight.call("is_logged_in")):
		_set_status("Sign in to use Friends & Party.", true)
	elif moonlight.get("auth") != null and bool(moonlight.get("auth").call("is_guest_account")):
		_set_status("Link the guest account before using Friends & Party.", true)
	else:
		_set_status("The friends list could not be refreshed.", true)
	_refresh_all()


func _on_friend_request_complete(friend_code: String, _user_id: String, response: int) -> void:
	_busy = false
	_set_busy_controls(false)
	match response:
		0:
			_set_status("Friend request sent for code %s." % friend_code)
			if _friend_code_input != null:
				_friend_code_input.text = ""
		1:
			_set_status("The game could not resolve that code. Try the player's GP- code instead.", true)
		_:
			_set_status("The friend request failed.", true)
	_refresh_all()


func _repair_local_friend_code() -> String:
	var moonlight = _moonlight()
	if moonlight == null or not bool(moonlight.call("is_logged_in")):
		return ""
	var session = moonlight.get("session")
	if session == null:
		return ""
	# Public identity from the active session; never stale account storage.
	var user_id: String = _friend_code_user_id(str(session.get("user_id")))
	return "GP-" + user_id if not user_id.empty() else ""


func _friend_code_user_id(value: String) -> String:
	var code: String = value.strip_edges().to_lower()
	if code.begins_with("gp-"):
		code = code.substr(3)
	if code.length() != 36:
		return ""
	for i in range(36):
		if i in [8, 13, 18, 23]:
			if code[i] != "-":
				return ""
		elif "0123456789abcdef".find(code[i]) == -1:
			return ""
	if code == "00000000-0000-0000-0000-000000000000":
		return ""
	return code


func _build_ui() -> void:
	if tas_tool == null or not is_instance_valid(tas_tool):
		return

	# Friends & Party is opened exclusively through the main Workspace GUI.

	var root: = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)
	_modal_root = root

	var shade: = ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.76)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)

	var panel: = PanelContainer.new()
	panel.anchor_left = 0.07
	panel.anchor_top = 0.06
	panel.anchor_right = 0.93
	panel.anchor_bottom = 0.94
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_PANEL_BG, COLOR_PANEL_BORDER, 4, 24))
	root.add_child(panel)

	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)

	var column: = VBoxContainer.new()
	column.add_constant_override("separation", 12)
	margin.add_child(column)

	var header: = HBoxContainer.new()
	header.add_constant_override("separation", 12)
	column.add_child(header)
	var title: Label = _make_label("FRIENDS & PARTY", 34, COLOR_WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_refresh_button = _make_button("REFRESH", COLOR_BLUE, 150)
	_refresh_button.connect("pressed", self, "_refresh_friends_from_server")
	header.add_child(_refresh_button)
	var close_top: Button = _make_button("CLOSE", COLOR_PINK, 140)
	close_top.connect("pressed", self, "close_window")
	header.add_child(close_top)

	_status_label = _make_label("Connecting to social services…", 18, COLOR_TEXT_DIM)
	_status_label.autowrap = true
	column.add_child(_status_label)

	var account_row: = HBoxContainer.new()
	account_row.add_constant_override("separation", 10)
	column.add_child(account_row)
	_friend_code_label = _make_label("YOUR FRIEND CODE: loading…", 19, COLOR_WHITE)
	_friend_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_row.add_child(_friend_code_label)
	var copy_code: Button = _make_button("COPY CODE", COLOR_BLUE, 150)
	copy_code.connect("pressed", self, "_copy_friend_code")
	account_row.add_child(copy_code)

	var request_row: = HBoxContainer.new()
	request_row.add_constant_override("separation", 10)
	column.add_child(request_row)
	_friend_code_input = LineEdit.new()
	_friend_code_input.placeholder_text = "Enter a friend code"
	_friend_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_code_input.rect_min_size = Vector2(320, 52)
	_friend_code_input.add_font_override("font", tas_tool.call("_make_font", 19))
	_friend_code_input.connect("text_entered", self, "_on_friend_code_entered")
	request_row.add_child(_friend_code_input)
	var add_friend: Button = _make_button("SEND REQUEST", COLOR_GREEN, 210)
	add_friend.connect("pressed", self, "_send_friend_request")
	request_row.add_child(add_friend)

	var divider: = HSeparator.new()
	column.add_child(divider)

	var columns: = HBoxContainer.new()
	columns.add_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)

	var friends_card: VBoxContainer = _build_list_card(columns, "FRIENDS & REQUESTS")
	_friends_list = friends_card
	var party_card: VBoxContainer = _build_list_card(columns, "PARTY")
	_party_list = party_card

	_refresh_all()


func _build_list_card(parent: HBoxContainer, heading_text: String) -> VBoxContainer:
	var panel: = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", COLOR_CARD_BG, COLOR_PANEL_BORDER, 2, 16))
	parent.add_child(panel)
	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_%s" % side, 14)
	panel.add_child(margin)
	var box: = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_make_label(heading_text, 24, COLOR_WHITE))
	var scroll: = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.rect_min_size = Vector2(0, 410)
	box.add_child(scroll)
	var list: = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_constant_override("separation", 7)
	scroll.add_child(list)
	return list


func _make_label(text: String, size: int, color: Color) -> Label:
	return tas_tool.call("_make_label", text, tas_tool.call("_make_font", size), color) as Label


func _make_button(text: String, color: Color, width: int) -> Button:
	return tas_tool.call("_make_button", text, color, width) as Button


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _refresh_all() -> void:
	if _friend_code_label == null:
		return
	var code: = _repair_local_friend_code()
	_friend_code_label.text = "YOUR FRIEND CODE: %s" % (code if not code.empty() else "not available")
	_refresh_friends_list()
	_refresh_party_list()
	_refresh_access_badge()
	var moonlight = _moonlight()
	if moonlight == null or not bool(moonlight.call("is_logged_in")):
		_set_status("Sign in to use Friends & Party.", true)
	elif moonlight.get("auth") != null and bool(moonlight.get("auth").call("is_guest_account")):
		_set_status("Link the guest account before using Friends & Party.", true)
	elif not _busy and _status_label.text == "Connecting to social services…":
		_set_status("Social services connected.")


func _refresh_access_badge() -> void:
	if _access_button == null:
		return
	var count: = 0
	var friends = _friends_module()
	if friends != null:
		var records = friends.get("friend_list_unfiltered")
		if records is Array:
			for entry in records:
				if entry != null and int(entry.get("state")) == REQUEST_RECEIVED:
					count += 1
	var party = _party_module()
	if party != null:
		var invites = party.get("party_invites")
		if invites is Dictionary:
			count += invites.size()
	_access_button.text = "👥  FRIENDS & PARTY%s" % ("  (%d)" % count if count > 0 else "")


func _refresh_friends_list() -> void:
	_clear_list(_friends_list)
	if _friends_list == null:
		return
	var friends = _friends_module()
	if friends == null:
		_friends_list.add_child(_make_label("Friends module is not ready.", 17, COLOR_TEXT_DIM))
		return
	var records = friends.get("friend_list_unfiltered")
	if not (records is Array) or records.empty():
		_friends_list.add_child(_make_label("No friends or pending requests yet.", 17, COLOR_TEXT_DIM))
		return
	for entry in records:
		_add_friend_row(entry, friends)


func _add_friend_row(entry, friends) -> void:
	if entry == null:
		return
	var user = entry.get("user")
	if user == null:
		return
	var user_id: = str(user.get("id"))
	var display_name: = str(user.get("display_name")).strip_edges()
	if display_name.empty():
		display_name = str(user.get("username")).strip_edges()
	if display_name.empty():
		display_name = user_id.left(12)
	var state: = int(entry.get("state"))

	var panel: = PanelContainer.new()
	panel.add_stylebox_override("panel", tas_tool.call("_make_flat_style", Color(0.02, 0.12, 0.23, 0.72), Color(1, 1, 1, 0.18), 1, 10))
	_friends_list.add_child(panel)
	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 7)
	panel.add_child(row)
	var label_text: = display_name
	match state:
		FRIENDS:
			var statuses = friends.get("friend_statuses")
			var online: bool = statuses is Dictionary and statuses.has(user_id)
			var presence: = str(statuses.get(user_id, "")) if online else ""
			label_text += "\n%s%s" % ["ONLINE" if online else "offline", " · " + presence if not presence.empty() else ""]
		REQUEST_SENT:
			label_text += "\nrequest sent"
		REQUEST_RECEIVED:
			label_text += "\nwants to be friends"
		BLOCKED:
			label_text += "\nblocked"
	var name_label: Label = _make_label(label_text, 17, COLOR_WHITE if state != REQUEST_RECEIVED else COLOR_ORANGE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap = true
	row.add_child(name_label)

	match state:
		FRIENDS:
			var invite: Button = _make_button("INVITE", COLOR_GREEN, 105)
			invite.connect("pressed", self, "_invite_friend_to_party", [user_id, display_name])
			row.add_child(invite)
			var remove: Button = _make_button("REMOVE", COLOR_PINK, 110)
			remove.connect("pressed", self, "_remove_friend", [user_id, display_name])
			row.add_child(remove)
		REQUEST_RECEIVED:
			var accept: Button = _make_button("ACCEPT", COLOR_GREEN, 110)
			accept.connect("pressed", self, "_accept_friend_request", [user_id, display_name])
			row.add_child(accept)
			var decline: Button = _make_button("DECLINE", COLOR_PINK, 115)
			decline.connect("pressed", self, "_remove_friend", [user_id, display_name])
			row.add_child(decline)
		REQUEST_SENT:
			var cancel: Button = _make_button("CANCEL", COLOR_PINK, 105)
			cancel.connect("pressed", self, "_remove_friend", [user_id, display_name])
			row.add_child(cancel)
		BLOCKED:
			var unblock: Button = _make_button("UNBLOCK", COLOR_BLUE, 120)
			unblock.connect("pressed", self, "_remove_friend", [user_id, display_name])
			row.add_child(unblock)
