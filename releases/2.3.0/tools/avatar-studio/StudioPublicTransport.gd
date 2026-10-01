extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const Look = preload("user://mod/tools/avatar-studio/StudioPublicLook.gd")
signal changed
const KEY_FILE = "user://goobplayability/studio-public-keys.cfg"
var status = "idle"
var cache = {}
var pending = []
var in_flight = []
var url = ""
var key = ""
var getter
var setter
var sent = ""
var sent_at = 0
var sending = ""
var next_try = 0
var failures = 0
var keys = ConfigFile.new()

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	keys.load(KEY_FILE)
	var config = ModPaths.try_load(ModPaths.path("OnlineConfig.gd"))
	if config != null:
		url = config.SUPABASE_URL
		key = config.anon_key()
	getter = _http("_received")
	setter = _http("_submitted")

func _http(callback):
	var node = HTTPRequest.new()
	node.timeout = 10.0
	node.body_size_limit = 4*1024*1024
	add_child(node)
	node.connect("request_completed", self, callback)
	return node

func _headers():
	return PoolStringArray(["apikey: "+key,"Authorization: Bearer "+key,"Content-Type: application/json"])

func _available(http):
	return not key.empty() and status != "schema_missing" and OS.get_unix_time() >= next_try and http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED

func publish(owner, appearance):
	if not Look.valid_id(owner) or appearance.empty() or not _available(setter): return
	var body_id = owner+JSON.print(appearance)
	var now = OS.get_unix_time()
	if now-sent_at<60 or (body_id==sent and now-sent_at<300): return
	var token = _token(owner)
	if token.empty():
		status = "key_save_failed"
		return
	sending = body_id
	# Record the attempt for rate limiting, but commit the content only on success.
	sent_at = now
	var error = setter.request(url+"/rest/v1/rpc/publish_studio_look",_headers(),true,HTTPClient.METHOD_POST,JSON.print({"p_user_id":owner,"p_write_key":token,"p_look":appearance}))
	if error != OK: _failed(0)

func _token(owner):
	var token = str(keys.get_value("write_keys",owner,""))
	if token.length()==64 and token.is_valid_hex_number(false): return token
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	keys.set_value("write_keys",owner,token)
	if Directory.new().make_dir_recursive(KEY_FILE.get_base_dir())!=OK: return ""
	if keys.save(KEY_FILE)!=OK: return ""
	return token

func lookup(ids):
	for id in ids:
		if not Look.valid_id(id): continue
		if OS.get_unix_time()-int(cache.get(id,{}).get("at",0))<60: continue
		if not id in pending and not id in in_flight and pending.size()<96: pending.append(id)
	_flush()

func _flush():
	if pending.empty() or not in_flight.empty() or not _available(getter): return
	in_flight = []
	while not pending.empty() and in_flight.size()<32: in_flight.append(pending.pop_front())
	var error = getter.request(url+"/rest/v1/rpc/lookup_studio_looks",_headers(),true,HTTPClient.METHOD_POST,JSON.print({"p_users":in_flight}))
	if error != OK:
		pending.append_array(in_flight)
		in_flight = []
		_failed(0)

func _received(result, code, _headers, body):
	var ids = in_flight
	in_flight = []
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		pending.append_array(ids)
		_failed(code)
		return
	var parsed = JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or not parsed.result is Array or parsed.result.size()>32:
		pending.append_array(ids)
		_failed(0)
		return
	for id in ids: cache[id] = {"at":OS.get_unix_time(),"present":false}
	for row in parsed.result:
		if row is Dictionary and row.get("user_id", "") in ids and row.get("appearance") is Dictionary:
			cache[row.user_id] = {"at":OS.get_unix_time(),"present":true,"look":row.appearance}
	# Bound cache retention across long sessions. Active renderers re-request as needed.
	if cache.size()>256:
		for id in cache.keys():
			if not id in ids: cache.erase(id)
	status = "ready"
	failures = 0
	emit_signal("changed")
	call_deferred("_flush")

func _submitted(result, code, _headers, _body):
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		sent = sending
		status = "ready"
		failures = 0
	else: _failed(code)

func _failed(code):
	failures = min(5,failures+1)
	next_try = OS.get_unix_time()+int(min(300,10*pow(2,failures)))
	status = "schema_missing" if code==404 else ("write_key_rejected" if code==403 else "retrying")
	# A rejected key never gets replaced automatically: do not steal another row.
	if code==403: next_try = OS.get_unix_time()+3600
