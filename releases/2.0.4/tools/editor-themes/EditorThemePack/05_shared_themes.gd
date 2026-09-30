extends "user://mod/tools/editor-themes/EditorThemePack/04_texture_scenery.gd"

# Shared level themes: a theme the author picks for a published level is sent
# to LevelThemeSync, so every Goobplayability player sees the level with it.
# Level explorer rows of such levels get a small Goobplayability mark.
const ROW_MARK = "GoobplayabilityThemeMark"
const MARK_SIZE = 40

func _setup_sync() -> void:
	var script = ModPaths.try_load(ModPaths.path("LevelThemeSync.gd"))
	if script == null:
		return
	_sync = script.new()
	add_child(_sync)
	_sync.connect("updated", self, "_on_remote_themes")

func _remote_theme(level_id) -> String:
	return _sync.theme_for(level_id) if _sync != null else ""

func _on_remote_themes() -> void:
	if not gui_enabled:
		return
	for level in _levels:
		if is_instance_valid(level) and level.is_inside_tree() and not _is_actual_editor_session():
			_refresh_loaded_editor_level(level)
	_mark_rows()

# Author only: the level must be saved (has an id) and be yours.
func _publish_theme_choice(loaded, key: String) -> void:
	if _sync == null or loaded == null:
		return
	var moonlight = get_node_or_null("/root/Moonlight")
	var session = moonlight.get("session") if moonlight != null else null
	var me = str(session.get("user_id")) if session != null and session.get("user_id") != null else ""
	var author = str(loaded.get("author_id")) if loaded.get("author_id") != null else ""
	var id = str(loaded.get("level_id"))
	if me.empty() or id.empty() or (not author.empty() and author != me):
		return
	_sync.publish(id, key, me)

# ---------------------------------------------------------------- explorer rows
func _watch_row(row) -> void:
	if not _rows.has(row):
		_rows.append(row)
	# show_level_data() runs right after the row is added.
	get_tree().create_timer(0.1).connect("timeout", self, "_mark_rows")

func _mark_rows() -> void:
	var live = []
	for row in _rows:
		if is_instance_valid(row) and row.is_inside_tree():
			live.append(row)
			_mark_row(row)
	_rows = live

func _mark_row(row) -> void:
	var holder = row.get_node_or_null("MarginContainer/HBoxContainer")
	var right = holder.get_node_or_null("RightSide") if holder != null else null
	if right == null:
		return
	var key = _remote_theme(row.get("level_id"))
	var mark = holder.get_node_or_null(ROW_MARK)
	if not gui_enabled or not THEME_DEFINITIONS.has(key):
		if mark != null:
			mark.queue_free()
		return
	if mark == null:
		mark = TextureRect.new()
		mark.name = ROW_MARK
		mark.texture = _mark_texture()
		mark.expand = true
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.rect_min_size = Vector2(MARK_SIZE, MARK_SIZE)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_PASS
		holder.add_child(mark)
		holder.move_child(mark, right.get_index())
	mark.hint_tooltip = "Goobplayability theme: " + str(THEME_DEFINITIONS[key].name)

func _mark_texture() -> Texture:
	if _row_mark_texture == null:
		var image = Image.new()
		if image.load(ModPaths.ICONS_DIR + "goob_bean.png") == OK:
			image.resize(MARK_SIZE * 2, MARK_SIZE * 2, Image.INTERPOLATE_LANCZOS)
			_row_mark_texture = ImageTexture.new()
			_row_mark_texture.create_from_image(image, Texture.FLAG_FILTER)
	return _row_mark_texture
