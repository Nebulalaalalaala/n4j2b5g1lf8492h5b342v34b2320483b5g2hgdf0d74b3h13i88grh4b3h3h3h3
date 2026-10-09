extends "user://mod/tools/replay-hub/ReplayHub/03_theme_replay.gd"

func _flat_style(background: Color, border: Color, border_width: int, corner: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _theme_fill(background)
	style.border_color = _theme_border(border)
	var w := border_width
	var c := corner
	if _modern_theme_active():
		w = min(border_width, 2)
		c = min(corner, 10)
	style.border_width_left = w
	style.border_width_top = w
	style.border_width_right = w
	style.border_width_bottom = w
	style.corner_radius_top_left = c
	style.corner_radius_top_right = c
	style.corner_radius_bottom_left = c
	style.corner_radius_bottom_right = c
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
	label.add_color_override("font_color", _theme_text(color))
	if _modern_theme_active():
		label.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	else:
		label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 2)
	return label


func _style_button(button: Button, background: Color, corner: int = 18, border_width: int = 4) -> void:
	var themed_bg := _theme_accent(_theme_fill(background))
	var w := border_width
	if _modern_theme_active():
		w = 0
	button.add_stylebox_override("normal", _flat_style(themed_bg, WHITE, w, corner))
	button.add_stylebox_override("hover", _flat_style(themed_bg.lightened(0.14), WHITE, w, corner))
	button.add_stylebox_override("pressed", _flat_style(themed_bg.darkened(0.18), WHITE, w, corner))
	button.add_stylebox_override("focus", _flat_style(themed_bg.lightened(0.12), PINK, w, corner))
	if _body_font != null:
		button.add_font_override("font", _body_font)
	button.add_color_override("font_color", _theme_text(WHITE))
	button.add_color_override("font_color_hover", _theme_text(WHITE))
	button.add_color_override("font_color_pressed", _theme_text(WHITE))


func _make_button(text: String, background: Color, font_size: int = 19) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.rect_min_size = Vector2(0, 50)
	_style_button(button, background)
	var font := _make_font(font_size)
	if font != null:
		button.add_font_override("font", font)
	return button
