extends Node

# One source service shared by the saved overlay and every editor view.
# No helper process, timers, camera or input polling when nothing consumes it.
signal tick
signal changed
signal input_changed
signal camera_changed(device)
const Doc=preload("user://mod/core/workspace4/overlays/OverlayDocument.gd")
const HELPER="user://mod/tools/overlays/bin/GoobOverlayBridge-20261104e.exe"
const HELPER_SHA="136f008296f0abb403d007415a55f7fcaf6cb8ae8ffdb7a88ee1962cc00bca2b"
var consumers={}
var tas_tool=null
var state={"sessions":[],"cameras":[],"media_error":"","camera_error":""}
var textures={}
var image_cache={}
var artwork={}
var metadata={}
var metadata_pending={}
var pressed={}
var counters={}
var focused=true
var auto_session=""
var camera_opt_in={}
var camera_running={}
var pid=-1
var session=""
var peer: StreamPeerTCP
var incoming=PoolByteArray()
var expected=0
var token=""
var startup=0
var failed=false
var next_io=0
var next_tick=0
var local_random=RandomNumberGenerator.new()
var audio: AudioStreamPlayer
var playlist=[]
var track=-1
var paused=false
var local_settings={"shuffle":false,"repeat":"off","volume":0.5}
var local_error=""
var last_position=0.0
var state_msec=0
var local_loading=false
var decoder: Thread
var decode_index=-1
var decode_cache={}
const FFMPEG="user://mod/tools/clips/bin/ffmpeg.exe"

func _ready():
	pause_mode=Node.PAUSE_MODE_PROCESS
	local_random.randomize()
	audio=AudioStreamPlayer.new()
	audio.bus="Master" # Separate from the game's SFX/music capture taps.
	add_child(audio)
	audio.connect("finished",self,"_finished")
	set_process(false)
	set_physics_process(false)
	set_process_input(false)

func register(owner: Object, item: Dictionary):
	consumers[owner.get_instance_id()]={"owner":weakref(owner),"item":item}
	if item.type=="media" and item.source.mode=="local" and playlist.empty(): set_playlist(item.source)
	_reconcile()

func unregister(owner: Object):
	consumers.erase(owner.get_instance_id())
	_reconcile()

func _reconcile():
	var bridge=false
	var keyboard=false
	var timed=false
	var wanted={}
	for id in consumers.keys():
		var owner=consumers[id].owner.get_ref()
		if not is_instance_valid(owner):
			consumers.erase(id)
			continue
		var item=consumers[id].item
		if not owner.is_visible_in_tree(): continue
		timed=timed or item.type in ["clock","fps","game","media"]
		keyboard=keyboard or item.type=="keyboard"
		bridge=bridge or (item.type=="media" and item.source.mode!="local")
		if item.type=="camera" and camera_opt_in.has(item.source.device): wanted[item.source.device]=item.source
	for device in camera_running.keys():
		if not wanted.has(device):
			command({"action":"camera_stop","device":device})
			camera_running.erase(device)
	for device in wanted:
		if not camera_running.has(device) and _connected():
			var request=wanted[device].duplicate()
			request.action="camera_start"
			command(request)
			camera_running[device]=true
	set_physics_process(keyboard)
	set_process_input(keyboard)
	if not keyboard and not pressed.empty():
		pressed.clear()
		emit_signal("input_changed")
	if bridge:
		if pid<0 and not failed: _start_bridge()
	else:
		_stop_bridge()
	set_process(bridge or timed)

func _process(_delta):
	var now=OS.get_ticks_msec()
	if pid>0 and now>=next_io:
		next_io=now+33
		_poll()
	if now>=next_tick:
		next_tick=now+250
		emit_signal("tick")

