extends Reference
const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const PageTabs = preload("user://mod/core/workspace4/PageTabs.gd")
const Service = preload("user://mod/tools/clips/ClipService.gd")
var menu
var service
var content_root
var tabs
var status
var buffer_label
var progress
var save_button
var enabled
var apply_button
var apply_buttons = []
var key_button
var controls = {}
var duration_buttons = {}
var duration_grid
var library_rows
var library_count
var library_filter = "all"
var library_page = 0
var library_times = {}
var previous_button
var next_button
var shot_status
var hide_menu
var automatic_toggle
var automatic_status

static func folder() -> String: return Service.folder()

func build(owner_menu,content: VBoxContainer) -> void:
	menu = owner_menu
	content_root = content
	service = Service.ensure(menu.tas_tool)
	tabs = PageTabs.new()
	content.add_child(tabs)
	tabs.setup("clips",menu.font(15))
	_build_capture(tabs.add_tab("Capture","clip"))
	_build_highlights(tabs.add_tab("Highlights","trophy"))
	_build_library(tabs.add_tab("Library","folder"))
	_build_preferences(tabs.add_tab("Settings","settings"))
	tabs.finish()
	service.connect("status_changed",self,"_refresh")
	service.connect("settings_changed",self,"_refresh")
	service.connect("clip_saved",self,"_clip_saved")
	content.connect("visibility_changed",self,"_refresh")
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.pause_mode = Node.PAUSE_MODE_PROCESS
	content.add_child(timer)
	timer.connect("timeout",self,"_refresh")
	timer.start()
	_refresh()
	refresh()

func _build_capture(parent: VBoxContainer) -> void:
	var hero = menu.card(parent,"Instant replay",Galaxy.color("record"))
	var heading = Kit.row(hero)
	enabled = _switch(heading,"Instant replay","enabled","Keeps recent game footage ready for your clip key. Nothing is uploaded.")
	heading.add_child(menu._spacer())
	status = menu.label("Off",14,Galaxy.color("muted"))
	heading.add_child(status)
	var automatic_row = Kit.row(hero)
	automatic_toggle = _plain_check(automatic_row,"Automatic highlights",bool(service.settings.highlights))
	automatic_toggle.hint_tooltip = "Detect dash kills and save matching streaks. Instant replay alone only enables the clip key."
	automatic_toggle.connect("toggled",self,"_option_changed",["highlights"])
	automatic_status = menu.label("",13,Galaxy.color("muted"))
	automatic_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	automatic_status.autowrap = true
	automatic_row.add_child(automatic_status)
	var presets = Kit.column(hero,6)
	presets.add_child(menu.label("Save the last",14,Galaxy.color("muted")))
	duration_grid = GridContainer.new()
	duration_grid.columns = 6
	duration_grid.add_constant_override("hseparation",6)
	duration_grid.add_constant_override("vseparation",6)
	presets.add_child(duration_grid)
	for seconds in [15,30,45,60,90,120]:
		duration_buttons[seconds] = Kit.action(menu,duration_grid,str(seconds)+"s","",self,"_duration",[seconds])
		duration_buttons[seconds].hint_tooltip = "A warming buffer saves the footage available so far."
	progress = ProgressBar.new()
	progress.rect_min_size.y = 6
	progress.percent_visible = false
	progress.add_font_override("font",menu.font(1))
	progress.add_stylebox_override("bg",Galaxy.box(Galaxy.color("raised"),Color.transparent,0,3))
	progress.add_stylebox_override("fg",Galaxy.box(Galaxy.color("accent"),Color.transparent,0,3))
	hero.add_child(progress)
	buffer_label = menu.label("",14,Galaxy.color("muted"))
	buffer_label.autowrap = true
	hero.add_child(buffer_label)
	var actions = Kit.row(hero)
	save_button = Kit.action(menu,actions,"Save last 45s","clip",service,"save_clip",[],true)
	key_button = Kit.action(menu,actions,service.shortcut(),"keyboard",self,"_shortcut")
	key_button.hint_tooltip = "Change the clip shortcut."
	actions.add_child(menu._spacer())
	Kit.action(menu,actions,"Open folder","folder",self,"_open_folder")
	apply_button = Kit.action(menu,hero,"Apply capture changes · restart buffer","redo",service,"restart")
	apply_button.hint_tooltip = "Finishes queued clips, then starts a fresh buffer with your new settings."
	apply_buttons.append(apply_button)
	var quality = menu.card(parent,"Picture",Galaxy.color("playback"))
	var presets_row = Kit.row(quality)
	for spec in [["Balanced",720,60,22],["High",1080,60,20],["Ultra",1440,60,18]]:
		var button = Kit.action(menu,presets_row,spec[0],"",self,"_quality",[spec])
		button.hint_tooltip = "%dp · %d FPS" % [spec[1],spec[2]]
	_choice(quality,"File size","compression",[["Compact","compact"],["Balanced","balanced"],["Highest detail","detail"]],"Compact saves more space; Balanced keeps smooth 60 FPS with a sensible bitrate. Highest detail uses the previous larger-file encoding. Apply to restart the buffer.")
	_choice(quality,"Resolution","height",[["720p",720],["1080p",1080],["1440p",1440]],"Keeps the game's aspect ratio; never upscales a smaller window.")
	_choice(quality,"Frame rate","fps",[["30 FPS",30],["60 FPS",60]],"60 FPS is smoother; 30 FPS reduces encoder load.")
	_choice(quality,"Source","capture_mode",[["Auto","auto"],["Game window","window"],["Display while focused","display"]],"Auto uses the game window normally and the game's display area in fullscreen. Display capture pauses when you switch away.")
	var shots = menu.card(parent,"Screenshot",Galaxy.color("muted"))
	var line = Kit.row(shots)
	Kit.action(menu,line,"Take screenshot","camera",self,"take")
	hide_menu = _plain_check(line,"Hide F1 menu",true)
	shot_status = menu.label("",13,Galaxy.color("muted"))
	shot_status.autowrap = true
	shots.add_child(shot_status)

