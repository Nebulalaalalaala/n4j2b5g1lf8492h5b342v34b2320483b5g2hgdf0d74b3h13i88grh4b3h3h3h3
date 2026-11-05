extends "user://mod/tools/tas/TASTool/19_macro_slots_1.gd"

# One saved-macro slot as a row: name and level on the left, actions on the
# right. Same buttons, handlers, slot arguments and reference arrays as before.
func _build_practice_macro_slot_card(slot: int) -> PanelContainer:
	var card: = PanelContainer.new()
	card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, COLOR_WHITE, 3, 16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.rect_min_size = Vector2(0, 60)

	var row_root: = HBoxContainer.new()
	row_root.add_constant_override("separation", 12)
	card.add_child(row_root)

	# 4.0: slot number in a small round badge.
	var badge: = PanelContainer.new()
	var badge_style = load("user://mod/core/workspace4/Galaxy.gd").box(load("user://mod/core/workspace4/Galaxy.gd").color("hover"), load("user://mod/core/workspace4/Galaxy.gd").color("line"), 0, 17)
	badge_style.content_margin_top = 0
	badge_style.content_margin_bottom = 0
	badge.add_stylebox_override("panel", badge_style)
	badge.rect_min_size = Vector2(34, 34)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_label: = _make_label("%d" % slot, _body_font, COLOR_WHITE)
	badge_label.align = Label.ALIGN_CENTER
	badge_label.valign = Label.VALIGN_CENTER
	badge.add_child(badge_label)
	row_root.add_child(badge)

	var info: = VBoxContainer.new()
	info.add_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row_root.add_child(info)
	var status_label: = _make_label("Empty", _body_font, COLOR_TEXT_DIM)
	status_label.clip_text = true
	info.add_child(status_label)
	_practice_macro_slot_status_labels.append(status_label)

	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row_root.add_child(row)

	# A separate launch action keeps the destructive delete icon away from
	# Play. Reuse Goober Dash's own white play asset.
	var play_btn: = _make_small_button("Play level", COLOR_PLAY_GREEN, 130)
	var play_icon = load("res://project_specific/gfx/icons/icon_play.png")
	if play_icon != null:
		play_btn.icon = play_icon
		play_btn.expand_icon = true
	play_btn.disabled = true
	play_btn.hint_tooltip = "Open this macro's saved level and start playback automatically"
	play_btn.connect("pressed", self, "_on_play_saved_practice_macro_slot_pressed", [slot])

	var load_btn: = _make_small_button("Load", COLOR_BLUE, 74)
	load_btn.disabled = true
	load_btn.hint_tooltip = "Replace the working run with this saved macro."
	load_btn.connect("pressed", self, "_on_load_practice_macro_slot_pressed", [slot])
	row.add_child(load_btn)
	_practice_macro_slot_load_buttons.append(load_btn)

	var edit_btn: = _make_small_button("Timeline", COLOR_PURPLE, 100)
	edit_btn.disabled = true
	edit_btn.hint_tooltip = "Open the detailed frame/input timeline editor"
	edit_btn.connect("pressed", self, "_on_edit_practice_macro_slot_pressed", [slot])
	row.add_child(edit_btn)

	var continue_btn = _make_small_button("Continue", COLOR_BLUE, 100)
	continue_btn.disabled = not _practice_macro_slots.has(slot)
	continue_btn.hint_tooltip = "Continue from end: re-simulate in the CURRENT local level (open your edited copy first), then record new inputs. From menus, opens the saved level link. Stops on death; never overwrites a slot. Timeline chooses an earlier point."
	continue_btn.connect("pressed",self,"_on_continue_saved_macro_pressed",[slot])
	row.add_child(continue_btn)
	_practice_continue_buttons[slot] = continue_btn

	var save_btn: = _make_small_button("Save here", COLOR_BLUE, 104)
	save_btn.hint_tooltip = "Save the working run into slot %d." % slot
	save_btn.connect("pressed", self, "_on_save_practice_macro_slot_pressed", [slot])
	row.add_child(save_btn)

	var delete_btn: = _make_small_button("", COLOR_PINK_DARK, 46)
	delete_btn.icon = load("user://mod/core/workspace4/Galaxy.gd").icon("trash", Color(1, 1, 1), 18)
	delete_btn.disabled = true
	delete_btn.hint_tooltip = "Delete the macro saved in slot %d." % slot
	delete_btn.connect("pressed", self, "_on_delete_practice_macro_slot_pressed", [slot])
	_practice_macro_slot_delete_buttons.append(delete_btn)
	_practice_macro_slot_edit_buttons.append(edit_btn)

	row.add_child(play_btn)
	row.add_child(delete_btn)
	_practice_macro_slot_play_buttons.append(play_btn)

	return card
