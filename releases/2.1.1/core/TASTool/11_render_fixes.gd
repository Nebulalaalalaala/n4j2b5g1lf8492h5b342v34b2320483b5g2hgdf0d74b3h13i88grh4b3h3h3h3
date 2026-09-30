extends "user://mod/core/TASTool/10_updater.gd"

func _apply_tas_gui_visibility() -> void:
	if _overlay_layer != null:
		_overlay_layer.visible = _tas_gui_enabled and not _overlay_hidden
	if _world_overlay != null and is_instance_valid(_world_overlay):
		_world_overlay.visible = not _overlay_hidden
	_set_practice_markers_visible(not _overlay_hidden)
	if not _tas_gui_enabled and _macro_editor != null and is_instance_valid(_macro_editor) and _macro_editor.has_method("is_open") and bool(_macro_editor.call("is_open")):
		_macro_editor.call("close_editor")
	if not _tas_gui_enabled and _replay_hub != null and is_instance_valid(_replay_hub) and _replay_hub.has_method("is_open") and bool(_replay_hub.call("is_open")):
		_replay_hub.call("close_hub")
	if not _tas_gui_enabled and _game_tools != null and is_instance_valid(_game_tools) and _game_tools.has_method("is_open") and bool(_game_tools.call("is_open")):
		_game_tools.call("close_window")
	_update_mouse_capture()

func _maintain_terrain_fallback_rendering(game: WPGame) -> void:
	# DIAGNOSTIC (temporary): _log_action() only writes to the in-tool Action
	# Log panel, never to godot.log. _terrain_fallback_debug() below uses
	# print() so its trail lands in godot.log regardless of what the in-game
	# panel shows. Safe to remove once this fix is confirmed working in-game
	# and left alone for a while.
	if game == null:
		_terrain_fallback_debug("no WPGame found")
		return
	if not ("level" in game):
		_terrain_fallback_debug("WPGame has no 'level' property")
		return
	var level = game.get("level")
	if level == null:
		_terrain_fallback_debug("game.level is null")
		return
	if not ("loaded_level" in level):
		_terrain_fallback_debug("level has no 'loaded_level' property")
		return
	var loaded_level = level.get("loaded_level")
	if loaded_level == null:
		_terrain_fallback_debug("level.loaded_level is null")
		return
	var loaded_level_id: int = loaded_level.get_instance_id()
	var now = OS.get_ticks_msec()
	var child_count = loaded_level.get_child_count()
	if loaded_level_id == _terrain_fallback_level_id and child_count == _terrain_maintenance_child_count and now < _terrain_maintenance_next_ms:
		return
	_terrain_maintenance_next_ms = now + 250
	_terrain_maintenance_child_count = child_count
	if loaded_level_id != _terrain_fallback_level_id:
		_terrain_fallback_level_id = loaded_level_id
		_terrain_fallback_debug("new loaded_level id=%d -- applying always-on block/ramp safety net" % loaded_level_id)

	# v3 -- unconditional safety net, no success/failure detection at all.
	# Three narrower attempts (a level-wide "zero fill" check, then a
	# per-node point-in-polygon coverage test against PolygonTerrain's real
	# output, then a hardened version of that same test) each produced
	# exactly zero visible change in-game, despite being reasoned from the
	# decompiled source and, as far as static reading can tell, individually
	# sound. That pattern -- three different detection conditions, zero
	# observable effect from any of them -- points at something shared by
	# all three rather than any one heuristic: most likely the shared
	# game/level/loaded_level/PolygonTerrain lookup above silently failing
	# in a way this environment cannot exercise or confirm without a live
	# Godot process. Rather than guess a fourth detection condition, this
	# version removes detection entirely: every non-animated "block"/"ramp"
	# LevelNode's own Polygon2D is unconditionally shown and textured, every
	# frame, with its z-index forced below PolygonTerrain's merged output so
	# a successful merge still visually covers it exactly as before. See
	# _apply_terrain_fallback_rendering_unconditional()'s own comment for
	# the known cosmetic tradeoff this accepts.
	_apply_terrain_fallback_rendering_unconditional(level, loaded_level)
func _terrain_fallback_debug(message: String) -> void:
	if message == _terrain_fallback_debug_last_message:
		return
	_terrain_fallback_debug_last_message = message
	if _debug_mode_enabled:
		print("[Goobplayability][TerrainFallback] " + message)


