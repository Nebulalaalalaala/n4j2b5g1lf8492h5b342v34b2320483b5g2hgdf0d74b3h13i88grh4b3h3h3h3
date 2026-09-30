extends "user://mod/tools/avatar-studio/CosmeticSandbox/01_placeholders.gd"

func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool
	var studio_script = load(ModPaths.AVATAR_STUDIO)
	if studio_script != null and studio_script.can_instance():
		_studio = studio_script.new()
		add_child(_studio)
		_studio.build(self, owner_tool)

func studio_freeze_avatar(avatar) -> void:
	avatar.update_mode = SpineConstant.UpdateMode_Manual
	avatar.update_skeleton(0.0)

func open_studio(section: int = 0) -> void:
	if _studio != null:
		_studio.open(section)
	else:
		_open_modal()


func _ready() -> void:
	layer = 125
	# Timeline Editor preview pauses the whole SceneTree (get_tree().paused =
	# true in TASTool.gd's _begin_macro_editor_preview()) so it can move the
	# freecam without the game simulating underneath it. Every node defaults
	# to PAUSE_MODE_INHERIT, so without this, opening the Sandbox while the
	# Timeline Editor (or any other pause) is active would silently stop
	# receiving input entirely -- mirroring the same fix already applied to
	# TASMacroEditor.gd itself.
	pause_mode = Node.PAUSE_MODE_PROCESS
	# Read the setting directly instead of waiting for TASTool.gd's
	# set_claude_experimental_icons_enabled() call: that call only arrives
	# via a deferred call made at the very end of TASTool.gd's own _ready(),
	# which runs AFTER add_child(_cosmetic_sandbox) already triggered this
	# whole _ready() (including _build_modal() below) -- so every stylebox
	# was actually always being built with the toggle reading as off,
	# regardless of the saved setting, exactly like the same bug found and
	# fixed in ReplayHub.gd. Reading the same saved value straight from
	# SavedSettings here sidesteps that ordering entirely.
	_claude_experimental_icons_enabled = bool(SavedSettings.get_value("client_tools_claude_experimental_icons", false))
	var window_geometry_script = load(WINDOW_GEOMETRY_SCRIPT_PATH)
	if window_geometry_script != null:
		_window_geometry = window_geometry_script.new()
	_title_font = _make_font(42)
	_header_font = _make_font(30)
	_body_font = _make_font(23)
	_small_font = _make_font(19)
	_load_settings()
	_build_modal()
	call_deferred("_initialize_saved_layout")
	if not get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().connect("node_added", self, "_on_tree_node_added")
	call_deferred("_scan_current_scene")
	set_process(true)


func _exit_tree() -> void:
	_restore_all_registered_goobers()
	if get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().disconnect("node_added", self, "_on_tree_node_added")


func _process(delta: float) -> void:
	_sync_modal_resize_grip()
	_process_catalog_retry(delta)
	var scene = get_tree().current_scene
	var scene_id: int = scene.get_instance_id() if scene != null else 0
	if scene_id != _last_scene_id:
		_last_scene_id = scene_id
		_skin_selector = null
		_avatar_button = null
		_gameplay_goober = null
		call_deferred("_scan_current_scene")
	_apply_elapsed += delta
	if _apply_elapsed >= 0.20:
		_apply_elapsed = 0.0
		_cleanup_goober_cache()
		if sandbox_enabled:
			_apply_sandbox_to_registered_goobers()
	if _save_pending:
		_save_delay -= delta
		if _save_delay <= 0.0:
			_save_pending = false
			_save_settings()


func _unhandled_input(event: InputEvent) -> void:
	if _modal_root.visible and event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		_close_modal()
		get_tree().set_input_as_handled()


func set_gui_enabled(value: bool) -> void:
	gui_enabled = value
	if _avatar_button != null and is_instance_valid(_avatar_button):
		_avatar_button.visible = false
	if not value and _modal_root != null:
		_modal_root.visible = false
	if value:
		call_deferred("_scan_current_scene")