func _build_highlights(parent: VBoxContainer) -> void:
	var card = menu.card(parent,"Automatic highlights",Galaxy.color("star"))
	_switch(card,"Save dash eliminations","highlights","Turns on Instant replay. Uses dash impact, native stun and death; ambiguous events are skipped.")
	var modes = Kit.row(card,20)
	_switch(modes,"Knockout","knockout","Only elimination rounds. Enabled by default.")
	_switch(modes,"Race","race","Optional. Requires the same dash-contact evidence; respawns reset attribution.")
	var players=menu.card(parent,"Player highlights",Galaxy.color("accent"))
	var player_list=load("user://mod/tools/clips/ClipPlayersView.gd").new()
	players.add_child(player_list)
	player_list.build(menu,service)
	var triggers = menu.card(parent,"Moments to keep",Galaxy.color("record"))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation",28)
	grid.add_constant_override("vseparation",10)
	triggers.add_child(grid)
	for spec in [["single_kills","Single kill"],["double_kills","Double kill"],["triple_kills","Triple kill"],["multi_kills","4+ kill streak"]]:
		_switch(grid,spec[1],spec[0],"One merged clip for the final streak. Kills must be caused by your dash.")
	var presets = Kit.row(triggers)
	for spec in [["Multikills","multi"],["Triple+","triple"],["Every kill","all"]]: Kit.action(menu,presets,spec[0],"",self,"_highlight_preset",[spec[1]])
	_number(triggers,"Kill window","kill_window",3,20,1,"Kills in the same window become one highlight.","s")
	var timing = menu.card(parent,"Clip timing",Galaxy.color("playback"))
	_number(timing,"Before first kill","preroll",3,30,1,"Keeps the approach to your first dash elimination.","s")
	_number(timing,"After last kill","postroll",1,10,1,"Keeps the result of the final elimination.","s")
	Kit.hint(menu,timing,"Related kills become one clip. Larger streaks are included in custom games.")

func _build_preferences(parent: VBoxContainer) -> void:
	var sound = menu.card(parent,"Game audio",Galaxy.color("playback"))
	_switch(sound,"Record independently of my volume","independent_audio","Your speakers keep their current volume. Clips use these levels even when the game is muted.")
	_switch(sound,"Game effects","effects","Includes GooberDash effects and other players. Outside music and voice apps are never captured.")
	_number(sound,"Effects level","effects_gain",0,1,0.05,"Recording level only; doesn't change what you hear.","%")
	_switch(sound,"Game music","music","GooberDash's own music only. Spotify, browsers and other apps stay out.")
	_number(sound,"Music level","music_gain",0,1,0.05,"Recording level for the game's music bus.","%")
	var apply_audio = Kit.action(menu,sound,"Apply recording changes","redo",service,"restart")
	apply_audio.hint_tooltip = "Starts a fresh buffer with the new recording settings."
	apply_buttons.append(apply_audio)
	var notices = menu.card(parent,"Clip notification",Galaxy.color("accent"))
	_switch(notices,"Sidebar notification","notifications","Appears when the buffer is ready, saving, or a clip is saved.")
	_switch(notices,"Confirmation sound","notification_sound","Plays after a clip is saved, even if your game is muted. Uses your system sound output.")
	_number(notices,"Sound level","notification_volume",0,1,0.05,"Volume of Clip Studio's confirmation chime.","%")
	_choice(notices,"Position","corner",[["Top right","top_right"],["Bottom right","bottom_right"],["Top left","top_left"],["Bottom left","bottom_left"]],"Choose where clip notifications appear.")
	_number(notices,"On-screen time","toast_seconds",2,8,1,"Notifications follow your reduced-motion preference.","s")
	Kit.action(menu,notices,"Preview notification","bell",service,"preview_notification")

