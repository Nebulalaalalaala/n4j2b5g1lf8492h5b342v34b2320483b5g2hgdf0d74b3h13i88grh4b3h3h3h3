extends Reference

# Conservative local observation, not a server kill statistic. A claim requires
# a new native stun AND matching knockback (or the full native dash-specific
# stun signature) in the dash's configured range, from exactly one attacker.
# GooberDash applies its dash push before Box2D's
# contact step, so ordinary body_entered contacts miss real dash hits.
# Recovery, another hit, respawn, leaving the round, or ambiguity cancels it.
var previous = {}
var claims = {}
var contact_history = {}
var scored = {}
var linked_pushes = 0

static func impact_pairs(players: Array,before: Dictionary,distance: float,impulse: float,dash_stun_ticks := 0.0,contact_stun_ticks := 0.0) -> Array:
	var pairs = []
	for victim in players:
		var old_victim = before.get(victim.id,{})
		if old_victim.empty() or not old_victim.alive or float(victim.stun)<=float(old_victim.stun)+0.5: continue
		if contact_stun_ticks>0 and float(victim.stun)<=contact_stun_ticks+0.5: continue
		var change = victim.velocity-old_victim.velocity
		# A spike/wall can consume the push in the very same physics step.
		# Death alone is not evidence: require a NEW full native DASH stun
		# (spring/contact stun has a different native duration) and the same
		# unique attacker/range/direction checks as an observed impulse.
		# Remote victims don't predict their own deaths; they can remain alive
		# against a spike until the authoritative elimination arrives. Retain
		# that hit claim too, but don't score it until actual death/elimination.
		var native_dash_stun = dash_stun_ticks>1.0 and abs(float(victim.stun)-dash_stun_ticks)<=0.5
		for attacker in players:
			if attacker.id==victim.id: continue
			var old_attacker = before.get(attacker.id,{})
			if not attacker.alive and not (old_attacker.get("alive",false) and old_attacker.get("dashing",false)): continue
			if old_attacker.empty() or (not attacker.dashing and not old_attacker.dashing): continue
			var relative = old_victim.position-old_attacker.position
			# Use the native dash radius, not an arbitrary nearby-death radius.
			if relative.length()>distance+1.0 or relative.length_squared()<0.001: continue
			var direction = (attacker.direction if attacker.dashing else old_attacker.direction).normalized()
			if direction.dot(relative.normalized())<0.2: continue
			if change.dot(relative.normalized())<max(100.0,impulse*0.2) and not native_dash_stun: continue
			pairs.append([attacker.id,victim.id])
	return pairs

func reset() -> void:
	previous.clear()
	claims.clear()
	contact_history.clear()
	scored.clear()
	linked_pushes = 0

func confirm_elimination(victim: int,now: float,local_id: int) -> bool:
	if scored.has(victim) or not claims.has(victim): return false
	var claim = claims[victim]
	claims.erase(victim)
	scored[victim] = true
	return victim!=local_id and claim.attacker==local_id and now-float(claim.at)<=6.0

