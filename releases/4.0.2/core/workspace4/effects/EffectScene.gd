extends Node2D
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")
const Trail = preload("user://mod/core/workspace4/effects/EffectTrail.gd")
var document = {}
var body_color = Color.white
var quality = 1.0
var components = []

static func texture(shape = "dot") -> Texture:
	var key = "goob_effect_shape_"+shape
	if Engine.has_meta(key): return Engine.get_meta(key)
	var pixels = Image.new()
	pixels.create(64,64,false,Image.FORMAT_RGBA8)
	pixels.lock()
	for y in 64:
		for x in 64:
			var p = (Vector2(x+0.5,y+0.5)-Vector2(32,32))/30.0
			var distance = p.length()
			var alpha = 0.0
			if shape=="star":
				var radius = 0.43+0.55*pow((cos(p.angle()*5-PI*0.5)+1)*0.5,2)
				alpha = clamp((radius-distance)*28,0,1)
			elif shape=="diamond": alpha = clamp((0.94-abs(p.x)-abs(p.y))*28,0,1)
			else: alpha = pow(clamp(1-distance,0,1),2)*1.4
			pixels.set_pixel(x,y,Color(1,1,1,clamp(alpha,0,1)))
	pixels.unlock()
	var result = ImageTexture.new()
	result.create_from_image(pixels,Texture.FLAG_FILTER)
	Engine.set_meta(key,result)
	return result

static func configure_emitter(target: CPUParticles2D, layer: Dictionary, color = Color.white, scale = 1.0, amount = -1):
	target.texture = texture(layer.shape)
	target.amount = int(layer.amount) if amount<0 else int(amount)
	target.lifetime = float(layer.lifetime)
	target.fixed_fps = 60
	target.local_coords = false
	target.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	target.emission_sphere_radius = 6.0*scale
	target.direction = Vector2(0,-1).rotated(deg2rad(float(layer.rotation)))
	target.spread = float(layer.spread)
	target.gravity = Vector2(layer.gravity_x,layer.gravity_y)*scale
	target.initial_velocity = float(layer.speed)*scale
	target.randomness = 0.45
	target.scale_amount = float(layer.size)*scale/64.0
	var size_curve = Curve.new()
	for point in layer.size_curve:
		size_curve.add_point(Vector2(point.t,point.v),0,0,Curve.TANGENT_LINEAR,Curve.TANGENT_LINEAR)
	target.scale_amount_curve = size_curve
	var gradient = Gradient.new()
	var stops = PoolRealArray()
	var colors = PoolColorArray()
	for index in 32:
		var t = index/31.0
		var current = Document.sample_color(layer.gradient,t)
		if layer.color_mode=="goober":
			current.r = color.r
			current.g = color.g
			current.b = color.b
		current.a *= Document.sample_curve(layer.alpha_curve,t)*float(layer.opacity)
		stops.append(t)
		colors.append(current)
	gradient.offsets = stops
	gradient.colors = colors
	target.color_ramp = gradient
	target.position = Vector2(layer.offset_x,layer.offset_y)*scale
	target.emitting = true

func configure(raw, color = Color.white, amount_scale = 1.0):
	document = Document.clean(raw)
	body_color = color
	quality = clamp(amount_scale,0.2,1.0)
	var previous = {}
	for component in components:
		if is_instance_valid(component):
			previous[str(component.get_meta("layer_id"))] = component
	components.clear()
	var remaining = 512 if quality>0.99 else 256
	for index in document.get("layers",[]).size():
		var layer = document.layers[index]
		if not layer.enabled: continue
		var node = previous.get(layer.id)
		if node!=null and str(node.get_meta("layer_kind"))!=layer.type: node = null
		if layer.type=="trail":
			if node==null:
				node = Trail.new()
				add_child(node)
				node.configure(self,layer,body_color)
			else:
				node.set_style(layer,body_color)
		else:
			if remaining<4: continue
			if node==null:
				node = CPUParticles2D.new()
				add_child(node)
			var amount = int(min(remaining,max(4,round(float(layer.amount)*quality))))
			configure_emitter(node,layer,body_color,1.0,amount)
			remaining -= amount
		node.name = "GoobEffectLayer"+str(index)
		if previous.get(layer.id)==node: previous.erase(layer.id)
		node.set_meta("layer_id",layer.id)
		node.set_meta("layer_kind",layer.type)
		node.z_index = index-8
		var material = node.material if node.material is CanvasItemMaterial else CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if layer.blend=="add" else CanvasItemMaterial.BLEND_MODE_MIX
		node.material = material
		components.append(node)
	for component in previous.values():
		remove_child(component)
		component.queue_free()

func clear_trails():
	for component in components:
		if component is Trail:
			component.points.clear()
			component.update()
