extends Reference

# JourneyPages: shared state (variables, constants, signals, inner classes), in the original order.
const ModPaths = preload("user://mod/core/ModPaths.gd")

# Journey sections and detail views. Everything renders JourneyModel data;
# a null system renders its explicit "not connected" state.
const QUEST_COLORS = {"Public Matches": Color("7fb4ff"), "Speedrunning": Color("ffb86b"), "Level Creation": Color("5ee0c8"), "Optional Challenges": Color("ff7ed3")}
const DIFFICULTY = {"easy": ["EASY", Color("8af0b4")], "medium": ["MEDIUM", Color("ffd84d")], "hard": ["HARD", Color("ff8fa3")], "expert": ["EXPERT", Color("c9a0ff")]}
const MAP_TINTS = ["2f7fe0", "1f9d8b", "d46a2b", "8b4de0", "c9304f", "2aa35a", "d1a21a", "3a5bd6"]

var screen
var ui
# XP for each map objective (claimed once per map).
const MAP_XP = {"discover": 200, "finish": 300, "first": 500, "pb": 400}
var quest_filter = "All"
var choose_shown = true
var map_query = ""
var map_filter = "all"
var map_sort = "name"
var map_grid = null
var map_catalog = null
var xp_backfill = null
var xp_plan = null
var achievement_filter = "all"
var reward_tab = "themes"
var activity_range = "week"
var calendar_week = 0
var selected_rank = -1
var king_shift = 0
var record_query = ""
var record_list = null
var expanded = {}

# Map thumbnail: the screenshot fills the whole area (scaled to cover, never
# stretched) with the map name in the bottom left over a soft shade.
# Screenshots live in journey-assets/map_<name>.png. top_only rounds only the
# top corners, for a thumbnail that sits flush at the top of a card.
const THUMB_SHADER = """
shader_type canvas_item;
uniform sampler2D shot;
uniform bool has_shot = false;
uniform vec4 tint : hint_color = vec4(0.2, 0.5, 0.9, 1.0);
uniform vec2 box = vec2(1.0);
uniform vec2 shot_size = vec2(1.0);
uniform float radius = 0.0;
uniform bool top_only = false;
uniform float shade = 0.85;
void fragment() {
	vec3 c;
	if (has_shot) {
		float s = max(box.x / shot_size.x, box.y / shot_size.y);
		vec2 shown = box / s;
		vec2 uv = ((shot_size - shown) * 0.5 + UV * shown) / shot_size;
		c = texture(shot, uv).rgb;
	} else {
		c = mix(tint.rgb * 1.15, tint.rgb * 0.7, UV.x * 0.5 + UV.y * 0.5);
	}
	float g = smoothstep(0.3, 1.0, UV.y);
	c = mix(c, vec3(0.0, 0.07, 0.16), g * g * shade);
	vec2 p = UV * box;
	vec2 d = min(p, box - p);
	float a = 1.0;
	if (d.x < radius && d.y < radius && !(top_only && p.y > box.y * 0.5)) {
		a = clamp(radius - length(vec2(radius) - d) + 0.5, 0.0, 1.0);
	}
	COLOR = vec4(c, a);
}
"""
var _thumb_shader = null

static func map_key(name) -> String:
	var key = "map_"
	for c in str(name).to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			key += c
		elif not key.ends_with("_"):
			key += "_"
	return key.rstrip("_").substr(0, 48)

# ================================================================== achievements
const COLLECTIONS = [
	["exploration", "Map Explorer", "Discover eligible public maps."],
	["crown", "Crown Collector", "Win public matches overall."],
	["podium", "Placement Fanatic", "Exceptional results for each match size."],
	["clock", "Against the Clock", "Verified personal bests and world records."],
	["builder", "Goob Builder", "Publish eligible levels."],
	["conqueror", "Map Conqueror", "Finish first on eligible public maps."],
	["streak", "Win Streak", "Win public matches in a row."],
]

