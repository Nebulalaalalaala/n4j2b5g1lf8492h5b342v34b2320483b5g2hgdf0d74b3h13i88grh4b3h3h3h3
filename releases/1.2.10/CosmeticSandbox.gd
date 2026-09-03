extends CanvasLayer

# Local-only cosmetic playground. Nothing in this file writes Moonlight
# storage, player cards, ownership, wallet state, or calls a Nakama RPC.
# The official profile is only read as an optional base layer; sandbox
# cosmetics are composed directly on local Goober renderer instances.

const SETTINGS_PATH := "user://cosmetic_sandbox.cfg"
const FONT_PATH := "res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf"
const GOOBER_SCENE_PATH := "res://project_specific/gfx/spine/upguy/upguy.tscn"
const COSMETIC_CARD_SCENE_PATH := "res://project_specific/ui/customization/CosmeticCard.tscn"
const WINDOW_GEOMETRY_SCRIPT_PATH := "user://mod/GoobWindowGeometry.gd"
const CATALOG_RETRY_INTERVAL := 0.5
const CATALOG_RETRY_LIMIT := 20

const NAVY := Color(0.0, 0.129412, 0.262745, 0.72)
const NAVY_2 := Color(0.0, 0.19, 0.36, 0.70)
const BLUE := Color(0.211765, 0.541176, 0.854902)
const PINK := Color(1.0, 0.219608, 0.588235)
const PINK_DARK := Color(0.80, 0.117647, 0.439216)
const GREEN := Color(0.117647, 0.690196, 0.423529)
const PURPLE := Color(0.55, 0.31, 0.88)
const ORANGE := Color(0.96, 0.48, 0.20)
const WHITE := Color.white
const DIM := Color(0.72, 0.82, 0.95)

const TYPE_COLORS := {
	"color": BLUE,
	"suit": PURPLE,
	"hat": PINK,
	"hand": GREEN,
	"emote": ORANGE,
}
const TYPE_ORDER := ["color", "suit", "hat", "hand", "emote"]

var sandbox_enabled := false
var include_profile_base := true
var selected_cosmetics := []
var custom_color_enabled := false
var custom_color := Color(0.25, 0.72, 1.0, 1.0)
var gui_enabled := true

# Phase 0.4 -- Cosmetic Sandbox Content Loading Bug. Optional back-reference
# set by TASTool.gd's configure() call, used only to gate/route Debug Mode
# diagnostics -- see _log_cosmetic_catalog_diagnostics(). Everything else in
# this file works standalone with tas_tool == null, same as before.
var tas_tool: Node = null

var _title_font: DynamicFont
var _header_font: DynamicFont
var _body_font: DynamicFont
var _small_font: DynamicFont

var _modal_root: Control
var _modal_panel: PanelContainer
var _modal_resize_grip: Button
var _modal_resizing := false
var _modal_moving := false
var _grid: GridContainer
var _status_label: Label
var _active_button: Button
var _profile_base_button: Button
var _custom_color_button: Button
var _color_picker: ColorPickerButton
var _search_box: LineEdit
var _filter_buttons := {}
var _filter := "color"
var _preview_goober = null

var _skin_selector: Node = null
var _avatar_button: Button = null
var _last_scene_id := 0
var _registered_goobers := []
var _original_materials := {}
var _applied_signatures := {}
var _renderer_by_goober_id := {}
var _gameplay_goober = null
var _sorting_cosmetics := {}
var _save_pending := false
var _save_delay := 0.0
var _apply_elapsed := 0.0
var _window_geometry = null
var _catalog_waiting_for_source := false
var _catalog_retry_elapsed := 0.0
var _catalog_retry_attempts := 0
var _last_catalog_diag_signature := ""
var _layout_default := {}


func configure(owner_tool: Node) -> void:
	tas_tool = owner_tool


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
		_avatar_button.visible = value
	if not value and _modal_root != null:
		_modal_root.visible = false
	if value:
		call_deferred("_scan_current_scene")


func _on_tree_node_added(node: Node) -> void:
	# Nodes arrive before their children/onready fields are necessarily ready.
	# Deferring makes LocalGoober and renderer.spine reliable to inspect.
	# Prefiltering avoids scheduling one deferred call for every decorative UI node.
	if node != null and (node.name == "CustomizeGoober" or node.name == "SpineSprite" or node.has_method("get_network_object")):
		call_deferred("_consider_new_node", node)


