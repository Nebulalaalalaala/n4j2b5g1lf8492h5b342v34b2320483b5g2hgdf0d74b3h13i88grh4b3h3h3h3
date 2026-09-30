extends "user://mod/tools/match-info/TASTool/15_leaderboard_search.gd"

# ----------------------------------------------------------------------
#  Custom Lobby -- host with your own code
# ----------------------------------------------------------------------
# The Custom Lobby screen's own CREATE LOBBY button always generates a random
# code (Moonlight.lobby.create_lobby()). The client already ships a second,
# fully-supported path for a chosen code though -- join_or_create_preset_lobby()
# -- it's just never wired to any button; the only place it's actually used
# is the Discord activity join flow (Moonlight_JoinDiscordLobbyButton.gd),
# which derives its code from the Discord instance ID instead of asking a
# player to type one. This adds a button that calls that same function with
# whatever the player types: if a lobby with that code already exists it
# joins it (matching the normal join-by-code behavior everyone already
# uses), otherwise it hosts a brand new one under that code. No new or
# restricted server call -- same RPCs as the native CREATE LOBBY and
# JOIN LOBBY buttons, just combined and given a player-chosen code.
func _inject_custom_lobby_code_button(scene: Node) -> void:
	if not _custom_lobby_code_enabled:
		return
	if not is_instance_valid(scene) or not scene.has_method("on_create_lobby_button_pressed"):
		return
	# "Create" itself is a Panel, NOT a layout container -- its children are
	# placed by absolute margins plus the game's own GoodAnchorPoint helpers.
	# A row added straight to it lands at (0,0) sized to nothing but its own
	# minimum, which collapsed the LineEdit (minimum width 0) to zero pixels
	# and made it impossible to click into or type in. The description
	# VBoxContainer inside that panel IS a real container at a fixed 800px
	# wide, so the row goes there instead: laid out properly, directly under
	# the "Create a new private lobby" text and above the CREATE LOBBY button.
	var create_container: Control = scene.get_node_or_null("SafeArea/MarginContainer/CreateOrJoin/Create/VBoxContainer") as Control
	if create_container == null or create_container.has_node("GoobplayabilityCustomLobbyCode"):
		return

	# That VBoxContainer separates its children by 50px. Adding the input row
	# and the status line as two separate children would spend that gap twice
	# and push the block down into the CREATE LOBBY button underneath it, so
	# they go inside one tightly-spaced sub-container that costs the 50px once.
	var block: = VBoxContainer.new()
	block.name = "GoobplayabilityCustomLobbyCode"
	block.add_constant_override("separation", 6)
	create_container.add_child(block)

	var row: = HBoxContainer.new()
	row.name = "CustomCodeRow"
	row.add_constant_override("separation", 12)
	block.add_child(row)

	var field: = LineEdit.new()
	field.name = "CustomCodeField"
	field.placeholder_text = "Host with your own code..."
	field.max_length = 24
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Real minimum width, not 0 -- SIZE_EXPAND_FILL only hands out space left
	# over above the minimums, so a 0-minimum field collapses to nothing the
	# moment its row isn't being stretched by something.
	field.rect_min_size = Vector2(320, BUTTON_H)
	field.add_stylebox_override("normal", _make_flat_style(COLOR_PANEL_BG, COLOR_BLUE, 3, 16))
	field.add_stylebox_override("focus", _make_flat_style(COLOR_PANEL_BG, COLOR_WHITE, 3, 16))
	if _body_font != null:
		field.add_font_override("font", _body_font)
	field.add_color_override("font_color", _theme_text(COLOR_WHITE))
	field.add_color_override("font_color_uneditable", _theme_text(COLOR_TEXT_DIM))
	field.add_color_override("cursor_color", _theme_text(COLOR_WHITE))
	row.add_child(field)

	var host_button: = _make_button("HOST WITH CODE", COLOR_BLUE, 220)
	row.add_child(host_button)

	var status_label: = _make_label("", _make_font(16), COLOR_TEXT_DIM)
	status_label.name = "GoobplayabilityCustomLobbyCodeStatus"
	status_label.align = Label.ALIGN_CENTER
	block.add_child(status_label)

	# The settings toggle hides the whole block, status line included.
	_custom_lobby_code_row = block
	_custom_lobby_code_status_label = status_label

	field.connect("text_entered", self, "_on_custom_lobby_code_text_entered", [field, status_label, scene, host_button])
	host_button.connect("pressed", self, "_on_custom_lobby_code_button_pressed", [field, status_label, scene, host_button])
	_log_action("Custom Lobby: added host-with-your-own-code option", null)


