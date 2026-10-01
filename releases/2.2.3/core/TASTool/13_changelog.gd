extends "user://mod/core/TASTool/12_action_log.gd"

# What's new: shown once per version, a short note in the Workspace menu's style.
const WHATS_NEW := [
	"Avatar Studio: layer hats and bodies, select multiple emotes, and edit local Goober size.",
	"Pan the Studio preview by dragging empty space or middle-dragging; Reset recenters.",
	"Studio size percentages are readable and accept typed values reliably.",
	"Studio emotes now work with the local emote wheel and its paging.",
	"Settings: customize tool shortcuts; TAS Undo Last defaults to Ctrl+Alt+U.",
	"Journey badges use native selection rings and titles; Inbox only keeps the original pills.",
]

func _show_changelog_if_needed() -> void:
	var seen_version := str(SavedSettings.get_value(SETTING_CHANGELOG_VERSION, ""))
	if seen_version == GOOBPLAYABILITY_VERSION:
		return
	SavedSettings.set_value(SETTING_CHANGELOG_VERSION, GOOBPLAYABILITY_VERSION)
	# Brand-new players get the introduction instead.
	var onboarding = ModPaths.try_load(ModPaths.path("Onboarding.gd"))
	if onboarding != null and not onboarding.seen("tour"):
		return
	_show_whats_new()


func _show_whats_new() -> void:
	if _tool_popup_layer != null and is_instance_valid(_tool_popup_layer):
		_tool_popup_layer.queue_free()
	_tool_popup_layer = CanvasLayer.new()
	_tool_popup_layer.layer = 260
	_tool_popup_layer.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(_tool_popup_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.025, 0.08, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_tool_popup_layer.add_child(shade)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("181c20")
	style.border_color = Color("343c40")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	for side in ["left", "right"]:
		style.set("content_margin_" + side, 28)
	for side in ["top", "bottom"]:
		style.set("content_margin_" + side, 22)
	panel.add_stylebox_override("panel", style)
	_tool_popup_layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "What's new in %s" % GOOBPLAYABILITY_VERSION
	title.add_font_override("font", _make_font(24))
	title.add_color_override("font_color", Color("f0f1eb"))
	column.add_child(title)
	for line in WHATS_NEW:
		var entry := Label.new()
		entry.text = "\u2022  " + line
		entry.autowrap = true
		entry.rect_min_size.x = 560
		entry.add_font_override("font", _make_font(17))
		entry.add_color_override("font_color", Color("c9d1d3"))
		column.add_child(entry)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_END
	column.add_child(row)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.add_font_override("font", _make_font(17))
	close.add_color_override("font_color", Color("181c20"))
	close.add_color_override("font_color_hover", Color("181c20"))
	for state in ["normal", "hover", "pressed"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("9dd6bd") if state == "normal" else Color("b4e2ce")
		button_style.set_corner_radius_all(8)
		button_style.content_margin_left = 18
		button_style.content_margin_right = 18
		button_style.content_margin_top = 6
		button_style.content_margin_bottom = 6
		close.add_stylebox_override(state, button_style)
	close.connect("pressed", self, "_close_tool_popup")
	row.add_child(close)
	# Centred on screen at the menu's scale (a scaled panel isn't centred by containers).
	var scale := get_gui_scale_factor()
	panel.rect_scale = Vector2.ONE * scale
	panel.rect_size = Vector2.ZERO
	var view: Vector2 = get_viewport().get_visible_rect().size
	panel.rect_position = ((view - panel.get_combined_minimum_size() * scale) * 0.5).floor()
