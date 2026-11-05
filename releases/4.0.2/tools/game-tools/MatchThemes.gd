extends VBoxContainer
const ModPaths = preload("user://mod/core/ModPaths.gd")
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")

# Match themes: play maps in another level theme (only you see it). Every
# certified map can keep its own theme; "All maps" covers the rest. In a match
# the hotkeys change the theme for that map, and the pick is remembered.

const SETTING = "match_themes"
const STOCK = ["green", "grassy", "meadow", "snow", "sandy", "castle", "city", "dungeon"]
const STOCK_PATH = "res://project_specific/level_themes/%s/theme.tres"
const GOOBER_SCENE = "res://project_specific/gfx/spine/upguy/upguy.tscn"
const OWN = ""
const RANDOM = "random"
const FOLLOW = "__follow"
const ACCENT = Color("b49cff")

var tool
var enabled = false
# default: theme for maps without their own pick. memory: map id -> theme key,
# RANDOM or OWN. names: map id -> name for maps picked in game.
var options = {"default": OWN, "pool": [], "preview": true, "memory": {}, "names": {}}
var level_ref = null
var loaded_id = 0
var current_key = ""
var current_map = ""
var current_map_name = ""
var check_elapsed = 0.0
var _poll_timer: Timer
var seen_id = 0
var seen_since = 0
var reapplied = 0
var hooked_level = 0
const SETTLE_MS = 1500
var target = ""   # "" = all maps, otherwise a map id
var maps = []     # [{id, name}]
var map_names = {}
var search
var map_list
var preview
var target_title
var target_note
var choice_grid
var pool_box
var pool_grid
var preview_check
var hint
var toast_layer
var toast
var toast_view
var toast_name
var toast_note
var toast_time = 0.0
var _built = false
var _stock_cache = {}
signal settings_changed


