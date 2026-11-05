extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Smooth tool-owned vector art; no cartoon face, particles or native-state edits.
class Saucer extends Node2D:
	var height = 180.0
	var back: Sprite
	var front: Sprite
	var ready_art = false
	func setup():
		var image = Image.new()
		if image.load(ModPaths.JOURNEY_ASSETS_DIR + "finish_ufo.png") != OK:
			return false
		var texture = ImageTexture.new()
		texture.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		back = Sprite.new()
		back.texture = texture
		back.scale = Vector2.ONE * height * 2.7 / float(image.get_width())
		back.offset = Vector2(0, -25.0 * float(image.get_width()) / 768.0)
		add_child(back)
		# The same hull in front hides the Goober as it enters the hatch. Beam
		# and native rig remain behind it; transparent corners stay transparent.
		front = Sprite.new()
		front.texture = texture
		front.scale = back.scale
		front.offset = back.offset
		ready_art = true
		return true
	func sync_front():
		if front != null:
			front.transform = transform * back.transform
			front.modulate = modulate
	func _exit_tree():
		if is_instance_valid(front) and front.get_parent() == null:
			front.free()

class Beam extends Polygon2D:
	var height = 180.0
	var strength = 0.0
	var phase = 0.0
	func _ready():
		var white = Image.new()
		white.create(1,1,false,Image.FORMAT_RGBA8)
		white.fill(Color.white)
		var tex = ImageTexture.new()
		tex.create_from_image(white)
		texture = tex
		uv = PoolVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
		var shader = Shader.new()
		shader.code = """shader_type canvas_item;
uniform float strength = 0.0;
uniform float phase = 0.0;
uniform vec2 origin = vec2(0.0);
uniform vec2 foot = vec2(0.0,1.0);
uniform float unit = 180.0;
varying vec2 point;
void vertex() { point = VERTEX; }
void fragment() {
 float down = clamp((point.y-origin.y) / max(1.0,foot.y-origin.y),0.0,1.0);
 float center = mix(origin.x,foot.x,down);
 float side = abs(point.x-center) / (mix(.24,.8,down)*unit);
 float feather = 1.0 - smoothstep(.7,1.0,side);
 float core = 1.0 - smoothstep(.06,.85,side);
 float bands = .94 + .06 * sin(down * 34.0 + phase * 3.2);
 float end_fade = 1.0 - smoothstep(.82,1.0,down);
 vec3 col = mix(vec3(.27,.65,.70),vec3(.70,.94,.92),core);
 COLOR = vec4(col,(.10 + .21 * core) * feather * end_fade * bands * strength) * COLOR;
}"""
		material = ShaderMaterial.new()
		material.shader = shader
	func aim(ship: Vector2, ground: Vector2, power: float, clock: float):
		strength = clamp(power,0.0,1.0)
		phase = clock
		var top = ship + Vector2(0,.23) * height
		polygon = PoolVector2Array([top+Vector2(-.24,0)*height,top+Vector2(.24,0)*height,ground+Vector2(.8,0)*height,ground+Vector2(-.8,0)*height])
		visible = strength > .001
		if material != null:
			material.set_shader_param("strength",strength)
			material.set_shader_param("phase",phase)
			material.set_shader_param("origin",top)
			material.set_shader_param("foot",ground)
			material.set_shader_param("unit",height)

# Clip the private cosmetic rig at the hatch. Coordinates belong to the
# JourneyFinishPlayer, not the live body. A custom canvas rect keeps the
# native skin/attachment materials intact; no new rig shader is substituted.
static func hatch_clip(goober, hatch_y: float, height: float, enabled: bool):
	var rid = goober.get_canvas_item()
	VisualServer.canvas_item_set_custom_rect(rid,enabled,Rect2(Vector2(-height*8.0,hatch_y-goober.position.y),Vector2(height*16.0,height*16.0)))
	VisualServer.canvas_item_set_clip(rid,enabled)
