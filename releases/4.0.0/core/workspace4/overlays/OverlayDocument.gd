extends Reference

const VERSION = 2
const TYPES = ["text","image","clock","fps","keyboard","media","camera","game"]
const TITLES = {"text":"Text","image":"Image","clock":"Clock","fps":"Frame rate","keyboard":"Keyboard","media":"Universal Media Player","camera":"Handcam","game":"Game information"}
const MAX_WIDGETS = 64
const MAX_BYTES = 2097152
const FONT_NAMES = ["Segoe UI","Inter Semibold","Segoe UI Semibold","Segoe UI Bold"]

static func uid() -> String:
	return str(OS.get_unix_time())+"-"+str(OS.get_ticks_usec())+"-"+Crypto.new().generate_random_bytes(6).hex_encode()

static func empty(name = "My overlay") -> Dictionary:
	return {"version":VERSION,"id":uid(),"name":name,"enabled":false,"width":1920,"height":1080,"scale_mode":"screen","widgets":[]}

static func widget(kind: String, reference = Vector2(1920,1080)) -> Dictionary:
	var size = Vector2(260,70)
	if kind=="image": size=Vector2(320,220)
	elif kind=="keyboard": size=Vector2(340,150)
	elif kind=="media": size=Vector2(430,124)
	elif kind=="camera": size=Vector2(384,216)
	elif kind=="game": size=Vector2(440,144)
	return {"id":uid(),"type":kind,"name":TITLES.get(kind,"Widget"),"x":0.08,"y":0.10,"w":size.x/reference.x,"h":size.y/reference.y,"visible":true,"locked":false,"group":"","opacity":1.0,"rotation":0.0,"font":FONT_NAMES[1],"font_size":24.0,"font_outline":0.0,"color":"f5f3ff","background":"1a1d38","background_opacity":0.92 if kind in ["keyboard","media","camera","game"] else 0.0,"accent":"a68bff","border":true if kind in ["keyboard","media","camera","game"] else false,"border_color":"484b70","border_width":1.0,"radius":14.0,"shadow":true if kind in ["keyboard","media","game"] else false,"padding":12.0,"source":source_defaults(kind)}

static func source_defaults(kind: String) -> Dictionary:
	match kind:
		"text": return {"text":"Goobplayability","align":0,"wrap":true}
		"image": return {"path":"","crop":[0.0,0.0,1.0,1.0],"mirror":false,"aspect_lock":true}
		"clock": return {"format":"24h","seconds":false}
		"fps": return {"suffix":true}
		"keyboard": return {"preset":"GooberDash","keys":keys("GooberDash"),"pressed":"a68bff","idle":"252947","text":"f5f3ff","shape":"rounded","animate":true,"rise":true,"rise_seconds":0.85,"rise_distance":110.0,"counter":false,"mouse":false}
		"media": return {"mode":"system","session":"auto","app":"","preset":"Compact","artwork":true,"artist":true,"progress":true,"controls":true,"source_icon":true,"when_stopped":"show","transition":true,"playlist":[],"shuffle":false,"repeat":"off","volume":0.5}
		"camera": return {"device":"","mirror":false,"crop":[0.0,0.0,1.0,1.0],"width":640,"height":360,"fps":15}
		"game": return {"field":"level","presentation":"Card","details":true,"artwork":true,"author":true,"show_idle":false,"appearance_version":1}
	return {}

static func keys(preset: String) -> Array:
	var result=[]
	var specs=[["A","player_left",0.05,0.52],["W","player_up",0.29,0.05],["D","player_right",0.53,0.52],["Dash","player_dash",0.77,0.52]]
	if preset in ["WASD","WASD + Space","WASD + Shift"]: specs=[["W","",0.29,0.05],["A","",0.05,0.52],["S","",0.29,0.52],["D","",0.53,0.52]]
	if preset=="Arrows": specs=[["Up","",0.29,0.05],["Left","",0.05,0.52],["Down","",0.29,0.52],["Right","",0.53,0.52]]
	if preset=="WASD + Space": specs.append(["Space","",0.77,0.52])
	if preset=="WASD + Shift": specs.append(["Shift","",0.77,0.52])
	for item in specs:
		result.append({"id":uid(),"label":item[0],"action":item[1],"code":OS.find_scancode_from_string(item[0]) if item[0]!="Dash" else KEY_SPACE,"kind":"key","x":item[2],"y":item[3],"w":0.20,"h":0.40,"shape":"rounded"})
	return result

