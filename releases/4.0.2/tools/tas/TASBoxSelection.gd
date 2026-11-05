extends Reference

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")

var ids = {}
var anchor = 0

func choose(sections: Array, index: int, toggle: bool, extend: bool) -> void:
	if index < 0 or index >= sections.size():
		if not toggle and not extend: clear()
		return
	var id = int(sections[index].id)
	if extend:
		var start = index
		for i in sections.size():
			if int(sections[i].id) == anchor:
				start = i
				break
		select_range(sections, start, index, ids if toggle else {})
		return
	if not toggle: ids.clear()
	if ids.has(id): ids.erase(id)
	else: ids[id] = true
	anchor = id

func clear() -> void:
	ids.clear()
	anchor = 0

func select_range(sections: Array, start: int, end: int, base: Dictionary) -> void:
	ids = base.duplicate()
	for index in range(max(0,min(start,end)),min(sections.size(),max(start,end)+1)):
		ids[int(sections[index].id)] = true

func prune(sections: Array) -> void:
	var remaining = {}
	for section in sections:
		if ids.has(int(section.id)): remaining[int(section.id)] = true
	ids = remaining

func primary(sections: Array, preferred: int) -> int:
	if preferred >= 0 and preferred < sections.size() and ids.has(int(sections[preferred].id)):
		return preferred
	for index in sections.size():
		if ids.has(int(sections[index].id)): return index
	return -1

static func dragging_rect(from: Vector2, to: Vector2) -> Rect2:
	return Rect2(from, to-from).abs()

static func editing_text(control) -> bool:
	return control is LineEdit or control is TextEdit or control is SpinBox

static func context(owner, parent, font, method: String) -> PopupMenu:
	var popup = PopupMenu.new()
	popup.pause_mode = Node.PAUSE_MODE_PROCESS
	popup.add_font_override("font",font)
	popup.add_color_override("font_color",Galaxy.color("ink"))
	popup.add_color_override("font_color_disabled",Galaxy.color("dim"))
	popup.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),10,8))
	popup.add_stylebox_override("hover",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),6,6))
	popup.connect("id_pressed",owner,method)
	parent.add_child(popup)
	return popup

static func show_context(popup: PopupMenu, at: Vector2, viewport: Vector2, count: int, can_focus: bool, can_clear = null) -> void:
	popup.clear()
	popup.add_item("Focus camera here",0)
	popup.set_item_disabled(0,not can_focus)
	if can_clear != null:
		popup.add_item("Clear practice history…",2)
		popup.set_item_disabled(popup.get_item_index(2),not can_clear)
	popup.add_separator()
	popup.add_item("Delete box" if count == 1 else "Delete %d selected boxes" % count,1)
	popup.rect_size = Vector2.ZERO
	popup.popup()
	popup.rect_position = Vector2(clamp(at.x,0,max(0,viewport.x-popup.rect_size.x)),clamp(at.y,0,max(0,viewport.y-popup.rect_size.y)))

static func confirm(parent, owner_tool, target, method: String, title: String, detail: String, action: String, args := []) -> PopupPanel:
	var popup = PopupPanel.new()
	popup.pause_mode = Node.PAUSE_MODE_PROCESS
	popup.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("border"),16,16))
	parent.add_child(popup)
	var body = VBoxContainer.new()
	var width = clamp(parent.get_viewport().get_visible_rect().size.x-48.0,260.0,416.0)
	body.rect_min_size.x = width-32.0
	body.rect_size.x = body.rect_min_size.x
	body.add_constant_override("separation",12)
	popup.add_child(body)
	body.add_child(owner_tool._make_label(title,owner_tool._make_font(20),Galaxy.color("ink")))
	var explanation = owner_tool._make_label(detail,owner_tool._make_font(16),Galaxy.color("muted"))
	explanation.rect_min_size.x = body.rect_min_size.x
	explanation.rect_size.x = body.rect_min_size.x
	explanation.autowrap = true
	body.add_child(explanation)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGN_END
	buttons.add_constant_override("separation",8)
	body.add_child(buttons)
	for spec in [["Cancel",Galaxy.color("raised")],[action,Galaxy.color("danger").darkened(0.28)]]:
		var button = owner_tool._make_button(spec[0],spec[1],0)
		button.add_font_override("font",owner_tool._make_font(16))
		button.focus_mode = Control.FOCUS_NONE
		button.connect("pressed",popup,"hide")
		if spec[0] == action:
			var ink = Color.white if Galaxy.theme_name() == "light" else Galaxy.color("bg")
			for color in ["font_color","font_color_hover","font_color_pressed","font_color_focus"]:
				button.add_color_override(color,ink)
			button.connect("pressed",target,method,args)
		buttons.add_child(button)
	popup.connect("popup_hide",popup,"queue_free")
	popup.popup_centered_minsize(Vector2(width,170))
	return popup
