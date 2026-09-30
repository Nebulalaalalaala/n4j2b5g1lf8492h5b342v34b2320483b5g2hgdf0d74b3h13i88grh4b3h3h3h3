extends Reference
# Dance: a groove the Goober keeps coming back to, mixed with bigger moves
# (A -> B -> A -> C …). Each move starts and ends near the neutral pose so any
# order flows. Ends in a finishing pose with a wink.
const BEAT = 0.48
const MOVES = ["floss", "spinhop", "shimmy", "wave", "starjump"]
const BEATS = {"floss": 8, "spinhop": 4, "shimmy": 6, "wave": 4, "starjump": 4, "own": 8}

var U = 60.0
var last_move = ""
var wink_at = -1.0
var own = []

func setup(p):
	U = p.unit
	p.puppet.anim = "Idle"
	own = p.puppet.dances()

func keep_hidden_after():
	return false

func intro_length():
	return 1.0

func intro(p, t):
	var pup = p.puppet
	pup.facing = 1.0
	if t < 0.25:
		pup.squash = 1.0 - 0.16 * p.ease_in(t / 0.25)
		pup.arm_l = -20.0 * t / 0.25
		pup.arm_r = pup.arm_l
	elif t < 0.62:
		var u = (t - 0.25) / 0.37
		pup.position = p.arc(Vector2.ZERO, Vector2.ZERO, u, 0.38 * U)
		pup.squash = 1.0 + 0.12 * p.bump(u, 0.0, 0.5)
		pup.arm_l = 150.0 * p.bump(u, 0.0, 1.2)
		pup.arm_r = pup.arm_l
		pup.feet_spread = 0.06 * p.bump(u, 0.0, 1.0)
		if p.at(0.25):
			p.emit_cue("hop")
	else:
		var u = (t - 0.62) / 0.38
		pup.squash = 1.0 - 0.14 * p.bump(u, 0.0, 0.6)
		pup.arm_l = 60.0 * (1.0 - u)
		pup.arm_r = pup.arm_l
		if p.at(0.62):
			p.emit_cue("land")

func next_segment(p, prev):
	wink_at = -1.0
	if prev != "groove":
		# Back to the groove; sometimes a wink on an off-beat.
		if prev != "" and p.can_wink(7.0) and p.rng.randf() < 0.45:
			wink_at = (p.rng.randi_range(1, 5) + 0.5) * BEAT
			p.mark_wink()
		return ["groove", BEAT * (6 if prev == "" else 4)]
	var options = []
	for move in MOVES:
		if move != last_move:
			options.append(move)
	if not own.empty() and last_move != "own":
		options.append("own")
	var move = p.pick(options)
	last_move = move
	return [move, BEAT * BEATS[move]]

# 0 at the ends of a move, 1 in the middle (so moves chain cleanly).
func _env(t, length, edge = 0.2):
	return min(1.0, min(t, length - t) / edge)

