extends Reference
# One-time achievement bonuses; rank milestones intentionally award no XP.
const BONUSES = {"first_sweep":1000,"wins_50":2500,"wins_100":5000,"wins_500":10000,
	"maps_10":500,"maps_25":1000,"maps_50":2000,"maps_100":4000,"active_50":2500,"active_100":5000}

func rewards(m, ledger, store, definitions = null):
	var out = []
	if ledger == null or store == null or not ledger.writable or not store.writable or str(ledger.account_id).empty() or ledger.account_id != store.account_id or m.get("preview",false):
		return out
	for item in build(m,definitions):
		if not BONUSES.has(item.key):
			continue
		var flag = "milestone:"+str(item.key)
		var id = flag+":"+str(ledger.account_id)
		item.xp = BONUSES[item.key]
		item.claimed = ledger.ids.has(id) or store.flag(flag)
		item.claimable = item.done and not item.claimed
		item.transaction_id = id
		out.append(item)
	return out

func claim(m, ledger, store, key = "", definitions = null):
	var batch = []
	var flags = []
	for item in rewards(m,ledger,store,definitions):
		if not item.claimable or (not key.empty() and str(item.key)!=key):
			continue
		batch.append({"id":item.transaction_id,"player_id":ledger.account_id,"category":"challenge",
			"reason":"Milestone: "+str(item.name),"related_id":str(item.key),"source":"verified_local_activity",
			"amount":int(item.xp),"timestamp":OS.get_unix_time()})
		flags.append("milestone:"+str(item.key))
	if batch.empty():
		return 0
	var added = ledger.award_batch(batch)
	if added < 0:
		return added
	for flag in flags:
		store.note(flag)
	store.save()
	return added
static func make(key, name, value, target, date, detail = ""):
	return {"key":key,"name":name,"value":min(value,target),"target":target,"done":value>=target,
		"date":int(date) if value>=target else 0,"progress":min(1.0,float(value)/max(1,target)),
		"detail":detail if not detail.empty() else "%d / %d recorded" % [min(value,target),target]}

func build(m, definitions = null):
	var list = []
	var records = m.stats.records.duplicate() if m.get("stats") != null and m.stats.get("records") != null else []
	records.sort_custom(self,"_earlier")
	var wins = []
	var maps = {}
	var map_dates = []
	for r in records:
		if r.get("custom",false) or str(r.mode)!="match_round":
			continue
		if bool(r.win):
			wins.append(int(r.date))
		if str(r.result)=="finish" and not str(r.map_id).empty() and not maps.has(str(r.map_id)):
			maps[str(r.map_id)] = true
			map_dates.append(int(r.date))
	for target in [50,100,500]:
		list.append(make("wins_"+str(target),"%d overall victories" % target,wins.size(),target,wins[target-1] if wins.size()>=target else 0))
	for target in [10,25,50,100]:
		list.append(make("maps_"+str(target),"Qualify on %d different maps" % target,maps.size(),target,map_dates[target-1] if maps.size()>=target else 0))
	var sweep_date = 0
	for entry in m.get("transactions",[]):
		if str(entry.get("reason",""))=="Clean sweep":
			var time = int(entry.timestamp)
			sweep_date = time if sweep_date==0 else min(sweep_date,time)
	list.append(make("first_sweep","First Clean Sweep",1 if sweep_date>0 else 0,1,sweep_date,"Win every race round and the overall public match."))
	var activity = m.get("activity")
	for hours in [50,100]:
		var seconds = int(activity.get("lifetime_seconds",0)) if activity != null else 0
		var date = int(activity.get("milestone_dates",{}).get(str(hours),0)) if activity != null else 0
		list.append(make("active_"+str(hours),"%d verified active hours" % hours,seconds,hours*3600,date,"%.1f / %d verified hours" % [seconds/3600.0,hours]))
	if definitions != null:
		var ranks = definitions.finite_ranks()
		ranks.append(definitions.king_rank(1))
		var entries = m.get("transactions",[]).duplicate()
		entries.sort_custom(self,"_transaction_earlier")
		for rank in ranks:
			if not (int(rank.id) in [6,9,12,15,18]):
				continue
			var total = 0
			var date = 0
			for entry in entries:
				total += int(entry.amount)
				if date==0 and total>=int(rank.xp):
					date = int(entry.timestamp)
			list.append(make("league_"+str(rank.id),"Reach "+str(rank.league),total,int(rank.xp),date,"%d / %d Journey XP" % [min(total,int(rank.xp)),int(rank.xp)]))
	return list

func _transaction_earlier(a,b):
	return int(a.timestamp)<int(b.timestamp)

func _earlier(a,b):
	return int(a.date)<int(b.date)
