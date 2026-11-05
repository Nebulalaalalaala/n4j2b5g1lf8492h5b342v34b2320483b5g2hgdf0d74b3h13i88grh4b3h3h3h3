extends Node

# Native GooberDash's CheckBox theme contains candy-button styleboxes with
# fixed margins. Those are unsuitable for tool labels. Scope this repair to
# mod-owned controls; the game's own settings keep their original assets.
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Motion = preload("user://mod/core/workspace4/ControlMotion.gd")
var tool
var watched = []
var textures = {}
var signature = ""
var last_poll = 0

static func ensure(owner):
	var existing = owner.get_node_or_null("GoobControlSkin")
	if existing!=null: return existing
	var skin = load("user://mod/core/workspace4/ControlSkin.gd").new()
	skin.name = "GoobControlSkin"
	owner.add_child(skin)
	skin.configure(owner)
	return skin

func configure(owner) -> void:
	tool = owner
	pause_mode = Node.PAUSE_MODE_PROCESS
	signature = Galaxy.color("accent").to_html()+Galaxy.color("ink").to_html()
	get_tree().connect("node_added",self,"_added")
	_scan(tool)

func _scan(node: Node) -> void:
	_added(node)
	for child in node.get_children(): _scan(child)

func _added(node: Node) -> void:
	if node is Control and _owned(node): Motion.bind_control(node)
	if not node is CheckBox and not node is CheckButton: return
	var reference = weakref(node)
	# Style before a container's first layout measurement. Deferring every
	# first application can provoke rebuild/resize loops in item galleries.
	_consider(reference)
	call_deferred("_finish",reference)

func _finish(reference: WeakRef) -> void:
	var check = reference.get_ref()
	if not is_instance_valid(check) or not _owned(check): return
	if not check.has_meta("goob_control_skin"):
		_consider(reference)
		return
	# A creator may add the inherited pill style after add_child(). Repair
	# that case once; don't continuously invalidate otherwise settled layouts.
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		if not check.get_stylebox(state) is StyleBoxEmpty:
			apply(check)
			return

func _owned(node: Node) -> bool:
	var parent = node.get_parent()
	while parent!=null:
		if parent==tool or parent.is_in_group("goobplayability_ui"): return true
		# A modded game/physics script is not an interface boundary. Only
		# explicit controls/layers count, keeping native game menus untouched.
		if parent is Control or parent is CanvasLayer:
			var script = parent.get_script()
			if script!=null and script.resource_path.begins_with(get_script().resource_path.get_base_dir().get_base_dir().get_base_dir()+"/"): return true
		parent = parent.get_parent()
	return false

func _consider(reference: WeakRef) -> void:
	var check = reference.get_ref()
	if not is_instance_valid(check) or not _owned(check): return
	if check.has_meta("goob_control_skin"): return
	check.set_meta("goob_control_skin",true)
	watched.append(reference)
	apply(check)

func apply(check: BaseButton) -> void:
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		check.add_stylebox_override(state,StyleBoxEmpty.new())
	check.add_stylebox_override("focus",Galaxy.box(Color.transparent,Galaxy.color("accent"),2,5) if check.focus_mode!=Control.FOCUS_NONE else StyleBoxEmpty.new())
	for state in ["font_color","font_color_pressed","font_color_focus"]: check.add_color_override(state,Galaxy.color("ink"))
	for state in ["font_color_hover","font_color_hover_pressed"]: check.add_color_override(state,Galaxy.color("accent"))
	check.add_color_override("font_color_disabled",Galaxy.color("dim"))
	if check is CheckBox:
		for pair in [["checked",true],["unchecked",false],["checked_disabled",true],["unchecked_disabled",false]]:
			# Preserve custom item/check icons supplied by an individual tool.
			var marker = "goob_skin_icon_"+pair[0]
			if not check.has_icon_override(pair[0]) or (check.has_meta(marker) and check.get_meta(marker)==check.get_icon(pair[0])):
				var icon = _check_icon(pair[1],"disabled" in pair[0])
				check.add_icon_override(pair[0],icon)
				check.set_meta(marker,icon)
	elif check is CheckButton:
		for pair in [["on",true],["off",false],["on_disabled",true],["off_disabled",false]]:
			var marker = "goob_skin_icon_"+pair[0]
			if not check.has_icon_override(pair[0]) or (check.has_meta(marker) and check.get_meta(marker)==check.get_icon(pair[0])):
				var icon = _switch_icon(pair[1],"disabled" in pair[0])
				check.add_icon_override(pair[0],icon)
				check.set_meta(marker,icon)

