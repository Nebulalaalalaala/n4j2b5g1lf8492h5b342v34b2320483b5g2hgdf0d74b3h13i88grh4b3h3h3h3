extends "user://mod/tools/avatar-studio/AvatarStudio/02_preview_font.gd"

var columns_changed_ms = 0
var columns_width = 0.0
var columns_rebuild_queued = false

func _goober_mode(value: bool) -> void:
	effects_mode = false
	texture_mode = value
	page_index = 0
	if value:
		_sync_imported_textures()
		sandbox.call("_commit_change",false)
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
	columns_rebuild_queued = false
	if catalog_grid == null or refreshing:
		return
	if not catalog_grid.is_visible_in_tree():
		_catalog_dirty = true
		return
	_catalog_dirty = false
	refreshing = true
	if texture_count_label != null:
		texture_count_label.text = "%d / %d imports" % [library.textures.size(),TextureLibrary.LIMIT]
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
					choice.add_stylebox_override("normal", style(Color("3a2f6b") if effect_settings.get(entry[0], "") == entry[1] else PANEL))
		paging.text = "Dash: %s Â· Trail: %s" % [effect_settings.dash.capitalize(), effect_settings.trail.capitalize()]
		refreshing = false
		return
	for key in category_buttons:
		category_buttons[key].add_stylebox_override("normal", style(Color("3a2f6b") if key == category else PANEL))
	inspector.text = "Cosmetic held items only." if category == "hand" else ""
	if category in ["hat", "suit", "hand"]:
		inspector.text += " Equip an item to adjust its position, rotation and scale."
	if category == "emote":
		inspector.text = "Equip multiple emotes. Studio emotes play locally from the emote wheel."
	if category == "effect":
		inspector.text = "Local only. Equip as many as you like."
	var catalog: Dictionary = sandbox.call("_all_cosmetics")
	var ids = []
	if category == "color" and texture_mode:
		for item in library.textures:
			if search.text.empty() or search.text.to_lower() in str(item.name).to_lower():
				ids.append(item.id)
		if ids.has(current_texture):
			ids.erase(current_texture)
			ids.push_front(current_texture)
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
		if dev_match != null:
			ids = dev_match.order(ids, category)
		# Level rewards first, like the newest section of the native grid.
		var rewards = []
		for id in ids:
			if CustomCosmetics.is_custom(id):
				rewards.append(id)
		for id in rewards:
			ids.erase(id)
		ids = rewards + ids
	_fit_catalog_columns()
	var page_size = _page_size()
	var pages = max(1, int(ceil(ids.size() / float(page_size))))
	page_index = int(clamp(page_index, 0, pages - 1))
	paging.text = "%d items Â· %d / %d" % [ids.size(), page_index + 1, pages]
	for i in range(page_index * page_size, min(ids.size(), (page_index + 1) * page_size)):
		var id = str(ids[i])
		if category == "color" and texture_mode:
			_texture_card(id)
		else:
			_catalog_card(id, catalog[id])
	if ids.empty():
		catalog_grid.add_child(label("No items here yet." if search.text.empty() else "No matching items.", 15, DIM))
	refreshing = false

# Columns fill the width (no empty strip beside the cards); Compact shows
# smaller cards so more fit on a page.
func _card_width() -> float:
	return 118.0 if compact_grid else 166.0

func _fit_catalog_columns() -> void:
	if catalog_grid == null or customize == null:
		return
	if compact_button != null:
		compact_button.text = "Large cards" if compact_grid else "Compact"
		compact_button.hint_tooltip = "Show fewer, bigger item cards" if compact_grid else "Show more, smaller item cards"
	var width = max(1.0, customize.rect_size.x)
	var columns = int(max(1, floor((width + 8) / (_card_width() + 8 + 4))))
	if columns != catalog_grid.columns:
		# A scrollbar appearing after a rebuild can shrink the width just enough
		# to flip the column count back, which rebuilt the grid forever (crash).
		var now = OS.get_ticks_msec()
		if now - columns_changed_ms < 1500 and abs(width - columns_width) < 48.0:
			return
		columns_changed_ms = now
		columns_width = width
		catalog_grid.columns = columns
		if not refreshing and not columns_rebuild_queued:
			columns_rebuild_queued = true
			call_deferred("rebuild_catalog")

