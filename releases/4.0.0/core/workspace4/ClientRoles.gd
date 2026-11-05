extends Reference

# Labels are awarded with Journey's existing admin-only SQL badge functions.
# Neither a public appearance upload nor a local setting can assign a role.
const PREFIX = "[GP:role:"
const DEFINITIONS = {
	"admin":{"name":"Goobplayability Admin","short":"Admin","emblem":"crown","icon":"star","color":"ff9fc9","tier":0},
	"moderator":{"name":"Goobplayability Moderator","short":"Mod","emblem":"podium","icon":"flag","color":"8ce0ba","tier":0},
	"basic":{"name":"Basic access","short":"Basic","emblem":"exploration","icon":"user","color":"7fd8ff","tier":1,"from":"6cdbff","to":"668bff"},
	"advanced":{"name":"Advanced access · TAS","short":"Advanced","emblem":"clock","icon":"macro","color":"c09bff","tier":2,"from":"aa8cff","to":"ff99d5"},
	"developer":{"name":"Developer","short":"Dev","emblem":"builder","icon":"flask","color":"ffd28a","tier":3,"from":"ffe6a0","to":"ffab76"},
	"contributor":{"name":"Contributor","short":"Creator","emblem":"conqueror","icon":"paint","color":"b6daff","tier":0},
	"tester":{"name":"Tester","short":"Tester","emblem":"exploration","icon":"target","color":"b8c7ff","tier":0}
}
const ORDER = ["admin","moderator","developer","advanced","basic","contributor","tester"]

static func marker(code: String) -> String:
	return PREFIX+code+"]"

static func code(badge: Dictionary) -> String:
	var detail = str(badge.get("detail",""))
	for key in ORDER:
		if detail.begins_with(marker(key)): return key
	return ""

static func roles(awards: Array) -> Array:
	var codes = []
	for badge in awards:
		if not badge is Dictionary: continue
		var key = code(badge)
		if not key.empty() and not codes.has(key): codes.append(key)
	var result = []
	for key in ORDER:
		if codes.has(key): result.append(key)
	return result

static func tier(codes: Array) -> String:
	var best = ""
	var rank = 0
	for key in codes:
		if DEFINITIONS.has(key) and int(DEFINITIONS[key].tier)>rank:
			rank = int(DEFINITIONS[key].tier)
			best = key
	return best

static func description(code: String) -> String:
	return marker(code)+" "+str(DEFINITIONS[code].name)+". Admin-assigned Goobplayability label; does not rename the game account or grant installed modules."
