extends Reference
# Rocket Ride: a rocket lands beside the Goober, it hops on top and rides it
# like a horse through laps with climbs, dives, barrel rolls and full
# backflip loops; on the transition it does one last loop and zooms away.
const LAP = 3.4
const FLIP = 2.2
const SEGMENTS = ["lap", "backflip", "dive", "barrel", "zigzag"]

var rocket
var U = 60.0
var L = 90.0
var vel = Vector2.ZERO
var depth = 1.0
var wink_at = -1.0
var last = ""
var since_flip = 0

func setup(p):
	U = p.unit * p.GOOBER     # laid out in real Goober heights
	L = U * 2.3
	rocket = p.add_prop(p.props.Rocket.new())
	rocket.length = L
	rocket.visible = false
	rocket.setup(p.props.resource_path.get_base_dir())
	p.puppet.anim = "Idle"

func preview_units():
	return 15.5

func keep_hidden_after():
	return true

func intro_length():
	return 2.7

# Start/end point of every segment: front, bottom-centre, flying right.
func _S():
	return Vector2(0, -1.55 * U)

func _place(p, pos, angle, f, s = 1.0, roll = 0.0):
	var pup = p.puppet
	rocket.visible = true
	rocket.position = pos
	rocket.rotation = angle
	rocket.scale = Vector2(f * s, s)
	rocket.roll = roll
	rocket.phase = p.elapsed
	# On the far side during a barrel roll: rider goes behind the rocket.
	var behind = rocket.rider_behind()
	if behind != (pup.get_index() < rocket.get_index()):
		p.move_child(pup, rocket.get_index() if behind else rocket.get_index() + 1)
	# Astride the rocket's back like a saddle, a little behind the middle.
	pup.position = rocket.transform.xform(_seat_local())
	pup.rotation = angle
	pup.facing = f
	pup.scale_mul = Vector2(s, s * cos(roll))
	pup.bones_extra = RIDE.duplicate()
	pup.lean = 0.0

# Riding pose built against the real rig: leaning forward, knees forward,
# front hand down on the rocket. Offsets in skeleton units.
const RIDE = {"Body": Vector3(-12, 0, 0), "Leg-left2": Vector3(0, 29, -85), "Leg-right2": Vector3(0, 161, 52), "Arm-left": Vector3(35, 0, 0)}
func _seat_local():
	return rocket.seat() + Vector2(0, 0.2 * U) * cos(rocket.roll)

func _stand(pup):
	pup.position = Vector2.ZERO
	pup.rotation = 0.0
	pup.scale_mul = Vector2.ONE
	pup.feet = Vector2.ZERO
	pup.feet_spread = 0.0
	pup.lean = 0.0
	pup.elbow = 0.0

