extends "user://mod/tools/journey/ui/JourneyUI/02_chart_medal.gd"

# JourneyUI is split into feature files (see the JourneyUI/ folder). This file only
# closes the chain so the loader and other scripts keep using the same path.

func _init(journey_art):
	art = journey_art
	_baloo_data = load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
	var inter_path = ModPaths.MAIN_FONT
	if File.new().file_exists(inter_path):
		_inter_data = DynamicFontData.new()
		_inter_data.font_path = inter_path
