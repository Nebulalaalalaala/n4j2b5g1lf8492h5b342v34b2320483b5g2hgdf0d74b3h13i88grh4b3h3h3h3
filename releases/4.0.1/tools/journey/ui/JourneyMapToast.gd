extends CanvasLayer
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")
const DISPLAY_SCALE = 0.82
var controller
var event = {}
var panel
var root_control
var ui
var age = 0.0
var duration = 4.5

func _ready():
	layer = 79
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	ui.reduced_motion = bool(Data.preference(self, controller, "reduced_motion", false))
	root_control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	panel = ui.card(root_control, ui.NAVY, 26, 32)
	var row = ui.box(panel, false, 24)
	var moment = str(event.get("moment", "finish"))
	if moment == "goal": duration = 3.0
	var accent = ui.YELLOW if moment == "first" else (ui.SKY_LIGHT if moment == "pb" else ui.GREEN_LIGHT)
	var icon = str(event.get("icon", "pin")) if moment == "goal" else ("stopwatch" if moment == "pb" else ("crown" if moment == "first" else "flag"))
	ui.icon(row, icon, 70, accent)
	var text = ui.grow(ui.box(row, true, 3))
	var title = {"first": "FIRST PLACE", "new": "NEW MAP", "pb": "NEW PERSONAL BEST", "goal": "PINNED GOAL"}.get(moment, "MAP COMPLETED")
	if moment == "goal" and int(event.to) >= int(event.target): title = "GOAL REACHED"
	ui.label(text, title, "h2", accent)
	ui.label(text, str(event.get("name", "")), "h3")
	var detail = "First finish"
	if moment == "first":
		detail = "New map · first place" if bool(event.get("new_map", false)) else "First time finishing first"
	elif moment == "new":
		detail = "Finished #%d" % int(event.get("rank", 0))
	elif moment == "pb":
		detail = "%.3fs faster · %.3fs" % [float(event.gain), float(event.time)]
	elif moment == "goal":
		detail = "%s → %s / %s" % [ui.thousands(event.from), ui.thousands(event.to), ui.thousands(event.target)]
		ui.bar(text, float(event.from) / max(1, int(event.target)), accent, 12)
		var bar = text.get_child(text.get_child_count() - 1)
		if ui.reduced_motion: bar.ratio = float(event.to) / max(1, int(event.target))
		else:
			var t = Tween.new()
			add_child(t)
			t.interpolate_property(bar, "ratio", float(event.from) / max(1, int(event.target)), float(event.to) / max(1, int(event.target)), 0.65, Tween.TRANS_CUBIC, Tween.EASE_OUT, 0.25)
			t.start()
	ui.label(text, detail, "small", ui.MUTED)
	# Objectives keep their existing manual-claim behavior. No fake XP award.
	get_viewport().connect("size_changed", self, "_fit")
	_fit()
	call_deferred("_compact")
	if controller.has_method("play_moment"):
		controller.play_moment("first" if moment == "first" else ("pb" if moment == "pb" else "claim"))
	elif is_instance_valid(controller.screen):
		controller.screen.play("claim")

func _fit():
	var viewport_size = get_viewport().get_visible_rect().size
	# Keep the existing layout, typography and slide choreography together,
	# but give the map/goal achievement toast a smaller on-screen footprint.
	var factor = min(clamp(viewport_size.y / 1920.0 * 1.7, 0.2, 1.7), viewport_size.x / 1100.0) * DISPLAY_SCALE
	scale = Vector2(factor, factor)
	root_control.rect_size = viewport_size / factor
	panel.rect_size.x = min(1260, root_control.rect_size.x - 64)
	panel.rect_position.x = (root_control.rect_size.x - panel.rect_size.x) * 0.5
	_position()

func _compact():
	# Autowrapped labels compute their height after the HBox receives its width.
	# Discard the temporary zero-width minimum rather than retaining a tall card.
	panel.rect_size.y = 0
	_position()

func _position():
	if ui.reduced_motion:
		panel.rect_position.y = 32
		return
	var hidden_y = -max(260, panel.rect_size.y) - 24
	if age < 0.24:
		var ratio = 1.0 - pow(1.0 - age / 0.24, 3)
		panel.rect_position.y = lerp(hidden_y, 32, ratio)
	elif age > duration - 0.26:
		panel.rect_position.y = lerp(32, hidden_y, clamp((age - (duration - 0.26)) / 0.24, 0, 1))
	else:
		panel.rect_position.y = 32

func _process(delta):
	age += delta
	if not is_instance_valid(controller) or str(controller.ledger.account_id) != str(event.get("account", "")) or age >= duration:
		queue_free()
		return
	_position()
