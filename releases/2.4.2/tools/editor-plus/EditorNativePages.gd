extends Reference

# Presentation adapter only: retain the existing controls, signals, state and
# feature implementations. Return them to their persistent module on exit.
const Controls = preload("user://mod/tools/editor-plus/EditorNativeControls.gd")
const PressSound = preload("res://goodoh/ui/components/PlaySoundOnPress.gd")
const CLICK = preload("res://goodoh/audio/click1.ogg")
const TITLES = ["Transform", "Properties", "Animation", "Groups", "Recovery", "Library", "Appearance", "Lasers"]
var ui
var pages = []
var original_parent
var current = 0
var buttons = []
var font
var message_at_entry = ""

func build(owner, parent, precision) -> void:
	ui = owner
	font = Controls.FONT.duplicate()
	font.size = 32
	# The stock 50px font has -20px top/bottom spacing. Keeping that fixed
	# when reducing its size collapses line height and overlaps wrapped text.
	font.extra_spacing_top = -6
	font.extra_spacing_bottom = -6
	var navigation = GridContainer.new()
	navigation.columns = 2
	navigation.add_constant_override("hseparation",12)
	navigation.add_constant_override("vseparation",10)
	parent.add_child(navigation)
	parent.move_child(navigation,1)
	for i in range(TITLES.size()):
		var button = ui.controls.button(navigation,TITLES[i],self,"show_section",[i])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.rect_min_size.y = 62
		buttons.append(button)
	pages.append(precision)
	original_parent = ui.host.content_scroll.get_child(0)
	var children = original_parent.get_children()
	for i in range(1,children.size()):
		var feature = children[i]
		original_parent.remove_child(feature)
		parent.add_child(feature)
		feature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style(feature)
		feature.connect("minimum_size_changed",ui,"_minimum_changed")
		pages.append(feature)
	_style(ui.host.confirmation)
	ui.host._refresh_recovery()
	show_section(0)

func show_section(index: int) -> void:
	if index < 0 or index >= pages.size(): return
	current = index
	message_at_entry = ui.host.message.text
	for i in range(pages.size()):
		pages[i].visible = i == index
		buttons[i].pressed = i == index
	ui.inspector.scroll_container.scroll_vertical = 0
	refresh()
	ui.call_deferred("_minimum_changed")

func refresh() -> void:
	if pages.empty(): return
	match current:
		1: ui.host.properties.refresh()
		2: ui.host.tween_panel.refresh()
		3: ui.host.groups_panel.refresh()
		6: ui.host.appearance_panel.refresh()
		7: ui.host.laser_panel.refresh()

func restore() -> void:
	# Called from the editor's tree_exiting signal, before its children are
	# destroyed. These seven controls belong to the persistent Editor+ module.
	if is_instance_valid(original_parent):
		for i in range(1,pages.size()):
			var feature = pages[i]
			if not is_instance_valid(feature): continue
			if feature.is_connected("minimum_size_changed",ui,"_minimum_changed"):
				feature.disconnect("minimum_size_changed",ui,"_minimum_changed")
			feature.get_parent().remove_child(feature)
			original_parent.add_child(feature)
		original_parent.current_tab = 0
	pages.clear()
	buttons.clear()

func _style(node) -> void:
	if node is Control:
		# Remove only the legacy window's visual overrides. Never replace
		# controls: backend references and all existing callbacks stay valid.
		for property in node.get_property_list():
			var key = String(property.name)
			if key.begins_with("custom_styles/"): node.remove_stylebox_override(key.get_slice("/",1))
			if key.begins_with("custom_colors/"): node.remove_color_override(key.get_slice("/",1))
		node.theme = Controls.NATIVE_THEME
		node.rect_min_size.x = 0
		node.rect_scale = Vector2.ONE
	if node is Label:
		node.add_font_override("font",font)
		node.valign = Label.VALIGN_CENTER
		if node.get_parent() is VBoxContainer: node.autowrap = true
		if node.autowrap:
			node.rect_min_size.y = 64
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif node is LineEdit:
		node.theme = Controls.FIELD_THEME
		node.add_font_override("font",font)
		node.align = LineEdit.ALIGN_CENTER
		node.expand_to_text_length = false
		node.rect_min_size.y = 70
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if node == ui.host.library_panel.search:
			node.hint_tooltip = node.placeholder_text
			node.placeholder_text = "Search levels"
	elif node is SpinBox:
		node.theme = Controls.FIELD_THEME
		node.add_font_override("font",font)
		node.rect_min_size = Vector2(140,70)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif node is OptionButton:
		node.add_font_override("font",font)
		node.get_popup().add_font_override("font",font)
		node.get_popup().theme = Controls.NATIVE_THEME
		node.align = Button.ALIGN_CENTER
		node.clip_text = true
		node.rect_min_size.y = 70
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif node is CheckBox:
		node.add_font_override("font",font)
		node.align = Button.ALIGN_CENTER
		node.rect_min_size.y = 70
		if node == ui.host.autosave:
			node.text = "Autosave · every minute"
	elif node is Button:
		node.theme_type_variation = "Button_White"
		node.add_font_override("font",font)
		node.align = Button.ALIGN_CENTER
		node.rect_min_size.y = 70
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var short = {"Apply to Selection":"Apply", "Save groups":"Save", "Save snapshot":"Snapshot", "Restore selected":"Restore", "Open selected":"Open level", "Reset native cycle":"Reset cycle"}
		if short.has(node.text):
			if node.hint_tooltip.empty(): node.hint_tooltip = node.text
			node.text = short[node.text]
	elif node is ItemList:
		node.theme = Controls.FIELD_THEME
		node.add_font_override("font",font)
		node.add_stylebox_override("bg",Controls.FIELD_THEME.get_stylebox("normal","LineEdit"))
		node.add_stylebox_override("selected",Controls.NATIVE_THEME.get_stylebox("pressed","Button_White"))
		node.add_stylebox_override("selected_focus",Controls.NATIVE_THEME.get_stylebox("pressed","Button_White"))
		node.rect_min_size.y = max(250,node.rect_min_size.y)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if node is BoxContainer: node.add_constant_override("separation",12)
	for child in node.get_children(): _style(child)
	if node is BaseButton and node.get_node_or_null("EditorNativePressSound") == null:
		var sound = PressSound.new()
		sound.name = "EditorNativePressSound"
		sound.audio_stream = CLICK
		sound.bus = "sfx_main"
		node.add_child(sound)
	# Button-heavy rows must wrap in the narrow native inspector, instead of
	# expanding its width. References to the buttons themselves are retained.
	if node is HBoxContainer and node.get_child_count() >= 3:
		var all_buttons = true
		for child in node.get_children(): all_buttons = all_buttons and child is Button
		if all_buttons:
			var grid = GridContainer.new()
			grid.columns = 2 if node.get_child_count() < 5 else 3
			grid.add_constant_override("hseparation",12)
			grid.add_constant_override("vseparation",10)
			var parent = node.get_parent()
			var index = node.get_index()
			parent.add_child(grid)
			parent.move_child(grid,index)
			for child in node.get_children():
				node.remove_child(child)
				grid.add_child(child)
			parent.remove_child(node)
			node.queue_free()
