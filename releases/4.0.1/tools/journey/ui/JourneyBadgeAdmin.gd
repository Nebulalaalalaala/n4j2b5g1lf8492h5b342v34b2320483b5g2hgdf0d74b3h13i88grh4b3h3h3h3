extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const ClientRoles = preload("user://mod/core/workspace4/ClientRoles.gd")

# "Custom badges" in the admin test tools (Ctrl+M): design a badge and award it
# to players. Writes need the admin passphrase set in journey-v5.sql.
var screen
var ui
var badges        # JourneyCustomBadges
var _pass_field
var _name_field
var _detail_field
var _emblem_pick
var _frame_pick
var _badge_pick
var _player_field
var _player_pick
var _preview_holder
var _status
var _role_template
var _role_code = ""

static func add_to(body, owner_screen):
	var source = owner_screen.get("custom_badges")
	if source == null or not is_instance_valid(source):
		return
	var admin = load(ModPaths.path("JourneyBadgeAdmin.gd")).new()
	admin.screen = owner_screen
	admin.ui = owner_screen.ui
	admin.badges = source
	body.add_child(admin)
	admin.build(body)

func build(body):
	badges.lookup([])   # loads the badge list if it is not loaded yet
	var p = ui.well(body, ui.NAVY_2, 22, 28)
	var col = ui.box(p, true, 14)
	ui.heading(col, "Custom badges", "achievements", "%d made" % badges.catalog.size())
	var row = ui.box(col, false, 12)
	_pass_field = _field(row, "Admin passphrase", 360)
	_pass_field.secret = true
	_pass_field.text = badges._pass
	# Design
	ui.label(col, "Design", "caps", ui.MUTED)
	var design = ui.box(col, false, 16)
	_preview_holder = CenterContainer.new()
	_preview_holder.rect_min_size = Vector2(150, 150)
	design.add_child(_preview_holder)
	var fields = ui.box(design, true, 10)
	var templates = ["Custom badge"]
	for key in ClientRoles.ORDER: templates.append(str(ClientRoles.DEFINITIONS[key].name))
	_role_template = _pick(fields,templates)
	_role_template.hint_tooltip = "Client role templates control the in-game logo labels and access-tier name gradient. Save the label, then award it below."
	_role_template.connect("item_selected",self,"_role_template_selected")
	_name_field = _field(fields, "Badge name", 420)
	_detail_field = _field(fields, "Short description", 420)
	var picks = ui.box(fields, false, 10)
	_emblem_pick = _pick(picks, badges.EMBLEMS)
	_frame_pick = _pick(picks, load(ModPaths.path("JourneyAchievements.gd")).NAMES)
	_emblem_pick.connect("item_selected", self, "_preview")
	_frame_pick.connect("item_selected", self, "_preview")
	var design_actions = ui.box(fields, false, 10)
	ui.button(design_actions, "Save badge", "small", self, "_save", true, "check")
	ui.button(design_actions, "Delete badge", "small", self, "_delete", true)
	# Award
	ui.label(col, "Award", "caps", ui.MUTED)
	var award = ui.box(col, false, 10)
	_badge_pick = _pick(award, [])
	_fill_badges()
	badges.connect("changed", self, "_fill_badges")
	_badge_pick.connect("item_selected", self, "_load_badge")
	_player_field = _field(award, "Player user id", 420)
	_player_pick = _pick(award, ["Leaderboard player…"])
	var lb = screen.get("leaderboard")
	for r in (lb.rows if lb != null else []):
		if not str(r.get("user_id", "")).empty():
			_player_pick.add_item(str(r.name))
			_player_pick.set_item_metadata(_player_pick.get_item_count() - 1, str(r.user_id))
	_player_pick.connect("item_selected", self, "_pick_player")
	var award_actions = ui.box(col, false, 10)
	ui.button(award_actions, "Award", "small", self, "_award", true, "star")
	ui.button(award_actions, "Take back", "small", self, "_award", false)
	_status = ui.label(col, "", "small", ui.MUTED)
	badges.connect("admin_done", self, "_done")
	if lb != null:
		lb.fetch()
	_preview(0)

func _role_template_selected(index):
	_role_code = ""
	if index<=0 or index>ClientRoles.ORDER.size(): return
	var key = ClientRoles.ORDER[index-1]
	_role_code = key
	var definition = ClientRoles.DEFINITIONS[key]
	_name_field.text = definition.name
	_detail_field.text = str(definition.name)+" · Goobplayability client label"
	_emblem_pick.select(max(0,badges.EMBLEMS.find(definition.emblem)))
	_frame_pick.select(0)
	var wanted = _role_badge_id()
	var found = false
	for i in _badge_pick.get_item_count():
		if str(_badge_pick.get_item_metadata(i))==wanted:
			_badge_pick.select(i)
			found = true
	if not found:
		_badge_pick.add_item("Save this role label first…")
		_badge_pick.set_item_metadata(_badge_pick.get_item_count()-1,"")
		_badge_pick.select(_badge_pick.get_item_count()-1)
	_preview(0)

