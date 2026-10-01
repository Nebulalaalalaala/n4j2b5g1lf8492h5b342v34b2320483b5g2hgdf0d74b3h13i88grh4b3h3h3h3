extends "user://mod/tools/avatar-studio/AvatarStudio/03_color_texture.gd"

func _load_texture(id: String) -> Texture:
	if texture_cache.has(id):
		return texture_cache[id]
	if not id.begins_with("import_") or "/" in id or "\\" in id or ":" in id or ".." in id:
		return null
	var image = Image.new()
	var path = TEXTURE_DIR.plus_file(id + ".png")
	if not File.new().file_exists(path) or image.load(path) != OK:
		return null
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_REPEAT)
	texture_cache[id] = texture
	return texture

func apply_effects(target, texture_id: String = "") -> void:
	_apply_texture(target, texture_id)
	if target == null or not is_instance_valid(target):
		return
	apply_avatar_size(target)
	var renderer = target.get_node_or_null("LocalCosmeticTransforms")
	if renderer == null and not item_transforms.empty():
		if transform_script == null:
			transform_script = load(ModPaths.COSMETIC_TRANSFORMS)
		if transform_script == null:
			return
		renderer = transform_script.new()
		renderer.name = "LocalCosmeticTransforms"
		target.add_child(renderer)
	if renderer != null:
		renderer.configure(target, item_transforms, sandbox.call("_all_cosmetics"))
	var layers = target.get_node_or_null("LocalCosmeticLayers")
	if layers == null:
		layers = load(ModPaths.path("CosmeticLayers.gd")).new()
		layers.name = "LocalCosmeticLayers"
		target.add_child(layers)
	layers.configure(target,sandbox,sandbox.selected_cosmetics,item_transforms)

func _size_entered(text: String) -> void:
	if restoring or rendering_look: return
	var number = text.strip_edges().trim_suffix("%").strip_edges()
	if not number.is_valid_float() or is_nan(float(number)) or is_inf(float(number)):
		size_control.get_line_edit().text = str(avatar_size * 100.0) + " %"
		return
	# Explicit numeric parsing also works when native SpinBox expression parsing
	# is unavailable in the custom game build. Never interpret a partial edit.
	var percent = clamp(float(number), size_control.min_value, size_control.max_value)
	size_control.value = percent
	_set_avatar_size(size_control.value)
	size_control.get_line_edit().text = str(size_control.value) + " %"

func _size_focus_exit() -> void:
	_size_entered(size_control.get_line_edit().text)

func _set_avatar_size(value: float) -> void:
	if restoring or rendering_look or is_nan(value) or is_inf(value): return
	var next_size = clamp(value/100.0,0.1,100.0)
	if is_equal_approx(next_size, avatar_size): return
	preview_skin_override = {}
	avatar_size = next_size
	sandbox.sandbox_enabled = true
	sandbox.call("_commit_change",false)
	_position_preview()

func apply_avatar_size(target) -> void:
	if target == goober:
		_position_preview()
		return
	var previous: float = float(target.get_meta("studio_size")) if target.has_meta("studio_size") else 1.0
	target.scale = target.scale / max(0.1,previous) * avatar_size
	target.set_meta("studio_size",avatar_size)

func _apply_texture(target, texture_id: String = "") -> void:
	if target == null or not is_instance_valid(target):
		return
	var id = current_texture if texture_id.empty() else texture_id
	if id == "default":
		return
	if id.begins_with("import_") and _load_texture(id) == null:
		return
	var base = target.get("normal_material")
	if not (base is ShaderMaterial):
		return
	if base.shader == shader:
		return
	var key = str(base.get_instance_id()) + id
	var material = shader_cache.get(key, null)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_param("gradient", base.get_shader_param("gradient"))
		material.set_shader_param("pattern", {"dots": 1, "stripes": 2, "grid": 3}.get(id, 4))
		material.set_shader_param("pattern_image", _load_texture(id))
		shader_cache[key] = material
		if shader_cache.size() > 64:
			shader_cache.clear()
	target.set("normal_material", material)
	target.set("gradient_material", material)
	var skeleton = target.call("get_skeleton")
	if skeleton == null:
		return
	for slot in skeleton.get_slots():
		var attachment = slot.get_attachment()
		if attachment != null and "body-tint" in attachment.get_attachment_name().to_lower():
			var tint = slot.get_color()
			tint.b = 0.5
			slot.set_color(tint)

