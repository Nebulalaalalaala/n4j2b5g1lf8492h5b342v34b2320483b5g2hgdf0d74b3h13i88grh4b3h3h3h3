extends Node

# TASTool itself has an extremely early process priority so injected input
# reaches the game in time.  This tiny companion deliberately runs at the
# opposite end of the physics callback order: it observes/corrects state
# after Goober Dash's native tick has had its chance to overwrite it.
var tas_tool = null


func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	set_process_priority(1000000)


func _process(_delta: float) -> void:
	if tas_tool != null and is_instance_valid(tas_tool):
		tas_tool._post_renderer_stitch_guard()


func _physics_process(_delta: float) -> void:
	if tas_tool != null and is_instance_valid(tas_tool):
		tas_tool._post_native_death_momentum_guard()
		tas_tool._capture_playback_visual_sample()
