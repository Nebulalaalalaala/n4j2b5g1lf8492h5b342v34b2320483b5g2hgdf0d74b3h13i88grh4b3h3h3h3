extends Reference

# Pure policy: adapter supplies live public-game evidence, never career history.
var rewards = {}

func entry(owner, id, category, reason, related, amount, now):
	return {"id":id,"player_id":owner,"category":category,"reason":reason,
		"related_id":related,"source":"server_event","amount":int(amount),"timestamp":int(now)}

func round_awards(owner, match_id, round_data, now):
	var out = []
	if owner.empty() or match_id.empty() or not round_data.get("eligible",false):
		return out
	if float(round_data.get("active",0))<1.0 or float(round_data.get("distance",0))<50:
		return out
	var root = "match:"+match_id+":"+str(round_data.number)
	var related = str(round_data.map_id)
	if related.empty():
		return out
	out.append(entry(owner,root+":participation","placement","Participation",related,rewards.participation,now))
	# Same key as Claude's claimable discovery, whichever route awards it first.
	out.append(entry(owner,"map:"+related+":discover:"+owner,"exploration","Map discovered",related,rewards.discovery,now))
	var rank = int(round_data.get("rank",0))
	if round_data.get("race",false) and rank>0:
		out.append(entry(owner,root+":finish","placement","Race finish",related,rewards.race_finish,now))
		if rank<=3:
			out.append(entry(owner,root+":podium","placement","Race podium",related,rewards.podium,now))
		if rank==1:
			out.append(entry(owner,root+":first","placement","Race first place",related,rewards.race_first,now))
	return out

func world_record_awards(owner,map_id,baseline,records,finish_time,certified,now):
	if owner.empty() or map_id.empty() or not certified or baseline==null or records.empty() or finish_time<=0:
		return []
	var top = records[0]
	var score = float(top.get("score",0))
	if str(top.get("owner_id",""))!=owner or score<=0 or score>=float(baseline) or abs(score-finish_time*100000.0)>1.0:
		return []
	return [entry(owner,"wr:"+map_id+":"+owner,"record","First verified world record",map_id,rewards.first_world_record,now)]

func match_awards(owner, match_id, rounds, winner, now, day):
	var out = []
	if owner.empty() or match_id.empty() or not winner or rounds.empty():
		return out
	var meaningful = false
	var complete = true
	var races = 0
	var highest = 0
	for number in rounds:
		var r = rounds[number]
		meaningful = meaningful or not round_awards(owner,match_id,r,now).empty()
		complete = complete and r.get("eligible",false)
		highest = max(highest,int(number))
		if r.get("race",false):
			races += 1
			complete = complete and int(r.get("rank",0))==1
	if not meaningful:
		return out
	out.append(entry(owner,"match:"+match_id+":win","win","Overall match victory",match_id,rewards.match_win,now))
	out.append(entry(owner,"daily-win:"+day+":"+owner,"win","First victory of the day",match_id,rewards.first_daily_win,now))
	# Require the entire observed round sequence, not just a late-joined final.
	for number in range(1,highest+1):
		complete = complete and rounds.has(number)
	if complete and races>0:
		out.append(entry(owner,"match:"+match_id+":sweep","win","Clean sweep",match_id,rewards.clean_sweep,now))
	return out
