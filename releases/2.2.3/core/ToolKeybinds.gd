extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")

# One persistent keyboard map. Tool actions retain their original context gates.
const SETTING = "goobplayability_keybinds"
var tool
var bindings = {}
var definitions = []
var capture_id = ""
var view = null
var suppress_key = 0
const LEGACY = {KEY_F1:"menu", KEY_F2:"slower", KEY_F3:"faster", KEY_F4:"speed_reset", KEY_F5:"pause", KEY_F6:"step", KEY_F7:"camera_restore", KEY_F:"checkpoint", KEY_U:"checkpoint_undo"}

func configure(owner) -> void:
	tool = owner
	pause_mode = Node.PAUSE_MODE_PROCESS
	definitions = [
		["menu","Interface","Show / hide menu",KEY_F1,0,""],
		["slower","TAS","Slower",KEY_F2,0,""], ["faster","TAS","Faster",KEY_F3,0,""],
		["speed_reset","TAS","Reset speed",KEY_F4,0,""], ["pause","TAS","Pause / play",KEY_F5,0,""],
		["step","TAS","Frame step",KEY_F6,0,""], ["camera_restore","Timeline","Exit / restore camera",KEY_F7,0,""],
		["checkpoint","TAS","Place checkpoint",KEY_F,0,""], ["checkpoint_undo","TAS","Undo last checkpoint",KEY_U,3,""],
		["emote","Game tools","Hold emote wheel",int(SavedSettings.get_value("emote_wheel_key",KEY_F8)),0,""],
		["editor_undo","Editor+","Undo",KEY_Z,1,""], ["editor_redo","Editor+","Redo",KEY_Y,1,""],
		["editor_redo_alt","Editor+","Redo (alternate)",KEY_Z,5,""],
		["editor_thumbnail","Editor+","Thumbnail view",KEY_T,0,""], ["editor_rotate","Editor+","Rotate shape",KEY_R,0,""],
		["editor_rotate_back","Editor+","Rotate shape backwards",KEY_R,4,""],
		["studio_undo","Avatar Studio","Undo",0,0,""], ["studio_redo","Avatar Studio","Redo",0,0,""],
		["council_pause","Level Council","Replay pause / play",KEY_SPACE,0,""],
		["observer_hide","Observer","Show / hide controls",KEY_H,0,""],
		["game:optimizer","Game tools","Toggle optimizer",0,0,""], ["game:dash","Game tools","Toggle infinite dash",0,0,""],
		["game:emotes","Game tools","Toggle emote wheel",0,0,""],
		["camera_left","Free camera","Move left",KEY_LEFT,0,""], ["camera_right","Free camera","Move right",KEY_RIGHT,0,""],
		["camera_up","Free camera","Move up",KEY_UP,0,""], ["camera_down","Free camera","Move down",KEY_DOWN,0,""]
	]
	for entry in [["Macro Bot","tab:1"],["Tools","tab:0"],["Timeline","timeline"],["Replay library","replays"],["Level Council","council"],["Accounts","accounts"],["Game tools","game"],["Avatar Studio","sandbox"],["Looks","loadouts"],["Editor+","editor-plus"],["Editor themes","themes"],["Wins","wins"],["Match maps","maps"],["Top rated levels","rated"],["Autoplay","tab:2"],["Friends & Party","social"],["Diagnostics","developer"],["Action log","logs"],["Settings","settings"]]:
		definitions.append(["open:"+entry[1],"Open tools",entry[0],0,0,entry[1]])
	if ModPaths.has("JourneyHandler.gd"): definitions.append(["open:journey","Open tools","Journey (home screen)",0,0,"journey"])
	var saved = SavedSettings.get_value(SETTING,{})
	for spec in definitions:
		var fallback = {"key":spec[3],"mods":spec[4]}
		var value = saved.get(spec[0],fallback) if saved is Dictionary else fallback
		bindings[spec[0]] = value if valid(value) else fallback
		if spec[0] == "menu" and bindings[spec[0]].key == 0: bindings[spec[0]] = fallback

func valid(value) -> bool:
	return value is Dictionary and typeof(value.get("key")) == TYPE_INT and typeof(value.get("mods")) == TYPE_INT and int(value.key)>=0 and int(value.mods)>=0 and int(value.mods)<=15

func key_event(id: String) -> InputEventKey:
	var e = InputEventKey.new()
	var b = bindings.get(id,{"key":0,"mods":0})
	e.scancode = b.key
	e.control = bool(b.mods & 1)
	e.alt = bool(b.mods & 2)
	e.shift = bool(b.mods & 4)
	e.meta = bool(b.mods & 8)
	return e

func matches(event, id: String) -> bool:
	if not capture_id.empty() or not event is InputEventKey or not bindings.has(id): return false
	var wanted = key_event(id)
	return wanted.scancode != 0 and wanted.shortcut_match(event)

