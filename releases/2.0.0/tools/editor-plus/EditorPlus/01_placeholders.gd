extends "user://mod/tools/editor-plus/EditorPlus/00_state.gd"

# Placeholders for functions that live in a later file of the EditorPlus chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _fit() -> void:
	pass

func _build() -> void:
	pass

func toggle_thumbnail() -> void:
	pass

func _apply_thumbnail() -> void:
	pass

func _thumbnail_players() -> void:
	pass