func _on_custom_lobby_code_button_pressed(field: LineEdit, status_label: Label, scene: Node, host_button: Button) -> void:
	_submit_custom_lobby_code(field, status_label, scene, host_button)


func _on_custom_lobby_code_text_entered(_new_text: String, field: LineEdit, status_label: Label, scene: Node, host_button: Button) -> void:
	_submit_custom_lobby_code(field, status_label, scene, host_button)


func _submit_custom_lobby_code(field: LineEdit, status_label: Label, scene: Node, host_button: Button) -> void:
	if not is_instance_valid(field) or not is_instance_valid(status_label) or not is_instance_valid(scene):
		return
	if _custom_lobby_code_busy:
		status_label.text = "Already working on it -- try again in a moment."
		return
	var code: = field.text.strip_edges()
	if code.empty():
		status_label.text = "Enter a lobby code."
		return
	var moonlight: Node = get_node_or_null("/root/Moonlight")
	if moonlight == null:
		status_label.text = "Not connected."
		return
	if bool(moonlight.auth.is_guest_account()):
		if scene.has_method("notify_is_guest"):
			scene.call("notify_is_guest")
		else:
			status_label.text = "Sign up to create custom lobbies."
		return
	_custom_lobby_code_busy = true
	if is_instance_valid(host_button):
		host_button.disabled = true
	status_label.text = "Setting up lobby..."
	var max_players: = _read_custom_lobby_party_size(scene)
	var outcome: String = yield(_host_or_join_custom_lobby_code(moonlight, max_players, code), "completed")
	_custom_lobby_code_busy = false
	if is_instance_valid(host_button):
		host_button.disabled = false
	if not is_instance_valid(status_label):
		return
	# An empty outcome means it worked -- the lobby_code_changed signal (already
	# connected by the scene's own _ready()) has updated the on-screen code.
	status_label.text = outcome


# Deliberately does NOT call Moonlight.lobby.join_or_create_preset_lobby().
# That function delegates hosting to create_preset_lobby(), which declares its
# parameter as `lobby_code` -- shadowing the member variable of the same name.
# So it assigns the server's answer to the parameter, the member stays empty,
# and the code label the UI reads never updates: the lobby really is registered
# under your code server-side, but nothing on screen ever says so, which reads
# as "it ignored my code". Winterpixel never hit this because the only caller
# is the Discord join button, and refresh_lobby_code_label() hides the label
# outright for `discord_*` codes. Doing the same two steps here lets us write
# the member ourselves and report what the server actually said.
func _host_or_join_custom_lobby_code(moonlight: Node, max_players: int, code: String) -> String:
	var lobby = moonlight.lobby
	var party = moonlight.party
	if lobby == null or party == null:
		return "Not connected."

	# Already a lobby under this code? Join it, exactly like typing the code
	# into the game's own JOIN box. join_lobby_code() sets the member itself.
	var join_result: Dictionary = yield(lobby.join_lobby_code(code), "completed")
	if not join_result.has("error"):
		_log_action("Custom Lobby: joined existing lobby '%s'" % code, null)
		return ""

	# Nothing there yet, so host a new one under that code.
	var create_result = party.create_lobby(max_players)
	if create_result is GDScriptFunctionState:
		yield(create_result, "completed")
	if not bool(party.is_in_lobby()):
		_log_action("Custom Lobby: failed to create a lobby for '%s'" % code, null)
		return "Couldn't create the lobby -- try again."

	var write_result = lobby.write_lobby_code(str(party.party_id), code)
	var written_code: = ""
	if write_result is GDScriptFunctionState:
		written_code = str(yield(write_result, "completed"))
	else:
		written_code = str(write_result)
	if written_code.empty():
		_log_action("Custom Lobby: server rejected the code '%s'" % code, null)
		return "The server wouldn't accept that code -- try another."

	lobby.lobby_code = written_code
	lobby.emit_signal("lobby_code_changed")
	_log_action("Custom Lobby: hosting under code '%s'" % written_code, null)
	return ""


# party_size is a compile-time const on UICustomLobbyScene.gd (32, matching
# the game's own "32-player race royale"), not an instance var, so it can't
# be read with a plain get(). Pulling it from the script's own constant map
# means this keeps working even if Winterpixel ever changes that number --
# 32 below is only the fallback if that lookup fails for some reason.
func _read_custom_lobby_party_size(scene: Node) -> int:
	var script_ref = scene.get_script()
	if script_ref != null:
		var constants: Dictionary = script_ref.get_script_constant_map()
		if constants.has("party_size"):
			return int(constants["party_size"])
	return 32