func intro(p, t):
	var pup = p.puppet
	var G = Vector2(1.6 * U, -0.46 * U)
	pup.facing = 1.0
	if t < 0.6:
		# Rocket drops in nose-first and levels out beside the Goober.
		var u = p.ease_out(t / 0.6)
		_place(p, G + Vector2(0.6 * U, -2.6 * U) * (1.0 - u), lerp(0.9, 0.0, u), 1.0)
		rocket.thrust = 0.9
		_stand(pup)
		pup.lean = -8.0 * u
		pup.arm_l = 50.0 * p.bump(t, 0.2, 0.6)
		pup.arm_r = pup.arm_l
		if p.at(0.0):
			p.emit_cue("rocket_arrive")
		return
	if t < 1.35:
		var land = p.bump(t, 0.6, 0.8)
		_place(p, G + Vector2(0, 0.08 * U * land), 0.0, 1.0)
		rocket.thrust = 0.25
		if t < 1.0:
			var c = p.ease_in((t - 0.6) / 0.4)
			_stand(pup)
			pup.squash = 1.0 - 0.18 * c
			pup.arm_l = -25.0 * c
			pup.arm_r = -25.0 * c
		else:
			var u = (t - 1.0) / 0.35
			pup.position = p.arc(Vector2.ZERO, rocket.transform.xform(_seat_local()), u, 0.55 * U)
			pup.squash = 1.0 + 0.12 * p.bump(u, 0.0, 0.6)
			pup.arm_l = 130.0 * p.bump(u, 0.0, 1.0)
			pup.arm_r = pup.arm_l
			pup.feet = Vector2.ZERO
			if p.at(1.0):
				p.emit_cue("hop")
		if p.at(0.6):
			p.burst(G + Vector2(0, 0.2 * L), 8, 1.0, [Color("ffffff"), Color("dddddd")])
		return
	if t < 2.0:
		# Settle and get ready: the rocket rumbles, the Goober grips and leans in.
		var u = (t - 1.35) / 0.65
		var shake = Vector2(sin(t * 70.0), cos(t * 53.0)) * 0.018 * U * u
		var sink = p.bump(t, 1.35, 1.6) * 0.08 * U
		_place(p, G + shake + Vector2(0, sink), -0.12 * p.ease_io(u), 1.0)
		rocket.thrust = 0.3 + 0.6 * u
		pup.squash = 1.0 - 0.12 * p.bump(t, 1.35, 1.6) - 0.06 * u
		pup.lean = 4.0 * u
		if p.at(1.35):
			p.emit_cue("land")
		return
	# Launch with both eyes squeezed shut: up and round into the lap start.
	var x = (t - 2.0) / 0.7
	var S = _S()
	var c1 = G + Vector2(0.9, -0.9) * U
	var c2 = S - Vector2(1.4 * U, 0)
	var u = pow(x, 1.6)
	var pos = p.bezier(G, c1, c2, S, u)
	var ahead = p.bezier(G, c1, c2, S, min(1.0, u + 0.01))
	var v = ahead - pos if u < 0.99 else Vector2(1, 0)
	var f = 1.0 if v.x >= -0.001 else -1.0
	_place(p, pos, atan2(v.y, abs(v.x)) * f, f)
	rocket.thrust = 1.0
	pup.squash = 1.0 + 0.1 * p.bump(x, 0.0, 0.6)
	pup.lean = 6.0
	if x < 0.6:
		pup.face = "wince"
	if p.at(2.0):
		p.burst(G + Vector2(-0.5 * L, 0), 14, 1.6, [Color("ffe066"), Color("ff7b1a"), Color("ffffff")])
		p.emit_cue("launch")

func next_segment(p, prev):
	var name = "lap"
	if prev != "":
		var options = []
		for s in SEGMENTS:
			if s != prev and s != last:
				options.append(s)
		# A backflip at least every third segment; it's the highlight.
		name = "backflip" if since_flip >= 2 and prev != "backflip" else p.pick(options)
	since_flip = 0 if name == "backflip" else since_flip + 1
	last = prev
	wink_at = -1.0
	# Now and then a confident wink right after a big move.
	if prev in ["backflip", "dive", "barrel"] and p.can_wink(6.0) and p.rng.randf() < 0.55:
		wink_at = p.rng.randf_range(0.15, 0.4)
		p.mark_wink()
	return [name, FLIP if name == "backflip" else LAP]

func _lap(u, kind):
	var th = TAU * u
	var A = 2.5 * U
	var B = 0.5 * U
	var C = _S() + Vector2(0, -B)
	var dy = 0.0
	if kind == "dive":
		dy = -1.0 * U * pow(sin(clamp((u - 0.18) / 0.35, 0.0, 1.0) * PI), 2) + 1.05 * U * pow(sin(clamp((u - 0.58) / 0.34, 0.0, 1.0) * PI), 2)
	elif kind == "zigzag":
		dy = 0.35 * U * sin(4.0 * th) * pow(sin(th * 0.5), 2)
	return [C + Vector2(A * sin(th), B * cos(th) + dy), cos(th)]

