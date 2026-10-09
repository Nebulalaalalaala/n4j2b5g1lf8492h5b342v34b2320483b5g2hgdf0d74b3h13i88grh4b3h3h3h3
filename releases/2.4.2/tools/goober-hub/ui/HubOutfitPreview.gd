extends Control
const ModPaths = preload("user://mod/core/ModPaths.gd")
const FRAME_INTERVAL = 1.0 / 30.0
var studio
var payload = {}
var service
var row = {}
var font
var avatar
var _scroll
var _notice
var _visibility_wait = 0.0
var _animation_time = 0.0
var _on_screen = false
var _failed = false
var _bounds = Rect2()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_clip_content = true
	var ancestor = get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			_scroll = ancestor
			break
		ancestor = ancestor.get_parent()
	_notice = Label.new()
	_notice.text = "Loading outfit…"
	_notice.align = Label.ALIGN_CENTER
	_notice.valign = Label.VALIGN_CENTER
	_notice.autowrap = true
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_color_override("font_color",Color("8eaedb"))
	if font!=null: _notice.add_font_override("font",font)
	_notice.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(_notice)
	connect("resized",self,"_place")
	if is_instance_valid(service): service.connect("outfit_ready",self,"_outfit_ready")
	if not is_instance_valid(studio):
		_failed = true
		_notice.text = "Enable Avatar Studio to preview"
	elif not payload.empty():
		_build_avatar()

func _in_view() -> bool:
	if not is_visible_in_tree() or rect_size.x<=0 or rect_size.y<=0: return false
	if not is_instance_valid(_scroll): return true
	# Compare in the scroll's local space: Hub's logical UI is scaled at 0.86.
	var transform = _scroll.get_global_transform().affine_inverse() * get_global_transform()
	var bounds = Rect2(transform.xform(Vector2.ZERO),transform.basis_xform(rect_size))
	return bounds.intersects(Rect2(Vector2.ZERO,_scroll.rect_size))

func _load_outfit():
	if _failed or not is_instance_valid(service) or not payload.empty(): return
	var item = service.outfit_preview(row)
	if item.has("payload"):
		payload = item.payload
		_build_avatar()
	elif item.has("error"):
		_failed = true
		_notice.text = str(item.error)

func _outfit_ready(code):
	if code==service.code(row) and _in_view(): _load_outfit()

func _build_avatar():
	if is_instance_valid(avatar) or not is_instance_valid(studio): return
	var looks = load(ModPaths.path("StudioSharedLooks.gd"))
	if not looks.valid(studio,payload):
		_failed = true
		_notice.text = "Preview unavailable"
		return
	var scene = load(studio.sandbox.GOOBER_SCENE_PATH)
	if not scene is PackedScene: return
	avatar = scene.instance()
	# This is a preview, not a live player to override/register in the sandbox.
	avatar.set_meta("studio_layer",true)
	avatar.enable_sounds = false
	avatar.enable_blink = true
	avatar.update_mode = SpineConstant.UpdateMode_Manual
	add_child(avatar)
	avatar.set_process(false)
	var before = studio.texture_cache.duplicate()
	var item_before = studio.item_textures.duplicate()
	for id in payload.get("textures",{}):
		var texture = ImageTexture.new()
		texture.create_from_image(looks.image_from(payload.textures[id]),Texture.FLAG_FILTER)
		studio.texture_cache[id] = texture
	studio.item_textures = payload.state.get("item_textures",{}).duplicate()
	studio._render_look(avatar,payload.state)
	studio.item_textures = item_before
	studio.texture_cache = before
	avatar.get_animation_state().set_animation("Idle",true,0)
	avatar.update_skeleton(0.0)
	_measure_outfit()
	_place()
	_notice.hide()

func _measure_outfit():
	# Native geometry, once per outfit (no screenshots/GPU readback). Include
	# a few idle poses so fitting doesn't change size as the Goober sways.
	var track = avatar.get_animation_state().get_current(0)
	var sprites = [avatar]
	var layers = avatar.get_node_or_null("LocalCosmeticLayers")
	if layers!=null: sprites += layers.avatars.values()
	for phase in [0.0,0.25,0.5,0.75]:
		track.set_track_time(track.get_animation_end()*phase)
		avatar.update_skeleton(0.0)
		for sprite in sprites:
			var bounds = sprite.get_skeleton().get_bounds()
			if bounds.size.x<=0 or bounds.size.y<=0: continue
			_bounds = bounds if _bounds.size==Vector2.ZERO else _bounds.merge(bounds)
			var edits = sprite.get_node_or_null("LocalCosmeticTransforms")
			if edits==null: continue
			# Slot materials edit vertices after native bounds are measured.
			# A conservative envelope also keeps freely moved/scaled items visible.
			for id in payload.state.get("transforms",{}):
				var geometry = edits.item_frame(id)
				if geometry.empty(): continue
				var transform = geometry.warp * geometry.frame.affine_inverse()
				for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
					_bounds = _bounds.expand(transform.xform(corner))
	track.set_track_time(0.0)
	avatar.update_skeleton(0.0)
	# Idle/blink blends can extend beyond the sampled key poses. Keep breathing
	# room without recalculating the scale (which would make the preview pulse).
	_bounds = _bounds.grow(max(100.0,_bounds.size.y*0.12))

func _place():
	if not is_instance_valid(avatar): return
	if _bounds.size.x<=0 or _bounds.size.y<=0: return
	var fit = min(max(1.0,rect_size.x-24.0)/_bounds.size.x,max(1.0,rect_size.y-24.0)/_bounds.size.y)
	var center = _bounds.position+_bounds.size*.5
	avatar.scale = Vector2(-fit,fit)
	avatar.position = rect_size*.5 - center*avatar.scale

func _process(delta):
	# Native Spine is manual: hidden/scroll-clipped cards do no animation work.
	if not is_visible_in_tree():
		_on_screen = false
		_animation_time = 0.0
		return
	_visibility_wait -= delta
	if _visibility_wait<=0.0:
		_visibility_wait = 0.1
		_on_screen = _in_view()
		if _on_screen: _load_outfit()
	if not _on_screen or not is_instance_valid(avatar):
		_animation_time = 0.0
		return
	_animation_time += delta
	if _animation_time<FRAME_INTERVAL: return
	var step = min(_animation_time,0.1)
	_animation_time = 0.0
	avatar._process(step) # Native blink, on the same visible-only clock.
	avatar.update_skeleton(step) # Also updates transformed/multiple cosmetic layers.

func _exit_tree():
	if is_instance_valid(service) and service.is_connected("outfit_ready",self,"_outfit_ready"):
		service.disconnect("outfit_ready",self,"_outfit_ready")
