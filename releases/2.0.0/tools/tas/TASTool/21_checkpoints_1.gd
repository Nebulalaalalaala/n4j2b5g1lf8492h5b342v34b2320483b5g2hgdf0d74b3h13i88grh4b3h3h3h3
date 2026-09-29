extends "user://mod/tools/tas/TASTool/20_macro_slots_2.gd"

func _restore_engine_state(s: Dictionary) -> void:
	if s["is_paused"]:
		_is_paused = true
		_saved_time_scale = s["saved_time_scale"]
		Engine.time_scale = 0.0
	else:
		_is_paused = false
		Engine.time_scale = s["time_scale"]


func _apply_undo(undo: Dictionary) -> void:
	var kind: String = undo.get("type", "")
	if kind == "engine_state":
		_restore_engine_state(undo["state"])


# Mirrors the fields WPGame itself reads/writes in respawn_player() and
# _set_players_to_start_positions(). Extend this dictionary if your player
# script exposes more state you want captured (e.g. custom power-ups).
# THE REAL ROOT CAUSE (2026-08-30, found via the first Key Event report with
# hold-state/frozen-stretch visibility): a Play Macro run whose checkpoint 0
# was captured DURING the level's own initial "wait a few seconds before you
# can move" hold (alive=true, body_enabled=false, dead_counter=0 -- this is
# NOT the death/respawn countdown, dead_counter stays 0 throughout it; it's
# WPGame's own LEVEL_PRE hold) can never be faithfully replayed. Evidence: a
# real divergence report showed live correctly HOLDING (position/enabled
# frozen) through tick 6+ after such a checkpoint's restore, while replay's
# player flipped enabled=true and teleported ~1200 units to a totally
# different position -- matching a LATER checkpoint's own recorded position
# almost exactly -- on the very NEXT tick. _restore_player() already
# restores last_checkpoint/last_checkpoint_anchor correctly, ruling out a
# stale-pointer bug there. The real mechanism: Play Macro restores player
# state IN PLACE on the SAME already-running WPGame instance -- it never
# reloads the level -- so wp_game_data.gameplay_state is already past
# LEVEL_PRE (the original live recording already transitioned it once, for
# real, at the actual correct moment). The instant that checkpoint's
# still-disabled snapshot is restored, the native game sees "alive, disabled
# player" + "gameplay already active" -- exactly what its own death/respawn
# recovery path exists to correct -- and calls what is presumably the same
# respawn_player() plumbing that legitimately fires after a real death:
# reposition to last_checkpoint, re-enable, reset velocity. Live never hits
# this because gameplay_state genuinely WAS still LEVEL_PRE at that real
# moment; replay always will, no matter how faithfully everything else is
# reproduced, because nothing about Play Macro re-enters LEVEL_PRE.
#   THE FIX: stop this at the source instead of trying to out-race or
# suppress a native recovery path we don't control -- refuse to snapshot
# ANY checkpoint (0 or otherwise) while the player is still in this state.
# This helper is the single place that decision is made, shared by
# _start_practice_mode(), _on_place_practice_checkpoint_pressed(), and
# _watch_practice_auto_activate()'s own separate wait -- all three used to
# gate on `alive` alone, which is exactly the gap that let this happen
# (alive is already true throughout the LEVEL_PRE hold; only body_enabled
# tells the two apart).
func _player_ready_for_checkpoint(p: WPPlayer) -> bool:
	return p.alive and p.body_enabled


func _game_ready_for_practice_start() -> bool:
	var g: = _find_game()
	if g == null or g.wp_game_data == null:
		return false
	var data: = g.wp_game_data
	if not ("gameplay_state" in data) or not ("state_time" in data):
		return false
	if data.gameplay_state != WPGameData.GameplayState_LEVEL_PLAY:
		return false
	var physics_fps: = max(1.0, float(Engine.iterations_per_second))
	return float(data.state_time) >= float(PRACTICE_START_MIN_ACTIVE_TICKS) / physics_fps


func _snapshot_moving_world_state(game: WPGame) -> Array:
	var result := []
	if game == null or not ("level" in game) or game.level == null:
		return result
	_snapshot_moving_world_state_recursive(game.level, game.level, result)
	return result


