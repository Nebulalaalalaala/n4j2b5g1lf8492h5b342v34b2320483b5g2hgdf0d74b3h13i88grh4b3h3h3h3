extends "user://mod/core/TASTool/04_host_2.gd"

# ----------------------------------------------------------------------
#  Finding the active game / local player / scene
# ----------------------------------------------------------------------
func _initialize_game_discovery() -> void:
	if _game_discovery_initialized:
		return
	_game_discovery_initialized = true
	var tree: = get_tree()
	# A null result used to be re-searched from SceneTree.root on every call.
	# The main menu has no WPGame, and several idle/physics watchers ask for one
	# each frame, so that meant multiple full walks of the (large) menu tree per
	# frame. Scan once for nodes which predate this autoload, then keep the cache
	# current from SceneTree's O(1)-per-added/removed-node notifications.
	if not tree.is_connected("node_added", self, "_on_tas_tree_node_added"):
		tree.connect("node_added", self, "_on_tas_tree_node_added")
	if not tree.is_connected("node_removed", self, "_on_tas_tree_node_removed"):
		tree.connect("node_removed", self, "_on_tas_tree_node_removed")
	_set_cached_game(_search_for_game(tree.root) as WPGame)

func _is_game_candidate(node: Node) -> bool:
	return node != null and not node.has_meta("goobplayability_review_only") and node.has_method("serialize_replay") and node.has_method("get_player_at_index")


func _set_cached_game(game: WPGame) -> void:
	if game == _game:
		return
	_game = game
	if _game != null:
		_connect_game_over_submission_guard(_game)
		_practice_auto_activate_was_pre = false
		_practice_auto_activate_checked_state_for_game = false
		_practice_auto_activate_waiting_for_alive = false


func _find_game() -> WPGame:
	if is_instance_valid(_game) and _game.is_inside_tree():
		return _game
	_game = null
	if not _game_discovery_initialized:
		_initialize_game_discovery()
	return _game


func _get_local_player() -> WPPlayer:
	var g: = _find_game()
	if g == null:
		return null
	var count: int = g.get_player_count()
	for i in count:
		var p: WPPlayer = g.get_player_at_index(i) as WPPlayer
		if p != null and g.is_local_player(p.object_id):
			return p
	return null


# ----------------------------------------------------------------------
#  Undo-able action log
# ----------------------------------------------------------------------
func _format_time() -> String:
	var t: = OS.get_time()
	return "%02d:%02d:%02d" % [t["hour"], t["minute"], t["second"]]


# Duck-typed search for the local player's renderer node (WPPlayerRenderer,
# or whatever future class fills that role) -- no hard class dependency, so
# a scene where it doesn't exist (e.g. this stub/test context, or a future
# build that renames/removes it) just means _reset_renderer_smoothing() is a
# no-op rather than a crash. Matched by get_network_object() identity rather
# than object_id, since that's the most direct "this renders THIS player"
# check available and mirrors how the game's own renderer code (see
# cheers_emit_confetti() in WPPlayerRenderer.gd) fetches its own player.
func _find_player_renderer(player: WPPlayer) -> Node:
	return _search_for_player_renderer(get_tree().root, player)



func _search_for_game(node: Node) -> Node:
	if node == null:
		return null
	if _is_game_candidate(node):
		return node
	for child in node.get_children():
		var found: Node = _search_for_game(child)
		if found != null:
			return found
	return null


func _search_for_player_renderer(node: Node, player: WPPlayer) -> Node:
	if node == null:
		return null
	if node.has_method("get_network_object") and node.has_method("get_object_id"):
		if node.get_network_object() == player:
			return node
	for child in node.get_children():
		var found: Node = _search_for_player_renderer(child, player)
		if found != null:
			return found
	return null
