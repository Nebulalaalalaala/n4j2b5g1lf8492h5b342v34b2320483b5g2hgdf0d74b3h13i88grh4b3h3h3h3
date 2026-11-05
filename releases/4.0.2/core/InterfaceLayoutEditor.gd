extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
var service
var screen
var scope
var targets = []
var handles = []
var selected = null
var root
var toolbar
var caption
var ui
var dragging = false
var resizing = false
var grab_offset = Vector2.ZERO
var initial_scale = 1.0
var initial_width = 1.0
var hidden = []
var group = null
var old_page = -1
var expanded_before = false
var home = null
var closed = false

func _ready():
	layer = 120
	pause_mode = Node.PAUSE_MODE_PROCESS
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	var source = screen.get_ref()
	source.close_overlay()
	if scope == "home":
		home = targets[0].space.get_ref()
		var paginator = source.get_parent()
		group = paginator.get("button_grouper")
		if group != null:
			old_page = group.selected
			group.set_selected(paginator.pages.find(home.get_parent()))
		expanded_before = home.expanded
		home.layout_editing = true
		home.refresh()
		home._set_expanded(true)
		home._fit()
	else:
		for node in source.get_parent().get_children():
			if node is Control:
				hidden.append([weakref(node), node.visible])
				node.hide()
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(root)
	toolbar = ui.card(root, ui.NAVY, 26, 26)
	var column = ui.box(toolbar, true, 10)
	caption = ui.label(column, "Drag a widget · Scroll or use − / + to resize", "body", ui.WHITE, Label.ALIGN_CENTER)
	caption.autowrap = false
	var row = ui.box(column, false, 10)
	row.alignment = BoxContainer.ALIGN_CENTER
	ui.button(row, "−", "quiet", self, "change_scale", -0.05)
	ui.button(row, "+", "quiet", self, "change_scale", 0.05)
	ui.button(row, "Reset selected", "quiet", self, "reset_selected")
	ui.button(row, "Reset all", "quiet", self, "reset_all")
	ui.button(row, "Cancel", "quiet", self, "finish", false)
	ui.button(row, "Save", "primary", self, "finish", true)
	for binding in targets:
		binding.editing = true
		binding.draft = service.layouts.get(binding.key)
		if binding.draft != null:
			binding.draft = binding.draft.duplicate(true)
		binding.apply()
		var frame = Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var outline = ui.flat(Color(0, 0, 0, 0), 12, 0, 0, ui.SKY_LIGHT, false)
		outline.set_border_width_all(3)
		outline.border_color = Color.white
		frame.add_stylebox_override("panel", outline)
		root.add_child(frame)
		handles.append([binding, frame])
	toolbar.raise()
	selected = targets[0]
	_fit()
	toolbar.connect("minimum_size_changed", self, "_fit", [], CONNECT_DEFERRED)
	call_deferred("_fit")
	get_viewport().connect("size_changed", self, "_fit", [], CONNECT_DEFERRED)

func _fit():
	if toolbar == null:
		return
	var size = get_viewport().get_visible_rect().size
	var factor = min(1.0, (size.x - 24) / max(1, toolbar.get_combined_minimum_size().x))
	toolbar.rect_size = toolbar.get_combined_minimum_size()
	toolbar.rect_scale = Vector2.ONE * factor
	toolbar.rect_position = Vector2((size.x - toolbar.rect_size.x * factor) * 0.5, 18)

func _process(_delta):
	for pair in handles:
		if not is_instance_valid(pair[0]) or not pair[0].is_available():
			finish(false)
			return
		var bounds = pair[0].window_rect()
		pair[1].rect_position = bounds.position - Vector2.ONE * 5
		pair[1].rect_size = bounds.size + Vector2.ONE * 10
		pair[1].modulate = ui.PINK_LIGHT if pair[0] == selected else ui.SKY_LIGHT
	if selected != null:
		caption.text = "%s · %d%% · Drag to move, scroll to resize" % [selected.title, round(float(selected.current().scale) * 100)]

func _input(event):
	if closed:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_ESCAPE:
		finish(false)
		get_tree().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT and not event.pressed:
			dragging = false
			resizing = false
		if toolbar.get_global_rect().has_point(event.position):
			return
		if event.pressed and event.button_index == BUTTON_LEFT:
			for i in range(handles.size() - 1, -1, -1):
				var binding = handles[i][0]
				var bounds = binding.window_rect().grow(5)
				if bounds.has_point(event.position):
					selected = binding
					grab_offset = event.position - binding.window_rect().position
					resizing = event.position.distance_to(bounds.end) < 28
					dragging = not resizing
					initial_scale = float(binding.current().scale)
					initial_width = max(1, binding.window_rect().size.x)
					break
		elif event.pressed and event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			change_scale(0.05 if event.button_index == BUTTON_WHEEL_UP else -0.05)
		get_tree().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if dragging and selected != null:
			selected.move_window(event.position - grab_offset)
		elif resizing and selected != null:
			selected.resize_to(initial_scale * max(1, event.position.x - selected.window_rect().position.x) / initial_width)
		get_tree().set_input_as_handled()

func change_scale(amount):
	if selected != null and selected.is_available():
		selected.resize_to(float(selected.current().scale) + amount)

func reset_selected():
	if selected != null:
		selected.draft = null
		selected.apply()

func reset_all():
	for binding in targets:
		binding.draft = null
		binding.apply()

func finish(save):
	if closed:
		return
	closed = true
	var draft = service.layouts.duplicate(true)
	for binding in targets:
		if not is_instance_valid(binding):
			continue
		if save:
			if binding.draft == null:
				draft.erase(binding.key)
			else:
				draft[binding.key] = binding.draft.duplicate(true)
		binding.editing = false
		binding.draft = null
	if save:
		service.commit(draft)
	else:
		service.refresh()
	_restore()
	service.editor = null
	queue_free()

func _restore():
	if is_instance_valid(home):
		home.layout_editing = false
		home._set_expanded(expanded_before)
		home.refresh()
		home._fit()
	if is_instance_valid(group) and old_page >= 0:
		group.set_selected(old_page)
	for item in hidden:
		var node = item[0].get_ref()
		if is_instance_valid(node):
			node.visible = item[1]
	var source = screen.get_ref()
	if is_instance_valid(source):
		source.call_deferred("_open_prefs")

func _exit_tree():
	if not closed:
		for binding in targets:
			if is_instance_valid(binding):
				binding.editing = false
				binding.draft = null
		_restore()
		service.editor = null