func segment(p, name, t, length):
	var u = t / length
	var pup = p.puppet
	if name == "backflip":
		# A full vertical loop: nose goes up and over, Goober stays on top.
		var R = 1.3 * U
		var ph = TAU * u + 0.35 * sin(TAU * u)
		vel = Vector2(cos(ph), -sin(ph)) * R * TAU / length
		depth = 1.0
		_place(p, _S() + Vector2(R * sin(ph), -R + R * cos(ph)), -ph, 1.0)
		rocket.thrust = 1.0
		pup.lean = 5.0
		pup.squash = 1.0 - 0.08 * p.bump(u, 0.0, 0.25)
		pup.arm_l = 30.0 * p.bump(u, 0.15, 0.85)
		if u > 0.2 and u < 0.7:
			pup.face = "wince"
		if p.at(0.0):
			p.emit_cue("backflip")
		_wink(p, t)
		return
	var here = _lap(u, name)
	var next = _lap(u + 0.003, name)
	vel = (next[0] - here[0]) / (0.003 * length)
	depth = here[1]
	var ref = 2.5 * U * TAU / length
	var f = clamp(vel.x / ref * 3.0, -1.0, 1.0)
	var dir = 1.0 if f >= 0.0 else -1.0
	var angle = atan2(vel.y, abs(vel.x) + 0.25 * ref) * dir
	var roll = 0.0
	if name == "barrel":
		# Barrel roll through the front of the lap.
		var w = clamp((u - 0.8) / 0.18, 0.0, 1.0)
		roll = TAU * p.ease_io(w)
		if w > 0.1 and w < 0.8:
			pup.face = "wince"
	_place(p, here[0], angle, f, 1.0, roll)
	rocket.thrust = 0.65 + 0.35 * clamp(-vel.y / ref, 0.0, 1.0)
	pup.lean += 5.0 * clamp(-vel.y / ref, -1.0, 1.0)
	if name == "dive":
		var drop = p.bump(u, 0.58, 0.92)
		pup.arm_l += 70.0 * drop
		pup.arm_r += 70.0 * drop
		if drop > 0.5:
			pup.face = "wince"
	elif name == "zigzag":
		pup.lean += 10.0 * sin(u * TAU * 4.0)
	_wink(p, t)

func _wink(p, t):
	if wink_at >= 0.0 and t >= wink_at and t < wink_at + 0.42 and p.puppet.face == "normal":
		p.puppet.face = "wink"

func snapshot(p):
	return {"pos": rocket.position, "vel": vel, "depth": depth}

func outro_length():
	return 3.4

func outro(p, t, length):
	var pup = p.puppet
	var snap = p.snap
	var S = _S()
	var p0 = snap.get("pos", S)
	var v0 = snap.get("vel", Vector2(U, 0))
	if t < 0.9:
		# Swoop back to the start point.
		var u = p.ease_io(t / 0.9)
		var c1 = p0 + v0 * 0.25
		var c2 = S - Vector2(1.1 * U, -0.3 * U)
		var pos = p.bezier(p0, c1, c2, S, u)
		var ahead = p.bezier(p0, c1, c2, S, min(1.0, u + 0.01))
		var v = ahead - pos if u < 0.99 else Vector2(1, 0)
		var f = clamp(v.x / (0.02 * U), -1.0, 1.0)
		var dir = 1.0 if f >= 0.0 else -1.0
		_place(p, pos, atan2(v.y, abs(v.x) + 0.01 * U) * dir, f)
		rocket.thrust = 0.8
	elif t < 2.3:
		# One last big loop.
		var u = (t - 0.9) / 1.4
		var R = 1.35 * U
		var ph = TAU * u + 0.35 * sin(TAU * u)
		_place(p, S + Vector2(R * sin(ph), -R + R * cos(ph)), -ph, 1.0)
		rocket.thrust = 1.0
		pup.lean = 5.0
		if u > 0.2 and u < 0.7:
			pup.face = "wince"
		if p.at(0.9):
			p.emit_cue("backflip")
	else:
		# Pull up and blast off up and out of view.
		var x = (t - 2.3) / 1.1
		var u = p.ease_in(x)
		var c1 = S + Vector2(1.2 * U, 0)
		var c2 = S + Vector2(2.4 * U, -0.9 * U)
		var end = S + Vector2(4.5 * U, -6.5 * U)
		var pos = p.bezier(S, c1, c2, end, u)
		var ahead = p.bezier(S, c1, c2, end, min(1.0, u + 0.01))
		var v = ahead - pos if u < 0.99 else Vector2(1, -1)
		_place(p, pos, atan2(v.y, abs(v.x) + 0.001), 1.0)
		rocket.thrust = 1.0
		pup.lean = 8.0
		pup.arm_r = 140.0 * p.bump(x, 0.0, 0.7)
		if x > 0.08 and x < 0.4:
			pup.face = "wink"
			if p.at(2.4):
				p.mark_wink()
		var fade = 1.0 - clamp((x - 0.8) / 0.2, 0.0, 1.0)
		rocket.modulate.a = fade
		pup.modulate.a = fade
		if p.at(2.3):
			p.emit_cue("blast_off")
			p.burst(S + Vector2(-0.5 * L, 0), 12, 1.4, [Color("ffe066"), Color("ff7b1a"), Color("ffffff")])