func _page_size() -> int:
	return int(max(PAGE_SIZE, catalog_grid.columns * (5 if compact_grid else 3)))

func _toggle_compact() -> void:
	compact_grid = not compact_grid
	SavedSettings.set_value("avatar_studio_compact_grid", compact_grid)
	page_index = 0
	_fit_catalog_columns()
	rebuild_catalog()

# Effects and unavailable rig items have no native card: show a Goober
# wearing them (effects keep animating on the card).
func _studio_card(c, id: String, data: Dictionary) -> void:
	var holder = Control.new()
	holder.rect_min_size = Vector2(100, 126) if compact_grid else Vector2(144, 180)
	holder.rect_clip_content = true
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(holder)
	var goober = load(sandbox.GOOBER_SCENE_PATH).instance()
	goober.enable_sounds = false
	goober.enable_blink = false
	var size = holder.rect_min_size
	goober.position = Vector2(size.x * 0.5, size.y - 8)
	goober.scale = Vector2.ONE * (size.y / 3000.0)
	holder.add_child(goober)
	sandbox.call("studio_freeze_avatar", goober)
	goober.set_goober_skin_data({"color": "color_default"})
	if data.get("unavailable", false):
		StudioSecrets.wear(goober, str(data.get("spine", "")))
	goober.update_skeleton(0.0)
	var wings = StudioEffects.wing_size([id])
	if wings != "none":
		var node = load(ModPaths.STUDIO_WINGS).new()
		goober.add_child(node)
		node.configure(goober, wings)
	elif StudioEffects.is_effect(id):
		var node = load(ModPaths.STUDIO_EFFECTS).new()
		goober.add_child(node)
		node.configure(goober, [id])
	var hit = Button.new()
	hit.flat = true
	hit.anchor_right = 1.0
	hit.anchor_bottom = 1.0
	hit.connect("pressed", self, "equip", [id])
	holder.add_child(hit)

# Effect options ("..." on an equipped effect): original colours, the
# Goober's colour, or a picked colour.
func _options_key(id: String) -> String:
	return "fx" if StudioEffects.is_effect(id) else "palette"

func effect_options(id: String) -> Dictionary:
	var all = effect_settings.get(_options_key(id), {})
	return all.get(id, {}) if all is Dictionary and all.get(id) is Dictionary else {}

func _effect_menu(id: String) -> void:
	effect_menu_id = id
	if effect_menu == null:
		effect_menu = PopupMenu.new()
		effect_menu.add_font_override("font", font(15))
		effect_menu.add_radio_check_item("Original colors", 0)
		effect_menu.add_radio_check_item("Match Goober color", 1)
		effect_menu.add_radio_check_item("Custom color...", 2)
		effect_menu.connect("id_pressed", self, "_effect_menu_pressed")
		customize.add_child(effect_menu)
	var effect = StudioEffects.is_effect(id)
	effect_menu.set_item_text(1, "Match Goober color" if effect else "Fit to Goober palette")
	effect_menu.set_item_text(2, "Custom color..." if effect else "Fit to a color's palette...")
	var mode = str(effect_options(id).get("mode", "original"))
	for i in 3:
		effect_menu.set_item_checked(i, ["original", "goober", "custom"][i] == mode)
	effect_menu.rect_size = Vector2.ZERO
	effect_menu.rect_global_position = customize.get_global_mouse_position()
	effect_menu.popup()

