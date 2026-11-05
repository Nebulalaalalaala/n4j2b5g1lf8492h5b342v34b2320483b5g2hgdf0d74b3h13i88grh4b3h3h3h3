extends Reference

# Capture effects run BEFORE the bus fader in the shipped Godot 3.5 mixer.
# Tap sfx_main once (its children are already included), plus music separately.
# Never change a bus's volume, mute flag, send, or the player's audio settings.
var taps = []
var options = {}
var session = ""
var sample_rate = 48000
var discarded = 0
var next_poll = 0
var next_flush = 0

func start(directory: String, settings: Dictionary) -> void:
	stop()
	session = directory
	options = settings.duplicate(true)
	sample_rate = int(AudioServer.get_mix_rate())
	for spec in [["sfx_main","effects"],["music","music"]]:
		if not options.get(spec[1],false): continue
		var index = AudioServer.get_bus_index(spec[0])
		if index < 0: continue
		var capture = AudioEffectCapture.new()
		capture.buffer_length = 2.0
		AudioServer.add_bus_effect(index,capture)
		taps.append({"bus":spec[0],"kind":spec[1],"capture":capture,"epoch":0.0,"frames":0,"discarded":0,"file":null,"bucket":-1})

func poll() -> void:
	var now = OS.get_ticks_msec()
	if now < next_poll: return
	next_poll = now + 20
	for tap in taps:
		var capture = tap.capture
		var count = capture.get_frames_available()
		if count == 0: continue
		var drops = capture.get_discarded_frames()
		if drops != tap.discarded:
			discarded += max(0,drops-tap.discarded)
			tap.discarded = drops
			tap.epoch = 0.0
		var samples = capture.get_buffer(count)
		if samples.empty(): continue
		if tap.epoch == 0.0:
			# The mixer runs ahead of the speakers. Match the screen's presentation
			# clock, rather than placing pre-output audio early in the video.
			tap.epoch = float(OS.get_system_time_msecs()) - count*1000.0/sample_rate - AudioServer.get_time_since_last_mix()*1000.0 + AudioServer.get_output_latency()*1000.0
			tap.frames = 0
		var stamp = tap.epoch + tap.frames*1000.0/sample_rate
		tap.frames += count
		var bucket = int(stamp/2000.0)
		if tap.bucket != bucket:
			if tap.file != null: tap.file.close()
			tap.file = File.new()
			var path = session.plus_file("audio-%d-%s.gca" % [bucket,tap.kind])
			if tap.file.open(path,File.WRITE) != OK:
				tap.file = null
				continue
			tap.bucket = bucket
		if tap.file == null: continue
		var gain = float(options.get(tap.kind+"_gain",0.8))
		if not options.get("independent_audio",true):
			var source = AudioServer.get_bus_index(tap.bus)
			gain *= _audible_gain(source)*_audible_gain(0)
		# var2bytes is a native bulk copy. Its first 8 bytes are the variant
		# type/count; the rest is the stereo float32 payload (verified in tests).
		if not is_equal_approx(gain,1.0): samples = Transform2D(Vector2(gain,0),Vector2(0,gain),Vector2.ZERO).xform(samples)
		var encoded = var2bytes(samples)
		tap.file.store_64(int(stamp*1000.0))
		tap.file.store_32(count)
		tap.file.store_buffer(encoded.subarray(8,encoded.size()-1))
	if now >= next_flush:
		flush()
		next_flush = now + 100

func flush() -> void:
	for tap in taps:
		if tap.file != null: tap.file.flush()

func _audible_gain(index: int) -> float:
	if index < 0 or AudioServer.is_bus_mute(index): return 0.0
	return db2linear(AudioServer.get_bus_volume_db(index))

func stop() -> void:
	for tap in taps:
		if tap.file != null: tap.file.close()
		var index = AudioServer.get_bus_index(tap.bus)
		if index < 0: continue
		for slot in range(AudioServer.get_bus_effect_count(index)-1,-1,-1):
			if AudioServer.get_bus_effect(index,slot) == tap.capture:
				AudioServer.remove_bus_effect(index,slot)
	taps.clear()
	next_poll = 0
	next_flush = 0