# Unconditionally shows and textures every non-animated "block"/"ramp"
# LevelNode's own (normally hidden, merge-input-only) Polygon2D, every
# frame, regardless of whether PolygonTerrain's merge actually succeeded
# for it. No success/failure detection at all -- see
# _maintain_terrain_fallback_rendering()'s comment for why three
# progressively more careful detection-based attempts were abandoned in
# favor of this.
# To avoid this drawing OVER a successful merge (which would turn every
# normal, correctly-rounded block in every level into a flat, square-
# cornered rectangle), each Polygon2D's z-index is forced below
# PolygonTerrain's own (both LevelNode and PolygonTerrain default to
# z_index=100, z_as_relative=true under Level.tscn -- equal z, so without
# this they'd tie-break on scene tree order, which is not guaranteed to put
# PolygonTerrain's merged mesh on top). z_as_relative=false makes the
# override absolute regardless of ancestor z-index, so it reliably stays
# beneath PolygonTerrain's merged fill wherever the merge succeeds, and is
# the only thing visible wherever it doesn't.
# Known cosmetic tradeoff, accepted deliberately: PolygonTerrain's merged
# fill has rounded corners (the theme's terrain_corner_radius) and the raw
# Polygon2D here is a plain, square-cornered rectangle/triangle. Since the
# fallback is now always present underneath, a small square-cornered sliver
# can peek out past each rounded corner on EVERY block/ramp in EVERY level,
# not just the pathologically thin ones this fix targets. That's a real,
# permanent, minor visual regression -- traded deliberately for actually
# guaranteeing no level is ever left fully hollow, since three attempts at
# a "no visible change when the merge already works" detection produced
# zero observable effect in-game and could not be verified further without
# a live Godot process. If the corner artifact turns out to be more
# noticeable/objectionable in practice than a rare hollow level, that's the
# tradeoff to revisit first.
func _apply_terrain_fallback_rendering_unconditional(level, loaded_level: Node) -> void:
	var theme = null
	if "level_theme" in level:
		theme = level.get("level_theme")
	var terrain_texture: Texture = null
	if theme != null and ("terrain_texture" in theme):
		terrain_texture = theme.get("terrain_texture") as Texture

	for child in loaded_level.get_children():
		if not ("node_type" in child):
			continue
		var node_type: String = str(child.get("node_type"))
		if node_type != "block" and node_type != "ramp":
			continue
		if ("animation" in child) and child.get("animation") != null:
			continue
		if child.has_method("show"):
			child.call("show")
		if "z_as_relative" in child:
			child.set("z_as_relative", false)
		if "z_index" in child:
			child.set("z_index", 50)
		if not ("renderer" in child):
			continue
		var renderer = child.get("renderer")
		if renderer == null:
			continue
		var polygon2d = renderer.get_node_or_null("Polygon2D")
		if polygon2d != null:
			polygon2d.set("visible", true)
			polygon2d.set("z_as_relative", false)
			polygon2d.set("z_index", 50)
			if terrain_texture != null and ("texture" in polygon2d):
				polygon2d.set("texture", terrain_texture)


