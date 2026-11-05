extends Reference

# One attention list for the bell in the menu header. Each notice keeps an id,
# title, body, time, read flag and an optional menu route to open.

const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PATH = "user://goobplayability/notifications.json"
const LIMIT = 60

static func all() -> Array:
	return Kit.read_json(PATH, [])

static func add(id: String, title: String, body: String, route: String = "") -> void:
	var list = all()
	for entry in list:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == id:
			return
	list.push_front({"id": id, "title": title, "body": body, "route": route, "time": OS.get_unix_time(), "read": false})
	if list.size() > LIMIT:
		list.resize(LIMIT)
	Kit.write_json(PATH, list)

static func unread() -> int:
	var count = 0
	for entry in all():
		if typeof(entry) == TYPE_DICTIONARY and not bool(entry.get("read", false)):
			count += 1
	return count

static func mark_all_read() -> void:
	var list = all()
	for entry in list:
		if typeof(entry) == TYPE_DICTIONARY:
			entry["read"] = true
	Kit.write_json(PATH, list)

static func clear() -> void:
	Kit.write_json(PATH, [])

static func age(unix: int) -> String:
	var seconds = max(0, OS.get_unix_time() - unix)
	if seconds < 3600:
		return "%d min ago" % max(1, seconds / 60)
	if seconds < 86400:
		return "%d h ago" % (seconds / 3600)
	return "%d d ago" % (seconds / 86400)
