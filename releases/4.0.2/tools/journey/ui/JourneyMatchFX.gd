extends Control

# Presentation only, for the match result card: flying XP, counter punches,
# the victory crate reveal, streak embers and card shake. Draws above the card,
# never takes input, frees itself with the card. Nothing here touches XP.

const TIER_COLORS = [Color("bfe8ff"), Color("7ee08a"), Color("c99bff"), Color("ffb347")]
const TIERS = ["Common", "Rare", "Epic", "Legendary"]

var ui
var card
var parts = []   # {p, v, life, age, size, color, kind}
var embers = []  # emitters: {control, color, rate, acc}
var _shake = 0.0
var _shake_base = Vector2.ZERO
var _rng = RandomNumberGenerator.new()
var _bar = null
var _bar_ratio = -1.0
var _bar_color = Color.white

func setup(design, card_panel):
	ui = design
	card = card_panel
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	set_process(true)

func _local(control) -> Vector2:
	return control.rect_global_position + control.rect_size * 0.5 - rect_global_position

# ------------------------------------------------------------------ emitters
func spark_burst(at: Vector2, color: Color, count = 26, speed = 620.0, size = 9.0):
	for i in count:
		var a = _rng.randf() * TAU
		var s = _rng.randf_range(0.35, 1.0) * speed
		parts.append({"p": at, "v": Vector2(cos(a), sin(a)) * s, "life": _rng.randf_range(0.45, 0.9), "age": 0.0,
			"size": _rng.randf_range(0.5, 1.0) * size, "color": color, "kind": "spark"})

func ring(at: Vector2, color: Color, radius = 160.0):
	parts.append({"p": at, "v": Vector2.ZERO, "life": 0.55, "age": 0.0, "size": radius, "color": color, "kind": "ring"})

# XP flies from a reward row into the big counter, leaving a trail.
class Flyer extends Label:
	var fx
	var a = Vector2.ZERO
	var mid = Vector2.ZERO
	var b = Vector2.ZERO
	var color = Color.white
	var t = 0.0 setget _set_t
	func _set_t(v):
		t = v
		rect_position = a.linear_interpolate(mid, t).linear_interpolate(mid.linear_interpolate(b, t), t)
		if fx != null and is_instance_valid(fx):
			fx.trail(rect_position + rect_size * 0.5, color)

func trail(p: Vector2, color: Color):
	if _rng.randf() < 0.85:
		parts.append({"p": p, "v": Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60)), "life": 0.35, "age": 0.0, "size": 7.0, "color": color, "kind": "spark"})

func fly(from_control, to_control, text: String, color: Color, on_arrive = null):
	if not is_instance_valid(from_control) or not is_instance_valid(to_control):
		return
	var l = Flyer.new()
	l.fx = self
	l.color = color
	l.text = text
	l.add_font_override("font", ui.font("display", 40, 4))
	l.add_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(l)
	l.a = _local(from_control) + Vector2(from_control.rect_size.x * 0.25, -24)
	l.b = _local(to_control) - Vector2(to_control.rect_size.x * 0.3, 24)
	l.mid = (l.a + l.b) * 0.5 + Vector2(-160, -140)
	l.t = 0.0
	var t = Tween.new()
	l.add_child(t)
	t.interpolate_property(l, "t", 0.0, 1.0, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN, 0.05)
	t.interpolate_property(l, "rect_scale", Vector2(0.6, 0.6), Vector2(1.15, 1.15), 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.1, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.5)
	t.interpolate_callback(self, 0.56, "_arrived", l, on_arrive)
	t.start()

func _arrived(l, on_arrive):
	if is_instance_valid(l):
		l.queue_free()
	if on_arrive != null and on_arrive.size() == 2 and is_instance_valid(on_arrive[0]):
		on_arrive[0].call(on_arrive[1])