func _consider_new_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
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
	if _is_skin_selector(node):
		_attach_to_skin_selector(node)
	if _is_local_menu_goober(node):
		_register_goober(node)
	_try_register_renderer_goober(node)
	for child in node.get_children():
		_scan_node(child)


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
	var goober_id: int = goober.get_instance_id()
	if not _original_materials.has(goober_id):
		_original_materials[goober_id] = goober.get("normal_material")
	if sandbox_enabled:
		_apply_to_goober(goober, _build_local_skin())


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
	var goober_id: int = goober.get_instance_id()
	if not _original_materials.has(goober_id):
		_original_materials[goober_id] = goober.get("normal_material")
	var signature := "%s|%s|%s" % [str(skin.hash()), str(custom_color_enabled), custom_color.to_html(true)]
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


func _apply_body_slot_gradient_row(goober, atlas_height: int) -> void:
	if atlas_height <= 1:
		return
	var skeleton = goober.call("get_skeleton")
	if skeleton == null:
		return
	var original_height := atlas_height - 1
	for value in skeleton.get_slots():
		var slot: SpineSlot = value
		var attachment = slot.get_attachment()
		if attachment == null:
			continue
		var attachment_name: String = attachment.get_attachment_name().to_lower()
		if attachment_name.find("-tint") < 0:
			continue
		var slot_color: Color = slot.get_color()
		if attachment_name.find("body-tint") >= 0:
			slot_color.g = (float(atlas_height - 1) + 0.5) / float(atlas_height)
		else:
			var original_row := clamp(int(floor(slot_color.g * original_height)), 0, original_height - 1)
			slot_color.g = (float(original_row) + 0.5) / float(atlas_height)
		slot.set_color(slot_color)