func _snapshot_moving_world_state_recursive(level_root: Node, node: Node, result: Array) -> void:
	if node.get_class() == "LevelNodeAnimation":
		result.append({"kind": "level_animation", "path": str(level_root.get_path_to(node)), "transform": node.transform, "parent_transform": node.get_parent().transform})
	elif node is AnimationPlayer:
		var animation := node as AnimationPlayer
		var animation_name: String = animation.current_animation
		var animation_position: float = 0.0
		# Godot reports an engine error when current_animation_position is read
		# from an idle AnimationPlayer. Empty players are common in downloaded
		# levels, so snapshot them without querying that invalid property.
		if not animation_name.empty():
			animation_position = animation.current_animation_position
		result.append({
			"kind": "animation",
			"path": str(level_root.get_path_to(animation)),
			"animation": animation_name,
			"position": animation_position,
			"speed": animation.playback_speed,
			"playing": animation.is_playing(),
		})
	elif node is Node2D and (node is RigidBody2D or node is KinematicBody2D or node.get_class() == "Box2DPhysicsBody"):
		var moving := node as Node2D
		var entry := {
			"kind": "body",
			"path": str(level_root.get_path_to(moving)),
			"position": moving.position,
			"rotation": moving.rotation,
			"scale": moving.scale,
		}
		if "linear_velocity" in moving:
			entry["linear_velocity"] = moving.get("linear_velocity")
		if "angular_velocity" in moving:
			entry["angular_velocity"] = moving.get("angular_velocity")
		if "enabled" in moving:
			entry["enabled"] = moving.get("enabled")
		result.append(entry)
	for child in node.get_children():
		_snapshot_moving_world_state_recursive(level_root, child, result)


func _restore_moving_world_state(snapshot: Dictionary, force := false) -> void:
	# An edited-level continuation must never reapply old object paths/transforms.
	if _continue_resimulating:
		return
	if not _sync_moving_objects_enabled and not force:
		return
	var game := _find_game()
	if game == null or not game.is_server() or not ("level" in game) or game.level == null:
		return
	if snapshot.has("moving_world_time") or snapshot.has("play_time"):
		_restore_native_world_phase(game, float(snapshot.get("moving_world_time", snapshot.get("play_time", 0.0))))
	if not snapshot.has("moving_world_state"):
		if snapshot.has("moving_world_time"):
			return
		# Compatibility for format-3/older slots: animation tracks can still be
		# moved to their recorded checkpoint phase using the saved play clock.
		# Physics bodies cannot be reconstructed retroactively, so new recordings
		# use the exact snapshots above instead.
		_seek_legacy_level_animations(game.level, float(snapshot.get("play_time", 0.0)))
		return
	for entry in snapshot["moving_world_state"]:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("path"):
			continue
		var node := game.level.get_node_or_null(NodePath(str(entry["path"])))
		if node == null and game.level.loaded_level != null:
			# Saved paths include the level's display name. A copied/renamed
			# level has a different root but the same internal node paths.
			var saved_path: String = str(entry["path"])
			var root_end: int = saved_path.find("/")
			if root_end >= 0:
				node = game.level.loaded_level.get_node_or_null(NodePath(saved_path.substr(root_end + 1)))
		if node == null:
			continue
		if entry.get("kind", "") == "level_animation" and node.get_class() == "LevelNodeAnimation":
			node.transform = entry.get("transform", node.transform)
			node.get_parent().transform = entry.get("parent_transform", node.get_parent().transform)
		elif entry.get("kind", "") == "animation" and node is AnimationPlayer:
			var animation := node as AnimationPlayer
			animation.playback_speed = float(entry.get("speed", 1.0))
			var animation_name := str(entry.get("animation", ""))
			if not animation_name.empty():
				animation.play(animation_name)
				animation.seek(float(entry.get("position", 0.0)), true)
			if not bool(entry.get("playing", false)):
				animation.stop(false)
		elif node is Node2D:
			var moving := node as Node2D
			moving.position = entry.get("position", moving.position)
			moving.rotation = entry.get("rotation", moving.rotation)
			moving.scale = entry.get("scale", moving.scale)
			if entry.has("linear_velocity") and "linear_velocity" in moving:
				moving.set("linear_velocity", entry["linear_velocity"])
			if entry.has("angular_velocity") and "angular_velocity" in moving:
				moving.set("angular_velocity", entry["angular_velocity"])
			if entry.has("enabled") and "enabled" in moving:
				moving.set("enabled", entry["enabled"])