func build(owner):
	tool = owner
	var saved = SavedSettings.get_value(SETTING, {})
	if saved is Dictionary:
		for key in saved:
			options[key] = saved[key]
		_migrate(saved)
	enabled = bool(SavedSettings.get_value(SETTING + "_enabled", false))
	add_constant_override("separation", 12)
	add_child(tool._make_label("MATCH THEMES", tool._make_font(18), Color.white))
	var main = HBoxContainer.new()
	main.add_constant_override("separation", 18)
	add_child(main)
	var left = VBoxContainer.new()
	left.add_constant_override("separation", 8)
	main.add_child(left)
	search = LineEdit.new()
	search.placeholder_text = "Search maps"
	search.rect_min_size = Vector2(270, 0)
	GoobStyle.style_input(search, ACCENT)
	search.connect("text_changed", self, "_search_changed")
	left.add_child(search)
	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(270, 430)
	scroll.scroll_horizontal_enabled = false
	left.add_child(scroll)
	map_list = VBoxContainer.new()
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.add_constant_override("separation", 4)
	scroll.add_child(map_list)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_constant_override("separation", 10)
	main.add_child(right)
	preview = ThemePreview.new()
	preview.painter = self
	preview.rect_min_size = Vector2(0, 210)
	right.add_child(preview)
	target_title = tool._make_label("", tool._make_font(22), Color.white)
	right.add_child(target_title)
	target_note = tool._make_label("", tool._make_font(15), GoobStyle.MUTED)
	right.add_child(target_note)
	choice_grid = GridContainer.new()
	choice_grid.columns = 5
	choice_grid.add_constant_override("hseparation", 8)
	choice_grid.add_constant_override("vseparation", 8)
	right.add_child(choice_grid)
	pool_box = VBoxContainer.new()
	pool_box.add_constant_override("separation", 6)
	right.add_child(pool_box)
	pool_box.add_child(tool._make_label("Random picks from", tool._make_font(15), GoobStyle.MUTED))
	pool_grid = GridContainer.new()
	pool_grid.columns = 4
	pool_grid.add_constant_override("hseparation", 14)
	pool_box.add_child(pool_grid)
	var bottom = HBoxContainer.new()
	bottom.add_constant_override("separation", 20)
	add_child(bottom)
	preview_check = CheckBox.new()
	preview_check.text = "Show the theme when a round starts"
	preview_check.pressed = bool(options.get("preview", true))
	preview_check.connect("toggled", self, "_preview_toggled")
	GoobStyle.style_input(preview_check, ACCENT)
	bottom.add_child(preview_check)
	hint = tool._make_label("", tool._make_font(15), GoobStyle.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.align = Label.ALIGN_RIGHT
	bottom.add_child(hint)
	connect("visibility_changed", self, "_on_visibility_changed")
	_build_toast()
	set_process(false)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.connect("timeout",self,"_poll_level")
	add_child(_poll_timer)
	if enabled: _poll_timer.start()


func _migrate(saved: Dictionary) -> void:
	if not saved.has("default"):
		var mode = str(saved.get("mode", "random"))
		if mode == "fixed":
			options.default = str(saved.get("theme", "snow"))
		elif mode == "random":
			options.default = RANDOM
		else:
			options.default = OWN
	for key in ["mode", "theme", "remember", "where"]:
		options.erase(key)
	if not options.get("memory") is Dictionary:
		options.memory = {}
	if not options.get("names") is Dictionary:
		options.names = {}


func _save() -> void:
	SavedSettings.set_value(SETTING, options.duplicate(true))
	SavedSettings.set_value(SETTING + "_enabled", enabled)
	emit_signal("settings_changed")


func set_enabled(value: bool) -> void:
	enabled = value
	if is_instance_valid(_poll_timer):
		if enabled: _poll_timer.start()
		else: _poll_timer.stop()
	_save()
	var game = _game()
	var online = game != null and not game.is_server()
	if not enabled:
		if online:
			current_key = "" # the next round loads with its own theme
			loaded_id = 0
		else:
			_restore_level()
	else:
		loaded_id = 0


func _preview_toggled(value: bool) -> void:
	options.preview = value
	_save()


# ---------------------------------------------------------------- themes

func theme_keys() -> Array:
	var keys = STOCK.duplicate()
	for key in _catalog().keys():
		keys.append(key)
	return keys


func _catalog() -> Dictionary:
	var path = ModPaths.ROOT + "tools/editor-themes/ThemeCatalog.gd"
	if not File.new().file_exists(path):
		return {}
	return load(path).DEFINITIONS


func theme_name(key: String) -> String:
	if key == RANDOM:
		return "Random"
	if key == OWN:
		return "Map's own"
	var catalog = _catalog()
	if catalog.has(key):
		return str(catalog[key].get("name", key))
	return {"green": "Green Hills", "grassy": "Grassy", "meadow": "Meadow", "snow": "Snow", "sandy": "Sandy", "castle": "Castle", "city": "City", "dungeon": "Dungeon"}.get(key, key.capitalize())


func theme_resource(key: String):
	if key in STOCK:
		if not _stock_cache.has(key):
			_stock_cache[key] = load(STOCK_PATH % key)
		return _stock_cache[key]
	var pack = tool.get("_editor_theme_pack")
	if pack == null or not is_instance_valid(pack) or not _catalog().has(key):
		return null
	var themes = pack.get("_themes")
	if typeof(themes) == TYPE_DICTIONARY and themes.has(key):
		return themes[key]
	var base = theme_resource("green")
	if base == null:
		return null
	pack.call("_ensure_themes", base, key)
	themes = pack.get("_themes")
	return themes.get(key) if typeof(themes) == TYPE_DICTIONARY else null


func _pool() -> Array:
	var pool = []
	for key in options.get("pool", []):
		if str(key) in theme_keys():
			pool.append(str(key))
	return pool if not pool.empty() else theme_keys()


# The saved pick for a map: its own entry, else the All maps pick.
func _pick_for(map: String) -> String:
	var memory = options.get("memory", {})
	if not map.empty() and memory.has(map):
		return str(memory[map])
	return str(options.get("default", OWN))


# ---------------------------------------------------------------- applying

func _game():
	return tool._find_game() if tool.has_method("_find_game") else null


func _eligible(game) -> bool:
	if game == null or game.wp_game_data == null or game.level == null or game.level.loaded_level == null:
		return false
	# Matches only: never time trials, TAS runs, replays, the editor or lobbies.
	for flag in ["is_time_trial", "is_replay", "is_level_editor", "is_tutorial"]:
		if bool(game.wp_game_data.get(flag)):
			return false
	if game.has_method("is_in_lobby") and game.is_in_lobby():
		return false
	# The pre-match lobby has no level id; never touch it.
	var loaded = game.level.loaded_level
	if not ("level_id" in loaded) or str(loaded.level_id).empty():
		return false
	if not game.level.is_inside_tree() or game.level.is_queued_for_deletion() or loaded.is_queued_for_deletion():
		return false
	return true


func _map_id(game) -> String:
	var loaded = game.level.loaded_level
	if "level_id" in loaded and not str(loaded.level_id).empty():
		return str(loaded.level_id)
	return str(loaded.get("level_name"))


func _map_name(game) -> String:
	var name = str(game.level.loaded_level.get("level_name"))
	return name if not name.empty() and name != "Null" else map_names.get(_map_id(game), "This map")


func _process(delta: float) -> void:
	if toast != null and toast.visible:
		toast_time -= delta
		toast.modulate.a = clamp(toast_time / 0.5, 0.0, 1.0)
		if toast_time <= 0.0:
			toast.visible = false
	else:
		set_process(false)

func _unhandled_input(event) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var keys = tool.get("_keybinds") if is_instance_valid(tool) else null
	if keys == null or keys.typing(): return
	for spec in [["game:theme_next","change_theme"],["game:theme_random","random_theme"]]:
		if keys.matches(event,spec[0]):
			call(spec[1])
			get_tree().set_input_as_handled()
			return

func _poll_level() -> void:
	if not enabled:
		return
	var game = _game()
	if game == null or game.level == null or not is_instance_valid(game.level):
		return
	# Online matches simulate the level on a second thread as well, so the
	# theme may only change at the moment a round's level loads -- the same
	# moment the game sets its own theme. Changing it mid-round crashed.
	if game.level.get_instance_id() != hooked_level and game.level.has_signal("loaded_level"):
		hooked_level = game.level.get_instance_id()
		if not game.level.is_connected("loaded_level", self, "_on_level_loaded"):
			game.level.connect("loaded_level", self, "_on_level_loaded", [weakref(game.level)])
	_prewarm()
	if not game.is_server():
		return
	# Local games have no second simulation: the theme can follow at any time.
	if not _eligible(game):
		seen_id = 0
		return
	var loaded = game.level.loaded_level
	if loaded.get_instance_id() != seen_id:
		seen_id = loaded.get_instance_id()
		seen_since = OS.get_ticks_msec()
		return
	if OS.get_ticks_msec() - seen_since < SETTLE_MS or loaded.get_instance_id() == loaded_id:
		return
	_theme_new_level(game)


# The round's level has just been loaded (online matches).
func _on_level_loaded(level_weak) -> void:
	var level = level_weak.get_ref() if level_weak != null else null
	if level == null or not is_instance_valid(level) or not enabled:
		return
	var game = _game()
	if game == null or game.level != level or game.is_server():
		return
	call_deferred("_themed_after_load", level_weak)


func _themed_after_load(level_weak) -> void:
	var level = level_weak.get_ref() if level_weak != null else null
	var game = _game()
	if level == null or game == null or game.level != level or not _eligible(game):
		return
	if level.loaded_level.get_instance_id() == loaded_id:
		return
	_theme_new_level(game)


func _theme_new_level(game) -> void:
	loaded_id = game.level.loaded_level.get_instance_id()
	level_ref = weakref(game.level)
	current_map = _map_id(game)
	current_map_name = _map_name(game)
	current_key = _resolve(_pick_for(current_map))
	if current_key.empty() or _ready_theme(current_key) == null:
		current_key = ""
		return
	_apply(game.level, current_key)
	if bool(options.get("preview", true)):
		show_toast(current_key, current_map_name)


# A theme that is ready to use without building anything right now. Custom
# themes are built ahead of time by _prewarm(), never during a round.
func _ready_theme(key: String):
	if key in STOCK:
		return theme_resource(key)
	var pack = tool.get("_editor_theme_pack")
	if pack == null or not is_instance_valid(pack):
		return null
	var themes = pack.get("_themes")
	return themes.get(key) if typeof(themes) == TYPE_DICTIONARY else null


# Build one custom theme that may be needed, while not racing (lobby, menus).
func _prewarm() -> void:
	var game = _game()
	if game != null and not game.is_server() and not (game.has_method("is_in_lobby") and game.is_in_lobby()):
		return
	var wanted = [str(options.get("default", OWN))]
	for key in options.get("memory", {}).values():
		wanted.append(str(key))
	if RANDOM in wanted:
		wanted += _pool()
	for key in wanted:
		if key != OWN and key != RANDOM and not key in STOCK and _catalog().has(key) and _ready_theme(key) == null:
			theme_resource(key)
			return


func _resolve(pick: String) -> String:
	if pick == RANDOM:
		var pool = []
		for key in _pool():
			if _ready_theme(key) != null:
				pool.append(key)
		return pool[randi() % pool.size()] if not pool.empty() else ""
	return pick


func _apply(level, key: String) -> void:
	var theme = theme_resource(key)
	if theme == null:
		return
	if not level.has_meta("match_theme_original"):
		level.set_meta("match_theme_original", level.get("level_theme"))
	level.set("level_theme", theme)
	level.call("_apply_level_theme", theme)


func _restore_original(level) -> void:
	if level != null and is_instance_valid(level) and level.has_meta("match_theme_original"):
		var original = level.get_meta("match_theme_original")
		level.remove_meta("match_theme_original")
		if original != null:
			level.set("level_theme", original)
			level.call("_apply_level_theme", original)


func _restore_level() -> void:
	_restore_original(level_ref.get_ref() if level_ref != null else null)
	current_key = ""
	loaded_id = 0


func _original_theme():
	var level = level_ref.get_ref() if level_ref != null else null
	if level == null or not is_instance_valid(level):
		return null
	return level.get_meta("match_theme_original") if level.has_meta("match_theme_original") else level.get("level_theme")


# Re-check the running map on the next tick after a pick changes.
func _reapply() -> void:
	loaded_id = 0
	check_elapsed = 0.5


# In a match: save `key` for this map and show it right away.
func _set_for_current_map(key: String, game) -> void:
	if not enabled:
		enabled = true
	var map = _map_id(game)
	options.memory[map] = key
	options.names[map] = _map_name(game)
	_save()
	current_map = map
	current_map_name = _map_name(game)
	if not game.is_server():
		# Online: changing the level mid-round is not safe; it shows next time.
		show_toast(key, "Saved for %s Â· shows next round on this map" % current_map_name)
	else:
		level_ref = weakref(game.level)
		loaded_id = game.level.loaded_level.get_instance_id()
		current_key = key
		if key.empty():
			_restore_original(game.level)
		elif _ready_theme(key) != null:
			_apply(game.level, key)
		show_toast(key, "Saved for " + current_map_name)
	if _built and is_visible_in_tree():
		_fill_maps()
		_refresh_target()


func change_theme() -> void:
	var game = _game()
	if not _eligible(game):
		return
	var order = [OWN] + theme_keys()
	var index = order.find(current_key)
	_set_for_current_map(order[(index + 1) % order.size()], game)


func random_theme() -> void:
	var game = _game()
	if not _eligible(game):
		return
	var keys = _pool()
	var key = keys[randi() % keys.size()]
	if keys.size() > 1:
		while key == current_key:
			key = keys[randi() % keys.size()]
	_set_for_current_map(key, game)


func _handle_keys() -> void:
	var keybinds = tool.get("_keybinds")
	if keybinds == null:
		return
	for entry in [["game:theme_next", "change_theme"], ["game:theme_random", "random_theme"]]:
		var pressed = keybinds.held(entry[0])
		var was = bool(tool._prev_key_state.get(entry[0], false))
		tool._prev_key_state[entry[0]] = pressed
		if pressed and not was:
			call(entry[1])


# ---------------------------------------------------------------- menu

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	var game = _game()
	if _eligible(game):
		current_map = _map_id(game)
		current_map_name = _map_name(game)
	if not _built:
		_built = true
		target = current_map if not current_map.empty() else ""
	_load_maps()
	_fill_maps()
	_fill_pool()
	preview.dress(self)
	_refresh_target()
	var keybinds = tool.get("_keybinds")
	if keybinds != null:
		hint.text = "In a match: %s changes the map's theme Â· %s random" % [keybinds.caption("game:theme_next"), keybinds.caption("game:theme_random")]


func _load_maps() -> void:
	var levels = []
	if ModPaths.has("JourneyCertified.gd"):
		var cached = load(ModPaths.path("JourneyCertified.gd")).load_cache().get("levels", [])
		if cached is Array:
			levels += cached
	var file = File.new()
	if ModPaths.has("journey-map-catalog.json") and file.open(ModPaths.path("journey-map-catalog.json"), File.READ) == OK:
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and parsed.result is Array:
			levels += parsed.result
	maps = []
	map_names = {}
	for level in levels:
		if not level is Dictionary:
			continue
		var id = str(level.get("id", ""))
		var name = str(level.get("name", "")).strip_edges()
		if id.empty() or name.empty() or map_names.has(id) or name.to_lower().find("lobby") >= 0:
			continue
		map_names[id] = name
		maps.append({"id": id, "name": name})
	for id in options.get("names", {}):
		if not map_names.has(id):
			map_names[id] = str(options.names[id])
			maps.append({"id": id, "name": map_names[id]})
	maps.sort_custom(self, "_by_name")


func _by_name(a, b) -> bool:
	return a.name.to_lower() < b.name.to_lower()


func _search_changed(_text) -> void:
	_fill_maps()


func _fill_maps() -> void:
	for child in map_list.get_children():
		child.queue_free()
	var needle = search.text.strip_edges().to_lower()
	if needle.empty():
		_add_row("", "All maps", str(options.get("default", OWN)), false)
		if not current_map.empty():
			_add_row(current_map, map_names.get(current_map, current_map_name), _row_value(current_map), true)
	for map in maps:
		if not needle.empty() and map.name.to_lower().find(needle) < 0:
			continue
		if needle.empty() and map.id == current_map:
			continue
		_add_row(map.id, map.name, _row_value(map.id), map.id == current_map)


func _row_value(id: String) -> String:
	var memory = options.get("memory", {})
	return str(memory[id]) if memory.has(id) else FOLLOW


func _add_row(id: String, title: String, value: String, playing: bool) -> void:
	var row = MapRow.new()
	row.title = title
	row.value = "" if value == FOLLOW else theme_name(value)
	row.playing = playing
	row.selected = id == target
	row.font = tool._make_font(16)
	row.small = tool._make_font(13)
	row.rect_min_size = Vector2(0, 38)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.connect("picked", self, "_select_target", [id])
	map_list.add_child(row)
	if row.selected:
		_scroll_to(row)


func _scroll_to(row) -> void:
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if is_instance_valid(row):
		map_list.get_parent().ensure_control_visible(row)


func _select_target(id: String) -> void:
	target = id
	for row in map_list.get_children():
		row.selected = false
		row.update()
	_fill_maps()
	_refresh_target()


func _target_value() -> String:
	return str(options.get("default", OWN)) if target.empty() else _row_value(target)


func _refresh_target() -> void:
	var value = _target_value()
	if target.empty():
		target_title.text = "All maps"
		target_note.text = theme_name(value) + " Â· maps without their own theme"
	else:
		target_title.text = map_names.get(target, current_map_name if target == current_map else target)
		if value == FOLLOW:
			target_note.text = "Like all maps (%s)" % theme_name(str(options.get("default", OWN)))
		elif value == RANDOM:
			target_note.text = "Random theme every round"
		else:
			target_note.text = theme_name(value)
	for child in choice_grid.get_children():
		child.queue_free()
	var values = ([FOLLOW] if not target.empty() else []) + [OWN, RANDOM] + theme_keys()
	for item in values:
		var card = ChoiceCard.new()
		card.painter = self
		card.value = item
		card.title = "Like all maps" if item == FOLLOW else theme_name(item)
		card.selected = item == value
		card.font = tool._make_font(14)
		card.rect_min_size = Vector2(104, 86)
		card.hint_tooltip = card.title
		card.connect("picked", self, "_choose", [item])
		card.connect("hovered", self, "_hover", [item])
		choice_grid.add_child(card)
	pool_box.visible = value == RANDOM or (value == FOLLOW and str(options.get("default", OWN)) == RANDOM)
	_show_preview(value)


func _show_preview(value: String) -> void:
	var shown = str(options.get("default", OWN)) if value == FOLLOW else value
	preview.value = shown
	preview.res = theme_resource(shown) if not shown in [OWN, RANDOM] else null
	if shown == OWN and (target == current_map or target.empty()):
		preview.res = _original_theme()
	preview.pool = _pool_resources() if shown == RANDOM else []
	preview.update()


func _hover(inside: bool, value: String) -> void:
	_show_preview(value if inside else _target_value())


func _choose(value: String) -> void:
	if target.empty():
		options.default = OWN if value == FOLLOW else value
	elif value == FOLLOW:
		options.memory.erase(target)
	else:
		options.memory[target] = value
		if not map_names.has(target) or target == current_map:
			options.names[target] = map_names.get(target, current_map_name)
	if not enabled and value != FOLLOW:
		enabled = true
	_save()
	_reapply()
	_fill_maps()
	_refresh_target()
	var shown = str(options.get("default", OWN)) if value == FOLLOW else value
	show_toast(shown, "All maps" if target.empty() else map_names.get(target, current_map_name))


func _fill_pool() -> void:
	for child in pool_grid.get_children():
		child.queue_free()
	var pool = options.get("pool", [])
	for key in theme_keys():
		var check = CheckBox.new()
		check.text = theme_name(key)
		check.pressed = pool.empty() or key in pool
		check.connect("toggled", self, "_pool_toggled", [key])
		GoobStyle.style_input(check, ACCENT)
		pool_grid.add_child(check)


func _pool_toggled(on: bool, key: String) -> void:
	var pool = options.get("pool", [])
	if pool.empty():
		pool = theme_keys()
	if on and not key in pool:
		pool.append(key)
	elif not on:
		pool.erase(key)
	if pool.empty():
		pool = [key]
	options.pool = pool if pool.size() < theme_keys().size() else []
	_save()
	_show_preview(_target_value())


func _pool_resources() -> Array:
	var list = []
	for key in _pool():
		# Preview only: never generate every custom theme to draw a mosaic.
		# The actual round selection still resolves its chosen theme normally.
		var res = _ready_theme(key)
		if res != null:
			list.append(res)
	return list

func paint_palette(ci: CanvasItem, rect: Rect2, key: String) -> void:
	var definition = _catalog().get(key,{})
	var top = definition.get("top",Color("445277"))
	var bottom = definition.get("bottom",Color("8885aa"))
	for i in 24:
		ci.draw_rect(Rect2(rect.position+Vector2(0,rect.size.y*i/24.0),Vector2(rect.size.x,rect.size.y/24.0+1)),top.linear_interpolate(bottom,i/23.0))
	var accent = definition.get("accent",Color("b49cff"))
	ci.draw_line(rect.position+Vector2(0,rect.size.y*0.8),rect.position+Vector2(rect.size.x,rect.size.y*0.8),accent,3,true)


# ---------------------------------------------------------------- drawing

func paint(ci: CanvasItem, rect: Rect2, res) -> void:
	var top = Color("6fb8ff")
	var bottom = Color("c3ded6")
	var gradient = res.get("background_gradient") if res != null else null
	if gradient is Gradient and gradient.get_point_count() >= 2:
		bottom = gradient.get_color(0)
		top = gradient.get_color(gradient.get_point_count() - 1)
	for step in 16:
		ci.draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * step / 16.0, rect.size.x, rect.size.y / 16.0 + 1), top.linear_interpolate(bottom, step / 15.0))
	var ground = rect.end.y - rect.size.y * 0.28
	var art = res.get_meta("background_art") if res != null and res.has_meta("background_art") else null
	if art is Texture:
		ci.draw_texture_rect(art, rect, false)
	elif res != null and res.get("horizon_texture") is Texture:
		var horizon = res.get("horizon_texture")
		var height = min(rect.size.y * 0.5, horizon.get_height())
		ci.draw_texture_rect(horizon, Rect2(rect.position.x, ground - height, rect.size.x, height), true, Color(1, 1, 1, 0.9))
	var platform = Rect2(rect.position.x, ground, rect.size.x, rect.end.y - ground)
	var terrain = res.get("terrain_texture") if res != null else null
	if terrain is Texture:
		ci.draw_texture_rect(terrain, platform, true)
	else:
		ci.draw_rect(platform, Color("4a5a3a"))
	var edge = res.get("terrain_color_1") if res != null else null
	ci.draw_line(platform.position, platform.position + Vector2(platform.size.x, 0), edge if edge is Color else Color.white, 3.0)
	var grass = res.get("front_grass_color") if res != null else null
	if grass is Color:
		ci.draw_line(platform.position + Vector2(0, -2), platform.position + Vector2(platform.size.x, -2), grass, 2.0)