func _effect_menu_pressed(index: int) -> void:
	var id = effect_menu_id
	var options = effect_options(id).duplicate()
	options["mode"] = ["original", "goober", "custom"][index]
	if not options.has("hex"):
		options["hex"] = "ff5ad2"
	_set_effect_options(id, options)
	if index == 2:
		if effect_picker == null:
			effect_picker = PopupPanel.new()
			var picker_node = ColorPicker.new()
			picker_node.edit_alpha = false
			picker_node.name = "Picker"
			picker_node.connect("color_changed", self, "_effect_color_picked")
			effect_picker.add_child(picker_node)
			customize.add_child(effect_picker)
			# Keep the final colour even if no drag event reached us.
			effect_picker.connect("popup_hide", self, "_effect_picker_closed")
		effect_picker.get_node("Picker").color = Color(str(options.hex))
		effect_picker.rect_global_position = customize.get_global_mouse_position()
		effect_picker.popup()

func _effect_picker_closed() -> void:
	var picked = effect_picker.get_node("Picker").color
	if str(effect_options(effect_menu_id).get("hex", "")) != picked.to_html(false):
		_effect_color_picked(picked)

func _effect_color_picked(color: Color) -> void:
	var options = effect_options(effect_menu_id).duplicate()
	options["mode"] = "custom"
	options["hex"] = color.to_html(false)
	_set_effect_options(effect_menu_id, options)

func _set_effect_options(id: String, options: Dictionary) -> void:
	var key = _options_key(id)
	var all = effect_settings.get(key, {})
	all = all.duplicate(true) if all is Dictionary else {}
	all[id] = options
	effect_settings[key] = all
	status.text = ""
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)

func _catalog_card(id: String, data: Dictionary) -> void:
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(_card_width(), 0)
	panel.add_stylebox_override("panel", style(PANEL, ACCENT if sandbox.selected_cosmetics.has(id) else LINE))
	catalog_grid.add_child(panel)
	var c = column(panel)
	var scene = load(sandbox.COSMETIC_CARD_SCENE_PATH)
	if str(data.get("type", "")) == "effect" or data.get("unavailable", false):
		_studio_card(c, id, data)
	elif scene is PackedScene:
		var holder = Control.new()
		holder.rect_min_size = Vector2(100, 126) if compact_grid else Vector2(144, 180)
		c.add_child(holder)
		var card = scene.instance()
		card.rect_scale = Vector2.ONE * (0.45 if compact_grid else 0.64)
		holder.add_child(card)
		if CustomCosmetics.is_custom(id):
			var shown = CustomCosmetics.carrier(id, Moonlight.storage.storage_get("cosmetics", {}))
			if not shown.empty():
				card.call("show_cosmetic", shown, {"unlocked": true})
				card.call("set_rarity", str(data.get("rarity", "legendary")))
				if str(data.get("type", "")) == "emote":
					CustomCosmetics.patch_emote(card.get("emote_spine"), id)
				elif card.get("goober") != null:
					CustomCosmetics.patch(card.get("goober"), [id])
		else:
			card.call("show_cosmetic", id, {"unlocked": true})
		card.connect("button_pressed", self, "equip", [id])
		for name in ["bg", "bg_unlocked", "border", "border_locked", "progress", "unlock_alert"]:
			var ornament = card.get(name)
			if ornament is CanvasItem:
				ornament.hide()
		var spine = card.get("goober")
		if spine != null:
			sandbox.call("studio_freeze_avatar", spine)
	var tag = ("  Â·  Level %d" % CustomCosmetics.LEVEL) if CustomCosmetics.is_custom(id) else ("  Â·  Unavailable" if data.get("unavailable", false) else "")
	var name_label = label(str(data.get("name", id)) + tag, 14)
	name_label.clip_text = true
	name_label.hint_tooltip = str(data.get("name", id))
	c.add_child(name_label)
	var r = row(c)
	r.add_child(button(("Off" if compact_grid else "Remove") if sandbox.selected_cosmetics.has(id) else "Equip", "equip", [id]))
	r.add_child(button("â˜…" if library.favorites.has(id) else "â˜†", "favorite", [id]))
	var colorable = (StudioEffects.is_effect(id) and StudioEffects.wing_size([id]) == "none") or category in ["hat", "suit", "hand"]
	if sandbox.selected_cosmetics.has(id) and colorable:
		var more = button("...", "_effect_menu", [id])
		more.hint_tooltip = "Color options"
		r.add_child(more)
	if sandbox.selected_cosmetics.has(id) and category in ["hat","suit","hand"] and not CustomCosmetics.is_custom(id):
		r.add_child(button("Adjust", "_select_item", [id]))
	if dev_match != null:
		dev_match.decorate(c, id)

