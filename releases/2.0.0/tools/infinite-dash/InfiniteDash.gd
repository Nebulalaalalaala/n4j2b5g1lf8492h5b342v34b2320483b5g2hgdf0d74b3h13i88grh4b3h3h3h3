extends Reference

# Infinite dash (an Advanced tool): keeps the local player's dash cooldown at zero.
# Game tools shows the "Infinite dash" card only when this file is installed.

static func apply(tas_tool) -> void:
	if tas_tool == null or not is_instance_valid(tas_tool):
		return
	var player = tas_tool.call("_get_local_player")
	if player == null or not is_instance_valid(player):
		return
	if not ("dash_cooldown" in player):
		return
	if int(player.dash_cooldown) == 0:
		return
	player.dash_cooldown = 0