func _moving_phase_shift(game: WPGame) -> float:
	var identity: int = game.level.loaded_level.get_instance_id() if game.level.loaded_level != null else 0
	if int(game.level.get_meta("tas_phase_level", -1)) != identity:
		game.level.set_meta("tas_phase_level", identity)
		game.level.set_meta("tas_phase_shift", 0.0)
	return float(game.level.get_meta("tas_phase_shift", 0.0))


func _restore_native_world_phase(game: WPGame, recorded_time: float) -> void:
	if game.wp_game_data == null:
		return
	var shift: float = recorded_time - game.wp_game_data.play_time
	var previous_shift: float = _moving_phase_shift(game)
	game.level.set_meta("tas_phase_shift", shift)
	for level_node in game.level.animated_nodes:
		if not is_instance_valid(level_node) or level_node.animation == null or level_node.body == null:
			continue
		var animation = level_node.animation
		var data = animation.animation_data
		if not animation.has_meta("tas_original_offset"):
			animation.set_meta("tas_original_offset", float(data.offset) - previous_shift)
		var offset: float = float(animation.get_meta("tas_original_offset")) + shift
		if abs(float(data.offset) - offset) < 0.00001:
			continue
		var old_position: Vector2 = animation.position
		var old_rotation: float = animation.rotation
		data.offset = offset
		animation.seek(game.wp_game_data.play_time, 1.0 / 60.0, level_node.body, true)
		level_node.position += animation.position - old_position
		level_node.rotation += animation.rotation - old_rotation
		level_node.body.global_transform = level_node.global_transform


func _seek_legacy_level_animations(node: Node, recorded_time: float) -> void:
	if node is AnimationPlayer:
		var animation := node as AnimationPlayer
		var animation_name := animation.current_animation
		if not animation_name.empty() and animation.has_animation(animation_name):
			var resource := animation.get_animation(animation_name)
			var length := resource.length if resource != null else 0.0
			animation.seek((fposmod(recorded_time, length) if resource.loop else clamp(recorded_time, 0.0, length)) if length > 0.0 else 0.0, true)
	for child in node.get_children():
		_seek_legacy_level_animations(child, recorded_time)


func _restore_practice_ground_motion(p: WPPlayer, state: Dictionary) -> void:
	if state.has("ground_normal"):
		p.ground_normal = state["ground_normal"]
	if state.has("ground_tangent_speed"):
		p.ground_tangent_speed = float(state["ground_tangent_speed"])
	elif state.has("linear_velocity"):
		# Older slots (including Slot 3) stored world velocity but omitted the
		# native ground-speed accumulator. Reconstruct its tangential component
		# using the current contact normal; do not inherit the previous attempt.
		var normal: Vector2 = p.ground_normal
		if normal.length_squared() < 0.5:
			normal = Vector2.UP
		var tangent: Vector2 = Vector2(-normal.y, normal.x).normalized()
		p.ground_tangent_speed = state["linear_velocity"].dot(tangent)


