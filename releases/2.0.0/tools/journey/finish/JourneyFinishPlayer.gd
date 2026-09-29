extends Node2D
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Runs one Journey finish animation (a "choreography" script) around the spot
# where the local player qualified:
#   intro -> looping segments (with variations) -> outro -> done
# The loop never ends on its own; request_outro(seconds_left) is called when
# the round starts to transition. The current segment may finish first only if
# there is time; the outro then plays, sped up to fit, and never holds the
# game back. Everything here is cosmetic and client-local.
#
# Choreography interface (a Reference script):
#   setup(player)                 create props / tiny goobers
#   intro_length() -> float
#   intro(player, t)              pose everything for intro time t
#   next_segment(player, prev) -> [name, length]
#   segment(player, name, t, length)
#   outro_length() -> float
#   outro(player, t, length)
#   keep_hidden_after() -> bool   true if the Goober leaves (portal, flying off)
#   snapshot(player) -> Dictionary  (optional) state the outro starts from
signal finished
signal cue(name)          # hook for sounds: "launch", "land", "portal_open" …

const BLEND = 0.25
const POSE_KEYS = ["position", "rotation", "arm_l", "arm_r", "elbow", "feet", "feet_spread", "lean", "squash", "scale_mul", "facing"]

var choreo
var unit = 60.0          # puppet size (the real Goober is GOOBER times taller)
const GOOBER = 3.0       # rendered Goober height / puppet size (measured in game)
var puppet               # the rider / dancer (JourneyFinishPuppet)
var props                # JourneyFinishProps script (RideStar, Rocket, StarPortal, Burst)
var rng = RandomNumberGenerator.new()
var state = "intro"
var t = 0.0
var prev_t = -0.001
var seg = ""
var seg_len = 1.0
var outro_wanted = false
var outro_len = 1.0
var outro_speed = 1.0
var elapsed = 0.0
var last_wink = -99.0
var snap = {}
var _deadline = -1.0
var _fresh = true
var _blend = []
var _bursts = []

func setup(choreography, skin, height, seed_value = 0):
	choreo = choreography
	unit = max(8.0, float(height))
	rng.seed = seed_value if seed_value != 0 else OS.get_ticks_usec()
	props = load(ModPaths.path("JourneyFinishProps.gd"))
	puppet = new_puppet(skin, unit)
	add_child(puppet)
	choreo.setup(self)

func new_puppet(skin, height):
	var p = load(ModPaths.path("JourneyFinishPuppet.gd")).new()
	p.skin = skin.duplicate(true) if skin is Dictionary else {}
	p.size = height
	return p

# The round is transitioning; `seconds` is how long until the level changes.
func request_outro(seconds = 3.0):
	if outro_wanted or state == "outro" or state == "done":
		return
	outro_wanted = true
	_deadline = elapsed + max(0.2, float(seconds))
	if state == "intro":
		_start_outro()
		_fresh = true
	elif state == "loop":
		# Finish the current segment only if the outro still fits afterwards.
		if seg_len - t + choreo.outro_length() > _deadline - elapsed:
			_start_outro()
			_fresh = true

func _start_outro():
	snap = choreo.snapshot(self) if choreo.has_method("snapshot") else {}
	_blend = []
	for p in puppets():
		var pose = {"node": p}
		for key in POSE_KEYS:
			pose[key] = p.get(key)
		_blend.append(pose)
	state = "outro"
	t = 0.0
	prev_t = -0.001
	outro_len = choreo.outro_length()
	var budget = _deadline - elapsed if _deadline > 0 else outro_len
	outro_speed = max(1.0, outro_len / max(0.3, budget))

func _process(delta):
	delta = min(delta, 0.1)
	elapsed += delta
	prev_t = -0.001 if _fresh else t
	_fresh = false
	t += delta * (outro_speed if state == "outro" else 1.0)
	for p in puppets():
		p.clear_pose()
	match state:
		"intro":
			if t >= choreo.intro_length():
				t -= choreo.intro_length()
				state = "loop"
				_next_segment("")
			else:
				choreo.intro(self, t)
		"outro":
			if t >= outro_len:
				state = "done"
				emit_signal("finished")
				return
			choreo.outro(self, t, outro_len)
			_apply_blend()
		"done":
			return
	if state == "loop":
		while t >= seg_len:
			t -= seg_len
			if outro_wanted:
				_start_outro()
				choreo.outro(self, t, outro_len)
				_step_puppets(delta)
				return
			_next_segment(seg)
		choreo.segment(self, seg, t, seg_len)
	_step_puppets(delta)

func _next_segment(prev):
	var next = choreo.next_segment(self, prev)
	seg = str(next[0])
	seg_len = max(0.2, float(next[1]))
	prev_t = -0.001

# A cut into the outro mid-move eases the puppets from where they were.
func _apply_blend():
	if t >= BLEND or _blend.empty():
		return
	var k = ease_io(t / BLEND)
	for pose in _blend:
		var p = pose.node
		if not is_instance_valid(p):
			continue
		for key in POSE_KEYS:
			var a = pose[key]
			if typeof(a) == TYPE_REAL or typeof(a) == TYPE_VECTOR2:
				p.set(key, lerp(a, p.get(key), k))

func _step_puppets(delta):
	for b in _bursts.duplicate():
		if not b.advance(delta):
			_bursts.erase(b)
			b.queue_free()
	for child in get_children():
		if child.has_method("step"):
			child.step(delta)

func puppets():
	var out = []
	for child in get_children():
		if child.has_method("clear_pose"):
			out.append(child)
	return out

# True once when the current phase time passes `time` (for bursts and cues).
func at(time):
	return prev_t < time and t >= time

func emit_cue(name):
	emit_signal("cue", name)

func keep_hidden_after() -> bool:
	return choreo.keep_hidden_after() if choreo != null else false

# Helpers for choreographies ------------------------------------------------
static func ease_out(x):
	x = clamp(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)

static func ease_in(x):
	x = clamp(x, 0.0, 1.0)
	return x * x

static func ease_io(x):
	x = clamp(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func back_out(x, amount = 1.7):
	x = clamp(x, 0.0, 1.0) - 1.0
	return 1.0 + x * x * ((amount + 1.0) * x + amount)

# 0 -> 1 -> 0 bump between a and b.
static func bump(x, a, b):
	if x <= a or x >= b:
		return 0.0
	return sin((x - a) / (b - a) * PI)

# Point on a hop from a to b (u 0..1) that peaks `height` pixels above the line.
static func arc(a, b, u, height):
	u = clamp(u, 0.0, 1.0)
	return a.linear_interpolate(b, u) + Vector2(0, -height * 4.0 * u * (1.0 - u))

static func bezier(a, b, c, d, u):
	var v = 1.0 - u
	return a * v * v * v + b * 3.0 * v * v * u + c * 3.0 * v * u * u + d * u * u * u

func pick(options):
	return options[rng.randi() % options.size()]

# Winks are short moments, never back to back.
func can_wink(cooldown = 6.0):
	return elapsed - last_wink >= cooldown

func mark_wink():
	last_wink = elapsed

func add_prop(node, behind = true):
	add_child(node)
	if behind:
		move_child(node, 0)
	return node

# A sparkle/confetti burst at `where` (local), removed when done.
func burst(where, count = 14, speed = 1.6, colors = [Color("ffe066"), Color("ffffff"), Color("7fe3ff")]):
	var b = props.Burst.new()
	b.position = where
	b.size = unit * 0.1
	b.start(count, speed * unit, colors)
	add_child(b)
	_bursts.append(b)
