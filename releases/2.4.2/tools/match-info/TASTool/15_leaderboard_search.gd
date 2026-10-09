extends "user://mod/core/TASTool/14_input_and_menu.gd"

# ----------------------------------------------------------------------
#  Leaderboard tab -- player search
# ----------------------------------------------------------------------
# Goober Dash's own Leaderboard tab (LeaderboardPage.tscn) only ever shows
# the top 100 entries for the selected board -- there's no way to jump
# straight to a specific player. This adds a search row above that list.
# It resolves a typed user ID directly, or a typed username via Nakama's
# own stock get_users_async() lookup (the same client library already
# shipped with the game -- Winterpixel just never wired a UI to it), then
# opens the result through the leaderboard's own on_leaderboard_row_pressed(),
# so it's the exact same profile dialog/fields as clicking any leaderboard
# row -- nothing extra, no online/presence status (the game only tracks
# that for mutual friends, and this doesn't touch that system at all).
func _inject_leaderboard_search(leaderboard_script: Node) -> void:
	if not _leaderboard_search_enabled:
		return
	if not is_instance_valid(leaderboard_script) or not leaderboard_script.has_method("on_leaderboard_row_pressed"):
		return
	var leaderboard_page: Node = leaderboard_script.get_parent()
	if leaderboard_page == null:
		return
	var vbox: VBoxContainer = leaderboard_page.get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vbox == null or vbox.has_node("GoobplayabilityLeaderboardSearch"):
		return
	var background_panel: Control = vbox.get_node_or_null("BackgroundPanel") as Control
	var insert_index: = background_panel.get_index() if background_panel != null else -1

	var row: = HBoxContainer.new()
	row.name = "GoobplayabilityLeaderboardSearch"
	row.add_constant_override("separation", 12)
	vbox.add_child(row)
	if insert_index >= 0:
		vbox.move_child(row, insert_index)

	var field: = LineEdit.new()
	field.name = "SearchField"
	field.placeholder_text = "Paste a player's user ID..."
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.rect_min_size = Vector2(0, BUTTON_H)
	field.add_stylebox_override("normal", _make_flat_style(COLOR_PANEL_BG, COLOR_BLUE, 3, 16))
	field.add_stylebox_override("focus", _make_flat_style(COLOR_PANEL_BG, COLOR_WHITE, 3, 16))
	if _body_font != null:
		field.add_font_override("font", _body_font)
	field.add_color_override("font_color", _theme_text(COLOR_WHITE))
	field.add_color_override("font_color_uneditable", _theme_text(COLOR_TEXT_DIM))
	field.add_color_override("cursor_color", _theme_text(COLOR_WHITE))
	row.add_child(field)

	var search_button: = _make_button("SEARCH", COLOR_BLUE, 160)
	row.add_child(search_button)

	var status_label: = _make_label("", _make_font(16), COLOR_TEXT_DIM)
	status_label.name = "GoobplayabilityLeaderboardSearchStatus"
	status_label.align = Label.ALIGN_CENTER
	vbox.add_child(status_label)
	vbox.move_child(status_label, row.get_index() + 1)

	_leaderboard_search_row = row
	_leaderboard_search_status_label = status_label

	field.connect("text_entered", self, "_on_leaderboard_search_text_entered", [field, status_label, leaderboard_script, search_button])
	search_button.connect("pressed", self, "_on_leaderboard_search_button_pressed", [field, status_label, leaderboard_script, search_button])
	_log_action("Leaderboard: added player search bar", null)


func _on_leaderboard_search_button_pressed(field: LineEdit, status_label: Label, leaderboard_script: Node, search_button: Button) -> void:
	_submit_leaderboard_search(field, status_label, leaderboard_script, search_button)


func _on_leaderboard_search_text_entered(_new_text: String, field: LineEdit, status_label: Label, leaderboard_script: Node, search_button: Button) -> void:
	_submit_leaderboard_search(field, status_label, leaderboard_script, search_button)


# Cooldown is enforced by comparing OS.get_ticks_msec() against a stored
# deadline at the very top of this function, before anything else runs --
# including before the free (no-network) direct-user-ID path. That's the
# actual guarantee: it can't be bypassed by hitting Enter and the button at
# the same time, by a fast double-click, or by triggering the connected
# signals some other way, because nothing below this check ever runs until
# the deadline has passed. Disabling search_button during the cooldown is
# just a visible reminder on top of that, not the enforcement itself.
func _submit_leaderboard_search(field: LineEdit, status_label: Label, leaderboard_script: Node, search_button: Button) -> void:
	if not is_instance_valid(field) or not is_instance_valid(status_label) or not is_instance_valid(leaderboard_script):
		return
	var now_msec: = OS.get_ticks_msec()
	if now_msec < _leaderboard_search_cooldown_until_msec:
		var remaining_sec: = int(ceil(float(_leaderboard_search_cooldown_until_msec - now_msec) / 1000.0))
		status_label.text = "Please wait %ds before searching again." % max(1, remaining_sec)
		return
	var query: = field.text.strip_edges()
	if query.empty():
		status_label.text = "Enter a full user ID."
		return
	var moonlight: Node = get_node_or_null("/root/Moonlight")
	if moonlight == null or not moonlight.has_method("is_logged_in") or not bool(moonlight.is_logged_in()):
		status_label.text = "Not logged in."
		return
	# Username lookup used to be attempted here via Nakama's stock
	# get_users_async(), on the theory that it's a normal, always-available
	# part of the client library. Confirmed against the real server: it
	# returns HTTP 401 (Forbidden) for a regular player session every time --
	# Winterpixel's server itself refuses that call, not something wrong on
	# our end and not something a client-side fix can work around. Only a
	# full user ID (which reuses query_player_profile, the same call every
	# leaderboard row click already makes, and which the server does allow)
	# actually works, so that's the only thing this accepts now.
	_start_leaderboard_search_cooldown(search_button)
	if not _looks_like_goober_user_id(query):
		status_label.text = "Only a full user ID works -- the server doesn't allow username lookups (401 Forbidden)."
		return
	status_label.text = ""
	leaderboard_script.call("on_leaderboard_row_pressed", query)


# Starts the cooldown window immediately (before the request that triggered
# it has even finished), so the minimum gap is measured from one search
# ATTEMPT to the next, not from one search's completion to the next --
# a slow network response can never be used to sneak in an extra request.
func _start_leaderboard_search_cooldown(search_button: Button) -> void:
	_leaderboard_search_cooldown_until_msec = OS.get_ticks_msec() + int(LEADERBOARD_SEARCH_COOLDOWN_SEC * 1000.0)
	if is_instance_valid(search_button):
		search_button.disabled = true
	var timer: = get_tree().create_timer(LEADERBOARD_SEARCH_COOLDOWN_SEC)
	timer.connect("timeout", self, "_on_leaderboard_search_cooldown_elapsed", [search_button])


func _on_leaderboard_search_cooldown_elapsed(search_button: Button) -> void:
	if is_instance_valid(search_button):
		search_button.disabled = false


func _looks_like_goober_user_id(s: String) -> bool:
	if s.length() != 36:
		return false
	for i in range(s.length()):
		var c: = s[i]
		if c == "-":
			continue
		var is_hex: = (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		if not is_hex:
			return false
	return true
