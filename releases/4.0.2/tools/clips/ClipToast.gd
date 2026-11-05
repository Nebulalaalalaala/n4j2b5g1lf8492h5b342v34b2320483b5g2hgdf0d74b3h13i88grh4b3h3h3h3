extends CanvasLayer

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
var options = {}
var card
var bar
var title_label
var detail_label
var icon
var open_button
var deadline = 0
var entered = 0
var closing = false
var path = ""
var target = Vector2.ZERO
var sound
var sound_target

func _ready() -> void:
	layer = 120
	pause_mode = Node.PAUSE_MODE_PROCESS
	card = PanelContainer.new()
	card.rect_min_size = Vector2(356,100)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	add_child(card)
	var column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_constant_override("separation",10)
	card.add_child(column)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_constant_override("separation",12)
	column.add_child(row)
	icon = TextureRect.new()
	icon.rect_min_size = Vector2(28,28)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand = true
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var words = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	title_label = _label(16)
	words.add_child(title_label)
	detail_label = _label(13)
	detail_label.rect_min_size.x = 220
	detail_label.autowrap = true
	words.add_child(detail_label)
	open_button = Button.new()
	open_button.text = "Open"
	open_button.focus_mode = Control.FOCUS_NONE
	open_button.add_font_override("font",_font(13))
	open_button.connect("pressed",self,"_open")
	row.add_child(open_button)
	bar = ColorRect.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.rect_min_size = Vector2(0,2)
	column.add_child(bar)
	sound = AudioStreamPlayer.new()
	sound.bus = "Master" # Own UI sound; outside sfx_main/music capture taps.
	add_child(sound)

func _font(size: int) -> DynamicFont:
	var result = DynamicFont.new()
	result.font_data = load("user://mod/shared/assets/fonts/Inter-SemiBold.ttf")
	result.size = size
	result.use_filter = true
	return result

func _label(size: int) -> Label:
	var result = Label.new()
	result.add_font_override("font",_font(size))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func show_notice(title: String, detail: String, file := "", failed := false, play_sound := true, force := false) -> void:
	if not force and not options.get("notifications",true):
		if play_sound and options.get("notification_sound",true): _chime(failed)
		return
	path = file
	closing = false
	var accent = Galaxy.color("danger") if failed else Galaxy.color("accent")
	card.add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),accent,16,12))
	icon.texture = Galaxy.icon("clip",accent,28)
	title_label.text = title
	title_label.add_color_override("font_color",Galaxy.color("ink"))
	detail_label.text = detail
	detail_label.add_color_override("font_color",Galaxy.color("muted"))
	bar.color = accent
	open_button.visible = not file.empty()
	open_button.add_color_override("font_color",Galaxy.color("ink"))
	open_button.add_stylebox_override("normal",Galaxy.box(Galaxy.color("raised"),Galaxy.color("border"),8,8))
	open_button.add_stylebox_override("hover",Galaxy.box(Galaxy.color("hover"),accent,8,8))
	open_button.add_stylebox_override("focus",StyleBoxEmpty.new())
	card.rect_size = Vector2(356,0)
	_place()
	entered = OS.get_ticks_msec()
	deadline = entered+int(float(options.get("toast_seconds",4))*1000)
	card.visible = true
	var reduced = bool(SavedSettings.get_value("workspace_reduced_motion",false))
	card.modulate.a = 1.0 if reduced else 0.0
	card.rect_position = target if reduced else target+Vector2(32 if str(options.get("corner","top_right")).ends_with("right") else -32,0)
	if play_sound and options.get("notification_sound",true): _chime(failed)

func _place() -> void:
	if card == null: return
	# Work in physical pixels so a 2x game stretch doesn't double toast size.
	var final = get_viewport().get_final_transform()
	transform = final.affine_inverse()
	var area = final.xform(get_viewport().get_visible_rect().size)
	var corner = str(options.get("corner","top_right"))
	var width = min(356,max(220,area.x-32))
	card.rect_min_size.x = width
	card.rect_size.x = width
	target = Vector2(area.x-width-20 if corner.ends_with("right") else 20,area.y-card.rect_size.y-20 if corner.begins_with("bottom") else 24)
	if card.visible and OS.get_ticks_msec()-entered>300: card.rect_position = target

func _process(_delta: float) -> void:
	if card == null or not card.visible: return
	_place()
	var now = OS.get_ticks_msec()
	bar.rect_scale.x = clamp(float(deadline-now)/max(1,deadline-entered),0.0,1.0)
	var reduced = bool(SavedSettings.get_value("workspace_reduced_motion",false))
	if now<deadline:
		var fraction = 1.0-pow(1.0-clamp((now-entered)/240.0,0.0,1.0),3)
		card.rect_position = target if reduced else target+Vector2((1-fraction)*(32 if str(options.get("corner","top_right")).ends_with("right") else -32),0)
		card.modulate.a = 1.0 if reduced else clamp((now-entered)/180.0,0.0,1.0)
	else:
		var fraction = clamp((now-deadline)/180.0,0.0,1.0)
		card.modulate.a = 0.0 if reduced else 1-fraction
		card.rect_position = target+Vector2(0,-8*fraction)
		if reduced or fraction>=1: card.visible = false

func _chime(failed: bool) -> void:
	if sound_target!=null and sound_target.play_chime(failed): return
	var file = File.new()
	var asset = "user://mod/tools/clips/assets/clip-error.wav" if failed else "user://mod/tools/clips/assets/clip-saved.wav"
	if file.open(asset,File.READ) != OK: return
	var bytes = file.get_buffer(file.get_len())
	file.close()
	if bytes.size()<=44: return
	var stream = AudioStreamSample.new()
	stream.format = AudioStreamSample.FORMAT_16_BITS
	stream.mix_rate = 48000
	stream.stereo = false
	stream.data = bytes.subarray(44,bytes.size()-1)
	sound.stream = stream
	sound.volume_db = linear2db(max(0.001,float(options.get("notification_volume",0.5))))
	sound.play()

func _open() -> void:
	if not path.empty(): OS.shell_open(path)
