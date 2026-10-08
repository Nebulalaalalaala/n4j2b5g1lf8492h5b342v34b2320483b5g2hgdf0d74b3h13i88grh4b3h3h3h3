extends Reference

# Daily and weekly challenges, counted from recorded rounds (and the active-time
# tracker for time goals). Daily challenges come in four sets a day (easy,
# medium, hard, expert); claiming every challenge in a set unlocks the next,
# which counts from the moment it unlocked. Picks, rerolls and claims are kept
# per account in JourneyStore (store.quests); XP is awarded by JourneyScreen.
const REROLLS = 2
const SETS = ["easy","medium","hard","expert"]
const DAILY_XP = {"easy":250,"medium":400,"hard":650,"expert":1000}
const WEEKLY_XP = {"easy":2000,"medium":3500,"hard":5000}
# kind: [category, icon, daily targets per set, weekly targets e/m/h, title, one-off title, detail]
const KINDS = {
	"rounds":["Public Matches","flag",[5,10,20,30],[40,80,150],"Play %d public rounds","Play a public round","Public matches"],
	"finishes":["Public Matches","flag",[3,6,12,18],[25,50,100],"Finish %d races","Finish a race","Public races"],
	"top3":["Public Matches","podium",[2,4,8,12],[15,30,60],"Place top 3 in %d races","Place top 3 in a race","Public races"],
	"wins":["Public Matches","crown",[1,2,3,5],[3,6,12],"Win %d public matches","Win a public match","Overall wins"],
	"maps":["Public Matches","compass",[3,6,10,14],[15,30,50],"Play %d different maps","Play a map","Public matches"],
	# No "discover new maps" quest: the certified pool is finite, so it could become
	# impossible (or take hours) for players who have seen almost every map.
	"map_finishes":["Public Matches","flag",[2,4,7,10],[10,20,35],"Finish on %d different maps","Finish on a map","Public races"],
	"trials":["Speedrunning","stopwatch",[2,4,8,12],[10,20,40],"Finish %d time trials","Finish a time trial","Time trials"],
	"pbs":["Speedrunning","stopwatch",[1,2,3,5],[4,8,15],"Beat %d personal bests","Beat a personal best","Time trials"],
	"firsts":["Optional Challenges","crown",[1,2,4,6],[5,10,20],"Finish first in %d races","Finish first in a race","Public races"],
	"clean":["Optional Challenges","target",[1,3,5,8],[8,15,30],"Finish %d rounds without dying","Finish a round without dying","Public matches"],
	"active":["Optional Challenges","clock",[20,45,90,120],[120,240,420],"Play for %d minutes","Play for a minute","Active time"],
}
const DIFFS = ["easy","medium","hard","expert"]
const SET_NAMES = ["Easy","Medium","Hard","Expert"]

func build(records:Array,store,activity,now = -1) -> Dictionary:
	if now < 0:
		now = OS.get_unix_time()
	var day = day_start(now)
	var week = day-_weekday(now)*86400
	var state = _state(store,day,week)
	var ordered = []
	for r in records:
		if not r.get("custom",false) and not (str(r.result)=="unknown" and float(r.play_seconds)<1.0):
			ordered.append(r)
	ordered.sort_custom(self,"_earlier")
	var today_active = int(activity.today_seconds) if activity!=null else 0
	# Current set: the first one not fully claimed. Unlock the next set's clock
	# the first time we see the previous one cleared.
	var current = 0
	var sets = []
	var changed = false
	while current<SETS.size():
		var key = str(current)
		if not state.set_start.has(key):
			state.set_start[key] = now if current>0 else day
			state.set_active[key] = today_active if current>0 else 0
			changed = true
		var list = []
		for i in state.sets[current].size():
			list.append(_quest(state.sets[current][i],"d%d_s%d_%d" % [day,current,i],ordered,int(state.set_start[key]),day+86400,activity,DAILY_XP,0,store,int(state.set_active[key])))
		sets.append(list)
		var all_claimed = true
		for q in list:
			all_claimed = all_claimed and q.claimed
		if not all_claimed:
			break
		current += 1
	if changed and store!=null:
		store.save()
	var cleared = current>=SETS.size()
	var shown = min(current,SETS.size()-1)
	var choices = []
	if not cleared:
		for i in state.choices.size():
			var pick = {"kind":state.choices[i].kind,"diff":SETS[shown]}
			choices.append(_quest(pick,"c%d_s%d_%d" % [day,shown,i],ordered,int(state.set_start[str(shown)]),day+86400,activity,DAILY_XP,0,store,int(state.set_active[str(shown)])))
	var weekly = []
	for i in state.weekly.size():
		weekly.append(_quest(state.weekly[i],"w%d_%d" % [week,i],ordered,week,week+7*86400,activity,WEEKLY_XP,1,store,0))
	return {"rerolls":max(0,REROLLS-int(state.rerolled)),"reset_in":day+86400-now,"weekly_reset_in":week+7*86400-now,
		"daily":sets[shown],"set":shown,"sets":SETS.size(),"set_name":SET_NAMES[shown],"cleared":cleared,
		"choices":choices,"weekly":weekly}

