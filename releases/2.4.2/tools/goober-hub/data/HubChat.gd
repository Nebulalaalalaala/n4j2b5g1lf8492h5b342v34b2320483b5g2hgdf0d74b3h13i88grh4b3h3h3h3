extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Friends-only messages. The server checks the friendship, blocks links and
# contact details, limits sending speed and deletes messages after 30 days.
# Bad words are masked here on both sides.
signal changed
signal failed(message)

const POLL_OPEN = 15
const POLL_CLOSED = 120
const MASK = ["fuck", "shit", "bitch", "cunt", "dick", "pussy", "bastard", "asshole", "slut", "whore", "fag", "retard", "nigg", "kys", "kill yourself"]
var api
var identity
var threads = {}      # friend id -> [{"id", "mine", "body", "at", "read"}]
var unread = {}       # friend id -> count
var blocked = {}
var last_id = 0
var status = "idle"
var open = false
var _polled = 0
var _owner = ""

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	api.connect("done", self, "_done")

static func mask(text) -> String:
	var out = str(text)
	var lower = out.to_lower()
	for word in MASK:
		var at = lower.find(word)
		while at >= 0:
			out = out.substr(0, at) + "*".repeat(word.length()) + out.substr(at + word.length())
			lower = out.to_lower()
			at = lower.find(word, at + word.length())
	return out

# Levels and invites ride in the message as [[kind:letters]]: the JSON bytes as
# letters a-p, so the server's link/number filter never sees ids or codes.
# Kinds: lv = level {id, name}, py = party {party}, lb = custom lobby {code}.
const KINDS = ["lv", "py", "lb"]

static func pack(kind, data) -> String:
	var out = ""
	for b in to_json(data).to_utf8():
		out += char(97 + (b >> 4)) + char(97 + (b & 15))
	return "[[%s:%s]]" % [kind, out]

static func _unpack(letters):
	if letters.length() < 2 or letters.length() % 2 != 0:
		return null
	var bytes = PoolByteArray()
	for i in range(0, letters.length(), 2):
		var hi = letters.ord_at(i) - 97
		var lo = letters.ord_at(i + 1) - 97
		if hi < 0 or hi > 15 or lo < 0 or lo > 15:
			return null
		bytes.append((hi << 4) | lo)
	var parsed = JSON.parse(bytes.get_string_from_utf8())
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else null

# [{text}] / [{emote, raw}] / [{kind, data, raw}] in order. emotes: known emote names.
static func parts(body, emotes = {}) -> Array:
	body = str(body)
	var out = []
	var start = 0
	var i = 0
	while i < body.length():
		var piece = null
		var end = -1
		if body.substr(i, 2) == "[[":
			end = body.find("]]", i + 2)
			var inner = body.substr(i + 2, end - i - 2) if end > 0 else ""
			var colon = inner.find(":")
			if colon > 0 and inner.left(colon) in KINDS:
				var data = _unpack(inner.substr(colon + 1))
				if data != null:
					piece = {"kind": inner.left(colon), "data": data}
					end += 2
		elif body[i] == ":" and not emotes.empty():
			end = body.find(":", i + 1)
			if end > i + 1 and emotes.has(body.substr(i + 1, end - i - 1)):
				piece = {"emote": body.substr(i + 1, end - i - 1)}
				end += 1
		if piece == null:
			i += 1
			continue
		if i > start:
			out.append({"text": body.substr(start, i - start)})
		piece.raw = body.substr(i, end - i)
		out.append(piece)
		i = end
		start = end
	if start < body.length():
		out.append({"text": body.substr(start)})
	return out

# One line for the friend list.
static func preview(body, emotes = {}) -> String:
	var out = ""
	for p in parts(body, emotes):
		if p.has("text"):
			out += p.text
		elif p.has("emote"):
			out += "[%s]" % str(emotes[p.emote].get("name", "Emote"))
		elif p.kind == "lv":
			out += "Level: " + str(p.data.get("name", "level"))
		else:
			out += "Party invite" if p.kind == "py" else "Game invite"
	return out.strip_edges()

