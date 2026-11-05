extends "res://scripts/WPGame.gd"

# Private replay observer only. The native WPGame tick remains unchanged.
# Stock tick_post_step is suppressed during native replay resimulation, so
# observe after the original tick as well to retain frames in render batches.
signal route_capture_tick
func _tick_game():
	._tick_game()
	emit_signal("route_capture_tick")