func paint_random(ci: CanvasItem, rect: Rect2, pool: Array, font) -> void:
	var count = int(min(5, pool.size()))
	if count == 0:
		ci.draw_rect(rect, GoobStyle.RAISED)
	for index in count:
		var width = rect.size.x / count
		paint(ci, Rect2(rect.position.x + width * index, rect.position.y, width + 1, rect.size.y), pool[index])
	ci.draw_rect(rect, Color(0, 0, 0, 0.35))
	if font != null:
		var size = font.get_string_size("?")
		var at = rect.position + rect.size * 0.5 + Vector2(-size.x * 0.5, size.y * 0.3)
		ci.draw_string(font, at + Vector2(2, 2), "?", Color(0, 0, 0, 0.6))
		ci.draw_string(font, at, "?", Color.white)


func paint_own(ci: CanvasItem, rect: Rect2, res) -> void:
	if res != null:
		paint(ci, rect, res)
		return
	ci.draw_rect(rect, GoobStyle.RAISED)
	var step = 14.0
	var x = -rect.size.y
	while x < rect.size.x:
		ci.draw_line(rect.position + Vector2(x, rect.size.y), rect.position + Vector2(x + rect.size.y, 0), Color(1, 1, 1, 0.05), 6.0)
		x += step
	var ground = rect.end.y - rect.size.y * 0.28
	ci.draw_rect(Rect2(rect.position.x, ground, rect.size.x, rect.end.y - ground), GoobStyle.EDGE)