# Big number pops like a slot machine payout.
func punch(control, strength = 1.18, color = Color(1.4, 1.3, 1.0)):
	if not is_instance_valid(control):
		return
	control.rect_pivot_offset = control.rect_size * Vector2(0.0, 0.5)
	var t = Tween.new()
	control.add_child(t)
	t.interpolate_property(control, "rect_scale", Vector2(strength, strength), Vector2.ONE, 0.32, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(control, "modulate", color, Color.white, 0.4)
	t.start()
	spark_burst(_local(control) - Vector2(control.rect_size.x * 0.25, 0), Color("ffd35a"), 14, 380.0, 7.0)

func shake(amount = 14.0):
	if not is_instance_valid(card):
		return
	if _shake <= 0.0:
		_shake_base = Vector2(card.margin_left, card.margin_top)
	_shake = max(_shake, amount)

# Sparks pour off the leading edge of the rank bar while it fills.
func track_bar(bar, color: Color):
	_bar = weakref(bar)
	_bar_color = color

# Rising embers around a control (the streak pill) while the card is open.
func embers_on(control, color: Color, rate = 18.0):
	embers.append({"control": weakref(control), "color": color, "rate": rate, "acc": 0.0})

# XP orbs burst out of a reward row and home into the counter; each one that
# lands calls owner.method(color) so the counter can tick and bump.
func orbs(from_control, to_control, color: Color, count, owner = null, method = ""):
	if not is_instance_valid(from_control) or not is_instance_valid(to_control):
		return
	var at = _local(from_control) + Vector2(from_control.rect_size.x * 0.3, 0)
	for i in int(count):
		var a = _rng.randf_range(-PI * 0.95, -PI * 0.05)
		parts.append({"p": at + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-10, 10)), "v": Vector2(cos(a), sin(a)) * _rng.randf_range(260, 620),
			"life": 3.0, "age": -0.025 * i, "size": _rng.randf_range(8.0, 12.0), "color": color, "kind": "orb",
			"target": weakref(to_control), "owner": owner, "method": method})

