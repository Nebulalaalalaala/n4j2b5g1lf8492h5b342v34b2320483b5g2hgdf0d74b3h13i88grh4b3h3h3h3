extends Reference

# Bounded, data-only document shared by the editor, Workshop and public looks.
# No code, external files, URLs, scene resources or native game state in effects.
const VERSION = 2
const MAX_LAYERS = 8
const MAX_POINTS = 8
const MAX_BYTES = 32768
const TYPES = ["trail","emitter"]
const SHAPES = ["dot","star","diamond"]

static func number(value, low, high, fallback):
	if not typeof(value) in [TYPE_INT,TYPE_REAL]: return fallback
	if is_nan(float(value)) or is_inf(float(value)): return fallback
	return clamp(float(value),low,high)

static func hex_color(value, fallback = "ffffffff") -> String:
	if not value is String or not value.length() in [6,8] or not value.is_valid_hex_number(false): return fallback
	return value.to_lower()+"ff" if value.length()==6 else value.to_lower()

static func title(value, fallback = "Effect") -> String:
	if not value is String: return fallback
	var result = ""
	for character in value.substr(0,48):
		if ord(character)>=32: result+=character
	return fallback if result.strip_edges().empty() else result.strip_edges()

# This custom Godot 3 build uses ARGB for Color's eight-digit string helpers.
# Documents use explicit RRGGBBAA so file/SQL/web consumers agree on alpha.
static func color(value: String) -> Color:
	var clean = hex_color(value)
	var result = Color(clean.substr(0,6))
	var digits = "0123456789abcdef"
	result.a = (digits.find(clean.substr(6,1))*16+digits.find(clean.substr(7,1)))/255.0
	return result

static func color_hex(value: Color) -> String:
	var alpha = int(round(clamp(value.a,0,1)*255))
	var digits = "0123456789abcdef"
	return value.to_html(false)+digits.substr(int(alpha/16),1)+digits.substr(alpha%16,1)

static func layer(kind = "emitter", id = "layer-1") -> Dictionary:
	return {"id":id,"name":"Trail" if kind=="trail" else "Emitter","type":kind,"enabled":true,"blend":"add","color_mode":"gradient","opacity":1.0,"width":12.0,"size":8.0,"amount":48,"lifetime":0.8,"speed":24.0,"spread":180.0,"gravity_x":0.0,"gravity_y":16.0,"offset_x":0.0,"offset_y":0.0,"rotation":0.0,"shape":"dot","gradient":[{"t":0.0,"color":"a68bffff"},{"t":1.0,"color":"7fd8ffff"}],"size_curve":[{"t":0.0,"v":1.0},{"t":1.0,"v":0.0}],"alpha_curve":[{"t":0.0,"v":1.0},{"t":1.0,"v":0.0}]}

static func points(raw, color = false) -> Array:
	if not raw is Array or raw.size()<2 or raw.size()>MAX_POINTS: return []
	var result = []
	for item in raw:
		if not item is Dictionary: return []
		var point = {"t":number(item.get("t"),0,1,0)}
		if color:
			if not item.get("color") is String or not item.color.length() in [6,8] or not item.color.is_valid_hex_number(false): return []
			point.color = hex_color(item.color)
		else: point.v = number(item.get("v"),0,1,1)
		var position = 0
		while position<result.size() and result[position].t<point.t: position+=1
		if position<result.size() and abs(result[position].t-point.t)<0.001: result[position] = point
		else: result.insert(position,point)
	if result.size()<2: return []
	result[0].t = 0.0
	result.back().t = 1.0
	return result

static func clean(raw) -> Dictionary:
	if not raw is Dictionary or JSON.print(raw).to_utf8().size()>MAX_BYTES: return {}
	if not raw.has("layers"):
		if not raw.has("amount") or not raw.has("color_a"): return {}
		var migrated = layer("emitter","legacy-emitter")
		migrated.amount = int(number(raw.get("amount"),4,160,40))
		migrated.lifetime = number(raw.get("lifetime"),0.1,3,0.9)
		migrated.size = number(raw.get("size"),1,16,5)*4.0
		migrated.speed = number(raw.get("speed"),0,200,30)
		migrated.gradient = [{"t":0.0,"color":hex_color(raw.get("color_a"),"ffe38aff")},{"t":1.0,"color":hex_color(raw.get("color_b"),"a68bffff")}]
		return {"version":VERSION,"name":title(raw.get("name",raw.get("preset","My effect"))),"layers":[migrated]}
	if raw.get("version")!=VERSION or not raw.layers is Array or raw.layers.empty() or raw.layers.size()>MAX_LAYERS: return {}
	var result = {"version":VERSION,"name":title(raw.get("name")),"layers":[]}
	var ids = {}
	for index in raw.layers.size():
		var source = raw.layers[index]
		if not source is Dictionary or not source.get("type") in TYPES: return {}
		if source.has("enabled") and not source.enabled is bool: return {}
		var current = layer(source.type)
		current.id = title(source.get("id"),"layer-"+str(index+1))
		if ids.has(current.id): current.id+="-"+str(index)
		ids[current.id] = true
		current.name = title(source.get("name"),"Trail" if source.type=="trail" else "Emitter")
		current.enabled = bool(source.get("enabled",true))
		current.blend = "add" if source.get("blend","add")=="add" else "mix"
		current.color_mode = "goober" if source.get("color_mode")=="goober" else "gradient"
		current.shape = source.get("shape","dot") if source.get("shape","dot") in SHAPES else "dot"
		for spec in [["opacity",0,1],["width",1,40],["size",1,64],["amount",4,160],["lifetime",0.1,3],["speed",0,200],["spread",0,360],["gravity_x",-150,150],["gravity_y",-150,150],["offset_x",-100,100],["offset_y",-100,100],["rotation",-360,360]]:
			current[spec[0]] = number(source.get(spec[0]),spec[1],spec[2],current[spec[0]])
		current.amount = int(current.amount)
		for key in ["gradient","size_curve","alpha_curve"]:
			current[key] = points(source.get(key,current[key]),key=="gradient")
			if current[key].empty(): return {}
		result.layers.append(current)
	return result

