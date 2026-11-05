extends Reference
# Star Ride: a star appears, the Goober hops on and they fly a figure-eight
# with depth (front/back by scale) until the round transitions; then a star
# portal opens, the Goober winks and swoops in, and the portal closes.
const LAP = 4.2
const SEGMENTS = ["cruise", "swoop", "wide", "twirl"]

var star
var portal
var U = 60.0
var vel = Vector2.ZERO
var depth = 1.0
var wink_at = -1.0
var last = ""
var seated = false
var landed_at = -1.0
var hands
var k = 0.1                         # skeleton units -> px (puppet scale)

func setup(p):
	U = p.unit * p.GOOBER     # this one is laid out in real Goober heights
	k = p.unit / 700.0        # puppet size / JourneyFinishPuppet.HEIGHT
	star = p.add_prop(p.props.RideStar.new(), false)
	star.radius = STAR_R * k
	star.scale = Vector2.ZERO
	star.setup(p.props.resource_path.get_base_dir())
	hands = p.add_prop(p.props.RideHands.new(), false)
	hands.visible = false
	portal = p.add_prop(p.props.StarPortal.new())
	portal.position = Vector2(2.2, -2.2) * U
	portal.scale = Vector2.ONE * U * 0.95 / 100.0
	p.puppet.anim = "Idle"

# How many puppet units tall a preview stage should be.
func preview_units():
	return 15.5

func keep_hidden_after():
	return true

func intro_length():
	return 2.6

# Riding like on a warp star: the Goober sits upright behind the star's top
# point (the star is drawn over it), legs round the star with the feet peeking
# out, hands clasping the point (nubs drawn over the star). Pose measured on
# the real rig offline; offsets in skeleton units.
const SEAT = Vector2(-120, -300)     # Goober root from the star centre (skeleton units, y down)
const STAR_R = 1200.0                # star radius (skeleton units)
const RIDE_POSE = {"Arm-left": Vector3(-40, 0, 0), "bone9b": Vector3(15, 0, 0), "Arm-right": Vector3(40, 0, 0), "bone12b": Vector3(-15, 0, 0), "Leg-left2": Vector3(0, 420, 230), "Leg-right2": Vector3(0, -360, 230)}

func _seat(p, at, _lean_back = 0.0):
	p.puppet.position = _seat_point(at)

func _seat_point(at):
	return at + SEAT * k

func _star_frame(p):
	star.phase = p.elapsed
	star.push_trail(star.global_position)
	star.sync()
	hands.visible = seated and p.puppet.visible
	if not seated:
		return
	var pup = p.puppet
	var fx = pup.facing if abs(pup.facing) > 0.06 else (0.06 if pup.facing >= 0.0 else -0.06)
	star.rotation = pup.rotation
	star.scale = Vector2(fx, 1.0) * pup.scale_mul
	var bob = sin(p.elapsed * TAU * 1.3) * 0.012 * U
	pup.position = star.position + (SEAT * k * star.scale).rotated(star.rotation) + Vector2(0, bob)
	var pose = RIDE_POSE.duplicate()
	var kick = sin(p.elapsed * 3.2)
	pose["Leg-left2"] = RIDE_POSE["Leg-left2"] + Vector3(0, 0, 40 * kick)
	pose["Leg-right2"] = RIDE_POSE["Leg-right2"] + Vector3(0, 0, -40 * kick)
	pup.bones_extra = pose
	# Hands let go of the star while an arm is raised.
	hands.k = k
	hands.alpha = [clamp(1.0 - abs(pup.arm_l) / 25.0, 0.0, 1.0), clamp(1.0 - abs(pup.arm_r) / 25.0, 0.0, 1.0)]
	hands.transform = pup.transform
	hands.scale = pup.scale
	hands.modulate.a = pup.modulate.a
	hands.update()