func _start_bridge():
	var file=File.new()
	if OS.get_name()!="Windows" or not file.file_exists(HELPER):
		state.media_error="Install the Windows media component from F1 → News → Windows component setup."
		state.camera_error=state.media_error
		failed=true
		emit_signal("changed")
		return
	if file.get_sha256(HELPER)!=HELPER_SHA:
		state.media_error="Source component failed its integrity check."
		state.camera_error=state.media_error
		failed=true
		emit_signal("changed")
		return
	token=Crypto.new().generate_random_bytes(32).hex_encode()
	session="user://goobplayability/overlays/sessions/"+Doc.uid()
	Directory.new().make_dir_recursive(session)
	if not Doc.write(session+"/config.json",{"pid":OS.get_process_id(),"session":ProjectSettings.globalize_path(session),"token":token}): return
	pid=OS.execute(ProjectSettings.globalize_path(HELPER),PoolStringArray([ProjectSettings.globalize_path(session+"/config.json")]),false)
	startup=OS.get_ticks_msec()
	peer=null
	incoming=PoolByteArray()
	expected=0
	if pid<=0:
		failed=true
		state.media_error="Could not start the Windows source component."

func _connected() -> bool:
	return peer!=null and peer.get_status()==StreamPeerTCP.STATUS_CONNECTED

func command(value: Dictionary):
	if not _connected(): return
	var bytes=JSON.print(value).to_utf8()
	var packet=PoolByteArray([3])
	packet.append_array(bytes)
	peer.put_32(packet.size())
	peer.put_data(packet)

func _poll():
	if pid>0 and peer==null:
		var status=Doc.read(session+"/status.json")
		if status.get("ready",false):
			peer=StreamPeerTCP.new()
			peer.big_endian=false
			if peer.connect_to_host("127.0.0.1",int(status.get("port",0)))!=OK: _bridge_error("Could not connect to Windows sources.")
		elif status.has("error") or OS.get_ticks_msec()-startup>15000:
			_bridge_error(str(status.get("error","Windows sources did not respond.")))
	if peer!=null:
		if _connected():
			if not token.empty():
				command({"token":token})
				token=""
				for path in metadata_pending: command({"action":"file_metadata","path":path})
				metadata_pending.clear()
				_reconcile()
			if not _connected(): return
			var available=peer.get_available_bytes()
			if available>0:
				var result=peer.get_data(min(available,4194308))
				if result[0]==OK: incoming.append_array(result[1])
			var began=OS.get_ticks_usec()
			while incoming.size()>=4 and OS.get_ticks_usec()-began<2500:
				if expected==0:
					expected=int(incoming[0])|(int(incoming[1])<<8)|(int(incoming[2])<<16)|(int(incoming[3])<<24)
					if expected<1 or expected>4194304:
						_bridge_error("Invalid source response.")
						break
				if incoming.size()<expected+4: break
				var packet=incoming.subarray(4,expected+3)
				incoming=incoming.subarray(expected+4,incoming.size()-1) if incoming.size()>expected+4 else PoolByteArray()
				expected=0
				_packet(packet)
		elif peer.get_status()==StreamPeerTCP.STATUS_ERROR or peer.get_status()==StreamPeerTCP.STATUS_NONE:
			_bridge_error("Windows source connection closed. Reopen the editor to retry.")

func _packet(packet: PoolByteArray):
	if packet[0]==2:
		var parsed=JSON.parse(packet.subarray(1,packet.size()-1).get_string_from_utf8())
		if parsed.error!=OK or not parsed.result is Dictionary: return
		var data=parsed.result
		if data.get("kind")=="file":
			var path=str(data.get("path",""))
			artwork.erase(path)
			_artwork(data)
			data.erase("artwork")
			metadata[path]=data
		elif data.get("kind")=="state":
			for entry in data.get("sessions",[]):
				if not str(entry.get("info",{}).get("artwork","")).empty(): _artwork(entry.info)
			state=data
			if not str(state.get("camera_error","")).empty():
				camera_opt_in.clear()
				textures.clear()
			state_msec=OS.get_ticks_msec()
			_reconcile()
		emit_signal("changed")
	elif packet[0]==1 and packet.size()>19:
		var length=int(packet[1])|(int(packet[2])<<8)
		if length<1 or length>2048 or packet.size()<=19+length: return
		var device=packet.subarray(3,2+length).get_string_from_utf8()
		var image=Image.new()
		if image.load_png_from_buffer(packet.subarray(19+length,packet.size()-1))==OK:
			if image.get_width()>4096 or image.get_height()>4096: return
			if not textures.has(device): textures[device]=ImageTexture.new()
			textures[device].create_from_image(image,Texture.FLAG_FILTER)
			emit_signal("camera_changed",device)

