extends Reference

# Authoritative Journey progression config. UI and ledger code read ranks only
# through rank_at/roadmap/finite_ranks/king_threshold; never copy thresholds.
# Initial proposed curve (XP Scaling spec); rebalance by editing these values.
# The 18 costs sum to 817,500 XP for King League 1 (the spec text says 817,000).
# Native account level/XP is never touched.
const LEAGUES = ["Bronze","Silver","Gold","Ruby","Sapphire","Master"]
const DIVISIONS = ["I","II","III"]
# Additional XP to leave each division, Bronze I -> Master III (18 values).
const DEFAULT_COSTS = [6000,7500,9000, 11000,13500,16000, 19500,23500,28000, 34000,40500,48000, 58000,69000,82000, 98000,116000,138000]
# King League N -> N+1 costs KING_BASE + KING_STEP*(N-1) + KING_CURVE*(N-1)^2.
const KING_DEFAULT = [150000,25000,2500]
# Keeps every King threshold below the 64-bit int limit (~6.7e18 XP at the cap).
const KING_MAX = 200000
const REWARDS = {"participation":200,"race_finish":500,"podium":400,"match_win":800,"race_first":100,"clean_sweep":500,"discovery":200,"first_world_record":2500}
const ACTIVITY_SECONDS = [1800,3600,7200,10800,14400]
const ACTIVITY_XP = [250,750,1500,2500,3500]
var costs = DEFAULT_COSTS.duplicate()
var king = KING_DEFAULT.duplicate()

func configure(values: Array, king_values: Array) -> bool:
	if values.size()!=18 or king_values.size()!=3:
		return false
	for value in values+king_values:
		if not typeof(value) in [TYPE_INT,TYPE_REAL] or is_nan(float(value)) or is_inf(float(value)) or value!=floor(value) or value<0 or value>100000000:
			return false
	for value in values:
		if value<=0:
			return false
	if king_values[0]<=0:
		return false
	costs = []
	for value in values:
		costs.append(int(value))
	king = []
	for value in king_values:
		king.append(int(value))
	return true

func finite_ranks() -> Array:
	var result = []
	var threshold = 0
	for i in range(18):
		var league = LEAGUES[int(i/3)]
		var division = DIVISIONS[i%3]
		result.append({"id":i,"league":league,"division":division,"name":league+" "+division,"xp":threshold,"next_xp":threshold+int(costs[i]),"art":league.to_lower()})
		threshold += int(costs[i])
	return result

func king_start() -> int:
	var total = 0
	for value in costs:
		total += int(value)
	return total

# Lifetime XP at which King League number begins (closed form, integer-safe).
func king_threshold(number: int) -> int:
	var m = int(clamp(number,1,KING_MAX))-1
	var squares = 0
	if m>1:
		squares = (m-1)*m*(2*m-1)/6
	return king_start()+int(king[0])*m+int(king[1])*(m*(m-1)/2)+int(king[2])*squares

func king_rank(number: int) -> Dictionary:
	number = int(clamp(number,1,KING_MAX))
	return {"id":17+number,"league":"King League","division":str(number),"name":"King League "+str(number),"xp":king_threshold(number),"next_xp":king_threshold(number+1),"art":"king"}

func rank_at(xp: int) -> Dictionary:
	xp = max(0,xp)
	for rank in finite_ranks():
		if xp < rank.next_xp:
			return rank
	# Largest King number whose threshold is <= xp.
	var low = 1
	var high = KING_MAX
	while low<high:
		var mid = int((low+high+1)/2)
		if king_threshold(mid)<=xp:
			low = mid
		else:
			high = mid-1
	return king_rank(low)

func roadmap(xp: int) -> Array:
	var result = finite_ranks()
	var current = rank_at(xp)
	var center = max(1,int(current.division)) if current.league=="King League" else 1
	for number in range(max(1,center-2),center+4):
		result.append(king_rank(number))
	return result
