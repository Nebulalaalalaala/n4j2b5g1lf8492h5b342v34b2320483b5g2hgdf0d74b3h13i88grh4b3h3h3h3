extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Journey UI sounds from journey-assets/sfx_<key>.wav (16-bit mono PCM).
# Plays on the game's SFX bus when it has one, so the game's volume and mute
# apply; Journey's own sounds/volume prefs apply on top.
const KEYS = ["click","toggle","tick","claim","rankup","league","open"]
var enabled = true
var volume = 0.8
var streams = {}
var players = []
var next_player = 0
var last_tick = 0

func _init(base_dir: String):
	for key in KEYS:
		var stream = _load_wav(ModPaths.JOURNEY_ASSETS_DIR + "sfx_"+key+".wav")
		if stream!=null:
			streams[key] = stream
	var bus = "Master"
	for name in ["SFX","Sfx","sfx","Effects"]:
		if AudioServer.get_bus_index(name)>=0:
			bus = name
			break
	for i in range(6):
		var player = AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		players.append(player)

# pitch > 1 raises it (the XP count-up climbs as it goes); clicks get a tiny
# random variation so repeated taps don't sound machine-like.
func play(key: String, pitch: float = 1.0):
	if not enabled or volume<=0.0 or not streams.has(key):
		return
	if key=="tick":
		var now = OS.get_ticks_msec()
		if now-last_tick<45:
			return
		last_tick = now
	# Prefer an idle player so long fanfares aren't cut off by quick ticks.
	var player = null
	for candidate in players:
		if not candidate.playing:
			player = candidate
			break
	if player==null:
		player = players[next_player]
		next_player = (next_player+1)%players.size()
	player.stream = streams[key]
	player.volume_db = linear2db(clamp(volume,0.0,1.0))
	if key=="click" or key=="toggle":
		pitch *= rand_range(0.96,1.04)
	player.pitch_scale = clamp(pitch,0.5,2.5)
	player.play()

func _load_wav(path: String):
	var file = File.new()
	if file.open(path,File.READ)!=OK:
		return null
	var bytes = file.get_buffer(file.get_len())
	file.close()
	if bytes.size()<44 or bytes.subarray(0,3).get_string_from_ascii()!="RIFF":
		return null
	# Walk chunks for fmt and data; only 16-bit PCM is accepted.
	var pos = 12
	var channels = 1
	var rate = 44100
	var bits = 16
	var data = null
	while pos+8<=bytes.size():
		var id = bytes.subarray(pos,pos+3).get_string_from_ascii()
		var size = bytes[pos+4]|(bytes[pos+5]<<8)|(bytes[pos+6]<<16)|(bytes[pos+7]<<24)
		if id=="fmt ":
			channels = bytes[pos+10]|(bytes[pos+11]<<8)
			rate = bytes[pos+12]|(bytes[pos+13]<<8)|(bytes[pos+14]<<16)|(bytes[pos+15]<<24)
			bits = bytes[pos+22]|(bytes[pos+23]<<8)
		elif id=="data":
			data = bytes.subarray(pos+8,min(bytes.size(),pos+8+size)-1)
		pos += 8+size+(size%2)
	if data==null or bits!=16:
		return null
	var stream = AudioStreamSample.new()
	stream.format = AudioStreamSample.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels==2
	stream.data = data
	return stream