func _quest(pick,id,records,from,to,activity,xp_table,weekly,store,active_base) -> Dictionary:
	var spec = KINDS[pick.kind]
	var target = int(spec[3 if weekly else 2][DIFFS.find(pick.diff)])
	var value = 0
	if pick.kind=="active" and not weekly:
		value = int(max(0,(int(activity.today_seconds) if activity!=null else 0)-active_base)/60)
	else:
		value = _count(pick.kind,records,from,to,activity)
	value = min(target,value)
	var test = false
	if store!=null and store.test.get("done",{}).has(id) and value<target:
		value = target
		test = true
	var done = value>=target
	var claimed = store!=null and store.quest_claimed(id)
	return {"id":id,"kind":pick.kind,"category":spec[0],"icon":spec[1],"title":spec[4] % target if target>1 else spec[5],
		"detail":spec[6],"value":value,"target":target,"xp":int(xp_table[pick.diff]),"difficulty":pick.diff,
		"done":done,"claimed":claimed,"claimable":done and not claimed and store!=null,"weekly":bool(weekly),"test":test}

func _count(kind,records,from,to,activity) -> int:
	if kind=="active":
		return _active_minutes(activity,from,to)
	var n = 0
	var maps = {}
	var best = {}
	for r in records:
		var t = int(r.date)
		var public = str(r.mode)=="match_round"
		var finish = str(r.result)=="finish"
		var inside = t>=from and t<to
		if kind=="pbs" and str(r.mode)=="time_trial" and finish:
			var prior = float(best.get(r.map_id,-1.0))
			if inside and prior>=0 and float(r.finish_time)<prior-0.000001:
				n += 1
			if prior<0 or float(r.finish_time)<prior:
				best[r.map_id] = float(r.finish_time)
			continue
		if not inside:
			continue
		match kind:
			"rounds":
				n += int(public)
			"finishes":
				n += int(public and finish)
			"top3":
				n += int(public and finish and int(r.placement)>=1 and int(r.placement)<=3)
			"wins":
				n += int(public and bool(r.win))
			"maps":
				if public:
					maps[r.map_id] = true
			"map_finishes":
				if public and finish:
					maps[r.map_id] = true
			"trials":
				n += int(str(r.mode)=="time_trial" and finish)
			"firsts":
				n += int(public and finish and int(r.placement)==1)
			"clean":
				n += int(public and finish and int(r.deaths)==0)
	return maps.size() if kind in ["maps","map_finishes"] else n

func _active_minutes(activity,from,to) -> int:
	if activity==null:
		return 0
	# snapshot.days: last 7 local days, oldest first, today last.
	var today = day_start(OS.get_unix_time())
	var seconds = 0
	var days = activity.get("days",[])
	for i in days.size():
		var start = today-(days.size()-1-i)*86400
		if start>=from and start<to:
			seconds += int(days[i])
	return int(seconds/60)

