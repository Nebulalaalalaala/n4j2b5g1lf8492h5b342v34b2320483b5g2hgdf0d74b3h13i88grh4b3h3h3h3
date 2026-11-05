extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Roles = preload("user://mod/core/workspace4/ClientRoles.gd")
signal changed
var badges
var next_refresh = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var script = ModPaths.try_load("user://mod/core/workspace4/identity/ClientBadges.gd")
	if script==null or not script.can_instance(): return
	badges = script.new()
	add_child(badges)
	badges.connect("changed",self,"_changed")

func lookup(ids: Array):
	if not is_instance_valid(badges) or ids.empty(): return
	# Reuse existing read-only SQL catalogue/awards. The regular Journey
	# profile cache is untouched; only this small active-player cache refreshes.
	var now = OS.get_unix_time()
	if now>=next_refresh:
		next_refresh = now+60
		badges.refresh_catalog()
	badges.lookup(ids.slice(0,min(31,ids.size()-1)))

func roles_for(user_id: String) -> Array:
	if not is_instance_valid(badges): return []
	var row = badges._awards.get(badges.player_key(user_id),{})
	if row.empty() or OS.get_unix_time()-int(row.get("at",0))>=600: return []
	return Roles.roles(badges.badges_for(user_id))

func _changed(): emit_signal("changed")