func equip(id: String) -> void:
	print("[AvatarStudio] Outfit change: equip " + id)
	var catalog = sandbox.call("_all_cosmetics")
	var data = catalog.get(id, {})
	if data.empty():
		return
	var type = str(data.get("type", ""))
	var was_equipped = sandbox.selected_cosmetics.has(id)
	if not was_equipped and type in ["hat","suit","hand"]:
		var count = 0
		for selected in sandbox.selected_cosmetics:
			if catalog.get(selected,{}).get("type","") == type: count += 1
		if count >= 8:
			status.text = "8 layers in this category. Remove an item first."
			return
	if type == "color":
		sandbox.call("_remove_selected_type", type)
	elif was_equipped:
		sandbox.selected_cosmetics.erase(id)
	if not was_equipped:
		if sandbox.selected_cosmetics.size() >= 64:
			status.text = "64 items selected. Remove an item first."
			return
		sandbox.selected_cosmetics.append(id)
		_remember(id)
		selected_item = id
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
	if sandbox.selected_cosmetics.has(selected_item) and catalog.get(selected_item,{}).get("type","") == category:
		return selected_item
	for id in sandbox.selected_cosmetics:
		if catalog.get(id, {}).get("type", "") == category:
			return id
	return ""

func _select_item(id: String) -> void:
	selected_item = id
	_refresh_transforms()
	if is_instance_valid(transform_gizmo): transform_gizmo.update()

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
	_refresh_item_texture_controls(id)
	if not id.empty() and not compatible:
		transform_note.text = "This item has no compatible transformable artwork."

# ---------------------------------------------------------------- item textures
func _refresh_item_texture_controls(id: String) -> void:
	if item_texture_imports == null:
		return
	var current = str(item_textures.get(id, ""))
	for key in item_texture_buttons:
		item_texture_buttons[key].disabled = id.empty()
		item_texture_buttons[key].add_stylebox_override("normal", style(Color("3a2f6b") if key == current and not id.empty() else PANEL))
	item_texture_imports.clear()
	item_texture_imports.add_item("Importedâ€¦")
	var selected = 0
	for data in library.textures:
		item_texture_imports.add_item(str(data.name))
		item_texture_imports.set_item_metadata(item_texture_imports.get_item_count() - 1, str(data.id))
		if str(data.id) == current:
			selected = item_texture_imports.get_item_count() - 1
	item_texture_imports.select(selected)
	item_texture_imports.disabled = id.empty() or library.textures.empty()

func _item_texture(texture_id: String) -> void:
	var id = _transform_id()
	if id.empty():
		return
	if texture_id.empty():
		item_textures.erase(id)
	else:
		item_textures[id] = texture_id
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)
	_refresh_item_texture_controls(id)

func _item_texture_import(index: int) -> void:
	if index <= 0:
		return
	_item_texture(str(item_texture_imports.get_item_metadata(index)))

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
	return {"version": 3, "selected": sandbox.selected_cosmetics.duplicate(), "base": sandbox.include_profile_base, "enabled": sandbox.sandbox_enabled, "custom": sandbox.custom_color_enabled, "color": sandbox.custom_color.to_html(false), "texture": current_texture, "emote": selected_emote, "effects": effect_settings.duplicate(true), "transforms": item_transforms.duplicate(true), "avatar_size": avatar_size, "item_textures": item_textures.duplicate()}