func _restore_player(p: WPPlayer, snap: Dictionary) -> void:
	_restore_moving_world_state(snap)
	var visual_position_before_restore: Vector2 = p.position
	if snap.has("alive"):
		p.alive = snap["alive"]
	# REVERTED, per Divergence Diagnostics evidence: this used to disable the
	# physics body before repositioning it, then re-enable right after, as an
	# UNVERIFIED experiment aimed at "spawn on the edge of a block, land
	# standing in the middle of it" (theorized as Box2D resolving a marginal
	# teleport-induced overlap). It could never be tested against real Box2D
	# until now. With Diagnostic Logging on, two independent live-vs-replay
	# comparisons both showed the exact same reproducible ~1.5 unit downward
	# position shift starting 2-3 ticks after EVERY checkpoint restore
	# (identical live/replay starting position, identical inputs, position
	# alone drifting) -- i.e. the toggle was itself causing a small settle
	# on re-enable that the real game's own respawn_player() (WPGame.gd)
	# never exhibits, because it never disables the body at all: it sets
	# player.body.enabled = true once, unconditionally, with no OFF step
	# first. Removing the toggle and matching that exactly is what this now
	# does. If block-edge landings resurface, that theory wasn't wrong about
	# WHAT was happening, just about disable/re-enable being a safe way to
	# fix it -- re-run Diagnostic Logging to see whether this changed the
	# tick-2/3 divergence at all before trying another approach.
	var had_body: = p.body != null
	if snap.has("body_enabled"):
		p.body_enabled = snap["body_enabled"]
	if snap.has("position"):
		# Deliberately NOT also writing p.body.position here -- see the
		# TELEPORT ACCURACY note below. p.body is a CHILD node of p (see
		# nodes/WPPlayer.tscn: Box2DPhysicsBody is parented under WPPlayer,
		# at local position (0,0)), so p.body.position is a position LOCAL
		# to the player, not a world coordinate. Writing our captured
		# (world-space) position into it stacks a second full copy of that
		# offset on top of p.position, which is compounded again through
		# Box2D's own simulation -- exactly the "teleports / off by a lot"
		# symptom. The game's own respawn_player() (WPGame.gd) never
		# touches body.position either, only player.position -- this now
		# matches that exactly.
		p.position = snap["position"]
	if snap.has("linear_velocity"):
		p.linear_velocity = snap["linear_velocity"]
		if p.body != null:
			p.body.linear_velocity = snap["linear_velocity"]
	# INSTRUMENTATION for the horizontal-phantom-velocity finding (see the
	# 2026-08-30 divergence report: replay showed vel=(-13.27778, 15.000001)
	# on the very first compared tick after a restore whose OWN snapshot said
	# velocity was (0, 0), decaying smoothly over several following ticks --
	# not a one-tick glitch, a real leftover velocity riding along under
	# something we do AFTER zeroing it). p._reset_object() below is the one
	# remaining step in this function whose internals we don't control or
	# see (native/compiled, called only because the real respawn_player()
	# also calls it last -- see the TELEPORT ACCURACY note below). Snapshot
	# what linear_velocity actually reads immediately before and immediately
	# after that one call so Restore Drift Diagnostics can show, per restore,
	# whether _reset_object() itself is what's putting the phantom velocity
	# back -- if pre/post differ, that's the culprit, isolated to one call;
	# if they're identical (both already wrong, or both correctly zero),
	# whatever's happening is further downstream (this tick's
	# _sync_practice_playback_injected_input() call, or the engine's own
	# physics step) and this rules _reset_object() out instead.
	var velocity_before_reset_object: Vector2 = p.linear_velocity
	if had_body:
		# Set once, directly, now that position/velocity already hold the new
		# values -- no OFF step beforehand (see the note above). Falls back
		# to whatever the snapshot's own body_enabled said (matches the
		# pre-existing behavior when the snapshot explicitly wanted it
		# disabled) rather than unconditionally forcing it on.
		p.body.enabled = snap.get("body_enabled", true)
	if snap.has("dash_cooldown"):
		p.dash_cooldown = snap["dash_cooldown"]
	if snap.has("dash_timer"):
		p.dash_timer = snap["dash_timer"]
	if snap.has("coyote_timer"):
		p.coyote_timer = snap["coyote_timer"]
	if snap.has("squish_counter"):
		p.squish_counter = snap["squish_counter"]
	if snap.has("wallslide_counter"):
		p.wallslide_counter = snap["wallslide_counter"]
	if snap.has("wallslide_dir"):
		# wallslide_dir is wallslide_counter's own direction companion --
		# confirmed together in the real game's renderer (WPPlayerRenderer_Old.gd:
		# "if player.wallslide_counter: player_dir = -1 if player.wallslide_dir
		# else 1"). We were already restoring wallslide_counter (the "are we
		# wall-sliding" flag) but never this half of it, so a restored player
		# could come back flagged as wall-sliding against whichever wall it
		# happened to be touching a moment before -- not necessarily the one
		# the snapshot was actually taken against. Any velocity/friction the
		# wallslide logic applies would then push the wrong way, which reads
		# exactly like "a bit of velocity carries over" from before the death.
		p.wallslide_dir = snap["wallslide_dir"]
	if snap.has("stun_timer"):
		p.stun_timer = snap["stun_timer"]
	if snap.has("is_inside_one_way_platform"):
		p.is_inside_one_way_platform = snap["is_inside_one_way_platform"]
	if snap.has("dead_counter"):
		p.dead_counter = snap["dead_counter"]
	if snap.has("last_checkpoint"):
		p.last_checkpoint = snap["last_checkpoint"]
	if snap.has("last_checkpoint_anchor"):
		p.last_checkpoint_anchor = snap["last_checkpoint_anchor"]
	if snap.has("stick_to_ground_timer"):
		# stick_to_ground_timer is coyote_timer's grounded-side counterpart
		# (confirmed real and readable via WPPlayerAI.gd: "var is_on_ground: =
		# ai.player.stick_to_ground_timer > 0") -- it's what lets the game
		# treat the player as still grounded for a few ticks after actually
		# leaving the ground (e.g. running off a ledge or over a bump),
		# which affects whether ground-only movement/friction rules apply
		# that tick. We were already restoring coyote_timer but not this;
		# leaving it at whatever stale value it had going into the death
		# means a restored player can be treated as grounded (or not) based
		# on leftover state that has nothing to do with the snapshot -- another
		# way stale state can surface as unexpected velocity right after a
		# restore. Notably the game's OWN respawn_player() doesn't reset this
		# field either, but that's fine for a real respawn (a fresh, designed
		# spawn point) -- Macro Bot Mode restores to an arbitrary mid-run
		# position instead, where a mismatched grounded-state guess matters.
		p.stick_to_ground_timer = snap["stick_to_ground_timer"]
	if snap.has("facing_dir"):
		# facing_dir is real and gameplay-relevant, not cosmetic: it's the
		# fallback GameInput.gd's own dash-direction logic uses when a dash
		# is pressed with neither left nor right currently held ("elif not
		# local_player.facing_dir: dash_dir = local_player.facing_dir",
		# confirmed verbatim) -- and since THE FIFTEENTH-PASS FIX, Macro Bot
		# Mode's own playback dash goes through that exact same native
		# GameInput.gd logic itself (via a synthetic dash Input event), rather
		# than reproducing the fallback here as it used to. If a
		# checkpoint snapshot doesn't capture which way the player was
		# actually facing, a restore leaves facing_dir at whatever stale
		# value it happened to hold from BEFORE the restore -- e.g. still
		# "facing right" from earlier in the run even though the checkpoint
		# was taken mid-death facing left. Any no-direction-held dash
		# replayed right after that restore/boundary then fires backwards
		# relative to the original recording, which reads exactly like
		# "confuses itself" / a movement that doesn't match what was done.
		p.facing_dir = snap["facing_dir"]
	if snap.has("practice_playback_air_hold_ticks"):
		# See the matching comment in _snapshot_player(): restore the observed
		# native airborne-ramp phase captured during live play.
		_practice_playback_air_hold_ticks = snap["practice_playback_air_hold_ticks"]
	else:
		# Old on-disk macros predate this state. Zero is imperfect for a midair
		# checkpoint but deterministic; inheriting the unrelated live player's
		# current airborne time would make the same old macro vary run to run.
		_practice_playback_air_hold_ticks = 0
	if snap.has("practice_playback_air_hold_dir"):
		_practice_playback_air_hold_dir = snap["practice_playback_air_hold_dir"]
	else:
		_practice_playback_air_hold_dir = 0.0
	# snap["play_time"] is intentionally NOT written back. Goober Dash's
	# time-trial replay recorder timestamps native input against this global
	# clock; rewinding it at checkpoint boundaries created non-monotonic
	# uploaded replays (clock jumping 5 -> 7 -> 5, deaths followed by apparent
	# teleports, and occasional resets toward zero). A player checkpoint may
	# restore player state, but it must never rewrite the race/server clock.
	# TELEPORT ACCURACY: the game's own respawn_player() (WPGame.gd) always
	# finishes a reposition with player._reset_object() -- confirmed from
	# the real game's source, called as the very last step after every
	# other field is set, exactly like here. We don't know everything it
	# does internally (native/compiled), but skipping it meant every
	# checkpoint restore this tool ever did (Checkpoints load/edit, Macro
	# Bot Mode's auto-respawn, its segment-boundary resync, its Play Macro
	# restore-to-checkpoint-0) was reproducing an approximation of a real
	# respawn rather than the real thing -- almost certainly a source of
	# the visible teleport/position-off-by-a-lot glitches, on top of the
	# body.position bug fixed above. Calling it here brings every one of
	# those restores in line with the one and only way the game itself
	# ever legitimately teleports a live player mid-run.
	#
	# REVISED (2026-08-30) -- respawn_player() is NOT the only state a real
	# player sits in. The actual GooberDash source (level-start setup code,
	# WPGame.gd) shows every player getting parked at the start of a round
	# with `player.alive = false`, `player.body.enabled = false`, and
	# `player.dead_counter = <ticks until the hold ends>` -- exactly the
	# "wait a few seconds before you can move" hold, and it explains a
	# confirmed repro this session: a checkpoint placed mid-hold, at the
	# very start of a run, replayed with the player free-falling from tick
	# 0 while the live recording sat bit-for-bit frozen (position AND
	# velocity unchanged) for many ticks straight -- exactly what a
	# disabled (unsimulated) Box2D body looks like next to a freshly-
	# restored, simulated one. Searching the ENTIRE decompiled source turns
	# up exactly one call to _reset_object() anywhere, and it's this exact
	# line -- respawn_player()'s own, always preceded by re-enabling
	# everything (alive=true, body.enabled=true, dead_counter=0) first. The
	# real game never calls _reset_object() on a still-disabled player --
	# the level-start code that parks them there doesn't call it at all.
	# This function used to call it here unconditionally regardless, which
	# is a state transition the real game itself never performs. Since
	# body_enabled was already restored above (matching the checkpoint --
	# see the block near `had_body`), skipping _reset_object() whenever
	# that came back false matches the real game's own behavior exactly,
	# rather than guessing at what _reset_object() does to a body it was
	# never designed to be called on.
	#   (An earlier same-day attempt tried forcing the physics body to
	# SLEEP instead, theorizing the freeze was a Box2D sleep/wake artifact.
	# A Restore Drift Diagnostics report confirmed the forced-sleep write
	# genuinely stuck on this build -- read back immediately as applied --
	# yet the fall afterward was byte-for-byte identical to before the
	# attempt. That ruled sleep out cleanly: whatever drives gravity here
	# isn't gated on Box2D's own sleep flag, so that attempt was removed
	# rather than left in as dead weight now that the real mechanism is
	# confirmed from source instead of guessed at.
	var velocity_after_reset_object: Vector2 = velocity_before_reset_object
	# Deliberately reads the SAME snap.get("body_enabled", true) expression
	# used above to set p.body.enabled, not p.body_enabled directly -- a
	# snapshot that doesn't include "body_enabled" at all (an older/partial
	# checkpoint) leaves p.body_enabled un-touched (whatever it happened to
	# be from before this restore) while p.body.enabled still gets the
	# true fallback; keying off p.body_enabled here could read that stale
	# leftover value and wrongly skip _reset_object() on a body that was
	# just correctly (re-)enabled.
	var reset_object_called: bool = snap.get("body_enabled", true)
	if reset_object_called:
		p._reset_object()
		velocity_after_reset_object = p.linear_velocity
	# The native controller rebuilds grounded velocity from this accumulator
	# on its next tick. Resetting body/player velocity alone leaves it stale.
	_restore_practice_ground_motion(p, snap)
	# A deliberate checkpoint restore is not a stock zero-speed respawn.
	# Prevent either death guard from erasing its valid momentum one tick later.
	_freeze_prev_alive = p.alive
	_freeze_last_alive_position = p.position
	_post_guard_player_id = p.get_instance_id()
	_post_guard_prev_alive = p.alive
	_post_guard_saw_gameplay_death = false
	_post_guard_probe_ticks_left = 0
	_post_guard_last_accepted_position = p.position
	_post_guard_last_accepted_vx = p.linear_velocity.x
	_arm_restore_drift_watch(p, snap, velocity_before_reset_object, velocity_after_reset_object, reset_object_called) # no-op unless Restore Drift Diagnostics is toggled on -- see that function for what/why
	_reset_renderer_smoothing(p)
	_snap_playback_visual_track(p)
	_begin_visual_seam_blend(visual_position_before_restore, p.position)
	# Keep the legacy diagnostic fingerprints scoped to the current restore
	# boundary. Global clock fields are no longer written anywhere in this
	# restore; they remain observation-only metadata (see the comment above).
	_live_tick_last_play_time = -1.0
	# THE TWENTY-THIRD-PASS FIX (2026-08-31, later) -- corrects THE TWENTY-
	# SECOND-PASS FIX's own choke-point reset, which used the same -1.0
	# sentinel as the line above and turned out to reopen the exact bug it
	# was fixing: a real report showed the tick-1 frozen-duplicate symptom
	# STILL happening even with that pass's phantom-call check active (3
	# OTHER phantom calls elsewhere in the same run WERE correctly caught,
	# proving the check itself works) -- because -1.0 means "no usable
	# baseline, process unconditionally," and a catch-up-burst call that
	# lands IMMEDIATELY after a checkpoint-0/boundary restore -- zero real
	# ticks elapsed since play_time was just rewound -- got treated as
	# automatically valid instead of being fingerprinted at all. Unlike the
	# live-recording baseline above (which genuinely can't know what play_
	# time to expect next, since a restore there can happen from a
	# completely different, asynchronous call site relative to recording's
	# own capture cadence), a playback-side restore ALWAYS happens INSIDE
	# this exact function -- so the true next-expected baseline is knowable
	# immediately: whatever play_time reads right now, at the end of this
	# same restore. Storing that instead of -1.0 means the very next call,
	# even one from the same catch-up burst with zero real ticks elapsed,
	# compares against a real, correct value and gets caught as phantom
	# exactly like any other -- closing the gap instead of only narrowing
	# it.
	var g_for_playback_baseline: = _find_game()
	if g_for_playback_baseline != null and g_for_playback_baseline.wp_game_data != null and ("play_time" in g_for_playback_baseline.wp_game_data):
		_playback_tick_last_play_time = g_for_playback_baseline.wp_game_data.play_time
	else:
		_playback_tick_last_play_time = -1.0