# Picks for today/this week: deterministic per account and period, stored so
# rerolls and swaps stick.
func _state(store,day,week) -> Dictionary:
	var saved = store.quests if store!=null else {}
	var owner = str(store.account_id) if store!=null else ""
	var changed = false
	if int(saved.get("day",0))!=day or not saved.get("sets") is Array:
		saved.day = day
		saved.sets = []
		for i in SETS.size():
			var rng = RandomNumberGenerator.new()
			rng.seed = hash(owner+":d:"+str(day)+":"+str(i))
			var kinds = _shuffled(rng)
			saved.sets.append([{"kind":kinds[0],"diff":SETS[i]},{"kind":kinds[1],"diff":SETS[i]},{"kind":kinds[2],"diff":SETS[i]}])
		saved.choices = []
		saved.set_start = {}
		saved.set_active = {}
		saved.rerolled = 0
		saved.erase("daily")
		saved.erase("spare")
		# Keep only this week's claimed challenges; old daily ids can't recur.
		var kept = {}
		for id in saved.get("claimed",{}):
			if str(id).begins_with("w%d_" % week):
				kept[id] = true
		saved.claimed = kept
		changed = true
	if int(saved.get("week",0))!=week or not saved.get("weekly") is Array:
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(owner+":w:"+str(week))
		var kinds = _shuffled(rng)
		saved.week = week
		saved.weekly = [{"kind":kinds[0],"diff":"easy"},{"kind":kinds[1],"diff":"medium"},{"kind":kinds[2],"diff":"hard"}]
		changed = true
	# Two swap choices per set, kinds not already in the current set.
	var index = _set_now(saved,store)
	if saved.choices.size()!=2 or int(saved.get("choices_set",-1))!=index:
		saved.choices = []
		saved.choices_set = index
		for kind in _free_kinds(saved,index):
			if saved.choices.size()<2:
				saved.choices.append({"kind":kind})
		changed = true
	if store!=null:
		store.quests = saved
		if changed:
			store.save()
	return saved

# Index of the set being worked on (first not fully claimed).
func _set_now(saved,store) -> int:
	for i in saved.sets.size():
		for n in saved.sets[i].size():
			if store==null or not store.quest_claimed("d%d_s%d_%d" % [int(saved.day),i,n]):
				return i
	return saved.sets.size()-1

func _free_kinds(saved,index) -> Array:
	var used = {}
	for pick in saved.sets[index]:
		used[pick.kind] = true
	for pick in saved.get("choices",[]):
		used[pick.kind] = true
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(saved.day)+":"+str(index)+":"+str(saved.get("rerolled",0)))
	var out = []
	for kind in _shuffled(rng):
		if not used.has(kind):
			out.append(kind)
	return out

func _shuffled(rng) -> Array:
	var kinds = KINDS.keys()
	for i in range(kinds.size()-1,0,-1):
		var j = rng.randi_range(0,i)
		var t = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	return kinds

# Swap challenge `slot` of the current set for another kind. False when out of rerolls.
func reroll(store,slot:int) -> bool:
	var s = store.quests
	var index = _set_now(s,store)
	if int(s.get("rerolled",0))>=REROLLS or slot<0 or slot>=s.sets[index].size():
		return false
	var free = _free_kinds(s,index)
	if free.empty():
		return false
	s.sets[index][slot] = {"kind":free[0],"diff":s.sets[index][slot].diff}
	s.rerolled = int(s.get("rerolled",0))+1
	store.save()
	return true

# Swap choice `index` in place of the first unfinished challenge; costs a reroll.
func choose(store,index:int,daily:Array) -> bool:
	var s = store.quests
	var current = _set_now(s,store)
	if int(s.get("rerolled",0))>=REROLLS or index<0 or index>=s.get("choices",[]).size():
		return false
	for slot in daily.size():
		if not daily[slot].done:
			var old = s.sets[current][slot]
			s.sets[current][slot] = {"kind":s.choices[index].kind,"diff":old.diff}
			s.choices[index] = {"kind":old.kind}
			s.rerolled = int(s.get("rerolled",0))+1
			store.save()
			return true
	return false

static func day_start(utc:int) -> int:
	var offset = int(OS.get_time_zone_info().get("bias",0))*60
	return int(floor(float(utc+offset)/86400.0))*86400-offset

static func _weekday(utc:int) -> int:
	var offset = int(OS.get_time_zone_info().get("bias",0))*60
	return (OS.get_datetime_from_unix_time(utc+offset).weekday+6)%7

func _earlier(a,b) -> bool:
	return int(a.date)<int(b.date)
