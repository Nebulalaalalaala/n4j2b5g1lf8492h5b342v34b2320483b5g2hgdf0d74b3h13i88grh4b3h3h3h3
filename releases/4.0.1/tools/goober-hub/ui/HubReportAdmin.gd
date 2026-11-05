extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Journey-styled moderation section in Ctrl+M. The display-only harness admin
# flag must NEVER unlock this section or a server-side action.
var screen
var ui
var hub
var service
var pass_field
var body
var status_label
var buttons = []
var confirmed = {}
var show_reviewed = false
var pages = [0]
var index = 0

static func add_to(parent, owner):
	if owner.ledger == null or str(owner.ledger.account_id) != owner.ADMIN_ID: return
	var profile = owner.profile_service
	var tool = profile.get("tool") if is_instance_valid(profile) else null
	var hub = tool.get_node_or_null("GooberHub") if is_instance_valid(tool) else null
	if not is_instance_valid(hub) or hub.get("moderation") == null: return
	var panel = load(ModPaths.path("HubReportAdmin.gd")).new()
	panel.screen = owner
	panel.ui = owner.ui
	panel.hub = hub
	panel.service = hub.moderation
	parent.add_child(panel)
	panel.build(parent)

func build(parent):
	var panel = ui.well(parent, ui.NAVY_2, 22, 28)
	var col = ui.box(panel, true, 14)
	ui.heading(col, "Reports & moderation", "flag", "Goober Hub only")
	ui.label(col, "Review the reported message before choosing an action.", "small", ui.MUTED)
	var row = ui.box(col, false, 12)
	pass_field = LineEdit.new()
	pass_field.placeholder_text = "Journey admin passphrase"
	pass_field.secret = true
	pass_field.max_length = 256
	pass_field.rect_min_size = Vector2(360, 56)
	pass_field.add_font_override("font", ui.font("display", 28))
	for state in ["normal", "focus", "read_only"]:
		pass_field.add_stylebox_override(state, ui.flat(ui.NAVY_DEEP, 20, 18, 0, ui.INK, false))
	pass_field.add_color_override("font_color", ui.WHITE)
	ui.grow(pass_field)
	row.add_child(pass_field)
	ui.button(row, "Load reports", "small", self, "_load", null, "session")
	var filters = ui.box(col, false, 12)
	ui.button(filters, "Pending", "small", self, "_filter", false, "inbox")
	ui.button(filters, "Reviewed", "small", self, "_filter", true, "check")
	status_label = ui.label(col, "Enter your admin passphrase to view reports.", "small", ui.MUTED)
	status_label.autowrap = true
	body = ui.box(col, true, 14)
	service.connect("changed", self, "_fill")
	service.connect("completed", self, "_completed")
	_fill()

func _exit_tree():
	if is_instance_valid(service): service.lock()

func _load():
	if not service.is_admin():
		_completed(false, "Open the Hub once after signing in to Emilia, then try again.")
		return
	service.unlock(pass_field.text)
	confirmed = {}
	service.fetch(show_reviewed, pages[index])

func _filter(reviewed):
	show_reviewed = bool(reviewed)
	pages = [0]
	index = 0
	_load()

func _fill():
	if not is_instance_valid(body): return
	if not service.is_admin():
		pass_field.text = ""
		confirmed = {}
		status_label.text = "Sign in to Emilia to use moderation."
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	buttons = []
	if service.status == "loading":
		ui.label(body, "Loading reports…", "small", ui.MUTED)
		return
	if service.status in ["missing", "error"]:
		ui.label(body, service.error, "small", ui.PINK_LIGHT).autowrap = true
		return
	if service.status != "ready": return
	ui.label(body, "Reviewed reports" if show_reviewed else "Pending reports", "caps", ui.MUTED)
	if service.rows.empty(): ui.label(body, "No reports here.", "small", ui.MUTED)
	for report in service.rows: _report(body, report)
	var nav = ui.box(body, false, 12)
	var previous = ui.button(nav, "Previous", "small", self, "_page", -1)
	previous.disabled = index == 0 or service.busy
	ui.grow(ui.label(nav, "Page %d" % (index + 1), "small", ui.MUTED)).align = Label.ALIGN_CENTER
	var next = ui.button(nav, "Next", "small", self, "_page", 1, "chevron_right")
	next.disabled = not service.has_more or service.busy