static func safe_id(value: String) -> String:
	var result=""
	for character in value:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_": result+=character
	return result.left(100)

static func finite(value, fallback: float, low: float, high: float) -> float:
	if not typeof(value) in [TYPE_INT,TYPE_REAL]: return fallback
	var number=float(value)
	return clamp(number,low,high) if not is_nan(number) and not is_inf(number) else fallback

static func rgb(value, fallback = "f5f3ff") -> String:
	var text=str(value).trim_prefix("#").to_lower()
	if text.length()!=6: return fallback
	for character in text:
		if not character in "0123456789abcdef": return fallback
	return text

static func clean(raw, legacy_view = Vector2(1920,1080)) -> Dictionary:
	if not raw is Dictionary: return {}
	if not typeof(raw.get("version",1)) in [TYPE_INT,TYPE_REAL]: return {}
	if int(raw.get("version",1))>VERSION or not raw.get("widgets",[]) is Array: return {}
	var doc=empty(str(raw.get("name","My overlay")).strip_edges().left(80))
	doc.id=safe_id(str(raw.get("id",doc.id)))
	if doc.id.empty(): doc.id=uid()
	if str(doc.name).empty(): doc.name="My overlay"
	doc.enabled=bool(raw.get("enabled",false))
	doc.width=int(finite(raw.get("width",1920),1920,640,7680))
	doc.height=int(finite(raw.get("height",1080),1080,360,4320))
	doc.scale_mode="fit" if raw.get("scale_mode","screen") == "fit" or int(raw.get("version",1))<2 else "screen"
	if int(raw.get("version",1))<2: doc.height=int(doc.width*legacy_view.y/max(1.0,legacy_view.x))
	var seen={}
	for value in raw.get("widgets",[]):
		if doc.widgets.size()>=MAX_WIDGETS: break
		if not value is Dictionary or not str(value.get("type","")) in TYPES: continue
		var kind=str(value.type)
		var item=widget(kind,Vector2(doc.width,doc.height))
		item.id=str(value.get("id",item.id)).left(100)
		if item.id.empty() or seen.has(item.id): item.id=uid()
		seen[item.id]=true
		item.name=str(value.get("name",item.name)).strip_edges().left(80)
		for key in ["visible","locked","border","shadow"]: item[key]=bool(value.get(key,item[key]))
		item.group=str(value.get("group","")).left(100)
		for key in ["x","y"]: item[key]=finite(value.get(key,item[key]),item[key],-2,2)
		for key in ["w","h"]: item[key]=finite(value.get(key,item[key]),item[key],0.005,4)
		item.opacity=finite(value.get("opacity",1),1,0,1)
		item.rotation=finite(value.get("rotation",0),0,-360,360)
		item.font=str(value.get("font",item.font))
		if item.font=="Inter-SemiBold.ttf": item.font="Inter Semibold"
		if not item.font in FONT_NAMES: item.font=FONT_NAMES[1]
		for spec in [["font_size",8,320],["font_outline",0,12],["background_opacity",0,1],["border_width",0,16],["radius",0,120],["padding",0,100]]:
			item[spec[0]]=finite(value.get(spec[0],item[spec[0]]),item[spec[0]],spec[1],spec[2])
		for key in ["color","background","accent","border_color"]: item[key]=rgb(value.get(key,item[key]),item[key])
		var source=value.get("source",{})
		if source is Dictionary:
			for key in item.source.keys():
				if source.has(key):
					if typeof(source[key])==typeof(item.source[key]) or (typeof(source[key]) in [TYPE_INT,TYPE_REAL] and typeof(item.source[key]) in [TYPE_INT,TYPE_REAL]): item.source[key]=source[key]
		if int(raw.get("version",1))<2:
			item.padding=0.0
			item.font_size=finite(value.get("size",28),28,8,160)*float(doc.width)/max(1.0,legacy_view.x)
			item.font_outline=2.0*float(doc.width)/max(1.0,legacy_view.x)
			if kind!="image":
				var legacy_text=str(value.get("text","Goobplayability")) if kind=="text" else "00:00:00 FPS"
				item.w=max(item.w,float(legacy_text.length()+1)*item.font_size/doc.width)
				item.h=max(item.h,item.font_size*1.5/doc.height)
				if kind=="text": item.source.wrap=false
			if kind=="text": item.source.text=str(value.get("text","Goobplayability"))
			if kind=="image":
				item.source.path=str(value.get("path",""))
				item.w=finite(value.get("size",160),160,16,4096)/max(1.0,legacy_view.x)
				var ratio=1.0
				var legacy_image=Image.new()
				var image_file=File.new()
				if image_file.file_exists(item.source.path) and image_file.open(item.source.path,File.READ)==OK:
					var length=image_file.get_len()
					image_file.close()
					if length<=33554432 and legacy_image.load(item.source.path)==OK and legacy_image.get_width()>0: ratio=float(legacy_image.get_height())/legacy_image.get_width()
				item.h=item.w*ratio*float(doc.width)/doc.height
		if kind=="keyboard":
			item.source.keys=clean_keys(item.source.keys)
			item.source.rise_seconds=finite(item.source.rise_seconds,0.85,0.25,2.0)
			item.source.rise_distance=finite(item.source.rise_distance,110,20,400)
			for key in ["idle","pressed","text"]: item.source[key]=rgb(item.source[key],source_defaults("keyboard")[key])
		elif kind=="media":
			var files=[]
			for path in item.source.playlist:
				if files.size()>=256: break
				if path is String and path.get_extension().to_lower() in ["mp3","wav","ogg"]: files.append(path.left(2048))
			item.source.playlist=files
			if not item.source.mode in ["system","local"]: item.source.mode="system"
			if not item.source.preset in ["Compact","Minimal","Expanded","Artwork Focus","Floating Pop-out"]: item.source.preset="Compact"
			if not item.source.when_stopped in ["show","hide"]: item.source.when_stopped="show"
			if not item.source.repeat in ["off","one","all"]: item.source.repeat="off"
			item.source.volume=finite(item.source.volume,0.5,0,1)
		elif kind=="camera":
			item.source.width=int(finite(item.source.width,640,160,1920))
			item.source.height=int(finite(item.source.height,360,120,1080))
			item.source.fps=int(finite(item.source.fps,15,5,30))
		if kind in ["camera","image"]:
			var crop=item.source.crop
			item.source.crop=[0.0,0.0,1.0,1.0]
			if crop is Array and crop.size()==4:
				item.source.crop=[finite(crop[0],0,0,0.99),finite(crop[1],0,0,0.99),finite(crop[2],1,0.01,1),finite(crop[3],1,0.01,1)]
		if kind in ["camera","image"]:
			item.source.crop[2]=min(item.source.crop[2],1.0-item.source.crop[0])
			item.source.crop[3]=min(item.source.crop[3],1.0-item.source.crop[1])
		if kind=="text":
			item.source.text=str(item.source.text).left(10000)
			item.source.align=int(finite(item.source.align,0,0,2))
		if kind=="clock" and not item.source.format in ["12h","24h"]: item.source.format="24h"
		if kind=="game":
			if source is Dictionary and not source.has("appearance_version"):
				# Upgrade the old unversioned text/weak card once; preserve nearest edges.
				var before=rect(item,Vector2(doc.width,doc.height))
				var upgraded=Rect2(before.position,Vector2(max(440,before.size.x),max(144,before.size.y)))
				if before.get_center().x>doc.width/2.0: upgraded.position.x=before.end.x-upgraded.size.x
				if before.get_center().y>doc.height/2.0: upgraded.position.y=before.end.y-upgraded.size.y
				set_rect(item,upgraded,Vector2(doc.width,doc.height))
				item.background_opacity=max(0.94,item.background_opacity)
				item.border=true
				item.shadow=true
				item.source.presentation="Card"
				item.source.appearance_version=1
			if not item.source.field in ["level","players","location"]: item.source.field="level"
			if item.source.field!="level" and source is Dictionary and not source.has("show_idle"): item.source.show_idle=true
			if not item.source.presentation in ["Card","Plain text"]: item.source.presentation="Card"
		for key in item.source.keys():
			if item.source[key] is String: item.source[key]=item.source[key].left(2048)
		doc.widgets.append(item)
	return doc