func _switch(parent: Control,text: String,key: String,tip: String):
	var result = _plain_check(parent,text,bool(service.settings[key]))
	result.hint_tooltip = tip
	result.connect("toggled",self,"_option_changed",[key])
	controls[key] = result
	return result

func _plain_check(parent: Control,text: String,value: bool) -> CheckButton:
	var result = CheckButton.new()
	result.text = text
	result.pressed = value
	result.focus_mode = Control.FOCUS_NONE
	result.add_font_override("font",menu.font(15))
	result.add_color_override("font_color",Galaxy.color("ink"))
	result.add_color_override("font_color_hover",Galaxy.color("accent"))
	result.add_color_override("font_color_pressed",Galaxy.color("ink"))
	result.add_color_override("font_color_hover_pressed",Galaxy.color("accent"))
	result.add_stylebox_override("focus",StyleBoxEmpty.new())
	for state in ["normal","hover","pressed","hover_pressed","disabled"]: result.add_stylebox_override(state,StyleBoxEmpty.new())
	result.add_icon_override("on",menu._toggle_icon(true))
	result.add_icon_override("off",menu._toggle_icon(false))
	result.rect_min_size.y = 30
	parent.add_child(result)
	return result

func _choice(parent: Control,text: String,key: String,values: Array,tip: String) -> void:
	var line = Kit.labeled(menu,parent,text)
	var pick = OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.rect_min_size = Vector2(170,32)
	pick.add_font_override("font",menu.font(14))
	pick.add_icon_override("arrow",Galaxy.icon("chev-down",Galaxy.color("muted"),16))
	pick.get_popup().add_font_override("font",menu.font(14))
	pick.get_popup().add_stylebox_override("panel",Galaxy.box(Galaxy.color("surface"),Galaxy.color("line"),8,10))
	pick.get_popup().add_stylebox_override("hover",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),6,6))
	pick.get_popup().add_color_override("font_color",Galaxy.color("ink"))
	pick.get_popup().add_color_override("font_color_hover",Galaxy.color("accent"))
	pick.add_color_override("font_color",Galaxy.color("ink"))
	pick.add_stylebox_override("normal",Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),10,8))
	pick.add_stylebox_override("hover",Galaxy.box(Galaxy.color("hover"),Galaxy.color("accent"),10,8))
	pick.hint_tooltip = tip
	for entry in values:
		pick.add_item(entry[0])
		pick.set_item_metadata(pick.get_item_count()-1,entry[1])
		if service.settings[key]==entry[1]: pick.select(pick.get_item_count()-1)
	pick.connect("item_selected",self,"_chosen",[key,pick])
	line.add_child(pick)
	controls[key] = pick

func _number(parent: Control,text: String,key: String,low: float,high: float,step: float,tip: String,unit: String) -> void:
	var line = Kit.labeled(menu,parent,text)
	var value = menu.label(_value_text(service.settings[key],unit),14,Galaxy.color("ink"))
	value.rect_min_size.x = 44
	var slider = Kit.slider(line,low,high,step,float(service.settings[key]),null,"")
	slider.hint_tooltip = tip
	line.add_child(value)
	slider.connect("value_changed",self,"_number_changed",[key,value,unit])
	controls[key] = slider

func _value_text(value,unit: String) -> String:
	return "%d%%"%round(float(value)*100) if unit=="%" else "%d%s"%[round(float(value)),unit]
