extends Node

const Controls = preload("user://mod/tools/editor-plus/EditorNativeControls.gd")
const Page = preload("user://mod/tools/editor-plus/EditorNativeInspectorPage.gd")
const NativeGroups = preload("user://mod/tools/editor-plus/EditorNativeGroups.gd")
const NativePages = preload("user://mod/tools/editor-plus/EditorNativePages.gd")
const EDIT_ICON = "res://project_specific/gfx/icons/icon_editor_stroke.png"
var host
var editor
var inspector
var controls = Controls.new()
var toolbar_button
var thumbnail_button
var tab_button
var page
var content
var fields = {}
var selection_buttons = []
var step_field
var status
var active_field = ""
var requested = false
var elapsed = 0.0
var selection_ids = []
var groups_ui
var layer_field
var layer_button
var pages_ui
var precision
var feedback

func attach(owner, native_editor) -> void:
	if editor == native_editor and is_instance_valid(toolbar_button):
		return
	detach()
	host = owner
	editor = native_editor
	inspector = editor.tool_select.inspector
	var toolbar = editor.play_button.get_parent()
	toolbar_button = controls.icon_button(toolbar, EDIT_ICON, "Editor+ · precision, flips and ordering", self, "open")
	toolbar_button.name = "GoobEditorPlus"
	toolbar_button.rect_min_size = editor.play_button.rect_min_size
	toolbar.move_child(toolbar_button, editor.undo_button.get_index())
	# Keep the familiar native thumbnail action next to the Editor+ entry.
	thumbnail_button = controls.icon_button(toolbar, "res://project_specific/gfx/rewarded-ad-camera-icon.png", "Thumbnail view · hide grid, selection and Goober", self, "_thumbnail")
	thumbnail_button.name = "GoobEditorThumbnail"
	thumbnail_button.rect_min_size = editor.play_button.rect_min_size
	thumbnail_button.toggle_mode = true
	toolbar.move_child(thumbnail_button, toolbar_button.get_index()+1)
	var tabs = inspector.properties_button.get_parent()
	tab_button = controls.button(tabs, "", self, "open")
	tab_button.name = "GoobEditorPlusTab"
	tab_button.theme_type_variation = "Button_Tab"
	tab_button.toggle_mode = true
	tab_button.rect_min_size = Vector2(0,120)
	tab_button.hint_tooltip = "Editor+ · exact transforms and selection tools"
	var icon = tab_button.get_node("GoodIcon")
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(80,80)
	tab_button.icon_tex = load(EDIT_ICON)
	var grouper = tabs.get_node("ButtonGrouper")
	tab_button.group = grouper.button_group
	tab_button.connect("pressed", grouper, "button_pressed", [tab_button])
	grouper.buttons.append(tab_button)
	page = Page.new()
	page.name = "GoobEditorPlusPage"
	page.integration = self
	page.level_editor = editor
	page.theme = Controls.NATIVE_THEME
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.properties_panel.get_parent().add_child(page)
	inspector.panels.append(page)
	_build_page()
	editor.connect("tree_exiting",self,"detach")
	page.hide()
	for button in [inspector.properties_button,inspector.position_button,inspector.rotation_button]:
		button.connect("pressed", self, "_native_tab")
	refresh()

