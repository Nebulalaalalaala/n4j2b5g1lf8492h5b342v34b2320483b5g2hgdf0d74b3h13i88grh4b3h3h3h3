extends "user://mod/tools/journey/ui/JourneyPages/00_state.gd"

# Placeholders for functions that live in a later file of the JourneyPages chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _map_items() -> Array:
	return []

func _tname(c, i) -> String:
	return ""

func _thr(c, i) -> int:
	return 0

func _finish_reward_card(parent, finish):
	return null

func _upcoming(parent):
	return null

func _fill_records():
	return null
