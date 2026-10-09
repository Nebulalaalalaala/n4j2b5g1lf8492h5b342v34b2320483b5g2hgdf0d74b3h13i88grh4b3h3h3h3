extends Reference
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Local TAS options and bounded checkpoint-join observations. Never writes a
# macro, changes a race clock, adds a physics tick, or changes native input.
const PAUSE_SETTING = "tas_pause_on_checkpoint"
const SPEED_SETTING = "tas_final_playback_normal_speed"
const EDITED_KEY = "__tas_input_unverified"
const STATE_KEY = "__tas_recorded_state"
const DETAIL_LIMIT = 8
const POSITION_TOLERANCE = 0.05
const VELOCITY_TOLERANCE = 0.05
var pause_on_checkpoint = false
var normal_playback = true
var checkpoint_queued = false
var checkpoint_deferred = false
var retry_queued = false
var retry_deferred = false
var transport = null
var native_step_remaining = 0
var native_clock = null
var pause_boundary = null
var targets = {}
var observations = {}
var details = []
var completed = false
var pause_button = null
var speed_button = null

func load_options() -> void:
	if native_clock == null:
		native_clock = load(ModPaths.path("TASNativeTickClock.gd")).new()
	if transport == null:
		transport = load(ModPaths.path("TASLiveTransport.gd")).new()
	if pause_boundary == null:
		pause_boundary = load(ModPaths.path("TASPauseBoundary.gd")).new()
	pause_on_checkpoint = bool(SavedSettings.get_value(PAUSE_SETTING, false))
	normal_playback = bool(SavedSettings.get_value(SPEED_SETTING, true))

func set_pause(value: bool) -> void:
	pause_on_checkpoint = value
	SavedSettings.set_value(PAUSE_SETTING, value)

func set_normal_speed(value: bool) -> void:
	normal_playback = value
	SavedSettings.set_value(SPEED_SETTING, value)

func playback_speed(frame: Dictionary) -> float:
	if normal_playback:
		return 1.0
	var state = frame.get(STATE_KEY, {})
	return clamp(float(state.get("tas_playback_speed", 1.0)), 0.05, 4.0) if state is Dictionary else 1.0

static func needs_resimulation(segments: Array) -> bool:
	for segment in segments:
		for frame in segment:
			if bool(frame.get(EDITED_KEY, false)):
				return true
	return false

func begin_join_check(boundaries: Array, frame_count: int) -> void:
	targets.clear()
	observations.clear()
	details.clear()
	completed = false
	for frame in boundaries:
		if int(frame) > 0 and int(frame) < frame_count:
			targets[int(frame)] = true

func observe_join(frame_index: int, expected, actual: Dictionary) -> void:
	if not targets.has(frame_index) or observations.has(frame_index):
		return
	var result = "unverified"
	var fields = []
	if expected is Dictionary and expected.get("position") is Vector2 and expected.get("linear_velocity") is Vector2:
		result = "clean"
		if not actual.get("position") is Vector2:
			result = "unverified"
			fields.append("missing position")
		elif actual.position.distance_to(expected.position) > POSITION_TOLERANCE:
			fields.append("position")
		if not actual.get("linear_velocity") is Vector2:
			result = "unverified"
			fields.append("missing velocity")
		elif actual.linear_velocity.distance_to(expected.linear_velocity) > VELOCITY_TOLERANCE:
			fields.append("velocity")
		# Absolute play/state clocks intentionally are NOT rewound or compared.
		for field in ["alive", "body_enabled", "dash_timer", "dash_cooldown", "coyote_timer", "jump_timer", "jumphold_timer", "fresh_jump_timer", "stun_timer", "stick_to_ground_timer", "ground_normal", "ground_tangent_speed", "facing_dir", "practice_playback_air_hold_ticks", "practice_playback_air_hold_dir"]:
			if not expected.has(field): continue
			if not actual.has(field):
				result = "unverified"
				fields.append("missing " + field)
			elif typeof(expected[field]) == TYPE_REAL and typeof(actual[field]) == TYPE_REAL:
				if abs(expected[field] - actual[field]) > 0.0001: fields.append(field)
			elif expected[field] != actual[field]:
				fields.append(field)
		if not fields.empty() and result != "unverified":
			result = "correction required"
	observations[frame_index] = result
	if result != "clean" and details.size() < DETAIL_LIMIT:
		details.append("Frame %d: %s%s" % [frame_index, result, " (" + PoolStringArray(fields).join(", ") + ")" if not fields.empty() else ""])

func join_summary() -> String:
	if targets.empty():
		return "No internal checkpoint joins in the last playback."
	var clean = 0
	var corrected = 0
	var unknown = targets.size() - observations.size()
	for result in observations.values():
		if result == "clean": clean += 1
		elif result == "correction required": corrected += 1
		else: unknown += 1
	return "Joins: %d clean · %d need correction · %d unverified%s" % [clean, corrected, unknown, " (incomplete playback)" if not completed else ""]

func join_report() -> String:
	var report = join_summary()
	for detail in details:
		report += "\n" + detail
	return report + "\n\nChecked before checkpoint/state restoration. Clean joins are not whole-run input-only verification. Missing or unobserved states are never marked accurate."

func build_controls(owner, parent: VBoxContainer) -> void:
	# Use the existing Tools button kit for every visual state. Native
	# CheckBox defaults inherit GooberDash's white strip skin in this menu.
	var options_row = HBoxContainer.new()
	options_row.add_constant_override("separation", 10)
	parent.add_child(options_row)
	for entry in [["Checkpoint pause", pause_on_checkpoint, "set_pause", "Off by default. Pauses after the native tick finishes; keeps velocity and recorded input intact."], ["Final playback at 1×", normal_playback, "set_normal_speed", "On by default. Replays every recorded native tick at normal speed. Turn off to inspect at the recorded slow-motion speed."]]:
		var button = owner._make_button("", owner.COLOR_BLUE, 0)
		button.toggle_mode = true
		button.set_pressed_no_signal(entry[1])
		button.align = Button.ALIGN_CENTER
		button.hint_tooltip = entry[3] + (" Placement only: death retries always restore and pause at the checkpoint." if entry[2] == "set_pause" else "")
		_refresh_option_button(owner, button, entry[0], entry[1])
		button.connect("toggled", self, "_on_option_toggled", [owner, button, entry[0], entry[2]])
		options_row.add_child(button)
		if entry[2] == "set_pause": pause_button = button
		else: speed_button = button
	var review = owner._make_button("Last checkpoint join check", owner.COLOR_BLUE, 280)
	review.align = Button.ALIGN_CENTER
	# Godot 3: clearing SIZE_FILL keeps the minimum-width button at the left.
	review.size_flags_horizontal = 0
	review.hint_tooltip = "Reviews joins from the last playback without inserting pauses or changing its inputs."
	review.connect("pressed", self, "show_join_report", [owner])
	parent.add_child(review)
	transport.build_controls(owner, parent)

func _refresh_option_button(owner, button: Button, title: String, value: bool) -> void:
	button.text = "%s: %s" % [title, "ON" if value else "OFF"]
	owner._style_button(button, owner.COLOR_PINK if value else owner.COLOR_BLUE)

func _on_option_toggled(value: bool, owner, button: Button, title: String, setter: String) -> void:
	call(setter, value)
	_refresh_option_button(owner, button, title, value)

func show_join_report(owner) -> void:
	owner._show_responsive_popup("CHECKPOINT JOINS", join_report())
