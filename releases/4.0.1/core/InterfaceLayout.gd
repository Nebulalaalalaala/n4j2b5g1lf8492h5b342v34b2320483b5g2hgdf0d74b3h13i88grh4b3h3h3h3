extends Node
const ModPaths = preload("user://mod/core/ModPaths.gd")
const SETTING = "goob_interface_layout_v1"
const KEYS = ["home_stats", "hud_journey", "hud_hub"]
var bindings = []
var layouts = {}
var editor = null

# One shared UI-only owner. Nothing here changes gameplay state or time scale.
static func acquire(tree):
	var existing = tree.root.get_node_or_null("GoobInterfaceLayout")
	if existing != null:
		return existing
	var service = load(ModPaths.path("InterfaceLayout.gd")).new()
	service.name = "GoobInterfaceLayout"
	tree.root.add_child(service)
	return service

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(false)
	var settings = get_tree().root.get_node_or_null("SavedSettings")
	if settings != null:
		layouts = sanitize(settings.get_value(SETTING, {}))

static func sanitize(raw):
	var out = {}
	if not raw is Dictionary:
		return out
	for key in KEYS:
		var value = raw.get(key)
		if not value is Dictionary:
			continue
		var valid = true
		for field in ["x", "y", "scale"]:
			var number = value.get(field)
			if not typeof(number) in [TYPE_REAL, TYPE_INT] or is_nan(float(number)) or is_inf(float(number)):
				valid = false
		if valid:
			out[key] = {"x": clamp(float(value.x), 0, 1), "y": clamp(float(value.y), 0, 1), "scale": clamp(float(value.scale), 0.5, 1.75)}
	return out

func bind(target, space, key, title, scope, slot = null):
	var binding = load(ModPaths.path("InterfaceLayoutBinding.gd")).new()
	binding.service = self
	binding.target = weakref(target)
	binding.space = weakref(space)
	binding.slot = weakref(slot) if slot != null else null
	binding.key = key
	binding.title = title
	binding.scope = scope
	target.add_child(binding)
	bindings.append(weakref(binding))
	return binding

func bind_hud(button, hud, key, title):
	var column = button.get_parent()
	var index = button.get_index()
	var slot = Control.new()
	slot.name = button.name
	slot.rect_min_size = button.rect_min_size
	slot.size_flags_horizontal = button.size_flags_horizontal
	slot.size_flags_vertical = button.size_flags_vertical
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.remove_child(button)
	column.add_child(slot)
	column.move_child(slot, index)
	var space = hud.get_node("Container")
	space.add_child(button)
	hud.set_meta("layout_" + str(button.name), weakref(button))
	var binding = bind(button, space, key, title, "match", slot)
	column.connect("sort_children", binding, "apply", [], CONNECT_DEFERRED)
	return binding

func preference(key, fallback = true):
	var settings = get_tree().root.get_node_or_null("SavedSettings")
	return settings.get_value("journey_pref_" + key, fallback) if settings != null else fallback

func refresh():
	var living = []
	for ref in bindings:
		var binding = ref.get_ref()
		if is_instance_valid(binding):
			living.append(ref)
			binding.apply()
	bindings = living

func available(scope):
	var out = []
	for ref in bindings:
		var binding = ref.get_ref()
		if is_instance_valid(binding) and binding.scope == scope and binding.is_available():
			out.append(binding)
	return out

func commit(draft):
	layouts = sanitize(draft)
	var settings = get_tree().root.get_node_or_null("SavedSettings")
	if settings != null:
		settings.set_value(SETTING, layouts.duplicate(true))
	refresh()

func open(screen):
	if is_instance_valid(editor):
		return
	var scope = "match" if screen.closable else "home"
	var targets = available(scope)
	if targets.empty():
		screen._toast("Layout editing is available on the home screen or in a match.")
		return
	editor = load(ModPaths.path("InterfaceLayoutEditor.gd")).new()
	editor.service = self
	editor.screen = weakref(screen)
	editor.scope = scope
	editor.targets = targets
	add_child(editor)