func make_goober():
	var scene = load(GOOBER_SCENE)
	if scene == null:
		return null
	var goober = scene.instance()
	goober.enable_sounds = false
	goober.enable_blink = false
	return goober


# Wear the player's current look (Avatar Studio included when it is loaded).
func dress_goober(goober) -> void:
	var sandbox = tool.get("_cosmetic_sandbox")
	if sandbox != null and is_instance_valid(sandbox) and sandbox.has_method("_build_local_skin"):
		sandbox.call("studio_freeze_avatar", goober)
		sandbox.call("_apply_to_goober", goober, sandbox.call("_build_local_skin"))
		return
	var moonlight = get_node_or_null("/root/Moonlight")
	var skin = moonlight.storage.storage_get("player.profile.skin", {}) if moonlight != null and moonlight.get("storage") != null else {}
	goober.set_goober_skin_data(skin if skin is Dictionary and not skin.empty() else {"color": "color_default"})
	goober.set_update_mode(2)
	goober.update_skeleton(0.0)


func _build_toast() -> void:
	toast_layer = CanvasLayer.new()
	toast_layer.layer = 105
	add_child(toast_layer)
	toast = PanelContainer.new()
	toast.add_stylebox_override("panel", GoobStyle.box(Color(0.06, 0.08, 0.09, 0.92), ACCENT, 10, 12))
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.margin_left = -170
	toast.margin_top = 18
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	toast_layer.add_child(toast)
	var box = HBoxContainer.new()
	box.add_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(box)
	toast_view = ThemePreview.new()
	toast_view.painter = self
	toast_view.rect_min_size = Vector2(150, 84)
	toast_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(toast_view)
	var text = VBoxContainer.new()
	text.alignment = BoxContainer.ALIGN_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	toast_name = tool._make_label("", tool._make_font(22), Color.white)
	text.add_child(toast_name)
	toast_note = tool._make_label("", tool._make_font(14), GoobStyle.MUTED)
	text.add_child(toast_note)


