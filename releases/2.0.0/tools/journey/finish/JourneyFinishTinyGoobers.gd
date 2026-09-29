extends Reference
# Tiny Goobers: four small Goobers run in, lift the Goober on their hands and
# keep throwing it up (normal, spin, backflip, sideways-then-corrected). They
# strain on the catch and cheer. The outro finishes with one big double flip,
# a hop down and the tinies running off.
const SPOTS = [-0.72, -0.3, 0.3, 0.72]
const THROWS = {"normal": [1.1, 2.3], "spin": [1.2, 2.5], "flip": [1.45, 3.1], "side": [1.3, 2.4]}
const TINTS = [Color("ff8a5c"), Color("7ddc6a"), Color("ffd84d"), Color("c690ff")]

var U = 60.0
var tinies = []
var strain = 0
var wink_throw = false
var last = ""

func setup(p):
	U = p.unit
	p.puppet.anim = "Idle"
	for i in range(SPOTS.size()):
		var tiny = p.new_puppet({}, U * 0.42)
		tiny.tint = TINTS[i]
		p.add_child(tiny)
		# Middle two stand behind the Goober, outer two in front.
		if i in [1, 2]:
			p.move_child(tiny, 0)
		tinies.append(tiny)

func keep_hidden_after():
	return false

func _top():
	return Vector2(0, -0.45 * U)

func _tiny_home(i):
	return Vector2(SPOTS[i] * U, -0.02 * U if i in [1, 2] else 0.0)

# Holding pose for all tinies, with a per-tiny bob so they don't move in sync.
func _hold(p, amount = 1.0, squash = 1.0):
	for i in range(tinies.size()):
		var tiny = tinies[i]
		tiny.anim = "Idle"
		tiny.position = _tiny_home(i)
		tiny.facing = 1.0 if SPOTS[i] < 0 else -1.0
		tiny.arm_l = 165.0 * amount
		tiny.arm_r = 165.0 * amount
		tiny.squash = squash + 0.03 * sin(p.elapsed * 7.0 + i * 1.7)

func intro_length():
	return 2.4

func intro(p, t):
	var pup = p.puppet
	pup.facing = 1.0
	for i in range(tinies.size()):
		var tiny = tinies[i]
		var home = _tiny_home(i)
		var side = -1.0 if SPOTS[i] < 0 else 1.0
		var delay = 0.08 * i
		var u = clamp((t - delay) / 0.95, 0.0, 1.0)
		tiny.facing = -side
		if u < 1.0:
			tiny.anim = "Run"
			tiny.position = (home + Vector2(side * 3.4 * U, 0)).linear_interpolate(home, p.ease_out(u))
			tiny.position.y -= abs(sin(t * 14.0 + i)) * 0.06 * U
		else:
			tiny.anim = "Idle"
			tiny.position = home
			tiny.squash = 1.0 - 0.15 * p.bump(t, delay + 0.95, delay + 1.2)
			var lift = p.ease_io((t - 1.3) / 0.25) if t > 1.3 else 0.0
			tiny.arm_l = 165.0 * lift
			tiny.arm_r = 165.0 * lift
	if p.at(0.0):
		p.emit_cue("tinies_run")
	if t < 1.3:
		pup.lean = -6.0 * p.bump(t, 0.2, 1.2)
		pup.arm_l = 30.0 * p.bump(t, 0.4, 1.2)
	elif t < 1.55:
		pup.squash = 1.0 - 0.16 * p.ease_in((t - 1.3) / 0.25)
		pup.arm_l = -20.0
		pup.arm_r = -20.0
	elif t < 1.95:
		var u = (t - 1.55) / 0.4
		pup.position = p.arc(Vector2.ZERO, _top(), u, 0.45 * U)
		pup.squash = 1.0 + 0.12 * p.bump(u, 0.0, 0.5)
		pup.arm_l = 120.0 * p.bump(u, 0.0, 1.0)
		pup.arm_r = pup.arm_l
		if p.at(1.55):
			p.emit_cue("hop")
	else:
		var land = p.bump(t, 1.95, 2.2)
		pup.position = _top()
		pup.squash = 1.0 - 0.15 * land
		_hold(p, 1.0, 1.0 - 0.2 * land)
		if p.at(1.95):
			p.emit_cue("catch")