func same_state(a: Dictionary, b: Dictionary) -> bool:
	var left = []
	var right = []
	for key in ["selected", "base", "enabled", "custom", "color", "texture", "emote", "effects", "transforms", "avatar_size", "item_textures"]:
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
	print("[AvatarStudio] Outfit change: restore %d items" % state.get("selected", []).size())
	restoring = true
	preview_skin_override.clear()
	sandbox.selected_cosmetics = state.get("selected", []).duplicate()
	_drop_stale_profile_items()
	sandbox.include_profile_base = bool(state.get("base", false))
	sandbox.sandbox_enabled = bool(state.get("enabled", true))
	sandbox.custom_color_enabled = bool(state.get("custom", false))
	sandbox.custom_color = Color(str(state.get("color", "40b8ff")))
	current_texture = str(state.get("texture", "default"))
	selected_emote = str(state.get("emote", ""))
	avatar_size = float(state.get("avatar_size",1.0))
	if size_control != null: size_control.set_value(avatar_size*100)
	item_transforms = state.get("transforms", {}).duplicate(true)
	item_textures = state.get("item_textures", {}).duplicate() if state.get("item_textures") is Dictionary else {}
	effect_settings = state.get("effects", {"dash": "default", "trail": "default", "color": "9dd6bd"}).duplicate(true)
	load("user://mod/core/workspace4/effects/StudioEffectBridge.gd").restore(self,effect_settings)
	# Wings used to be a Dash & Trail setting; they are Effects items now.
	var old_wings = str(effect_settings.get("wings", "none"))
	effect_settings.erase("wings")
	if old_wings in ["small", "medium", "large"] and not sandbox.selected_cosmetics.has("studio_fx_wings_" + old_wings):
		sandbox.selected_cosmetics.append("studio_fx_wings_" + old_wings)
	SavedSettings.set_value("studio_movement_effects", effect_settings.duplicate(true))
	SavedSettings.set_value("studio_movement_effects_enabled", sandbox.sandbox_enabled)
	sandbox.call("_commit_change", true)
	restoring = false
	working = capture()
	refresh()

# One-time cleanup: an old account copy put the profile's own item (the
# balloon) into saved outfits next to the item chosen in the Studio, so both
# were drawn. Drop a profile item when another item of that type is selected.
func _drop_stale_profile_items() -> void:
	if library.get("profile_items_cleaned", false):
		return
	var profile = Moonlight.storage.storage_get("player.profile.skin", {}) if Moonlight.storage != null else {}
	var catalog = sandbox.call("_all_cosmetics")
	if typeof(profile) != TYPE_DICTIONARY or profile.empty() or catalog.empty():
		return
	var own = {}
	for value in profile.values():
		own[str(value)] = true
	var keep = []
	for id in sandbox.selected_cosmetics:
		var kind = str(catalog.get(str(id), {}).get("type", ""))
		var duplicate = false
		if own.has(str(id)) and kind in ["hat", "suit", "hand"]:
			for other in sandbox.selected_cosmetics:
				if str(other) != str(id) and str(catalog.get(str(other), {}).get("type", "")) == kind:
					duplicate = true
		if duplicate:
			print("[AvatarStudio] Removed profile item next to a Studio item: %s" % str(id))
		else:
			keep.append(id)
	sandbox.selected_cosmetics = keep
	library["profile_items_cleaned"] = true
	if library.has("accounts"):
		for key in library.accounts:
			var saved = library.accounts[key].get("selected", [])
			var cleaned = []
			for id in saved:
				var kind = str(catalog.get(str(id), {}).get("type", ""))
				var duplicate = false
				if own.has(str(id)) and kind in ["hat", "suit", "hand"]:
					for other in saved:
						if str(other) != str(id) and str(catalog.get(str(other), {}).get("type", "")) == kind:
							duplicate = true
				if not duplicate:
					cleaned.append(id)
			library.accounts[key]["selected"] = cleaned

