extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Folders = preload("user://mod/tools/editor-themes/ThemeFolders.gd")
const PAGE_SIZE = 8
var pack
var dialog
var grid
var folder := ""
var page := 0
var _native := []
var _custom := {}
var _folder_buttons := []
var _nav := []
var _preview_cache := {}
var _enabled := true
var _last_view := ""

func _init(owner, selector, parent):
	pack = owner
	dialog = selector
	grid = parent
	for child in grid.get_children():
		if child is BaseButton and not str(child.name).begins_with("GoobplayabilityTheme_") and not child.has_meta("theme_page_navigation"):
			_native.append(child)
		elif child is BaseButton:
			child.hide()
	var native_dialog = dialog.get("dialog")
	if native_dialog != null and not native_dialog.is_connected("animated_in", self, "_opened"):
		native_dialog.connect("animated_in", self, "_opened")
	for entry in Folders.FOLDERS:
		var button = _button("ThemeFolder_"+entry.key, entry.name.to_upper())
		if button == null: continue
		button.get_node("ThemeTexture").hide()
		var icon = load(ModPaths.path("ThemeFolderIcon.gd")).new()
		icon.color = Color(entry.color)
		button.add_child(icon)
		icon.anchor_right = 1.0
		icon.margin_left = 10
		icon.margin_top = 5
		icon.margin_right = -10
		icon.margin_bottom = 100
		button.get_node("SDFLabel/GoodAnchorPoint").anchor_to_parent = Vector2(0.5,0.84)
		button.connect("pressed", self, "open_folder", [entry.key])
		_folder_buttons.append(button)
	for entry in [["Back", "FOLDERS", ""], ["Previous", "PREVIOUS", -1], ["Next", "NEXT", 1]]:
		var button = _button("ThemeFolderNav_"+entry[0], entry[1])
		if button == null: continue
		button.rect_min_size = Vector2(150,64)
		button.get_node("ThemeTexture").hide()
		if entry[0] == "Back":
			button.connect("pressed", self, "open_folder", [""])
		else:
			button.connect("pressed", self, "turn_page", [entry[2]])
		_nav.append(button)
	refresh(true)

func _button(name: String, text: String):
	var scene = dialog.get("theme_button_scene")
	if not scene is PackedScene: return null
	var button = scene.instance()
	button.name = name
	button.rect_min_size = Vector2(150,150)
	button.set_meta("theme_folder_generated",true)
	grid.add_child(button)
	button.set("label_text",text)
	return button

func _opened() -> void:
	if _enabled: open_folder("")

func open_folder(key: String) -> void:
	folder = key
	page = 0
	refresh(_enabled)

func turn_page(step: int) -> void:
	page += step
	refresh(_enabled)

func refresh(enabled: bool) -> void:
	_enabled = enabled
	if not is_instance_valid(grid) or not is_instance_valid(dialog): return
	# The theme pack checks the dialog periodically. Don't hide/show identical
	# choices on every pass: native focus-on-visible would steal keyboard focus.
	var view: String = str(enabled)+"|"+folder+"|"+str(page)
	if view == _last_view: return
	_last_view = view
	for button in _native:
		if is_instance_valid(button): button.visible = not enabled
	for button in _custom.values():
		if is_instance_valid(button): button.hide()
	for button in _folder_buttons: button.visible = enabled and folder.empty()
	for button in _nav: button.hide()
	if not enabled:
		grid.columns = 4
		dialog.dialog.set_dialog_title("SELECT THEME")
		return
	grid.columns = 4
	grid.add_constant_override("hseparation",18)
	grid.add_constant_override("vseparation",14)
	dialog.dialog.set_dialog_title("THEME FOLDERS" if folder.empty() else Folders.title(folder).to_upper())
	if folder.empty(): return
	var choices := []
	if folder == "default":
		choices = _native.duplicate()
	else:
		var keys: Array = pack.THEME_DEFINITIONS.keys()
		keys.sort()
		for key in keys:
			if Folders.category(key,pack.THEME_DEFINITIONS) != folder: continue
			if not _custom.has(key):
				var definition = pack.THEME_DEFINITIONS[key]
				var button = _button("GoobplayabilityTheme_"+key, str(definition.name).to_upper())
				if button == null: continue
				button.get_node("ThemeTexture").texture = _preview(key,definition)
				button.hint_tooltip = "Goobplayability visual theme; native GooberDash objects and physics."
				button.connect("pressed",self,"_selected",[key])
				_custom[key] = button
			choices.append(_custom[key])
	var pages: int = max(1,int(ceil(float(choices.size())/PAGE_SIZE)))
	page = posmod(page,pages)
	_last_view = str(enabled)+"|"+folder+"|"+str(page)
	for index in range(choices.size()):
		choices[index].visible = int(index/PAGE_SIZE) == page
		if choices[index].visible: grid.move_child(choices[index],grid.get_child_count()-1)
	for index in range(_nav.size()):
		_nav[index].visible = index == 0 or pages > 1
		if index > 0: _nav[index].set("label_text",("< " if index == 1 else "> ")+"%d / %d" % [page+1,pages])
		grid.move_child(_nav[index],grid.get_child_count()-1)

func _preview(key: String, definition: Dictionary) -> Texture:
	if _preview_cache.has(key): return _preview_cache[key]
	var path := ModPaths.THEME_BACKGROUNDS_DIR+key+"-preview.png"
	var image := Image.new()
	var texture: Texture
	if File.new().file_exists(path) and image.load(path) == OK:
		var png := ImageTexture.new()
		png.create_from_image(image,Texture.FLAG_FILTER)
		texture = png
	else:
		var gradient := Gradient.new()
		gradient.colors = PoolColorArray([definition.top,definition.bottom])
		var fill := GradientTexture2D.new()
		fill.gradient = gradient
		fill.fill_to = Vector2(0,1)
		texture = fill
	_preview_cache[key] = texture
	return texture

func _selected(key: String) -> void:
	if not _enabled: return
	var base = load("res://project_specific/level_themes/green/theme.tres")
	pack._ensure_themes(base,key)
	if pack._themes.has(key): pack._on_custom_theme_button_pressed(dialog,pack._themes[key])
