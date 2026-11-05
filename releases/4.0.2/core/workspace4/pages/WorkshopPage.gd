extends Reference
const EffectDocument = preload("user://mod/core/workspace4/effects/EffectDocument.gd")

# Workshop (local first): share overlays and effects as .goobpkg files.
# A package is plain JSON: {format, kind, name, author, version, data}.
# Nothing in a package can run code; import only accepts known kinds.
# Online: browse and upload through Supabase (Cloud.gd). Online installs go
# through the same checks as files; image widgets are never uploaded or
# installed from online, since they point at files on someone's computer.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const EffectRuntime = preload("user://mod/core/workspace4/EffectRuntime.gd")
const EffectsPage = preload("user://mod/core/workspace4/pages/EffectsPage.gd")
const SHARE_DIR = "user://goobplayability/workshop/"
const KINDS = ["overlay", "effect"]
const MAX_BYTES = 262144
const Cloud = preload("user://mod/core/workspace4/Cloud.gd")
const ONLINE_FIELDS = "id,kind,name,author,description,data,downloads,created_at"

var menu
var overlay_layer
var list: ItemList
var status: Label
var author: LineEdit
var cloud
var online_list: ItemList
var online_status: Label
var online_kind := ""
var online_rows := []
var kind_buttons := {}
var description: LineEdit

func build(owner_menu, content: VBoxContainer, layer) -> void:
	menu = owner_menu
	overlay_layer = layer
	cloud = Cloud.new()
	content.add_child(cloud)
	cloud.connect("finished", self, "_cloud_finished")
	var online = menu.card(content, "Browse online", Galaxy.color("playback"))
	var filters = Kit.row(online, 6)
	for entry in [["All", "", "star"], ["Overlays", "overlay", "overlay"], ["Effects", "effect", "effects"]]:
		kind_buttons[entry[1]] = Kit.action(menu, filters, entry[0], entry[2], self, "_set_online_kind", [entry[1]], entry[1] == online_kind)
	var filter_space = Control.new()
	filter_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(filter_space)
	Kit.action(menu, filters, "Refresh", "replay", self, "refresh_online")
	online_list = ItemList.new()
	online_list.rect_min_size = Vector2(0, 200)
	online_list.add_font_override("font", menu.font(15))
	online_list.add_stylebox_override("bg", Galaxy.box(Galaxy.color("surface"), Galaxy.color("border"), 6))
	online_list.add_color_override("font_color", Galaxy.color("ink"))
	online_list.connect("item_selected", self, "_online_selected")
	online.add_child(online_list)
	var online_actions = Kit.row(online, 8)
	Kit.action(menu, online_actions, "Install selected", "check", self, "_install_online", [], true)
	online_status = Kit.hint(menu, online_actions, "")
	online_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var share = menu.card(content, "Share", Galaxy.color("accent"))
	author = Kit.field(menu, Kit.labeled(menu, share, "Your name"), str(SavedSettings.get_value("workshop_author", "")), "Shown on packages you share", self, "_set_author")
	description = Kit.field(menu, Kit.labeled(menu, share, "Description"), "", "Optional, one line", null, "")
	var upload_line = Kit.row(share, 8)
	Kit.action(menu, upload_line, "Upload overlay layout", "overlay", self, "_upload", ["overlay"], true)
	Kit.action(menu, upload_line, "Upload worn effect", "effects", self, "_upload", ["effect"], true)
	var line = Kit.row(share, 8)
	Kit.action(menu, line, "Save overlay as file", "save", self, "_export_overlay")
	Kit.action(menu, line, "Save effect as file", "save", self, "_export_effect")
	Kit.action(menu, line, "Open share folder", "folder", self, "_open_folder")
	var install = menu.card(content, "Install from file", Galaxy.color("star"))
	Kit.hint(menu, install, "Put .goobpkg files in the share folder, then pick one and install it.")
	list = ItemList.new()
	list.rect_min_size = Vector2(0, 170)
	list.add_font_override("font", menu.font(15))
	list.add_stylebox_override("bg", Galaxy.box(Galaxy.color("surface"), Galaxy.color("border"), 6))
	list.add_color_override("font_color", Galaxy.color("ink"))
	install.add_child(list)
	var actions = Kit.row(install, 8)
	Kit.action(menu, actions, "Install selected", "check", self, "_install", [], true)
	Kit.action(menu, actions, "Refresh", "replay", self, "refresh")
	status = Kit.hint(menu, content, "")
	refresh()
	refresh_online()