func _bridge_error(message: String):
	state.sessions=[]
	state.active_cameras=[]
	state.media_error=message
	state.camera_error=message
	failed=true
	_stop_bridge()
	emit_signal("changed")

func retry():
	failed=false
	_reconcile()

func _stop_bridge():
	if _connected(): command({"action":"stop"})
	if peer!=null: peer.disconnect_from_host()
	peer=null
	# Only this service's helper PID is ever eligible for shutdown.
	if pid>0 and OS.is_process_running(pid): OS.kill(pid)
	pid=-1
	textures.clear()
	camera_running.clear()
	if not session.empty():
		var dir=Directory.new()
		for name in ["config.json","config.json.tmp","status.json","status.json.tmp"]:
			var path=session+"/"+name
			if dir.file_exists(path): dir.remove(path)
		dir.remove(session) # Only this session's empty directory; never recursive.
		session=""

func _notification(what):
	if what==MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		focused=false
		pressed.clear()
		emit_signal("input_changed")
	elif what==MainLoop.NOTIFICATION_WM_FOCUS_IN: focused=true

func _input(_event):
	_physics_process(0)

func _physics_process(_delta):
	var next={}
	if focused:
		for entry in consumers.values():
			var owner=entry.owner.get_ref()
			if not is_instance_valid(owner) or not owner.is_visible_in_tree() or entry.item.type!="keyboard": continue
			for key in entry.item.source.keys:
				var id=key_id(key)
				if not next.has(id):
					next[id]=Input.is_action_pressed(key.action) if not str(key.action).empty() and InputMap.has_action(key.action) else (Input.is_mouse_button_pressed(int(key.code)) if key.kind=="mouse" else Input.is_key_pressed(int(key.code)))
	var changed=next.size()!=pressed.size()
	for id in next:
		if not pressed.has(id) or bool(next[id])!=bool(pressed[id]): changed=true
	if changed:
		for key in next:
			if next[key] and not pressed.get(key,false): counters[key]=int(counters.get(key,0))+1
		pressed=next
		emit_signal("input_changed")

func game_info(field: String) -> String:
	var game=tas_tool.call("_find_game") if is_instance_valid(tas_tool) and tas_tool.has_method("_find_game") else null
	if game==null or not is_instance_valid(game): return "Workspace" if field=="location" else "Not in a level"
	if field=="players": return str(game.get_player_count())+" players"
	if field=="location": return "Match" if game.is_in_regular_play() else "Level"
	var level=game.get("level")
	if level!=null and level.get("loaded_level")!=null:
		return str(level.loaded_level.get("level_name"))
	return "Loading level…"

func game_card(field: String) -> Dictionary:
	var game=tas_tool.call("_find_game") if is_instance_valid(tas_tool) and tas_tool.has_method("_find_game") else null
	if game==null or not is_instance_valid(game): return {"title":"Ready for the next level" if field=="level" else game_info(field),"detail":"Level details appear when you enter a level","label":"LEVEL","active":false,"author":"","theme":"","rating":0.0,"players":0,"mode":""}
	var level=game.get("level")
	var loaded=level.get("loaded_level") if is_instance_valid(level) else null
	var data={"title":game_info(field),"detail":"","label":"CURRENT LEVEL","active":is_instance_valid(loaded),"author":"","theme":"","rating":0.0,"players":game.get_player_count(),"mode":"LOBBY" if game.is_in_lobby() else ("MATCH" if game.is_in_regular_play() else "LEVEL")}
	# These native LevelInstance properties are the exact fields used by LevelJson.
	# No network request or repeated level JSON parsing is needed.
	if is_instance_valid(loaded):
		data.author=str(loaded.author_name)
		data.theme=str(loaded.level_theme)
		data.rating=float(loaded.rating)
	if field!="level":
		data.label={"location":"LOCATION","players":"PLAYERS"}.get(field,"LEVEL")
		data.detail=game_info("level")
	return data