func _option_changed(value,key: String) -> void: service.set_option(key,value)
func _chosen(index: int,key: String,pick) -> void: service.set_option(key,pick.get_item_metadata(index))
func _duration(value: int) -> void: service.set_option("duration",value)
func _number_changed(value: float,key: String,label: Label,unit: String) -> void:
	label.text = _value_text(value,unit)
	service.set_option(key,value)
func _quality(spec: Array) -> void:
	service.set_option("height",spec[1])
	service.set_option("fps",spec[2])
	service.set_option("quality",spec[3])
func _highlight_preset(preset: String) -> void:
	service.set_option("single_kills",preset=="all")
	service.set_option("double_kills",preset!="triple")
	service.set_option("triple_kills",true)
	service.set_option("multi_kills",true)

func _refresh() -> void:
	if not is_instance_valid(content_root) or not content_root.is_visible_in_tree(): return
	duration_grid.columns = 3 if content_root.rect_size.x<540 else 6
	status.text = {"off":"Off","starting":"Starting…","awaiting_window":"Waiting for game","buffering":"● Buffering","waiting":"Paused window","stopping":"Finishing…","error":"Needs attention"}.get(service.state,service.state)
	status.add_color_override("font_color",Galaxy.color("success") if service.active() else Galaxy.color("muted"))
	progress.max_value = service.settings.duration
	progress.value = min(service.seconds,service.settings.duration)
	buffer_label.text = "%ds ready · %dp / %d FPS · %s" % [service.seconds,service.video_height,service.video_fps,"GPU encoder" if service.codec!="libx264" else "Software encoder"] if service.active() else service.message
	buffer_label.add_color_override("font_color",Galaxy.color("danger") if service.state=="error" else Galaxy.color("muted"))
	automatic_toggle.set_pressed_no_signal(bool(service.settings.highlights))
	automatic_status.text = service.highlights.status_text()
	automatic_status.add_color_override("font_color",Galaxy.color("success") if service.settings.highlights and service.active() else Galaxy.color("warning"))
	save_button.text = "Save last %ds"%service.settings.duration
	save_button.disabled = not service.active() or service.seconds<0.25
	enabled.disabled = service.state=="stopping"
	for button in apply_buttons:
		button.visible = service.dirty or service.state=="error"
		button.text = "Retry recorder" if service.state=="error" else "Apply recording changes · restart buffer"
	key_button.text = service.shortcut()
	for key in controls:
		var control = controls[key]
		if control is CheckButton: control.set_pressed_no_signal(bool(service.settings[key]))
		elif control is OptionButton:
			for index in control.get_item_count():
				if control.get_item_metadata(index)==service.settings[key]: control.select(index)
		elif control is HSlider and not is_equal_approx(control.value,float(service.settings[key])): control.set_value(service.settings[key])
	for duration in duration_buttons:
		var button = duration_buttons[duration]
		button.add_stylebox_override("normal",Galaxy.primary_box(Galaxy.color("accent"),12) if duration==service.settings.duration else Galaxy.box(Galaxy.color("raised"),Galaxy.color("line"),12))
		button.add_color_override("font_color",Galaxy.color("accent_ink") if duration==service.settings.duration else Galaxy.color("ink"))

func _shortcut() -> void:
	menu.select("settings")
	var view = menu.tas_tool._keybinds.view
	if not is_instance_valid(view): return
	var node = view.get_parent()
	while node!=null:
		if node.get_script()==PageTabs:
			node.select(2)
			break
		node = node.get_parent()
	view.capture("clip_save")

func _build_library(parent: VBoxContainer) -> void:
	var line = Kit.row(parent,6)
	for item in [["All","all"],["Clips","clips"],["Highlights","highlights"],["Screenshots","screenshots"]]: Kit.action(menu,line,item[0],"",self,"_filter",[item[1]])
	line.add_child(menu._spacer())
	Kit.action(menu,line,"Refresh","redo",self,"refresh")
	library_count = menu.label("",14,Galaxy.color("muted"))
	parent.add_child(library_count)
	library_rows = VBoxContainer.new()
	library_rows.add_constant_override("separation",10)
	parent.add_child(library_rows)
	var navigation = Kit.row(parent)
	previous_button = Kit.action(menu,navigation,"Previous","chev-left",self,"_page",[-1])
	next_button = Kit.action(menu,navigation,"Next","chev-right",self,"_page",[1])
	navigation.add_child(menu._spacer())
	Kit.action(menu,navigation,"Open folder","folder",self,"_open_folder")
func _filter(value: String) -> void:
	library_filter = value
	library_page = 0
	refresh()
