extends "user://mod/tools/avatar-studio/CosmeticSandbox/00_state.gd"

# Placeholders for functions that live in a later file of the CosmeticSandbox chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _apply_body_slot_gradient_row(goober, atlas_height: int) -> void:
	pass

func _apply_body_effect_colors(goober) -> void:
	pass

func _restore_original_material(goober) -> void:
	pass

func _restore_all_registered_goobers() -> void:
	pass

func _attach_to_skin_selector(selector: Node) -> void:
	pass

func _build_modal() -> void:
	pass

func _open_modal() -> void:
	pass

func _close_modal() -> void:
	pass

func _process_catalog_retry(delta: float) -> void:
	pass

func _sync_modal_resize_grip() -> void:
	pass

func _rebuild_grid() -> void:
	pass

func _clear_cosmetic_grid() -> void:
	pass

func _refresh_controls() -> void:
	pass

func _refresh_filter_buttons() -> void:
	pass

func _load_settings() -> void:
	pass

func _save_settings() -> void:
	pass

func _make_font(size: int) -> DynamicFont:
	return null

func _flat_style(background: Color, border: Color, border_width: int, corner: int) -> StyleBoxFlat:
	return null

func _make_label(text: String, font: DynamicFont, color: Color) -> Label:
	return null

func _style_button(button: Button, background: Color, corner: int = 18, border_width: int = 4) -> void:
	pass

func _make_button(text: String, background: Color, font_size: int = 19) -> Button:
	return null
