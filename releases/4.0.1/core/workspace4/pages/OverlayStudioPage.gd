extends Reference
const Kit=preload("user://mod/core/workspace4/Kit.gd")
const Galaxy=preload("user://mod/core/workspace4/Galaxy.gd")
var menu
var layer
var status
func build(owner_menu, content: VBoxContainer, overlay_layer):
	menu=owner_menu
	layer=overlay_layer
	var row=Kit.row(content,16)
	var copy=Kit.column(row,8)
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	copy.add_child(menu.label("Your overlay, your space",24))
	Kit.hint(menu,copy,"Design in the expanded studio. Your layout stays live when F1 closes.")
	Kit.action(menu,row,"Open Overlay Studio","expand",self,"_open",[],true)
	var panel=PanelContainer.new()
	panel.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),22,16))
	content.add_child(panel)
	var body=Kit.column(panel,16)
	status=menu.label(str(layer.layout.get("name","My overlay")),20)
	body.add_child(status)
	for item in [["Universal Media Player","Music from Windows players or your own audio files."],["Keyboard","Show real input and arrange your own keys."],["Text, images & game information","Build a layout once. Use the same widgets in the preview and in game."]]:
		body.add_child(menu.label(item[0],17))
		Kit.hint(menu,body,item[1])
	var buttons=Kit.row(body,12)
	Kit.action(menu,buttons,"Show / hide in game","eye",self,"_toggle")
	Kit.action(menu,buttons,"Edit layout","layers",self,"_open")
func _open(): layer.show_editor(menu)
func _toggle():
	layer.layout.enabled=not layer.layout.enabled
	var saved=layer.save_layout()
	layer.rebuild()
	status.text=str(layer.layout.name)+(" · Live" if layer.layout.enabled else " · Hidden") if saved else "Could not save layout"
func export_data() -> Dictionary: return layer.layout.duplicate(true)
