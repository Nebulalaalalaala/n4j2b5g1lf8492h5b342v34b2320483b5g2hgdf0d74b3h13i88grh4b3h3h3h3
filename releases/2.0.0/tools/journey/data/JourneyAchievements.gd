extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Achievement collections and milestones derived from the locally recorded
# match history (ProfileHistoryStore records). Values only count what this
# client observed; nothing is estimated. Tier XP is shown but only awarded by
# the ledger owner (see JourneyStore.claims_enabled / mark_claimed).
const TIER_XP = [1000,2500,5000,10000,20000,40000]
const KINGLY_XP = 40000
const NAMES = ["Silver","Gold","Ruby","Sapphire","Master","Kingly"]
# key, name, detail, emblem, thresholds for Silver..Master, Kingly 1..Kingly 5.
# Crown Kingly begins at 1,000 observed wins; later Kingly tiers add 500.
# Claim identities stay unchanged: previously awarded XP is never revoked.
const COLLECTIONS = [
	["exploration","Map Explorer","Discover public maps.","exploration",[25,75,150,300,500,800,1000,1200,1400,1600]],
	["crown","Crown Collector","Win public matches overall.","crown",[10,50,150,350,650,1000,1500,2000,2500,3000]],
	["podium","Placement Fanatic","Finish a public race in the top three.","podium",[15,50,150,350,700,1100,1450,1800,2150,2500]],
	["clock","Against the Clock","Beat your own time-trial record.","clock",[3,10,25,60,120,200,275,350,425,500]],
	["builder","Goob Builder","Publish levels with more than 200 objects.","builder",[1,3,7,15,30,50,70,90,110,130]],
	["conqueror","Map Conqueror","Finish first on different public maps.","conqueror",[5,15,40,80,150,250,325,400,475,550]],
	# Best win streak from the account's GooberDash stats (store.native, see JourneyStore).
	# The optional 6th value multiplies the tier XP (streaks are far rarer than the other counts).
	["streak","Win Streak","Win public matches in a row.","streak",[5,10,15,20,25,30,33,36,39,42],5],
]

static func tier_name(tier:int) -> String:
	if tier<=0:
		return "Not started"
	if tier<=5:
		return NAMES[tier-1]
	return "Kingly %d" % (tier-5)

# Threshold for reaching `tier` (1-based), unbounded past Kingly 5.
static func threshold(base:Array,tier:int) -> int:
	if tier<=base.size():
		return int(base[tier-1])
	var step = int(base[-1])-int(base[-2])
	return int(base[-1])+step*(tier-base.size())

