extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Journey theme rewards: the Goobplayability menu themes (EditorThemePack.gd,
# art in theme_backgrounds/) unlocked by Journey rank. Equipping calls the pack's
# own set_menu_theme(), which saves "client_tools_menu_theme" and redraws the
# main menu background. Nothing here touches accounts, levels or the server.
const PACK = "EditorThemePack.gd"
# Theme key -> rank id (0 = Bronze I ... 17 = Master III, 18 = King League 1).
const UNLOCKS = {
	"mushroom_valley": 1, "floating_island": 2, "cloud_passage": 3, "summer_beach": 4,
	"orchard": 5, "cosmic_dots": 6, "lagoon": 7, "animal_kingdom": 8, "wild_jungle": 9,
	"sweet_hazard": 10, "night_plain": 11, "holy_night": 12, "moon": 13, "porcelain": 14,
	"black_forest": 15, "ember": 16, "neon_grid": 17, "sunset_circuit": 18,
}
var base_dir = ""
var _definitions = null
var _pack = null
var _fallback = "follow"

func _init(directory):
	base_dir = directory

func definitions() -> Dictionary:
	if _definitions == null:
		_definitions = {}
		var path = ModPaths.path(PACK)
		if File.new().file_exists(path):
			var script = load(path)
			while script != null and _definitions.empty():   # the constant may live in a base file of the chain
				_definitions = script.get_script_constant_map().get("THEME_DEFINITIONS", {})
				script = script.get_base_script()
	return _definitions

# The running pack (owned by the TAS tool as _editor_theme_pack), if any.
func pack(tree):
	if _pack != null and is_instance_valid(_pack):
		return _pack
	_pack = null
	if tree == null:
		return null
	var queue = tree.root.get_children()
	var checked = 0
	while not queue.empty() and checked < 400:
		var node = queue.pop_front()
		checked += 1
		var candidate = node.get("_editor_theme_pack")
		if candidate != null and is_instance_valid(candidate) and candidate.has_method("set_menu_theme"):
			_pack = candidate
			return _pack
		if checked < 60:
			queue += node.get_children()
	return null

# Themes only show while Settings -> "Editor theme pack" is on.
func enabled(tree) -> bool:
	var p = pack(tree)
	return p != null and bool(p.gui_enabled)

func equipped(tree) -> String:
	var p = pack(tree)
	if p != null:
		return str(p.menu_theme) if bool(p.gui_enabled) else "follow"
	var settings = tree.root.get_node_or_null("SavedSettings") if tree != null else null
	return str(settings.get_value("client_tools_menu_theme", "follow")) if settings != null else _fallback

# Returns "equipped", "enabled" (the theme pack setting was switched on first)
# or "" when there is nothing to apply it with.
func equip(tree, key) -> String:
	var p = pack(tree)
	if p != null:
		var switched = false
		if not bool(p.gui_enabled) and str(key) != "follow":
			# Same path as the Settings toggle, so the saved setting stays in sync.
			var tool = p.get_parent()
			if tool != null and tool.has_method("_on_settings_editor_theme_pack_toggled"):
				tool._on_settings_editor_theme_pack_toggled(true)
			else:
				p.set_gui_enabled(true)
			switched = true
		p.set_menu_theme(str(key))
		return "enabled" if switched else "equipped"
	var settings = tree.root.get_node_or_null("SavedSettings") if tree != null else null
	if settings == null:
		# No game settings (tests): remember it for this run only.
		_fallback = str(key)
		return "equipped"
	return ""

func art(key, layer) -> Texture:
	var suffix = "-flat-v3.png" if key in ["mushroom_valley", "wild_jungle", "animal_kingdom"] else "-hd.png"
	var path = ModPaths.THEME_BACKGROUNDS_DIR + "%s-%s%s" % [key, layer, suffix]
	if not File.new().file_exists(path):
		return null
	var image = Image.new()
	if image.load(path) != OK:
		return null
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER)
	return texture

# Rewards list for the page: {key, name, requirement, rank, state, colors}.
func build(roadmap, xp, current) -> Array:
	var out = [{"key": "follow", "name": "Official", "requirement": "Always available", "rank": 0, "official": true,
		"state": "equipped" if current == "follow" else "unlocked", "colors": {"top": "5fb6ff", "bottom": "bfe8ff", "accent": "ffc40f", "terrain": "2f7fe0"}}]
	var defs = definitions()
	var keys = UNLOCKS.keys()
	keys.sort_custom(self, "_by_rank")
	for key in keys:
		if not defs.has(key):
			continue
		var d = defs[key]
		var index = int(UNLOCKS[key])
		var rank = null
		for r in roadmap:
			if int(r.id) == index:
				rank = r
		if rank == null:
			continue
		var unlocked = int(xp) >= int(rank.xp)
		out.append({"key": key, "name": str(d.get("name", key)), "requirement": "Reach " + str(rank.name), "rank": index,
			"rank_name": str(rank.name), "rank_xp": int(rank.xp), "rank_id": int(rank.get("id", index)), "state": ("equipped" if current == key else "unlocked") if unlocked else "locked",
			"colors": {"top": _hex(d.get("top")), "bottom": _hex(d.get("bottom")), "accent": _hex(d.get("accent")), "terrain": _hex(d.get("terrain"))}})
	return out

func unlocks_at(rank_id) -> Array:
	var names = []
	var defs = definitions()
	for key in UNLOCKS:
		if int(UNLOCKS[key]) == int(rank_id) and defs.has(key):
			names.append({"name": str(defs[key].get("name", key)) + " theme", "icon": "palette"})
	return names

func _by_rank(a, b) -> bool:
	return int(UNLOCKS[a]) < int(UNLOCKS[b])

func _hex(value) -> String:
	return value.to_html(false) if value is Color else "2f7fe0"
