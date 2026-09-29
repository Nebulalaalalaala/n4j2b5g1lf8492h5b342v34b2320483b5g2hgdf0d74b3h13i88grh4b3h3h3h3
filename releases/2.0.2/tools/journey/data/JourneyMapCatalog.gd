extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Known public maps, not an assertion about the server's current rotation.
# Catalog presence never implies a discovery, finish or XP award.
var entries = null
var known = {}
var certified = false
var modes = {}   # map id -> catalog mode ("32P", "Elimination", ...)

# Card caption: 32P, 16P, 8P or Knockout. Falls back to the largest recorded lobby.
static func size_label(mode, players) -> String:
	var text = str(mode).to_upper()
	if text.find("ELIM") >= 0 or text.find("KNOCK") >= 0 or text == "4P":
		return "Knockout"
	if text in ["32P", "16P", "8P"]:
		return text
	if players > 16:
		return "32P"
	if players > 8:
		return "16P"
	if players > 4:
		return "8P"
	if players > 0:
		return "Knockout"
	return ""

func maps(stats):
	if entries == null:
		entries = []
		var file = File.new()
		if file.open(ModPaths.path("journey-map-catalog.json"),File.READ)==OK:
			var parsed = JSON.parse(file.get_as_text())
			file.close()
			if parsed.error==OK and parsed.result is Array:
				entries = parsed.result
		# Certified levels cached by JourneyCertified.gd (Level Explorer's CERTIFIED list).
		for entry in entries:
			known[str(entry.get("id",""))] = true
			modes[str(entry.get("id",""))] = str(entry.get("mode",""))
		for level in load(ModPaths.path("JourneyCertified.gd")).load_cache().get("levels",[]):
			certified = true
			if level is Dictionary and not known.has(str(level.get("id",""))):
				known[str(level.id)] = true
				entries.append(level)
			if level is Dictionary and not str(level.get("mode","")).empty():
				modes[str(level.get("id",""))] = str(level.mode)
	var result = []
	var seen = {}
	for map in stats.maps if stats!=null else []:
		var id = str(map.key).split(":",true,1)[-1]
		# Only certified/public maps get cards; own or unlisted levels played in
		# time trial or the editor stay out. Before the certified list has been
		# fetched, recorded public matches are the only proof a map is public.
		if not known.has(id) and (certified or not str(map.key).begins_with("match_round:")):
			continue
		if seen.has(id):
			var prior = result[seen[id]]
			for field in ["plays","completions","dnfs","wins","deaths","total_time"]:
				prior[field] = prior.get(field,0)+map.get(field,0)
			prior.last_played = max(prior.last_played,map.last_played)
			prior.players = max(int(prior.get("players",0)),int(map.get("players",0)))
			if float(map.best)>=0 and (float(prior.best)<0 or float(map.best)<float(prior.best)):
				prior.best = map.best
			if int(map.get("best_placement",0))>0 and (int(prior.get("best_placement",0))==0 or int(map.best_placement)<int(prior.best_placement)):
				prior.best_placement = map.best_placement
			continue
		seen[id] = result.size()
		result.append(map.duplicate(true))
	for map in result:
		map.mode = size_label(modes.get(str(map.key).split(":",true,1)[-1], ""), int(map.get("players",0)))
	for entry in entries:
		if seen.has(str(entry.id)):
			continue
		seen[str(entry.id)] = result.size()
		result.append({"key":"catalog:"+str(entry.id),"name":entry.name,"mode":size_label(entry.mode,0),
			"plays":0,"completions":0,"dnfs":0,"wins":0,"best":-1.0,"total_time":0.0,
			"deaths":0,"last_played":0,"best_placement":0,"pb_steps":[]})
	return result
