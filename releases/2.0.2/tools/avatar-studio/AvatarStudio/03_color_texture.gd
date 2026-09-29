extends "user://mod/tools/avatar-studio/AvatarStudio/02_preview_font.gd"

func _goober_mode(value: bool) -> void:
	effects_mode = false
	texture_mode = value
	page_index = 0
	rebuild_catalog()

func _effects_mode() -> void:
	effects_mode = true
	rebuild_catalog()

func _effect_selected(kind: String, id: String) -> void:
	effect_settings[kind] = id
	status.text = ""
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)
	rebuild_catalog()

func _effect_color_changed(color: Color) -> void:
	effect_settings["color"] = color.to_html(false)
	status.text = ""
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)

func rebuild_catalog() -> void:
	if catalog_grid == null or refreshing:
		return
	refreshing = true
	_refresh_transforms()
	for child in catalog_grid.get_children():
		child.hide()
		child.queue_free()
	goober_tabs.visible = category == "color"
	color_controls.visible = category == "color" and not texture_mode and not effects_mode
	texture_controls.visible = category == "color" and texture_mode and not effects_mode
	effect_controls.visible = category == "color" and effects_mode
	search.get_parent().visible = not effect_controls.visible
	category_actions.visible = not effect_controls.visible
	for child in paging.get_parent().get_children():
		if child is Button:
			child.visible = not effect_controls.visible
	if effect_controls.visible:
		inspector.text = ""
		for effect_row in effect_controls.get_children():
			for choice in effect_row.get_children():
				if choice.has_meta("effect"):
					var entry = choice.get_meta("effect")
					choice.add_stylebox_override("normal", style(Color("30463b") if effect_settings.get(entry[0]) == entry[1] else PANEL))
		paging.text = "Dash: %s · Trail: %s" % [effect_settings.dash.capitalize(), effect_settings.trail.capitalize()]
		refreshing = false
		return
	for key in category_buttons:
		category_buttons[key].add_stylebox_override("normal", style(Color("30463b") if key == category else PANEL))
	inspector.text = "Cosmetic held items only." if category == "hand" else ""
	if category in ["hat", "suit", "hand"]:
		inspector.text += " Equip an item to adjust its position, rotation and scale."
	if category == "emote":
		inspector.text = "Select an emote to preview it. Playback controls are in Preview."
	var catalog: Dictionary = sandbox.call("_all_cosmetics")
	var ids = []
	if category == "color" and texture_mode:
		for item in library.textures:
			if search.text.to_lower() in str(item.name).to_lower():
				ids.append(item.id)
	else:
		for id in catalog:
			var data = catalog[id]
			if typeof(data) != TYPE_DICTIONARY or data.get("type", "") != category:
				continue
			if not search.text.empty() and not search.text.to_lower() in (str(data.get("name", id)) + str(id)).to_lower():
				continue
			if browser_mode == "Favorites" and not library.favorites.has(id):
				continue
			if browser_mode == "Recent" and not library.recent.has(id):
				continue
			ids.append(id)
		ids.sort()
	var pages = max(1, int(ceil(ids.size() / float(PAGE_SIZE))))
	page_index = int(clamp(page_index, 0, pages - 1))
	paging.text = "%d items · %d / %d" % [ids.size(), page_index + 1, pages]
	for i in range(page_index * PAGE_SIZE, min(ids.size(), (page_index + 1) * PAGE_SIZE)):
		var id = str(ids[i])
		if category == "color" and texture_mode:
			_texture_card(id)
		else:
			_catalog_card(id, catalog[id])
	if ids.empty():
		catalog_grid.add_child(label("No items here yet." if search.text.empty() else "No matching items.", 15, DIM))
	refreshing = false

