extends Reference

# Swept convex shape checks, not center-point raycasts. Read-only estimate for
# current velocity + gravity against CURRENT enabled native fixtures. It stops
# at the first solid/hazard; it does not guess future inputs, bounces, moving
# hazards, lasers switching phase, wind, or gravity-field entry.
func predict(position: Vector2, velocity: Vector2, gravity: float, player_polygon: PoolVector2Array, fixtures: Array, horizon: float, steps: int) -> Dictionary:
	var dt = horizon / steps
	var path = PoolVector2Array([position])
	var preview = []
	var p = position
	var v = velocity
	var bounds = Rect2(p, Vector2.ZERO)
	for _i in range(steps):
		v.y += gravity * dt
		p += v * dt
		preview.append(p)
		bounds = bounds.expand(p)
	var radius = 0.0
	for point in player_polygon: radius = max(radius, point.length())
	var nearby = []
	for fixture in fixtures:
		if bounds.grow(radius).intersects(fixture.bounds, true): nearby.append(fixture)
	p = position
	for next in preview:
		var first = 2.0
		var hit = null
		for fixture in nearby:
			# One-way platforms are not full walls; do not invent collisions
			# against their underside. Directional/custom sensors stay uncertain.
			if fixture.level_node != null and fixture.level_node.collision_type == 1: continue
			var fraction = swept_fraction(player_polygon, p, next - p, fixture.world_points)
			if fraction >= 0.0 and fraction < first:
				first = fraction
				hit = fixture
		if hit != null:
			var contact = p.linear_interpolate(next, first)
			path.append(contact)
			return {"points": path, "death": hit.category == "hazards", "contact": contact, "fixture": hit.fixture}
		path.append(next)
		p = next
	return {"points": path, "death": false}

func swept_fraction(player: PoolVector2Array, origin: Vector2, motion: Vector2, obstacle: PoolVector2Array) -> float:
	if player.size() < 3 or obstacle.size() < 3: return -1.0
	var enter = 0.0
	var leave = 1.0
	for polygon in [player, obstacle]:
		for i in range(polygon.size() - 1):
			var edge = polygon[i+1] - polygon[i]
			if edge.length_squared() < 0.000001: continue
			var axis = Vector2(-edge.y, edge.x).normalized()
			var a_min = INF
			var a_max = -INF
			var b_min = INF
			var b_max = -INF
			for point in player:
				var value = axis.dot(origin + point)
				a_min = min(a_min, value)
				a_max = max(a_max, value)
			for point in obstacle:
				var value = axis.dot(point)
				b_min = min(b_min, value)
				b_max = max(b_max, value)
			var speed = axis.dot(motion)
			if abs(speed) < 0.000001:
				if a_max < b_min or b_max < a_min: return -1.0
				continue
			var t0 = (b_min - a_max) / speed
			var t1 = (b_max - a_min) / speed
			enter = max(enter, min(t0,t1))
			leave = min(leave, max(t0,t1))
			if enter > leave: return -1.0
	# A surface merely touched at t=0 while moving away is not an impact.
	return enter if enter <= 1.0 and leave > 0.000001 else -1.0