# THE EVIDENCE: Divergence Diagnostics (two independent, fully-covered
# live-vs-replay comparisons) showed a reproducible ~1.5 unit downward
# position drift starting 2-3 ticks after EVERY checkpoint restore, with
# inputs matching exactly and the starting position identical -- i.e. not a
# Macro Bot Mode bug, but Box2D itself settling after a hard teleport. A
# body arriving at a resting position via continuous simulation carries
# resolved contact/manifold state into that rest; a body arriving via a hard
# `position =` assignment (a teleport, which is what every restore here is)
# does not, and can visibly fall/settle for a couple of physics ticks before
# new ground contact re-establishes.
# THE IDEA: when checkpoint 0 was ALREADY at rest (near-zero velocity,
# grounded), hold the replayed input at zero for a few ticks before playback
# visibly begins, giving Box2D room to establish contact before frame 0.
# This is deliberately startup-only. It previously ran at every internal
# stitch boundary, where it inserted a neutral physics tick, visibly paused
# the macro, and let the body move before the next recorded frame. The
# authoritative per-frame state path now handles internal boundary accuracy
# without adding any unrecorded time.
# THE GUARD (read this before touching either function below): the FIRST
# version of this shipped with an infinite-loop bug -- arming settling
# unconditionally on every boundary restore, with no way to tell "just
# armed this boundary" apart from "already finished settling this boundary
# and now revisiting the same unmoved _practice_playback_index" -- so once
# settling ended, the very next tick recomputed the SAME boundary_idx
# (nothing had advanced it) and re-armed forever. A first patch only guarded
# the case where that boundary was also the LAST one, which missed every
# mid-macro checkpoint -- any at-rest checkpoint anywhere but the very end
# still looped forever, which is what actually reached the user as a
# real crash (34000+ nodes). The fix is `_practice_playback_settled_boundary`
# at the call site in _advance_practice_playback(). Settling is now only
# armed for checkpoint 0 and remains hard-capped, so it cannot re-arm at an
# internal boundary or reveal a stitch with a pause.
func _snapshot_is_at_rest(snap: Dictionary) -> bool:
	var v: Vector2 = snap.get("linear_velocity", Vector2.ZERO)
	if v.length() >= PLAYBACK_SETTLE_VELOCITY_EPSILON:
		return false
	return snap.get("stick_to_ground_timer", 0.0) > 0.0


