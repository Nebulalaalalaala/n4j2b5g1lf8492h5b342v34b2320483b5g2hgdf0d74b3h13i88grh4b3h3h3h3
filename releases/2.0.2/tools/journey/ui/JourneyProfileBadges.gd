extends Reference

# "JOURNEY BADGES:" on the player's own profile, laid out like the native
# MEDALS EARNED section right above it: the same title label (duplicated, so it
# keeps the game's SDF font) and a 6-column grid of 134 px icons. Shows the
# Journey rank, then featured badges, then every other earned badge.
const SIZE = 134
# The medal art has a transparent margin; drawn a bit larger to match native medals.
const ART = 160

static func attach(medals_section, screen) -> void:
	if medals_section == null or not is_instance_valid(screen) or screen.model.empty():
		return
	var list = medals_section.get_parent()
	var old = list.get_node_or_null("JourneySection")
	if old != null:
		list.remove_child(old)
		old.queue_free()
	var m = screen.model
	var ui = screen.ui
	var section = VBoxContainer.new()
	section.name = "JourneySection"
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_constant_override("separation", 20)
	list.add_child(section)
	list.move_child(section, medals_section.get_index() + 1)
	var native_title = medals_section.get_child(0)
	if native_title is Label:
		var title = native_title.duplicate()
		title.text = "JOURNEY BADGES:"
		section.add_child(title)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_constant_override("hseparation", 4)
	grid.add_constant_override("vseparation", 4)
	section.add_child(grid)
	if m.get("rank") != null:
		var cell = _cell(grid, "Journey rank · " + str(m.rank.name))
		ui.badge(cell, m.rank, ART)
	if m.get("achievements") == null:
		return
	var featured = screen.journey_store.featured if screen.journey_store != null else []
	var earned = []
	for c in m.achievements.collections:
		if int(c.tier) > 0 and not c.get("unsupported", false):
			earned.append(c)
	earned.sort_custom(Order.new(featured), "before")
	for c in earned:
		var tier = int(c.tier)
		var names = c.get("tier_names", [])
		var tier_name = str(names[tier - 1]) if tier - 1 < names.size() else "Kingly"
		var cell = _cell(grid, "%s · %s" % [str(c.name), tier_name])
		ui.medal(cell, int(clamp(tier - 1, 0, 5)), c.emblem, ART)

static func _cell(grid, tip):
	var cell = CenterContainer.new()
	cell.rect_min_size = Vector2(ART, SIZE)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.hint_tooltip = tip
	grid.add_child(cell)
	return cell

class Order:
	var featured = []
	func _init(list):
		featured = list
	func before(a, b) -> bool:
		var fa = featured.has(a.key)
		var fb = featured.has(b.key)
		if fa != fb:
			return fa
		return int(a.tier) > int(b.tier)
