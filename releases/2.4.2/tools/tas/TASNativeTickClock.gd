extends Reference

# NetworkGame.pre_step announces a BATCH, not one tick. WPGame.tick_post_step
# closes each real world.step in that batch. Never repeat a recorded frame to
# fill a batch or infer tick count from Godot render callbacks.
var batch_remaining = 0
var last_post_frame = -1
const MOTION_TIMERS = ["jump_timer", "jumphold_timer", "fresh_jump_timer"]

func capture_motion_timers(player: WPPlayer, state: Dictionary) -> void:
	for field in MOTION_TIMERS:
		state[field] = player.get(field)

func restore_motion_timers(player: WPPlayer, state: Dictionary) -> bool:
	var changed = false
	for field in MOTION_TIMERS:
		if state.has(field) and player.get(field) != state[field]:
			player.set(field, state[field])
			changed = true
	return changed

func begin_batch(ticks: int) -> void:
	batch_remaining = max(0, ticks)

func finish_tick(frame: int) -> bool:
	last_post_frame = frame
	batch_remaining = max(0, batch_remaining - 1)
	return batch_remaining > 0
