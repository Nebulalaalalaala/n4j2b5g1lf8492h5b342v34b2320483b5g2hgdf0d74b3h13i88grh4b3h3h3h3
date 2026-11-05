extends "res://project_specific/ui/UIPlayerProfileDialog.gd"
const ModPaths = preload("user://mod/core/ModPaths.gd")

var profile_service = null
var profile_user_id := ""

func show_player_profile_dialog(user_id: String):
	profile_user_id = user_id
	.show_player_profile_dialog(user_id)

func populate_stats(values):
	# Native populate_stats appends rows. Refreshing an already-open profile
	# must not nest old Profile+ panels or duplicate the previous stat rows.
	for child in stats_list_container.get_children():
		if child != stats_row_template:
			stats_list_container.remove_child(child)
			child.queue_free()
	.populate_stats(values)
	var journey_available = profile_service != null and is_instance_valid(profile_service.journey) and profile_service.journey.has_screen()
	if profile_service != null and profile_service.store != null and profile_user_id == profile_service.store.account_id and not profile_user_id.empty() and not journey_available:
		var panel = load(get_script().resource_path.get_base_dir().plus_file("ProfilePanel.gd")).new()
		panel.service = profile_service
		panel.profile = self
		stats_list_container.add_child(panel)
		panel.build()
		call_deferred("_apply_studio_look")

func populate_awards(p):
	.populate_awards(p)
	# Journey rank, featured badges and custom badges: yours from the Journey
	# screen, other Goobplayability players' from their leaderboard row.
	var journey = profile_service.get("journey") if profile_service != null else null
	if journey == null or not is_instance_valid(journey) or profile_user_id.empty():
		return
	_show_journey()
	for source in [journey.get("looks"), journey.get("custom_badges")]:
		if source == null:
			continue
		var signal_name = "looked_up" if source.has_signal("looked_up") else "changed"
		if not source.is_connected(signal_name, self, "_show_journey"):
			source.connect(signal_name, self, "_show_journey")
		if not source.has_fresh(profile_user_id):
			source.lookup([profile_user_id])

func _own_profile() -> bool:
	return profile_service.store != null and profile_user_id == profile_service.store.account_id

func _show_journey():
	var journey = profile_service.get("journey") if profile_service != null else null
	if not is_inside_tree() or journey == null or not is_instance_valid(journey) or profile_user_id.empty():
		return
	var custom = journey.custom_badges.badges_for(profile_user_id) if journey.get("custom_badges") != null else []
	var section = award_medal_grid_container.get_parent()
	var badges = load(ModPaths.JOURNEY_PROFILE_BADGES)
	if _own_profile():
		if is_instance_valid(journey.screen):
			badges.own(section, journey.screen, custom)
		return
	var look = journey.looks.look(profile_user_id) if journey.get("looks") != null else null
	if look == null and custom.empty():
		return
	var ui = journey.screen.ui if is_instance_valid(journey.screen) else load(ModPaths.path("JourneyUI.gd")).new(load(ModPaths.path("JourneyArt.gd")).new())
	badges.other(section, ui, look, custom)

func _apply_studio_look() -> void:
	if profile_service.tool == null or not is_instance_valid(profile_service.tool):
		return
	var sandbox = profile_service.tool.get("_cosmetic_sandbox")
	if sandbox != null and is_instance_valid(sandbox):
		sandbox.call("_apply_to_goober", goober, sandbox.call("_build_local_skin"))
