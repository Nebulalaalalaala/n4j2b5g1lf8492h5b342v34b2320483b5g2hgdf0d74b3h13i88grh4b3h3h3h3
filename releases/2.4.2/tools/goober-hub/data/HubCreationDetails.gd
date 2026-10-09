extends Reference
# Lightweight, display-only metadata. Never used as replay/physics authority.
static func macro_summary(data) -> Dictionary:
	var frames = 0
	for segment in data.get("segments",[]): frames += segment.size()
	return {"level":str(data.get("level_context",{}).get("level_name","")).substr(0,100),"frames":frames,"checkpoints":data.get("checkpoints",[]).size()}

static func clean(source) -> Dictionary:
	if not source is Dictionary: return {}
	var result = {}
	if source.get("level") is String: result.level = source.level.replace("\n"," ").replace("\r"," ").substr(0,100)
	for key in ["objects","cosmetics","frames","checkpoints"]:
		var value = source.get(key)
		if typeof(value) in [TYPE_INT,TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value)) and value>=0 and value<=2000000 and value==int(value): result[key] = int(value)
	return result

static func from_item(item) -> Dictionary:
	var payload = item.get("payload",{})
	if payload is Dictionary:
		if item.kind=="stamp" and payload.get("nodes") is Array: return {"objects":payload.nodes.size()}
		if item.kind=="outfit" and payload.get("state") is Dictionary and payload.state.get("selected") is Array: return {"cosmetics":payload.state.selected.size()}
		if payload.get("summary") is Dictionary: return clean(payload.summary)
	return clean(item.get("summary",{}))

static func caption(item) -> String:
	var summary = from_item(item)
	var parts = []
	if summary.has("objects"): parts.append("%d object%s" % [summary.objects,"" if summary.objects==1 else "s"])
	if summary.has("cosmetics"): parts.append("%d cosmetic%s" % [summary.cosmetics,"" if summary.cosmetics==1 else "s"])
	if not str(summary.get("level","")).empty(): parts.append(summary.level)
	if summary.has("frames"):
		var seconds = float(summary.frames)/60.0
		parts.append("%d:%05.2f at 1×" % [int(seconds)/60,fmod(seconds,60)])
	if summary.has("checkpoints"): parts.append("%d checkpoint%s" % [summary.checkpoints,"" if summary.checkpoints==1 else "s"])
	if parts.empty() and typeof(item.get("bytes")) in [TYPE_INT,TYPE_REAL] and item.bytes>0: parts.append("%.1f KiB" % (float(item.bytes)/1024))
	return PoolStringArray(parts).join(" · ")