static func clean_keys(raw) -> Array:
	var result=[]
	if not raw is Array: return result
	for value in raw:
		if result.size()>=64: break
		if not value is Dictionary: continue
		var item={"id":str(value.get("id",uid())).left(100),"label":str(value.get("label","Key")).left(24),"action":str(value.get("action","")).left(80),"code":int(finite(value.get("code",0),0,0,33554431)),"kind":"mouse" if value.get("kind")=="mouse" else "key","shape":str(value.get("shape","rounded"))}
		for key in ["x","y"]: item[key]=finite(value.get(key,0),0,-2,2)
		for key in ["w","h"]: item[key]=finite(value.get(key,0.2),0.2,0.01,3)
		result.append(item)
	return result

# Normalized placement follows the game aspect by default. A fixed reference is
# explicit; narrow-window authoring must not permanently letterbox a wide screen.
static func reference(doc: Dictionary, viewport_size: Vector2) -> Vector2:
	var width=float(doc.get("width",1920))
	if doc.get("scale_mode","screen")=="fit": return Vector2(width,float(doc.get("height",1080)))
	return Vector2(width,round(width*viewport_size.y/max(1.0,viewport_size.x)))

static func display_rect(item: Dictionary, doc: Dictionary, target: Vector2) -> Rect2:
	var original=Vector2(doc.width,doc.height)
	var box=rect(item,original)
	if doc.get("scale_mode","screen")=="screen" and box.size.y<min(original.y,target.y):
		# Preserve component proportions and its relative travel between top/bottom.
		# A bottom-aligned card remains bottom-aligned without stretching its art.
		box.position.y=box.position.y/max(1,original.y-box.size.y)*max(0,target.y-box.size.y)
	return box