func _set_author(value: String) -> void:
	SavedSettings.set_value("workshop_author", value.strip_edges().left(32))

func _package(kind: String, name: String, data) -> Dictionary:
	return {"format": 1, "kind": kind, "name": name, "author": str(SavedSettings.get_value("workshop_author", "")), "version": 1, "created": OS.get_unix_time(), "data": data}

func _write(package: Dictionary) -> void:
	var path = SHARE_DIR + EffectsPage.file_name(package.kind + "-" + package.name).get_basename() + ".goobpkg"
	status.text = ("Saved " + path.get_file() + " in the share folder.") if Kit.write_json(path, package) else "Couldn't write the package."
	refresh()

func _export_overlay() -> void:
	var layout = overlay_layer.layout.duplicate(true)
	layout.erase("enabled")
	_write(_package("overlay", "layout", layout))

func _export_effect() -> void:
	var worn = Kit.read_json(EffectRuntime.WORN, {})
	if worn.empty():
		status.text = "Wear an effect in the Effects Editor first."
		return
	_write(_package("effect", str(worn.get("name", "effect")), EffectDocument.export_data(worn)))

func refresh() -> void:
	list.clear()
	var dir = Directory.new()
	dir.make_dir_recursive(SHARE_DIR)
	if dir.open(SHARE_DIR) != OK:
		return
	dir.list_dir_begin(true, true)
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".goobpkg"):
			var package = Kit.read_json(SHARE_DIR + file, {})
			if not package.empty():
				list.add_item("%s · %s%s" % [str(package.get("kind", "?")).capitalize(), str(package.get("name", file)), (" · by " + str(package.author)) if not str(package.get("author", "")).empty() else ""])
				list.set_item_metadata(list.get_item_count() - 1, SHARE_DIR + file)
		file = dir.get_next()
	if list.get_item_count() == 0:
		list.add_item("No packages yet")

func _install() -> void:
	var picked = list.get_selected_items()
	if picked.empty() or list.get_item_metadata(picked[0]) == null:
		status.text = "Pick a package first."
		return
	var path = str(list.get_item_metadata(picked[0]))
	var file = File.new()
	if file.open(path, File.READ) == OK:
		var too_big = file.get_len() > MAX_BYTES
		file.close()
		if too_big:
			status.text = "That package is too large."
			return
	status.text = _install_package(Kit.read_json(path, {}), true)


func _install_package(package: Dictionary, allow_images: bool) -> String:
	var kind = str(package.get("kind", ""))
	if not kind in KINDS or typeof(package.get("data")) != TYPE_DICTIONARY:
		return "Not a package this version understands."
	if kind == "effect":
		var effect = EffectDocument.clean(package.data)
		if effect.empty(): return "That effect is unsupported or damaged."
		if not Kit.write_json(EffectRuntime.DIR + EffectsPage.file_name(str(effect.name)), EffectDocument.export_data(effect)):
			return "Could not save the effect."
		return "Installed the effect. Find it under Saved in Effects Editor."
	else:
		var document=load("user://mod/core/workspace4/overlays/OverlayDocument.gd").clean(package.data)
		if document.empty(): return "That overlay is unsupported or damaged."
		if not allow_images:
			var widgets=[]
			for widget in document.widgets:
				if widget.type in ["text","clock","fps"]: widgets.append(widget)
			document.widgets=widgets
		if not overlay_layer.apply_document(document): return "Could not save the overlay."

		return "Installed the overlay layout. Open Overlay Studio to adjust it."

