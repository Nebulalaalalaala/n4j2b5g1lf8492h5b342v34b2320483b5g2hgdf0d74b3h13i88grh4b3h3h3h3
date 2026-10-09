extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")
# UFO: hover / flicker / drop-and-catch loops until the round transitions.
# Everything is confined to JourneyFinishPlayer's cosmetic Goober and props.
const SEGMENTS = ["hover","flicker","drop_catch","double_catch","sway"]
var U = 180.0
var saucer
var beam
var prop_script
var bag = []
var power = 0.0

func setup(p):
	U = p.unit * p.GOOBER
	prop_script = load(ModPaths.path("JourneyFinishUFOProps.gd"))
	beam = p.add_prop(prop_script.Beam.new())
	beam.height = U
	saucer = p.add_prop(prop_script.Saucer.new())
	saucer.height = U
	saucer.setup()
	if saucer.front != null:
		p.add_prop(saucer.front,false)
	saucer.visible = false
	if saucer.front != null: saucer.front.visible = false
	p.puppet.anim = "Idle"

func preview_units(): return 14.5
func keep_hidden_after(): return true
func intro_length(): return 2.6
func outro_length(): return 2.6
func _rest(): return Vector2(0,-1.2)*U
func _ship(p): return Vector2(sin(p.elapsed*1.15)*.055,-3.24+sin(p.elapsed*1.65)*.035)*U
func _bob(p): return Vector2(sin(p.elapsed*1.7)*.045,sin(p.elapsed*2.1)*.04)*U

func _props(p, ship, tilt, strength):
	power = clamp(strength,0.0,1.0)
	saucer.visible = true
	saucer.position = ship
	saucer.rotation = tilt
	saucer.sync_front()
	if saucer.front != null: saucer.front.visible = true
	beam.aim(ship,Vector2(0,-.04)*U,power,p.elapsed)

func _float(p, at, reaction = 0.0):
	var pup = p.puppet
	pup.position = at
	pup.facing = 1.0
	pup.arm_l = 23.0 + reaction*45.0 + sin(p.elapsed*2.1)*3.0
	pup.arm_r = 30.0 + reaction*48.0 + sin(p.elapsed*2.1+.7)*3.0
	pup.elbow = 8.0
	pup.feet = Vector2(sin(p.elapsed*2.3)*.012,.035)
	pup.feet_spread = .025
	pup.rotation = sin(p.elapsed*1.7)*.035
	if reaction > .5: pup.face = "wince"

func intro(p, t):
	var arrival = p.ease_out(t/.85)
	var target = _ship(p)
	_props(p,target+Vector2(2.7,-1.1)*U*(1.0-arrival),-.18*(1.0-arrival),p.ease_io((t-.65)/.55))
	if t < 1.0:
		p.puppet.position = Vector2.ZERO
		p.puppet.lean = -5.0*p.bump(t,.25,.95)
		p.puppet.arm_l = 26.0*p.bump(t,.35,.95)
	else:
		var lift = p.ease_io((t-1.0)/1.6)
		_float(p,(_rest()+_bob(p))*lift)
		p.puppet.arm_l *= lift
		p.puppet.arm_r *= lift
	if p.at(.7): p.emit_cue("tractor_on")

func next_segment(p, prev):
	if prev == "": return ["hover",3.6]
	if bag.empty(): bag = SEGMENTS.duplicate()
	var options = bag.duplicate()
	if options.size()>1: options.erase(prev)
	var chosen = p.pick(options)
	bag.erase(chosen)
	return [chosen,4.0 if chosen in ["double_catch","sway"] else 3.6]

func segment(p, name, t, length):
	var u = clamp(t/length,0.0,1.0)
	var at = _rest()+_bob(p)
	var strength = 1.0
	var reaction = 0.0
	match name:
		"flicker":
			# Three brief brownouts, not a rapid full-screen strobe.
			for bounds in [[.18,.30],[.40,.53],[.62,.75]]:
				var dip = pow(p.bump(u,bounds[0],bounds[1]),2)
				strength -= .82*dip
				at.y += .17*U*dip
				reaction = max(reaction,.65*dip)
		"drop_catch":
			var fall = p.ease_in((u-.18)/.24) if u<.42 else 1.0-p.ease_out((u-.42)/.32)
			fall = clamp(fall,0.0,1.0)
			at.y += .97*U*fall
			at.x += .08*U*p.bump(u,.18,.74)
			strength = 1.0-.92*p.ease_io((u-.14)/.06) if u<.37 else .08+.92*p.ease_io((u-.37)/.10)
			reaction = fall
			if p.at(length*.40): p.emit_cue("tractor_catch")
		"double_catch":
			for interval in [[.15,.32,.49],[.53,.68,.87]]:
				var fall = 0.0
				if u>=interval[0] and u<interval[1]: fall=p.ease_in((u-interval[0])/(interval[1]-interval[0]))
				elif u>=interval[1] and u<interval[2]: fall=1.0-p.ease_out((u-interval[1])/(interval[2]-interval[1]))
				at.y += .62*U*fall
				reaction = max(reaction,fall)
				strength -= .84*pow(p.bump(u,interval[0],interval[1]+.045),2)
		"sway":
			var sweep = sin(u*TAU)*pow(sin(u*PI),2)
			at.x += .34*U*sweep
			at.y -= .10*U*pow(sin(u*PI),2)
	_props(p,_ship(p),sin(p.elapsed*1.15)*.025,strength)
	_float(p,at,reaction)
	if name=="sway": p.puppet.rotation += .12*sin(u*TAU)*pow(sin(u*PI),2)

func snapshot(p):
	return {"goober":p.puppet.position,"ship":saucer.position,"tilt":saucer.rotation,"power":power}

func outro(p, t, _length):
	var start = p.snap.get("ship",_ship(p))
	var at = p.snap.get("goober",p.puppet.position)
	var pup = p.puppet
	if t<1.35:
		var pull = p.ease_io(t/1.35)
		var hatch = start+Vector2(0,.23)*U
		_props(p,start,lerp(p.snap.get("tilt",0.0),0.0,p.ease_io(t/.25)),lerp(p.snap.get("power",1.0),1.0,p.ease_out(t/.18)))
		_float(p,at.linear_interpolate(hatch,pull))
		pup.rotation *= 1.0-p.ease_io(t/.25)
		pup.arm_l = 34.0
		pup.arm_r = 34.0
		# Upper body disappears behind the hatch plane, not by scaling the rig.
		prop_script.hatch_clip(pup,hatch.y,U,true)
		if p.at(.12): p.emit_cue("tractor_pull")
	else:
		pup.visible = false
		var leave = clamp((t-1.35)/1.25,0.0,1.0)
		var retract = 1.0-p.ease_io(leave/.24)
		var ship = start+Vector2(6.2,-4.5)*U*p.ease_in(leave)
		_props(p,ship,-.12*p.ease_io(leave/.45),retract)
		saucer.modulate.a = 1.0-p.ease_io((leave-.75)/.25)
		saucer.sync_front()
		if p.at(1.35): p.emit_cue("ufo_depart")
