extends "user://mod/tools/editor-themes/EditorThemePack/00_state.gd"

# Placeholders for functions that live in a later file of the EditorThemePack chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _inject_into_theme_dialog(dialog) -> void:
	pass

func _set_dialog_buttons_visible(dialog, value: bool) -> void:
	pass

func _theme_key_for_level(level) -> String:
	return ""

func _apply_themed_block_variants(level) -> void:
	pass

func _apply_background_visuals(level, theme) -> void:
	pass

func _load_background_art(key: String) -> Texture:
	return null

func _recolor_stock_surface_texture(source, background: Color, foreground: Color) -> Texture:
	return null

func _recolor_stock_floor_texture(source, terrain: Color, accent_dark: Color, accent: Color) -> Texture:
	return null

func _make_starfield_texture(star_color: Color, seed_value: int, star_count: int) -> Texture:
	return null

func _make_background_block_texture(mode: String, background: Color, accent: Color) -> Texture:
	return null

func _make_ambient_texture(mode: String, accent: Color) -> Texture:
	return null

func _make_scenery_texture(key: String, definition: Dictionary) -> Texture:
	return null

func _make_sky_texture(key: String, definition: Dictionary) -> Texture:
	return null

func _refresh_main_menu() -> void:
	pass

func _recolor_stock_crate_texture(source, accent: Color, accent_dark: Color) -> Texture:
	return null

func _texture_from_image(image: Image, repeating: bool) -> Texture:
	return null

func _log(message: String) -> void:
	pass

func _setup_sync() -> void:
	pass

func _remote_theme(level_id) -> String:
	return ""

func _publish_theme_choice(loaded, key: String) -> void:
	pass

func _watch_row(row) -> void:
	pass

func _mark_rows() -> void:
	pass
