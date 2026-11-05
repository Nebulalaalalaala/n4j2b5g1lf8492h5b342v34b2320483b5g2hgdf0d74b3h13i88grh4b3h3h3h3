extends Control

# The exact same renderer draws the editor canvas and gameplay output.
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const FONT_DIR="user://mod/shared/assets/fonts/"
var item={}
var reference=Vector2(1920,1080)
var sources
var preview=false
var interactive=false
var fallback_tick=0
var key_started=0
var key_from={}
var key_targets={}
var fade_started=-1
var font: DynamicFont
var small_font: DynamicFont
var card_meta: DynamicFont
var card_caption: DynamicFont
var image_texture
var media_state={}
var game_state={}
var game_art: Texture
var game_art_key=""
var buttons={}
var key_mix={}
var key_down={}
var rising=[]
var last_text=""
var last_art=null
var track_signature=""
var picture: TextureRect
var picture_material: ShaderMaterial
var registered=false
var asset_error=""
var asset_key=""
var font_key=""

func setup(data: Dictionary, service, dimensions: Vector2, in_preview=false):
	item=data
	sources=service
	reference=dimensions
	preview=in_preview
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	if is_inside_tree(): refresh()

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	connect("visibility_changed",self,"_visibility")
	connect("resized",self,"update")
	connect("gui_input",self,"_gui")
	set_process(false)
	if sources!=null:
		sources.connect("changed",self,"_tick")
		sources.connect("tick",self,"_tick")
		sources.connect("input_changed",self,"_input_changed")
		sources.connect("camera_changed",self,"_camera_changed")
	refresh()

func refresh():
	if item.empty(): return
	var next_font=str(item.font)+":"+str(int(item.font_size))+":"+str(item.get("font_outline",0))
	if next_font!=font_key:
		font_key=next_font
		font=_font(int(item.font_size),item.font)
		font.outline_size=int(item.get("font_outline",0))
		font.outline_color=Color(0,0,0,0.55)
		small_font=_font(int(max(10,item.font_size*0.67)),item.font)
		if item.type=="game":
			card_meta=_font(int(max(12,item.font_size*0.55)),item.font)
			card_caption=_font(int(max(10,item.font_size*0.46)),item.font)
	modulate.a=item.opacity
	rect_pivot_offset=rect_size/2
	rect_rotation=item.rotation
	if item.type=="image":
		var file=File.new()
		var key=str(item.source.path)+":"+str(file.get_modified_time(item.source.path) if file.file_exists(item.source.path) else 0)
		if key!=asset_key:
			asset_key=key
			image_texture=_load_image(item.source.path)
	_visibility()
	_tick()

static func _font(pixels: int, name: String) -> DynamicFont:
	var font=DynamicFont.new()
	var data=DynamicFontData.new()
	data.antialiased=true
	data.override_oversampling=2.0
	data.font_path={"Segoe UI":"C:/Windows/Fonts/segoeui.ttf","Segoe UI Semibold":"C:/Windows/Fonts/seguisb.ttf","Segoe UI Bold":"C:/Windows/Fonts/segoeuib.ttf"}.get(name,FONT_DIR+"Inter-SemiBold.ttf")
	font.font_data=data
	font.size=max(6,pixels)
	font.use_filter=true
	return font

func _load_image(path: String):
	asset_error=""
	if path.empty(): return null
	var file=File.new()
	if not file.file_exists(path):
		asset_error="Image is missing"
		return null
	if file.open(path,File.READ)!=OK: return null
	var length=file.get_len()
	file.close()
	if length>33554432:
		asset_error="Image exceeds 32 MB"
		return null
	var cache_key=path+":"+str(file.get_modified_time(path))
	if is_instance_valid(sources) and sources.image_cache.has(cache_key):
		var cached=sources.image_cache[cache_key].get_ref()
		if is_instance_valid(cached): return cached
	var image=Image.new()
	if image.load(path)!=OK:
		asset_error="Unsupported image"
		return null
	if image.get_width()>8192 or image.get_height()>8192:
		asset_error="Image exceeds 8192 pixels"
		return null
	var texture=ImageTexture.new()
	texture.create_from_image(image,Texture.FLAG_FILTER)
	if is_instance_valid(sources):
		if sources.image_cache.size()>128:
			for key in sources.image_cache.keys():
				if not is_instance_valid(sources.image_cache[key].get_ref()): sources.image_cache.erase(key)
		sources.image_cache[cache_key]=weakref(texture)
	return texture

