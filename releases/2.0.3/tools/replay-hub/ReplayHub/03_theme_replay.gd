extends "user://mod/tools/replay-hub/ReplayHub/02_hub_council.gd"

# ----------------------------------------------------------------------
#  Download / Play (fetch full data, then import into a Macro Slot)
# ----------------------------------------------------------------------
func _on_download_pressed(id: String, title: String) -> void:
	_start_detail_fetch(id, {"mode": "download", "title": title})


func _on_play_pressed(id: String, title: String) -> void:
	_start_detail_fetch(id, {"mode": "play", "title": title})


func _start_detail_fetch(id: String, context: Dictionary) -> void:
	if not _looks_like_uuid(id):
		_set_status("That replay has an invalid id.")
		return
	if _detail_busy:
		_set_status("Already fetching a replay -- try again in a moment.")
		return
	if tas_tool == null or not is_instance_valid(tas_tool):
		_set_status("Goobplayability isn't available to import into.")
		return
	_detail_busy = true
	_pending_detail_context = context
	_set_status("Fetching '%s'..." % str(context.get("title", "")))
	var url := "%s/rest/v1/%s?id=eq.%s&select=data" % [SUPABASE_URL, REPLAYS_TABLE, id]
	if _detail_http.request(url, _auth_headers(), true, HTTPClient.METHOD_GET) != OK:
		_detail_busy = false
		_pending_detail_context = {}
		_set_status("Couldn't start the download.")