# Called via call_deferred() from _process(), never directly. Read (decompiled):
# - physics_block/PhysicsBlockRenderer.gd sets `visible = false` itself, every
#   frame, whenever ViewportRectCalculator.viewport_visible_rect (however
#   fresh or stale) doesn't intersect the block's own world rect.
# - ice_block's ShaderUniformCamera.gd doesn't touch visibility, but feeds
#   that same rect's center into the ice shader as `camera_position` every
#   frame -- a wrong value there can make the reflection effect render wrong/
#   blank, which is visually indistinguishable from "invisible" at a glance.
# - jump_zone and sawblade don't reference ViewportRectCalculator at all in
#   their own scripts, so whatever hides them (if the exemption above didn't
#   already fix it) is a still-unidentified, separate mechanism.
# Rather than keep tracking down each type's own native condition one at a
# time, this forces the single outcome every one of them needs -- visible,
# unconditionally -- the same way _apply_terrain_fallback_rendering_unconditional()
# already does for block/ramp. It has to run via call_deferred(), AFTER this
# frame's regular _process() pass, because TASTool.gd sets its own
# process_priority to -1000000 (see _ready()) so it runs FIRST, before native
# nodes -- including PhysicsBlockRenderer.gd, whose own _process() would
# simply overwrite `visible = false` again later in the same frame if this
# ran directly from TASTool's _process() instead of deferred after it.
func _force_dynamic_object_visibility_late(game: WPGame) -> void:
	# 1.2.10 -- now that this covers every node type in the game (many of
	# which have real, legitimate show/hide or animation-driven visibility
	# as part of actual gameplay -- disappearing_block literally disappears
	# on purpose, cannons/lasers/alerts/checkpoints likely toggle state too),
	# unconditionally forcing them all visible EVERY frame regardless of
	# context would be a real gameplay regression, not just a harmless no-op
	# like it was for the original 4 always-visible-in-real-play types
	# (physics/ice blocks, jump zones, sawblades). Restricting this to only
	# run while the Timeline Editor preview is actually active keeps it
	# scoped to the bug Len is actually reporting (objects invisible in the
	# editor) without touching normal gameplay at all.
	if not _macro_editor_preview_active:
		return
	if game == null:
		return
	if not ("level" in game):
		return
	var level = game.get("level")
	if level == null:
		return
	if not ("loaded_level" in level):
		return
	var loaded_level = level.get("loaded_level")
	if loaded_level == null:
		return
	for child in loaded_level.get_children():
		if not ("node_type" in child):
			continue
		var node_type: String = str(child.get("node_type"))
		if not (node_type in FORCE_VISIBLE_NODE_TYPES):
			continue
		# Same caution _apply_terrain_fallback_rendering_unconditional() already
		# takes for block/ramp: don't fight a node that's deliberately mid-
		# animation (disappearing_block chief among the new types this could
		# matter for) even while paused for preview.
		if ("animation" in child) and child.get("animation") != null:
			continue
		if child.has_method("show"):
			child.call("show")
		if "visible" in child:
			child.set("visible", true)
		if not ("renderer" in child):
			continue
		var renderer = child.get("renderer")
		if renderer == null:
			continue
		if renderer.has_method("show"):
			renderer.call("show")
		if "visible" in renderer:
			renderer.set("visible", true)
		# 1.2.9 -- ice_block-specific safety net. Jump zones and sawblades
		# were fully fixed by the two lines above (forcing the LevelNode and
		# its top-level "Renderer" node visible); ice blocks were not, per
		# Len's report, even though ice_block's Renderer.tscn uses the same
		# generic LevelNodeRenderer base as jump_zone/sawblade and nothing
		# found by reading the decompiled source explains why it would
		# behave differently. Since the actual mechanism is unconfirmed,
		# this additionally force-shows the two named mesh children the ice
		# block's own scene defines (MeshInstance2D2 -- the base ice sprite
		# with the reflection shader -- and Outline), in case one of them
		# specifically ends up hidden by something this function's first two
		# checks don't reach. Deliberately NOT touching
		# "UpGuys_LevelNodeShadow" (shipped already `visible = false` in the
		# base scene -- that's the drop-shadow, not the ice block itself).
		if node_type == "ice_block":
			for ice_child_name in ["MeshInstance2D2", "Outline"]:
				var ice_child = renderer.get_node_or_null(ice_child_name)
				if ice_child != null:
					if ice_child.has_method("show"):
						ice_child.call("show")
					if "visible" in ice_child:
						ice_child.set("visible", true)


# DISPLAY ACCURACY: the game's own WPPlayerRenderer (renderers/WPPlayerRenderer.gd,
# _compute_position()) does its own client-side smoothing SEPARATE from the
# player's actual simulated position -- it's built to hide small network
# corrections, not to represent deliberate teleports. It compares where the
# player "should" be (prev_position + prev_velocity * tick_rate) against
# where it actually now is; if that distance lands between 25 and 100 units
# it starts a smooth_damp glide from the old spot to the new one instead of
# snapping, and once started it keeps gliding for as long as it stays more
# than 1 unit off target. A real level checkpoint-to-checkpoint respawn is
# usually a big enough jump to land above that 100-unit ceiling and snap
# instantly, which is almost certainly why this never shows up in normal
# play -- but Macro Bot Mode checkpoints are typically placed close together
# on purpose (that's the point of GD-style segment practice), so a restore
# lands squarely in that 25-100 "please smooth this" zone the renderer
# mistakes our deliberate teleport for a minor correction to glide through.
# That's what "the macro doesn't display correctly" almost certainly is:
# the character visibly sliding to the checkpoint instead of appearing there
# instantly, on every restore.
#   is_smoothing and smoothed_p are plain (non-native) vars declared right
# in WPPlayerRenderer.gd, so writing them is guaranteed to take. prev_position
# and prev_velocity are inherited from its native base class and aren't
# something we can fully verify from the outside -- writing them is
# best-effort (a dynamic Object.set() on an untyped Node reference, which
# Godot no-ops harmlessly rather than erroring if the property turns out not
# to be externally settable), not a guaranteed fix on its own. Together they
# should stop both a smoothing glide already in progress from continuing
# (is_smoothing/smoothed_p, guaranteed) and a fresh one from starting on the
# very next frame because prev_position/prev_velocity still reflect where
# the player was a moment ago (prev_position/prev_velocity, best-effort).
func _reset_renderer_smoothing(player: WPPlayer) -> void:
	var renderer: = _find_player_renderer(player)
	if renderer == null:
		return
	if renderer.get("is_smoothing") != null:
		renderer.is_smoothing = false
	if renderer.get("smoothed_p") != null:
		renderer.smoothed_p = player.linear_velocity
	if renderer.get("prev_position") != null:
		renderer.prev_position = player.position
	if renderer.get("prev_velocity") != null:
		renderer.prev_velocity = player.linear_velocity