func show_toast(key: String, note: String) -> void:
	if toast_view.goober == null:
		toast_view.dress(self)
	toast_view.value = key
	toast_view.res = _ready_theme(key) if not key in [OWN, RANDOM] else _original_theme()
	var ready = []
	for pool_key in _pool():
		var res = _ready_theme(pool_key)
		if res != null:
			ready.append(res)
	toast_view.pool = ready
	toast_view.update()
	toast_name.text = theme_name(key)
	toast_note.text = note
	toast.visible = true
	toast.modulate.a = 1.0
	toast_time = 2.8
	set_process(true)


class ThemePreview extends Control:
	var painter
	var value = ""
	var res = null
	var pool = []
	var goober = null
	var big_font = null

	func _init() -> void:
		rect_clip_content = true
		connect("resized", self, "_place")

	func dress(owner) -> void:
		if goober == null or not is_instance_valid(goober):
			goober = owner.make_goober()
			if goober == null:
				return
			add_child(goober)
			_place()
		owner.dress_goober(goober)

	func _place() -> void:
		if goober != null and is_instance_valid(goober):
			goober.position = Vector2(rect_size.x * 0.5, rect_size.y * 0.72 + 2)
			goober.scale = Vector2.ONE * (rect_size.y * 0.42 / 2800.0)

	func _draw() -> void:
		var rect = Rect2(Vector2.ZERO, rect_size)
		if big_font == null:
			big_font = painter.tool._make_font(int(max(18, rect_size.y * 0.3)))
		if value == "random":
			painter.paint_random(self, rect, pool, big_font)
		elif value == "":
			painter.paint_own(self, rect, res)
		else:
			painter.paint(self, rect, res)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.0)


