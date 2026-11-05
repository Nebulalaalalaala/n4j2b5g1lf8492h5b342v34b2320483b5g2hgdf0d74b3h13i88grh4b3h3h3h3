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
	var finished_race = round_data.get("race",false) and int(round_data.get("rank",0))>0
	# A replicated finish is stronger evidence than input samples lost to a stall.
	if not finished_race and (float(round_data.get("active",0))<1.0 or float(round_data.get("distance",0))<50):
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

# Repeatable: every 5 wins in a row while playing (5, 10, 15 ...), bigger for longer streaks.
const STREAK_XP = {5:2500,10:7500,15:15000,20:25000,25:40000}

func streak_award(owner, match_id, streak, now):
	if owner.empty() or match_id.empty() or streak<5 or streak%5!=0:
		return []
	var amount = STREAK_XP.get(streak,40000+20000*(streak-25)/5)
	return [entry(owner,"streak:"+match_id+":"+str(streak),"win","Win streak · %d in a row" % streak,match_id,amount,now)]

# Every win from the 2nd in a row pays more, so a streak is always worth keeping.
const STREAK_STEP = 250
const STREAK_STEP_CAP = 8
# Victory crate after every win: one fixed roll per match (no rerolls), luckier on a streak.
const CRATES = [["Common", 300, 600], ["Rare", 700, 1200], ["Epic", 1500, 2500], ["Legendary", 5000, 5000]]
const FIRST_WIN_XP = 1500

# pity: losses in a row before this win, each one makes the crate luckier.
static func crate_roll(owner, match_id, streak, pity = 0, salt = "crate", table = CRATES) -> Dictionary:
	var seed_value = ("0x" + str(owner + ":" + match_id + ":" + salt).sha256_text().substr(0, 7)).hex_to_int()
	var roll = float(seed_value % 10000) / 10000.0
	var luck = min(0.2, 0.02 * max(0, int(streak) - 1) + 0.04 * min(4, int(pity)))
	var tier = 0
	if roll >= 0.98 - luck * 0.2:
		tier = 3
	elif roll >= 0.88 - luck:
		tier = 2
	elif roll >= 0.60 - luck:
		tier = 1
	var low = int(table[tier][1])
	var high = int(table[tier][2])
	var amount = low + (int(seed_value / 10000) % int(max(1, high - low + 1)))
	return {"tier": tier, "name": str(table[tier][0]), "amount": int(round(amount / 50.0) * 50)}

# Daily Drops: a bigger crate on the 1st, 4th and 8th win of the day.
const DROP_WINS = [1, 4, 8]
const DROPS = [["Common", 1000, 1500], ["Rare", 2000, 3500], ["Epic", 4000, 6000], ["Legendary", 10000, 10000]]
static func wins_today(owner, saved, day) -> int:
	var count = 0
	for e in saved:
		if str(e.get("player_id", "")) == owner and str(e.get("reason", "")) == "Overall match victory" and str(e.get("win_day", "")) == str(day):
			count += 1
	return count

# Rested bonus: time away banks doubled matches (one per 8 hours, up to 3).
const RESTED_SECONDS = 28800
const RESTED_MAX = 3
func rested_awards(owner, match_id, saved, pending, now):
	var out = []
	var ids = {}
	for e in saved:
		ids[str(e.id)] = true
	var prefix = "match:" + match_id + ":"
	for e in saved + pending:
		if str(e.get("player_id", "")) != owner or not str(e.id).begins_with(prefix):
			continue
		var bonus_id = "rested:" + str(e.id)
		if ids.has(bonus_id):
			continue
		ids[bonus_id] = true
		out.append(entry(owner, bonus_id, e.category, "Rested 2x · " + str(e.reason), match_id, e.amount, now))
	return out

# After the streak has been updated for this match.
func win_awards(owner, match_id, winner, streak, previous_streak, saved, now, day, pity = 0):
	var out = []
	if owner.empty() or match_id.empty():
		return out
	var root = "match:" + match_id + ":"
	if not winner:
		if int(previous_streak) >= 3:
			out.append(entry(owner, root + "streak-ended", "win", "Win streak ended · %d wins" % int(previous_streak), match_id, min(1500, 150 * int(previous_streak)), now))
		return out
	if int(streak) >= 2:
		out.append(entry(owner, root + "streak-bonus", "win", "Win streak bonus · %d in a row" % int(streak), match_id, STREAK_STEP * min(int(streak) - 1, STREAK_STEP_CAP), now))
	var crate = crate_roll(owner, match_id, streak, pity)
	out.append(entry(owner, root + "crate", "win", "Win bonus · " + crate.name, match_id, crate.amount, now))
	var wins = wins_today(owner, saved, day) + 1
	if wins in DROP_WINS:
		var drop = crate_roll(owner, match_id, streak, pity, "drop", DROPS)
		var e = entry(owner, root + "daily-drop", "win", "Daily drop %d/3 · %s" % [DROP_WINS.find(wins) + 1, drop.name], match_id, drop.amount, now)
		e["drop_day"] = str(day)
		out.append(e)
	var first = true
	for e in saved:
		if str(e.get("player_id", "")) == owner and str(e.get("reason", "")) == "First win of the day" and str(e.get("win_day", "")) == str(day):
			first = false
			break
	if first:
		var bonus = entry(owner, root + "first-win", "win", "First win of the day", match_id, FIRST_WIN_XP, now)
		bonus["win_day"] = str(day)
		out.append(bonus)
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
	var won = entry(owner,"match:"+match_id+":win","win","Overall match victory",match_id,rewards.match_win,now)
	won["win_day"] = str(day)
	out.append(won)
	# Require the entire observed round sequence, not just a late-joined final.
	for number in range(1,highest+1):
		complete = complete and rounds.has(number)
	if complete and races>0:
		out.append(entry(owner,"match:"+match_id+":sweep","win","Clean sweep",match_id,rewards.clean_sweep,now))
	return out

# Called only after the local player is eliminated or the match ends. Bonuses
# and their slot metadata share the ledger's atomic transaction; no second save
# can drift out of sync. Only newly observed completions consume daily slots.
func daily_awards(owner, match_id, saved, pending, now, day):
	if owner.empty() or match_id.empty():
		return []
	var used = {}
	var slot = 0
	var assigned_day = day
	var ids = {}
	for e in saved:
		ids[str(e.id)] = true
		if e.get("player_id","")!=owner or not e.has("daily_match_day"):
			continue
		if str(e.daily_match_day)==day:
			used[str(e.related_id)] = true
		if str(e.related_id)==match_id:
			slot = int(e.get("daily_match_slot",0))
			assigned_day = str(e.daily_match_day)
	if slot==0:
		if used.size()>=10:
			return []
		slot = used.size()+1
	var out = []
	var prefix = "match:"+match_id+":"
	# Previously committed round XP is included, but never historical matches,
	# quest claims, achievement tiers, streak rewards or world records.
	for e in saved+pending:
		if e.get("player_id","")!=owner or not str(e.id).begins_with(prefix):
			continue
		var bonus_id = "daily-double:"+str(e.id)
		if ids.has(bonus_id):
			continue
		ids[bonus_id] = true
		var bonus = entry(owner,bonus_id,e.category,"Daily 2x (%d/10) · %s" % [slot,e.reason],match_id,e.amount,now)
		bonus["daily_match_day"] = assigned_day
		bonus["daily_match_slot"] = slot
		out.append(bonus)
	return out
