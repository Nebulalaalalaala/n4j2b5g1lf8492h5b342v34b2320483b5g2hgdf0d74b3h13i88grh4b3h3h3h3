extends Reference

# These are inferred death/respawn episodes, never authoritative death events.
# Require a continuous alive -> inactive -> alive sequence in the same track.
func episodes(tracks: Array, end_time: float = -1.0) -> Array:
	var result = []
	for track in tracks:
		if track.has("eliminated_at") and (track.get("elimination_confirmed",false) or end_time<0 or track.eliminated_at<end_time):
			result.append({"time":track.eliminated_at,"position":Vector2(track.death_position[0],track.death_position[1]),"player":track.id})
		var previous = null
		var pending = null
		for sample in track.samples:
			if end_time >= 0 and sample[0] >= end_time:
				break
			if previous != null:
				if sample[0] - previous[0] > 0.15:
					pending = null
				elif previous[5] and not sample[5]:
					pending = {"time":sample[0], "position":Vector2(previous[1], previous[2]), "player":track.id}
				elif not previous[5] and sample[5] and pending != null:
					if track.outcome != "finish" or track.finish_time < 0 or sample[0] < track.finish_time:
						result.append(pending)
					pending = null
			previous = sample
	return result

func clusters(events: Array, cell_size: float = 96.0) -> Array:
	var buckets = {}
	for event in events:
		var point: Vector2 = event.position
		var key = str(floor(point.x / cell_size)) + ":" + str(floor(point.y / cell_size))
		if not buckets.has(key):
			buckets[key] = {"position":Vector2.ZERO, "count":0, "players":{}}
		var bucket = buckets[key]
		bucket.position += point
		bucket.count += 1
		bucket.players[event.player] = true
	var result = []
	for bucket in buckets.values():
		bucket.position /= bucket.count
		result.append(bucket)
	return result
