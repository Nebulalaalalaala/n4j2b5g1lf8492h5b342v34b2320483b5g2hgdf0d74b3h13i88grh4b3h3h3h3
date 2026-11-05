extends Reference

# Effects Editor: build a particle trail from a preset, preview it here, save
# it, and wear it in local games. Saved effects are plain JSON files in
# goobplayability/effects/, so Workshop can share them.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const Kit = preload("user://mod/core/workspace4/Kit.gd")
const EffectRuntime = preload("user://mod/core/workspace4/EffectRuntime.gd")

var menu
var runtime
var effect = {}
var preview: CPUParticles2D
var mover: Node2D
var stage: Panel
var name_field: LineEdit
var saved_list: ItemList
var status: Label
var controls = {}

func build(owner_menu, content: VBoxContainer, effect_runtime) -> void:
	menu = owner_menu
	runtime = effect_runtime
	effect = EffectRuntime.presets()["Stardust"].duplicate(true)
	effect["name"] = "My effect"
	var presets = Kit.row(content, 8)
	presets.add_child(menu.label("Start from", 15, Galaxy.color("muted")))
	for key in EffectRuntime.presets():
		Kit.action(menu, presets, key, "effects", self, "_preset", [key])
	var body = Kit.row(content, 14)
	stage = Panel.new()
	stage.rect_min_size = Vector2(420, 240)
	stage.rect_clip_content = true
	stage.add_stylebox_override("panel", Galaxy.box(Color("100c2e"), Galaxy.color("line"), 0, 12))
	body.add_child(stage)
	mover = Node2D.new()
	stage.add_child(mover)
	preview = CPUParticles2D.new()
	mover.add_child(preview)
	var goober = TextureRect.new()
	goober.texture = Galaxy.texture("fox-head.png")
	goober.expand = true
	goober.rect_size = Vector2(34, 34)
	goober.rect_position = Vector2(-17, -17)
	goober.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mover.add_child(goober)
	var side = Kit.column(body, 8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field = Kit.field(menu, Kit.labeled(menu, side, "Name"), effect.name, "Effect name", self, "_set_name")
	controls["color_a"] = Kit.color_button(Kit.labeled(menu, side, "Start colour"), Color(effect.color_a), null, "")
	controls["color_a"].connect("color_changed", self, "_set_color", ["color_a"])
	controls["color_b"] = Kit.color_button(Kit.labeled(menu, side, "End colour"), Color(effect.color_b), null, "")
	controls["color_b"].connect("color_changed", self, "_set_color", ["color_b"])
	for entry in [["amount", "Amount", 4, 200, 1], ["lifetime", "Lifetime", 0.1, 3.0, 0.05], ["size", "Size", 1, 16, 0.5], ["speed", "Speed", 0, 160, 1]]:
		var slider = Kit.slider(Kit.labeled(menu, side, entry[1]), entry[2], entry[3], entry[4], float(effect[entry[0]]), null, "")
		slider.connect("value_changed", self, "_set_value", [entry[0]])
		controls[entry[0]] = slider
	var actions = Kit.row(content, 8)
	Kit.action(menu, actions, "Save", "save", self, "_save", [], true)
	Kit.action(menu, actions, "Wear in local games", "check", self, "_wear")
	Kit.action(menu, actions, "Take off", "close", self, "_take_off")
	status = Kit.hint(menu, content, "Effects show on your own Goober in solo levels, the level editor and local mode. Only you see them.")
	content.add_child(menu.label("Saved effects", 16))
	saved_list = ItemList.new()
	saved_list.rect_min_size = Vector2(0, 110)
	saved_list.add_font_override("font", menu.font(15))
	saved_list.add_stylebox_override("bg", Galaxy.box(Galaxy.color("surface"), Galaxy.color("border"), 6))
	saved_list.add_color_override("font_color", Galaxy.color("ink"))
	saved_list.connect("item_activated", self, "_open_saved")
	saved_list.connect("item_selected", self, "_open_saved")
	content.add_child(saved_list)
	_list_saved()
	_update_preview()
	var timer = Timer.new()
	timer.wait_time = 0.033
	timer.connect("timeout", self, "_move")
	stage.add_child(timer)
	timer.start()

func _move() -> void:
	if not stage.is_visible_in_tree():
		return
	var t = OS.get_ticks_msec() / 1000.0
	mover.position = Vector2(stage.rect_size.x * 0.5 + cos(t * 1.3) * stage.rect_size.x * 0.32, stage.rect_size.y * 0.5 + sin(t * 2.6) * stage.rect_size.y * 0.22)

func _update_preview() -> void:
	EffectRuntime.configure(preview, effect)

func _preset(key: String) -> void:
	var keep_name = effect.get("name", "My effect")
	effect = EffectRuntime.presets()[key].duplicate(true)
	effect["name"] = keep_name
	for field in ["amount", "lifetime", "size", "speed"]:
		controls[field].set_block_signals(true)
		controls[field].value = float(effect[field])
		controls[field].set_block_signals(false)
	controls.color_a.color = Color(effect.color_a)
	controls.color_b.color = Color(effect.color_b)
	_update_preview()

func _set_name(value: String) -> void:
	effect["name"] = value

func _set_color(value: Color, key: String) -> void:
	effect[key] = value.to_html(false)
	_update_preview()

func _set_value(value: float, key: String) -> void:
	effect[key] = value
	_update_preview()

static func file_name(name: String) -> String:
	var clean = ""
	for character in name.to_lower():
		clean += character if character in "abcdefghijklmnopqrstuvwxyz0123456789-_" else "-"
	return (clean if not clean.empty() else "effect") + ".json"

func _save() -> void:
	var ok = Kit.write_json(EffectRuntime.DIR + file_name(str(effect.name)), effect)
	status.text = "Saved “%s”." % effect.name if ok else "Couldn't save the effect."
	_list_saved()

func _list_saved() -> void:
	saved_list.clear()
	var dir = Directory.new()
	if dir.open(EffectRuntime.DIR) != OK:
		return
	dir.list_dir_begin(true, true)
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".json") and file != "worn.json":
			saved_list.add_item(file.get_basename())
			saved_list.set_item_metadata(saved_list.get_item_count() - 1, EffectRuntime.DIR + file)
		file = dir.get_next()

func _open_saved(index: int) -> void:
	var loaded = Kit.read_json(str(saved_list.get_item_metadata(index)), {})
	if loaded.empty():
		return
	effect = loaded
	name_field.text = str(effect.get("name", ""))
	for field in ["amount", "lifetime", "size", "speed"]:
		controls[field].set_block_signals(true)
		controls[field].value = float(effect.get(field, 1))
		controls[field].set_block_signals(false)
	controls.color_a.color = Color(str(effect.get("color_a", "ffffff")))
	controls.color_b.color = Color(str(effect.get("color_b", "ffffff")))
	_update_preview()

func _wear() -> void:
	runtime.wear(effect)
	status.text = "Wearing “%s” in local games." % effect.get("name", "")

func _take_off() -> void:
	runtime.take_off()
	status.text = "Effect taken off."
