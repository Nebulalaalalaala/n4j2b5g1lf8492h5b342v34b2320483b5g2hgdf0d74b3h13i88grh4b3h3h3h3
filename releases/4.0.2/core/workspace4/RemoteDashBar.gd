extends Node

# Native remote renderers intentionally hide their own recharge bar. Reuse that
# exact UI and interpolation, applying only its presentation after native drawing.
var renderer
var bar
var icon
var spine
var game
var previous = 0.0
var icon_scale = Vector2.ONE
var original = {}
var ready_tween
var restored = false
var native_sink: TextureProgress
var pulse_style={}
var pulse_image: Image
var pulse_texture: ImageTexture
var pulse_tiles=[]
var pulse_body=Color(-1,-1,-1,-1)

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process_priority(1000002)
	bar = renderer.get("dash_cooldown")
	icon = renderer.get("charge_icon")
	spine = renderer.get("spine")
	game = renderer.get_network_game()
	if not bar is TextureProgress or not is_instance_valid(icon):
		set_process(false)
		return
	icon_scale = icon.rect_scale
	original = {"value":bar.value,"under":bar.tint_under,"progress":bar.tint_progress,"icon":icon.visible,"material":bar.material,"under_texture":bar.texture_under,"progress_texture":bar.texture_progress}
	var player = renderer.get_network_object()
	if is_instance_valid(player): previous = float(player.dash_cooldown)
	# Native remote rendering unconditionally hides its bar every display frame.
	# Keep the original visible control and anchor scripts in their native tree,
	# but send that redundant hide to a detached, never-rendered control. This
	# avoids two visibility/layout invalidations per player per frame. The local
	# player is never borrowed, and the original binding is restored on exit.
	if is_instance_valid(player) and not game.is_local_player(renderer.get_object_id()):
		native_sink=TextureProgress.new()
		native_sink.visible=false
		renderer.set("dash_cooldown",native_sink)
		if renderer.get("dash_cooldown")!=native_sink:
			native_sink.free()
			native_sink=null # Compatible fallback for a future read-only renderer.


	_build_pulse_style()

func _process(_delta):
	if restored or not is_instance_valid(renderer) or not is_instance_valid(game) or not is_instance_valid(bar): return
	if game.is_local_player(renderer.get_object_id()):
		restore_native_presentation()
		queue_free()
		return # Return ownership immediately if spectating/control ownership changes.
	var player = renderer.get_network_object()
	if player == null or not player.alive or not is_instance_valid(spine) or not spine.is_visible_in_tree():
		if bar.visible: bar.visible = false
		return
	var data = game.wp_game_data
	if data == null: return
	var cooldown = max(0.0,float(renderer.get_interpolated_property("dash_cooldown")))
	var value = 1.0-cooldown/max(1.0,float(data.player_dash_cooldown_ticks))
	if previous > 0.0 and cooldown == 0.0:
		bar.tint_under = Color.white
		if ready_tween != null and ready_tween.is_running(): ready_tween.kill()
		ready_tween = create_tween()
		ready_tween.tween_property(icon,"rect_scale",icon_scale*2.0,0.13).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		ready_tween.tween_property(icon,"rect_scale",icon_scale,0.13).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	if cooldown == 0.0:
		var active_ticks = max(1,int(data.player_dash_ticks-data.player_dash_charge_ticks))
		if player.dash_timer > active_ticks:
			_progress_tint(Color.white,false)
			icon.visible = false
		elif player.dash_timer > 0:
			value = float(player.dash_timer)/active_ticks
			_progress_tint(spine.get_tint(),false)
			icon.visible = false
		else:
			icon.visible = true
			_progress_tint(spine.get_tint(),true)
			var under=spine.get_dark_tint()
			if bar.tint_under!=under: bar.tint_under=under
	else:
		_progress_tint(spine.get_tint(),false)
		icon.visible = false
	bar.value = value
	if not bar.visible: bar.visible = true
	previous = cooldown

