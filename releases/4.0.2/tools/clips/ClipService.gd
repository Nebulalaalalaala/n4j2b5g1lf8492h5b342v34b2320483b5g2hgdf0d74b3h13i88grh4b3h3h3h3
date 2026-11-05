extends Node

const Kit = preload("user://mod/core/workspace4/Kit.gd")
const Notices = preload("user://mod/core/workspace4/Notices.gd")
const AudioTap = preload("user://mod/tools/clips/ClipAudio.gd")
const Toast = preload("user://mod/tools/clips/ClipToast.gd")
const Highlights = preload("user://mod/tools/clips/ClipHighlights.gd")
const DEFAULTS = {"enabled":false,"duration":45,"fps":60,"height":1080,"quality":20,
	"capture_mode":"auto","compression":"balanced",
	"effects":true,"music":false,"independent_audio":true,"effects_gain":0.8,"music_gain":0.45,
	"highlights":false,"knockout":true,"race":false,"single_kills":false,"double_kills":true,"triple_kills":true,"multi_kills":true,
	"watched_players":[],"kill_window":10,"preroll":10,"postroll":3,"notifications":true,"notification_sound":true,"notification_volume":0.5,"corner":"top_right","toast_seconds":4}
signal status_changed
signal clip_saved(path)
signal settings_changed
var settings = DEFAULTS.duplicate(true)
var tool
var toast
var highlights
var audio = AudioTap.new()
var state = "off"
var message = "Replay buffer is off"
var seconds = 0.0
var elapsed = 0.0
var codec = ""
var video_height = 0
var video_fps = 0
var pid = 0
var session = ""
var start_ticks = 0.0
var results = {}
var poll_clock = 0.0
var restart_pending = false
var dirty = false
var stopping_at = 0
var backend_epoch = 0.0
var recorder_origin = 0.0
var next_command = 0
var last_hotkey = 0
var highlight_status_clock = 0

static func ensure(owner):
	var existing = owner.get_node_or_null("GoobClipStudio")
	if existing != null: return existing
	var service = load("user://mod/tools/clips/ClipService.gd").new()
	service.name = "GoobClipStudio"
	owner.add_child(service)
	service.configure(owner)
	return service

static func folder() -> String:
	var pictures = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	return ProjectSettings.globalize_path("user://goobplayability/captures") if pictures.empty() else pictures.plus_file("Goobplayability")

static func helper_path() -> String:
	# Versioned deployment leaves an already-running replay buffer intact.
	var recovered = ProjectSettings.globalize_path("user://mod/tools/clips/bin/GoobCapture-20261104f.exe")
	if File.new().file_exists(recovered): return recovered
	var paced = ProjectSettings.globalize_path("user://mod/tools/clips/bin/GoobCapture-20261103b.exe")
	if File.new().file_exists(paced): return paced
	var updated = ProjectSettings.globalize_path("user://mod/tools/clips/bin/GoobCapture-20261103.exe")
	return updated if File.new().file_exists(updated) else ProjectSettings.globalize_path("user://mod/tools/clips/bin/GoobCapture.exe")

func configure(owner) -> void:
	tool = owner
	pause_mode = Node.PAUSE_MODE_PROCESS
	var saved = SavedSettings.get_value("clip_studio",{})
	if saved is Dictionary:
		for key in DEFAULTS:
			if not saved.has(key): continue
			var expected = typeof(DEFAULTS[key])
			if typeof(saved[key])==expected or (expected in [TYPE_REAL,TYPE_INT] and typeof(saved[key]) in [TYPE_REAL,TYPE_INT]): settings[key] = saved[key]
	settings.watched_players=load("user://mod/tools/clips/ClipPlayers.gd").clean(settings.watched_players)
	settings.duration = int(clamp(float(settings.duration),5,120))
	settings.fps = 60 if int(settings.fps)>=60 else 30
	settings.height = int(clamp(float(settings.height),720,1440))
	settings.kill_window = int(clamp(float(settings.kill_window),3,20))
	settings.preroll = int(clamp(float(settings.preroll),3,30))
	settings.postroll = int(clamp(float(settings.postroll),1,10))
	if not settings.compression in ["compact","balanced","detail"]: settings.compression = "balanced"
	settings.quality = int(clamp(float(settings.quality),16,32))
	if not settings.capture_mode in ["auto","window","display"]: settings.capture_mode = "auto"
	if not settings.corner in ["top_right","bottom_right","top_left","bottom_left"]: settings.corner = "top_right"
	toast = Toast.new()
	toast.options = settings
	toast.sound_target = self
	add_child(toast)
	highlights = Highlights.new()
	add_child(highlights)
	highlights.configure(self)
	highlights.connect("highlight",self,"_highlight")
	if settings.enabled: call_deferred("start")

