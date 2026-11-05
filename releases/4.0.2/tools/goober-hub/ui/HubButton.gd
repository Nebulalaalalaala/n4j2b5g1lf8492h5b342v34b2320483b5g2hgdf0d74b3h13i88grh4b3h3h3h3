extends Button
# Native activation and focus; centered caption with a light sheen (same as Speedrun Lab's buttons).
var caption_label
var glyph_node
var caption = ""
var glossy = true
var radius = 18

func configure(value,typeface,texture=null):
	caption = str(value)
	text = ""
	align = Button.ALIGN_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	caption_label = Label.new()
	caption_label.name = "CenteredCaption"
	caption_label.text = caption
	caption_label.visible = not caption.empty()
	caption_label.align = Label.ALIGN_CENTER
	caption_label.valign = Label.VALIGN_CENTER
	caption_label.clip_text = true
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.add_font_override("font",typeface)
	add_child(caption_label)
	caption_label.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var reserve = 52 if texture!=null else 20
	rect_min_size = Vector2(typeface.get_string_size(caption).x+reserve*2,48)
	if texture!=null:
		glyph_node = TextureRect.new()
		glyph_node.name = "ActionGlyph"
		glyph_node.texture = texture
		glyph_node.expand = true
		glyph_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glyph_node)
		glyph_node.anchor_top = 0.5
		glyph_node.anchor_bottom = 0.5
		glyph_node.margin_left = 18
		glyph_node.margin_right = 42
		glyph_node.margin_top = -12
		glyph_node.margin_bottom = 12
		if caption.empty():
			glyph_node.anchor_left = 0.5
			glyph_node.anchor_right = 0.5
			glyph_node.margin_left = -12
			glyph_node.margin_right = 12
			rect_min_size.x = 48

func _draw():
	if not glossy or disabled or is_pressed(): return
	var sheen = StyleBoxFlat.new()
	sheen.bg_color = Color(1,1,1,0.09)
	sheen.set_corner_radius_all(radius-4)
	sheen.corner_detail = 12
	sheen.anti_aliasing = true
	draw_style_box(sheen,Rect2(5,3,max(0,rect_size.x-10),max(0,rect_size.y*0.43)))
	draw_line(Vector2(radius,3),Vector2(rect_size.x-radius,3),Color(1,1,1,0.20),1.0,true)

func _notification(what):
	if what!=NOTIFICATION_DRAW or not is_instance_valid(caption_label): return
	var state = "disabled" if disabled else "pressed" if is_pressed() else "hover" if is_hovered() else "focus" if has_focus() else "normal"
	var ink = get_color("font_color"+("" if state=="normal" else "_"+state))
	if caption_label.get_color("font_color")!=ink: caption_label.add_color_override("font_color",ink)
	caption_label.margin_top = 2 if state=="pressed" else 0
	caption_label.margin_bottom = 2 if state=="pressed" else 0
	if is_instance_valid(glyph_node): glyph_node.modulate = get_color("icon_color_"+state)
