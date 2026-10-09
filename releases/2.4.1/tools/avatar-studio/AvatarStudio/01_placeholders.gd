extends "user://mod/tools/avatar-studio/AvatarStudio/00_state.gd"

# Placeholders for functions that live in a later file of the AvatarStudio chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func rebuild_catalog() -> void:
	pass

func capture() -> Dictionary:
	return {}

func _restore(state: Dictionary) -> void:
	pass

func refresh() -> void:
	pass

func _load_texture(id: String) -> Texture:
	return null

func _find_look(id: String) -> Dictionary:
	return {}

func _build_look_cards() -> void:
	pass

func _render_look(target, state: Dictionary) -> void:
	pass

func _load() -> void:
	pass

func _save() -> void:
	pass

func _position_preview() -> void:
	pass

func _animate(name: String) -> void:
	pass

func _exit_playable() -> void:
	pass

func _end_item_drag() -> void:
	pass