func intro(p, t):
	var pup = p.puppet
	var K = Vector2(1.75, -0.66) * U
	pup.facing = 1.0
	star.position = K + Vector2(0, sin(t * 5.0) * 0.04 * U)
	star.scale = Vector2.ONE * p.back_out(t / 0.5)
	star.glow = p.bump(t, 0.0, 0.6)
	if p.at(0.05):
		p.burst(K, 10, 1.3)
		p.emit_cue("star_appear")
	if t < 0.85:
		# Notices the star, then crouches to hop.
		pup.position = Vector2.ZERO
		pup.arm_l = 35.0 * p.bump(t, 0.0, 0.6)
		pup.lean = -6.0 * p.bump(t, 0.1, 0.6)
		if t > 0.5:
			var c = p.ease_in((t - 0.5) / 0.35)
			pup.squash = 1.0 - 0.18 * c
			pup.arm_l = -25.0 * c
			pup.arm_r = -25.0 * c
	elif t < 1.25:
		var u = (t - 0.85) / 0.4
		pup.position = p.arc(Vector2.ZERO, _seat_point(K), u, 0.7 * U)
		pup.feet = Vector2.ZERO
		pup.squash = 1.0 + 0.14 * p.bump(u, 0.0, 0.6) - 0.05 * p.bump(u, 0.6, 1.0)
		pup.arm_l = 120.0 * p.bump(u, 0.0, 1.0)
		pup.arm_r = 120.0 * p.bump(u, 0.0, 1.0)
		if p.at(0.85):
			p.emit_cue("hop")
	elif t < 1.85:
		# Lands on the star (it dips), then leans back ready to go.
		var land = p.bump(t, 1.25, 1.55)
		var prep = p.ease_io((t - 1.45) / 0.4) if t > 1.45 else 0.0
		star.position = K + Vector2(-0.14 * U * prep, (0.12 * land + 0.08 * prep) * U)
		_seat(p, star.position, 10.0 * prep)
		pup.squash = 1.0 - 0.14 * land
		if p.at(1.25):
			seated = true
			landed_at = p.elapsed
			p.emit_cue("land")
	else:
		# Launch with a squeeze of both eyes, into the start of the lap.
		var x = (t - 1.85) / 0.75
		var from = K + Vector2(-0.14 * U, 0.08 * U)
		var C = _path(0.0, "cruise")[0]
		star.position = p.bezier(from, from + Vector2(0.3, -0.6) * U, C - Vector2(0.6 * U, 0), C, pow(x, 1.5))
		_seat(p, star.position)
		pup.squash = 1.0 + 0.1 * p.bump(x, 0.0, 0.7)
		pup.arm_l = 50.0 * p.bump(x, 0.0, 0.8)
		pup.rotation = -0.25 * p.bump(x, 0.0, 1.0)
		star.rotation = pup.rotation
		star.glow = p.bump(x, 0.0, 0.6)
		if x < 0.55:
			pup.face = "wince"
		if p.at(1.9):
			p.burst(from, 12, 1.5)
			p.emit_cue("launch")
	_star_frame(p)

# Position and depth (1 front … -1 back) on the lap, u 0..1. Every lap starts
# and ends at the same point and speed, so any order joins up.
func _path(u, kind):
	var th = TAU * u
	var A = 2.2 * U
	var B = 0.45 * U
	var C = Vector2(0, -2.35 * U)
	var lift = 0.0
	if kind == "wide":
		A *= 1.18
		B *= 1.3
	elif kind == "swoop":
		lift = 1.0 * U * pow(sin(clamp((u - 0.55) / 0.4, 0.0, 1.0) * PI), 2)
	elif kind == "twirl":
		lift = -0.4 * U * pow(sin(clamp((u - 0.08) / 0.45, 0.0, 1.0) * PI), 2)
	return [C + Vector2(A * sin(th), B * sin(2.0 * th) + lift), cos(th)]

func next_segment(p, prev):
	var options = []
	for name in SEGMENTS:
		if name != prev and name != last:
			options.append(name)
	if prev == "" or options.empty():
		options = ["cruise"]
	last = prev
	var name = p.pick(options)
	wink_at = -1.0
	if name == "cruise" and p.can_wink(7.0) and p.rng.randf() < 0.45:
		wink_at = p.rng.randf_range(0.1, 0.8) * LAP
		p.mark_wink()
	return [name, LAP]

func segment(p, name, t, length):
	var u = t / length
	var here = _path(u, name)
	var ahead = _path(u + 0.004, name)
	vel = (ahead[0] - here[0]) / (0.004 * length)
	depth = here[1]
	_fly(p, here[0], vel, depth)
	var pup = p.puppet
	if name == "swoop":
		var dip = p.bump(u, 0.55, 0.95)
		pup.arm_l += 90.0 * dip
		pup.arm_r += 90.0 * dip
		if dip > 0.55 and u < 0.8:
			pup.face = "wince"
	elif name == "twirl":
		var w = clamp((u - 0.18) / 0.22, 0.0, 1.0)
		pup.rotation += TAU * p.ease_io(w) * sign(pup.facing)
		star.rotation = pup.rotation
		if w > 0.15 and w < 0.8:
			pup.face = "wince"
		pup.arm_l += 60.0 * p.bump(w, 0.0, 1.0)
	elif name == "wide":
		pup.lean += 6.0 * sin(u * TAU * 2.0)
	if wink_at >= 0.0 and t >= wink_at and t < wink_at + 0.45:
		pup.face = "wink"
	_star_frame(p)