func undo() -> void:
	print("[AvatarStudio] Outfit change: undo")
	if history.empty():
		return
	future.append(capture())
	_restore(history.pop_back())
	_save()
	rebuild_catalog()

func redo() -> void:
	print("[AvatarStudio] Outfit change: redo")
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
	summary.text = " Â· ".join(names) if not names.empty() else "Profile appearance"
	if not current_look.empty():
		var saved = _find_look(current_look)
		if not saved.empty():
			status.text = str(saved.name) + (" Â· Modified" if not same_state(saved.state, capture()) else " Â· Saved")
	_rebuild_palette()
	if preview_skin_override.empty() and goober != null and sandbox.get("_modal_root").visible:
		_render_look(goober, capture())
	if status.text.empty():
		status.text = "Local appearance " + ("on" if sandbox.sandbox_enabled else "off") + " Â· Profile base " + ("included" if sandbox.include_profile_base else "hidden")

func _toggle_local() -> void:
	sandbox.sandbox_enabled = not sandbox.sandbox_enabled
	status.text = "Local appearance " + ("on" if sandbox.sandbox_enabled else "off")
	sandbox.call("_commit_change", false)

func _toggle_base() -> void:
	sandbox.include_profile_base = not sandbox.include_profile_base
	status.text = "Profile base " + ("included" if sandbox.include_profile_base else "hidden")
	sandbox.call("_commit_change", true)

func _reset_appearance() -> void:
	print("[AvatarStudio] Outfit change: reset to profile")
	sandbox.selected_cosmetics.clear()
	sandbox.custom_color_enabled = false
	sandbox.sandbox_enabled = false
	sandbox.include_profile_base = true
	current_texture = "default"
	selected_emote = ""
	avatar_size = 1.0
	if size_control != null:
		size_control.set_block_signals(true)
		size_control.set_value(100)
		size_control.set_block_signals(false)
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
	print("[AvatarStudio] Outfit change: randomize")
	var catalog = sandbox.call("_all_cosmetics")
	for entry in CATEGORIES:
		var type = entry[0]
		if type in ["emote", "effect"] or (not all_categories and type != category):
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

# Wears a whole outfit (cosmetic ids) as the local look, e.g. another player's
# profile skin. Emotes stay; undo goes back to the previous look.
func apply_outfit(ids: Array) -> void:
	print("[AvatarStudio] Outfit change: wear outfit %d items" % ids.size())
	var catalog = sandbox.call("_all_cosmetics")
	var state = capture()
	history.append(state.duplicate(true))
	future.clear()
	var selected = []
	for id in ids:
		if catalog.has(str(id)) and str(catalog[str(id)].get("type", "")) == "color" and not selected.has(str(id)):
			selected.append(str(id))
	for id in ids:
		if catalog.has(str(id)) and str(catalog[str(id)].get("type", "")) in ["hat", "suit", "hand"] and not selected.has(str(id)):
			selected.append(str(id))
	for id in state.get("selected", []):
		if str(catalog.get(str(id), {}).get("type", "")) == "emote":
			selected.append(str(id))
	state.selected = selected
	state.base = false
	state.enabled = true
	state.custom = false
	state.texture = "default"
	state.transforms = {}
	state.item_textures = {}
	current_look = ""
	_restore(state)
	_save()
	rebuild_catalog()

func _texture(id: String) -> void:
	current_texture = id
	page_index = 0
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change", false)
	var title = id.capitalize()
	for item in library.textures:
		if str(item.id) == id:
			title = str(item.name)
	status.text = "Texture: " + title
	call_deferred("rebuild_catalog")

func _show_texture_import() -> void:
	if _sync_imported_textures():
		TextureLibrary.save_registry(DATA_PATH,library)
	rebuild_catalog()
	file_dialog.popup_centered_ratio(0.65)