func _visibility():
	if sources==null or item.empty(): return
	var active=is_visible_in_tree() and bool(item.visible)
	if not active and item.type=="keyboard":
		rising.clear()
		key_down.clear()
		key_targets.clear()
		set_process(false)
	if active and not registered:
		sources.register(self,item)
		registered=true
	elif not active and registered:
		sources.unregister(self)
		registered=false

	set_process_input(active and item.type=="media" and not preview)

func _tick():
	if not is_visible_in_tree() or item.empty(): return
	var text=""
	match item.type:
		"text": text=item.source.text
		"clock":
			var now=OS.get_time()
			var hour=int(now.hour)
			if item.source.format=="12h": hour=12 if hour%12==0 else hour%12
			text="%02d:%02d"%[hour,now.minute]
			if item.source.seconds: text+=":%02d"%now.second
			if item.source.format=="12h": text+=" PM" if now.hour>=12 else " AM"
		"fps": text=str(Engine.get_frames_per_second())+(" FPS" if item.source.suffix else "")
		"game":
			game_state=sources.game_card(item.source.field) if sources!=null else {"title":"Not in a level","label":"CURRENT LEVEL","detail":"Level details appear during play"}
			var theme=str(game_state.get("theme",""))
			if theme!=game_art_key:
				game_art_key=theme
				game_art=null
				if theme in ["castle","city","dungeon","grassy","green","meadow","sandy","snow"]:
					var path="res://project_specific/level_themes/"+theme+"/background.png"
					if ResourceLoader.exists(path): game_art=load(path)
			modulate.a=item.opacity if preview or item.source.get("show_idle",false) or game_state.get("active",false) else 0.0
			text=JSON.print(game_state)
		"media":
			media_state=sources.media(item.source) if sources!=null else {}
			var signature=str(media_state.get("id",""))+str(media_state.get("title",""))
			if signature!=track_signature and not track_signature.empty() and item.source.transition and media_state.get("playing",false):
				fade_started=OS.get_ticks_msec()
				set_process(true)
			track_signature=signature
			if item.source.when_stopped=="hide" and not media_state.get("playing",false) and not preview:
				modulate.a=0
			else: modulate.a=item.opacity
		"camera": pass
	if text!=last_text or item.type in ["media","camera"]:
		last_text=text
		update()

func _camera_changed(device: String):
	if item.get("type")=="camera" and item.source.device==device: update()

func _input_changed():
	if item.get("type")!="keyboard" or not is_visible_in_tree(): return
	if not sources.focused:
		key_mix.clear()
		key_down.clear()
		rising.clear()
		key_targets.clear()
		set_process(false)
		update()
		return
	var next={}
	var same=not key_targets.empty()
	for key in item.source.keys:
		next[key.id]=1.0 if sources.pressed.get(sources.key_id(key),false) else 0.0
		if float(key_targets.get(key.id,-1))!=float(next[key.id]): same=false
		if next[key.id]>0 and not key_down.get(key.id,false) and item.source.rise and not SavedSettings.get_value("workspace_reduced_motion",false):
			if rising.size()>=64: rising.pop_front()
			rising.append({"key":key.duplicate(),"started":OS.get_ticks_msec()})
		key_down[key.id]=next[key.id]>0
	if same: return # A different keyboard's input must not restart this animation.
	key_started=OS.get_ticks_msec()
	key_from=key_mix.duplicate()
	key_targets=next
	for key in item.source.keys:
		if not item.source.animate or SavedSettings.get_value("workspace_reduced_motion",false): key_mix[key.id]=key_targets[key.id]
	if not item.source.animate or SavedSettings.get_value("workspace_reduced_motion",false): key_targets.clear()
	set_process((item.source.animate and not SavedSettings.get_value("workspace_reduced_motion",false)) or not rising.empty())
	update()

