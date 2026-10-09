extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
# Who you are to Goober Hub. Each account gets a random key on this PC; the first
# install to claim an account id owns it (hub_claim), and every write needs the key.
# keys.cfg holds hub keys, not GooberDash logins. Keep it private; copy it to use
# the same account's Hub from another PC.
signal changed

const KEYS = "user://goobplayability/hub/keys.cfg"
const RECHECK = 43200
var api
var user_id = ""
var key = ""
var state = "signed_out"   # signed_out, checking, ready, failed, missing
var error = ""
var _checked_at = 0

func configure(owner):
	if str(owner) == user_id:
		return
	user_id = str(owner)
	key = ""
	state = "signed_out"
	error = ""
	if user_id.empty():
		emit_signal("changed")
		return
	var cfg = ConfigFile.new()
	cfg.load(KEYS)
	key = str(cfg.get_value(user_id.sha256_text(), "key", ""))
	_checked_at = int(cfg.get_value(user_id.sha256_text(), "checked", 0))
	if key.length() != 64:
		key = Crypto.new().generate_random_bytes(32).hex_encode()
		_checked_at = 0
		_save(cfg)
	state = "ready" if OS.get_unix_time() - _checked_at < RECHECK else "checking"
	emit_signal("changed")
	if state == "checking":
		verify()

func _save(cfg):
	Directory.new().make_dir_recursive(KEYS.get_base_dir())
	cfg.set_value(user_id.sha256_text(), "key", key)
	cfg.set_value(user_id.sha256_text(), "checked", _checked_at)
	cfg.save(KEYS)

func signed_in() -> bool:
	return state == "ready" and not user_id.empty()

func auth(extra = {}) -> Dictionary:
	var args = {"p_user": user_id, "p_key": key}
	for k in extra: args[k] = extra[k]
	return args

var friend_ids = []   # set by GooberHub from the game's friends list

func verify():
	var moonlight = get_node_or_null("/root/Moonlight")
	var session = moonlight.get("session") if moonlight != null else null
	if session == null or user_id.empty() or str(session.user_id) != user_id:
		return
	var user = moonlight.local_account.user if moonlight.get("local_account") != null and moonlight.local_account.get("user") != null else null
	var display = ""
	var created = ""
	if user != null:
		display = str(user.display_name) if not str(user.display_name).strip_edges().empty() else str(user.username)
		created = str(user.create_time) if user.get("create_time") != null else ""
	state = "checking"
	emit_signal("changed")
	print("[GooberHub] checking sign-in")
	api.call_fn("hub_claim", {"p_user": user_id, "p_key": key, "p_name": display, "p_created": created, "p_friends": friend_ids}, "verify")

func _ready():
	api.connect("done", self, "_done")

func _done(tag, ok, data, message):
	if tag != "verify":
		return
	if ok and str(data) == user_id:
		_checked_at = OS.get_unix_time()
		var cfg = ConfigFile.new()
		cfg.load(KEYS)
		_save(cfg)
		state = "ready"
		error = ""
		print("[GooberHub] signed in")
	else:
		state = "missing" if message == "missing" else "failed"
		error = "This account's Hub belongs to another PC. Copy keys.cfg from that PC." if message.find("claimed by another") >= 0 else message
	emit_signal("changed")

# A write was refused: the key may have been dropped server side. Check again.
func refused():
	if state == "ready" and OS.get_unix_time() - _checked_at > 60:
		_checked_at = 0
		verify()
