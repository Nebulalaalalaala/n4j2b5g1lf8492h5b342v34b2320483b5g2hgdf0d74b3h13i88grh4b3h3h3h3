extends "user://mod/tools/avatar-studio/CosmeticSandbox/03_modal_layout.gd"

func _all_cosmetics() -> Dictionary:
	var source = Moonlight.storage.storage_get("cosmetics", {})
	_catalog_waiting_for_source = typeof(source) != TYPE_DICTIONARY or source.empty()
	var result: Dictionary = source.duplicate(true) if typeof(source) == TYPE_DICTIONARY else {}
	if not result.has("color_default"):
		result["color_default"] = CosmeticsCollection.lookup_cosmetic_id("color_default")
	if not result.has("color_yellow"):
		result["color_yellow"] = CosmeticsCollection.lookup_cosmetic_id("color_yellow")
	_log_cosmetic_catalog_diagnostics(source, result)
	return result


# Phase 0.4 -- Cosmetic Sandbox Content Loading Bug. Debug Mode-only
# diagnostics for the "accessories/emotes don't populate" report. This
# deliberately does NOT try to guess-fix the data source: whether
# Moonlight's "cosmetics" cache is empty, keyed differently, or just
# populated after a delay can only be confirmed by seeing this output on the
# affected machine/account, so it reports exactly what _all_cosmetics() saw
# instead of silently reinterpreting it.
func _log_cosmetic_catalog_diagnostics(raw_source, merged: Dictionary) -> void:
	if tas_tool == null or not is_instance_valid(tas_tool) or not tas_tool.has_method("_log_action"):
		return
	if not bool(tas_tool.get("_debug_mode_enabled")):
		return
	if typeof(raw_source) != TYPE_DICTIONARY or raw_source.empty():
		var reason: String = "an empty catalog" if typeof(raw_source) == TYPE_DICTIONARY else "a non-Dictionary value (type %d)" % typeof(raw_source)
		var empty_signature := "empty:%s" % reason
		if empty_signature == _last_catalog_diag_signature:
			return
		_last_catalog_diag_signature = empty_signature
		tas_tool.call("_log_action", "Cosmetic Sandbox: Moonlight.storage 'cosmetics' returned %s -- only the 2 built-in fallback colors are available." % reason, null)
		return
	var counts: = {}
	var missing_type: = 0
	var missing_name: = 0
	for cosmetic_id in merged.keys():
		var data = merged[cosmetic_id]
		if typeof(data) != TYPE_DICTIONARY:
			missing_type += 1
			continue
		var cosmetic_type: String = str(data.get("type", ""))
		if cosmetic_type.empty():
			missing_type += 1
		else:
			counts[cosmetic_type] = int(counts.get(cosmetic_type, 0)) + 1
		if str(data.get("name", "")).empty():
			missing_name += 1
	var count_text: = []
	for cosmetic_type in TYPE_ORDER:
		count_text.append("%s: %d" % [cosmetic_type, int(counts.get(cosmetic_type, 0))])
	var extra: = ""
	if missing_type > 0:
		extra += " -- %d item(s) missing/invalid type" % missing_type
	if missing_name > 0:
		extra += " -- %d item(s) missing a name" % missing_name
	var diag_signature := "%d:%s:%d:%d" % [raw_source.size(), str(counts), missing_type, missing_name]
	if diag_signature == _last_catalog_diag_signature:
		return
	_last_catalog_diag_signature = diag_signature
	tas_tool.call("_log_action", "Cosmetic Sandbox: %d item(s) from Moonlight catalog (%s)%s" % [raw_source.size(), ", ".join(PoolStringArray(count_text)), extra], null)


func _rebuild_grid() -> void:
	if _studio != null:
		_studio.rebuild_catalog()
		return
	if _grid == null:
		return
	_clear_cosmetic_grid()
	var cosmetics := _all_cosmetics()
	_sorting_cosmetics = cosmetics
	var ids := cosmetics.keys()
	ids.sort_custom(self, "_sort_cosmetics")
	var query := _search_box.text.strip_edges().to_lower() if _search_box != null else ""
	for cosmetic_id in ids:
		var data: Dictionary = cosmetics[cosmetic_id]
		var cosmetic_type: String = data.get("type", "other")
		if _filter != "all" and cosmetic_type != _filter:
			continue
		var cosmetic_name: String = data.get("name", str(cosmetic_id))
		if not query.empty() and cosmetic_name.to_lower().find(query) < 0 and str(cosmetic_id).to_lower().find(query) < 0:
			continue
		_add_visual_cosmetic_card(str(cosmetic_id), cosmetic_name, cosmetic_type)


