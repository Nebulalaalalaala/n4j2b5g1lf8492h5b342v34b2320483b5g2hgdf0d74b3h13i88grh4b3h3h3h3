extends Reference

static func clean(raw,limit=100) -> Array:
	var result=[]
	var seen={}
	if not raw is Array: return result
	for entry in raw:
		if not entry is Dictionary: continue
		var id=str(entry.get("id","")).strip_edges()
		var name=str(entry.get("name",entry.get("username",""))).replace("\r"," ").replace("\n"," ").strip_edges().left(80)
		if id.empty() or id.length()>100 or name.empty() or seen.has(id): continue
		seen[id]=true
		result.append({"id":id,"name":name})
		if result.size()>=limit: break
	return result

static func identity(game,object_id) -> Dictionary:
	if not is_instance_valid(game): return {}
	var data=game.get_metadata_for_player(object_id)
	if not data is Dictionary: return {}
	var id=str(data.get("uuid",""))
	var name=str(data.get("name",""))
	return {"id":id,"name":name} if not id.empty() and not name.empty() else {}

static func candidates(owner) -> Array:
	var result=[]
	if not is_instance_valid(owner): return result
	var game=owner.call("_find_game")
	if is_instance_valid(game):
		for index in game.get_player_count():
			var player=game.get_player_at_index(index)
			if player!=null and not game.is_local_player(player.object_id): result.append(identity(game,player.object_id))
	var wins=owner.get("_wins_leaderboard")
	if is_instance_valid(wins):
		for row in wins._snapshots.get(wins._latest_snapshot_key(),{}).get("rows",[]): result.append({"id":str(row.get("id","")),"name":str(row.get("username",""))})
	return clean(result,10000)

static func search(rows,query) -> Array:
	query=str(query).strip_edges().to_lower()
	var prefix=[]
	var substring=[]
	for row in rows:
		var name=str(row.name).to_lower()
		if query.empty() or name.begins_with(query): prefix.append(row)
		elif query in name: substring.append(row)
	var result=prefix+substring
	return result.slice(0,min(11,result.size()-1)) if not result.empty() else []