func _catalog_card(id: String, data: Dictionary) -> void:
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(166, 0)
	panel.add_stylebox_override("panel", style(PANEL, ACCENT if sandbox.selected_cosmetics.has(id) else LINE))
	catalog_grid.add_child(panel)
	var c = column(panel)
	var scene = load(sandbox.COSMETIC_CARD_SCENE_PATH)
	if scene is PackedScene:
		var holder = Control.new()
		holder.rect_min_size = Vector2(144, 180)
		c.add_child(holder)
		var card = scene.instance()
		card.rect_scale = Vector2(0.64, 0.64)
		holder.add_child(card)
		card.call("show_cosmetic", id, {"unlocked": true})
		card.connect("button_pressed", self, "equip", [id])
		for name in ["bg", "bg_unlocked", "border", "border_locked", "progress", "unlock_alert"]:
			var ornament = card.get(name)
			if ornament is CanvasItem:
				ornament.hide()
		var spine = card.get("goober")
		if spine != null:
			sandbox.call("studio_freeze_avatar", spine)
	var name_label = label(str(data.get("name", id)), 14)
	name_label.clip_text = true
	name_label.hint_tooltip = str(data.get("name", id))
	c.add_child(name_label)
	var r = row(c)
	r.add_child(button("Remove" if sandbox.selected_cosmetics.has(id) else "Equip", "equip", [id]))
	r.add_child(button("★" if library.favorites.has(id) else "☆", "favorite", [id]))

func equip(id: String) -> void:
	var catalog = sandbox.call("_all_cosmetics")
	var data = catalog.get(id, {})
	if data.empty():
		return
	var type = str(data.get("type", ""))
	var was_equipped = sandbox.selected_cosmetics.has(id)
	sandbox.call("_remove_selected_type", type)
	if not was_equipped:
		sandbox.selected_cosmetics.append(id)
		_remember(id)
	if type == "color":
		sandbox.custom_color_enabled = false
	sandbox.sandbox_enabled = true
	if type == "emote":
		selected_emote = str(data.get("dance", "")) if not was_equipped else ""
	sandbox.call("_commit_change", true)
	if type == "emote" and not was_equipped:
		selected_emote = str(data.get("dance", ""))
		if not selected_emote.empty():
			_animate(selected_emote)
		else:
			status.text = "This emote has a card animation only; it cannot animate the full avatar."
	call_deferred("rebuild_catalog")

func _transform_id() -> String:
	var catalog = sandbox.call("_all_cosmetics")
	for id in sandbox.selected_cosmetics:
		if catalog.get(id, {}).get("type", "") == category:
			return id
	return ""

func _refresh_transforms() -> void:
	if transform_controls == null:
		return
	transform_controls.visible = category in ["hat", "suit", "hand"]
	var id = _transform_id()
	var state = item_transforms.get(id, {})
	var compatible = not id.empty()
	if compatible and is_instance_valid(goober):
		var data = sandbox.call("_all_cosmetics").get(id, {})
		var skin = goober.skeleton_data_res.find_skin(str(data.get("spine", "")))
		compatible = skin != null and not skin.get_attachments().empty()
	editing_transform = true
	for key in transform_fields:
		transform_fields[key].editable = compatible
		transform_fields[key].value = state.get(key, 1.0 if key == "scale" else 0.0)
	editing_transform = false
	transform_note.text = "Equip an item above first." if id.empty() else "Adjusting: " + str(sandbox.call("_all_cosmetics").get(id, {}).get("name", id))
	if not id.empty() and not compatible:
		transform_note.text = "This item has no compatible transformable artwork."

func _transform_changed(value: float, key: String) -> void:
	if editing_transform:
		return
	var id = _transform_id()
	if id.empty():
		return
	if not item_transforms.has(id):
		if item_transforms.size() >= 64:
			status.text = "64 item adjustments saved. Reset an old item before adding another."
			return
		item_transforms[id] = {}
	item_transforms[id][key] = value
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)

func _reset_transform(part: String) -> void:
	var id = _transform_id()
	if not item_transforms.has(id):
		return
	if part == "all":
		item_transforms.erase(id)
	elif part == "position":
		item_transforms[id].erase("x")
		item_transforms[id].erase("y")
	else:
		item_transforms[id].erase(part)
	sandbox.call("_commit_change", false)
	_refresh_transforms()

func capture() -> Dictionary:
	return {"version": 3, "selected": sandbox.selected_cosmetics.duplicate(), "base": sandbox.include_profile_base, "enabled": sandbox.sandbox_enabled, "custom": sandbox.custom_color_enabled, "color": sandbox.custom_color.to_html(false), "texture": current_texture, "emote": selected_emote, "effects": effect_settings.duplicate(true), "transforms": item_transforms.duplicate(true)}

func same_state(a: Dictionary, b: Dictionary) -> bool:
	var left = []
	var right = []
	for key in ["selected", "base", "enabled", "custom", "color", "texture", "emote", "effects", "transforms"]:
		left.append(a.get(key))
		right.append(b.get(key))
	return JSON.print(left) == JSON.print(right)