static func reframe(doc: Dictionary, viewport_size: Vector2) -> bool:
	if doc.get("scale_mode","screen")!="screen": return false
	var target=reference(doc,viewport_size)
	target.y=round(target.y)
	if int(doc.height)==int(target.y): return false
	for item in doc.widgets: set_rect(item,display_rect(item,doc,target),target)
	doc.height=int(target.y)
	return true

static func rect(item: Dictionary, reference: Vector2) -> Rect2:
	return Rect2(Vector2(item.x,item.y)*reference,Vector2(item.w,item.h)*reference)

static func set_rect(item: Dictionary, value: Rect2, reference: Vector2) -> void:
	item.x=value.position.x/reference.x
	item.y=value.position.y/reference.y
	item.w=max(8.0,value.size.x)/reference.x
	item.h=max(8.0,value.size.y)/reference.y

static func read(path: String):
	var file=File.new()
	if file.open(path,File.READ)!=OK: return {}
	if file.get_len()>MAX_BYTES:
		file.close()
		return {}
	var parsed=JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error==OK and parsed.result is Dictionary else {}

static func write(path: String, data: Dictionary) -> bool:
	var directory=Directory.new()
	if directory.make_dir_recursive(path.get_base_dir())!=OK: return false
	var file=File.new()
	var temp=path+".tmp"
	if file.open(temp,File.WRITE)!=OK: return false
	file.store_string(JSON.print(data,"  "))
	file.close()
	if read(temp).empty(): return false
	var previous=path+".previous"
	if directory.file_exists(path):
		if directory.file_exists(previous) and directory.remove(previous)!=OK: return false
		if directory.rename(path,previous)!=OK: return false
	if directory.rename(temp,path)==OK: return true
	if directory.file_exists(previous): directory.rename(previous,path)
	return false
