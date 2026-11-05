extends Node

# Pause engine-driven preview animation with its UI. set_process(false) alone
# does not stop Spine's internal skeleton tick. Native match actors are excluded:
# only descendants of explicit mod Control/CanvasLayer boundaries are watched.
var owner_tool
var watched = {}

static func ensure(owner):
	var existing = owner.get_node_or_null("GoobPreviewActivity")
	if existing != null: return existing
	var activity = load("user://mod/core/workspace4/PreviewActivity.gd").new()
	activity.owner_tool = owner
	activity.name = "GoobPreviewActivity"
	owner.add_child(activity)
	return activity

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("node_added",self,"_added")
	_scan(owner_tool)
	set_process(false)

func _scan(node):
	_added(node)
	for child in node.get_children(): _scan(child)

func _added(node):
	if not (node is SpineSprite or node is CPUParticles2D or node is Particles2D): return
	var boundary = node.get_parent()
	while boundary != null and boundary != owner_tool:
		if boundary is UpGuys_PlayerRenderer or boundary is NetworkGameRenderer or boundary is WPGame: return
		if boundary is Control or boundary is CanvasLayer:
			var script = boundary.get_script()
			if script != null and script.resource_path.begins_with(get_script().resource_path.get_base_dir().get_base_dir().get_base_dir()+"/"):
				call_deferred("_watch",weakref(node))
				return
		boundary = boundary.get_parent()

func _watch(reference):
	var node = reference.get_ref()
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	var id = node.get_instance_id()
	if watched.has(id): return
	watched[id] = {"ref":reference,"asleep":false}
	node.connect("visibility_changed",self,"_sync",[id])
	node.connect("tree_exiting",self,"_forget",[id])
	_sync(id)

func _sync(id):
	if not watched.has(id): return
	var state = watched[id]
	var node = state.ref.get_ref()
	if not is_instance_valid(node):
		watched.erase(id)
		return
	var asleep = not node.is_visible_in_tree()
	if asleep == state.asleep: return
	state.asleep = asleep
	if asleep:
		state.process = node.is_processing()
		node.set_process(false)
		if node is SpineSprite:
			state.mode = node.update_mode
			node.update_mode = SpineConstant.UpdateMode_Manual
		else:
			state.speed = node.speed_scale
			node.speed_scale = 0.0
	else:
		node.set_process(state.process)
		if node is SpineSprite: node.update_mode = state.mode
		else: node.speed_scale = state.speed

func _forget(id):
	if not watched.has(id): return
	var state = watched[id]
	var node = state.ref.get_ref()
	if is_instance_valid(node):
		# Restore before reparenting so the new preview captures real settings.
		if state.asleep:
			node.set_process(state.process)
			if node is SpineSprite: node.update_mode = state.mode
			else: node.speed_scale = state.speed
		for pair in [["visibility_changed","_sync"],["tree_exiting","_forget"]]:
			if node.is_connected(pair[0],self,pair[1]): node.disconnect(pair[0],self,pair[1])
	watched.erase(id)

func _exit_tree():
	for id in watched.keys(): _forget(id)
