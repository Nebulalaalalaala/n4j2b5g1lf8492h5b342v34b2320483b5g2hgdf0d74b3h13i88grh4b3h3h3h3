extends Control

# Presentation only: the victory crate / Daily Drop opening in the middle of the
# screen. The tier was fixed when the match was won; tapping (or waiting) only
# reveals it one rarity at a time. Never awards XP.

signal done

const TIERS = ["Common", "Rare", "Epic", "Legendary"]
const COLORS = [Color("bfe8ff"), Color("7ee08a"), Color("c99bff"), Color("ffb347")]
const AUTO_FIRST = 1.3
const AUTO_STEP = 0.8

var ui
var fx
var owner_card
var target = 0
var amount = 0
var title = ""
var big = false
var step = 0
var teased = false
var busy = 0.0
var idle = 0.0
var opened = false
var finished = false
var center = Vector2.ZERO
var _shade
var _stage
var _box
var _glow
var _hint
var _name
var _rng = RandomNumberGenerator.new()

func setup(design, effects, card, tier_name, xp, heading, is_drop = false):
	ui = design
	fx = effects
	owner_card = card
	target = max(0, TIERS.find(str(tier_name)))
	amount = int(xp)
	title = heading
	big = is_drop
	_rng.randomize()

func _ready():
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	center = get_parent().rect_size * Vector2(0.5, 0.46)
	_shade = ColorRect.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.color = Color(0.02, 0.03, 0.1, 0.0)
	_shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(_shade)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.rect_position = center
	add_child(_stage)
	var side = 300 if big else 250
	_glow = ui.image(_stage, "fx_glow", side * 2.4, Color(COLORS[0].r, COLORS[0].g, COLORS[0].b, 0.55))
	_glow.rect_position = -_glow.rect_min_size * 0.5
	_glow.rect_pivot_offset = _glow.rect_min_size * 0.5
	_box = ui.tile_icon(_stage, "rewards", Color.white, side)
	_box.rect_position = Vector2(-side, -side) * 0.5
	_box.rect_pivot_offset = Vector2(side, side) * 0.5
	_box.modulate = COLORS[0]
	var head = ui.label(_stage, title.to_upper(), "h2", ui.WHITE)
	head.add_font_override("font", ui.font("display", 52, 6))
	head.rect_position = Vector2(-head.get_combined_minimum_size().x * 0.5, -side * 0.5 - 130)
	_name = ui.label(_stage, "COMMON", "h2", COLORS[0])
	_name.add_font_override("font", ui.font("display", 60, 7))
	_place_name()
	_hint = ui.label(_stage, "Tap to open", "body", ui.SKY_LIGHT)
	_hint.add_font_override("font", ui.font("display", 34, 4))
	_hint.rect_position = Vector2(-_hint.get_combined_minimum_size().x * 0.5, side * 0.5 + 120)
	fx.raise()
	var t = Tween.new()
	add_child(t)
	t.interpolate_property(_shade, "color:a", 0.0, 0.62, 0.25)
	t.interpolate_property(_box, "rect_position:y", -900, -side * 0.5, 0.5, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	t.interpolate_property(_glow, "rect_scale", Vector2(0.2, 0.2), Vector2.ONE, 0.5, Tween.TRANS_BACK, Tween.EASE_OUT, 0.2)
	t.interpolate_callback(self, 0.42, "_landed")
	t.start()
	_pulse(_hint)
	busy = 0.55
	_sound("open", 0.9)

func _landed():
	fx.shake(8.0)
	fx.spark_burst(center + Vector2(0, 130), Color("dfe9ff"), 18, 420.0, 7.0)

func _place_name():
	_name.rect_position = Vector2(-_name.get_combined_minimum_size().x * 0.5, (300 if big else 250) * 0.5 + 30)
	_name.rect_pivot_offset = _name.get_combined_minimum_size() * 0.5

func _gui_input(event):
	var pressed = (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		accept_event()
		_advance()

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):
		get_tree().set_input_as_handled()
		_advance()

func _process(delta):
	busy -= delta
	if opened:
		return
	idle += delta
	if is_instance_valid(_box):
		# Anticipation: the crate shivers harder the closer it is to opening.
		var k = 2.0 + step * 2.5 + idle * 3.0
		_box.rect_rotation = sin(OS.get_ticks_msec() * 0.03) * min(14.0, k)
		_glow.rect_rotation += delta * (20 + step * 25)
	if idle >= (AUTO_FIRST if step == 0 and not teased else AUTO_STEP):
		_advance()

func _advance():
	if busy > 0.0 or opened:
		return
	idle = 0.0
	if step < target:
		step += 1
		_upgrade()
	elif not teased and target < 3 and (amount / 50) % 2 == 0:
		teased = true
		_tease()
	else:
		_open()

func _upgrade():
	busy = 0.42
	var color = COLORS[step]
	var t = Tween.new()
	add_child(t)
	_box.rect_scale = Vector2(1.4, 0.7)
	t.interpolate_property(_box, "rect_scale", Vector2(1.4, 0.7), Vector2(1.0 + step * 0.06, 1.0 + step * 0.06), 0.35, Tween.TRANS_ELASTIC, Tween.EASE_OUT)
	t.interpolate_property(_box, "modulate", Color(2.2, 2.2, 2.2), color, 0.3)
	t.interpolate_property(_glow, "modulate", Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.6 + step * 0.12), 0.4)
	t.interpolate_property(_glow, "rect_scale", Vector2(1.35, 1.35), Vector2(1.0 + step * 0.12, 1.0 + step * 0.12), 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.start()
	_name.text = TIERS[step].to_upper() + "!"
	_name.add_color_override("font_color", color)
	_place_name()
	var nt = Tween.new()
	add_child(nt)
	nt.interpolate_property(_name, "rect_scale", Vector2(2.0, 2.0), Vector2.ONE, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
	nt.start()
	fx.spark_burst(center, color, 24 + step * 10, 520.0 + step * 120, 9.0)
	fx.ring(center, color, 170.0 + step * 40)
	fx.shake(5.0 + step * 3.0)
	if step >= 2:
		fx.flash(color, 0.18 + 0.06 * step)
	_sound("tick", 1.2 + step * 0.22)
	_sound("claim", 0.9 + step * 0.12)

# Near miss: it looks like it's about to climb again, then settles.
func _tease():
	busy = 0.7
	var t = Tween.new()
	add_child(t)
	var next = COLORS[min(3, step + 1)]
	t.interpolate_property(_box, "rect_scale", _box.rect_scale, Vector2(1.18, 1.18), 0.35, Tween.TRANS_QUAD, Tween.EASE_IN)
	t.interpolate_property(_box, "modulate", COLORS[step], next.linear_interpolate(Color.white, 0.2), 0.35)
	t.interpolate_property(_box, "rect_scale", Vector2(1.18, 1.18), Vector2(1.0, 1.0), 0.25, Tween.TRANS_BACK, Tween.EASE_OUT, 0.38)
	t.interpolate_property(_box, "modulate", next, COLORS[step], 0.25, Tween.TRANS_LINEAR, Tween.EASE_OUT, 0.38)
	t.start()
	fx.shake(4.0)
	_sound("tick", 1.0 + step * 0.22)

func _open():
	opened = true
	busy = 99.0
	var color = COLORS[target]
	_hint.hide()
	_box.rect_rotation = 0
	var t = Tween.new()
	add_child(t)
	t.interpolate_property(_box, "rect_scale", _box.rect_scale, Vector2(1.6, 1.6), 0.12, Tween.TRANS_QUAD, Tween.EASE_IN)
	t.interpolate_property(_box, "rect_scale", Vector2(1.6, 1.6), Vector2(0.1, 0.1), 0.16, Tween.TRANS_BACK, Tween.EASE_IN, 0.12)
	t.interpolate_property(_box, "modulate:a", 1.0, 0.0, 0.16, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.12)
	t.interpolate_callback(self, 0.2, "_burst_open", color)
	t.start()

func _burst_open(color):
	var rays = ui.image(_stage, "fx_rays", 760 + target * 180, Color(color.r, color.g, color.b, 0.0))
	rays.rect_position = -rays.rect_min_size * 0.5
	rays.rect_pivot_offset = rays.rect_min_size * 0.5
	_stage.move_child(rays, 0)
	var t = Tween.new()
	add_child(t)
	t.interpolate_property(rays, "modulate:a", 0.0, 0.9, 0.15)
	t.interpolate_property(rays, "rect_scale", Vector2(0.3, 0.3), Vector2.ONE, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(rays, "rect_rotation", 0.0, 200.0 + target * 80, 2.4, Tween.TRANS_QUAD, Tween.EASE_OUT)
	t.interpolate_property(_glow, "rect_scale", Vector2(0.6, 0.6), Vector2(1.5, 1.5), 0.5, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(_glow, "modulate", Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.8), 0.5)
	# The amount, counted up fast under the tier name.
	_name.text = TIERS[target].to_upper()
	_name.add_font_override("font", ui.font("display", 76 + target * 10, 8))
	_name.rect_position = Vector2(-_name.get_combined_minimum_size().x * 0.5, -150)
	_name.rect_pivot_offset = _name.get_combined_minimum_size() * 0.5
	t.interpolate_property(_name, "rect_scale", Vector2(2.4, 2.4), Vector2.ONE, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
	var xp = ui.label(_stage, "+0 XP", "h1", ui.YELLOW)
	xp.add_font_override("font", ui.font("display", 96, 8))
	xp.name = "Amount"
	_amount_label = xp
	_set_amount(0)
	t.interpolate_method(self, "_set_amount", 0, amount, 0.55, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.15)
	t.interpolate_callback(self, 0.72, "_amount_landed")
	t.interpolate_callback(self, 1.5 + target * 0.25, "_fly")
	t.start()
	fx.spark_burst(center, color, 40 + target * 30, 760.0 + target * 180, 11.0 + target * 2)
	fx.spark_burst(center, Color.white, 16 + target * 6, 480.0, 7.0)
	fx.ring(center, color, 240 + target * 70)
	fx.shake(10.0 + target * 6.0)
	fx.flash(color, 0.22 + target * 0.08)
	if target >= 2:
		var b = ui.burst(_stage)
		if b != null:
			b.rect_position = Vector2(-450, -450)
			b.rect_size = Vector2(900, 900)
	if target == 3:
		for i in 7:
			get_tree().create_timer(0.1 * i).connect("timeout", fx, "spark_burst", [center + Vector2(_rng.randf_range(-380, 380), _rng.randf_range(-220, 220)), Color("ffd35a"), 22, 560.0, 9.0])
	_sound(["claim", "claim", "rankup", "league"][target], 1.0 + target * 0.04)

var _amount_label = null
var _last_tick = -1
func _set_amount(value):
	if not is_instance_valid(_amount_label):
		return
	_amount_label.text = ui.xp_text(int(value))
	var w = _amount_label.get_combined_minimum_size()
	_amount_label.rect_position = Vector2(-w.x * 0.5, 40)
	var tick = int(float(value) / max(1, amount) * 12)
	if tick > _last_tick and int(value) < amount:
		_last_tick = tick
		_sound("tick", 1.0 + float(value) / max(1, amount) * 0.5)

func _amount_landed():
	if is_instance_valid(_amount_label):
		fx.punch(_amount_label, 1.25, Color(1.6, 1.4, 0.9))

func _fly():
	if is_instance_valid(_amount_label) and is_instance_valid(owner_card) and is_instance_valid(owner_card.get("_count")):
		fx.orbs(_amount_label, owner_card._count, COLORS[target], 10 + target * 4, owner_card, "_orb_hit")
	var t = Tween.new()
	add_child(t)
	t.interpolate_property(self, "modulate:a", 1.0, 0.0, 0.35, Tween.TRANS_QUAD, Tween.EASE_IN, 0.1)
	t.interpolate_callback(self, 0.5, "_finish")
	t.start()

func _finish():
	if finished:
		return
	finished = true
	emit_signal("done")
	queue_free()

func _exit_tree():
	# Never leave the result waiting if the card closes mid-reveal.
	if not finished:
		finished = true
		emit_signal("done")

func _pulse(control):
	var t = Tween.new()
	control.add_child(t)
	t.repeat = true
	t.interpolate_property(control, "modulate:a", 1.0, 0.35, 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	t.interpolate_property(control, "modulate:a", 0.35, 1.0, 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.6)
	t.start()

func _sound(key, pitch = 1.0):
	if is_instance_valid(owner_card) and owner_card.has_method("_play"):
		owner_card._play(key, pitch)
