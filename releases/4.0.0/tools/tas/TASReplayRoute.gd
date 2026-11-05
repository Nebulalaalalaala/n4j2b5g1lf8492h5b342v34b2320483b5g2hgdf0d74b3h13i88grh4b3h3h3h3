extends Reference

# Only goals are derived here. Replay samples never become TAS save states.
const BOX_SIZE = Vector2(72, 96)
const MAX_BOXES = 256

static func touches(box: Rect2, from: Vector2, to: Vector2) -> bool:
	if box.has_point(from) or box.has_point(to):
		return true
	var corners = [box.position, Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]
	for index in 4:
		if Geometry.segment_intersects_segment_2d(from,to,corners[index],corners[(index+1)%4]) != null:
			return true
	return false

static func first_visit(samples: Array, box: Rect2, first := 0, last := -1) -> int:
	# A goal already occupied at entry is not an immediate successful section.
	var armed = first >= samples.size() or not box.has_point(samples[first].position)
	var end = samples.size() if last<0 else min(samples.size(),last+1)
	for index in range(max(1,first+1),end):
		if not armed:
			armed = not box.has_point(samples[index].position)
		elif touches(box,samples[index-1].position,samples[index].position):
			return index
	return -1

static func generate(samples: Array, seconds := 3.0, size := BOX_SIZE) -> Array:
	var result = []
	if samples.size() < 2:
		return result
	seconds = clamp(seconds,1.0,10.0)
	var start = 0
	while start < samples.size()-1 and result.size() < MAX_BOXES:
		var began = float(samples[start].time)
		var target = began+seconds
		var candidates = []
		var last_candidate = -INF
		for index in range(start+1,samples.size()):
			var sample = samples[index]
			var at = float(sample.time)
			if at > began+seconds*1.65:
				break
			if at < began+seconds*0.55 or at-last_candidate < 0.08:
				continue
			last_candidate = at
			var score = abs(at-target)/seconds
			if not bool(sample.get("grounded",false)): score += 0.28
			if bool(sample.get("dashing",false)): score += 0.65
			if index>0 and sample.get("checkpoint") != samples[index-1].get("checkpoint"): score -= 0.25
			if index>0 and bool(sample.get("grounded",false)) and not bool(samples[index-1].get("grounded",false)): score -= 0.15
			candidates.append({"index":index,"score":score})
		candidates.sort_custom(ScoreOrder.new(),"before")
		var cut = -1
		var zone = Rect2()
		var terminal = false
		for choice in candidates:
			var candidate = Rect2(samples[choice.index].position-size*0.5,size)
			var visit = first_visit(samples,candidate,start,choice.index)
			if visit > start and float(samples[visit].time)-began >= seconds*0.5:
				cut = visit
				zone = candidate
				break
		# Near the finish retain the actual final approach, not the finish's
		# post-qualification teleport. The collector excludes that teleport.
		if cut < 0 or float(samples.back().time)-float(samples[cut].time) < seconds*0.5:
			terminal = true
			zone = Rect2(samples.back().position-size*0.5,size)
			cut = first_visit(samples,zone,start)
			if cut <= start:
				break
		var guide = int(samples[cut].frame)-(int(samples[start].frame) if not result.empty() else 0)
		result.append({"start":-1,"end":-1,"zone":zone,"source":"leaderboard","done":false,"replay_frame":int(samples[cut].frame),"replay_time":float(samples[cut].time),"guide":guide,"base":guide})
		start = cut
		if terminal:
			break
	return result

static func retime(boxes: Array, samples: Array) -> String:
	var first = 0
	var previous_frame = 0
	for index in boxes.size():
		var section = boxes[index]
		var zone = section.get("zone")
		if not zone is Rect2 or zone.size.x<8 or zone.size.y<8:
			return "Box %d needs a valid size." % (index+1)
		var visit = first_visit(samples,zone,first)
		if visit <= first:
			return "The selected replay doesn't reach box %d in this order. Move it onto the route or remove it." % (index+1)
		section.replay_frame = int(samples[visit].frame)
		section.replay_time = float(samples[visit].time)
		section.guide = int(samples[visit].frame)-previous_frame
		section.base = section.guide
		previous_frame = int(samples[visit].frame)
		first = visit
	return ""

static func points(samples: Array) -> PoolVector2Array:
	var result = PoolVector2Array()
	var step = int(max(1,ceil(samples.size()/1500.0)))
	for index in range(0,samples.size(),step):
		result.append(samples[index].position)
	if not samples.empty() and (result.empty() or result[result.size()-1]!=samples.back().position):
		result.append(samples.back().position)
	return result

class ScoreOrder:
	extends Reference
	func before(a,b): return a.score < b.score


# Native dash initiation (including charge) and direction, independent of
# movement/facing. A mid-dash timer refill is another dash, not one long event.
static func dash_events(samples: Array) -> Array:
	var result = []
	var current = null
	var previous_timer = 0
	for sample in samples:
		var dashing = bool(sample.get("dashing",false))
		var timer = int(sample.get("dash_timer",1 if dashing else 0))
		if dashing and (current==null or timer>previous_timer):
			current = {"position":sample.position,"frame":int(sample.frame),"time":float(sample.time),"direction":(Vector2.RIGHT if bool(sample.dash_dir) else Vector2.LEFT) if sample.has("dash_dir") else Vector2.ZERO,"points":PoolVector2Array()}
			result.append(current)
		if dashing and current!=null and bool(sample.get("dash_active",true)):
			var points = current.points
			points.append(sample.position)
			current.points = points
		if not dashing: current = null
		previous_timer = timer
	return result