func _clear_cosmetic_grid() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		# queue_free keeps the native Spine card in-tree until the idle deletion
		# pass. Removing it synchronously from its own button signal can tear down
		# Spine state while the plugin is still dispatching that signal.
		child.visible = false
		child.queue_free()


func _refresh_visual_card_selection() -> void:
	if _grid == null:
		return
	for holder in _grid.get_children():
		if not holder.has_meta("cosmetic_id"):
			continue
		var cosmetic_id: String = holder.get_meta("cosmetic_id")
		var selected := selected_cosmetics.has(cosmetic_id)
		var selection_panel = holder.get_node_or_null("Selection")
		if selection_panel != null:
			selection_panel.add_stylebox_override("panel", _flat_style(Color(0.02, 0.12, 0.24, 0.7), PINK if selected else Color(1, 1, 1, 0.15), 6 if selected else 2, 24))
		var name_label = holder.get_node_or_null("Name")
		if name_label != null:
			name_label.text = ("✓  " if selected else "") + str(holder.get_meta("cosmetic_name"))


func _add_visual_cosmetic_card(cosmetic_id: String, cosmetic_name: String, cosmetic_type: String) -> void:
	var selected := selected_cosmetics.has(cosmetic_id)
	var holder := Control.new()
	holder.rect_min_size = Vector2(210, 294)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.set_meta("cosmetic_id", cosmetic_id)
	holder.set_meta("cosmetic_name", cosmetic_name)
	# Add the holder first so the native card enters the tree and all of its
	# onready references exist before show_cosmetic() configures the preview.
	_grid.add_child(holder)
	var selection_panel := Panel.new()
	selection_panel.name = "Selection"
	selection_panel.anchor_right = 1.0
	selection_panel.anchor_bottom = 1.0
	selection_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_panel.add_stylebox_override("panel", _flat_style(Color(0.02, 0.12, 0.24, 0.7), PINK if selected else Color(1, 1, 1, 0.15), 6 if selected else 2, 24))
	holder.add_child(selection_panel)
	var card_scene = load(COSMETIC_CARD_SCENE_PATH)
	if card_scene != null and card_scene is PackedScene:
		var card = card_scene.instance()
		card.rect_position = Vector2(5, 2)
		card.hint_tooltip = "%s\n%s\nLocal sandbox—ownership is unchanged." % [cosmetic_name, cosmetic_id]
		holder.add_child(card)
		card.call("show_cosmetic", cosmetic_id, {"unlocked": true})
		var card_goober = card.get("goober")
		if card_goober != null:
			card_goober.update_mode = SpineConstant.UpdateMode_Manual
			card_goober.call("update_skeleton", 0.0)
		elif tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("_log_action") and bool(tas_tool.get("_debug_mode_enabled")):
			# Phase 0.4 -- Cosmetic Sandbox Content Loading Bug. show_cosmetic()
			# ran but the card ended up with no Spine node -- likely a failed
			# asset load for this specific item rather than a catalog problem.
			tas_tool.call("_log_action", "Cosmetic Sandbox: '%s' (%s) has no preview -- show_cosmetic() left 'goober' null (failed/missing asset)." % [cosmetic_name, cosmetic_id], null)
		card.connect("button_pressed", self, "_toggle_cosmetic", [cosmetic_id])
	var label := _make_label(("✓  " if selected else "") + cosmetic_name, _small_font, WHITE)
	label.name = "Name"
	label.anchor_left = 0.0
	label.anchor_top = 1.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.margin_left = 8.0
	label.margin_top = -42.0
	label.margin_right = -8.0
	label.margin_bottom = -5.0
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)


func _sort_cosmetics(a, b) -> bool:
	var data_a: Dictionary = _sorting_cosmetics.get(a, {})
	var data_b: Dictionary = _sorting_cosmetics.get(b, {})
	var type_a: String = data_a.get("type", "other")
	var type_b: String = data_b.get("type", "other")
	var order_a := TYPE_ORDER.find(type_a)
	var order_b := TYPE_ORDER.find(type_b)
	if order_a < 0:
		order_a = 999
	if order_b < 0:
		order_b = 999
	if order_a != order_b:
		return order_a < order_b
	return str(data_a.get("name", a)).naturalnocasecmp_to(str(data_b.get("name", b))) < 0


