extends Reference
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const DIR="user://goobplayability/overlays/layouts/"

static func key(value: String) -> String:
	var result=""
	for character in value:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_": result+=character
	return result.left(100)

static func path(id: String) -> String:
	return DIR+key(id)+".overlay.json"

static func list_layouts() -> Array:
	var result=[]
	var dir=Directory.new()
	if dir.open(DIR)!=OK: return result
	dir.list_dir_begin(true,true)
	var name=dir.get_next()
	while not name.empty():
		if name.ends_with(".overlay.json"):
			var data=Doc.read(DIR+name)
			if not data.empty(): result.append({"id":str(data.get("id","")),"name":str(data.get("name","Overlay")),"path":DIR+name})
		if result.size()>=128: break
		name=dir.get_next()
	dir.list_dir_end()
	return result

static func save(data: Dictionary) -> bool:
	return not key(str(data.get("id",""))).empty() and Doc.write(path(data.id),data)

static func remove(id: String) -> bool:
	# Keep recoverable user data instead of permanently deleting a layout.
	var source=path(id)
	var dir=Directory.new()
	if not dir.file_exists(source): return true
	if dir.make_dir_recursive(DIR+"trash")!=OK: return false
	return dir.rename(source,DIR+"trash/"+key(id)+"-"+str(OS.get_unix_time())+".overlay.json")==OK

static func save_widget(item: Dictionary) -> bool:
	var doc=Doc.empty(str(item.name))
	doc.widgets=[item.duplicate(true)]
	var name=key(str(item.name))
	if name.empty(): name=key(str(item.id))
	return Doc.write(DIR+"widgets/"+name+".overlay.json",Doc.clean(doc))

static func widget_presets(kind: String) -> Array:
	var result=[]
	var dir=Directory.new()
	if dir.open(DIR+"widgets/")!=OK: return result
	dir.list_dir_begin(true,true)
	var name=dir.get_next()
	while not name.empty():
		if name.ends_with(".overlay.json"):
			var data=Doc.clean(Doc.read(DIR+"widgets/"+name))
			if not data.empty() and not data.widgets.empty() and data.widgets[0].type==kind: result.append({"name":data.name,"widget":data.widgets[0]})
		if result.size()>=128: break
		name=dir.get_next()
	dir.list_dir_end()
	return result