func _role_badge_id() -> String:
	for badge in badges.catalog.values():
		if ClientRoles.code(badge)==_role_code: return str(badge.id)
	return "gp_role_"+_role_code

func _action_badge_id() -> String:
	return _role_badge_id() if not _role_code.empty() else _selected_badge()

func _fill_badges():
	if _badge_pick == null or not is_instance_valid(_badge_pick):
		return
	var keep = _action_badge_id()
	_badge_pick.clear()
	for b in badges.catalog.values():
		_badge_pick.add_item(str(b.name))
		_badge_pick.set_item_metadata(_badge_pick.get_item_count() - 1, b.id)
		if b.id == keep:
			_badge_pick.select(_badge_pick.get_item_count() - 1)

func _field(parent, hint, width):
	var f = LineEdit.new()
	f.placeholder_text = hint
	f.rect_min_size = Vector2(width, 56)
	f.add_font_override("font", ui.font("display", 28))
	for state in ["normal", "focus", "read_only"]:
		var box = ui.flat(ui.NAVY_DEEP, 20, 18, 0, ui.INK, false)
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		f.add_stylebox_override(state, box)
	f.add_color_override("font_color", ui.WHITE)
	parent.add_child(f)
	return f

func _pick(parent, items):
	var o = OptionButton.new()
	o.rect_min_size = Vector2(260, 56)
	o.add_font_override("font", ui.font("display", 28))
	for item in items:
		o.add_item(str(item).capitalize())
	for state in ["normal", "hover", "pressed", "focus"]:
		o.add_stylebox_override(state, ui.flat(ui.NAVY_DEEP if state != "hover" else ui.NAVY_3, 20, 18, 0, ui.INK, false))
	o.add_color_override("font_color", ui.WHITE)
	o.get_popup().add_font_override("font", ui.font("display", 28))
	parent.add_child(o)
	return o

func _preview(_index):
	for c in _preview_holder.get_children():
		c.queue_free()
	ui.medal(_preview_holder, _frame_pick.selected, badges.EMBLEMS[max(0, _emblem_pick.selected)], 140)

func _selected_badge() -> String:
	return str(_badge_pick.get_item_metadata(_badge_pick.selected)) if _badge_pick.selected >= 0 and _badge_pick.get_item_count() > 0 else ""

# Picking an existing badge loads it for editing.
func _load_badge(_index):
	var b = badges.catalog.get(_selected_badge())
	if b == null:
		return
	_role_code = ClientRoles.code(b)
	if _role_template!=null: _role_template.select(ClientRoles.ORDER.find(_role_code)+1 if not _role_code.empty() else 0)
	_name_field.text = str(b.name)
	_detail_field.text = str(b.detail).trim_prefix(ClientRoles.marker(_role_code)).strip_edges() if not _role_code.empty() else str(b.detail)
	_emblem_pick.select(max(0, badges.EMBLEMS.find(str(b.emblem))))
	_frame_pick.select(int(b.frame))
	_preview(0)

func _pick_player(index):
	if index > 0:
		_player_field.text = str(_player_pick.get_item_metadata(index))

func _save(_arg = null):
	var badge_name = _name_field.text.strip_edges()
	if badge_name.empty():
		return _done(false, "Give the badge a name.")
	badges.set_pass(_pass_field.text)
	# Editing keeps the id of the badge picked under Award if the name matches it.
	var id = _selected_badge()
	if not _role_code.empty():
		id = _role_badge_id()
	elif id.empty() or str(badges.catalog.get(id, {}).get("name", "")) != badge_name:
		id = badge_name.to_lower().replace(" ", "_").left(32) + "_" + str(OS.get_unix_time() % 100000)
	var detail = _detail_field.text.strip_edges()
	if not _role_code.empty(): detail = ClientRoles.marker(_role_code)+" "+detail
	badges.save_badge(id, badge_name, detail, badges.EMBLEMS[max(0, _emblem_pick.selected)], _frame_pick.selected)

func _delete(_arg = null):
	var id = _action_badge_id()
	if id.empty() or not badges.catalog.has(id):
		return _done(false, "Pick the badge under Award first.")
	badges.set_pass(_pass_field.text)
	badges.delete_badge(id)

func _award(on):
	var id = _action_badge_id()
	if id.empty() or not badges.catalog.has(id) or _player_field.text.strip_edges().empty():
		return _done(false, "Pick a badge and a player.")
	badges.set_pass(_pass_field.text)
	badges.award(id, _player_field.text, on)

func _done(ok, message):
	if _status != null and is_instance_valid(_status):
		_status.text = str(message)
		_status.add_color_override("font_color", ui.WHITE if ok else ui.PINK_LIGHT)
	if ok and screen != null and is_instance_valid(screen):
		screen.play("claim")
