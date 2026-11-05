extends Reference

func create_client():
	# Same SDK/auth protocol, detached from Moonlight's 403 handler so a failed
	# target login cannot invalidate the currently working account.
	var client = Nakama.create_client(Moonlight.nakama_key,Moonlight.nakama_host,Moonlight.nakama_port,Moonlight.nakama_scheme,Moonlight.nakama_path_prefix,10,NakamaLogger.LOG_LEVEL.NONE)
	client.auto_retry = false
	client.auto_refresh = false
	return client

func email_session(email,password):
	var client = create_client()
	return yield(client.authenticate_email_async(email,password,null,false,{"client_version":Moonlight.get_client_version(),"platform":OS.get_name()}),"completed")

func needs_signin(result):
	return result != null and result.is_exception() and result.get_exception().status_code in [401,404]

func prepare(session):
	if session == null or not session.is_valid():
		return {"error":"signin_required"}
	var identity = session.user_id
	var client = create_client()
	if session.would_expire_in(60):
		if session.refresh_token.empty() or session.is_refresh_expired():
			return {"error":"signin_required"}
		session = yield(client.session_refresh_async(session),"completed")
		if session == null or session.is_exception() or not session.is_valid():
			return {"error":"signin_required" if needs_signin(session) else "refresh_failed"}
	if session.user_id != identity:
		return {"error":"identity_mismatch"}
	var result = yield(client.rpc_async(session,"player_fetch_data","{}"),"completed")
	if result == null or result.is_exception():
		return {"error":"signin_required" if needs_signin(result) else "validation_failed"}
	var parsed = JSON.parse(result.payload)
	if parsed.error != OK or not valid_payload(parsed.result,identity):
		return {"error":"identity_mismatch"}
	var socket = Nakama.create_socket_from(client)
	var connected = yield(socket.connect_async(session,true,10),"completed")
	if connected.is_exception() or not socket.is_connected_to_host():
		socket.close()
		return {"error":"connection_failed"}
	return {"session":session,"payload":parsed.result,"socket":socket,"client":client}

func valid_payload(payload,identity):
	if not payload is Dictionary or not payload.get("account") is Dictionary or not payload.account.get("user") is Dictionary or payload.account.user.get("id","") != identity:
		return false
	if not payload.get("data",{}) is Dictionary or not payload.get("wallet",{}) is Dictionary:
		return false
	var account = NakamaSerializer.deserialize(NakamaAPI,"ApiAccount",payload.account)
	return account != null and not account.is_exception()

func busy_requests(node):
	if node is NakamaHTTPAdapter and not node._pending.empty():
		return true
	for child in node.get_children():
		if busy_requests(child):
			return true
	return false

func drain(tree):
	var deadline = OS.get_ticks_msec()+12000
	while busy_requests(tree.root) or (Moonlight.socket != null and not Moonlight.socket._responses.empty()):
		if OS.get_ticks_msec() > deadline:
			return false
		yield(tree,"idle_frame")
	return true

func commit(prepared):
	if not valid_payload(prepared.payload,prepared.session.user_id) or not prepared.socket.is_connected_to_host():
		return false
	var old_socket = Moonlight.socket
	for signal_info in Moonlight.get_signal_list():
		for connection in Moonlight.get_signal_connection_list(signal_info.name):
			if connection.target == Moonlight.party or connection.target == Moonlight.friends:
				Moonlight.disconnect(signal_info.name,connection.target,connection.method)
	# All target reads and connection checks succeeded before replacing anything.
	Moonlight.session = prepared.session
	Moonlight.socket = prepared.socket
	for entry in [["connected","_on_socket_connected"],["closed","_on_socket_closed"],["received_error","_on_socket_error"],["received_notification","_on_socket_notification"]]:
		Moonlight.socket.connect(entry[0],Moonlight,entry[1])
		if old_socket != null and old_socket.is_connected(entry[0],Moonlight,entry[1]):
			old_socket.disconnect(entry[0],Moonlight,entry[1])
	Moonlight.party = Moonlight_Party.new(Moonlight.socket)
	Moonlight.friends = Moonlight_Friends.new(Moonlight.socket)
	Moonlight.lobby.lobby_code = ""
	Moonlight.local_player_profile.clear()
	Moonlight.storage._storage_clear()
	Moonlight.parse_into_storage("player_fetch_data",prepared.payload)
	Moonlight.seasons = Moonlight_Seasons.new()
	Moonlight.seasons._parse_seasons(Moonlight.storage)
	Moonlight.heartbeat = Moonlight_Heartbeat.new()
	if old_socket != null:
		old_socket.close()
	return true

func discard(prepared):
	if prepared.has("socket"):
		prepared.socket.close()
