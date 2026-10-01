extends Control
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Data = preload("user://mod/tools/journey/ui/JourneyMomentData.gd")
var controller
var ui
var definitions
var card
var rank_name
var rank_badge
var progress
var progress_text
var next_text
var daily
var pin_row
var pin_title
var pin_detail
var signature = ""
var daily_signature = ""
var remaining = 10
var trigger
var expanded = false
var owner_id = ""

func _ready():
	name = "JourneyHomeStats"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	ui = load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
	trigger = ui.button(self, "Journey", "quiet", self, "toggle_panel", null, "chevron_right")
	trigger.name = "StatsDropdown"
	trigger.add_font_override("font", ui.font("display", 42))
	trigger.rect_min_size = Vector2(360, 90)
	trigger.hint_tooltip = "Open Journey stats"
	trigger.toggle_mode = true
	card = ui.card(self, ui.NAVY, 38, 44)
	card.hide()
	var col = ui.box(card, true, 20)
	var heading = ui.box(col, false, 14)
	ui.image(heading, "journey", 40)
	ui.label(heading, "JOURNEY", "caps", ui.SKY_LIGHT)
	var rank_row = ui.box(col, false, 24)
	rank_badge = ui.badge(rank_row, definitions.rank_at(0), 120)
	var rank_col = ui.grow(ui.box(rank_row, true, 5))
	rank_name = ui.label(rank_col, "", "h1")
	progress_text = ui.label(rank_col, "", "body", ui.MUTED)
	progress = ui.bar(col, 0, ui.YELLOW, 32)
	next_text = ui.label(col, "", "body", ui.SKY_LIGHT)
	var bonus = ui.well(col, ui.NAVY_2, 20, 24)
	var bonus_row = ui.box(bonus, false, 14)
	ui.icon(bonus_row, "sparkle", 40, ui.YELLOW)
	daily = ui.grow(ui.label(bonus_row, "", "h3", ui.YELLOW))
	pin_row = ui.box(col, false, 16)
	ui.icon(pin_row, "pin", 34, ui.MUTED)
	var pins = ui.grow(ui.box(pin_row, true, 4))
	pin_title = ui.label(pins, "", "h3")
	pin_detail = ui.label(pins, "", "small", ui.MUTED)
	connect("resized", self, "_fit")
	_fit()
	refresh()

func _fit():
	if card == null or rect_size.x < 100 or rect_size.y < 100:
		return
	# Native UI uses a 1920px-tall canvas. Keep the card left of Play and the
	# avatar, below the identity bar, without changing either native control.
	var width = min(1020.0, rect_size.x * 0.31)
	if rect_size.x < 2300:
		width = min(940.0, rect_size.x - 100)
	trigger.rect_position = Vector2(90, max(250, rect_size.y * 0.15))
	trigger.rect_size = trigger.rect_min_size
	card.rect_position = trigger.rect_position + Vector2(0, trigger.rect_size.y + 18)
	card.rect_size = Vector2(width, 0)
	# For portrait/narrow native layouts place compact stats above Play.
	var factor = min(1.0, width / 940.0)
	if rect_size.x < 2300:
		factor = min(factor, 0.75)
	card.rect_scale = Vector2(factor, factor)
	card.rect_size.x = width / factor

func refresh():
	if not is_instance_valid(controller) or controller.ledger == null:
		return
	var ledger = controller.ledger
	if owner_id != str(ledger.account_id):
		owner_id = str(ledger.account_id)
		_set_expanded(false)
	visible = not owner_id.empty() and bool(Data.preference(self, controller, "home_stats", true))
	if not visible:
		_set_expanded(false)
		return
	var day = str(int(floor(float(OS.get_unix_time() + int(OS.get_time_zone_info().get("bias", 0)) * 60) / 86400.0)))
	var key = "%s:%s:%s" % [ledger.account_id, ledger.revision, day]
	if key != daily_signature:
		daily_signature = key
		remaining = Data.daily_remaining(ledger.entries, ledger.account_id, day)
	var pins = []
	var xp = int(ledger.total_xp)
	var screen = controller.screen
	if is_instance_valid(screen) and screen.journey_store != null and screen.journey_store.account_id == ledger.account_id:
		# Reuse Journey's existing admin preview offset, if one is deliberately set.
		xp += int(screen.journey_store.test.get("xp", 0))
		var selected = screen.model.get("pins", []) if not screen.model.get("preview", false) else []
		if selected is Array:
			pins = selected
	var state = "%s:%s:%s" % [key, xp, JSON.print(pins)]
	if state == signature:
		return
	signature = state
	var rank = definitions.rank_at(xp)
	var next = definitions.rank_at(int(rank.next_xp))
	var league = ui.league(rank)
	rank_name.text = str(rank.name).to_upper()
	var badge = rank_badge.get_child(0)
	badge.texture = ui.art.texture(str(rank.art))
	badge.text = str(rank.division)
	badge.pips = 0 if str(rank.league) == "King League" else int(rank.id) % 3 + 1
	badge.text_color = ui.INK if str(rank.league) == "King League" else ui.WHITE
	badge.pip_color = league.base
	badge.update()
	var span = max(1, int(rank.next_xp) - int(rank.xp))
	progress.fill = league.base
	progress.ratio = float(xp - int(rank.xp)) / span
	progress_text.text = "%s / %s XP" % [ui.thousands(max(0, xp - int(rank.xp))), ui.thousands(span)]
	next_text.text = "%s XP to %s" % [ui.thousands(max(0, int(rank.next_xp) - xp)), next.name]
	daily.text = "2x XP  ·  %d games left today" % remaining if remaining > 0 else "Daily bonus complete"
	pin_row.visible = not pins.empty()
	if not pins.empty():
		pin_title.text = str(pins[0].name)
		pin_detail.text = str(pins[0].next)

func toggle_panel():
	_set_expanded(not expanded)
	if expanded:
		refresh()
		_fit()
	if is_instance_valid(controller.screen):
		controller.screen.play("click")

func _set_expanded(value):
	expanded = bool(value)
	if card != null:
		card.visible = expanded
	if trigger != null:
		trigger.pressed = expanded
		trigger.icon = ui.art.texture("icon_chevron_down" if expanded else "icon_chevron_right")
		trigger.hint_tooltip = "Close Journey stats" if expanded else "Open Journey stats"

func _unhandled_key_input(event):
	if expanded and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		_set_expanded(false)
		get_tree().set_input_as_handled()