func _build_page() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	for side in ["left","right","top","bottom"]:
		margin.add_constant_override("margin_"+side,20)
	page.add_child(margin)
	content = VBoxContainer.new()
	content.add_constant_override("separation",10)
	margin.add_child(content)
	var header = controls.row(content)
	controls.label(header,"Editor+",true)
	controls.icon_button(header,"res://project_specific/gfx/icons/icon_info.png","Editor+ tutorial",host,"show_guide")
	feedback = Label.new()
	feedback.theme = Controls.NATIVE_THEME
	feedback.add_font_override("font",controls.number_font)
	feedback.rect_min_size.y = 64
	content.add_child(feedback)
	feedback.autowrap = true
	feedback.hide()
	precision = VBoxContainer.new()
	precision.add_constant_override("separation",10)
	content.add_child(precision)
	# Transform controls use the same page builders as before, within their
	# own section. Other feature controls retain their original backend.
	var page_content = content
	content = precision
	controls.label(content,"Precision",true)
	status = controls.label(content,"Select objects to edit.")
	status.autowrap = true
	status.rect_min_size.y = 62
	_pair("Position",[["x","X"],["y","Y"]])
	_pair("Size",[["width","W"],["height","H"]])
	var row = controls.row(content)
	controls.label(row,"Rotation")
	_add_field(row,"rotation","Rotation in degrees")
	_pair("Pivot",[["pivot_x","X"],["pivot_y","Y"]])
	var apply_row = controls.row(content)
	var apply = controls.button(apply_row,"Apply",self,"_apply_active")
	apply.hint_tooltip = "Apply the last focused number field. Enter does the same."
	selection_buttons.append(apply)
	controls.label(content,"Move",true)
	var move = controls.row(content)
	step_field = controls.field(move,"Move step in grid units, 0.01–10")
	step_field.text = str(host.step.value)
	step_field.rect_min_size.x = 98
	for entry in [["←",Vector2.LEFT],["↑",Vector2.UP],["↓",Vector2.DOWN],["→",Vector2.RIGHT]]:
		var arrow = controls.icon_button(move,"res://project_specific/level_editor/icons/icon-up.png","Move selection "+entry[0],self,"_nudge",[entry[1]])
		arrow.get_node("GoodIcon").rect_rotation = {Vector2.LEFT:-90,Vector2.UP:0,Vector2.DOWN:180,Vector2.RIGHT:90}[entry[1]]
		selection_buttons.append(arrow)
	var rotate = controls.row(content)
	for entry in [["-90°","rotate_shape",[-1]],["+90°","rotate_shape",[1]],["Flip H","mirror_selection",[true]],["Flip V","mirror_selection",[false]]]:
		selection_buttons.append(controls.button(rotate,entry[0],self,"_invoke",[entry[1],entry[2]]))
	controls.label(content,"Order",true)
	var order = controls.row(content)
	for entry in [["Back","back"],["-1","backward"],["+1","forward"],["Front","front"]]:
		var button = controls.button(order,entry[0],self,"_invoke",["change_order",[entry[1]]])
		button.hint_tooltip = "Order inside the same draw layer. Use Layer below to move across object types."
		selection_buttons.append(button)
	var layer_row = controls.row(content)
	controls.label(layer_row,"Layer")
	layer_field = controls.field(layer_row,"Draw layer -6 to 6. Higher layers draw in front across object types; Goobplayability required to display custom layers.")
	layer_field.connect("text_entered",self,"_apply_layer")
	layer_button = controls.button(layer_row,"Apply",self,"_apply_layer",[""])
	selection_buttons.append(layer_button)
	groups_ui = NativeGroups.new()
	groups_ui.build(self,content)
	content = page_content
	pages_ui = NativePages.new()
	pages_ui.build(self,content,precision)
	content.connect("minimum_size_changed",self,"_minimum_changed")
	call_deferred("_minimum_changed")

func _pair(title: String, values: Array) -> void:
	controls.label(content,title)
	var row = controls.row(content)
	for entry in values:
		var label = controls.label(row,entry[1])
		label.size_flags_horizontal = Control.SIZE_FILL
		label.rect_min_size.x = 28
		_add_field(row,entry[0],title+" "+entry[1])

func _add_field(parent, key: String, tip: String) -> void:
	var field = controls.field(parent,tip)
	field.connect("text_entered",self,"_apply",[key])
	field.connect("focus_entered",self,"_focus_field",[key])
	fields[key] = field

func _minimum_changed() -> void:
	if is_instance_valid(page) and is_instance_valid(content):
		page.rect_min_size.y = content.get_combined_minimum_size().y+40

func open() -> bool:
	if not is_instance_valid(editor) or not host.available() or not is_instance_valid(page):
		return false
	requested = true
	editor.select_tool(editor.Tool.Select,true)
	inspector.show()
	inspector._show_panel(page)
	var grouper = tab_button.get_parent().get_node("ButtonGrouper")
	grouper.selected = grouper.buttons.find(tab_button)
	refresh()
	return true

func _native_tab() -> void:
	requested = false
	if host.selected().empty():
		inspector.hide()

func _focus_field(key: String) -> void:
	active_field = key

func _apply(text: String, key: String) -> void:
	if not host.available() or host.selected().empty():
		return
	host.fields[key].text = text
	host.apply_field(key)
	status.text = host.message.text
	refresh()