func _find_look(id: String) -> Dictionary:
	for look in library.looks:
		if look.id == id:
			return look
	return {}

func save_look(update: bool = false) -> void:
	if not update and library.looks.size() >= 40:
		status.text = "40 Looks saved. Delete a Look before adding another."
		return
	var name = look_name.text.strip_edges()
	if name.empty():
		name = "Untitled look"
	var look = _find_look(current_look) if update else {}
	if update and look.empty():
		status.text = "Equip a saved Look first, or choose Save as new."
		return
	if look.empty():
		look = {"id": str(OS.get_unix_time()) + "_" + str(randi()), "favorite": false, "created": OS.get_unix_time()}
		library.looks.append(look)
	look["name"] = name
	look["state"] = capture()
	look["updated"] = OS.get_unix_time()
	current_look = look.id
	_save()
	_build_look_cards()
	status.text = "Saved " + name

func _build_look_cards() -> void:
	for child in looks_grid.get_children():
		child.hide()
		child.queue_free()
	look_previews.clear()
	if library.looks.empty():
		looks_grid.add_child(label("Your first Look starts here. Name your outfit and save it.", 15, DIM))
		return
	for look in library.looks:
		var panel = PanelContainer.new()
		panel.rect_min_size.x = 252
		panel.add_stylebox_override("panel", style(PANEL, ACCENT if look.id == current_look else LINE))
		looks_grid.add_child(panel)
		var c = column(panel)
		var holder = Control.new()
		holder.rect_min_size = Vector2(220, 190)
		c.add_child(holder)
		var scene = load(sandbox.GOOBER_SCENE_PATH)
		if scene is PackedScene:
			var avatar = scene.instance()
			avatar.position = Vector2(110, 180)
			avatar.scale = Vector2(-0.10, 0.10)
			avatar.enable_sounds = false
			avatar.enable_blink = false
			holder.add_child(avatar)
			_render_look(avatar, look.state)
			sandbox.call("studio_freeze_avatar", avatar)
			look_previews.append(avatar)
		var name_field = LineEdit.new()
		name_field.text = str(look.name)
		name_field.max_length = 60
		name_field.hint_tooltip = "Press Enter to rename"
		name_field.add_font_override("font", font(15))
		name_field.connect("text_entered", self, "_rename_look", [look.id])
		c.add_child(name_field)
		var actions = row(c)
		actions.add_child(button("Equip", "_equip_look", [look.id]))
		actions.add_child(button("Preview", "_preview_look", [look.id]))
		actions.add_child(button("★" if look.favorite else "☆", "_favorite_look", [look.id]))
		var other = row(c)
		other.add_child(button("Duplicate", "_duplicate_look", [look.id]))
		other.add_child(button("Export", "_export_look", [look.id]))
		other.add_child(button("Delete", "_delete_look", [look.id]))