class FinishPreview extends Control:
	const RUN = 1.8
	const SHOW = 10.0
	const COUNT = 5.0
	const FADE = 1.3
	var base = ""
	var finish = {}
	var skin = {}
	var big
	var small
	var world
	var top
	var runner = null
	var player = null
	var phase = "idle"
	var clock = 0.0
	var U = 100.0
	var shade = 0.0
	var banner = 0.0
	var line_x = 0.0
	func setup(base_dir, data, look, height, font_big, font_small):
		base = base_dir
		finish = data
		skin = look
		big = font_big
		small = font_small
		rect_min_size = Vector2(0, height)
		rect_clip_content = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		world = Node2D.new()
		add_child(world)
		top = Control.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		add_child(top)
		top.connect("draw", self, "_draw_top")
	func _ground():
		return rect_size.y * 0.86
	func restart(_arg = null):
		if player != null and is_instance_valid(player):
			player.queue_free()
		player = null
		var choreo = load(ModPaths.path(str(finish.script))).new()
		U = rect_size.y / (choreo.preview_units() if choreo.has_method("preview_units") else 5.2)
		line_x = rect_size.x * 0.42
		if runner == null:
			runner = load(ModPaths.path("JourneyFinishPuppet.gd")).new()
			runner.skin = skin.duplicate(true)
			runner.size = U
			world.add_child(runner)
		runner.visible = true
		phase = "run"
		clock = 0.0
		shade = 0.0
		banner = 0.0
	func skip(_arg = null):
		if phase == "loop":
			_countdown()
	func _process(delta):
		if phase == "idle":
			if rect_size.y > 20 and is_visible_in_tree():
				restart()
			return
		delta = min(delta, 0.1)
		clock += delta
		banner = max(0.0, banner - delta * 0.7)
		var anchor = Vector2(rect_size.x * 0.54, _ground())
		match phase:
			"run":
				# Runs in from the left, crosses the line, slows to a stop.
				var u = clamp(clock / RUN, 0.0, 1.0)
				var x0 = -0.1 * rect_size.x
				var x = x0 + (anchor.x - x0) * (1.0 - pow(1.0 - u, 2.2))
				if runner.position.x < line_x and x >= line_x:
					banner = 1.0
				runner.clear_pose()
				runner.position = Vector2(x, anchor.y)
				runner.facing = 1.0
				runner.anim = "Run" if u < 0.8 else "Idle"
				runner.lean = -10.0 * max(0.0, (u - 0.75) / 0.25) * (1.0 - u) * 4.0
				runner.step(delta)
				if clock >= RUN:
					_start(anchor)
			"loop":
				if clock >= SHOW:
					_countdown()
			"count":
				var left = COUNT - clock
				shade = clamp((FADE - left) / 0.7, 0.0, 1.0)
				if left <= 0.0:
					phase = "dark"
					clock = 0.0
			"dark":
				# Level reloads behind the fade, then it starts over.
				if clock > 0.5:
					if player != null and is_instance_valid(player):
						player.queue_free()
					player = null
					runner.visible = false
				shade = 1.0 if clock < 0.7 else clamp(1.0 - (clock - 0.7) / 0.5, 0.0, 1.0)
				if clock >= 1.6:
					restart()
		if runner != null and runner.visible and phase != "run":
			runner.clear_pose()
			runner.anim = "Idle"
			runner.step(delta)
		top.update()
	func _start(anchor):
		runner.visible = false
		player = load(ModPaths.path("JourneyFinishPlayer.gd")).new()
		player.position = anchor
		world.add_child(player)
		player.setup(load(ModPaths.path(str(finish.script))).new(), skin, U)
		player.connect("finished", self, "_done")
		phase = "loop"
		clock = 0.0
	func _countdown():
		phase = "count"
		clock = 0.0
		if player != null and is_instance_valid(player):
			player.request_outro(COUNT - FADE)
	func _done():
		if player == null or not is_instance_valid(player):
			return
		if player.keep_hidden_after():
			player.visible = false
		else:
			player.queue_free()
			player = null
			runner.position = Vector2(rect_size.x * 0.54, _ground())
			runner.visible = true
	func _notification(what):
		if what == NOTIFICATION_RESIZED:
			update()
	func _draw():
		var w = rect_size.x
		var h = rect_size.y
		var g = _ground()
		for i in range(10):
			var k = float(i) / 10.0
			draw_rect(Rect2(0, g * k, w, g / 10.0 + 1), Color("3d8fe8").linear_interpolate(Color("9ad6ff"), k))
		for c in [[0.12, 0.18, 1.0], [0.7, 0.12, 0.8], [0.88, 0.3, 0.6]]:
			var p = Vector2(w * c[0], h * c[1])
			var r = h * 0.05 * c[2]
			for o in [Vector2(-1.2, 0.2), Vector2(0, 0), Vector2(1.2, 0.2)]:
				draw_circle(p + o * r, r, Color(1, 1, 1, 0.85))
		# Ground with a grass edge and a raised block on the left.
		draw_rect(Rect2(0, g, w, h - g), Color("c98a4b"))
		draw_rect(Rect2(0, g, w, h * 0.03), Color("5cc24a"))
		var block = Rect2(w * 0.1, g - h * 0.12, w * 0.12, h * 0.12)
		draw_rect(block, Color("c98a4b"))
		draw_rect(Rect2(block.position, Vector2(block.size.x, h * 0.03)), Color("5cc24a"))
		# Finish line: checkered post and flag.
		var x = w * 0.42
		var cell = h * 0.035
		var rows = int(h * 0.42 / cell)
		for i in range(rows):
			for j in range(2):
				var col = Color.white if (i + j) % 2 == 0 else Color("1b2346")
				draw_rect(Rect2(x - cell + j * cell, g - (i + 1) * cell, cell, cell), col)
		var top_y = g - rows * cell
		draw_rect(Rect2(x - cell - 3, top_y - 3, cell * 2 + 6, rows * cell + 3), Color("1b2346"), false, 3.0)
		var flag = PoolVector2Array([Vector2(x + cell, top_y), Vector2(x + cell + h * 0.12, top_y + h * 0.04), Vector2(x + cell, top_y + h * 0.08)])
		draw_colored_polygon(flag, Color("ff5ca8"))
	func _draw_top():
		var w = rect_size.x
		if banner > 0.0:
			var text = "Qualified!"
			var size = big.get_string_size(text)
			top.draw_string(big, Vector2((w - size.x) * 0.5, rect_size.y * 0.18), text, Color(1, 0.86, 0.3, min(1.0, banner * 2.0)))
		if phase == "count":
			var left = int(ceil(max(0.0, COUNT - clock)))
			var text = "Next round in %d" % left
			var size = small.get_string_size(text)
			top.draw_string(small, Vector2((w - size.x) * 0.5, rect_size.y * 0.12), text, Color.white)
		if shade > 0.0:
			top.draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.04, 0.08, 0.2, shade))

