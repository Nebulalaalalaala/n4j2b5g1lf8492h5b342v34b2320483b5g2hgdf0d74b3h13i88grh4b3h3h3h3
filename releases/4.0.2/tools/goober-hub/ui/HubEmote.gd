extends Control
# A GooberDash emote in chat: the game's own emote animation, sent as :<cosmetic id>:.
const SCENE = "res://project_specific/gfx/spine/upguy/emote.tscn"
var spine = "" setget set_spine   # the emote's animation name (catalog()[id].spine)
var animated = false
var _sprite = null

# Emote cosmetics: id -> {name, spine}.
static func catalog() -> Dictionary:
	var out = {}
	var all = CosmeticsCollection.filter_cosmetics_type("emote")
	for id in all:
		if not str(all[id].get("spine", "")).empty():
			out[str(id)] = {"name": str(all[id].get("name", id)), "spine": str(all[id].spine)}
	return out

# The ones this account can use: unlocked or equipped, equipped first.
static func owned(list) -> Array:
	var cards = Moonlight.storage.storage_get("player.profile.cards", {})
	var out = []
	for id in Moonlight.storage.storage_get("player.profile.emotes", []) + list.keys():
		if list.has(str(id)) and not out.has(str(id)) and (bool(cards.get(id, {}).get("unlocked", false)) or Moonlight.storage.storage_get("player.profile.emotes", []).has(id)):
			out.append(str(id))
	return out

func set_spine(value):
	spine = str(value)
	if is_inside_tree():
		_show()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized", self, "_place")
	_show()

func _show():
	if spine.empty():
		return
	if _sprite == null:
		var packed = load(SCENE)
		if packed == null:
			return
		_sprite = packed.instance()
		add_child(_sprite)
	_place()
	if animated:
		_sprite.show_loop_animation(spine)
	else:
		_sprite.show_static_frame(spine)

# Same framing as the emote wheel (108x88 card, 0.32 scale).
func _place():
	if _sprite != null:
		var s = min(rect_size.x, rect_size.y)
		_sprite.position = Vector2(rect_size.x * 0.5, rect_size.y * 0.5 - s * 0.16)
		_sprite.scale = Vector2.ONE * s * 0.0036
