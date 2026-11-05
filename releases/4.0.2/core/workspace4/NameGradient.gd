extends Reference
const Roles = preload("user://mod/core/workspace4/ClientRoles.gd")
const META = "goob_name_gradient"

# The native WPSDFLabel encodes glyph scale in COLOR.g and stroke in COLOR.r.
# Preserve that shader, its premultiplied alpha and its separate outline labels.
# Only the main fill's RGB changes. Text and account metadata are never written.
static func apply(label: Label, role: String) -> bool:
	if not Roles.DEFINITIONS.has(role) or int(Roles.DEFINITIONS[role].tier)==0:
		restore(label)
		return false
	var state = label.get_meta(META) if label.has_meta(META) else {}
	if state.empty() or label.material!=state.get("owned"):
		var original = label.material
		var source = original
		if source==null and "sdf_material" in label: source = label.get("sdf_material")
		var material = _material(source)
		if material==null: return false
		state = {"original":original,"owned":material}
		label.set_meta(META,state)
		label.material = material
	var data = Roles.DEFINITIONS[role]
	state.owned.set_shader_param("gp_from",Color(data.from))
	state.owned.set_shader_param("gp_to",Color(data.to))
	state.owned.set_shader_param("gp_width",max(1.0,label.rect_size.x))
	return true

static func restore(label: Label):
	if not label.has_meta(META): return
	var state = label.get_meta(META)
	if label.material==state.get("owned"): label.material = state.original
	label.remove_meta(META)

static func _material(original) -> ShaderMaterial:
	var result = ShaderMaterial.new()
	var code = ""
	if original is ShaderMaterial and original.shader!=null:
		code = original.shader.code
		var scale_line = "VERTEX = VERTEX * COLOR.g;"
		var color_line = "vec4 fgColor = vec4(MODULATE.rgb * MODULATE.a, MODULATE.a);"
		if not scale_line in code or not color_line in code: return null
		result = original.duplicate()
		code = code.replace(scale_line,scale_line+"\n gp_name_x = VERTEX.x;")
		code = code.replace(color_line,"vec3 gp_rgb = mix(gp_from.rgb, gp_to.rgb, clamp(gp_name_x / max(1.0,gp_width),0.0,1.0));\n vec4 fgColor = vec4(gp_rgb * MODULATE.a, MODULATE.a);")
	else:
		code = "shader_type canvas_item;\nvoid vertex(){ gp_name_x = VERTEX.x; }\nvoid fragment(){ vec4 glyph = texture(TEXTURE,UV); COLOR = vec4(mix(gp_from.rgb,gp_to.rgb,clamp(gp_name_x/max(1.0,gp_width),0.0,1.0)), glyph.a*COLOR.a); }"
	var declarations = "\nuniform vec4 gp_from : hint_color;\nuniform vec4 gp_to : hint_color;\nuniform float gp_width = 200.0;\nvarying float gp_name_x;\n"
	code = code.replace("shader_type canvas_item;","shader_type canvas_item;"+declarations)
	var shader = Shader.new()
	shader.code = code
	result.shader = shader
	return result