func _render_look(target, state: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var before = capture()
	var selected = sandbox.selected_cosmetics
	sandbox.selected_cosmetics = state.get("selected", []).duplicate()
	sandbox.include_profile_base = bool(state.get("base", false))
	sandbox.custom_color_enabled = bool(state.get("custom", false))
	sandbox.custom_color = Color(str(state.get("color", "40b8ff")))
	current_texture = str(state.get("texture", "default"))
	rendering_look = true
	item_transforms = state.get("transforms", {}).duplicate(true)
	avatar_size = float(state.get("avatar_size",1.0))
	sandbox.call("_apply_to_goober", target, sandbox.call("_build_local_skin"))
	rendering_look = false
	current_texture = before.texture
	item_transforms = before.transforms
	avatar_size = before.avatar_size
	sandbox.selected_cosmetics = selected
	sandbox.include_profile_base = before.base
	sandbox.custom_color_enabled = before.custom
	sandbox.custom_color = Color(before.color)

func _equip_look(id: String) -> void:
	var look = _find_look(id)
	if look.empty():
		return
	history.append(capture())
	future.clear()
	current_look = id
	_restore(look.state)
	look_name.text = look.name
	_save()
	_build_look_cards()

func _preview_look(id: String) -> void:
	var look = _find_look(id)
	if not look.empty():
		preview_skin_override = look.state.duplicate(true)
		_render_look(goober, look.state)
		status.text = "Previewing " + look.name + " · choose Equip to keep it, or Customize to return."

func _rename_look(name: String, id: String) -> void:
	var look = _find_look(id)
	if not look.empty() and not name.strip_edges().empty():
		look.name = name.strip_edges().substr(0, 60)
		_save()

func _duplicate_look(id: String) -> void:
	if library.looks.size() >= 40:
		status.text = "40 Looks saved. Delete a Look before adding another."
		return
	var source = _find_look(id)
	if source.empty():
		return
	var copy = source.duplicate(true)
	copy.id = str(OS.get_unix_time()) + "_" + str(randi())
	copy.name += " remix"
	library.looks.append(copy)
	_save()
	_build_look_cards()

func _favorite_look(id: String) -> void:
	var look = _find_look(id)
	if not look.empty():
		look.favorite = not look.favorite
		_save()
		_build_look_cards()

func _delete_look(id: String) -> void:
	var look = _find_look(id)
	if look.empty(): return
	var host = sandbox.get("_modal_root")
	if host.get_node_or_null("StudioLookConfirmation") != null: return
	var dialog = load(ModPaths.path("StudioLookConfirmation.gd")).new()
	dialog.name = "StudioLookConfirmation"
	dialog.connect("confirmed", self, "_confirm_delete_look", [id, dialog])
	host.add_child(dialog)
	dialog.build(self, str(look.get("name", "Untitled Look")))

func _confirm_delete_look(id: String, _dialog) -> void:
	var look = _find_look(id)
	if look.empty(): return
	library.looks.erase(look)
	_save()
	_build_look_cards()

func _export_look(id: String) -> void:
	var look = _find_look(id)
	if look.empty():
		return
	OS.clipboard = "AVATAR1:" + Marshalls.utf8_to_base64(JSON.print({"version": 1, "name": look.name, "state": look.state}))
	status.text = "Look code copied." + (" Share the custom PNG separately." if str(look.state.get("texture", "")).begins_with("import_") else "")

func _show_import() -> void:
	import_field.text = ""
	pending_import = {}
	import_dialog.get_ok().disabled = true
	import_dialog.popup_centered(Vector2(560, 320))

func _validate_import() -> void:
	pending_import = {}
	import_dialog.get_ok().disabled = true
	import_feedback.text = "Not a valid Avatar Studio Look code."
	var text = import_field.text.strip_edges()
	if not text.begins_with("AVATAR1:") or text.length() > 32000:
		return
	var encoded = text.trim_prefix("AVATAR1:")
	if not _valid_base64(encoded):
		return
	var decoded = Marshalls.base64_to_utf8(encoded)
	if not decoded.begins_with("{") or not decoded.ends_with("}"):
		return
	var parsed = JSON.parse(decoded)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var value = parsed.result
	if value.get("version", 0) != 1 or not valid_state(value.get("state", null)):
		return
	pending_import = value
	import_dialog.get_ok().disabled = false
	preview_skin_override = value.state.duplicate(true)
	_render_look(goober, value.state)
	status.text = "Import preview: " + str(value.get("name", "Imported look")) + " · appearance unchanged"
	if str(value.state.get("texture", "")).begins_with("import_") and _load_texture(value.state.texture) == null:
		status.text += " · Custom texture required"
	var catalog = sandbox.call("_all_cosmetics")
	var missing = 0
	for id in value.state.selected:
		if not catalog.has(id):
			missing += 1
	if missing > 0:
		status.text += " · %d unavailable items will be skipped" % missing
	import_feedback.text = status.text

func _valid_base64(encoded: String) -> bool:
	# Goober Dash's custom engine omits the optional regex module.
	if encoded.empty() or encoded.length() % 4 != 0:
		return false
	var padding = 0
	var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for index in range(encoded.length()):
		var character = encoded.substr(index, 1)
		if character == "=":
			padding += 1
			if padding > 2 or index < encoded.length() - 2:
				return false
		elif padding > 0 or alphabet.find(character) < 0:
			return false
	return true

func _confirm_import() -> void:
	if pending_import.empty():
		return
	if library.looks.size() >= 40:
		status.text = "40 Looks saved. Delete a Look before importing another."
		return
	library.looks.append({"id": str(OS.get_unix_time()) + "_" + str(randi()), "name": str(pending_import.get("name", "Imported look")).substr(0, 60), "state": pending_import.state.duplicate(true), "favorite": false, "created": OS.get_unix_time(), "updated": OS.get_unix_time()})
	_save()
	_build_look_cards()
	status.text = "Imported to Looks. Equip when ready."

func valid_state(value) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not value.get("version", 0) in [1, 2, 3]:
		return false
	if transform_script == null:
		transform_script = load(ModPaths.COSMETIC_TRANSFORMS)
	if transform_script == null or not transform_script.valid(value.get("transforms", {})):
		return false
	var effects = value.get("effects", {})
	if not effects is Dictionary:
		return false
	if not effects.get("dash", "default") in ["default", "none", "sparks", "stars"] or not effects.get("trail", "default") in ["default", "none", "soft", "stars"]:
		return false
	var effect_hex = effects.get("color", "9dd6bd")
	if not effect_hex is String or effect_hex.length() != 6 or not effect_hex.is_valid_hex_number(false):
		return false
	if typeof(value.get("selected", null)) != TYPE_ARRAY or value.selected.size() > 64:
		return false
	for id in value.selected:
		if typeof(id) != TYPE_STRING or id.length() > 160:
			return false
	var counts = {}
	var catalog = sandbox._all_cosmetics()
	for id in value.selected:
		var kind = str(catalog.get(id,{}).get("type",""))
		if kind in ["hat","suit"]:
			counts[kind] = int(counts.get(kind,0))+1
			if counts[kind] > 8: return false
	var color = value.get("color", "")
	if typeof(color) != TYPE_STRING or color.length() != 6 or not color.is_valid_hex_number(false):
		return false
	var texture = value.get("texture", "default")
	if typeof(texture) != TYPE_STRING or texture.length() > 100 or "/" in texture or "\\" in texture or ".." in texture or ":" in texture:
		return false
	for key in ["base", "enabled", "custom"]:
		if typeof(value.get(key, true)) != TYPE_BOOL:
			return false
	if typeof(value.get("emote", "")) != TYPE_STRING or str(value.get("emote", "")).length() > 160:
		return false
	var size = value.get("avatar_size",1.0)
	if not typeof(size) in [TYPE_INT,TYPE_REAL] or is_nan(float(size)) or is_inf(float(size)) or size < 0.1 or size > 100:
		return false
	return true

func _migrate_looks() -> void:
	if library.get("legacy_imported", false):
		return
	var legacy = tool_ref.get("_cosmetic_loadouts")
	if legacy == null:
		return
	for look in legacy.get("_loadouts"):
		if typeof(look) != TYPE_DICTIONARY or look.empty():
			continue
		var selected = look.get("skin", {}).values()
		for emote in look.get("emotes", []):
			if not str(emote).empty():
				selected.append(emote)
		library.looks.append({"id": "legacy_" + str(library.looks.size()), "name": str(look.get("name", "Imported loadout")), "state": {"version": 1, "selected": selected, "base": false, "enabled": true, "custom": false, "color": "40b8ff", "texture": "default", "emote": ""}, "favorite": false, "created": OS.get_unix_time(), "updated": OS.get_unix_time()})
	library["legacy_imported"] = true
	_save()

func _load() -> void:
	var f = File.new()
	if f.open(DATA_PATH, File.READ) != OK:
		return
	if f.get_len() > 2 * 1024 * 1024:
		f.close()
		return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY or parsed.result.get("version", 0) != 1:
		return
	for key in ["looks", "favorites", "recent", "colors", "textures"]:
		if typeof(parsed.result.get(key, null)) == TYPE_ARRAY:
			library[key] = parsed.result[key]
	library.looks = library.looks.slice(0, 39) if library.looks.size() > 40 else library.looks
	var valid_looks = []
	for look in library.looks:
		if typeof(look) == TYPE_DICTIONARY and valid_state(look.get("state", null)) and typeof(look.get("id")) == TYPE_STRING and typeof(look.get("name")) == TYPE_STRING and typeof(look.get("favorite")) == TYPE_BOOL:
			valid_looks.append(look)
	library.looks = valid_looks
	for key in ["favorites", "recent", "colors"]:
		var safe = []
		for value in library[key]:
			if typeof(value) == TYPE_STRING and value.length() <= 160:
				if key != "colors" or (value.length() == 6 and value.is_valid_hex_number(false)):
					safe.append(value)
			if safe.size() >= (12 if key == "colors" else 200):
				break
		library[key] = safe
	var safe_textures = []
	for value in library.textures:
		if typeof(value) == TYPE_DICTIONARY and typeof(value.get("id")) == TYPE_STRING and typeof(value.get("name")) == TYPE_STRING:
			if str(value.id).begins_with("import_") and not "/" in value.id and not "\\" in value.id and not ".." in value.id and not ":" in value.id:
				safe_textures.append(value)
		if safe_textures.size() >= 24:
			break
	library.textures = safe_textures
	if valid_state(parsed.result.get("working", null)):
		library["working"] = parsed.result.working
	library["legacy_imported"] = bool(parsed.result.get("legacy_imported", false))

func _save() -> void:
	library["working"] = capture()
	var f = File.new()
	if f.open(DATA_PATH + ".tmp", File.WRITE) != OK:
		return
	f.store_string(JSON.print(library))
	f.close()
	var directory = Directory.new()
	if directory.file_exists(DATA_PATH):
		directory.copy(DATA_PATH, DATA_PATH + ".bak")
		directory.remove(DATA_PATH)
	directory.rename(DATA_PATH + ".tmp", DATA_PATH)

func _zoom(amount: float) -> void:
	zoom = max(0.05, zoom * (1.0 + amount))
	zoom_control.set_block_signals(true)
	zoom_control.value = zoom * 100.0
	zoom_control.set_block_signals(false)
	_position_preview()

func _set_zoom_percent(value: float) -> void:
	zoom = max(0.05, value / 100.0)
	_position_preview()

func _face(direction: float) -> void:
	facing = direction
	_position_preview()

func _reset_view() -> void:
	preview_pan = Vector2.ZERO
	zoom = 1.0
	zoom_control.set_block_signals(true)
	zoom_control.value = 100
	zoom_control.set_block_signals(false)
	tilt = 0.0
	facing = -1.0
	_position_preview()

func _position_preview() -> void:
	if goober == null or stage == null:
		return
	if not playable:
		goober.position = Vector2(stage.rect_size.x / 2, stage.rect_size.y - 65) + preview_pan
	var fitted_scale = min(0.21, max(0.05, (stage.rect_size.y - 90.0) / 2200.0))
	var displayed_size = float(preview_skin_override.get("avatar_size", avatar_size))
	goober.scale = Vector2(facing, 1) * fitted_scale * zoom * displayed_size
	goober.rotation_degrees = tilt
	stage.pan = Vector2.ZERO if playable else preview_pan
	stage.update()

func _animate(name: String) -> void:
	if goober == null:
		return
	var resource = goober.get("skeleton_data_res")
	if resource != null and resource.has_method("find_animation") and resource.call("find_animation", name) == null:
		status.text = "Animation unavailable: " + name
		return
	animation = name
	animation_paused = false
	var state = goober.call("get_animation_state")
	if state != null:
		state.set_animation(name, animation_loop, 0)
		if state.has_method("set_time_scale"):
			state.call("set_time_scale", 1.0)
