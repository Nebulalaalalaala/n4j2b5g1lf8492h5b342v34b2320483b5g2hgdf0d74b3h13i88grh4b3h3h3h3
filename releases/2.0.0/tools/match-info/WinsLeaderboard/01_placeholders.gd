extends "user://mod/tools/match-info/WinsLeaderboard/00_state.gd"

# Placeholders for functions that live in a later file of the WinsLeaderboard chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _period_result(period: String, latest_key: String) -> Dictionary:
	return {}

func _add_native_row(entry: Dictionary, rank: int, alternate: bool) -> void:
	pass

func _clear_rows() -> void:
	pass

func _add_empty_message(message: String) -> void:
	pass

func _load_snapshots() -> void:
	pass

func _save_snapshots() -> void:
	pass

func _prune_snapshots() -> void:
	pass

func _latest_snapshot_key() -> String:
	return ""

func _utc_date_key(date: Dictionary) -> String:
	return ""

func _make_label(text: String, size: int, color: Color) -> Label:
	return null

func _make_button(text: String, color: Color, width: int) -> Button:
	return null

func _log(message: String) -> void:
	pass
