extends VBoxContainer
var service
var workspace
var buttons = {}
var message: Label

func build(owner, menu) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	service = owner
	workspace = menu
	service.view = self
	var instruction = workspace.label("Click a shortcut, then press a key or chord. Esc cancels.",14,workspace.MUTED)
	instruction.autowrap = true
	add_child(instruction)
	message = workspace.label("",14,workspace.MINT)
	message.autowrap = true
	add_child(message)
	var group = ""
	for spec in service.definitions:
		if not service.available(spec[0]): continue
		if str(spec[0]).begins_with("open:") and not workspace.enabled(spec[5]): continue
		if spec[1] != group:
			group = spec[1]
			add_child(workspace.label(group,17))
		var row = HBoxContainer.new()
		add_child(row)
		var title = workspace.label(spec[2],15)
		title.autowrap = true
		title.rect_min_size.x = 120
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var pick = Button.new()
		pick.rect_min_size = Vector2(160,36)
		pick.add_font_override("font",workspace.font(15))
		_style_button(pick)
		pick.connect("pressed",self,"capture",[spec[0]])
		row.add_child(pick)
		buttons[spec[0]] = pick
		for item in [["×","clear"],["Reset","reset"]]:
			var b = Button.new()
			b.text = item[0]
			b.hint_tooltip = "Unbind" if item[1]=="clear" else "Reset shortcut"
			b.rect_min_size = Vector2(36 if item[1]=="clear" else 62,36)
			if spec[0]=="menu" and item[1]=="clear":
				b.disabled = true
				b.hint_tooltip = "Keep a shortcut to reopen the interface."
			_style_button(b)
			b.connect("pressed",self,item[1],[spec[0]])
			row.add_child(b)
	refresh()

func _style_button(button: Button) -> void:
	button.add_font_override("font",workspace.font(15))
	button.add_color_override("font_color",workspace.INK)
	button.add_color_override("font_color_hover",workspace.MINT)
	button.add_color_override("font_color_disabled",workspace.MUTED)
	button.add_stylebox_override("normal",workspace.box(workspace.BG,workspace.BORDER,8))
	button.add_stylebox_override("hover",workspace.box(workspace.SELECTED,workspace.MINT,8))
	button.add_stylebox_override("pressed",workspace.box(workspace.SELECTED,workspace.MINT,8))
	button.add_stylebox_override("disabled",workspace.box(workspace.BG,workspace.BORDER,8))

func refresh() -> void:
	for id in buttons:
		var event = service.key_event(id)
		buttons[id].text = "Press shortcut…" if service.capture_id==id else ("Unbound" if event.scancode==0 else event.as_text())

func capture(id: String) -> void:
	service.capture_id = id
	message.text = "Esc cancels. Conflicting shortcuts will be rejected."
	refresh()

func clear(id: String) -> void:
	service.capture_id = ""
	service.assign(id,0)

func reset(id: String) -> void:
	service.capture_id = ""
	for spec in service.definitions:
		if spec[0] == id:
			var event = InputEventKey.new()
			event.scancode = spec[3]
			event.control = bool(spec[4]&1)
			event.alt = bool(spec[4]&2)
			event.shift = bool(spec[4]&4)
			var conflict = service.conflict(id,event) if event.scancode!=0 else ""
			if not conflict.empty():
				message.text = "Default is already used: " + conflict
				return
			service.assign(id,spec[3],spec[4])
			return
