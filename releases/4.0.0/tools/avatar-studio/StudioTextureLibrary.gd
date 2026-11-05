extends Reference

const LIMIT = 24
const MAX_BYTES = 8 * 1024 * 1024
const MAX_DIMENSION = 4096

static func valid_id(id: String) -> bool:
	return id.begins_with("import_") and id.length() <= 160 and not "/" in id and not "\\" in id and not ":" in id and not ".." in id

static func read_png(path: String) -> Dictionary:
	var file = File.new()
	if file.open(path,File.READ) != OK:
		return {"error":"Could not read the PNG file."}
	var length = file.get_len()
	if length < 33 or length > MAX_BYTES:
		file.close()
		return {"error":"Choose a valid PNG up to 8 MB."}
	var bytes = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"error":"Could not read the complete PNG file."}
	var signature = [137,80,78,71,13,10,26,10]
	for i in signature.size():
		if int(bytes[i]) != signature[i]:
			return {"error":"This file is not a PNG image."}
	if bytes[12] != 73 or bytes[13] != 72 or bytes[14] != 68 or bytes[15] != 82:
		return {"error":"The PNG header is invalid."}
	var width = int(bytes[16])*16777216+int(bytes[17])*65536+int(bytes[18])*256+int(bytes[19])
	var height = int(bytes[20])*16777216+int(bytes[21])*65536+int(bytes[22])*256+int(bytes[23])
	if width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION:
		return {"error":"PNG dimensions must be between 1 and 4096 pixels."}
	var image = Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return {"error":"The PNG could not be decoded."}
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != 512 or image.get_height() != 512:
		image.resize(512,512,Image.INTERPOLATE_LANCZOS)
	return {"image":image,"error":""}

# The registry is an index of usable local PNGs, not an ever-growing import
# counter. Missing/duplicate/broken entries do not occupy slots. Orphan PNGs
# left by an interrupted metadata write can be recovered without deleting data.
static func reconcile(entries: Array, directory: String) -> Dictionary:
	var kept = []
	var images = {}
	var seen = {}
	var candidates = entries.duplicate()
	var disk = Directory.new()
	var filenames = []
	if disk.open(directory) == OK:
		disk.list_dir_begin(true,true)
		var filename = disk.get_next()
		while not filename.empty() and filenames.size() < 256:
			if not disk.current_is_dir() and filename.get_extension().to_lower() == "png" and valid_id(filename.get_basename()):
				filenames.append(filename.get_basename())
			filename = disk.get_next()
		disk.list_dir_end()
	filenames.sort()
	for id in filenames:
		candidates.append({"id":id,"name":"Recovered texture","source":"imported"})
	for candidate in candidates:
		if not candidate is Dictionary or not candidate.get("id") is String or not candidate.get("name") is String:
			continue
		var id = str(candidate.id)
		if not valid_id(id) or seen.has(id):
			continue
		seen[id] = true
		var decoded = read_png(directory.plus_file(id+".png"))
		if not decoded.has("image"):
			continue
		var item = candidate.duplicate()
		item.name = str(item.name).substr(0,160)
		item.source = "imported"
		kept.append(item)
		images[id] = decoded.image
		if kept.size() >= LIMIT:
			break
	return {"entries":kept,"images":images}

static func save_registry(path: String, data: Dictionary) -> bool:
	var directory = Directory.new()
	if directory.make_dir_recursive(path.get_base_dir()) != OK:
		return false
	var contents = JSON.print(data)
	var file = File.new()
	var temporary = path+".tmp"
	var backup = path+".bak"
	if file.open(temporary,File.WRITE) != OK:
		return false
	file.store_string(contents)
	var error = file.get_error()
	file.close()
	if error != OK or file.open(temporary,File.READ) != OK:
		return false
	var read_back = file.get_as_text()
	file.close()
	if read_back != contents:
		return false
	var had_previous = directory.file_exists(path)
	if had_previous:
		if directory.file_exists(backup) and directory.remove(backup) != OK:
			return false
		if directory.rename(path,backup) != OK:
			return false
	if directory.rename(temporary,path) != OK:
		if had_previous:
			directory.rename(backup,path)
		return false
	return true