class ChoiceCard extends Control:
	signal picked
	signal hovered(inside)
	var painter
	var value = ""
	var title = ""
	var selected = false
	var inside = false
	var font = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_set_inside", [true])
		connect("mouse_exited", self, "_set_inside", [false])

	func _set_inside(value_inside: bool) -> void:
		inside = value_inside
		emit_signal("hovered", value_inside)
		update()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
			emit_signal("picked")

	func _draw() -> void:
		var swatch = Rect2(0, 0, rect_size.x, rect_size.y - 24)
		var shown = value
		if value == "__follow":
			shown = str(painter.options.get("default", ""))
		if shown == "random":
			painter.paint_random(self, swatch, painter._pool_resources(), font)
		elif shown == "":
			painter.paint_own(self, swatch, null)
		else:
			var cached = painter._ready_theme(shown)
			if cached != null: painter.paint(self, swatch, cached)
			else: painter.paint_palette(self,swatch,shown)
		if value == "__follow":
			draw_rect(swatch, Color(0.1, 0.12, 0.14, 0.55))
		var line = Color("b49cff") if selected else (Color(1, 1, 1, 0.6) if inside else Color(0, 0, 0, 0.5))
		draw_rect(swatch, line, false, 3.0 if selected else 1.5)
		if font != null:
			var text = title
			while text.length() > 3 and font.get_string_size(text).x > rect_size.x:
				text = text.substr(0, text.length() - 2) + "…"
			draw_string(font, Vector2(0, rect_size.y - 6), text, load("user://mod/core/workspace4/Galaxy.gd").color("ink"))