func _looks_like_uuid(s: String) -> bool:
	if s.length() != 36:
		return false
	for i in range(s.length()):
		var c := s[i]
		if c == "-":
			continue
		var is_hex := (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
		if not is_hex:
			return false
	return true


func _looks_like_safe_variant_string(s: String) -> bool:
	# var2str() with the default full_objects=false -- all this file's own
	# export path ever uses -- never emits an "Object(" literal. Refusing
	# that token before str2var() is a defense-in-depth guard against a
	# hand-edited row trying to smuggle an Object through decoding, on top
	# of the Dictionary/key validation done right after.
	return s.find("Object(") == -1


# Macro Slot data (checkpoints/segments/level_context) is a rich per-tick
# physics snapshot -- real slots have come in around 8 MB as plain
# var2str() text. Gzipping before upload/export shrinks that a lot (it's
# highly repetitive structured text) and keeps both the client-side limits
# and the Supabase row size reasonable. Only used when it actually helps --
# a tiny macro can come out larger once gzip framing + base64 overhead is
# added, so those are stored as plain var2str() text instead, unprefixed.
func _encode_replay_data(data: Dictionary) -> String:
	var raw_string: = var2str(data)
	var raw_bytes: = raw_string.to_utf8()
	var compressed: = raw_bytes.compress(File.COMPRESSION_GZIP)
	if compressed.size() < raw_bytes.size():
		var b64: = Marshalls.raw_to_base64(compressed)
		return "%s%d:%s" % [COMPRESSED_DATA_PREFIX, raw_bytes.size(), b64]
	return raw_string


# Reverses _encode_replay_data(). Returns the plain var2str() text either
# way (never decodes the Variant itself -- the caller still runs the
# result through _looks_like_safe_variant_string() and str2var() exactly
# as before). A row with no compression prefix is passed through
# unchanged, so replays uploaded before this change still work. Returns an
# empty string on any malformed/oversized input rather than trusting it.
func _decode_replay_data(encoded: String) -> String:
	if not encoded.begins_with(COMPRESSED_DATA_PREFIX):
		return encoded
	var rest: = encoded.substr(COMPRESSED_DATA_PREFIX.length())
	var sep: = rest.find(":")
	if sep <= 0:
		return ""
	var size_text: = rest.substr(0, sep)
	var b64: = rest.substr(sep + 1)
	if not size_text.is_valid_integer():
		return ""
	var expected_size: = int(size_text)
	if expected_size <= 0 or expected_size > MAX_DECOMPRESSED_BYTES:
		return ""
	var compressed: = Marshalls.base64_to_raw(b64)
	if compressed.empty():
		return ""
	var decompressed: = compressed.decompress(expected_size, File.COMPRESSION_GZIP)
	if decompressed.size() != expected_size:
		return ""
	return decompressed.get_string_from_utf8()


func _on_detail_request_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	_detail_busy = false
	var context: Dictionary = _pending_detail_context
	_pending_detail_context = {}
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_set_status("Couldn't fetch that replay (HTTP %d)." % response_code)
		return
	if body.size() <= 0 or body.size() > MAX_REPLAY_PAYLOAD_BYTES + 4096:
		_set_status("Replay response had an invalid size.")
		return
	var parsed := JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY or parsed.result.empty():
		_set_status("Replay response was not valid JSON.")
		return
	var row = parsed.result[0]
	if typeof(row) != TYPE_DICTIONARY or not row.has("data"):
		_set_status("Replay response was missing its data.")
		return
	var encoded := _decode_replay_data(str(row["data"]))
	if encoded.empty():
		_set_status("That replay's data is corrupt, oversized, or from an incompatible format.")
		return
	if not _looks_like_safe_variant_string(encoded):
		_set_status("Refused to import that replay -- its data failed a safety check.")
		return
	var decoded = str2var(encoded)
	if typeof(decoded) != TYPE_DICTIONARY or not decoded.has("checkpoints") or not decoded.has("segments"):
		_set_status("That replay's data is corrupt or from an incompatible format.")
		return
	var title := str(context.get("title", "Downloaded Replay"))
	if not tas_tool.has_method("_import_downloaded_replay"):
		_set_status("This Goobplayability build can't import replays yet.")
		return
	var slot := int(tas_tool.call("_import_downloaded_replay", decoded, title))
	if slot <= 0:
		_set_status("Import failed -- check the Action Log.")
		return
	if str(context.get("mode", "")) == "play" and tas_tool.has_method("_on_play_saved_practice_macro_slot_pressed"):
		tas_tool.call("_on_play_saved_practice_macro_slot_pressed", slot)
		_set_status("Imported into Macro Slot %d and opening the level..." % slot)
	else:
		_set_status("Imported '%s' into Macro Slot %d." % [title, slot])


# ----------------------------------------------------------------------
#  Export a local Macro Slot to a SQL INSERT (no network -- clipboard only)
# ----------------------------------------------------------------------
func _open_export_picker() -> void:
	if tas_tool == null or not is_instance_valid(tas_tool):
		_set_status("Goobplayability isn't available.")
		return
	if not tas_tool.has_method("_get_practice_macro_slots_snapshot"):
		_set_status("This Goobplayability build can't export Macro Slots yet.")
		return
	var slots: Dictionary = tas_tool.call("_get_practice_macro_slots_snapshot")
	_populate_export_picker(slots)
	_export_root.visible = true


func _populate_export_picker(slots: Dictionary) -> void:
	for child in _export_list_box.get_children():
		child.queue_free()
	var keys := slots.keys()
	keys.sort()
	if keys.empty():
		_export_list_box.add_child(_make_label("No saved Macro Slots yet.", _small_font, DIM))
		return
	for slot_key in keys:
		var slot := int(slot_key)
		var data = slots[slot_key]
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var macro_name := str(data.get("name", "Macro %d" % slot))
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 6)
		var label := _make_label("Slot %d — %s" % [slot, macro_name], _small_font, WHITE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var upload_btn := _make_button("UPLOAD", GREEN, 15)
		upload_btn.rect_min_size = Vector2(120, 0)
		upload_btn.connect("pressed", self, "_on_upload_slot_pressed", [slot, data])
		row.add_child(upload_btn)
		var sql_btn := _make_button("SQL", BLUE, 15)
		sql_btn.rect_min_size = Vector2(80, 0)
		sql_btn.connect("pressed", self, "_on_copy_slot_sql_pressed", [slot, data])
		row.add_child(sql_btn)
		_export_list_box.add_child(row)


func _on_author_field_changed(text: String) -> void:
	SavedSettings.set_value(SETTING_AUTHOR_NAME, text)


func _current_author_name() -> String:
	var text := ""
	if _author_field != null:
		text = _author_field.text.strip_edges()
	return text if not text.empty() else "Anonymous"


func _current_mod_version() -> String:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_get_goobplayability_version"):
		return str(tas_tool.call("_get_goobplayability_version"))
	return "unknown"


# Shared by both the UPLOAD and COPY SQL actions so the two paths can never
# describe the same slot differently.
func _extract_replay_metadata(slot: int, data: Dictionary) -> Dictionary:
	var macro_name := str(data.get("name", "Macro %d" % slot))
	var level_context = data.get("level_context", {})
	var level_name := ""
	var level_id := ""
	if typeof(level_context) == TYPE_DICTIONARY:
		level_name = str(level_context.get("level_name", ""))
		level_id = str(level_context.get("level_id", ""))
	var level_display := level_name if not level_name.empty() else level_id
	if level_display.empty():
		level_display = "unknown"
	var frame_count := 0
	var segments = data.get("segments", [])
	if typeof(segments) == TYPE_ARRAY:
		for segment in segments:
			if typeof(segment) == TYPE_ARRAY:
				frame_count += segment.size()
	var run_time_ms := int(round(frame_count / 60.0 * 1000.0))
	return {
		"title": macro_name,
		"level": level_display,
		"run_time_ms": run_time_ms,
		"encoded": _encode_replay_data(data),
	}


func _on_copy_slot_sql_pressed(slot: int, data: Dictionary) -> void:
	var meta := _extract_replay_metadata(slot, data)
	var sql := "-- Edit author/compatibility/featured before running if you want.\n"
	sql += "insert into public.replays (title, author, level, run_time_ms, compatibility, data, featured)\n"
	sql += "values (\n"
	sql += "  %s,\n" % _sql_quote(str(meta["title"]))
	sql += "  %s,\n" % _sql_quote(_current_author_name())
	sql += "  %s,\n" % _sql_quote(str(meta["level"]))
	sql += "  %d,\n" % int(meta["run_time_ms"])
	sql += "  %s,\n" % _sql_quote(_current_mod_version())
	sql += "  %s,\n" % _sql_quote(str(meta["encoded"]))
	sql += "  false\n"
	sql += ");\n"
	OS.clipboard = sql
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_log_action"):
		tas_tool.call("_log_action", "Copied a Replay Hub SQL INSERT for Macro Slot %d to the clipboard -- paste it into the Supabase SQL editor." % slot, null)
	_set_status("Copied SQL for Slot %d to clipboard." % slot)
	_close_export_picker()


func _sql_quote(text: String) -> String:
	return "'" + text.replace("'", "''") + "'"


# ----------------------------------------------------------------------
#  Upload (real network POST -- anon key, bounded by the Supabase RLS
#  insert policy in replay_hub_schema.sql: sane size limits, and every
#  upload is forced to featured=false so it can never mark itself Featured)
# ----------------------------------------------------------------------
func _on_upload_slot_pressed(slot: int, data: Dictionary) -> void:
	if _upload_busy:
		_set_status("Already uploading -- try again in a moment.")
		return
	var meta := _extract_replay_metadata(slot, data)
	var encoded := str(meta["encoded"])
	if encoded.length() > MAX_REPLAY_PAYLOAD_BYTES:
		_set_status("That Macro Slot is too large to upload (%d KB, limit %d KB)." % [encoded.length() / 1024, MAX_REPLAY_PAYLOAD_BYTES / 1024])
		return
	var payload := {
		"title": str(meta["title"]),
		"author": _current_author_name(),
		"level": str(meta["level"]),
		"run_time_ms": int(meta["run_time_ms"]),
		"compatibility": _current_mod_version(),
		"data": encoded,
		"featured": false,
	}
	var body := to_json(payload)
	if body.length() > MAX_REPLAY_PAYLOAD_BYTES + 4096:
		_set_status("That Macro Slot is too large to upload.")
		return
	var headers := _auth_headers()
	headers.append("Content-Type: application/json")
	headers.append("Prefer: return=minimal")
	var url := "%s/rest/v1/%s" % [SUPABASE_URL, REPLAYS_TABLE]
	_upload_busy = true
	_set_status("Uploading Slot %d..." % slot)
	if _upload_http.request(url, headers, true, HTTPClient.METHOD_POST, body) != OK:
		_upload_busy = false
		_set_status("Couldn't start the upload.")
		return
	_close_export_picker()


func _on_upload_request_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	_upload_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 201):
		var detail := ""
		if body.size() > 0 and body.size() <= 512:
			detail = " -- " + body.get_string_from_utf8()
		_set_status("Upload failed (HTTP %d)%s" % [response_code, detail])
		return
	_set_status("Uploaded! Refreshing the list...")
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_log_action"):
		tas_tool.call("_log_action", "Uploaded a replay to the Replay Hub.", null)
	if _active_tab != TAB_NEWEST:
		_active_tab = TAB_NEWEST
		for i in range(_tab_buttons.size()):
			var btn: Button = _tab_buttons[i]
			var is_active := (i == _active_tab)
			btn.pressed = is_active
			_style_button(btn, PINK if is_active else BLUE, 18, 4)
	_refresh_list()