func _import_texture(path: String) -> void:
	if _sync_imported_textures():
		TextureLibrary.save_registry(DATA_PATH,library)
	if library.textures.size() >= TextureLibrary.LIMIT:
		status.text = "24 / 24 imports. Remove a texture to make room."
		return
	if path.get_extension().to_lower() != "png":
		status.text = "Choose a PNG image."
		return
	var decoded = TextureLibrary.read_png(path)
	if not decoded.has("image"):
		status.text = decoded.error
		return
	var directory = Directory.new()
	if directory.make_dir_recursive(TEXTURE_DIR) != OK:
		status.text = "Could not create the texture folder."
		return
	var id = "import_" + str(OS.get_unix_time()) + "_" + str(randi())
	while File.new().file_exists(TEXTURE_DIR.plus_file(id+".png")):
		id += "_"+str(randi())
	if decoded.image.save_png(TEXTURE_DIR.plus_file(id + ".png")) != OK:
		status.text = "Could not save the texture."
		return
	library.textures.append({"id": id, "name": path.get_file().get_basename().substr(0,160), "source": "imported"})
	if not TextureLibrary.save_registry(DATA_PATH,library):
		library.textures.pop_back()
		status.text = "PNG saved, but the library could not be saved. Check folder access, then Refresh."
		return
	category = "color"
	texture_mode = true
	effects_mode = false
	search.set_block_signals(true)
	search.text = ""
	search.set_block_signals(false)
	_texture(id)

func _texture_card(id: String) -> void:
	var c = column(catalog_grid)
	c.set_meta("texture_id",id)
	var image = TextureRect.new()
	image.rect_min_size = Vector2(_card_width() - 16, 90 if compact_grid else 120)
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
	if current_texture == id:
		b.add_stylebox_override("normal",style(Color("3a2f6b"),ACCENT))
	c.add_child(b)
	c.add_child(label("Equipped Â· local" if current_texture == id else "Imported Â· local",12,ACCENT if current_texture == id else DIM))
	var remove = button("Remove", "_remove_texture", [id])
	remove.hint_tooltip = "Remove this imported copy. Your original PNG stays untouched."
	c.add_child(remove)

func _remove_texture(id: String) -> void:
	if not TextureLibrary.valid_id(id): return
	var host = sandbox.get("_modal_root")
	if host.get_node_or_null("StudioTextureConfirmation") != null: return
	var title = "Imported texture"
	for item in library.textures:
		if str(item.id) == id: title = str(item.name)
	var dialog = load(ModPaths.path("StudioLookConfirmation.gd")).new()
	dialog.name = "StudioTextureConfirmation"
	dialog.connect("confirmed",self,"_confirm_remove_texture",[id])
	host.add_child(dialog)
	dialog.build(self,title,{"eyebrow":"IMPORTED TEXTURE","title":"Remove texture?","action":"Remove","note":"Looks using it will show the default pattern.\nYour original PNG will not be changed."})

func _confirm_remove_texture(id: String) -> void:
	if not TextureLibrary.valid_id(id): return
	var path = TEXTURE_DIR.plus_file(id+".png")
	if File.new().file_exists(path) and Directory.new().remove(path) != OK:
		status.text = "Could not remove that imported copy."
		return
	for index in range(library.textures.size()-1,-1,-1):
		if str(library.textures[index].get("id","")) == id:
			library.textures.remove(index)
	texture_cache.erase(id)
	shader_cache.clear()
	if current_texture == id: current_texture = "default"
	for item in item_textures.keys():
		if str(item_textures[item]) == id: item_textures.erase(item)
	sandbox.call("_commit_change",false)
	call_deferred("rebuild_catalog")
	status.text = "Imported texture removed."

func _catalog_visibility_changed() -> void:
	if _catalog_dirty and is_instance_valid(catalog_grid) and catalog_grid.is_visible_in_tree():
		call_deferred("rebuild_catalog")