func _apply_active() -> void:
	if fields.has(active_field):
		_apply(fields[active_field].text,active_field)

func _nudge(direction: Vector2) -> void:
	var text = step_field.text.strip_edges()
	if not text.is_valid_float() or is_nan(float(text)) or is_inf(float(text)) or float(text) < 0.01 or float(text) > 10:
		status.text = "Move step: 0.01–10 grid units."
		return
	host.step.value = float(text)
	_invoke("nudge",[direction])

func _invoke(method: String, args: Array) -> void:
	if host.available() and not host.selected().empty():
		host.callv(method,args)
		status.text = host.message.text
		refresh()

func _thumbnail() -> void:
	host.toggle_thumbnail()
	refresh()

func show_section(index: int) -> void:
	if open(): pages_ui.show_section(index)

func _apply_layer(text: String) -> void:
	if not host.available() or host.selected().empty():
		return
	if text.empty(): text = layer_field.text
	text = text.strip_edges()
	if not text.is_valid_integer() or int(text) < -6 or int(text) > 6:
		status.text = "Draw layer: whole numbers -6 to 6."
		return
	host.appearance_panel.layer_input.value = int(text)
	host.appearance_panel.change("layer")
	status.text = host.appearance_panel.status.text
	refresh()

func refresh() -> void:
	if not is_instance_valid(page) or not is_instance_valid(editor):
		return
	var nodes = host.selected()
	var enabled = host.available() and not nodes.empty()
	feedback.text = host.message.text
	feedback.visible = pages_ui.current != 0 and not feedback.text.empty() and feedback.text != pages_ui.message_at_entry
	groups_ui.refresh()
	layer_field.editable = enabled
	if not layer_field.has_focus():
		var layers = []
		for node in nodes:
			var visual = node.properties.get(host.appearance_panel.KEY,{})
			var layer = int(visual.get("layer",0)) if host.appearance_panel.valid(visual) else 0
			if not layers.has(layer): layers.append(layer)
		layer_field.text = str(layers[0]) if layers.size() == 1 else ""
		layer_field.placeholder_text = "Mixed" if layers.size() > 1 else "—"
	var current_ids = []
	for node in nodes:
		current_ids.append(node.get_instance_id())
	if selection_ids != current_ids:
		selection_ids = current_ids
		status.text = "Enter to apply · native Undo" if enabled else "Select objects to edit."
	thumbnail_button.pressed = host.thumbnail
	if requested and host.available():
		inspector.show()
	for button in selection_buttons:
		button.disabled = not enabled
	for key in fields:
		var field = fields[key]
		field.editable = enabled
		if field.has_focus():
			continue
		field.text = ""
		field.placeholder_text = "—"
		if not enabled:
			continue
		var value = host._value(nodes[0],key)
		var mixed = false
		for node in nodes:
			mixed = mixed or not is_equal_approx(value,host._value(node,key))
		if mixed:
			field.placeholder_text = "Mixed"
		else:
			field.text = str(value)

func poll(delta: float) -> void:
	if not is_instance_valid(page) or not page.is_visible_in_tree():
		return
	elapsed += delta
	if elapsed >= 0.12:
		elapsed = 0.0
		refresh()

func detach() -> void:
	requested = false
	if is_instance_valid(editor) and editor.is_connected("tree_exiting",self,"detach"):
		editor.disconnect("tree_exiting",self,"detach")
	if pages_ui != null:
		pages_ui.restore()
		pages_ui = null
	if is_instance_valid(inspector):
		for button in [inspector.properties_button,inspector.position_button,inspector.rotation_button]:
			if button.is_connected("pressed",self,"_native_tab"):
				button.disconnect("pressed",self,"_native_tab")
		inspector.panels.erase(page)
		if is_instance_valid(tab_button):
			var grouper = tab_button.get_parent().get_node("ButtonGrouper")
			grouper.buttons.erase(tab_button)
			if tab_button.pressed:
				grouper.selected = 0
				inspector._show_panel(inspector.properties_panel)
	for node in [toolbar_button,thumbnail_button,tab_button,page]:
		if is_instance_valid(node):
			node.queue_free()
	fields.clear()
	selection_buttons.clear()
	selection_ids.clear()
	groups_ui = null
	editor = null
	inspector = null

func _exit_tree() -> void:
	detach()
