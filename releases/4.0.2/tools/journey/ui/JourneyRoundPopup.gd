extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")

# In-match "+XP" after you finish (or are out of) a round. Top centre, small,
# gone in about two seconds. Presentation only; the ledger is untouched.

var controller
var amount = 0
var detail = ""
var gold = false
var ui
var _root
var _age = 0.0

func setup(owner, xp, text, best = false):
	controller = owner
	amount = int(xp)
	detail = text
	gold = best
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())

func _ready():
	layer = 70
	ui.reduced_motion = bool(Data.preference(self, controller, "reduced_motion", false))
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var size = get_viewport().get_visible_rect().size
	var k = clamp(size.y / 1080.0, 0.5, 2.0)
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGN_CENTER
	col.add_constant_override("separation", 0)
	_root.add_child(col)
	var big = ui.label(col, ui.xp_text(amount), "h1", ui.YELLOW if gold else ui.WHITE, Label.ALIGN_CENTER)
	big.add_font_override("font", ui.font("display", int(54 * k), int(6 * k)))
	var small = ui.label(col, detail, "body", ui.SKY_LIGHT, Label.ALIGN_CENTER)
	small.add_font_override("font", ui.font("display", int(26 * k), int(4 * k)))
	big.autowrap = false
	small.autowrap = false
	var w = col.get_combined_minimum_size()
	col.rect_size = w
	col.rect_position = Vector2(size.x * 0.5 - w.x * 0.5, size.y * 0.16)
	col.rect_pivot_offset = w * 0.5
	if controller != null and controller.has_method("play_moment"):
		controller.play_moment("first" if gold else "claim", 1.0)
	var t = Tween.new()
	add_child(t)
	if not ui.reduced_motion:
		t.interpolate_property(col, "rect_scale", Vector2(1.8, 1.8), Vector2.ONE, 0.28, Tween.TRANS_BACK, Tween.EASE_OUT)
		t.interpolate_property(col, "modulate:a", 0.0, 1.0, 0.12)
		t.interpolate_property(col, "rect_position:y", col.rect_position.y, col.rect_position.y - 50 * k, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN, 1.7)
	t.interpolate_property(col, "modulate:a", 1.0, 0.0, 0.45, Tween.TRANS_QUAD, Tween.EASE_IN, 1.75)
	t.interpolate_callback(self, 2.3, "queue_free")
	t.start()