func _on_place_practice_checkpoint_pressed() -> void:
	if not _practice_active:
		_log_action("Macro Bot Mode is off -- press Start Macro Bot Mode first", null)
		return
	# THE FIX (2026-08-30, fourth pass): same idle-frame-vs-physics-tick gap
	# as _on_toggle_practice_pressed() and _on_play_practice_macro_pressed()
	# -- see the big comment on the first of those for the full story
	# (a divergence report caught this exact class of bug: an idle-frame
	# readiness check/snapshot disagreeing with what the very next physics
	# tick actually goes on to record). This button is just as much an
	# idle-frame Button "pressed" handler as that one, and every checkpoint
	# it places is exactly as replay-sensitive as checkpoint 0 -- there's no
	# reason this one gets to keep reading player state from the wrong
	# frame just because it wasn't the checkpoint the first report happened
	# to catch. Don't check readiness or snapshot anything here; arm a
	# pending flag and let _watch_practice_place_request() -- called from
	# _physics_process(), every physics tick -- do it on solid footing
	# instead. In the overwhelmingly common case (you're actively playing
	# when you press this) it fires on the very next physics tick,
	# imperceptibly; if you happen to press it while dead or mid-hold, it
	# just waits, tick by tick, for the same readiness _start_practice_mode()
	# already requires of checkpoint 0, instead of failing and making you
	# press it again.
	_practice_place_pending = true
	_refresh_practice_ui()