func _process(_delta):
	var now=OS.get_ticks_msec()
	var active=false
	if not key_targets.empty() and item.get("type")=="keyboard":
		var progress=clamp((now-key_started)/90.0,0,1)
		var eased=1.0-pow(1.0-progress,2)
		for id in key_targets: key_mix[id]=lerp(float(key_from.get(id,0)),float(key_targets[id]),eased)
		if progress>=1: key_targets.clear()
		else: active=true
		update()
	if not rising.empty():
		for entry in rising.duplicate():
			if now-int(entry.started)>=float(item.source.rise_seconds)*1000: rising.erase(entry)
		active=active or not rising.empty()
		update()
	if fade_started>=0:
		var progress=clamp((now-fade_started)/180.0,0,1)
		modulate.a=lerp(0.45,float(item.opacity),progress)
		if item.source.when_stopped=="hide" and not media_state.get("playing",false): modulate.a=0
		if progress>=1: fade_started=-1
		else: active=true
	set_process(active and is_visible_in_tree())

func _input(event):
	if event is InputEventKey and event.scancode==KEY_ALT:
		mouse_filter=Control.MOUSE_FILTER_STOP if event.pressed else Control.MOUSE_FILTER_IGNORE

func set_interactive(value: bool):
	interactive=value
	mouse_filter=Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE

func _gui(event):
	if not event is InputEventMouseButton or event.button_index!=BUTTON_LEFT or not event.pressed or item.type!="media": return
	for action in buttons:
		if buttons[action].has_point(event.position):
			if action=="seek": sources.control("seek",item.source,clamp((event.position.x-buttons.seek.position.x)/buttons.seek.size.x,0,1)*float(media_state.get("duration",0)))
			else: sources.control(action,item.source)
			accept_event()
			break

func _draw():
	if item.empty() or font==null: return
	if picture!=null: picture.visible=false
	var bounds=Rect2(Vector2.ZERO,rect_size)
	var style=StyleBoxFlat.new()
	style.bg_color=Color(item.background)
	style.bg_color.a=item.background_opacity
	style.set_corner_radius_all(int(min(item.radius,min(rect_size.x,rect_size.y)*0.5)))
	style.corner_detail=12
	style.border_color=Color(item.border_color)
	style.set_border_width_all(int(item.border_width) if item.border else 0)
	if item.shadow and item.background_opacity>0:
		style.shadow_color=Color(0,0,0,0.22)
		style.shadow_size=10
		style.shadow_offset=Vector2(0,4)
	draw_style_box(style,bounds)
	var pad=min(max(item.padding,item.border_width if item.border else 0),min(rect_size.x,rect_size.y)/3)
	var area=bounds.grow(-pad)
	match item.type:
		"image":
			if image_texture!=null: _picture(image_texture,area,item.source.crop,item.source.mirror,item.source.aspect_lock)
			elif preview: _text(asset_error if not asset_error.empty() else "Choose an image",area,small_font,Color(item.color),1)
		"game":
			if item.source.get("presentation","Card")=="Card": _game_card(area)
			else: _text(str(game_state.get("title","Not in a level")),area,font,Color(item.color))
		"keyboard": _keyboard(area)
		"media": _media(area)
		"camera":
			var texture=sources.textures.get(item.source.device) if sources!=null else null
			if texture!=null: _picture(texture,area,item.source.crop,item.source.mirror,true)
			else:
				var message="Camera is off"
				if sources!=null and sources.state.get("cameras",[]).empty(): message="No camera connected"
				if sources!=null and not str(sources.state.get("camera_error","")).empty(): message="Camera unavailable"
				_text(message,area,small_font,Color(item.color),1)
		_: _text(last_text,area,font,Color(item.color),int(item.source.get("align",0)),bool(item.source.get("wrap",false)))