func key_id(key: Dictionary) -> String:
	return str(key.get("action",""))+":"+str(key.get("kind","key"))+":"+str(key.get("code",0))

func camera_enable(_device: String, _value: bool):
	state.camera_error = "Handcam is unavailable in 4.0."
	emit_signal("changed")


func media(source: Dictionary) -> Dictionary:
	if source.mode=="local": return local_media()
	var sessions=state.get("sessions",[])
	var selected={}
	if source.session!="auto":
		for value in sessions:
			if value.id==source.session:
				selected=value
				break
		if selected.empty() and not str(source.app).empty():
			for value in sessions:
				if value.app==source.app:
					selected=value
					if value.get("playing",false): break
	if selected.empty() and source.session=="auto":
		for value in sessions:
			if value.id==auto_session: selected=value
		if selected.empty() or not selected.get("playing",false):
			for value in sessions:
				if value.get("playing",false):
					selected=value
					break
		if selected.empty():
			for value in sessions:
				if value.id==state.get("current",""): selected=value
		if selected.empty() and not sessions.empty(): selected=sessions[0]
		if not selected.empty(): auto_session=selected.id
	if selected.empty(): return {"title":"No active media" if str(state.get("media_error","")).empty() else "Media unavailable","artist":str(state.get("media_error","")),"playing":false,"duration":0.0,"position":0.0,"controls":{},"id":""}
	var info=selected.get("info",{})
	var result={"id":selected.id,"title":str(info.get("title","Untitled")),"artist":str(info.get("artist","")),"album":str(info.get("album","")),"app":selected.app,"playing":selected.playing,"position":float(selected.position),"duration":float(selected.duration),"controls":selected.controls}
	if result.playing: result.position=min(result.duration,result.position+(OS.get_ticks_msec()-state_msec)/1000.0)
	result.artwork=_artwork(info)
	return result

func _artwork(info: Dictionary):
	var bytes=str(info.get("artwork",""))
	var key=str(info.get("revision",""))
	if key.empty(): key=str(hash(bytes))
	if artwork.has(key): return artwork[key]
	var texture=null
	if not bytes.empty():
		var raw=Marshalls.base64_to_raw(bytes)
		var image=Image.new()
		if raw.size()>8 and raw[0]==137 and image.load_png_from_buffer(raw)==OK and not image.is_empty():
			texture=ImageTexture.new()
			texture.create_from_image(image,Texture.FLAG_FILTER)
			if artwork.size()>32: artwork.clear()
	artwork[key]=texture
	return texture

func control(action: String, source: Dictionary, seconds=0.0):
	if source.mode=="local":
		match action:
			"toggle":
				if not audio.playing: play_track(max(0,track))
				else:
					paused=not paused
					audio.stream_paused=paused
			"next": play_track(_next_index(1))
			"previous": play_track(_next_index(-1))
			"seek":
				if audio.stream!=null: audio.seek(clamp(seconds,0,audio.stream.get_length()))
	else:
		var current=media(source)
		if current.get("controls",{}).get(action,false): command({"action":action,"session":current.id,"seconds":seconds})
	emit_signal("changed")

func set_playlist(source: Dictionary):
	var playing_path=playlist[track] if track>=0 and track<playlist.size() else ""
	playlist=source.playlist.duplicate()
	if not str(playing_path).empty():
		track=playlist.find(playing_path)
		if track<0:
			audio.stop()
			audio.stream=null
			last_position=0
	local_settings={"shuffle":source.shuffle,"repeat":source.repeat,"volume":source.volume}
	audio.volume_db=linear2db(max(0.0001,float(source.volume)))
	if playlist.empty() or track>=playlist.size():
		audio.stop()
		audio.stream=null
		last_position=0
		track=-1

func _next_index(direction: int) -> int:
	if playlist.empty(): return -1
	if local_settings.shuffle and direction>0: return local_random.randi_range(0,playlist.size()-1)
	return posmod(track+direction,playlist.size())