func restore_native_presentation() -> void:
	if restored: return
	restored = true
	set_process(false)
	if ready_tween != null and ready_tween.is_running(): ready_tween.kill()
	if is_instance_valid(native_sink):
		if is_instance_valid(renderer) and renderer.get("dash_cooldown")==native_sink and is_instance_valid(bar): renderer.set("dash_cooldown",bar)
		native_sink.free()
		native_sink=null
	if not is_instance_valid(bar): return
	if not original.empty():
		bar.material=original.material
		bar.texture_under=original.under_texture
		bar.texture_progress=original.progress_texture
	if is_instance_valid(game) and is_instance_valid(renderer) and game.is_local_player(renderer.get_object_id()): return
	bar.visible = false
	if not original.empty():
		bar.value = original.value
		bar.material = original.material
		bar.texture_under = original.under_texture
		bar.texture_progress = original.progress_texture
		bar.tint_under = original.under
		bar.tint_progress = original.progress
	if is_instance_valid(icon):
		icon.rect_scale = icon_scale
		if not original.empty(): icon.visible = original.icon

func _exit_tree():
	restore_native_presentation()

func _build_pulse_style():
	# Only the stock solid-pixel bar is eligible. Preserve a themed/custom bar
	# exactly, including any material or artwork supplied by another module.
	if bar.material!=null or bar.use_parent_material or bar.texture_under!=bar.texture_progress: return
	if bar.texture_under==null or not str(bar.texture_under.resource_path).ends_with("/white_pixel.png"): return
	var key="goob_native_recharge_gpu_pulse"
	if Engine.has_meta(key): pulse_style=Engine.get_meta(key)
	else:
		var shader=Shader.new()
		shader.code="shader_type canvas_item; uniform float pulse=0.0; void fragment(){ vec4 vertex=COLOR; vec4 tex=texture(TEXTURE,UV); if(UV.x>0.666667){ tex=mix(vec4(1.0),tex,pulse); } COLOR=tex*vertex; }"
		var material=ShaderMaterial.new()
		material.shader=shader
		pulse_style={"material":material,"frame":-1}
		Engine.set_meta(key,pulse_style)
	# Encode the target ready colour in the texture, rather than vertex COLOR.
	# Parent/self tint and opacity then compose exactly as native drawing does.
	pulse_image=Image.new()
	pulse_image.create(9,1,false,Image.FORMAT_RGBAF)
	pulse_image.fill(Color.white)
	pulse_texture=ImageTexture.new()
	pulse_texture.create_from_image(pulse_image,0)
	for index in 3:
		var tile=AtlasTexture.new()
		tile.atlas=pulse_texture
		tile.region=Rect2(index*3,0,3,1)
		pulse_tiles.append(tile)
	bar.material=pulse_style.material
	bar.texture_under=pulse_tiles[0]
	bar.texture_progress=pulse_tiles[1]

func _progress_tint(color: Color, ready: bool):
	if pulse_style.empty():
		bar.tint_progress=Color.white.linear_interpolate(color,abs(sin(OS.get_ticks_msec()*0.015))) if ready else color
		return
	var texture=pulse_tiles[2] if ready else pulse_tiles[1]
	if bar.texture_progress!=texture: bar.texture_progress=texture
	var target=Color.white if ready else color
	if bar.tint_progress!=target: bar.tint_progress=target
	if not ready: return
	if color!=pulse_body:
		pulse_body=color
		pulse_image.lock()
		for x in range(6,9): pulse_image.set_pixel(x,0,color)
		pulse_image.unlock()
		pulse_texture.set_data(pulse_image)
	var frame=Engine.get_frames_drawn()
	if int(pulse_style.frame)!=frame:
		pulse_style.frame=frame
		pulse_style.material.set_shader_param("pulse",abs(sin(OS.get_ticks_msec()*0.015)))
