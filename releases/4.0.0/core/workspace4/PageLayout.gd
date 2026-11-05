extends Reference

# Presentation helpers for pages backed by existing module controllers.
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
var menu
var grids = []

func _init(owner = null):
	menu = owner

func move(node, parent):
	if not is_instance_valid(node): return
	if node.get_parent() != null: node.get_parent().remove_child(node)
	parent.add_child(node)
	if node is Control:
		node.rect_scale = Vector2.ONE
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.show()

func note(parent, text, tooltip = ""):
	var result = menu.label(text,14,Galaxy.color("muted"))
	result.autowrap = true
	result.hint_tooltip = tooltip
	if not tooltip.empty(): result.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(result)
	return result

func badge(parent, text, color_key = "accent"):
	var result = menu.chip(text,Galaxy.color(color_key))
	# The shared chip lightens its ink; keep light-mode badges readable.
	result.get_child(0).add_color_override("font_color",Galaxy.color(color_key))
	parent.add_child(result)
	return result

func grid(parent, minimum = 250):
	var result = GridContainer.new()
	result.columns = 2
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_constant_override("hseparation",12)
	result.add_constant_override("vseparation",12)
	parent.add_child(result)
	grids.append([result,minimum])
	result.connect("resized",self,"fit_grid",[result,minimum])
	var ancestor = parent
	while ancestor!=null:
		if ancestor is ScrollContainer:
			if not ancestor.is_connected("resized",self,"fit_all"):
				ancestor.connect("resized",self,"fit_all")
			break
		ancestor = ancestor.get_parent()
	fit_grid(result,minimum)
	return result

func fit_all():
	for entry in grids:
		if is_instance_valid(entry[0]): fit_grid(entry[0],entry[1])

func fit_grid(control, minimum):
	if is_instance_valid(control):
		var available = control.rect_size.x
		var ancestor = control.get_parent()
		while ancestor!=null:
			if ancestor is ScrollContainer:
				available = max(1,ancestor.rect_size.x-36)
				break
			ancestor = ancestor.get_parent()
		var required = minimum
		for child in control.get_children():
			if child is Control and child.visible: required = max(required,child.get_combined_minimum_size().x)
		control.columns = int(clamp(floor((available+12)/float(required+12)),1,3))

func wrap(row, minimum = 180):
	var parent = row.get_parent()
	var index = row.get_index()
	var result = grid(parent,minimum)
	parent.move_child(result,index)
	for child in row.get_children(): move(child,result)
	row.queue_free()
	fit_grid(result,minimum)
	return result

func card(parent, title, icon_name = "", color_key = "accent"):
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),16,12))
	parent.add_child(panel)
	var column = Kit.column(panel,10)
	if not title.empty():
		var heading = Kit.row(column)
		if not icon_name.empty():
			var icon = TextureRect.new()
			icon.texture = Galaxy.icon(icon_name,Galaxy.color(color_key),20)
			icon.rect_min_size = Vector2(20,20)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			heading.add_child(icon)
		var text = menu.label(title,17,Galaxy.color("ink"))
		text.autowrap = true
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(text)
	return column

func choice(parent, values, selected, target, method):
	var result = OptionButton.new()
	result.focus_mode = Control.FOCUS_NONE
	for value in values: result.add_item(str(value))
	result.select(clamp(selected,0,max(0,values.size()-1)))
	result.connect("item_selected",target,method)
	parent.add_child(result)
	skin(result)
	return result

# Only explicitly moved legacy module views are restyled. No native UI search.
func skin(node):
	if node is Label:
		var size = 15
		if node.has_font_override("font") and node.get_font("font") is DynamicFont:
			size = int(clamp(node.get_font("font").size,14,20))
		node.add_font_override("font",menu.font(size))
		node.add_color_override("font_color",Galaxy.color("ink"))
		node.add_color_override("font_color_shadow",Color.transparent)
		node.autowrap = true
	elif node is LineEdit:
		node.add_font_override("font",menu.font(15))
		for state in ["normal","focus","read_only"]:
			node.add_stylebox_override(state,Galaxy.box(Galaxy.color("raised"),Galaxy.color("accent" if state=="focus" else "line"),10))
		node.add_color_override("font_color",Galaxy.color("ink"))
		node.add_color_override("cursor_color",Galaxy.color("accent"))
		node.add_color_override("font_color_uneditable",Galaxy.color("muted"))
		node.rect_min_size.x = min(node.rect_min_size.x,160)
	elif node is CheckBox or node is CheckButton:
		node.add_font_override("font",menu.font(15))
	elif node is Button:
		node.add_font_override("font",menu.font(15))
		for state in ["font_color","font_color_hover","font_color_pressed","font_color_focus"]:
			node.add_color_override(state,Galaxy.color("ink"))
		node.add_color_override("font_color_disabled",Galaxy.color("dim"))
		for state in ["normal","hover","pressed","disabled"]:
			node.add_stylebox_override(state,Galaxy.box(Galaxy.color("raised" if state=="normal" else "hover"),Galaxy.color("border"),10))
		node.add_stylebox_override("focus",StyleBoxEmpty.new())
		node.rect_min_size = Vector2(min(node.rect_min_size.x,140),34)
		if node is OptionButton:
			node.add_icon_override("arrow",Galaxy.icon("chev-down",Galaxy.color("muted"),14))
			node.get_popup().add_font_override("font",menu.font(15))
			node.get_popup().add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),10))
			node.get_popup().add_color_override("font_color",Galaxy.color("ink"))
			node.get_popup().add_color_override("font_color_hover",Galaxy.color("ink"))
	elif node is PanelContainer:
		node.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),12))
	elif node is ItemList:
		node.add_font_override("font",menu.font(14))
		node.add_stylebox_override("bg",Galaxy.box(Galaxy.color("raised"),Galaxy.color("border"),8))
		node.add_color_override("font_color",Galaxy.color("ink"))
		node.add_color_override("font_color_selected",Galaxy.color("ink"))
	elif node is HSlider:
		node.add_icon_override("grabber",Kit.slider_thumb())
		node.add_icon_override("grabber_highlight",Kit.slider_thumb())
	elif node is ScrollContainer:
		node.scroll_horizontal_enabled = false
		node.rect_min_size.x = min(node.rect_min_size.x,180)
	for child in node.get_children(): skin(child)
