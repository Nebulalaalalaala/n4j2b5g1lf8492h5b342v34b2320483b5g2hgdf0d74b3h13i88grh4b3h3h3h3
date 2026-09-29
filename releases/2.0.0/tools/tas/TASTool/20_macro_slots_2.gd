extends "user://mod/tools/tas/TASTool/19_macro_slots_1.gd"

func _build_practice_macro_slot_card(slot: int) -> PanelContainer:
	var card: = PanelContainer.new()
	card.add_stylebox_override("panel", _make_flat_style(COLOR_SLOT_EMPTY, COLOR_WHITE, 3, 16))
	card.rect_min_size = Vector2(220, 184)

	var vb: = VBoxContainer.new()
	vb.add_constant_override("separation", 3)
	card.add_child(vb)

	vb.add_child(_make_label("MACRO %d" % slot, _body_font, COLOR_WHITE))
	var status_label: = _make_label("Empty", _body_font, COLOR_TEXT_DIM)
	vb.add_child(status_label)
	_practice_macro_slot_status_labels.append(status_label)

	var row: = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	var save_btn: = _make_button("Save", COLOR_BLUE, 58)
	save_btn.rect_min_size.y = 42
	save_btn.connect("pressed", self, "_on_save_practice_macro_slot_pressed", [slot])
	row.add_child(save_btn)
	var load_btn: = _make_button("Load", COLOR_BLUE, 58)
	load_btn.rect_min_size.y = 42
	load_btn.disabled = true
	load_btn.connect("pressed", self, "_on_load_practice_macro_slot_pressed", [slot])
	row.add_child(load_btn)
	_practice_macro_slot_load_buttons.append(load_btn)
	var delete_btn: = _make_button("✕", COLOR_PINK_DARK, 46)
	delete_btn.rect_min_size.y = 42
	delete_btn.disabled = true
	delete_btn.connect("pressed", self, "_on_delete_practice_macro_slot_pressed", [slot])
	row.add_child(delete_btn)
	_practice_macro_slot_delete_buttons.append(delete_btn)
	vb.add_child(row)
	var edit_btn: = _make_button("EDIT TIMELINE", COLOR_PURPLE, 0)
	edit_btn.rect_min_size.y = 42
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.disabled = true
	edit_btn.hint_tooltip = "Open the detailed frame/input timeline editor"
	edit_btn.connect("pressed", self, "_on_edit_practice_macro_slot_pressed", [slot])
	vb.add_child(edit_btn)
	_practice_macro_slot_edit_buttons.append(edit_btn)
	var continue_btn = _make_button("CONTINUE FROM END",COLOR_BLUE,0)
	continue_btn.rect_min_size.y = 42
	continue_btn.disabled = not _practice_macro_slots.has(slot)
	continue_btn.hint_tooltip = "Re-simulate in the CURRENT local level (open your edited copy first), then record new inputs. From menus, opens the saved level link. Stops on death; never overwrites a slot. Edit Timeline chooses an earlier point."
	continue_btn.connect("pressed",self,"_on_continue_saved_macro_pressed",[slot])
	vb.add_child(continue_btn)
	_practice_continue_buttons[slot] = continue_btn

	# A separate full-width launch action keeps the destructive delete icon
	# away from Play and gives the requested one-click workflow a clear visual
	# hierarchy. Reuse Goober Dash's own white play asset so it fits the game's
	# visual language instead of introducing an unrelated icon style.
	var play_btn: = _make_button("PLAY LEVEL", COLOR_PLAY_GREEN, 0)
	var play_icon = load("res://project_specific/gfx/icons/icon_play.png")
	if play_icon != null:
		play_btn.icon = play_icon
		play_btn.expand_icon = true
	else:
		play_btn.text = "▶  PLAY LEVEL"
	play_btn.rect_min_size.y = 44
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.disabled = true
	play_btn.hint_tooltip = "Open this macro's saved level and start playback automatically"
	play_btn.connect("pressed", self, "_on_play_saved_practice_macro_slot_pressed", [slot])
	vb.add_child(play_btn)
	_practice_macro_slot_play_buttons.append(play_btn)

	return card