func segment(p, name, t, length):
	var pup = p.puppet
	pup.facing = 1.0
	pup.position = Vector2.ZERO
	var beat = t / BEAT
	var b = fmod(beat, 1.0)
	var env = _env(t, length)
	match name:
		"groove":
			var side = 1.0 if int(beat) % 2 == 0 else -1.0
			var up = max(0.0, sin(beat * PI))
			pup.squash = 1.0 - 0.1 * pow(1.0 - b, 3) * env
			pup.position.y = -0.05 * U * sin(b * PI) * env
			pup.lean = 7.0 * sin(beat * PI) * env
			pup.arm_l = (30.0 + 90.0 * up) * env if side > 0 else 30.0 * env
			pup.arm_r = (30.0 + 90.0 * up) * env if side < 0 else 30.0 * env
			pup.elbow = 20.0 * env
		"floss":
			pup.anim = "floss" if t < length - 0.12 else "Idle"
		"own":
			pup.anim = own[int(p.elapsed / 30.0) % own.size()] if t < length - 0.12 else "Idle"
		"spinhop":
			if beat < 1.0:
				pup.squash = 1.0 - 0.18 * p.ease_in(b)
				pup.arm_l = -20.0 * b
				pup.arm_r = pup.arm_l
			elif beat < 2.6:
				var u = (beat - 1.0) / 1.6
				pup.position = p.arc(Vector2.ZERO, Vector2.ZERO, u, 0.65 * U)
				pup.facing = cos(TAU * p.ease_io(u))
				pup.squash = 1.0 + 0.14 * p.bump(u, 0.0, 0.4)
				pup.arm_l = 150.0 * p.bump(u, 0.0, 1.0)
				pup.arm_r = pup.arm_l
				pup.feet = Vector2(0, 0.1 * p.bump(u, 0.2, 0.9))
				if u < 0.3:
					pup.face = "wince"
				if p.at(BEAT):
					p.emit_cue("jump")
			else:
				var u = (beat - 2.6) / 1.4
				pup.squash = 1.0 - 0.18 * p.bump(u, 0.0, 0.45)
				pup.arm_l = 90.0 * (1.0 - p.ease_io(u))
				pup.arm_r = pup.arm_l
				pup.feet_spread = 0.05 * (1.0 - u)
				if p.at(2.6 * BEAT):
					p.emit_cue("land")
		"shimmy":
			pup.feet_spread = 0.07 * env
			pup.squash = 1.0 - 0.05 * env
			pup.lean = 13.0 * sin(TAU * beat) * env
			pup.position.x = 0.1 * U * sin(PI * beat * 0.5) * env
			pup.arm_l = 80.0 * env
			pup.arm_r = 80.0 * env
			pup.elbow = 30.0 * sin(TAU * beat * 2.0) * env
		"wave":
			pup.arm_l = 155.0 * env
			pup.arm_r = 155.0 * env
			pup.lean = 12.0 * sin(PI * beat) * env
			pup.elbow = 25.0 * sin(PI * beat + 0.8) * env
			pup.squash = 1.0 - 0.06 * pow(1.0 - b, 2) * env
		"starjump":
			var k = fmod(beat, 2.0) / 2.0
			var second = beat >= 2.0
			if k < 0.3:
				pup.squash = 1.0 - 0.15 * p.bump(k, 0.0, 0.6)
				pup.arm_l = -15.0 * p.bump(k, 0.0, 0.6)
				pup.arm_r = pup.arm_l
			elif k < 0.85:
				var u = (k - 0.3) / 0.55
				var x = p.bump(u, 0.0, 1.0)
				pup.position = p.arc(Vector2.ZERO, Vector2.ZERO, u, (0.6 if second else 0.45) * U)
				pup.arm_l = 150.0 * x
				pup.arm_r = pup.arm_l
				pup.feet_spread = 0.14 * x
				pup.squash = 1.0 + 0.1 * p.bump(u, 0.0, 0.35)
				if second and u > 0.3 and u < 0.62:
					pup.face = "wince"
			else:
				pup.squash = 1.0 - 0.14 * p.bump(k, 0.85, 1.0)
			if p.at(0.6 * BEAT) or p.at(2.6 * BEAT):
				p.emit_cue("jump")
	if wink_at >= 0.0 and t >= wink_at and t < wink_at + 0.45 and pup.face == "normal":
		pup.face = "wink"

func outro_length():
	return 1.9

func outro(p, t, length):
	var pup = p.puppet
	pup.facing = 1.0
	pup.anim = "Idle"
	if t < 0.3:
		pup.squash = 1.0 - 0.16 * p.ease_in(t / 0.3)
		pup.arm_l = -20.0 * t / 0.3
		pup.arm_r = pup.arm_l
	elif t < 0.72:
		# Spinning hop into the pose.
		var u = (t - 0.3) / 0.42
		pup.position = p.arc(Vector2.ZERO, Vector2.ZERO, u, 0.5 * U)
		pup.facing = cos(TAU * p.ease_io(u))
		pup.squash = 1.0 + 0.12 * p.bump(u, 0.0, 0.4)
		pup.arm_l = 140.0 * p.bump(u, 0.0, 1.0)
		pup.arm_r = pup.arm_l
		if p.at(0.3):
			p.emit_cue("jump")
	else:
		# Finishing pose: one arm up high, a little lean, a wink; then relax so
		# the normal Goober takes over without a jump.
		var hold = 1.0 - p.ease_io(clamp((t - 1.55) / 0.35, 0.0, 1.0))
		var into = p.back_out(clamp((t - 0.72) / 0.2, 0.0, 1.0))
		pup.squash = 1.0 - 0.15 * p.bump(t, 0.72, 0.9)
		pup.arm_r = 160.0 * into * hold
		pup.arm_l = -15.0 * into * hold
		pup.elbow = 15.0 * into * hold
		pup.lean = -9.0 * into * hold
		pup.feet_spread = 0.06 * into * hold
		if t >= 0.95 and t < 1.4:
			pup.face = "wink"
			if p.at(0.95):
				p.mark_wink()
				p.emit_cue("wink")
		if p.at(0.72):
			p.emit_cue("pose")
			p.burst(Vector2(0, -0.6 * U), 10, 1.2)