func play_track(index: int):
	if index<0 or index>=playlist.size(): return
	var path=str(playlist[index])
	var file=File.new()
	if file.open(path,File.READ)!=OK:
		local_error="File is missing: "+path.get_file()
		emit_signal("changed")
		return
	if file.get_len()>134217728:
		file.close()
		local_error="Audio file exceeds 128 MB."
		emit_signal("changed")
		return
	var data=file.get_buffer(file.get_len())
	file.close()
	var stream=null
	match path.get_extension().to_lower():
		"mp3":
			if ClassDB.class_exists("AudioStreamMP3"):
				stream=ClassDB.instance("AudioStreamMP3")
				stream.data=data
			else:
				_decode_audio(index,path)
				return
		"ogg":
			if ClassDB.class_exists("AudioStreamOGGVorbis"):
				stream=ClassDB.instance("AudioStreamOGGVorbis")
				stream.data=data
			else:
				_decode_audio(index,path)
				return
		"wav": stream=_wav(data)
	if stream==null or stream.get_length()<=0:
		local_error="Unsupported or damaged audio. WAV requires PCM 8/16-bit."
		emit_signal("changed")
		return
	_play_stream(stream,index,path)

func _play_stream(stream, index: int, path: String):
	audio.stream=stream
	audio.volume_db=linear2db(max(0.0001,float(local_settings.volume)))
	audio.stream_paused=false
	paused=false
	track=index
	local_error=""
	last_position=0
	audio.play()
	var absolute=ProjectSettings.globalize_path(path)
	if _connected(): command({"action":"file_metadata","path":absolute})
	elif metadata_pending.size()<256: metadata_pending[absolute]=true
	emit_signal("changed")

func _decode_audio(index: int, path: String):
	if local_loading: return
	var key=path+":"+str(File.new().get_modified_time(path))
	if decode_cache.has(key):
		var file=File.new()
		if file.open(decode_cache[key],File.READ)==OK:
			var bytes=file.get_buffer(file.get_len())
			file.close()
			var stream=_wav(bytes)
			if stream!=null:
				_play_stream(stream,index,path)
				return
	if not File.new().file_exists(FFMPEG):
		local_error="This codec needs the installed audio decoder."
		emit_signal("changed")
		return
	local_loading=true
	local_error="Preparing audio…"
	var target="user://goobplayability/overlays/audio-cache/"+key.sha256_text()+".wav"
	Directory.new().make_dir_recursive(target.get_base_dir())
	decoder=Thread.new()
	decoder.start(self,"_decode_worker",{"index":index,"path":path,"target":target,"key":key})
	emit_signal("changed")

func _decode_worker(job: Dictionary):
	var args=PoolStringArray(["-hide_banner","-loglevel","error","-nostdin","-y","-i",ProjectSettings.globalize_path(job.path),"-vn","-t","601","-ac","2","-ar","44100","-c:a","pcm_s16le",ProjectSettings.globalize_path(job.target)])
	job.exit=OS.execute(ProjectSettings.globalize_path(FFMPEG),args,true)
	call_deferred("_decoded",job)
	return null

func _decoded(job: Dictionary):
	if decoder!=null:
		decoder.wait_to_finish()
		decoder=null
	local_loading=false
	var file=File.new()
	var stream=null
	if job.exit==0 and file.open(job.target,File.READ)==OK:
		if file.get_len()<=134217728: stream=_wav(file.get_buffer(file.get_len()))
		file.close()
	if stream==null or stream.get_length()>600:
		local_error="Audio could not be decoded. Local tracks support up to 10 minutes."
		Directory.new().remove(job.target)
		emit_signal("changed")
		return
	_trim_audio_cache(job.target)
	decode_cache[job.key]=job.target
	if job.index<playlist.size() and playlist[job.index]==job.path: _play_stream(stream,job.index,job.path)

