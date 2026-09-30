extends "user://mod/tools/tas/TASMacroEditor/00_state.gd"

# Placeholders for functions that live in a later file of the TASMacroEditor chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _build_ui() -> void:
	pass

func _rebuild_timeline() -> void:
	pass

func _set_preview_direction(direction: int) -> void:
	pass

func _advance_preview(delta: float) -> void:
	pass

func _refresh_inspector() -> void:
	pass

func _number_field(parent: GridContainer, title: String) -> SpinBox:
	return null

func _panel_box(title: String) -> PanelContainer:
	return null

func _theme_text(color: Color) -> Color:
	return Color()

func _theme_accent(color: Color) -> Color:
	return Color()

func _font(size: int) -> DynamicFont:
	return null

func _label(text: String, font: DynamicFont, color: Color) -> Label:
	return null

func _button(text: String, color: Color, width: int, icon_path: String = "") -> Button:
	return null

func _style(color: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	return null