func changed() -> void:
	if restoring or sandbox == null:
		return
	var next = capture()
	SavedSettings.set_value("studio_movement_effects", effect_settings.duplicate(true))
	SavedSettings.set_value("studio_movement_effects_enabled", sandbox.sandbox_enabled)
	if not working.empty() and not same_state(next, working):
		history.append(working.duplicate(true))
		if history.size() > 50:
			history.pop_front()
		future.clear()
	working = next
	preview_skin_override.clear()
	library["working"] = working
	_save()
	refresh()

func _restore(state: Dictionary) -> void:
	restoring = true
	preview_skin_override.clear()
	sandbox.selected_cosmetics = state.get("selected", []).duplicate()
	sandbox.include_profile_base = bool(state.get("base", false))
	sandbox.sandbox_enabled = bool(state.get("enabled", true))
	sandbox.custom_color_enabled = bool(state.get("custom", false))
	sandbox.custom_color = Color(str(state.get("color", "40b8ff")))
	current_texture = str(state.get("texture", "default"))
	selected_emote = str(state.get("emote", ""))
	item_transforms = state.get("transforms", {}).duplicate(true)
	effect_settings = state.get("effects", {"dash": "default", "trail": "default", "color": "9dd6bd"}).duplicate(true)
	SavedSettings.set_value("studio_movement_effects", effect_settings.duplicate(true))
	SavedSettings.set_value("studio_movement_effects_enabled", sandbox.sandbox_enabled)
	sandbox.call("_commit_change", true)
	restoring = false
	working = capture()
	refresh()

func undo() -> void:
	if history.empty():
		return
	future.append(capture())
	_restore(history.pop_back())
	_save()
	rebuild_catalog()

func redo() -> void:
	if future.empty():
		return
	history.append(capture())
	_restore(future.pop_back())
	_save()
	rebuild_catalog()

func refresh() -> void:
	if summary == null:
		return
	_refresh_transforms()
	picker.color = sandbox.custom_color
	effect_color.color = Color(str(effect_settings.get("color", "9dd6bd")))
	var catalog = sandbox.call("_all_cosmetics")
	var names = []
	for id in sandbox.selected_cosmetics:
		names.append(str(catalog.get(id, {}).get("name", id)))
	summary.text = " · ".join(names) if not names.empty() else "Profile appearance"
	if not current_look.empty():
		var saved = _find_look(current_look)
		if not saved.empty():
			status.text = str(saved.name) + (" · Modified" if not same_state(saved.state, capture()) else " · Saved")
	_rebuild_palette()
	if preview_skin_override.empty() and goober != null and sandbox.get("_modal_root").visible:
		_render_look(goober, capture())
	if status.text.empty():
		status.text = "Local appearance " + ("on" if sandbox.sandbox_enabled else "off") + " · Profile base " + ("included" if sandbox.include_profile_base else "hidden")

func _toggle_local() -> void:
	sandbox.sandbox_enabled = not sandbox.sandbox_enabled
	status.text = "Local appearance " + ("on" if sandbox.sandbox_enabled else "off")
	sandbox.call("_commit_change", false)

func _toggle_base() -> void:
	sandbox.include_profile_base = not sandbox.include_profile_base
	status.text = "Profile base " + ("included" if sandbox.include_profile_base else "hidden")
	sandbox.call("_commit_change", true)

func _reset_appearance() -> void:
	sandbox.selected_cosmetics.clear()
	sandbox.custom_color_enabled = false
	sandbox.sandbox_enabled = false
	sandbox.include_profile_base = true
	current_texture = "default"
	selected_emote = ""
	effect_settings = {"dash": "default", "trail": "default", "color": "9dd6bd"}
	SavedSettings.set_value("studio_movement_effects", effect_settings.duplicate(true))
	current_look = ""
	sandbox.call("_commit_change", true)
	rebuild_catalog()

func _color_changed(value: Color) -> void:
	sandbox.call("_on_custom_color_changed", value)

func _copy_color() -> void:
	OS.clipboard = "#" + sandbox.custom_color.to_html(false)
	status.text = "Color copied."