# See TASTool.gd's _load_claude_icon() for the full explanation -- same
# loader, duplicated here since this file has no import access to TASTool.gd's
# copy. Resizes the 142x142 source art down to the exact display size with
# high-quality interpolation instead of leaving TextureRect to scale it at
# draw time -- that's what made the first pass look muddy/out of proportion.
# Returns null (never an error) if the icon pack isn't installed.
# The approved icon PNGs are fully opaque 142x142 squares -- the dark tile
# art is baked into the pixels, not a transparent background behind a
# cut-out glyph. This keys out the tile's own fill color to transparent on
# the in-memory copy only (never touches the source PNG on disk), so the
# glyph blends into the modern black panels instead of floating as a chip.
func _strip_icon_background(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	if w < 4 or h < 4:
		return
	image.lock()
	var bg := Color(0, 0, 0)
	var samples := [
		image.get_pixel(1, 1), image.get_pixel(w - 2, 1),
		image.get_pixel(1, h - 2), image.get_pixel(w - 2, h - 2),
		image.get_pixel(w / 2, 1), image.get_pixel(1, h / 2),
	]
	for s in samples:
		bg += s
	bg /= samples.size()
	var threshold := 0.16
	var feather := 0.1
	for y in range(h):
		for x in range(w):
			var px := image.get_pixel(x, y)
			var dist := sqrt(pow(px.r - bg.r, 2) + pow(px.g - bg.g, 2) + pow(px.b - bg.b, 2))
			if dist <= threshold:
				px.a = 0.0
				image.set_pixel(x, y, px)
			elif dist <= threshold + feather:
				px.a = (dist - threshold) / feather
				image.set_pixel(x, y, px)
	image.unlock()


func _load_claude_icon(icon_name: String, size: int = 40) -> Texture:
	var cache_key: = "%s@%d" % [icon_name, size]
	if _claude_icon_texture_cache.has(cache_key):
		return _claude_icon_texture_cache[cache_key]
	var texture: Texture = null
	var path: = ModPaths.ICONS_DIR + icon_name + ".png"
	if File.new().file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			_strip_icon_background(image)
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
			var image_texture := ImageTexture.new()
			image_texture.create_from_image(image, Texture.FLAGS_DEFAULT)
			texture = image_texture
	_claude_icon_texture_cache[cache_key] = texture
	return texture


# Called by TASTool.gd whenever Claude Experimental Mode is toggled (and once
# at startup if it was already on). Purely cosmetic.
func set_claude_experimental_icons_enabled(value: bool) -> void:
	_claude_experimental_icons_enabled = value
	if _claude_title_icon == null:
		return
	if not value:
		_claude_title_icon.visible = false
		return
	var texture: = _load_claude_icon("cosmetic_sandbox", 40)
	_claude_title_icon.texture = texture
	_claude_title_icon.visible = texture != null


func _on_tree_node_added(node: Node) -> void:
	# Nodes arrive before their children/onready fields are necessarily ready.
	# Deferring makes LocalGoober and renderer.spine reliable to inspect.
	# Prefiltering avoids scheduling one deferred call for every decorative UI node.
	if node != null and (node.name == "CustomizeGoober" or node.name == "SpineSprite" or node.has_method("get_network_object") or node.has_method("on_show_my_player_profile_button_pressed")):
		call_deferred("_consider_new_node", node)


func _consider_new_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	_hook_own_profile_button(node)
	if _is_skin_selector(node):
		_attach_to_skin_selector(node)
	if _is_local_menu_goober(node):
		_register_goober(node)
	_try_register_renderer_goober(node)


func _scan_current_scene() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	_scan_node(scene)
	_discover_local_gameplay_goober()
	if sandbox_enabled:
		_apply_sandbox_to_registered_goobers()


func _scan_node(node: Node) -> void:
	_hook_own_profile_button(node)
	if _is_skin_selector(node):
		_attach_to_skin_selector(node)
	if _is_local_menu_goober(node):
		_register_goober(node)
	_try_register_renderer_goober(node)
	for child in node.get_children():
		_scan_node(child)


func _hook_own_profile_button(node: Node) -> void:
	if not node.has_method("on_show_my_player_profile_button_pressed"):
		return
	var button = node.get("show_my_player_profile_button")
	if button == null or not is_instance_valid(button):
		return
	if button.is_connected("pressed", self, "_open_own_profile"):
		return
	if not button.is_connected("pressed", node, "on_show_my_player_profile_button_pressed"):
		return
	button.disconnect("pressed", node, "on_show_my_player_profile_button_pressed")
	button.connect("pressed", self, "_open_own_profile", [node])


func _open_own_profile(header) -> void:
	if not is_instance_valid(header):
		return
	var scene = get_tree().current_scene
	var previous = scene.get_children()
	# Keep the game's own request and profile behavior. Only the freshly
	# created OWN-profile avatar is registered, never another player's skin.
	header.call("on_show_my_player_profile_button_pressed")
	for child in scene.get_children():
		if not child in previous and child.has_method("show_player_profile_dialog"):
			var avatar = child.get("goober")
			if _is_goober(avatar):
				_register_goober(avatar)


func _is_skin_selector(node: Node) -> bool:
	return node != null and node.has_method("show_cosmetic_type") and node.has_method("on_cosmetics_button_pressed") and node.has_method("equip_cosmetic")


func _is_goober(node: Node) -> bool:
	return node != null and node.has_method("set_goober_skin_data") and node.has_method("apply_skin_data") and node.has_method("get_skeleton")


func _is_local_menu_goober(node: Node) -> bool:
	return _is_goober(node) and node.get_node_or_null("LocalGoober") != null


func _try_register_renderer_goober(node: Node) -> void:
	if node == null or not node.has_method("get_network_object"):
		return
	var player = node.call("get_network_object")
	var game = node.get("network_game")
	if player == null or game == null or not game.has_method("is_local_player"):
		return
	if not ("object_id" in player) or not game.is_local_player(player.object_id):
		return
	var spine = node.get("spine")
	if _is_goober(spine):
		_gameplay_goober = spine
		_renderer_by_goober_id[spine.get_instance_id()] = node
		_register_goober(spine)


func _discover_local_gameplay_goober() -> void:
	# A renderer can finish its onready setup after its node_added callback.
	# The full walk happens once per scene; node_added handles later renderers.
	var scene = get_tree().current_scene
	if scene == null:
		return
	_discover_renderer_in_branch(scene)


func _discover_renderer_in_branch(node: Node) -> bool:
	if node.has_method("get_network_object"):
		var before := _registered_goobers.size()
		_try_register_renderer_goober(node)
		if _registered_goobers.size() > before:
			return true
	for child in node.get_children():
		if _discover_renderer_in_branch(child):
			return true
	return false


func _register_goober(goober) -> void:
	if not _is_goober(goober):
		return
	for existing in _registered_goobers:
		if is_instance_valid(existing) and existing == goober:
			return
	_registered_goobers.append(goober)
	if goober.has_signal("skin_data_changed") and not goober.is_connected("skin_data_changed", self, "_on_registered_skin_changed"):
		goober.connect("skin_data_changed", self, "_on_registered_skin_changed", [goober])
	var goober_id: int = goober.get_instance_id()
	if not _original_materials.has(goober_id):
		_original_materials[goober_id] = goober.get("normal_material")
	if sandbox_enabled:
		_apply_to_goober(goober, _build_local_skin())


func _on_registered_skin_changed(goober) -> void:
	# Native respawn can rebuild slots/materials without changing the dictionary.
	# Invalidate now; the existing bounded refresh reapplies the active look.
	if is_instance_valid(goober):
		_applied_signatures.erase(goober.get_instance_id())


func _cleanup_goober_cache() -> void:
	var clean := []
	var live_ids := {}
	for goober in _registered_goobers:
		if is_instance_valid(goober) and goober.is_inside_tree():
			clean.append(goober)
			live_ids[goober.get_instance_id()] = true
	_registered_goobers = clean
	for goober_id in _original_materials.keys():
		if not live_ids.has(goober_id):
			_original_materials.erase(goober_id)
			_applied_signatures.erase(goober_id)
			_renderer_by_goober_id.erase(goober_id)
	if _gameplay_goober != null and (not is_instance_valid(_gameplay_goober) or not _gameplay_goober.is_inside_tree()):
		_gameplay_goober = null


func _apply_sandbox_to_registered_goobers() -> void:
	var skin := _build_local_skin()
	for goober in _registered_goobers:
		if is_instance_valid(goober):
			_apply_to_goober(goober, skin)


func _build_local_skin() -> Dictionary:
	var skin := {}
	if include_profile_base:
		var profile = Moonlight.storage.storage_get("player.profile.skin", {})
		if typeof(profile) == TYPE_DICTIONARY:
			skin = profile.duplicate(true)
	var ordered := selected_cosmetics.duplicate()
	var catalog = Moonlight.storage.storage_get("cosmetics", {})
	if typeof(catalog) != TYPE_DICTIONARY:
		catalog = {}
	# Array order is meaningful: a later selection wins when two Spine skins
	# both write the same attachment, while non-conflicting parts all remain.
	var extra_index := 0
	for cosmetic_id in ordered:
		# The catalog arrives after startup. Quietly defer saved IDs until it does,
		# and tolerate cosmetics removed by a later game update without log spam.
		var data: Dictionary = catalog.get(str(cosmetic_id), {})
		if data.empty():
			continue
		var cosmetic_type: String = data.get("type", "")
		if cosmetic_type == "color":
			skin["color"] = str(cosmetic_id)
		else:
			skin["sandbox_%03d" % extra_index] = str(cosmetic_id)
			extra_index += 1
	# A body skin is required for both normal and arbitrary colour rendering.
	if not skin.has("color") or str(skin.get("color", "")).empty():
		skin["color"] = "color_default"
	return skin


func _apply_to_goober(goober, skin: Dictionary) -> void:
	if goober == null or not is_instance_valid(goober):
		return
	if _studio != null and goober == _preview_goober and not _studio.preview_skin_override.empty() and not _studio.rendering_look:
		return
	var goober_id: int = goober.get_instance_id()
	if not _original_materials.has(goober_id):
		_original_materials[goober_id] = goober.get("normal_material")
	var signature := "%s|%s|%s" % [str(skin.hash()), str(custom_color_enabled), custom_color.to_html(true)]
	if _studio != null:
		signature += "|" + _studio.current_texture
	var current_skin = goober.get("goober_skin_data")
	var current_hash: int = current_skin.hash() if typeof(current_skin) == TYPE_DICTIONARY else 0
	if _applied_signatures.get(goober_id, "") == signature and current_hash == skin.hash():
		return
	_restore_original_material(goober)
	goober.call("set_goober_skin_data", skin)
	# set_goober_skin_data deliberately no-ops for the same dictionary. Force a
	# refresh in that case so disabling/changing an arbitrary colour also restores
	# the Goober's Gradient resource, not only its material.
	if current_hash == skin.hash():
		goober.call("apply_skin_data")
	if goober.has_method("update_skeleton"):
		goober.call("update_skeleton", 0.0)
	# Apply the custom body row after the animation update so a keyed Spine slot
	# colour cannot immediately overwrite our BODY-only row selection.
	if custom_color_enabled:
		_apply_custom_gradient(goober)
	_apply_body_effect_colors(goober)
	if _studio != null:
		_studio.apply_effects(goober)
	_applied_signatures[goober_id] = signature


func _apply_custom_gradient(goober) -> void:
	var goober_id: int = goober.get_instance_id()
	var base_material = _original_materials.get(goober_id, null)
	if base_material == null or not (base_material is ShaderMaterial):
		return
	var gradient := Gradient.new()
	gradient.offsets = PoolRealArray([0.0, 1.0])
	gradient.colors = PoolColorArray([custom_color.darkened(0.42), custom_color.lightened(0.18)])
	var gradient_texture := GradientTexture.new()
	var source_texture = base_material.get_shader_param("gradient")
	var source_image: Image = source_texture.get_data() if source_texture != null and source_texture.has_method("get_data") else null
	var source_width := source_image.get_width() if source_image != null and source_image.get_width() > 0 and source_image.get_height() > 0 else 64
	gradient_texture.width = source_width
	gradient_texture.gradient = gradient
	var shader_texture = gradient_texture
	var atlas_height := 1
	if source_image != null and source_image.get_width() > 0 and source_image.get_height() > 0:
		# Keep every built-in gradient row for accessory tint slots, then append one
		# private row used only by BODY-tint attachments.
		atlas_height = source_image.get_height() + 1
		var custom_row: Image = gradient_texture.get_data()
		if custom_row.get_format() != source_image.get_format():
			custom_row.convert(source_image.get_format())
		var atlas := Image.new()
		atlas.create(source_width, atlas_height, false, source_image.get_format())
		atlas.blit_rect(source_image, Rect2(0, 0, source_width, source_image.get_height()), Vector2.ZERO)
		atlas.blit_rect(custom_row, Rect2(0, 0, source_width, 1), Vector2(0, atlas_height - 1))
		var atlas_texture := ImageTexture.new()
		atlas_texture.create_from_image(atlas, 0)
		shader_texture = atlas_texture
	var local_material: ShaderMaterial = base_material.duplicate(true) as ShaderMaterial
	local_material.set_shader_param("gradient", shader_texture)
	goober.set("normal_material", local_material)
	if goober.get("gradient_material") != null:
		goober.set("gradient_material", local_material)
	# Goober.get_tint() powers local particles/checkpoint colour. Point it at
	# the same runtime gradient so those details agree with the visible body.
	if goober.get("gradient") != null:
		goober.set("gradient", gradient)
	_apply_body_slot_gradient_row(goober, atlas_height)