func next_segment(p, prev):
	var options = []
	for name in THROWS:
		if name != prev and name != last:
			options.append(name)
	var name = "normal" if prev == "" else p.pick(options)
	last = prev
	strain = p.rng.randi() % tinies.size()
	wink_throw = name == "normal" and p.can_wink(7.0) and p.rng.randf() < 0.5
	if wink_throw:
		p.mark_wink()
	return [name, 0.6 + THROWS[name][0] + 0.75]

func segment(p, name, t, length):
	_throw(p, name, t, THROWS[name][0], THROWS[name][1], wink_throw)

# One throw from the tinies' hands and back; `air` seconds up, apex `H` units.
func _throw(p, name, t, air, H, wink = false, launch_at = 0.45):
	var pup = p.puppet
	var top = _top()
	var fly = launch_at + 0.15
	pup.facing = 1.0
	if t < launch_at:
		# Crouch together.
		var c = p.ease_in(t / launch_at)
		pup.position = top + Vector2(0, 0.08 * U * c)
		pup.squash = 1.0 - 0.16 * c
		pup.arm_l = -20.0 * c
		pup.arm_r = pup.arm_l
		_hold(p, 1.0 - 0.15 * c, 1.0 - 0.2 * c)
	elif t < fly:
		# Launch: tinies stretch up, the Goober shoots off with both eyes shut.
		var u = (t - launch_at) / 0.15
		pup.position = top + Vector2(0, 0.08 * U * (1.0 - u) - 0.25 * U * u)
		pup.squash = 1.0 + 0.2 * u
		pup.face = "wince"
		_hold(p, 1.08, 1.0 + 0.16 * p.bump(u, 0.0, 2.0))
		for i in range(tinies.size()):
			if i == strain:
				tinies[i].face = "wince"
		if p.at(launch_at):
			p.emit_cue("throw")
	elif t < fly + air:
		var s = (t - fly) / air
		pup.position = top + Vector2(0, -0.25 * U * (1.0 - s) - H * U * 4.0 * s * (1.0 - s))
		pup.squash = 1.0 + 0.12 * p.bump(s, 0.0, 0.25) + 0.08 * p.bump(s, 0.8, 1.0)
		var apex = p.bump(s, 0.2, 0.8)
		if s < 0.3:
			pup.face = "wince"
		match name:
			"normal":
				pup.arm_l = 150.0 * apex
				pup.arm_r = pup.arm_l
				pup.feet_spread = 0.1 * apex
				if wink and s > 0.42 and s < 0.62:
					pup.face = "wink"
			"spin":
				pup.facing = cos(TAU * 2.0 * p.ease_io(s))
				pup.arm_l = 90.0 * apex
				pup.arm_r = pup.arm_l
			"flip":
				pup.rotation = -TAU * p.ease_io(clamp((s - 0.15) / 0.7, 0.0, 1.0))
				pup.feet = Vector2(0, 0.2 * p.bump(s, 0.2, 0.8))
				pup.arm_l = 60.0 * apex
				pup.arm_r = pup.arm_l
			"double":
				pup.rotation = -TAU * 2.0 * p.ease_io(clamp((s - 0.12) / 0.72, 0.0, 1.0))
				pup.feet = Vector2(0, 0.22 * p.bump(s, 0.15, 0.85))
				pup.arm_l = 150.0 * p.bump(s, 0.8, 1.0) + 50.0 * apex
				pup.arm_r = pup.arm_l
				if s > 0.3 and s < 0.6:
					pup.face = "wince"
			"side":
				# Tips over sideways, then rights itself before the catch.
				var tip = p.ease_out(clamp(s / 0.4, 0.0, 1.0))
				var fix = p.back_out(clamp((s - 0.55) / 0.3, 0.0, 1.0), 2.2)
				pup.rotation = 1.35 * tip * (1.0 - fix)
				pup.position.x = 0.35 * U * sin(PI * s)
				pup.arm_l = 110.0 * tip * (1.0 - fix)
				pup.feet_spread = 0.08 * tip * (1.0 - fix)
		# Tinies lower their arms a little and watch it go up.
		for i in range(tinies.size()):
			var tiny = tinies[i]
			tiny.anim = "Idle"
			tiny.position = _tiny_home(i)
			tiny.facing = 1.0 if pup.position.x > tiny.position.x else -1.0
			var ready = p.ease_io(clamp((s - 0.7) / 0.3, 0.0, 1.0))
			tiny.arm_l = lerp(60.0 + 40.0 * apex, 165.0, ready)
			tiny.arm_r = tiny.arm_l
			tiny.lean = -6.0 * apex * tiny.facing
			tiny.position.y -= 0.05 * U * p.bump(s, 0.3, 0.6) * float(i % 2)
	else:
		# Catch: small squash, tinies strain (one squeezes its eyes), then cheer.
		var k = t - fly - air
		var caught = p.bump(k, 0.0, 0.3)
		pup.position = top + Vector2(0, 0.07 * U * caught)
		pup.squash = 1.0 - 0.2 * caught
		pup.arm_l = 60.0 * caught
		pup.arm_r = pup.arm_l
		var cheer = p.bump(k, 0.25, 0.75)
		_hold(p, 1.0 - 0.1 * caught, 1.0 - 0.28 * caught)
		for i in range(tinies.size()):
			var tiny = tinies[i]
			tiny.lean = 8.0 * caught * (1.0 if i % 2 == 0 else -1.0)
			if i == strain and caught > 0.3:
				tiny.face = "wince"
			# Outer tinies let go with one hand and cheer.
			if i in [0, 3]:
				tiny.arm_r = 165.0 + 10.0 * sin(k * 30.0) * cheer
				tiny.position.y -= 0.06 * U * cheer
		if p.at(fly + air):
			p.emit_cue("catch")