func _text(value: String, area: Rect2, face: Font, color: Color, align=0, wrap=false):
	var lines=value.split("\n")
	if wrap:
		lines=PoolStringArray()
		for paragraph in value.split("\n"):
			var line=""
			for word in paragraph.split(" "):
				if face.get_string_size(line+word).x>area.size.x and not line.empty():
					lines.append(line.strip_edges())
					line=""
				line+=word+" "
			lines.append(line.strip_edges())
	var y=area.position.y+face.get_ascent()
	for line in lines:
		if y-face.get_ascent()+face.get_height()>area.end.y+1: break
		var text=str(line)
		while face.get_string_size(text).x>area.size.x and text.length()>1: text=text.left(text.length()-1)
		if text!=line and text.length()>2: text=text.left(text.length()-2)+"…"
		var width=face.get_string_size(text).x
		var x=area.position.x+(max(0,area.size.x-width)*(0.5 if align==1 else (1.0 if align==2 else 0.0)))
		if item.shadow and (item.type in ["text","clock","fps"] or (item.type=="game" and item.source.get("presentation")=="Plain text")): draw_string(face,Vector2(x+1,y+2),text,Color(0,0,0,0.5),max(0,area.size.x))
		draw_string(face,Vector2(x,y),text,color,max(0,area.size.x))
		y+=face.get_height()+2

func _picture(texture: Texture, area: Rect2, crop: Array, mirror: bool, keep: bool):
	var region=Rect2(Vector2(crop[0],crop[1])*texture.get_size(),Vector2(crop[2],crop[3])*texture.get_size())
	if keep:
		var scale=min(area.size.x/region.size.x,area.size.y/region.size.y)
		var fit=region.size*scale
		area=Rect2(area.position+(area.size-fit)/2,fit)
	if item.type in ["image","camera","game"]:
		if picture==null:
			picture=TextureRect.new()
			picture.expand=true
			picture.stretch_mode=TextureRect.STRETCH_SCALE
			picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var shader=Shader.new()
			shader.code="shader_type canvas_item; uniform vec2 dimensions; uniform float radius; varying vec2 local_position; void vertex(){local_position=VERTEX;} void fragment(){ vec4 c=texture(TEXTURE,UV)*COLOR; vec2 p=abs(local_position-dimensions*0.5)-(dimensions*0.5-vec2(radius)); float d=length(max(p,vec2(0.0)))+min(max(p.x,p.y),0.0)-radius; c.a*=1.0-smoothstep(-0.7,0.7,d); COLOR=c; }"
			picture_material=ShaderMaterial.new()
			picture_material.shader=shader
			picture.material=picture_material
			add_child(picture)
		var atlas=AtlasTexture.new()
		atlas.atlas=texture
		atlas.region=region
		picture.texture=atlas
		picture.flip_h=mirror
		picture.rect_position=area.position
		picture.rect_size=area.size
		picture_material.set_shader_param("dimensions",area.size)
		picture_material.set_shader_param("radius",min(item.radius,min(area.size.x,area.size.y)/2))
		picture.visible=true
	else:
		if mirror:
			area.position.x+=area.size.x
			area.size.x=-area.size.x
		draw_texture_rect_region(texture,area,region,Color.white,false)

func _keyboard(area: Rect2):
	for key in item.source.keys:
		var box=Rect2(area.position+Vector2(key.x,key.y)*area.size,Vector2(key.w,key.h)*area.size)
		var down=sources!=null and sources.pressed.get(sources.key_id(key),false)
		var mix=float(key_mix.get(key.id,1.0 if down else 0.0)) if item.source.animate else (1.0 if down else 0.0)
		var style=StyleBoxFlat.new()
		style.bg_color=Color(item.source.idle).linear_interpolate(Color(item.source.pressed),mix)
		style.border_color=Color(item.border_color)
		style.set_border_width_all(int(item.border_width) if item.border else 0)
		style.set_corner_radius_all(int(min(box.size.x,box.size.y)/2) if key.shape=="circle" else (0 if key.shape=="square" else int(min(item.radius,min(box.size.x,box.size.y)/4))))
		style.corner_detail=10
		draw_style_box(style,box)
		var label=str(key.label)
		if not str(key.action).empty() and InputMap.has_action(key.action):
			var actual=[]
			for binding in InputMap.get_action_list(key.action):
				if binding is InputEventKey: actual.append(OS.get_scancode_string(binding.scancode))
			if not actual.empty(): hint_tooltip="Game bindings: "+PoolStringArray(actual).join(" / ")
		if item.source.counter and sources!=null: label+=" "+str(sources.counters.get(sources.key_id(key),0))
		var text_area=box.grow(-3)
		text_area.position.y+=(text_area.size.y-font.get_height())/2
		_text(label,text_area,font,Color(item.source.text),1)

	for entry in rising:
		var key=entry.key
		var t=clamp((OS.get_ticks_msec()-int(entry.started))/(1000.0*float(item.source.rise_seconds)),0,1)
		var eased=1.0-pow(1.0-t,3)
		var size=Vector2(key.w,key.h)*area.size
		var box=Rect2(Vector2(area.position.x+key.x*area.size.x,-size.y-4-eased*float(item.source.rise_distance)),size)
		var tint=Color(item.source.pressed)
		tint.a=pow(1.0-t,2)*0.85
		var style=StyleBoxFlat.new()
		style.bg_color=tint
		style.set_corner_radius_all(int(min(item.radius,size.y/4)))
		style.corner_detail=10
		draw_style_box(style,box)
		var ink=Color(item.source.text)
		ink.a=tint.a
		box.position.y+=(size.y-font.get_height())/2
		_text(str(key.label),box,font,ink,1)