class MapRow extends Control:
	signal picked
	var title = ""
	var value = ""
	var playing = false
	var selected = false
	var inside = false
	var font = null
	var small = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		connect("mouse_entered", self, "_set_inside", [true])
		connect("mouse_exited", self, "_set_inside", [false])

	func _set_inside(value_inside: bool) -> void:
		inside = value_inside
		update()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
			emit_signal("picked")

	func _draw() -> void:
		var palette = load("user://mod/core/workspace4/Galaxy.gd")
		var fill = palette.color("hover" if selected or inside else "surface")
		draw_rect(Rect2(Vector2.ZERO, rect_size), fill)
		if selected:
			draw_rect(Rect2(0, 0, 3, rect_size.y), Color("b49cff"))
		if font == null:
			return
		var right = rect_size.x - 10
		if not value.empty() and small != null:
			var width = small.get_string_size(value).x
			draw_rect(Rect2(right - width - 12, rect_size.y * 0.5 - 11, width + 12, 22), Color(0.71, 0.61, 1.0, 0.18))
			draw_string(small, Vector2(right - width - 6, rect_size.y * 0.5 + 5), value, palette.color("accent"))
			right -= width + 20
		var x = 12.0
		if playing and small != null:
			draw_string(small, Vector2(x, rect_size.y * 0.5 + 5), "NOW", palette.color("success"))
			x += small.get_string_size("NOW ").x + 4
		var text = title
		while text.length() > 3 and x + font.get_string_size(text).x > right:
			text = text.substr(0, text.length() - 2) + "…"
		draw_string(font, Vector2(x, rect_size.y * 0.5 + 6), text, palette.color("ink"))
