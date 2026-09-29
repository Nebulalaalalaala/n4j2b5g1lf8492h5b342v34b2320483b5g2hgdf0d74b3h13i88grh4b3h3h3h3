extends Control

var host
var pages = []
var page = 0
var panel: PanelContainer
var picker: OptionButton
var diagram
var caption: Label
var steps: Label
var example: Label
var tip: Label
var scroll: ScrollContainer
var counter: Label
var previous: Button
var next: Button
var title_label
var custom_pages = false

func set_pages(content,title):
	custom_pages = true
	pages = content
	title_label.text = title
	picker.clear()
	for item in pages:
		picker.add_item(item.title)
	show_page(0)

func build(owner) -> void:
	host = owner
	pages = load(get_script().resource_path.get_base_dir().plus_file("EditorGuidePages.gd")).pages()
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color(0.02, 0.035, 0.04, 0.78)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(shade)
	panel = PanelContainer.new()
	panel.theme = host.panel.theme
	panel.add_stylebox_override("panel", host._style(Color("181c20")))
	add_child(panel)
	var body = VBoxContainer.new()
	body.add_constant_override("separation", 10)
	panel.add_child(body)
	var header = host._row(body)
	var title = host._label("Editor+ guide", 23, Color("9dd6bd"))
	title_label = title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	button(header, "×", "close")
	picker = OptionButton.new()
	host.properties._style_choice(picker)
	for item in pages:
		picker.add_item(item.title)
	picker.connect("item_selected", self, "show_page")
	body.add_child(picker)
	diagram = load(get_script().resource_path.get_base_dir().plus_file("EditorGuideDiagram.gd")).new()
	diagram.font = host.tool._make_font(14)
	diagram.rect_min_size = Vector2(600, 150)
	diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(diagram)
	caption = host._label("", 13, Color("9ba8ad"))
	caption.autowrap = true
	caption.rect_min_size.y = 36
	body.add_child(caption)
	scroll = ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.rect_min_size.y = 180
	body.add_child(scroll)
	var text = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_constant_override("separation", 12)
	scroll.add_child(text)
	steps = paragraph(text, "How to use it")
	example = paragraph(text, "Try this")
	tip = paragraph(text, "Keep in mind")
	var footer = host._row(body)
	previous = button(footer, "← Back", "advance", [-1])
	counter = host._label("", 13, Color("9ba8ad"))
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counter.align = Label.ALIGN_CENTER
	footer.add_child(counter)
	button(footer, "Open section", "open_section")
	next = button(footer, "Next →", "advance", [1])
	get_viewport().connect("size_changed", self, "fit")
	show_page(0)
	call_deferred("fit")
	hide()

func paragraph(parent, title: String) -> Label:
	parent.add_child(host._label(title, 16, Color("9dd6bd")))
	var label = host._label("", 15)
	label.autowrap = true
	label.rect_min_size.x = 580
	parent.add_child(label)
	return label

func button(parent, title: String, method: String, binds: Array = []) -> Button:
	var control = host._button(parent, title, "_refresh")
	control.disconnect("pressed", host, "_refresh")
	control.connect("pressed", self, method, binds)
	return control

func open(section: String = "") -> void:
	var index = 0
	for i in pages.size():
		if pages[i].section == section:
			index = i
			break
	show_page(index)
	show()
	fit()
	picker.grab_focus()

func close() -> void:
	hide()
	if not custom_pages and is_instance_valid(host.section_choice):
		host.section_choice.grab_focus()

func show_page(index: int) -> void:
	page = clamp(index, 0, pages.size() - 1)
	var data = pages[page]
	picker.select(page)
	diagram.kind = data.picture
	diagram.update()
	caption.text = data.caption
	steps.text = data.steps
	example.text = data.example
	tip.text = data.tip
	counter.text = "%d / %d" % [page + 1, pages.size()]
	previous.disabled = page == 0
	next.disabled = page == pages.size() - 1
	scroll.scroll_vertical = 0

func advance(amount: int) -> void:
	show_page(page + amount)

func open_section() -> void:
	if custom_pages:
		close()
		return
	for index in host.section_choice.get_item_count():
		if host.section_choice.get_item_text(index) == pages[page].section:
			host.section_choice.emit_signal("item_selected", index)
			break
	close()

func fit() -> void:
	if panel == null:
		return
	panel.rect_size = Vector2(680, 760)
	var viewport = get_viewport().get_visible_rect().size
	var stretch = max(0.01, abs(get_viewport().get_final_transform().get_scale().x))
	var factor = min(1.0 / stretch, min((viewport.x - 24) / panel.rect_size.x, (viewport.y - 24) / panel.rect_size.y))
	panel.rect_scale = Vector2.ONE * max(0.01, factor)
	panel.rect_position = (viewport - panel.rect_size * panel.rect_scale) / 2

func _input(event) -> void:
	if not visible or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()