func set_option(key: String,value) -> void:
	if not DEFAULTS.has(key): return
	if key=="watched_players": value=load("user://mod/tools/clips/ClipPlayers.gd").clean(value)
	settings[key] = value
	if key=="highlights" and value: settings.enabled = true
	SavedSettings.set_value("clip_studio",settings.duplicate(true))
	if key in ["fps","height","quality","compression","capture_mode","effects","music","independent_audio","effects_gain","music_gain"] and pid>0: dirty = true
	if key=="highlights" and not value: highlights.disable()
	emit_signal("settings_changed")
	if key=="enabled":
		if value: start()
		else: stop()
	elif key=="highlights" and value and pid<=0: start()

func active() -> bool:
	return state in ["buffering","waiting"] and pid>0

func start() -> void:
	if pid>0: return
	var helper = helper_path()
	var encoder = ProjectSettings.globalize_path("user://mod/tools/clips/bin/ffmpeg.exe")
	var file = File.new()
	if not file.file_exists(helper) or not file.file_exists(encoder):
		_error("Install the Windows components and FFmpeg from F1 → News → Windows component setup.")
		return
	var base = ProjectSettings.globalize_path("user://goobplayability/capture-buffer")
	session = base.plus_file("session-%d-%d" % [OS.get_process_id(),OS.get_ticks_msec()])
	var dir = Directory.new()
	if dir.make_dir_recursive(session)!=OK or dir.make_dir_recursive(folder())!=OK:
		_error("Clip Studio couldn't create its capture folders.")
		return
	_cleanup_old_sessions(base)
	var config = {"pid":OS.get_process_id(),"session":session,"output":folder(),"encoder":encoder,
		"fps":settings.fps,"height":settings.height,"duration":settings.duration,"buffer":max(90,settings.duration+8),
		"quality":settings.quality,"compression":settings.compression,"sample_rate":int(AudioServer.get_mix_rate()),"capture_mode":settings.capture_mode}
	if not Kit.write_json(session.plus_file("config.json"),config):
		_error("Clip Studio couldn't write its capture settings.")
		return
	results.clear()
	seconds = 0.0
	elapsed = 0.0
	backend_epoch = 0.0
	dirty = false
	state = "starting"
	message = "Preparing game capture…"
	start_ticks = OS.get_ticks_msec()/1000.0
	pid = OS.execute(helper,PoolStringArray([session.plus_file("config.json")]),false)
	if pid<=0:
		pid = 0
		_error("The game recorder couldn't start. Try repairing its files.")
		return
	emit_signal("status_changed")

func stop() -> void:
	restart_pending = false
	highlights.disable()
	audio.stop()
	if pid<=0:
		state = "off"
		emit_signal("status_changed")
		return
	_command({"kind":"stop"})
	state = "stopping"
	message = "Finishing queued clips…"
	stopping_at = OS.get_ticks_msec()
	emit_signal("status_changed")

func restart() -> void:
	if pid<=0:
		set_option("enabled",true)
		return
	stop()
	restart_pending = true

func save_clip() -> void:
	if not active():
		toast.show_notice("No replay buffer","Turn on Instant replay in Clip Studio.","",true)
		return
	if OS.get_ticks_msec()-last_hotkey<700: return
	last_hotkey = OS.get_ticks_msec()
	# Freeze the clip boundary at the keypress, before showing the toast.
	queue_clip(settings.duration,OS.get_ticks_msec()/1000.0-recorder_origin,"Clip",0)

func queue_clip(duration: float,end: float,label: String,kills: int) -> void:
	if not active(): return
	_command({"kind":"save","duration":duration,"end":end,"label":label,"kills":kills})
	toast.show_notice("Saving clip…",("%d eliminations · " % kills if kills>0 else "")+"Keep playing. We'll finish in the background.","",false,false)

func _highlight(first: float,last: float,count: int) -> void:
	if not active(): return
	# Convert the native-event monotonic time to the recorder's video clock.
	var end = last-recorder_origin+float(settings.postroll)
	end = min(elapsed,end)
	var duration = last-first+float(settings.preroll)+float(settings.postroll)
	var label = "Double kill" if count==2 else ("Triple kill" if count==3 else ("%d kill streak"%count if count>3 else "Dash kill"))
	queue_clip(duration,end,label,count)

func _command(data: Dictionary) -> String:
	if data.get("kind","")=="save":
		audio.next_poll = 0
		audio.poll()
		audio.flush()
	next_command += 1
	var id = "%d-%05d" % [OS.get_ticks_msec(),next_command]
	data.id = id
	if not Kit.write_json(session.plus_file("commands").plus_file(id+".json"),data): _error("Couldn't send a command to the recorder.")
	return id

func _input(event) -> void:
	if tool==null or tool.get("_keybinds")==null: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if tool._keybinds.typing(): return
	if tool._keybinds.matches(event,"clip_save"):
		save_clip()
		get_tree().set_input_as_handled()