# Mask only the typed text, never the packed letters.
static func mask_message(body) -> String:
	var out = ""
	for p in parts(body):
		out += mask(p.text) if p.has("text") else p.raw
	return out

func reset_for(owner):
	if owner == _owner:
		return
	_owner = owner
	threads = {}
	unread = {}
	blocked = {}
	last_id = 0
	_polled = 0
	emit_signal("changed")

func _process(_delta):
	if not identity.signed_in():
		return
	reset_for(identity.user_id)
	if OS.get_unix_time() - _polled >= (POLL_OPEN if open else POLL_CLOSED):
		poll()

func poll():
	if not identity.signed_in() or api.pending("inbox"):
		return
	_polled = OS.get_unix_time()
	api.call_fn("hub_inbox", identity.auth({"p_after": last_id}), "inbox")
	if blocked.empty():
		api.call_fn("hub_blocked", identity.auth(), "blocked")

func _done(tag, ok, data, message):
	if tag == "inbox":
		var before_id = last_id
		var before_status = status
		status = "ready" if ok else ("missing" if message == "missing" else "error")
		if not ok and message.find("not allowed") >= 0:
			identity.refused()
		for m in data if ok and data is Array else []:
			var mine = str(m.sender) == identity.user_id
			var other = str(m.recipient) if mine else str(m.sender)
			var list = threads.get(other, [])
			list.append({"id": int(m.id), "mine": mine, "body": mask_message(m.body), "at": load(ModPaths.path("HubFeed.gd")).unix(m.created_at), "read": m.read_at != null})
			threads[other] = list
			last_id = max(last_id, int(m.id))
			if not mine and m.read_at == null:
				unread[other] = int(unread.get(other, 0)) + 1
		if before_id != last_id or before_status != status:
			emit_signal("changed")
	elif tag == "blocked" and ok and data is Array:
		blocked = {}
		for id in data:
			blocked[str(id)] = true
		emit_signal("changed")
	elif tag == "send":
		if not ok:
			var text = "Couldn't send. Try again."
			for k in [["only message friends", "You can only message friends."], ["blocked", "You can't message this player."], ["slow down", "Slow down a little."], ["links and contact", "Links and contact details aren't allowed."], ["too long", "That message is too long."], ["hub muted", "Messaging is temporarily muted."], ["hub banned", "Goober Hub access is temporarily suspended."]]:
				if message.find(k[0]) >= 0:
					text = k[1]
			emit_signal("failed", text)
		poll()
	elif tag == "report":
		emit_signal("failed", "Thanks. The message was reported." if ok else "Couldn't submit that report. Please try again.")

func send(friend_id, text):
	text = str(text).strip_edges()
	if text.empty() or not identity.signed_in():
		return
	if text.length() > 300:
		emit_signal("failed", "That message is too long.")
		return
	api.call_fn("hub_send", identity.auth({"p_to": str(friend_id), "p_body": text}), "send")

# Admin only: write to yourself as the test account.
func send_as_test(text):
	text = str(text).strip_edges()
	if text.empty() or not identity.signed_in():
		return
	api.call_fn("hub_send_as_test", identity.auth({"p_body": text}), "send")

func mark_read(friend_id):
	if int(unread.get(str(friend_id), 0)) == 0:
		return
	unread.erase(str(friend_id))
	api.call_fn("hub_read", identity.auth({"p_from": str(friend_id)}), "read")
	emit_signal("changed")

func set_blocked(friend_id, on):
	if on:
		blocked[str(friend_id)] = true
	else:
		blocked.erase(str(friend_id))
	api.call_fn("hub_block", identity.auth({"p_target": str(friend_id), "p_on": bool(on)}), "block")
	emit_signal("changed")

func report(friend_id, message_id, reason = "message"):
	api.call_fn("hub_report", identity.auth({"p_target": str(friend_id), "p_message": int(message_id), "p_reason": reason}), "report")

func total_unread(muted = {}) -> int:
	var n = 0
	for id in unread:
		if not blocked.has(id) and not muted.has(id):
			n += int(unread[id])
	return n

func last(friend_id):
	var list = threads.get(str(friend_id), [])
	return list[list.size() - 1] if not list.empty() else null