func _page(delta: int) -> void:
	library_page = max(0,library_page+delta)
	refresh()
func _clip_saved(_path: String) -> void: refresh()

func refresh() -> void:
	if library_rows==null: return
	for child in library_rows.get_children():
		library_rows.remove_child(child)
		child.queue_free()
	var files = []
	library_times.clear()
	var dir = Directory.new()
	if dir.open(folder())==OK:
		dir.list_dir_begin(true,true)
		var file = dir.get_next()
		while file!="":
			var ext = file.get_extension().to_lower()
			if not file.ends_with(".partial.mp4") and ext in ["png","mp4","webm","gif"]:
				var metadata = Kit.read_json(folder().plus_file(file.get_basename()+".json"),{})
				var video = ext in ["mp4","webm"]
				if library_filter=="all" or (library_filter=="clips" and video) or (library_filter=="highlights" and int(metadata.get("kills",0))>0) or (library_filter=="screenshots" and not video):
					files.append(file)
					library_times[file] = File.new().get_modified_time(folder().plus_file(file))
			file = dir.get_next()
		dir.list_dir_end()
	files.sort_custom(self,"_newest_first")
	library_page = min(library_page,max(0,int((files.size()-1)/6)))
	library_count.text = "%d captures · %s" % [files.size(),folder()]
	library_count.autowrap = true
	previous_button.disabled = library_page==0
	next_button.disabled = (library_page+1)*6>=files.size()
	for index in range(library_page*6,min(files.size(),(library_page+1)*6)):
		var file = files[index]
		var path = folder().plus_file(file)
		var data = Kit.read_json(folder().plus_file(file.get_basename()+".json"),{})
		var card = menu.card(library_rows,"",Galaxy.color("accent"))
		var row = Kit.row(card,14)
		var picture = TextureRect.new()
		picture.expand = true
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.rect_min_size = Vector2(112,64)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var image_path = path if file.get_extension()=="png" else folder().plus_file(file.get_basename()+".jpg")
		var img = Image.new()
		if File.new().file_exists(image_path) and img.load(image_path)==OK:
			img.resize(224,126,Image.INTERPOLATE_LANCZOS)
			var texture = ImageTexture.new()
			texture.create_from_image(img,Texture.FLAG_FILTER)
			picture.texture = texture
		else: picture.texture = Galaxy.icon("clip",Galaxy.color("accent"),48)
		row.add_child(picture)
		var words = Kit.column(row,4)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(menu.label(str(data.get("label","Screenshot" if file.get_extension()=="png" else "Clip")),16))
		var info = menu.label(file,13,Galaxy.color("muted"))
		info.clip_text = true
		info.hint_tooltip = file
		words.add_child(info)
		if data.has("duration"): words.add_child(menu.label("%.0fs · %d FPS%s"%[float(data.duration),int(data.get("fps",60))," · %d eliminations"%int(data.kills) if int(data.get("kills",0))>0 else ""],13,Galaxy.color("muted")))
		Kit.action(menu,row,"Open","play",self,"_open_item",[path])
	if files.empty(): Kit.hint(menu,library_rows,"Your saved clips and screenshots will appear here.")

func take() -> void:
	var window = menu.tas_tool.get("_menu_window")
	var was_visible = window!=null and window.visible
	if hide_menu.pressed and was_visible:
		window.visible = false
		yield(menu.get_tree(),"idle_frame")
		yield(menu.get_tree(),"idle_frame")
	var image = menu.get_viewport().get_texture().get_data()
	image.flip_y()
	if hide_menu.pressed and was_visible: window.visible = true
	Directory.new().make_dir_recursive(folder())
	var stamp = OS.get_datetime()
	var path = folder().plus_file("goob-%04d%02d%02d-%02d%02d%02d.png"%[stamp.year,stamp.month,stamp.day,stamp.hour,stamp.minute,stamp.second])
	var ok = image.save_png(path)==OK
	shot_status.text = "Screenshot saved" if ok else "Couldn't save the screenshot."
	service.toast.show_notice(shot_status.text,path.get_file() if ok else "Check that the capture folder is writable.",path if ok else "",not ok)
	refresh()
func _open_item(path: String) -> void: OS.shell_open(path)
func _newest_first(a: String,b: String) -> bool:
	return int(library_times.get(a,0))>int(library_times.get(b,0)) if library_times.get(a,0)!=library_times.get(b,0) else a>b
func _open_folder() -> void:
	Directory.new().make_dir_recursive(folder())
	OS.shell_open(folder())