func _toggle_cosmetic(cosmetic_id: String) -> void:
	var data: Dictionary = CosmeticsCollection.lookup_cosmetic_id(cosmetic_id)
	if data.empty():
		return
	if selected_cosmetics.has(cosmetic_id):
		selected_cosmetics.erase(cosmetic_id)
	else:
		if data.get("type", "") == "color":
			_remove_selected_type("color")
			custom_color_enabled = false
		selected_cosmetics.append(cosmetic_id)
	sandbox_enabled = true
	_commit_change(true)


func _remove_selected_type(cosmetic_type: String) -> void:
	var keep := []
	for cosmetic_id in selected_cosmetics:
		var data: Dictionary = CosmeticsCollection.lookup_cosmetic_id(str(cosmetic_id))
		if data.get("type", "") != cosmetic_type:
			keep.append(cosmetic_id)
	selected_cosmetics = keep


func _toggle_sandbox_enabled() -> void:
	sandbox_enabled = not sandbox_enabled
	if sandbox_enabled:
		_apply_sandbox_to_registered_goobers()
	else:
		_restore_all_registered_goobers()
	_commit_change(false)


func _toggle_profile_base() -> void:
	include_profile_base = not include_profile_base
	sandbox_enabled = true
	_commit_change(false)


func _toggle_custom_color() -> void:
	custom_color_enabled = not custom_color_enabled
	sandbox_enabled = true
	if custom_color_enabled:
		_remove_selected_type("color")
	_commit_change(true)


func _on_custom_color_changed(color: Color) -> void:
	custom_color = Color(color.r, color.g, color.b, 1.0)
	custom_color_enabled = true
	sandbox_enabled = true
	_remove_selected_type("color")
	_commit_change(false)


func _randomize_stack() -> void:
	var cosmetics := _all_cosmetics()
	var by_type := {"color": [], "suit": [], "hat": [], "hand": [], "emote": []}
	for cosmetic_id in cosmetics:
		var cosmetic_type: String = cosmetics[cosmetic_id].get("type", "")
		if by_type.has(cosmetic_type):
			by_type[cosmetic_type].append(str(cosmetic_id))
	selected_cosmetics = []
	_pick_random_from(by_type["color"], 1)
	_pick_random_from(by_type["suit"], 2)
	_pick_random_from(by_type["hat"], 2)
	_pick_random_from(by_type["hand"], 2)
	_pick_random_from(by_type["emote"], 1)
	custom_color_enabled = false
	sandbox_enabled = true
	_commit_change(true)


func _pick_random_from(source: Array, count: int) -> void:
	var pool := source.duplicate()
	for _i in range(min(count, pool.size())):
		var index := randi() % pool.size()
		selected_cosmetics.append(pool[index])
		pool.remove(index)


func _clear_extras() -> void:
	selected_cosmetics.clear()
	custom_color_enabled = false
	sandbox_enabled = true
	_commit_change(true)


func _disable_and_restore_profile() -> void:
	sandbox_enabled = false
	_restore_all_registered_goobers()
	_commit_change(false)


func _commit_change(rebuild: bool) -> void:
	_applied_signatures.clear()
	if sandbox_enabled:
		_apply_sandbox_to_registered_goobers()
	else:
		_restore_all_registered_goobers()
	_queue_save()
	_refresh_controls()
	if rebuild and _modal_root.visible:
		# Selection changes only touch lightweight UI decoration. Never destroy or
		# recreate the native Spine card from inside its own button signal.
		_refresh_visual_card_selection()
	if _studio != null:
		_studio.changed()