# builder: JourneyBuilder.summary() (null until the account's levels were checked).
func build(records:Array,store,builder = null) -> Dictionary:
	var ordered = records.duplicate()
	ordered.sort_custom(self,"_earlier")
	var events = {"exploration":[],"crown":[],"podium":[],"clock":[],"conqueror":[],"streak":[]}
	if store!=null and store.get("native") is Dictionary:
		for i in int(clamp(int(store.native.get("Winstreak",0)),0,1000)):
			events.streak.append(int(store.native.get("time",0)))
	var maps = {}
	var firsts = {}
	var best = {}
	var milestones = {"match":0,"win":0,"first":0,"trial":0,"rounds_100":0}
	var rounds = 0
	for r in ordered:
		if r.get("custom",false) or (str(r.result)=="unknown" and float(r.play_seconds)<1.0):
			continue
		var date = int(r.date)
		var public = str(r.mode)=="match_round"
		rounds += 1
		if rounds==100:
			milestones.rounds_100 = date
		if public:
			if milestones.match==0:
				milestones.match = date
			if not maps.has(r.map_id):
				maps[r.map_id] = true
				events.exploration.append(date)
			if r.win:
				events.crown.append(date)
				if milestones.win==0:
					milestones.win = date
			if str(r.result)=="finish" and int(r.placement)>=1 and int(r.placement)<=3:
				events.podium.append(date)
			if str(r.result)=="finish" and int(r.placement)==1:
				if milestones.first==0:
					milestones.first = date
				if not firsts.has(r.map_id):
					firsts[r.map_id] = true
					events.conqueror.append(date)
		elif str(r.mode)=="time_trial" and str(r.result)=="finish":
			if milestones.trial==0:
				milestones.trial = date
			var previous = float(best.get(r.map_id,-1.0))
			if previous>=0 and float(r.finish_time)<previous-0.000001:
				events.clock.append(date)
			if previous<0 or float(r.finish_time)<previous:
				best[r.map_id] = float(r.finish_time)
	# Wins and likely maps from Calculate XP count toward Crown Collector and Map Explorer.
	if store!=null and store.get("backfill") is Dictionary and not store.backfill.empty():
		var when = int(store.backfill.get("time",0))
		var extra = []
		for i in int(clamp(int(store.backfill.get("wins",0)),0,100000)):
			extra.append(when)
		events.crown = extra+events.crown
		# Likely-played maps count once, and only until the map shows up in recorded history.
		extra = []
		var ids = store.backfill.get("map_ids",null)
		if ids is Array:
			for id in ids:
				if not maps.has(id):
					extra.append(when)
		else:
			for i in int(clamp(int(store.backfill.get("maps",0)),0,100000)):
				extra.append(when)
		events.exploration = extra+events.exploration
	if builder!=null:
		var times = []
		for level in builder.levels:
			if level.qualifies:
				times.append(max(1,int(level.time)))
		times.sort()
		events.builder = times
	var collections = []
	for entry in COLLECTIONS:
		var key = entry[0]
		var thresholds = entry[4]
		var c = {"key":key,"name":entry[1],"detail":entry[2],"emblem":entry[3],"thresholds":thresholds.slice(0,5),"xp":TIER_XP,
			"tier":0,"value":0,"dates":[0,0,0,0,0,0],"claimable":false,"claimed":0,"tier_names":NAMES}
		if not events.has(key):
			c.unsupported = true
			collections.append(c)
			continue
		var list = events[key]
		c.value = list.size()
		while list.size()>=threshold(thresholds,int(c.tier)+1):
			c.tier += 1
		# Arrays cover every reached tier plus the next one (at least 6 rows).
		var count = max(6,int(c.tier)+1)
		c.thresholds = []
		c.xp = []
		c.dates = []
		c.tier_names = []
		for i in range(count):
			var t = threshold(thresholds,i+1)
			c.thresholds.append(t)
			c.xp.append((TIER_XP[i] if i<TIER_XP.size() else KINGLY_XP)*(int(entry[5]) if entry.size()>5 else 1))
			c.dates.append(int(list[t-1]) if list.size()>=t else 0)
			c.tier_names.append(tier_name(i+1))
		if store!=null:
			c.claimed = store.claimed_tier(key)
			c.claimable = store.claims_enabled and c.tier>c.claimed
		collections.append(c)
	var featured = []
	if store!=null:
		for key in store.featured:
			for c in collections:
				if c.key==key and int(c.tier)>0:
					featured.append(key)
	var wins = events.crown.size()
	var list = [
		{"name":"First public match","detail":"Play a public match.","date":milestones.match,"done":milestones.match>0},
		{"name":"First overall victory","detail":"Win a public match.","date":milestones.win,"done":milestones.win>0},
		{"name":"First race win","detail":"Finish first in a public race.","date":milestones.first,"done":milestones.first>0},
		{"name":"First time trial","detail":"Finish a time trial.","date":milestones.trial,"done":milestones.trial>0},
		{"name":"100 rounds played","detail":"%d of 100 recorded" % min(rounds,100),"date":milestones.rounds_100,"done":milestones.rounds_100>0,"progress":min(1.0,rounds/100.0)},
		{"name":"10 overall victories","detail":"%d of 10 recorded" % min(wins,10),"date":events.crown[9] if wins>=10 else 0,"done":wins>=10,"progress":min(1.0,wins/10.0)},
	]
	# Every certified level (list cached by JourneyCertified.gd), any mode counts.
	var certified = load(ModPaths.path("JourneyCertified.gd")).load_cache().get("levels",[])
	if not certified.empty():
		var played = {}
		for r in ordered:
			if not r.get("custom",false):
				played[str(r.map_id)] = int(r.date)
		var count = 0
		var last = 0
		for level in certified:
			if played.has(str(level.get("id",""))):
				count += 1
				last = max(last,played[str(level.id)])
		var all_done = count>=certified.size()
		list.append({"name":"Every certified level","detail":"%d of %d played" % [count,certified.size()],"date":last if all_done else 0,
			"done":all_done,"progress":float(count)/certified.size()})
	return {"achievements":{"featured":featured,"collections":collections},"milestones":list}

func _earlier(a,b) -> bool:
	return int(a.date)<int(b.date)