func _open_folder() -> void:
	Directory.new().make_dir_recursive(SHARE_DIR)
	OS.shell_open(ProjectSettings.globalize_path(SHARE_DIR))


# ------------------------------------------------------------ online

func _set_online_kind(kind: String) -> void:
	online_kind = kind
	for key in kind_buttons:
		var on = key == kind
		var accent = Galaxy.color("accent")
		var ink = Galaxy.color("accent_ink") if on else Galaxy.color("ink")
		kind_buttons[key].add_stylebox_override("normal", Galaxy.primary_box(accent, 12) if on else Galaxy.box(Galaxy.color("raised"), Galaxy.color("line"), 12))
		kind_buttons[key].add_color_override("font_color", ink)
		kind_buttons[key].add_color_override("font_color_hover", ink)
	refresh_online()

func refresh_online() -> void:
	online_list.clear()
	online_list.add_item("Loading…")
	online_list.set_item_disabled(0, true)
	var query = "workshop_items?select=%s&order=created_at.desc&limit=60" % ONLINE_FIELDS
	if not online_kind.empty():
		query += "&kind=eq." + online_kind
	cloud.get_rows("list", query)

func _cloud_finished(tag: String, ok: bool, data) -> void:
	if tag == "list":
		online_list.clear()
		online_rows = []
		if not ok or typeof(data) != TYPE_ARRAY:
			online_list.add_item("Couldn't load the Workshop" if not ok else "Nothing shared yet")
			online_status.text = str(data) if not ok else ""
			return
		for row in data:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			online_rows.append(row)
			var by = str(row.get("author", ""))
			online_list.add_item("%s · %s%s · %d installs" % [str(row.get("kind", "?")).capitalize(), str(row.get("name", "")).left(60), (" · by " + by.left(32)) if not by.empty() else "", int(row.get("downloads", 0))])
		if online_rows.empty():
			online_list.add_item("Nothing shared yet")
	elif tag == "upload":
		online_status.text = "Uploaded. Thanks for sharing!" if ok else str(data)
		if ok:
			refresh_online()
	elif tag == "count":
		pass

func _online_selected(index: int) -> void:
	if index < online_rows.size():
		online_status.text = str(online_rows[index].get("description", "")).left(200)

func _install_online() -> void:
	var picked = online_list.get_selected_items()
	if picked.empty() or picked[0] >= online_rows.size():
		online_status.text = "Pick something first."
		return
	var row = online_rows[picked[0]]
	var package = {"kind": str(row.get("kind", "")), "name": str(row.get("name", "")), "data": row.get("data")}
	if typeof(package.data) == TYPE_DICTIONARY and package.kind == "effect":
		package.data["name"] = package.name
	online_status.text = _install_package(package, false)
	cloud.call_function("count", "workshop_count_install", {"item_id": str(row.get("id", ""))})

func _upload(kind: String) -> void:
	var name_text = str(SavedSettings.get_value("workshop_author", "")).strip_edges()
	if name_text.empty():
		online_status.text = "Add your name first."
		return
	var data = {}
	var title = ""
	if kind == "overlay":
		var widgets = []
		for widget in overlay_layer.layout.get("widgets", []):
			if typeof(widget) == TYPE_DICTIONARY and str(widget.get("type", "")) in ["text", "clock", "fps"]:
				widgets.append(widget)
		if widgets.empty():
			online_status.text = "Add a text, clock or FPS widget in Overlay Studio first. Images aren't uploaded."
			return
		data = {"widgets": widgets}
		title = "Overlay layout"
	else:
		data = Kit.read_json(EffectRuntime.WORN, {})
		if data.empty():
			online_status.text = "Wear an effect in the Effects Editor first."
			return
		title = str(data.get("name", "Effect"))
	if to_json(data).length() > Cloud.MAX_UPLOAD_BYTES:
		online_status.text = "That is too large to upload."
		return
	online_status.text = "Uploading…"
	cloud.insert("upload", "workshop_items", {"kind": kind, "name": title.left(60), "author": name_text.left(32), "description": description.text.strip_edges().left(200), "data": data})