func _game_card(area: Rect2):
	var ink=Color(item.color)
	var accent=Color(item.accent)
	var text_area=area
	if area.size.x>=300 and area.size.y>=80:
		var side=min(108,area.size.y)
		var art_box=Rect2(area.position,Vector2(side,area.size.y))
		var tile=StyleBoxFlat.new()
		tile.bg_color=Color(accent.r,accent.g,accent.b,0.16)
		tile.set_corner_radius_all(12)
		draw_style_box(tile,art_box)
		if item.source.get("artwork",true) and game_art!=null:
			_picture(game_art,art_box,[0,0,1,1],false,false) # Actual native theme artwork, not a fabricated map thumbnail.
		else:
			var cell=side*0.16
			var at=art_box.position+Vector2(side*0.25,(area.size.y-cell*3)/2)
			for offset in [Vector2(0,2),Vector2(1,2),Vector2(2,2),Vector2(2,1),Vector2(0,0)]:
				draw_rect(Rect2(at+offset*cell,Vector2.ONE*(cell-3)),accent)
		text_area.position.x+=side+16
		text_area.size.x-=side+16
	if text_area.size.y<card_caption.get_height()+font.get_height()+8:
		_text(str(game_state.get("title","Ready for the next level")),text_area,font,ink)
		return
	_text(str(game_state.get("label","CURRENT LEVEL")),Rect2(text_area.position,Vector2(text_area.size.x,card_caption.get_height()+1)),card_caption,accent)
	var y=text_area.position.y+card_caption.get_height()+8
	_text(str(game_state.get("title","Ready for the next level")),Rect2(Vector2(text_area.position.x,y),Vector2(text_area.size.x,font.get_height()+2)),font,ink)
	y+=font.get_height()+5
	var author=str(game_state.get("author",""))
	if item.source.get("author",true) and not author.empty() and y+card_meta.get_height()<=text_area.end.y:
		_text("by "+author,Rect2(Vector2(text_area.position.x,y),Vector2(text_area.size.x,card_meta.get_height()+1)),card_meta,Color(ink.r,ink.g,ink.b,ink.a*0.72))
		y+=card_meta.get_height()+5
	if not item.source.get("details",true) or y+card_meta.get_height()>text_area.end.y:return
	var parts=[]
	var mode=str(game_state.get("mode",""))
	
	if game_state.get("active",false):parts.append(str(game_state.get("players",0))+" players")
	var rating=float(game_state.get("rating",0))
	if rating>0:parts.append("★ %.1f"%rating)
	if parts.empty():parts.append(str(game_state.get("detail","")))
	var footer=Rect2(Vector2(text_area.position.x,text_area.end.y-card_meta.get_height()-1),Vector2(text_area.size.x,card_meta.get_height()+1))
	if not mode.empty():
		var chip_width=card_caption.get_string_size(mode).x+18
		var chip=Rect2(footer.position-Vector2(0,3),Vector2(chip_width,card_meta.get_height()+6))
		var badge=StyleBoxFlat.new()
		badge.bg_color=Color(accent.r,accent.g,accent.b,0.14)
		badge.set_corner_radius_all(6)
		draw_style_box(badge,chip)
		_text(mode,Rect2(chip.position+Vector2(0,4),chip.size),card_caption,accent,1)
		footer.position.x+=chip_width+10
		footer.size.x-=chip_width+10
	_text(PoolStringArray(parts).join("  ·  "),footer,card_meta,Color(ink.r,ink.g,ink.b,ink.a*0.78))