func held(id: String) -> bool:
	if suppress_key != 0:
		if Input.is_key_pressed(suppress_key): return false
		suppress_key = 0
	if not capture_id.empty() or not bindings.has(id): return false
	if typing() and not id in ["menu","camera_restore"]: return false
	var b = bindings[id]
	var mods = int(Input.is_key_pressed(KEY_CONTROL)) + int(Input.is_key_pressed(KEY_ALT))*2 + int(Input.is_key_pressed(KEY_SHIFT))*4 + int(Input.is_key_pressed(KEY_META))*8
	return b.key != 0 and mods == b.mods and Input.is_key_pressed(b.key)

func typing() -> bool:
	var focus = tool._menu_window.get_focus_owner() if tool._menu_window != null else null
	return focus is LineEdit or focus is TextEdit

func conflict(id: String, e: InputEventKey) -> String:
	# Existing contextual shortcuts (e.g. Space in the replay viewer) retain
	# their original defaults. New assignments still reject game controls.
	var contextual_default = false
	if id in ["council_pause","editor_undo","editor_redo","editor_redo_alt","editor_thumbnail","editor_rotate","editor_rotate_back","camera_left","camera_right","camera_up","camera_down"]:
		for spec in definitions:
			if spec[0] == id:
				var expected = InputEventKey.new()
				expected.scancode = spec[3]
				expected.control = bool(spec[4]&1)
				expected.alt = bool(spec[4]&2)
				expected.shift = bool(spec[4]&4)
				contextual_default = expected.shortcut_match(e)
	for action in InputMap.get_actions():
		if contextual_default or action == "goob_emote_wheel": continue
		for native in InputMap.get_action_list(action):
			if native is InputEventKey and native.shortcut_match(e): return "Goober Dash: " + str(action)
	for other in bindings:
		if other != id and key_event(other).scancode != 0 and key_event(other).shortcut_match(e): return "Tool: " + other
	return ""

func assign(id: String, key: int, mods: int = 0) -> void:
	if id == "menu" and key == 0: return
	bindings[id] = {"key":key,"mods":mods}
	SavedSettings.set_value(SETTING,bindings.duplicate(true))
	tool._prev_key_state.clear()
	suppress_key = key
	if tool._practice_undo_button != null:
		tool._practice_undo_button.hint_tooltip = "Remove the most recent checkpoint and segment. Shortcut: " + caption("checkpoint_undo")
	var game_tools = tool.get("_game_tools")
	if game_tools != null and id == "emote":
		var wheel = game_tools.get("_emote_wheel")
		if wheel != null: wheel.set_binding(key_event("emote").scancode)
	if is_instance_valid(view): view.refresh()

func handle(event) -> bool:
	if not capture_id.empty() and (not is_instance_valid(view) or not view.is_visible_in_tree()): capture_id = ""
	if not capture_id.empty():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.scancode == KEY_ESCAPE:
				capture_id = ""
			elif not event.scancode in [KEY_CONTROL,KEY_ALT,KEY_SHIFT,KEY_META]:
				var message = conflict(capture_id,event)
				if message.empty():
					var id = capture_id
					capture_id = ""
					assign(id,event.scancode,int(event.control)+int(event.alt)*2+int(event.shift)*4+int(event.meta)*8)
				elif is_instance_valid(view): view.message.text = "Already used: " + message
			if is_instance_valid(view): view.refresh()
		return true
	if typing() or not event is InputEventKey or not event.pressed or event.echo: return false
	for id in ["game:optimizer","game:dash","game:emotes"]:
		if matches(event,id) and tool._game_tools != null and tool._game_tools.gui_enabled:
			tool._game_tools._tool_card_pressed(id.trim_prefix("game:"))
			return true
	for spec in definitions:
		if not str(spec[0]).begins_with("open:") or not matches(event,spec[0]): continue
		if spec[5] == "journey":
			return _open_journey()
		if tool._workspace_menu != null and tool._workspace_menu.enabled(spec[5]):
			tool._set_menu_open(true)
			tool._workspace_menu.select(spec[5])
			return true
	var sandbox = tool.get("_cosmetic_sandbox")
	if sandbox != null and sandbox._studio != null and sandbox._modal_root.visible:
		if matches(event,"studio_undo"): sandbox._studio.undo(); return true
		if matches(event,"studio_redo"): sandbox._studio.redo(); return true
	return false

func caption(id: String) -> String:
	var event = key_event(id)
	return "Unbound" if event.scancode == 0 else event.as_text()

func available(id: String) -> bool:
	if id.begins_with("studio_"): return ModPaths.has("AvatarStudio.gd")
	if id.begins_with("editor_"): return ModPaths.has("EditorPlus.gd")
	if id == "council_pause": return ModPaths.has("LevelCouncil.gd")
	if id == "observer_hide": return ModPaths.has("ObserverCamera.gd")
	if id == "emote" or id.begins_with("game:"): return ModPaths.has("GameTools.gd") and (id != "game:dash" or ModPaths.has("InfiniteDash.gd"))
	return true

func _open_journey() -> bool:
	var game_tools = tool.get("_game_tools")
	if game_tools == null: return false
	for child in game_tools.get_children():
		if child.has_method("has_screen") and child.has_screen():
			var navigation = child.get("navigation")
			if navigation != null and is_instance_valid(navigation.button):
				tool._set_menu_open(false)
				navigation.button.emit_signal("pressed")
				return true
	return false
