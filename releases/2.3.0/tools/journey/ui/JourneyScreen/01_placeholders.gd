extends "user://mod/tools/journey/ui/JourneyScreen/00_state.gd"

# Placeholders for functions that live in a later file of the JourneyScreen chain, so earlier
# files can call them. The real function (same signature) replaces each one at runtime.

func _style_scrollbar(target):
	return null

func _banners(parent):
	return null

func _overview(parent):
	return null

func update_claims(redraw = true):
	return null

func make_badge(size = 34):
	return null

func claimables() -> Array:
	return []

func _unread() -> int:
	return 0

func streak_rewards() -> Array:
	return []

func playtime_rewards() -> Array:
	return []

func _finishes() -> Array:
	return []

func _award_quest(quest) -> bool:
	return false

func _after_claim(xp_before = -1, rank_before = null):
	return null

func _xp_bar(bar, rank):
	return null

func live(control, until, fmt):
	return null

func _check_rank_up():
	return null

func open_xp_calculator(_arg = null):
	return null

func _claim_fx(source, xp):
	return null

func _toast(text):
	return null

func notify(kind, title, detail = "", xp = 0, target = "inbox"):
	return null

func _open_inbox():
	return null

func _open_prefs():
	return null

func is_admin() -> bool:
	return false

func _apply_test_xp(m):
	return null

func close_overlay():
	return null

func _load_prefs():
	return null

func play(key, pitch = 1.0):
	return null

func set_pref(key, value):
	return null

func _settings():
	return null

func celebrate(rank, unlocks = []):
	return null

func show_match_results(awards, xp_before = -1, title = "", animate = true):
	return null