func _apply_body_effect_colors(goober) -> void:
	var renderer = _renderer_by_goober_id.get(goober.get_instance_id(), null)
	if renderer == null or not is_instance_valid(renderer):
		return
	var primary: Color = goober.call("get_tint")
	var dark: Color = goober.call("get_dark_tint")
	var particle_color := primary.lightened(0.2)
	_set_property_if_present(renderer, "particles_color", particle_color)
	_set_canvas_color(renderer.get_node_or_null("Position/LandingParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/JumpParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/SpineHolder/WallSlideParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/SpineHolder/FloorDust"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/GravityFieldEnterExitParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/GravityFieldLoopParticles"), particle_color, false)
	_set_canvas_color(renderer.get_node_or_null("Position/DashTrailParticles"), particle_color, true)
	_set_canvas_color(renderer.get_node_or_null("Position/DashCharge"), particle_color, true)
	var cooldown = renderer.get_node_or_null("UIHolder/UI/DashCooldown")
	if cooldown != null:
		cooldown.set("tint_progress", primary)
		cooldown.set("tint_under", dark)
	var dash_trail = renderer.get_node_or_null("DashTrail")
	if dash_trail != null and dash_trail.get("material") is ShaderMaterial:
		dash_trail.get("material").set_shader_param("dash_color", primary)


func _set_canvas_color(node, color: Color, use_self_modulate: bool) -> void:
	if node == null or not (node is CanvasItem):
		return
	if use_self_modulate:
		node.self_modulate = color
	else:
		node.modulate = color


func _set_property_if_present(object, property_name: String, value) -> void:
	if object == null:
		return
	for property in object.get_property_list():
		if property.get("name", "") == property_name:
			object.set(property_name, value)
			return


func _restore_original_material(goober) -> void:
	var original = _original_materials.get(goober.get_instance_id(), null)
	if original == null:
		return
	goober.set("normal_material", original)
	if goober.get("gradient_material") != null:
		goober.set("gradient_material", original)


func _restore_all_registered_goobers() -> void:
	var profile = Moonlight.storage.storage_get("player.profile.skin", {})
	if typeof(profile) != TYPE_DICTIONARY:
		profile = {}
	for goober in _registered_goobers:
		if not is_instance_valid(goober):
			continue
		_restore_original_material(goober)
		goober.call("set_goober_skin_data", profile)
		goober.call("apply_skin_data")
		if goober.has_method("update_skeleton"):
			goober.call("update_skeleton", 0.0)
		_apply_body_effect_colors(goober)
	_applied_signatures.clear()


func _attach_to_skin_selector(selector: Node) -> void:
	if selector == null or not is_instance_valid(selector):
		return
	_skin_selector = selector
	var existing = selector.get_node_or_null("CosmeticSandboxButton")
	if existing != null:
		_avatar_button = existing
		_avatar_button.visible = gui_enabled
		_refresh_avatar_button()
		return
	var button := _make_button("✦  SANDBOX", PURPLE, 25)
	button.name = "CosmeticSandboxButton"
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.5
	button.anchor_bottom = 0.5
	button.margin_left = -300.0
	button.margin_right = -40.0
	button.margin_top = -260.0
	button.margin_bottom = -174.0
	button.rect_min_size = Vector2(260, 86)
	button.hint_tooltip = "Open the local cosmetic sandbox"
	button.connect("pressed", self, "_open_modal")
	selector.add_child(button)
	selector.move_child(button, selector.get_child_count() - 1)
	_avatar_button = button
	_avatar_button.visible = gui_enabled
	_refresh_avatar_button()


func _build_modal() -> void:
	_modal_root = Control.new()
	_modal_root.name = "CosmeticSandboxModal"
	_modal_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	dim.color = Color(0.015, 0.025, 0.08, 0.10)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_root.add_child(dim)

	_modal_panel = PanelContainer.new()
	_modal_panel.anchor_left = 0.055
	_modal_panel.anchor_top = 0.035
	_modal_panel.anchor_right = 0.945
	_modal_panel.anchor_bottom = 0.965
	_modal_panel.add_stylebox_override("panel", _flat_style(NAVY, Color(0.49, 0.78, 1.0, 0.9), 6, 34))
	_modal_root.add_child(_modal_panel)

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 26)
	margin.add_constant_override("margin_right", 26)
	margin.add_constant_override("margin_top", 22)
	margin.add_constant_override("margin_bottom", 22)
	var modal_scroll := ScrollContainer.new()
	modal_scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	modal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_panel.add_child(modal_scroll)
	modal_scroll.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_constant_override("separation", 14)
	margin.add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_constant_override("separation", 12)
	root_vbox.add_child(header)
	var title := _make_label("COSMETIC SANDBOX", _title_font, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Phase 0.2 -- Universal Movable & Resizable GUI. A plain Label defaults to
	# MOUSE_FILTER_IGNORE in Godot 3.x, so it never received the gui_input
	# events _on_modal_move_gui_input() below was already listening for --
	# this connect() call was wired up but could never fire. That's the whole
	# reason dragging the Sandbox by its title never worked.
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.hint_tooltip = "Drag to move the Sandbox window."
	title.connect("gui_input", self, "_on_modal_move_gui_input")
	header.add_child(title)
	var local_badge := _make_label("  LOCAL ONLY  ", _small_font, Color(0.72, 1.0, 0.87))
	local_badge.add_stylebox_override("normal", _flat_style(Color(0.05, 0.32, 0.23, 1.0), GREEN, 3, 99))
	local_badge.valign = Label.VALIGN_CENTER
	header.add_child(local_badge)
	var close := _make_button("×", PINK_DARK, 22)
	close.rect_min_size = Vector2(64, 58)
	close.connect("pressed", self, "_close_modal")
	header.add_child(close)

	var subtitle := _make_label("Every catalog cosmetic is available here. Stack as many as you want; nothing is purchased, unlocked, uploaded, or written to your real profile.", _small_font, DIM)
	subtitle.autowrap = true
	root_vbox.add_child(subtitle)

	var hero := HBoxContainer.new()
	hero.add_constant_override("separation", 18)
	root_vbox.add_child(hero)
	var preview_panel := PanelContainer.new()
	preview_panel.rect_min_size = Vector2(245, 245)
	preview_panel.add_stylebox_override("panel", _flat_style(NAVY_2, Color(1, 1, 1, 0.25), 3, 24))
	hero.add_child(preview_panel)
	var preview_holder := Control.new()
	preview_holder.rect_min_size = Vector2(245, 245)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_holder)
	var goober_scene = load(GOOBER_SCENE_PATH)
	if goober_scene != null and goober_scene is PackedScene:
		_preview_goober = goober_scene.instance()
		_preview_goober.position = Vector2(122, 222)
		_preview_goober.scale = Vector2(-0.125, 0.125)
		_preview_goober.enable_sounds = false
		preview_holder.add_child(_preview_goober)
		_register_goober(_preview_goober)
		var animation_state = _preview_goober.get_animation_state()
		if animation_state != null:
			animation_state.set_animation("Idle", true, 0)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_constant_override("separation", 9)
	hero.add_child(controls)
	_status_label = _make_label("", _header_font, WHITE)
	controls.add_child(_status_label)
	_active_button = _make_button("", PINK, 20)
	_active_button.connect("pressed", self, "_toggle_sandbox_enabled")
	controls.add_child(_active_button)
	_profile_base_button = _make_button("", BLUE, 18)
	_profile_base_button.connect("pressed", self, "_toggle_profile_base")
	controls.add_child(_profile_base_button)
	var color_row := HBoxContainer.new()
	color_row.add_constant_override("separation", 10)
	controls.add_child(color_row)
	_custom_color_button = _make_button("", PURPLE, 18)
	_custom_color_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_color_button.connect("pressed", self, "_toggle_custom_color")
	color_row.add_child(_custom_color_button)
	_color_picker = ColorPickerButton.new()
	_color_picker.rect_min_size = Vector2(92, 58)
	_color_picker.color = custom_color
	_color_picker.focus_mode = Control.FOCUS_NONE
	_color_picker.hint_tooltip = "Choose any local Goober colour"
	_color_picker.connect("color_changed", self, "_on_custom_color_changed")
	color_row.add_child(_color_picker)

	var filter_row := HBoxContainer.new()
	filter_row.add_constant_override("separation", 7)
	root_vbox.add_child(filter_row)
	var filters := [["color", "COLORS"], ["suit", "SUITS"], ["hat", "HATS"], ["hand", "HANDS"], ["emote", "EMOTES"]]
	for item in filters:
		var filter_button := _make_button(item[1], TYPE_COLORS.get(item[0], BLUE), 15)
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_button.connect("pressed", self, "_set_filter", [item[0]])
		filter_row.add_child(filter_button)
		_filter_buttons[item[0]] = filter_button

	_search_box = LineEdit.new()
	_search_box.rect_min_size = Vector2(0, 52)
	_search_box.placeholder_text = "Search every cosmetic by name or ID…"
	_search_box.clear_button_enabled = true
	_search_box.focus_mode = Control.FOCUS_ALL
	if _body_font != null:
		_search_box.add_font_override("font", _body_font)
	_search_box.add_stylebox_override("normal", _flat_style(NAVY_2, Color(1, 1, 1, 0.35), 3, 16))
	_search_box.add_stylebox_override("focus", _flat_style(NAVY_2, PINK, 4, 16))
	_search_box.connect("text_changed", self, "_on_search_changed")
	root_vbox.add_child(_search_box)

	var scroll := ScrollContainer.new()
	# Phase 0.4 -- Cosmetic Sandbox Content Loading Bug. The catalog was
	# loading fine (confirmed via Debug Mode: 287 items) but never appeared,
	# because this ScrollContainer sits inside ANOTHER ScrollContainer
	# (modal_scroll, wrapping the whole modal body below). A ScrollContainer's
	# reported minimum size in Godot 3.x does not include its child's full
	# content size -- that's what lets it be smaller than what it scrolls --
	# so nested inside another ScrollContainer, root_vbox gets sized to its
	# bare minimum and this one collapses to near-zero height, hiding every
	# card even though they were all correctly created. Giving it an explicit
	# minimum height forces real space to be reserved for the grid.
	scroll.rect_min_size = Vector2(0, 460)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	root_vbox.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_constant_override("hseparation", 9)
	_grid.add_constant_override("vseparation", 9)
	scroll.add_child(_grid)

	var actions := HBoxContainer.new()
	actions.add_constant_override("separation", 10)
	root_vbox.add_child(actions)
	var random_button := _make_button("⚄  STACK RANDOM", PURPLE, 18)
	random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_button.connect("pressed", self, "_randomize_stack")
	actions.add_child(random_button)
	var clear_button := _make_button("CLEAR EXTRAS", BLUE, 18)
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.connect("pressed", self, "_clear_extras")
	actions.add_child(clear_button)
	var profile_button := _make_button("USE REAL PROFILE", PINK_DARK, 18)
	profile_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_button.connect("pressed", self, "_disable_and_restore_profile")
	actions.add_child(profile_button)

	_modal_resize_grip = _make_button("↘", Color(0.08, 0.34, 0.55, 0.84), 20)
	_modal_resize_grip.rect_min_size = Vector2(48, 48)
	_modal_resize_grip.rect_size = Vector2(48, 48)
	_modal_resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_modal_resize_grip.hint_tooltip = "Drag to resize the Sandbox window."
	_modal_resize_grip.connect("gui_input", self, "_on_modal_resize_gui_input")
	_modal_root.add_child(_modal_resize_grip)
	call_deferred("_sync_modal_resize_grip")

	_modal_root.visible = false
	_refresh_controls()


func _open_modal() -> void:
	if not gui_enabled:
		return
	_modal_root.visible = true
	_filter = "color"
	_search_box.text = ""
	_catalog_retry_elapsed = 0.0
	_catalog_retry_attempts = 0
	_rebuild_grid()
	_refresh_controls()


func _close_modal() -> void:
	_modal_resizing = false
	_modal_moving = false
	_modal_root.visible = false
	_catalog_waiting_for_source = false
	_clear_cosmetic_grid()


func _process_catalog_retry(delta: float) -> void:
	if _modal_root == null or not _modal_root.visible or not _catalog_waiting_for_source:
		return
	if _catalog_retry_attempts >= CATALOG_RETRY_LIMIT:
		return
	_catalog_retry_elapsed += delta
	if _catalog_retry_elapsed < CATALOG_RETRY_INTERVAL:
		return
	_catalog_retry_elapsed = 0.0
	_catalog_retry_attempts += 1
	var source = Moonlight.storage.storage_get("cosmetics", {})
	if typeof(source) == TYPE_DICTIONARY and not source.empty():
		_catalog_waiting_for_source = false
		_rebuild_grid()


func _on_modal_resize_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_modal_resizing = event.pressed
		if event.pressed:
			_convert_modal_panel_to_pixel_rect()
		else:
			_save_modal_layout()
	elif event is InputEventMouseMotion and _modal_resizing:
		# Phase 0.1/0.2 follow-up: when `available` (room between the panel's
		# fixed position and the viewport edge) dropped below the intended
		# 440x400 minimum, min_size got set to `available` too -- making the
		# clamp's min and max the SAME value and permanently locking the
		# panel at that exact size no matter which way you dragged. Clamping
		# the minimum DOWN to whatever's actually available (instead of
		# leaving it at a fixed 440/400) keeps min <= max always, so resizing
		# never gets stuck.
		var viewport_size: Vector2 = get_viewport().size
		var minimum := Vector2(440, 400)
		if _window_geometry != null:
			_modal_panel.rect_size = _window_geometry.resized_size(_modal_panel.rect_size, event.relative, minimum, _modal_panel.rect_position, viewport_size, Vector2(18, 18))
		else:
			var available: Vector2 = viewport_size - _modal_panel.rect_position - Vector2(18, 18)
			var maximum := Vector2(max(minimum.x, available.x), max(minimum.y, available.y))
			_modal_panel.rect_size = Vector2(clamp(_modal_panel.rect_size.x + event.relative.x, minimum.x, maximum.x), clamp(_modal_panel.rect_size.y + event.relative.y, minimum.y, maximum.y))
		_grid.columns = 2 if _modal_panel.rect_size.x < 760.0 else (3 if _modal_panel.rect_size.x < 1040.0 else 4)
		_sync_modal_resize_grip()


func _on_modal_move_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		_modal_moving = event.pressed
		if event.pressed:
			_convert_modal_panel_to_pixel_rect()
		else:
			_save_modal_layout()
	elif event is InputEventMouseMotion and _modal_moving:
		var viewport_size: Vector2 = get_viewport().size
		if _window_geometry != null:
			_modal_panel.rect_position = _window_geometry.moved_position(_modal_panel.rect_position, _modal_panel.rect_size, event.relative, viewport_size)
		else:
			var next: Vector2 = _modal_panel.rect_position + event.relative
			next.x = clamp(next.x, -_modal_panel.rect_size.x + 120.0, viewport_size.x - 120.0)
			next.y = clamp(next.y, 0.0, viewport_size.y - 64.0)
			_modal_panel.rect_position = next
		_sync_modal_resize_grip()


func _convert_modal_panel_to_pixel_rect() -> void:
	if _window_geometry != null:
		_window_geometry.convert_to_pixel_rect(_modal_panel)
		return
	if is_zero_approx(_modal_panel.anchor_right) and is_zero_approx(_modal_panel.anchor_bottom):
		return
	var position := _modal_panel.rect_position
	var size := _modal_panel.rect_size
	_modal_panel.anchor_left = 0.0
	_modal_panel.anchor_top = 0.0
	_modal_panel.anchor_right = 0.0
	_modal_panel.anchor_bottom = 0.0
	_modal_panel.rect_position = position
	_modal_panel.rect_size = size


func _sync_modal_resize_grip() -> void:
	if _modal_panel == null or _modal_resize_grip == null:
		return
	_modal_resize_grip.rect_position = _modal_panel.rect_position + _modal_panel.rect_size - _modal_resize_grip.rect_size - Vector2(8, 8)


func _initialize_saved_layout() -> void:
	if _modal_panel == null:
		return
	_convert_modal_panel_to_pixel_rect()
	_layout_default = {"position": _modal_panel.rect_position, "size": _modal_panel.rect_size}
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("restore_gui_panel_layout"):
		tas_tool.call("restore_gui_panel_layout", "cosmetic_sandbox", _modal_panel, Vector2(640, 440))
	_grid.columns = 2 if _modal_panel.rect_size.x < 760.0 else (3 if _modal_panel.rect_size.x < 1040.0 else 4)
	_sync_modal_resize_grip()


func _save_modal_layout() -> void:
	if tas_tool != null and is_instance_valid(tas_tool) and tas_tool.has_method("save_gui_panel_layout"):
		tas_tool.call("save_gui_panel_layout", "cosmetic_sandbox", _modal_panel)


func reset_saved_layout() -> void:
	if _modal_panel == null or _layout_default.empty():
		return
	_modal_panel.rect_position = _layout_default["position"]
	_modal_panel.rect_size = _layout_default["size"]
	_grid.columns = 2 if _modal_panel.rect_size.x < 760.0 else (3 if _modal_panel.rect_size.x < 1040.0 else 4)
	_sync_modal_resize_grip()


func _set_filter(value: String) -> void:
	_filter = value
	_rebuild_grid()
	_refresh_filter_buttons()


func _on_search_changed(_text: String) -> void:
	_rebuild_grid()


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
	_avatar_button.text = "✦  SANDBOX%s" % ("  • ON" if sandbox_enabled else "")
	_style_button(_avatar_button, PINK if sandbox_enabled else PURPLE, 24, 5)


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


func _make_font(size: int) -> DynamicFont:
	var data = load(FONT_PATH)
	if data == null or not (data is DynamicFontData):
		return null
	var font := DynamicFont.new()
	var crisp_data: DynamicFontData = data.duplicate()
	crisp_data.antialiased = true
	crisp_data.override_oversampling = 2.0
	font.font_data = crisp_data
	font.size = size
	font.outline_size = 1
	font.outline_color = Color(0, 0.02, 0.05, 0.95)
	font.use_filter = true
	font.use_mipmaps = true
	return font


func _flat_style(background: Color, border: Color, border_width: int, corner: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	style.corner_detail = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _make_label(text: String, font: DynamicFont, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if font != null:
		label.add_font_override("font", font)
	label.add_color_override("font_color", color)
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 2)
	return label


func _style_button(button: Button, background: Color, corner: int = 18, border_width: int = 4) -> void:
	button.add_stylebox_override("normal", _flat_style(background, WHITE, border_width, corner))
	button.add_stylebox_override("hover", _flat_style(background.lightened(0.14), WHITE, border_width, corner))
	button.add_stylebox_override("pressed", _flat_style(background.darkened(0.18), WHITE, border_width, corner))
	button.add_stylebox_override("focus", _flat_style(background.lightened(0.12), PINK, border_width, corner))
	if _body_font != null:
		button.add_font_override("font", _body_font)
	button.add_color_override("font_color", WHITE)
	button.add_color_override("font_color_hover", WHITE)
	button.add_color_override("font_color_pressed", WHITE)


func _make_button(text: String, background: Color, font_size: int = 19) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.rect_min_size = Vector2(0, 58)
	_style_button(button, background)
	var font := _make_font(font_size)
	if font != null:
		button.add_font_override("font", font)
	return button