func _check_icon(on: bool,disabled: bool) -> Texture:
	var accent = Galaxy.color("accent")
	var key = "check:%s:%s:%s"%[on,disabled,accent.to_html()+Galaxy.color("raised").to_html()]
	if textures.has(key): return textures[key]
	var pixels = Image.new()
	pixels.create(72,72,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.transparent)
	pixels.lock()
	for y in 72:
		for x in 72:
			var p = Vector2(x+0.5,y+0.5)
			var q = Vector2(abs(p.x-36)-24,abs(p.y-36)-24)
			var edge = Vector2(max(q.x,0),max(q.y,0)).length()+min(max(q.x,q.y),0)-9
			var alpha = clamp(0.5-edge,0.0,1.0)
			if alpha<=0: continue
			var color = accent if on else (Galaxy.color("line") if edge>-4 else Galaxy.color("raised"))
			if on:
				var a = Geometry.get_closest_point_to_segment_2d(p,Vector2(19,36),Vector2(31,47))
				var b = Geometry.get_closest_point_to_segment_2d(p,Vector2(31,47),Vector2(53,25))
				var ink = clamp(4.0-min(p.distance_to(a),p.distance_to(b)),0,1)
				color = color.linear_interpolate(Galaxy.color("accent_ink"),ink)
			color.a = alpha*(0.45 if disabled else 1.0)
			pixels.set_pixel(x,y,color)
	pixels.unlock()
	return _texture(pixels,Vector2(18,18),key)

func _switch_icon(on: bool,disabled: bool) -> Texture:
	var accent = Galaxy.color("accent")
	var key = "switch:%s:%s:%s"%[on,disabled,accent.to_html()+Galaxy.color("raised").to_html()]
	if textures.has(key): return textures[key]
	var pixels = Image.new()
	pixels.create(144,80,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.transparent)
	pixels.lock()
	for y in 80:
		for x in 144:
			var p = Vector2(x+0.5,y+0.5)
			var center = Vector2(clamp(p.x,40,104),40)
			var alpha = clamp(36-p.distance_to(center),0,1)
			if alpha<=0: continue
			var color = accent if on else Galaxy.color("line")
			var knob = clamp(26-p.distance_to(Vector2(104 if on else 40,40)),0,1)
			color = color.linear_interpolate(Color.white,knob)
			color.a = alpha*(0.45 if disabled else 1.0)
			pixels.set_pixel(x,y,color)
	pixels.unlock()
	return _texture(pixels,Vector2(36,20),key)

func _texture(pixels: Image,size: Vector2,key: String) -> Texture:
	var texture = ImageTexture.new()
	texture.create_from_image(pixels,Texture.FLAG_FILTER)
	texture.set_size_override(size)
	textures[key] = texture
	return texture

func _process(_delta: float) -> void:
	if OS.get_ticks_msec()-last_poll<500: return
	last_poll = OS.get_ticks_msec()
	var next = Galaxy.color("accent").to_html()+Galaxy.color("ink").to_html()
	var live = []
	for reference in watched:
		if is_instance_valid(reference.get_ref()): live.append(reference)
	watched = live
	if next==signature: return
	signature = next
	for ref in watched.duplicate():
		var check = ref.get_ref()
		if not is_instance_valid(check): watched.erase(ref)
		else: apply(check)