func _trim_audio_cache(keep: String):
	var folder="user://goobplayability/overlays/audio-cache/"
	var dir=Directory.new()
	if dir.open(folder)!=OK: return
	var entries=[]
	var total=0
	dir.list_dir_begin(true,true)
	var name=dir.get_next()
	while not name.empty():
		# These are generated decoder caches, never the user's imported tracks.
		if name.ends_with(".wav") and name.get_basename().length()==64 and name.get_basename().is_valid_hex_number(false):
			var path=folder+name
			var file=File.new()
			if file.open(path,File.READ)==OK:
				var bytes=file.get_len()
				file.close()
				total+=bytes
				if path!=keep: entries.append([file.get_modified_time(path),path,bytes])
		name=dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(self,"_older_cache")
	for entry in entries:
		if total<=536870912: break
		if dir.remove(entry[1])==OK: total-=entry[2]

func _older_cache(a, b) -> bool: return a[0]<b[0]

func _wav(bytes: PoolByteArray):
	if bytes.size()<44 or bytes.subarray(0,3).get_string_from_ascii()!="RIFF" or bytes.subarray(8,11).get_string_from_ascii()!="WAVE": return null
	var reader=StreamPeerBuffer.new()
	reader.data_array=bytes
	reader.big_endian=false
	var offset=12
	var format=0
	var channels=0
	var rate=0
	var bits=0
	var samples=PoolByteArray()
	while offset+8<=bytes.size():
		reader.seek(offset+4)
		var length=reader.get_u32()
		if length>bytes.size()-offset-8: return null
		var kind=bytes.subarray(offset,offset+3).get_string_from_ascii()
		if kind=="fmt " and length>=16:
			format=reader.get_u16()
			channels=reader.get_u16()
			rate=reader.get_u32()
			reader.seek(offset+22)
			bits=reader.get_u16()
		elif kind=="data" and length>0: samples=bytes.subarray(offset+8,offset+7+length)
		offset+=8+length+(length%2)
	if format!=1 or not channels in [1,2] or not bits in [8,16] or rate<8000 or rate>192000 or samples.empty(): return null
	var stream=AudioStreamSample.new()
	stream.format=AudioStreamSample.FORMAT_8_BITS if bits==8 else AudioStreamSample.FORMAT_16_BITS
	stream.stereo=channels==2
	stream.mix_rate=rate
	if bits==8:
		for i in samples.size(): samples[i]=(samples[i]+128)%256
	stream.data=samples
	return stream

func _finished():
	if local_settings.repeat=="one": play_track(track)
	elif local_settings.repeat=="all" or local_settings.shuffle or track+1<playlist.size(): play_track(_next_index(1))
	else:
		last_position=audio.stream.get_length() if audio.stream!=null else 0.0
		emit_signal("changed")
		_reconcile()

func local_media() -> Dictionary:
	var path=str(playlist[track]) if track>=0 and track<playlist.size() else ""
	var info=metadata.get(path,{})
	var title=str(info.get("title",""))
	if title.empty(): title=path.get_file().get_basename() if not path.empty() else "Choose audio files"
	var artist=str(info.get("artist",""))
	if not local_error.empty(): artist=local_error
	return {"id":"local","title":title,"artist":artist,"album":str(info.get("album","")),"artwork":_artwork(info),"app":"Local audio","playing":audio.playing and not paused,"position":audio.get_playback_position() if audio.playing else last_position,"duration":audio.stream.get_length() if audio.stream!=null else 0.0,"controls":{"toggle":not playlist.empty() and not local_loading,"next":playlist.size()>1 and not local_loading,"previous":playlist.size()>1 and not local_loading,"seek":audio.stream!=null and not local_loading,"volume":true}}

func stop():
	image_cache.clear()
	artwork.clear()
	metadata.clear()
	metadata_pending.clear()
	pressed.clear()
	consumers.clear()
	camera_opt_in.clear()
	_stop_bridge()
	if audio!=null:
		audio.stop()
		audio.stream=null
	last_position=0
	set_process(false)
	set_physics_process(false)
	set_process_input(false)

func _exit_tree():
	if decoder!=null:
		decoder.wait_to_finish()
		decoder=null
	_stop_bridge()
	if audio!=null: audio.stop()