func _refresh_controls() -> void:
	if _status_label != null:
		_status_label.text = "%d extra cosmetic%s equipped" % [selected_cosmetics.size(), ("" if selected_cosmetics.size() == 1 else "s")]
	if _active_button != null:
		_active_button.text = "SANDBOX: %s" % ("ON" if sandbox_enabled else "OFF")
		_style_button(_active_button, PINK if sandbox_enabled else NAVY_2, 18, 4)
	if _profile_base_button != null:
		_profile_base_button.text = "REAL PROFILE BASE: %s" % ("INCLUDED" if include_profile_base else "HIDDEN")
	if _custom_color_button != null:
		_custom_color_button.text = "CUSTOM COLOUR: %s" % ("ON" if custom_color_enabled else "OFF")
		_style_button(_custom_color_button, custom_color if custom_color_enabled else PURPLE, 18, 4)
	if _color_picker != null:
		_color_picker.color = custom_color
	_refresh_filter_buttons()
	_refresh_avatar_button()
	if _preview_goober != null and is_instance_valid(_preview_goober) and sandbox_enabled:
		_apply_to_goober(_preview_goober, _build_local_skin())


func _refresh_filter_buttons() -> void:
	for key in _filter_buttons:
		var button: Button = _filter_buttons[key]
		_style_button(button, PINK if key == _filter else TYPE_COLORS.get(key, BLUE).darkened(0.18), 14, 3)


func _refresh_avatar_button() -> void:
	if _avatar_button == null or not is_instance_valid(_avatar_button):
		return
	_avatar_button.text = "AVATAR STUDIO%s" % ("  •" if sandbox_enabled else "")
	_style_button(_avatar_button, Color("304c40") if sandbox_enabled else Color("22282c"), 23, 5)


func _queue_save() -> void:
	_save_pending = true
	_save_delay = 0.25


func _load_settings() -> void:
	var file := File.new()
	if not file.file_exists(SETTINGS_PATH) or file.open(SETTINGS_PATH, File.READ) != OK:
		return
	var data = file.get_var(false)
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	sandbox_enabled = bool(data.get("enabled", false))
	include_profile_base = bool(data.get("include_profile_base", true))
	var stored_selected = data.get("selected_cosmetics", [])
	selected_cosmetics = stored_selected.duplicate() if typeof(stored_selected) == TYPE_ARRAY else []
	custom_color_enabled = bool(data.get("custom_color_enabled", false))
	var stored_color = data.get("custom_color", custom_color)
	if typeof(stored_color) == TYPE_COLOR:
		custom_color = Color(stored_color.r, stored_color.g, stored_color.b, 1.0)


func _save_settings() -> void:
	var file := File.new()
	if file.open(SETTINGS_PATH, File.WRITE) != OK:
		return
	file.store_var({
		"enabled": sandbox_enabled,
		"include_profile_base": include_profile_base,
		"selected_cosmetics": selected_cosmetics,
		"custom_color_enabled": custom_color_enabled,
		"custom_color": custom_color,
	}, false)
	file.close()


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


# Button backgrounds are brand accent colors (blue/pink/green/purple) that
# _theme_fill() deliberately leaves alone. Muted here on top of that so
# they read as flat modern tones instead of bright candy-colored pills.
func _theme_accent(color: Color) -> Color:
	if not _modern_theme_active():
		return color
	# Same restrained palette as TASTool.gd -- BLUE is this file's default/
	# inactive button color too (PINK if sandbox_enabled/selected else BLUE),
	# so it becomes a calm neutral slate rather than another loud accent;
	# PINK is the actual "active/selected" signal, so it gets the one vivid
	# accent color. Red stays reserved for PINK_DARK's close/destructive use.
	if _color_rgb_eq(color, BLUE):
		return Color(0.22, 0.23, 0.26, color.a)
	if _color_rgb_eq(color, PINK):
		return Color(0.21, 0.38, 0.31, color.a)
	if _color_rgb_eq(color, PINK_DARK):
		return Color(0.43, 0.23, 0.23, color.a)
	if _color_rgb_eq(color, GREEN):
		return Color(0.22, 0.40, 0.32, color.a)
	if _color_rgb_eq(color, PURPLE):
		return Color(0.22, 0.28, 0.29, color.a)
	if _color_rgb_eq(color, ORANGE):
		return Color(0.961, 0.62, 0.043, color.a)
	return color


func _get_claude_modern_font_data() -> DynamicFontData:
	if _claude_modern_font_load_attempted:
		return _claude_modern_font_data
	_claude_modern_font_load_attempted = true
	if File.new().file_exists(CLAUDE_EXPERIMENTAL_FONT_PATH):
		var data := DynamicFontData.new()
		data.font_path = CLAUDE_EXPERIMENTAL_FONT_PATH
		data.antialiased = true
		data.override_oversampling = 2.0
		_claude_modern_font_data = data
	return _claude_modern_font_data