static func sample_curve(curve: Array, time: float) -> float:
	if curve.empty(): return 1.0
	var t = clamp(time,0,1)
	for index in range(1,curve.size()):
		if t<=curve[index].t:
			var amount = (t-float(curve[index-1].t))/max(0.0001,float(curve[index].t)-float(curve[index-1].t))
			return lerp(float(curve[index-1].v),float(curve[index].v),amount)
	return float(curve.back().v)

static func sample_color(stops: Array, time: float) -> Color:
	if stops.empty(): return Color.white
	var t = clamp(time,0,1)
	for index in range(1,stops.size()):
		if t<=stops[index].t:
			var amount = (t-float(stops[index-1].t))/max(0.0001,float(stops[index].t)-float(stops[index-1].t))
			return color(stops[index-1].color).linear_interpolate(color(stops[index].color),amount)
	return color(stops.back().color)

static func export_data(raw: Dictionary) -> Dictionary:
	var document = clean(raw)
	if document.empty(): return {}
	# Mirrors keep earlier clients / Workshop versions able to preview a
	# single-emitter approximation. New readers use the full layers array.
	var first = document.layers[0]
	for item in document.layers:
		if item.type=="emitter":
			first = item
			break
	document.color_a = str(first.gradient[0].color).substr(0,6)
	document.color_b = str(first.gradient.back().color).substr(0,6)
	document.amount = first.amount
	document.lifetime = first.lifetime
	document.size = first.size/4.0
	document.speed = first.speed
	document.preset = document.name
	return document

static func presets() -> Dictionary:
	var result = {}
	for spec in [["Stardust","ffe38aff","a68bffff","star",32,0.9],["Comet","7fd8ffff","5a7bffff","dot",50,0.6],["Sakura","ffc2e6ff","ff8ec6ff","diamond",24,1.4],["Aurora","8ce0baff","a68bffff","dot",40,1.1],["Arctic Fox","ffffffff","a68bffff","star",28,0.8],["Ember","ffd28aff","ff6555ff","dot",52,0.7],["Neon Ribbon","7fd8ffff","ff8ec6ff","dot",20,0.45],["Moonlight","d9e7ffff","8d9dffff","star",18,1.5],["Mint Drift","8ce0baff","39a7a7ff","diamond",32,1.0],["Golden Hour","fff0b0ff","f5a554ff","star",36,0.9],["Void","b38affff","4f3ca0ff","dot",30,0.7],["Confetti","ff8ec6ff","ffd86bff","diamond",64,0.8]]:
		var trail = layer("trail","trail-1")
		trail.name = "Ribbon"
		trail.width = 8.0 if spec[0]!="Neon Ribbon" else 18.0
		trail.lifetime = spec[5]*0.65
		trail.gradient = [{"t":0.0,"color":spec[1]},{"t":1.0,"color":spec[2]}]
		var emitter = layer("emitter","emitter-1")
		emitter.name = "Sparkles"
		emitter.shape = spec[3]
		emitter.size = {"Stardust":20.0,"Comet":28.0,"Sakura":24.0,"Aurora":16.0,"Arctic Fox":16.0,"Moonlight":14.0,"Confetti":18.0}.get(spec[0],20.0)
		emitter.speed = {"Stardust":30.0,"Comet":10.0,"Sakura":45.0,"Aurora":20.0,"Ember":48.0,"Confetti":65.0}.get(spec[0],24.0)
		emitter.amount = spec[4]
		emitter.lifetime = spec[5]
		emitter.gradient = trail.gradient.duplicate(true)
		result[spec[0]] = export_data({"version":VERSION,"name":spec[0],"layers":[trail,emitter]})
	return result
