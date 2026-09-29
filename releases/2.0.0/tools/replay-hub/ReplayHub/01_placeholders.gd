extends "user://mod/tools/replay-hub/ReplayHub/00_state.gd"

# Placeholders for functions that live in a later file of the ReplayHub chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _theme_text(color: Color) -> Color:
	return Color()

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