func _paste_color() -> void:
	var value = OS.clipboard.strip_edges().trim_prefix("#")
	if value.length() != 6 or not value.is_valid_hex_number(false):
		status.text = "Paste a six-digit HEX color."
		return
	_color_changed(Color(value))

func _reset_color() -> void:
	sandbox.custom_color_enabled = false
	sandbox.call("_commit_change", true)

func _save_color() -> void:
	var hex = sandbox.custom_color.to_html(false)
	library.colors.erase(hex)
	library.colors.push_front(hex)
	if library.colors.size() > 12:
		library.colors.pop_back()
	_save()
	_rebuild_palette()

func _rebuild_palette() -> void:
	for child in color_palette.get_children():
		child.queue_free()
	for hex in library.colors:
		var b = button(" ", "_color_changed", [Color(hex)])
		b.rect_min_size = Vector2(28, 28)
		b.add_stylebox_override("normal", style(Color(hex)))
		b.hint_tooltip = "#" + hex
		color_palette.add_child(b)

func _remember(id: String) -> void:
	library.recent.erase(id)
	library.recent.push_front(id)
	if library.recent.size() > 60:
		library.recent.pop_back()

func favorite(id: String) -> void:
	if library.favorites.has(id):
		library.favorites.erase(id)
	else:
		library.favorites.append(id)
	_save()
	call_deferred("rebuild_catalog")

func _page_delta(delta: int) -> void:
	page_index += delta
	rebuild_catalog()

func _remove_category() -> void:
	sandbox.call("_remove_selected_type", category)
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", true)
	rebuild_catalog()

func randomize_appearance(all_categories: bool = true) -> void:
	var catalog = sandbox.call("_all_cosmetics")
	for entry in CATEGORIES:
		var type = entry[0]
		if type == "emote" or (not all_categories and type != category):
			continue
		var pool = []
		for id in catalog:
			if catalog[id].get("type", "") == type:
				pool.append(id)
		sandbox.call("_remove_selected_type", type)
		if not pool.empty():
			sandbox.selected_cosmetics.append(pool[randi() % pool.size()])
	sandbox.custom_color_enabled = false
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", true)
	rebuild_catalog()

func _texture(id: String) -> void:
	current_texture = id
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)
	status.text = "Texture: " + id

func _show_texture_import() -> void:
	file_dialog.popup_centered_ratio(0.65)

func _import_texture(path: String) -> void:
	if library.textures.size() >= 24:
		status.text = "Texture library is full (24 imports)."
		return
	var f = File.new()
	if path.get_extension().to_lower() != "png" or f.open(path, File.READ) != OK:
		status.text = "Choose a PNG image."
		return
	var length = f.get_len()
	var header = f.get_buffer(24)
	f.close()
	if length > 8 * 1024 * 1024 or header.size() < 24 or header[0] != 137 or header[1] != 80 or header[2] != 78 or header[3] != 71:
		status.text = "Invalid PNG, or file exceeds 8 MB."
		return
	var width = int(header[16]) * 16777216 + int(header[17]) * 65536 + int(header[18]) * 256 + int(header[19])
	var height = int(header[20]) * 16777216 + int(header[21]) * 65536 + int(header[22]) * 256 + int(header[23])
	if width < 8 or height < 8 or width > 4096 or height > 4096:
		status.text = "Texture dimensions must be between 8 and 4096 pixels."
		return
	var image = Image.new()
	if image.load(path) != OK:
		status.text = "The PNG could not be decoded."
		return
	image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var directory = Directory.new()
	directory.make_dir_recursive(TEXTURE_DIR)
	var id = "import_" + str(OS.get_unix_time()) + "_" + str(randi())
	if image.save_png(TEXTURE_DIR.plus_file(id + ".png")) != OK:
		status.text = "Could not save the texture."
		return
	library.textures.append({"id": id, "name": path.get_file().get_basename(), "source": "imported"})
	_texture(id)
	rebuild_catalog()

func _texture_card(id: String) -> void:
	var c = column(catalog_grid)
	var image = TextureRect.new()
	image.rect_min_size = Vector2(150, 120)
	image.expand = true
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = _load_texture(id)
	c.add_child(image)
	var title = id
	for data in library.textures:
		if data.id == id:
			title = data.name
	var b = button(title, "_texture", [id])
	b.clip_text = true
	c.add_child(b)
	c.add_child(label("Imported · local", 12, DIM))
