extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# "JOURNEY BADGES:" on a GooberDash profile, laid out like the native MEDALS
# EARNED section right above it: the same title label (duplicated, so it keeps
# the game's SDF font) and a grid of 134 px icons. Shows the Journey rank and
# the player's featured badges (up to three).
const SIZE = 134
# The medal art has a transparent margin; drawn a bit larger to match native medals.
const ART = 160

# Your own profile, from the Journey screen's model.
static func own(medals_section, screen, custom = []) -> void:
	if not is_instance_valid(screen) or screen.model.empty():
		return
	var m = screen.model
	var badges = []
	if m.get("achievements") != null:
		for key in m.achievements.get("featured", []):
			for c in m.achievements.collections:
				if c.key == key and int(c.tier) > 0:
					badges.append({"key": c.key, "tier": int(c.tier)})
	attach(medals_section, screen.ui, m.get("rank"), badges, custom)

# Another player's profile, from their looked-up row (JourneyLooks).
# look is null for a player who has only custom badges.
static func other(medals_section, ui, look, custom = []) -> void:
	var definitions = load(ModPaths.path("JourneyDefinitions.gd")).new()
	var rank = definitions.rank_at(int(look.get("xp", 0))) if look != null else null
	attach(medals_section, ui, rank, look.get("badges", []) if look != null else [], custom)

# custom: badges from the admin tools (JourneyCustomBadges), shown after the featured ones.
static func attach(medals_section, ui, rank, badges: Array, custom = []) -> void:
	if medals_section == null or not is_instance_valid(medals_section) or ui == null:
		return
	var list = medals_section.get_parent()
	var old = list.get_node_or_null("JourneySection")
	if old != null:
		list.remove_child(old)
		old.queue_free()
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
	if rank != null:
		ui.badge(_cell(grid, "Journey rank · " + str(rank.name)), rank, ART)
	var achievements = load(ModPaths.path("JourneyAchievements.gd"))
	for b in badges:
		for c in achievements.COLLECTIONS:
			if c[0] == str(b.key):
				var tier = int(b.tier)
				var cell = _cell(grid, "%s · %s" % [c[1], achievements.tier_name(tier)])
				ui.medal(cell, int(clamp(tier - 1, 0, 5)), c[3], ART)
	for c in custom:
		var tip = str(c.name) + (" · " + str(c.detail) if not str(c.get("detail", "")).empty() else "")
		ui.medal(_cell(grid, tip), int(c.frame), str(c.emblem), ART)

static func _cell(grid, tip):
	var cell = CenterContainer.new()
	cell.rect_min_size = Vector2(ART, SIZE)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.hint_tooltip = tip
	grid.add_child(cell)
	return cell