func observe(players: Array, pairs: Array, now: float, local_id: int,contact_stun_ticks := 0.0,spring_distance := 0.0,minimum_transfer := 100.0) -> Array:
	var current = {}
	var kills = []
	for p in players: current[p.id] = p
	for pair in pairs:
		if pair.size() == 2: contact_history[_pair(pair[0],pair[1])] = now
	for key in contact_history.keys():
		if now-float(contact_history[key]) > 0.10: contact_history.erase(key)
	for p in players:
		var old = previous.get(p.id,{})
		if old.empty(): continue
		if p.alive and not old.alive:
			claims.erase(p.id)
			scored.erase(p.id)
		if old.alive and float(p.stun)>float(old.stun)+0.5:
			var passive_contact = contact_stun_ticks>0 and float(p.stun)<=contact_stun_ticks+0.5
			var candidates = []
			for attacker in players:
				if attacker.id==p.id: continue
				var before = previous.get(attacker.id,{})
				if not attacker.alive and not (before.get("alive",false) and before.get("dashing",false)): continue
				if not attacker.dashing and not before.get("dashing",false): continue
				if contact_history.has(_pair(attacker.id,p.id)): candidates.append(attacker.id)
			# Native one-tick player spring/contact stun is often part of the
			# knockback into the hazard. It is neither another dash nor proof
			# of regaining control; don't erase an already-evidenced dash for it.
			if not passive_contact or candidates.size()>1: claims.erase(p.id)
			if not passive_contact and candidates.size()==1:
				var attacker = current[candidates[0]]
				var prior_attacker = previous.get(attacker.id,{})
				claims[p.id] = {"attacker":attacker.id,"at":now,"ground_since":-1.0,"direction":attacker.direction if attacker.dashing else prior_attacker.get("direction",Vector2.ZERO),"path":[attacker.id,p.id],"depth":0}
		if claims.has(p.id):
			var claim = claims[p.id]
			var expired = now-float(claim.at)>6.0
			if p.alive and float(p.stun)<=0.0:
				if p.get("jumping",false) or p.dashing: expired = true
				if p.get("grounded",false):
					if claim.ground_since<0: claim.ground_since = now
					if now-float(claim.ground_since)>0.2: expired = true
				else: claim.ground_since = -1.0
			if expired: claims.erase(p.id)
	# Establish all direct hits before following a transfer. In a packed group,
	# the outer player can be visited before the directly dashed player.
	if contact_stun_ticks>0 and spring_distance>0:
		_link_pushes(players,current,now,contact_stun_ticks,spring_distance,minimum_transfer)
	for p in players:
		var old = previous.get(p.id,{})
		if old.empty(): continue
		if old.alive and not p.alive and not scored.has(p.id):
			scored[p.id] = true
			if claims.has(p.id) and claims[p.id].attacker==local_id and p.id!=local_id:
				kills.append({"victim":p.id,"at":now})
			claims.erase(p.id)
	for id in claims.keys():
		if not current.has(id): claims.erase(id)
	previous = current.duplicate(true)
	return kills


# A native player spring/contact can transmit already-proven dash momentum
# into another player. Require the native contact stun, swept spring range,
# forward transferred impulse, and one ultimate attacker. Nearby deaths alone
# never establish a link. Links retain the original expiry and cannot cycle.
func _link_pushes(players: Array,current: Dictionary,now: float,contact_stun: float,distance: float,minimum: float) -> void:
	for _pass in players.size():
		var additions = {}
		for target in players:
			if claims.has(target.id) or scored.has(target.id): continue
			var old_target = previous.get(target.id,{})
			if old_target.empty() or not old_target.alive: continue
			if target.stun<=0 or target.stun>contact_stun+0.5: continue
			var change = target.velocity-old_target.velocity
			if change.length()<minimum: continue
			var origins = {}
			for source_id in claims.keys():
				if source_id==target.id or not current.has(source_id): continue
				var source = current[source_id]
				var old_source = previous.get(source_id,{})
				var claim = claims[source_id]
				var path = claim.get("path",[])
				if old_source.empty() or not old_source.alive or path.empty() or target.id in path or now-float(claim.at)>6.0: continue
				var direction = claim.get("direction",Vector2.ZERO).normalized()
				if direction==Vector2.ZERO: continue
				var incoming = source.velocity if source.velocity.dot(direction)>=old_source.velocity.dot(direction) else old_source.velocity
				if incoming.dot(direction)<minimum: continue
				var relative = old_target.position-old_source.position
				if relative.length_squared()<0.001 or relative.normalized().dot(incoming.normalized())<0.2: continue
				var closest = Geometry.get_closest_point_to_segment_2d(old_target.position,old_source.position,source.position)
				if closest.distance_to(old_target.position)>distance+1.0: continue
				if change.dot(incoming.normalized())<minimum: continue
				var root = int(claim.attacker)
				if not origins.has(root):
					origins[root] = {"attacker":root,"at":claim.at,"ground_since":-1.0,"direction":incoming.normalized(),"path":path+[target.id],"depth":int(claim.get("depth",0))+1}
			if origins.size()==1: additions[target.id] = origins.values()[0]
		for id in additions:
			claims[id] = additions[id]
			linked_pushes += 1
		if additions.empty(): break

func _pair(a: int,b: int) -> String:
	return "%d:%d" % [min(a,b),max(a,b)]