func _watch_practice_place_request() -> void:
	if not _practice_place_pending:
		_practice_place_ready_stable_ticks = 0
		return
	if not _practice_active:
		# Stopped (or Start/Stop toggled off) while a placement was still
		# pending -- nothing sensible left to commit it against.
		_practice_place_pending = false
		_practice_place_ready_stable_ticks = 0
		return
	var player: = _get_local_player()
	if player == null:
		_practice_place_ready_stable_ticks = 0
		return # keep waiting -- no player to check or snapshot yet
	if not _player_ready_for_checkpoint(player):
		_practice_place_ready_stable_ticks = 0 # see THE SEVENTH-PASS FIX on _watch_practice_start_request()
		return # keep waiting, tick by tick -- see the big comment on _on_place_practice_checkpoint_pressed()
	_practice_place_ready_stable_ticks += 1
	if _practice_place_ready_stable_ticks < PRACTICE_READY_STABLE_TICKS_REQUIRED:
		return # looked ready this tick, but not for long enough yet -- see THE SEVENTH-PASS FIX on _watch_practice_start_request()
	_practice_place_ready_stable_ticks = 0
	_practice_place_pending = false
	_practice_segments.append(_practice_current_segment.duplicate())
	_diag_live_committed.append(_diag_live_current.duplicate()) # kept in lockstep with _practice_segments -- see _capture_diag_entry()
	var idx: = _practice_checkpoints.size()
	var snap: = _snapshot_player(player)
	_practice_checkpoints.append(snap)
	_practice_markers.append(_spawn_checkpoint_marker(player, snap["position"]))
	_restyle_practice_markers()
	var seg_len: int = _practice_segments.back().size()
	_practice_current_segment = []
	_diag_live_current = []
	_practice_deaths_this_segment = 0
	_log_action("Macro Bot Mode: checkpoint %d placed (segment: %d frame(s))" % [idx, seg_len], null)
	_refresh_practice_ui()