# A small sky stage that runs a finish animation on a loop. Uses the game's
# Goober rig when the Spine runtime is there (in the game).
class FinishStage extends Control:
	var base = ""
	var finish = {}
	var skin = {}
	var player = null
	var wait = -1.0
	func setup(base_dir, data, look, height):
		base = base_dir
		finish = data
		skin = look
		rect_min_size = Vector2(0, height)
		rect_clip_content = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta):
		if wait >= 0.0:
			wait -= delta
			if wait < 0.0:
				_spawn()
		elif player == null and rect_size.y > 20 and is_visible_in_tree():
			_spawn()
	func _spawn():
		if player != null and is_instance_valid(player):
			player.queue_free()
		player = load(ModPaths.path("JourneyFinishPlayer.gd")).new()
		player.position = Vector2(rect_size.x * 0.5, rect_size.y * 0.9)
		add_child(player)
		move_child(player, 0)
		var choreo = load(ModPaths.path(str(finish.script))).new()
		var units = choreo.preview_units() if choreo.has_method("preview_units") else 5.2
		player.setup(choreo, skin, rect_size.y / (units * 0.92))
		player.connect("finished", self, "_done")
	func ending(_arg = null):
		if player != null and is_instance_valid(player):
			player.request_outro(player.choreo.outro_length())
	func _done():
		wait = 0.9
	func _draw():
		var h = rect_size.y
		for i in range(8):
			var k = float(i) / 8.0
			draw_rect(Rect2(0, h * 0.9 * k, rect_size.x, h * 0.9 / 8.0 + 1), Color("3d8fe8").linear_interpolate(Color("8fd0ff"), k))
		draw_rect(Rect2(0, h * 0.9, rect_size.x, h * 0.1), Color("f0c27a"))
		draw_rect(Rect2(0, h * 0.9, rect_size.x, 4), Color("d9a55e"))
	func _notification(what):
		if what == NOTIFICATION_RESIZED:
			update()
			if player != null and is_instance_valid(player) and rect_size.y > 20:
				player.position = Vector2(rect_size.x * 0.5, rect_size.y * 0.9)

var open_day = -1

class ValueSort:
	var values = {}
	func desc(a, b) -> bool:
		return int(values[a]) > int(values[b])

# 24-hour bar for one day: a block per round, ticks every 6 hours.
class DayStrip extends Control:
	var day_start = 0
	var rounds = []
	var font
	var colors = []
	func _draw():
		var w = rect_size.x
		draw_rect(Rect2(0, 0, w, 22), colors[0])
		for r in rounds:
			var a = clamp(float(int(r.date) - day_start) / 86400.0, 0.0, 1.0)
			var b = clamp((float(int(r.date) - day_start) + float(r.play_seconds)) / 86400.0, 0.0, 1.0)
			var c = colors[2] if bool(r.win) or int(r.placement) == 1 else colors[1]
			draw_rect(Rect2(a * w, 0, max(3.0, (b - a) * w), 22), c)
		var names = ["12 AM", "6 AM", "12 PM", "6 PM", "12 AM"]
		for i in 5:
			var x = clamp(w * i / 4.0, 1.0, w - 1.0)
			draw_line(Vector2(x, 22), Vector2(x, 28), colors[3], 2)
			if font != null:
				var tw = font.get_string_size(names[i]).x
				draw_string(font, Vector2(clamp(x - tw * 0.5, 0.0, w - tw), 48), names[i], colors[3])
	func _notification(what):
		if what == NOTIFICATION_RESIZED:
			update()
# Achievement details reuse the existing slide-in overlay and design components.
static func bonus_group(key):
	if key.begins_with("wins_") or key == "first_sweep":
		return "crown"
	if key.begins_with("maps_"):
		return "exploration"
	if key.begins_with("active_"):
		return "activity"
	return ""

static func bonus_target(key):
	var group = bonus_group(key)
	if group == "activity":
		return {"section":"Career","view":""}
	if not group.empty():
		return {"view":"achievement","key":group}
	if key.begins_with("league_"):
		return {"view":"roadmap"}
	return {"section":"Achievements","view":""}
