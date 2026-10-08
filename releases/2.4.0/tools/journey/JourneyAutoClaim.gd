extends Reference
var signature = ""
var busy = false

# Called by the existing one-second Journey owner, not a per-frame poll.
# No extra network requests or second ledger writer. Rebuild only when a
# local round/XP/activity minute changes, and only on the real home screen.
func tick(screen):
	if busy or not safe(screen) or not enabled(screen):
		return
	var records = screen.profile_service.store.records
	var last = str(records[-1].get("id", "")) if not records.empty() else ""
	var active = screen.activity.snapshot() if is_instance_valid(screen.activity) and screen.activity.account_id == screen.ledger.account_id else {}
	var next = "%s:%s:%s:%s:%s:%s" % [screen.ledger.account_id, records.size(), last,
		screen.ledger.revision, int(active.get("today_seconds", 0)) / 60, int(OS.get_unix_time()) / 86400]
	if signature == next:
		return
	signature = next
	busy = true
	screen._load_prefs()
	screen.refresh()
	busy = false

static func enabled(screen):
	var settings = screen._settings()
	return bool(settings.get_value("journey_pref_auto_claim", false)) if settings != null else bool(screen.prefs.get("auto_claim", false))

static func safe(screen):
	if not is_instance_valid(screen) or not screen.is_inside_tree() or screen.closable or screen.design_preview or screen.model.empty() or screen.model.get("preview", false):
		return false
	if screen.get_parent() == null or not screen.get_parent().is_visible_in_tree():
		return false
	if screen.ledger == null or not screen.ledger.writable or screen.ledger.account_id.empty() or screen.journey_store == null or not screen.journey_store.writable:
		return false
	if screen.journey_store.account_id != screen.ledger.account_id or not screen.journey_store.test.empty():
		return false
	var service = screen.profile_service
	if service == null or service.store == null or service.store.account_id != screen.ledger.account_id:
		return false
	return screen.model.get("stats") != null and screen.model.stats.get("store") == service.store
