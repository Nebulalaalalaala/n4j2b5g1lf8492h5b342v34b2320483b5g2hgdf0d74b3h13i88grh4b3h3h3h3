extends Reference

const NATIVE_KEYS = ["castle", "city", "dungeon", "grassy", "green", "meadow", "sandy", "snow"]
const BLOCK_BROS = ["mushroom_valley", "floating_island", "cloud_passage", "sweet_hazard", "animal_kingdom", "holy_night", "wild_jungle", "night_plain", "black_forest", "summer_beach"]
const FOLDERS = [
	{"key":"default", "name":"GooberDash", "color":"8ec9ff"},
	{"key":"custom", "name":"Custom", "color":"ffb1cf"},
	{"key":"themed", "name":"Themed", "color":"a4dfd0"},
	{"key":"block_bros", "name":"Block Bros.", "color":"ffe095"},
]

static func category(key: String, definitions: Dictionary) -> String:
	if not definitions.has(key): return "default"
	if BLOCK_BROS.has(key): return "block_bros"
	if str(definitions[key].get("folder", "custom")) == "themed": return "themed"
	return "custom"

static func title(key: String) -> String:
	for folder in FOLDERS:
		if folder.key == key: return folder.name
	return "Themes"

static func native_key(key: String) -> String:
	if key.begins_with("native/") and NATIVE_KEYS.has(key.substr(7)):
		return key.substr(7)
	return ""