func outro_length():
	return 4.5

func outro(p, t, length):
	var pup = p.puppet
	if t < 2.55:
		# One last big double flip.
		_throw(p, "double", t, 1.65, 3.7, false, 0.5)
		if p.at(0.5):
			p.burst(Vector2(0, -0.4 * U), 12, 1.3, [Color("ffffff"), Color("ffe066")])
		return
	if t < 2.95:
		# Hop down in front of the tinies.
		var u = (t - 2.55) / 0.4
		pup.position = p.arc(_top(), Vector2.ZERO, u, 0.4 * U)
		pup.squash = 1.0 + 0.1 * p.bump(u, 0.0, 0.5)
		pup.arm_l = 120.0 * p.bump(u, 0.0, 1.0)
		pup.arm_r = pup.arm_l
		_hold(p, 1.0 - p.ease_io(u), 1.0)
		if p.at(2.55):
			p.emit_cue("hop")
		return
	var k = t - 2.95
	pup.squash = 1.0 - 0.16 * p.bump(k, 0.0, 0.25)
	pup.facing = 1.0
	var wave = p.bump(k, 0.6, 1.4)
	pup.arm_r = 140.0 * wave
	pup.elbow = 25.0 * sin(k * 18.0) * wave
	if p.at(2.95):
		p.emit_cue("land")
		p.burst(Vector2(0, -0.8 * U), 18, 1.6, [Color("ff8a5c"), Color("7ddc6a"), Color("ffd84d"), Color("c690ff"), Color("ffffff")])
	for i in range(tinies.size()):
		var tiny = tinies[i]
		var home = _tiny_home(i)
		var side = -1.0 if SPOTS[i] < 0 else 1.0
		if k < 0.6:
			# Cheer: little jump with both arms up.
			tiny.anim = "Idle"
			tiny.facing = -side
			tiny.position = p.arc(home, home, clamp((k - 0.05 * i) / 0.45, 0.0, 1.0), 0.18 * U)
			tiny.arm_l = 160.0
			tiny.arm_r = 160.0
		else:
			# Run off to the sides and fade out.
			var u = clamp((k - 0.6 - 0.06 * i) / 0.85, 0.0, 1.0)
			tiny.anim = "Run"
			tiny.facing = side
			tiny.position = home + Vector2(side * 3.4 * U * p.ease_in(u), -abs(sin(t * 14.0 + i)) * 0.05 * U)
			tiny.modulate.a = 1.0 - clamp((u - 0.6) / 0.4, 0.0, 1.0)
