extends Node2D
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
var follow = null
var layer = {}
var body_color = Color.white
var points = []
var clock = 0.0
var elapsed = 0.0
var gradient: Gradient
var width_curve: Curve
var alpha_curve: Curve

func configure(source, settings, color):
	follow = source
	set_style(settings,color)
	points.clear()
	clock = 0.0

func set_style(settings, color):
	layer = settings.duplicate(true)
	body_color = color
	gradient = Gradient.new()
	var stops = PoolRealArray()
	var colors = PoolColorArray()
	for point in layer.gradient:
		stops.append(point.t)
		var value = Document.color(point.color)
		if layer.color_mode == "goober":
			value.r = color.r
			value.g = color.g
			value.b = color.b
		colors.append(value)
	gradient.offsets = stops
	gradient.colors = colors
	width_curve = _curve(layer.size_curve)
	alpha_curve = _curve(layer.alpha_curve)
	update()

func _curve(points_data) -> Curve:
	var curve = Curve.new()
	for point in points_data:
		curve.add_point(Vector2(point.t,point.v),0,0,Curve.TANGENT_LINEAR,Curve.TANGENT_LINEAR)
	return curve

func _process(delta):
	if not is_instance_valid(follow) or layer.empty(): return
	# Points are world coordinates. Keep their canvas anchored in world space
	# between samples while the emitter's parent follows the native renderer.
	global_transform = Transform2D.IDENTITY
	if not follow.is_visible_in_tree():
		if not points.empty():
			points.clear()
			update()
		return
	clock += delta
	elapsed += delta
	var position = follow.global_transform.xform(Vector2(layer.offset_x,layer.offset_y))
	while not points.empty() and clock-points[0][1]>float(layer.lifetime): points.pop_front()
	if not points.empty() and position.distance_squared_to(points.back()[0])>122500:
		points.clear() # Do not draw a ribbon across teleports or checkpoint restores.
	if elapsed>=1.0/60.0:
		elapsed = 0
		if points.empty() or position.distance_squared_to(points.back()[0])>=1.0:
			points.append([position,clock])
			if points.size()>181: points.pop_front()
		# Geometry and gradients only change at the 60 Hz sample boundary.
		# The parent still follows the native renderer at display frame rate.
		update()

func _draw():
	if points.size()<2 or layer.empty(): return
	var vertices = []
	var colors = []
	var indices = []
	var scale = abs(follow.global_transform.get_scale().x)
	for index in points.size():
		var t = clamp((clock-float(points[index][1]))/float(layer.lifetime),0,1)
		var previous = points[max(0,index-1)][0]
		var next = points[min(points.size()-1,index+1)][0]
		var tangent = (next-previous).normalized()
		var normal = Vector2(-tangent.y,tangent.x)
		var width = float(layer.width)*width_curve.interpolate(t)*0.5*scale
		var color = gradient.interpolate(t)
		color.a *= alpha_curve.interpolate(t)*float(layer.opacity)
		vertices.append(points[index][0]+normal*width)
		vertices.append(points[index][0]-normal*width)
		colors.append(color)
		colors.append(color)
		if index > 0:
			var at = index*2
			indices.append_array([at-2,at,at-1,at,at+1,at-1])
	# A ribbon already has known topology. Avoid generic polygon triangulation
	# (quadratic, and unreliable when a fast route crosses itself).
	VisualServer.canvas_item_add_triangle_array(get_canvas_item(),PoolIntArray(indices),PoolVector2Array(vertices),PoolColorArray(colors))