func _process(_delta: float) -> void:
	if pid<=0: return
	if active(): audio.poll()
	if OS.get_ticks_msec()-poll_clock<150: return
	poll_clock = OS.get_ticks_msec()
	var info = Kit.read_json(session.plus_file("status.json"),{})
	if not info.empty():
		var before = state
		if state!="stopping": state = str(info.get("state",state))
		message = str(info.get("message",message))
		seconds = float(info.get("seconds",seconds))
		elapsed = float(info.get("elapsed",elapsed))
		codec = str(info.get("codec",codec))
		video_height = int(info.get("height",video_height))
		video_fps = int(info.get("fps",video_fps))
		if before in ["starting","awaiting_window"] and state in ["buffering","waiting"] and float(info.get("epoch",0))>0:
			backend_epoch = float(info.get("epoch",0))
			recorder_origin = OS.get_ticks_msec()/1000.0-(float(OS.get_system_time_msecs())-backend_epoch)/1000.0
			audio.start(session,settings)
			toast.show_notice("Instant replay ready",str(settings.duration)+" seconds · "+shortcut(),"",false,false)
		if state=="error" and before!="error":
			audio.stop()
			highlights.disable()
			toast.show_notice("Recording stopped",message,"",true)
		emit_signal("status_changed")
	_read_results()
	if active() and settings.highlights: highlights.attach(tool.get("_game"))
	if OS.get_ticks_msec()-highlight_status_clock>=1000:
		highlight_status_clock = OS.get_ticks_msec()
		var report = highlights.diagnostics()
		report["updated_at"] = OS.get_unix_time()
		Kit.write_json(session.plus_file("highlights.json"),report)
	if not OS.is_process_running(pid):
		var was_stopping = state=="stopping"
		pid = 0
		audio.stop()
		highlights.disable()
		if was_stopping:
			state = "off"
			message = "Replay buffer is off"
		elif state!="error": _error("The recorder stopped unexpectedly. Existing clips are safe.")
		emit_signal("status_changed")
		if restart_pending:
			restart_pending = false
			start()
	elif state=="starting" and OS.get_ticks_msec()/1000.0-start_ticks>25:
		_command({"kind":"stop"})
		_error("The recorder didn't become ready. Restore the game window, then retry.")

func _read_results() -> void:
	var dir = Directory.new()
	if dir.open(session.plus_file("results"))!=OK: return
	dir.list_dir_begin(true,true)
	var filename = dir.get_next()
	while filename!="":
		if filename.ends_with(".json"):
			var result = Kit.read_json(session.plus_file("results").plus_file(filename),{})
			var phase = str(result.get("state",""))
			if results.get(filename,"")!=phase:
				results[filename] = phase
				if phase=="saved":
					var file = str(result.path)
					toast.show_notice("Clip saved",str(result.get("label","Clip"))+" · %.0fs"%float(result.get("duration",0)),file)
					Notices.add("clip-"+filename,"Clip saved",file.get_file(),"clips")
					emit_signal("clip_saved",file)
				elif phase=="error": toast.show_notice("Couldn't save clip",str(result.get("message","Try again.")),"",true)
		filename = dir.get_next()
	dir.list_dir_end()

func shortcut() -> String:
	return tool._keybinds.caption("clip_save") if tool!=null and tool.get("_keybinds")!=null else "Ctrl+F10"

func _error(text: String) -> void:
	state = "error"
	message = text
	if toast!=null: toast.show_notice("Clip Studio",text,"",true)
	emit_signal("status_changed")

func preview_notification() -> void:
	toast.show_notice("Clip saved","Triple kill · 45s", "",false,true,true)

func play_chime(failed: bool) -> bool:
	var helper = helper_path()
	if not File.new().file_exists(helper): return false
	var kind = "error" if failed else "saved"
	if active() and OS.is_process_running(pid):
		_command({"kind":"sound","label":kind,"volume":settings.notification_volume})
	else: OS.execute(helper,PoolStringArray(["--chime",kind,str(settings.notification_volume)]),false)
	return true

func _exit_tree() -> void:
	audio.stop()
	if pid>0: _command({"kind":"stop"})

func _cleanup_old_sessions(base: String) -> void:
	var dir = Directory.new()
	if dir.open(base)!=OK: return
	dir.list_dir_begin(true,true)
	var entry = dir.get_next()
	while entry!="":
		# Only our explicitly named cache sessions; never touch saved captures.
		var path = base.plus_file(entry)
		if dir.current_is_dir() and entry.begins_with("session-") and path!=session:
			var config = Kit.read_json(path.plus_file("config.json"),{})
			var owner = int(config.get("pid",0))
			var old_status = Kit.read_json(path.plus_file("status.json"),{})
			if owner<=0 or not OS.is_process_running(owner) or old_status.get("state","")=="stopped": _remove_cache_tree(path,base)
		entry = dir.get_next()
	dir.list_dir_end()

func _remove_cache_tree(path: String,base: String) -> void:
	if not path.replace("\\","/").begins_with(base.replace("\\","/")+"/session-"): return
	var dir = Directory.new()
	if dir.open(path)!=OK: return
	dir.list_dir_begin(true,true)
	var entry = dir.get_next()
	while entry!="":
		var child = path.plus_file(entry)
		if dir.current_is_dir(): _remove_cache_tree(child,base)
		else: dir.remove(child)
		entry = dir.get_next()
	dir.list_dir_end()
	dir.remove(path)
