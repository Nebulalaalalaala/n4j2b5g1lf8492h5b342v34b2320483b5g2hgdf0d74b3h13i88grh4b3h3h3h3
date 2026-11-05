extends "user://mod/tools/avatar-studio/AvatarStudio/05_drag_animation.gd"

# AvatarStudio is split into feature files (see the AvatarStudio/ folder). This file only
# closes the chain so the loader and other scripts keep using the same path.

func _open_custom_effects():
	load("user://mod/core/workspace4/effects/StudioEffectBridge.gd").open_editor(self)

func _link_custom_effect():
	load("user://mod/core/workspace4/effects/StudioEffectBridge.gd").link(self)

func _follow_global_effect():
	load("user://mod/core/workspace4/effects/StudioEffectBridge.gd").follow(self)