func _on_undo_practice_checkpoint_pressed() -> void:
	if _practice_checkpoints.size() <= 1:
		_log_action("Macro Bot Mode: no placed checkpoints to undo (only the start point remains)", null)
		return
	_practice_checkpoints.pop_back()
	_practice_segments.pop_back()
	if not _diag_live_committed.empty():
		_diag_live_committed.pop_back()
	var m = _practice_markers.pop_back()
	if is_instance_valid(m):
		m.queue_free()
	_restyle_practice_markers()
	_practice_current_segment.clear()
	_diag_live_current.clear()
	_practice_deaths_this_segment = 0
	var player: = _get_local_player()
	if player != null:
		_restore_player(player, _practice_checkpoints.back())
	_log_action("Macro Bot Mode: undid last checkpoint (%d remaining)" % [_practice_checkpoints.size() - 1], null)
	_refresh_practice_ui()


func _on_toggle_practice_auto_respawn_pressed() -> void:
	_practice_auto_respawn = not _practice_auto_respawn
	_style_button(_practice_auto_respawn_button, COLOR_PINK if _practice_auto_respawn else COLOR_BLUE)
	_practice_auto_respawn_button.text = "⟲ Auto-Respawn to Checkpoint: ON" if _practice_auto_respawn else "⟲ Auto-Respawn to Checkpoint: OFF"
	_log_action("Macro Bot Mode: Auto-Respawn to Checkpoint %s" % ("ON" if _practice_auto_respawn else "OFF"), null)


func _spawn_checkpoint_marker(player: WPPlayer, pos: Vector2) -> Node2D:
	var parent: = player.get_parent()
	if parent == null:
		return null
	var marker: = CheckpointMarker.new()
	marker.position = pos
	marker.visible = not _overlay_hidden
	parent.add_child(marker)
	return marker
