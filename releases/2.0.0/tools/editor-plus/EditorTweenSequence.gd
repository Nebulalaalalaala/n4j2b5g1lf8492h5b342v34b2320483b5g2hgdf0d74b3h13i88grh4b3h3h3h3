extends "res://project_specific/level_editor/animation_editor/TweenSequenceEditor.gd"

func _move_tween(index: int, new_index: int):
	var parent = get_parent()
	while parent != null:
		if parent is LevelEditor_AnimationEditor and parent.has_method("reorder_keys"):
			parent.reorder_keys(index, new_index)
			return
		parent = parent.get_parent()
