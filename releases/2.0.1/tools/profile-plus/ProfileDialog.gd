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
	if profile_service!=null and not profile_user_id.empty() and not stats_list_container.has_node("RecordedGames"):
		var recordings = Button.new()
		recordings.name = "RecordedGames"
		recordings.text = "Game recordings"
		recordings.hint_tooltip = "Open locally recorded matches containing this account. Older recordings without account IDs cannot be linked reliably."
		recordings.rect_min_size.y = 40
		# The name label's font is an SDF font that only renders with its SDF
		# material; on a plain Button it drew as coloured squares.
		var face = DynamicFont.new()
		face.font_data = load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
		face.size = 22
		face.use_filter = true
		recordings.add_font_override("font",face)
		var style = StyleBoxFlat.new()
		style.bg_color = Color("244f66")
		style.set_corner_radius_all(6)
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		for state in ["normal","hover","pressed"]:
			recordings.add_stylebox_override(state,style)
		recordings.connect("pressed",self,"_open_recorded_games")
		stats_list_container.add_child(recordings)
		stats_list_container.move_child(recordings,0)

func populate_awards(p):
	.populate_awards(p)
	# Journey badges on the signed-in player's own profile (read-only).
	if profile_service == null or profile_service.store == null or profile_user_id.empty() or profile_user_id != profile_service.store.account_id:
		return
	var journey = profile_service.get("journey")
	if journey == null or not is_instance_valid(journey) or not is_instance_valid(journey.screen):
		return
	load(ModPaths.JOURNEY_PROFILE_BADGES).attach(award_medal_grid_container.get_parent(), journey.screen)

func _open_recorded_games():
	var tool = profile_service.tool
	if tool==null or not is_instance_valid(tool) or not tool._workspace_menu.enabled("council"):
		return
	tool._replay_hub.ensure_council()
	tool._replay_hub._council.open_player_recordings(profile_user_id,false)
	tool._workspace_menu.select("council")
	dialog.on_close_button_pressed()

func _apply_studio_look() -> void:
	if profile_service.tool == null or not is_instance_valid(profile_service.tool):
		return
	var sandbox = profile_service.tool.get("_cosmetic_sandbox")
	if sandbox != null and is_instance_valid(sandbox):
		sandbox.call("_apply_to_goober", goober, sandbox.call("_build_local_skin"))
