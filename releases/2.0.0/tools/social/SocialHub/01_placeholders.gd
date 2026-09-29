extends "user://mod/tools/social/SocialHub/00_state.gd"

# Placeholders for functions that live in a later file of the SocialHub chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _refresh_party_list() -> void:
	pass

func _set_status(text: String, is_error: bool = false) -> void:
	pass

func _set_busy_controls(value: bool) -> void:
	pass

func _refresh_friends_from_server() -> void:
	pass
