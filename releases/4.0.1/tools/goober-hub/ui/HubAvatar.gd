extends Control
# A player's Goober, drawn with the game's own profile rig (upguy.tscn).
var goober
var skin = null setget show_skin
var own_tool = null

func _init(size = Vector2(220, 280)):
	rect_min_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_clip_content = false

func _ready():
	var scene = load("res://project_specific/gfx/spine/upguy/upguy.tscn")
	if scene == null:
		return
	goober = scene.instance()
	add_child(goober)
	_place()
	connect("resized", self, "_place")
	show_skin(skin if skin is Dictionary else {})
	# Without a skin the rig shows its editor preview ("body/Skeleton") in the setup pose.
	var state = goober.get_animation_state() if goober.has_method("get_animation_state") else null
	if state != null:
		state.set_animation("Idle", true, 0)

func _place():
	if goober != null:
		# The profile dialog draws it at 0.3 in a 600-tall holder that is itself scaled 0.66.
		var s = rect_size.y * 0.3 * 0.66 / 600.0
		goober.position = Vector2(rect_size.x * 0.5, rect_size.y * 0.965)
		goober.scale = Vector2(-s, s)

func show_skin(value):
	skin = value
	if goober == null or not value is Dictionary:
		return
	# An empty skin is a bare rig (just the skeleton): fall back to the default Goober.
	goober.set("apply_defaults", true)
	if goober.has_method("set_goober_skin_data"):
		goober.set_goober_skin_data(value if not value.empty() else {"color": "color_default"})
	# Your own Avatar Studio look, as Profile+ shows it.
	if own_tool != null and is_instance_valid(own_tool):
		var sandbox = own_tool.get("_cosmetic_sandbox")
		if sandbox != null and is_instance_valid(sandbox) and sandbox.has_method("_apply_to_goober"):
			sandbox.call("_apply_to_goober", goober, sandbox.call("_build_local_skin"))
