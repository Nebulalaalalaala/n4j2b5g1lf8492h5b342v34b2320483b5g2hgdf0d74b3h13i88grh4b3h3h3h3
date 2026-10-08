extends Reference

# Use the game's scenes/materials/fonts, including hover/press sounds and
# native selected/focus states. Sizes are native editor logical units; the
# editor owns display scaling, so these controls must not counter-scale it.
const BUTTON = preload("res://goodoh/ui/nodes/GoodButton.tscn")
const ICON_BUTTON = preload("res://project_specific/ui/button_styles/FlatButtonWhite.tscn")
const NATIVE_THEME = preload("res://project_specific/ui/upguys_theme.tres")
const FIELD_THEME = preload("res://project_specific/level_editor/properties_editor/ui/level_editor_inspector_theme.tres")
const FONT = preload("res://project_specific/fonts/baloo_50.tres")
const SDF_SCRIPT = preload("res://goodoh/fonts/SDFLabel.gd")
const SDF_MATERIAL = preload("res://goodoh/fonts/msdf-font-shader2.material")
var number_font

func _init():
	number_font = FONT.duplicate()
	number_font.size = 40
	number_font.extra_spacing_top = -8
	number_font.extra_spacing_bottom = -8

func label(parent, text: String, heading: bool = false):
	var node = WPSDFLabel.new()
	node.set_script(SDF_SCRIPT)
	node.material = SDF_MATERIAL
	node.sdf_material = SDF_MATERIAL
	node.theme = NATIVE_THEME
	node.text = text
	node.font_size = 2 if heading else 1
	node.align = Label.ALIGN_LEFT
	node.valign = Label.VALIGN_CENTER
	node.rect_min_size = Vector2(0, 58 if heading else 42)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent, title: String, target, method: String, args: Array = []):
	var node = BUTTON.instance()
	node.theme = NATIVE_THEME
	node.theme_type_variation = "Button_White"
	node.label_text = title
	node.font_size = 1
	node.rect_min_size = Vector2(0, 72)
	var label = node.get_node("SDFLabel")
	label.fit_inside_parent_margin = 20.0
	node.connect("pressed", target, method, args)
	parent.add_child(node)
	return node

func icon_button(parent, path: String, tip: String, target, method: String, args: Array = []):
	var node = ICON_BUTTON.instance()
	node.rect_min_size = Vector2(76, 76)
	node.size_flags_horizontal = Control.SIZE_FILL
	node.icon_tex = load(path)
	node.hint_tooltip = tip
	node.connect("pressed", target, method, args)
	parent.add_child(node)
	return node

func field(parent, tip: String):
	var node = LineEdit.new()
	node.theme = FIELD_THEME
	node.add_font_override("font", number_font)
	node.align = LineEdit.ALIGN_CENTER
	node.rect_min_size = Vector2(0, 70)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.expand_to_text_length = false
	node.max_length = 32
	node.hint_tooltip = tip+" · Enter to apply · uses native Undo"
	parent.add_child(node)
	return node

func row(parent):
	var node = HBoxContainer.new()
	node.add_constant_override("separation", 12)
	parent.add_child(node)
	return node