# ----------------------------------------------------------------------
#  Claude Experimental Mode theme remapping (same restrained palette and
#  value-based remap technique as TASTool.gd/CosmeticSandbox.gd/
#  TASMacroEditor.gd -- see those files for the full rationale). Every
#  function here returns its input completely unchanged when the toggle is
#  off, so the classic look above is pixel-identical to before this was
#  added.
# ----------------------------------------------------------------------
func _modern_theme_active() -> bool:
	return true


func _color_rgb_eq(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


# Remaps a background/fill/panel color, by value, preserving the caller's
# own alpha. Must be called BEFORE any .lightened()/.darkened() transform.
func _theme_fill(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, NAVY):
		return Color(MODERN_BG.r, MODERN_BG.g, MODERN_BG.b, color.a)
	if _color_rgb_eq(color, NAVY_2):
		return Color(MODERN_BG_2.r, MODERN_BG_2.g, MODERN_BG_2.b, color.a)
	return color


func _theme_border(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, WHITE):
		return Color(MODERN_BORDER.r, MODERN_BORDER.g, MODERN_BORDER.b, color.a)
	return color


func _theme_text(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, WHITE):
		return Color(MODERN_WHITE.r, MODERN_WHITE.g, MODERN_WHITE.b, color.a)
	if _color_rgb_eq(color, DIM):
		return Color(MODERN_DIM.r, MODERN_DIM.g, MODERN_DIM.b, color.a)
	return _theme_accent(color)


# Button backgrounds are brand accent colors (blue/pink/green) that
# _theme_fill() deliberately leaves alone. Muted here on top of that so
# they read as flat modern tones instead of bright candy-colored pills.
# Same restrained palette as every other window: BLUE is this file's
# default/inactive tab color, so it becomes a calm neutral slate rather
# than another loud accent; PINK is the "active" tab/badge signal, so it
# gets the one vivid accent color; PINK_DARK stays reserved for close/
# destructive buttons, GREEN for play/positive actions.
func _theme_accent(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	if _color_rgb_eq(color, BLUE):
		return Color(0.22, 0.23, 0.26, color.a)
	if _color_rgb_eq(color, PINK):
		return Color(0.21, 0.38, 0.31, color.a)
	if _color_rgb_eq(color, PINK_DARK):
		return Color(0.43, 0.23, 0.23, color.a)
	if _color_rgb_eq(color, GREEN):
		return Color(0.22, 0.40, 0.32, color.a)
	return color


func _get_claude_modern_font_data() -> DynamicFontData:
	if _claude_modern_font_load_attempted:
		return _claude_modern_font_data
	_claude_modern_font_load_attempted = true
	if File.new().file_exists(CLAUDE_EXPERIMENTAL_FONT_PATH):
		var data: = DynamicFontData.new()
		data.font_path = CLAUDE_EXPERIMENTAL_FONT_PATH
		data.antialiased = true
		data.override_oversampling = 2.0
		_claude_modern_font_data = data
	return _claude_modern_font_data


# ----------------------------------------------------------------------
#  Style helpers (same conventions as CosmeticSandbox.gd / TASMacroEditor.gd)
# ----------------------------------------------------------------------
func _make_font(size: int) -> DynamicFont:
	var font := DynamicFont.new()
	var crisp_data: DynamicFontData = null
	if _modern_theme_active():
		crisp_data = _get_claude_modern_font_data()
	if crisp_data == null:
		var data = load(FONT_PATH)
		if data == null or not (data is DynamicFontData):
			return null
		crisp_data = data.duplicate()
		crisp_data.antialiased = true
		crisp_data.override_oversampling = 2.0
	font.font_data = crisp_data
	font.size = size
	if _modern_theme_active():
		font.outline_size = 0
		font.outline_color = Color(0, 0, 0, 0)
	else:
		font.outline_size = 1
		font.outline_color = Color(0, 0.02, 0.05, 0.95)
	font.use_filter = true
	font.use_mipmaps = true
	return font