func _media(area: Rect2):
	buttons.clear()
	var preset=str(item.source.preset)
	var art=media_state.get("artwork")
	var art_size=min(area.size.y,area.size.x*0.23)
	var text_area=area
	if item.source.artwork and preset!="Minimal":
		var art_rect=Rect2(area.position,Vector2(art_size,art_size))
		if preset=="Artwork Focus":
			art_size=min(area.size.x,area.size.y*0.65)
			art_rect=Rect2(Vector2(area.position.x+(area.size.x-art_size)/2,area.position.y),Vector2(art_size,art_size))
		if art!=null: _picture(art,art_rect,[0,0,1,1],false,true)
		else:
			var placeholder=StyleBoxFlat.new()
			placeholder.bg_color=Color(item.accent).darkened(0.6)
			placeholder.set_corner_radius_all(8)
			draw_style_box(placeholder,art_rect)
			_text("♪",Rect2(art_rect.position+Vector2(0,(art_size-font.get_height())/2),art_rect.size),font,Color(item.accent),1)
		if preset=="Artwork Focus": text_area=Rect2(area.position+Vector2(0,art_size+10),Vector2(area.size.x,area.size.y-art_size-10))
		else: text_area=Rect2(area.position+Vector2(art_size+12,0),Vector2(area.size.x-art_size-12,area.size.y))
	_text(str(media_state.get("title","No active media")),Rect2(text_area.position,Vector2(text_area.size.x,font.get_height()+2)),font,Color(item.color))
	var row_y=text_area.position.y+font.get_height()+3
	if item.source.artist and preset!="Minimal":
		_text(str(media_state.get("artist","")),Rect2(Vector2(text_area.position.x,row_y),Vector2(text_area.size.x,small_font.get_height()+2)),small_font,Color(item.color).darkened(0.2))
		row_y+=small_font.get_height()+6
	if item.source.source_icon and preset in ["Expanded","Floating Pop-out"]:
		_text(str(media_state.get("app","")),Rect2(Vector2(text_area.position.x,row_y),Vector2(text_area.size.x,small_font.get_height()+2)),small_font,Color(item.accent))
		row_y+=small_font.get_height()+6
	var controls=media_state.get("controls",{})
	if item.source.controls and row_y+22<=area.end.y and preset!="Minimal":
		for pair in [["previous","‹"],["toggle","Ⅱ" if media_state.get("playing",false) else "▶"],["next","›"]]:
			var rect=Rect2(Vector2(text_area.position.x,row_y),Vector2(32,24))
			var enabled=controls.get(pair[0],false)
			_text(pair[1],rect,small_font,Color(item.accent) if enabled else Color(item.border_color),1)
			if enabled: buttons[pair[0]]=rect
			text_area.position.x+=35
		row_y+=28
	var duration=float(media_state.get("duration",0))
	if item.source.progress and duration>0 and row_y+10<=area.end.y:
		var bar=Rect2(Vector2(area.position.x+art_size+12 if item.source.artwork and preset!="Artwork Focus" else area.position.x,area.end.y-8),Vector2(area.size.x-art_size-12 if item.source.artwork and preset!="Artwork Focus" else area.size.x,4))
		draw_rect(bar,Color(item.border_color))
		var fill=bar
		fill.size.x*=clamp(float(media_state.get("position",0))/duration,0,1)
		draw_rect(fill,Color(item.accent))
		if controls.get("seek",false): buttons.seek=bar.grow(6)

func _notification(what):
	if what==MainLoop.NOTIFICATION_WM_FOCUS_OUT and not preview: mouse_filter=Control.MOUSE_FILTER_IGNORE

func _exit_tree():
	if registered and is_instance_valid(sources): sources.unregister(self)
