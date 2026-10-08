extends "user://mod/tools/journey/ui/JourneyPages/07_pref_tool.gd"

# JourneyPages is split into feature files (see the JourneyPages/ folder). This file only
# closes the chain so the loader and other scripts keep using the same path.

func _init(owner, design):
	screen = owner
	ui = design
