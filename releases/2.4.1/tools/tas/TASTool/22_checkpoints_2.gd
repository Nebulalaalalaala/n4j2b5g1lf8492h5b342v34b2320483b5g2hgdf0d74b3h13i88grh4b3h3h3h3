extends "user://mod/tools/tas/TASTool/21_checkpoints_1.gd"

# Returns the highest index i into _practice_playback_checkpoint_at (i.e.
# checkpoint i) whose recorded frame-index equals target, or -1 if none
# match. See the call site's comment for why "highest," not "first," is
# the correct match when zero-length segments make two boundaries share
# the same frame index.
func _find_last_checkpoint_boundary(target: int) -> int:
	for i in range(_practice_playback_checkpoint_at.size() - 1, -1, -1):
		if _practice_playback_checkpoint_at[i] == target:
			return i
	return -1