# "+500" rises off a row and fades.
func popup(control, text: String, color: Color, size = 34):
	if not is_instance_valid(control):
		return
	var l = ui.label(get_parent(), text, "h3", color)
	l.add_font_override("font", ui.font("display", size, 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at = _local(control) + Vector2(control.rect_size.x * 0.12, -34)
	l.rect_position = at
	var t = Tween.new()
	l.add_child(t)
	t.interpolate_property(l, "rect_position:y", at.y, at.y - 70, 0.8, Tween.TRANS_QUAD, Tween.EASE_OUT)
	t.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.3, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.5)
	t.interpolate_callback(l, 0.85, "queue_free")
	t.start()

# Big text slams down onto a point (multipliers, streaks), holds, then fades.
func stamp(at: Vector2, text: String, color: Color, size = 72, hold = 0.9):
	var l = ui.label(get_parent(), text, "h1", color)
	l.add_font_override("font", ui.font("display", size, 8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w = l.get_combined_minimum_size()
	l.rect_position = at - w * 0.5
	l.rect_pivot_offset = w * 0.5
	var t = Tween.new()
	l.add_child(t)
	t.interpolate_property(l, "rect_scale", Vector2(3.2, 3.2), Vector2.ONE, 0.22, Tween.TRANS_QUAD, Tween.EASE_IN)
	t.interpolate_property(l, "modulate:a", 0.0, 1.0, 0.1)
	t.interpolate_property(l, "rect_scale", Vector2(1.12, 1.12), Vector2.ONE, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT, 0.22)
	t.interpolate_property(l, "rect_position:y", l.rect_position.y, l.rect_position.y - 40, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN, 0.22 + hold)
	t.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.4, Tween.TRANS_QUAD, Tween.EASE_IN, 0.22 + hold)
	t.interpolate_callback(self, 0.22, "_stamp_hit", at, color)
	t.interpolate_callback(l, 0.7 + hold, "queue_free")
	t.start()
	return l

func _stamp_hit(at, color):
	spark_burst(at, color, 28, 640.0, 9.0)
	ring(at, color, 190.0)
	shake(9.0)

# Short full-screen tint for the biggest moments.
func flash(color: Color, strength = 0.35):
	var r = ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = Color(color.r, color.g, color.b, strength)
	r.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	get_parent().add_child(r)
	var t = Tween.new()
	r.add_child(t)
	t.interpolate_property(r, "color:a", strength, 0.0, 0.45, Tween.TRANS_QUAD, Tween.EASE_OUT)
	t.interpolate_callback(r, 0.5, "queue_free")
	t.start()

# A small scale bump without sparks, for each orb that lands.
func bump(control, strength = 1.07):
	if not is_instance_valid(control):
		return
	control.rect_pivot_offset = control.rect_size * Vector2(0.0, 0.5)
	control.rect_scale = Vector2(strength, strength)
	var t = Tween.new()
	control.add_child(t)
	t.interpolate_property(control, "rect_scale", Vector2(strength, strength), Vector2.ONE, 0.14, Tween.TRANS_QUAD, Tween.EASE_OUT)
	t.connect("tween_all_completed", t, "queue_free")
	t.start()

# Keeps the particle layer above anything added later (the crate show).
func raise():
	if get_parent() != null:
		get_parent().move_child(self, get_parent().get_child_count() - 1)

# ------------------------------------------------------------------ crate
# Anticipation shake, then the lid flies off: rays, glow, sparks, a tier stamp.
# Seconds from the start of a crate reveal until it opens: the crate starts
# Common and climbs one rarity per step (the result was fixed when it was won).
static func reveal_time(tier_name) -> float:
	return 0.5 + 0.45 * max(0, TIERS.find(str(tier_name)))

func crate(row, tier_name: String, owner, sound_method: String, big = false):
	if not is_instance_valid(row):
		return
	var tier = max(0, TIERS.find(tier_name))
	var color = TIER_COLORS[tier]
	var stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(stage)
	var center = _local(card) + Vector2(0, card.rect_size.y * 0.08)
	stage.rect_position = center
	var rays = ui.image(stage, "fx_rays", 520 + tier * 140, Color(color.r, color.g, color.b, 0.0))
	rays.rect_position = -rays.rect_min_size * 0.5
	rays.rect_pivot_offset = rays.rect_min_size * 0.5
	var glow = ui.image(stage, "fx_glow", 420 + tier * 120, Color(color.r, color.g, color.b, 0.0))
	glow.rect_position = -glow.rect_min_size * 0.5
	glow.rect_pivot_offset = glow.rect_min_size * 0.5
	var side = 210 if big else 170
	var box = ui.tile_icon(stage, "rewards", Color.white, side)
	box.rect_position = Vector2(-side, -side) * 0.5
	box.rect_pivot_offset = Vector2(side, side) * 0.5
	box.modulate = TIER_COLORS[0]
	var t = Tween.new()
	stage.add_child(t)
	# Anticipation: wobble faster and faster.
	for i in 8:
		var at = i * (0.085 - i * 0.006)
		t.interpolate_property(box, "rect_rotation", (-1 if i % 2 else 1) * (4 + i * 2.2), (1 if i % 2 else -1) * (4 + i * 2.2), 0.06, Tween.TRANS_SINE, Tween.EASE_IN_OUT, at)
	var pop = reveal_time(tier_name)
	t.interpolate_property(box, "rect_scale", Vector2.ONE, Vector2(1.25, 1.25), pop - 0.05, Tween.TRANS_QUAD, Tween.EASE_IN)
	for s in range(1, tier + 1):
		t.interpolate_callback(self, 0.5 + 0.45 * (s - 1), "_crate_step", box, center, s, owner, sound_method)
	t.interpolate_property(box, "rect_scale", Vector2(1.25, 1.25), Vector2(0.2, 0.2), 0.18, Tween.TRANS_BACK, Tween.EASE_IN, pop)
	t.interpolate_property(box, "modulate:a", 1.0, 0.0, 0.18, Tween.TRANS_LINEAR, Tween.EASE_IN, pop)
	t.interpolate_property(rays, "modulate:a", 0.0, 0.85, 0.15, Tween.TRANS_LINEAR, Tween.EASE_OUT, pop)
	t.interpolate_property(rays, "rect_scale", Vector2(0.3, 0.3), Vector2(1.0, 1.0), 0.4, Tween.TRANS_BACK, Tween.EASE_OUT, pop)
	t.interpolate_property(rays, "rect_rotation", 0.0, 140.0 + tier * 60, 1.6 + tier * 0.4, Tween.TRANS_QUAD, Tween.EASE_OUT, pop)
	t.interpolate_property(glow, "modulate:a", 0.0, 1.0, 0.1, Tween.TRANS_LINEAR, Tween.EASE_OUT, pop)
	t.interpolate_property(glow, "rect_scale", Vector2(0.4, 0.4), Vector2(1.1, 1.1), 0.35, Tween.TRANS_BACK, Tween.EASE_OUT, pop)
	var fade = pop + 1.2 + tier * 0.35
	t.interpolate_property(rays, "modulate:a", 0.85, 0.0, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN, fade)
	t.interpolate_property(glow, "modulate:a", 1.0, 0.0, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN, fade)
	t.interpolate_callback(self, pop, "_crate_open", stage, center, color, tier, owner, sound_method)
	t.interpolate_callback(stage, fade + 0.55, "queue_free")
	t.start()

func _crate_step(box, center, step, owner, sound_method):
	if not is_instance_valid(box):
		return
	var color = TIER_COLORS[step]
	var t = Tween.new()
	box.add_child(t)
	t.interpolate_property(box, "modulate", Color(2, 2, 2), color, 0.25)
	t.interpolate_property(box, "rect_rotation", 0.0, 360.0 * (1 if step % 2 else -1), 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.start()
	spark_burst(center, color, 16 + step * 6, 420.0 + step * 80, 8.0)
	ring(center, color, 120.0 + step * 30)
	shake(3.0 + step * 2.0)
	var tag = ui.label(get_parent(), TIERS[step].to_upper() + "!", "h3", color)
	tag.add_font_override("font", ui.font("display", 40, 5))
	tag.rect_position = center + Vector2(-60, -170)
	var tt = Tween.new()
	tag.add_child(tt)
	tt.interpolate_property(tag, "rect_position:y", center.y - 150, center.y - 210, 0.5, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tt.interpolate_property(tag, "modulate:a", 1.0, 0.0, 0.2, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.3)
	tt.interpolate_callback(tag, 0.55, "queue_free")
	tt.start()
	if is_instance_valid(owner):
		owner.call(sound_method, "tick", 1.15 + step * 0.18)

func _crate_open(stage, center, color, tier, owner, sound_method):
	spark_burst(center, color, 30 + tier * 25, 700.0 + tier * 160, 10.0 + tier * 2)
	spark_burst(center, Color.white, 12 + tier * 6, 420.0, 6.0)
	ring(center, color, 200 + tier * 60)
	shake(8.0 + tier * 7.0)
	if tier >= 2:
		var b = ui.burst(stage)
		if b != null:
			b.rect_position = Vector2(-300, -300)
			b.rect_size = Vector2(600, 600)
	if is_instance_valid(owner):
		owner.call(sound_method, ["claim", "claim", "rankup", "league"][tier], 1.0 + tier * 0.05)
	var stamp = ui.label(stage, TIERS[tier].to_upper(), "h2", color)
	stamp.add_font_override("font", ui.font("display", 54 + tier * 10, 6))
	stamp.rect_position = Vector2(-stamp.get_combined_minimum_size().x * 0.5, -60)
	stamp.rect_pivot_offset = Vector2(stamp.get_combined_minimum_size().x * 0.5, 30)
	stamp.rect_pivot_offset = Vector2(0, 30)
	var t = Tween.new()
	stage.add_child(t)
	t.interpolate_property(stamp, "rect_scale", Vector2(2.2, 2.2), Vector2.ONE, 0.28, Tween.TRANS_BACK, Tween.EASE_OUT)
	t.interpolate_property(stamp, "modulate:a", 0.0, 1.0, 0.12)
	t.interpolate_property(stamp, "rect_position:y", -60, -110, 1.4, Tween.TRANS_QUAD, Tween.EASE_OUT, 0.3)
	t.interpolate_property(stamp, "modulate:a", 1.0, 0.0, 0.4, Tween.TRANS_QUAD, Tween.EASE_IN, 1.3 + tier * 0.3)
	t.start()
	if tier == 3:
		for i in 6:
			get_tree().create_timer(0.12 * i).connect("timeout", self, "spark_burst", [center + Vector2(_rng.randf_range(-260, 260), _rng.randf_range(-120, 120)), Color("ffd35a"), 18, 520.0, 9.0])

# ------------------------------------------------------------------ frame
func _process(delta):
	for e in embers:
		var c = e.control.get_ref()
		if c == null or not c.is_visible_in_tree():
			continue
		e.acc += delta * e.rate
		while e.acc >= 1.0:
			e.acc -= 1.0
			var r = Rect2(c.rect_global_position - rect_global_position, c.rect_size)
			var p = Vector2(_rng.randf_range(r.position.x, r.end.x), r.position.y + r.size.y * 0.6)
			parts.append({"p": p, "v": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-170, -80)), "life": _rng.randf_range(0.7, 1.3),
				"age": 0.0, "size": _rng.randf_range(3.0, 7.0), "color": e.color, "kind": "ember"})
	var bar = _bar.get_ref() if _bar != null else null
	if bar != null and bar.is_visible_in_tree():
		var ratio = float(bar.ratio)
		if _bar_ratio >= 0.0 and abs(ratio - _bar_ratio) > 0.0005 and ratio > _bar_ratio:
			var tip = bar.rect_global_position - rect_global_position + Vector2(ratio * bar.rect_size.x, bar.rect_size.y * 0.5)
			for i in 3:
				parts.append({"p": tip, "v": Vector2(_rng.randf_range(-260, 40), _rng.randf_range(-220, 120)), "life": _rng.randf_range(0.3, 0.6),
					"age": 0.0, "size": _rng.randf_range(4.0, 8.0), "color": _bar_color, "kind": "spark"})
		_bar_ratio = ratio
	var alive = []
	var landed = []
	var trails = []
	for p in parts:
		p.age += delta
		if p.age >= p.life:
			continue
		if p.kind == "orb":
			if p.age < 0.0:
				alive.append(p)
				continue
			var target = p.target.get_ref()
			if target == null:
				continue
			var goal = _local(target) - Vector2(target.rect_size.x * 0.25, 0)
			if p.age > 0.2:
				var speed = 700.0 + p.age * 3200.0
				p.v = p.v.linear_interpolate((goal - p.p).normalized() * speed, min(1.0, delta * 9.0))
			p.p += p.v * delta
			if _rng.randf() < 0.5:
				trails.append({"p": p.p, "v": Vector2.ZERO, "life": 0.22, "age": 0.0, "size": p.size * 0.6, "color": p.color, "kind": "spark"})
			if p.p.distance_to(goal) < max(34.0, p.v.length() * delta * 1.2) or p.age > 2.2:
				landed.append(p)
				continue
			alive.append(p)
			continue
		if p.kind == "spark":
			p.v *= pow(0.06, delta)
			p.v.y += 260 * delta
		elif p.kind == "ember":
			p.v.x += sin(p.age * 9.0 + p.p.y * 0.05) * 60 * delta
		p.p += p.v * delta
		alive.append(p)
	parts = alive + trails
	for p in landed:
		spark_burst(p.p, p.color, 3, 220.0, 6.0)
		if p.owner != null and is_instance_valid(p.owner) and p.method != "":
			p.owner.call(p.method, p.color)
	if _shake > 0.0 and is_instance_valid(card):
		_shake = max(0.0, _shake - delta * 60.0)
		var o = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
		var width = card.margin_right - card.margin_left
		card.margin_left = _shake_base.x + o.x
		card.margin_right = card.margin_left + width
		card.margin_top = _shake_base.y + o.y
		card.margin_bottom = _shake_base.y + o.y
	update()

func _draw():
	for p in parts:
		if p.age < 0.0:
			continue
		var col = p.color
		if p.kind == "orb":
			draw_circle(p.p, p.size * 1.8, Color(col.r, col.g, col.b, 0.25))
			draw_circle(p.p, p.size, col)
			draw_circle(p.p, p.size * 0.45, Color(1, 1, 1, 0.85))
			continue
		var k = 1.0 - p.age / p.life
		if p.kind == "ring":
			col.a = k * 0.8
			draw_arc(p.p, p.size * (1.4 - k * 0.6), 0, TAU, 48, col, 10.0 * k + 2.0, true)
			continue
		col.a = k
		draw_circle(p.p, p.size * (0.4 + k * 0.6), col)
		var core = Color(1, 1, 1, k * 0.6)
		draw_circle(p.p, p.size * 0.35 * k, core)