func _page(direction):
	if direction < 0:
		index = max(0, index - 1)
	elif service.has_more and not service.rows.empty():
		if pages.size() == index + 1: pages.append(int(service.rows.back().id))
		index += 1
	_load()

func _report(parent, report):
	var panel = ui.well(parent, ui.NAVY_DEEP, 18, 22)
	var col = ui.box(panel, true, 10)
	ui.heading(col, str(report.get("target_name", "Player")), "goober", "Report #%d" % int(report.id))
	ui.label(col, "Player ID: " + str(report.target), "small", ui.MUTED).autowrap = true
	ui.label(col, "Reported by %s · %s" % [str(report.get("reporter_name", report.reporter)), service.until_text(report.created_at)], "small", ui.MUTED).autowrap = true
	ui.label(col, "Reason: " + str(report.reason), "small", ui.MUTED).autowrap = true
	var message = ui.well(col, ui.NAVY_2, 16, 18)
	# A plain label preserves evidence; never execute attached levels/invites.
	ui.label(message, str(report.body) if report.body != null else "Message unavailable", "body", ui.WHITE).autowrap = true
	var verified = bool(report.get("validated", false))
	if not verified: ui.label(col, "Legacy report — sender could not be verified. No penalty can be applied.", "small", ui.PINK_LIGHT).autowrap = true
	for kind in ["banned_until", "muted_until"]:
		if report.get(kind) != null:
			ui.label(col, ("Hub ban until " if kind == "banned_until" else "Chat mute until ") + service.until_text(report[kind]), "small", ui.MUTED)
	var row = ui.box(col, false, 10)
	var days = OptionButton.new()
	days.align = Button.ALIGN_CENTER
	days.rect_min_size = Vector2(150, 52)
	days.add_font_override("font", ui.font("display", 26))
	days.get_popup().add_font_override("font", ui.font("display", 26))
	for day in [1, 2, 3]: days.add_item("%d day%s" % [day, "" if day == 1 else "s"], day)
	for state in ["normal", "hover", "pressed", "focus"]:
		days.add_stylebox_override(state, ui.flat(ui.NAVY_2, 18, 14, 0, ui.INK, false))
	days.add_color_override("font_color", ui.WHITE)
	row.add_child(days)
	var safe = verified and str(report.target) != hub.ADMIN_ID and str(report.target) != hub.TEST_ID
	for action in ["ban", "mute"]:
		var b = ui.button(row, "Ban" if action == "ban" else "Mute", "small", self, "_choose", [report.id, action, days], "lock" if action == "ban" else "bell")
		b.disabled = not safe or service.busy or bool(report.reviewed)
	var dismiss = ui.button(row, "Mark reviewed", "small", self, "_choose", [report.id, "dismiss", null], "check")
	dismiss.disabled = service.busy or bool(report.reviewed)
	var undo = ui.box(col, false, 10)
	for pair in [["unban", "banned_until", "Lift ban"], ["unmute", "muted_until", "Lift mute"]]:
		if report.get(pair[1]) != null:
			ui.button(undo, pair[2], "small", self, "_choose", [report.id, pair[0], null], "check").disabled = not safe or service.busy
	if int(confirmed.get("id", -1)) == int(report.id):
		var confirm = ui.box(col, false, 10)
		var label = str(confirmed.action).capitalize() + (" for %d day(s)?" % int(confirmed.days) if int(confirmed.days) > 0 else "?")
		ui.grow(ui.label(confirm, label, "small", ui.PINK_LIGHT))
		ui.button(confirm, "Confirm", "accent", self, "_confirm", null, "check").disabled = service.busy
		ui.button(confirm, "Cancel", "small", self, "_cancel", null, "close")

func _choose(args):
	confirmed = {"id": int(args[0]), "action": str(args[1]), "days": args[2].get_selected_id() if args[2] != null else 0}
	_fill()

func _cancel():
	confirmed = {}
	_fill()

func _confirm():
	if confirmed.empty(): return
	service.unlock(pass_field.text)
	service.act(confirmed.id, confirmed.action, confirmed.days)
	confirmed = {}

func _completed(ok, text):
	if not is_instance_valid(status_label): return
	status_label.text = str(text)
	status_label.add_color_override("font_color", ui.WHITE if ok else ui.PINK_LIGHT)