func _fly(p, pos, v, d):
	var pup = p.puppet
	var ref = 2.2 * U * TAU / LAP
	star.position = pos
	var s = 1.0
	star.scale = Vector2.ONE * s
	# Turning is a "paper turn": the width passes through zero at the sides.
	pup.facing = clamp(v.x / ref * 2.5, -1.0, 1.0)
	_seat(p, pos)
	pup.position.y += sin(p.elapsed * TAU * 1.4) * 0.025 * U
	pup.scale_mul = Vector2.ONE * s
	var dir = 1.0 if pup.facing >= 0.0 else -1.0
	pup.rotation = atan2(v.y, abs(v.x) + 0.6 * ref) * dir * 0.7
	star.rotation = pup.rotation * 0.6

func snapshot(p):
	return {"pos": star.position, "vel": vel, "depth": depth}

func outro_length():
	return 3.4

func outro(p, t, length):
	var pup = p.puppet
	var snap = p.snap
	var p0 = snap.get("pos", star.position)
	var v0 = snap.get("vel", Vector2(U, 0))
	var H = Vector2(-0.7, -2.1) * U
	var P = portal.position
	portal.phase = p.elapsed
	if t < 2.55:
		portal.open = p.back_out(clamp((t - 0.3) / 0.7, 0.0, 1.0), 1.2)
	else:
		var c = clamp((t - 2.6) / 0.7, 0.0, 1.0)
		portal.open = (1.0 + 0.08 * p.bump(c, 0.0, 0.35)) * (1.0 - p.ease_in(c))
	portal.refresh()
	if p.at(0.3):
		p.burst(P, 14, 1.4, [Color("7fe3ff"), Color("ffffff"), Color("b58cff")])
		p.emit_cue("portal_open")
	if t < 1.1:
		# Carry on from the current flight and slow to a hover near the portal.
		var u = p.ease_out(t / 1.1)
		var c2 = H + Vector2(-0.8, -0.3) * U
		var pos = p.bezier(p0, p0 + v0 * 0.3, c2, H, u)
		var next = p.bezier(p0, p0 + v0 * 0.3, c2, H, min(1.0, u + 0.01))
		var v = (next - pos) / 0.011 if u < 0.99 else Vector2(0.4 * U, 0)
		_fly(p, pos, v, lerp(snap.get("depth", 1.0), 1.0, u))
		pup.facing = lerp(clamp(v.x / U, -1.0, 1.0), 1.0, p.ease_in(u))
		pup.rotation *= 1.0 - u
		star.rotation = pup.rotation * 0.6
	elif t < 2.05:
		# Hover: wave and wink at the camera, then pull back to build up.
		var bob = sin((t - 1.1) * TAU * 1.2) * 0.05 * U
		var pull = p.ease_io((t - 1.75) / 0.3) if t > 1.75 else 0.0
		star.position = H + Vector2(-0.25 * U * pull, bob + 0.06 * U * pull)
		star.scale = Vector2.ONE
		_seat(p, star.position, 8.0 * pull)
		pup.facing = 1.0
		pup.squash = 1.0 - 0.1 * pull
		var wave = p.bump(t, 1.12, 1.7)
		pup.arm_r += 110.0 * wave
		pup.elbow = 25.0 * sin((t - 1.1) * 18.0) * wave
		if t >= 1.2 and t < 1.62:
			pup.face = "wink"
			if p.at(1.2):
				p.mark_wink()
				p.emit_cue("wink")
	elif t < 2.55:
		# One swoop straight into the portal.
		var x = (t - 2.05) / 0.5
		var from = H + Vector2(-0.25 * U, 0.06 * U)
		var pos = p.bezier(from, from + Vector2(0.6, 0.5) * U, P + Vector2(-0.8, 0.3) * U, P, p.ease_in(x))
		var shrink = 1.0 - 0.85 * p.ease_in(clamp((x - 0.35) / 0.65, 0.0, 1.0))
		star.position = pos
		star.scale = Vector2.ONE * shrink
		_seat(p, pos)
		pup.scale_mul = Vector2.ONE * shrink
		pup.facing = 1.0
		pup.squash = 1.0 + 0.2 * p.bump(x, 0.1, 0.9)
		pup.rotation = -0.3 + 1.2 * p.ease_in(x)
		pup.arm_l = 140.0
		pup.arm_r = 140.0
		star.rotation = pup.rotation
		var fade = 1.0 - p.ease_in(clamp((x - 0.6) / 0.4, 0.0, 1.0))
		pup.modulate.a = fade
		star.modulate.a = fade
		if p.at(2.05):
			p.emit_cue("swoop")
	else:
		pup.visible = false
		star.visible = false
		if p.at(2.55):
			p.burst(P, 18, 1.8, [Color("7fe3ff"), Color("ffffff"), Color("ffe066")])
			p.emit_cue("portal_enter")
	if t < 2.55:
		_star_frame(p)
