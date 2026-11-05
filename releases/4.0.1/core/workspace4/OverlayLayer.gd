extends CanvasLayer

# Persistent gameplay output, independent of F1 editor visibility.
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const Widget=preload("user://mod/core/workspace4/overlays/OverlayWidget.gd")
const Library=preload("user://mod/core/workspace4/overlays/OverlayLibrary.gd")
const PATH="user://goobplayability/overlays/layout.json"
var layout={}
var root: Control
var nodes={}
var foreground: CanvasLayer
var fps_root: Control
var sources
var editor=null
var editor_visible=false

func _ready():
	layer=64
	root=Control.new()
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_margins_preset(Control.PRESET_TOP_LEFT)
	add_child(root)
	foreground=CanvasLayer.new()
	foreground.layer=512
	add_child(foreground)
	fps_root=Control.new()
	fps_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	foreground.add_child(fps_root)
	sources=load("user://mod/core/workspace4/overlays/OverlaySources.gd").new()
	sources.name="OverlaySources"
	sources.tas_tool=get_parent().get("tas_tool")
	add_child(sources)
	get_viewport().connect("size_changed",self,"_place")
	load_layout()

func load_layout():
	var raw=Doc.read(PATH)
	layout=Doc.clean(raw,root.get_viewport_rect().size) if not raw.empty() else Doc.empty()
	if layout.empty(): layout=Doc.empty()
	rebuild()

func save_layout() -> bool:
	var clean=Doc.clean(layout,root.get_viewport_rect().size)
	if clean.empty(): return false
	layout=clean
	return Library.save(layout) and Doc.write(PATH,layout)

func apply_document(data: Dictionary) -> bool:
	var clean=Doc.clean(data)
	if clean.empty(): return false
	var previous=layout
	layout=clean
	if not save_layout():
		layout=previous
		return false
	rebuild()
	return true

func clear_active_layout() -> bool:
	# Deleting the active named layout must not leave its gameplay widgets alive.
	# Doc.write retains the previous active file for recovery. Do not create a
	# replacement named-library entry until the user explicitly saves a layout.
	var empty=Doc.empty()
	if not Doc.write(PATH,empty): return false
	layout=empty
	rebuild()
	return true

func rebuild():
	if root==null: return
	for child in fps_root.get_children():
		fps_root.remove_child(child)
		child.queue_free()
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	nodes.clear()
	layout=Doc.clean(layout,root.get_viewport_rect().size)
	if layout.empty(): layout=Doc.empty()
	root.visible=layout.enabled and not editor_visible
	fps_root.visible=root.visible
	if not layout.enabled: return # Disabled layouts do not decode images or allocate widget fonts.
	for item in layout.widgets:
		var node=Widget.new()
		node.setup(item,sources,Vector2(layout.width,layout.height))
		(fps_root if item.type=="fps" else root).add_child(node)
		nodes[item.id]=[node,item]
	_place()

func _place():
	if root==null or layout.empty(): return
	var view=root.get_viewport_rect().size
	var reference=Doc.reference(layout,view)
	var factor=min(view.x/reference.x,view.y/reference.y)
	var origin=(view-reference*factor)/2
	root.rect_position=origin
	root.rect_size=reference
	root.rect_scale=Vector2.ONE*factor
	fps_root.rect_position=origin
	fps_root.rect_size=reference
	fps_root.rect_scale=root.rect_scale
	for pair in nodes.values():
		var node=pair[0]
		var item=pair[1]
		var box=Doc.display_rect(item,layout,reference)
		node.rect_position=box.position
		node.rect_size=box.size
		node.rect_scale=Vector2.ONE
		node.rect_pivot_offset=node.rect_size/2
		node.visible=item.visible

func show_editor(menu):
	if editor==null or not is_instance_valid(editor):
		editor=load("user://mod/core/workspace4/overlays/OverlayEditor.gd").new()
		editor.setup(menu,self)
		menu.add_child(editor)
	editor.open()

func set_editor_visible(value: bool):
	editor_visible=value
	if root!=null: root.visible=layout.get("enabled",false) and not value
	if fps_root!=null: fps_root.visible=root.visible

# Kept for existing local consumers. New callers should use shared setup().
static func make_widget(item: Dictionary, scale: float) -> Control:
	var doc=Doc.clean({"version":2 if item.has("source") else 1,"widgets":[item]})
	var node=Widget.new()
	if not doc.widgets.empty(): node.setup(doc.widgets[0],null,Vector2(1920,1080),true)
	node.rect_scale=Vector2.ONE*scale
	return node

static func widget_text(item: Dictionary) -> String:
	if item.get("type")=="fps": return "%d FPS"%Engine.get_frames_per_second()
	if item.get("type")=="clock":
		var time=OS.get_time()
		return "%02d:%02d"%[time.hour,time.minute]
	return str(item.get("source",{}).get("text",item.get("text","Text")))
