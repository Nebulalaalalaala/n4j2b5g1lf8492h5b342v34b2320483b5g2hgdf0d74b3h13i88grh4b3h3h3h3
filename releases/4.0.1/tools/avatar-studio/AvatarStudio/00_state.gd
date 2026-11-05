extends Node

# AvatarStudio: shared state (variables, constants, signals, inner classes), in the original order.

const ModPaths = preload("user://mod/core/ModPaths.gd")
const CustomCosmetics = preload("user://mod/shared/scripts/CustomCosmetics.gd")
const StudioEffects = preload("user://mod/shared/scripts/StudioEffects.gd")
const StudioSecrets = preload("user://mod/shared/scripts/StudioSecrets.gd")
const TextureLibrary = preload("user://mod/tools/avatar-studio/StudioTextureLibrary.gd")
const ItemHues = preload("user://mod/shared/scripts/ItemHues.gd")

# Local editor layered over the existing renderer/catalog. No profile RPCs.
const DATA_PATH = ModPaths.AVATAR_STUDIO_DATA
const GoobStyle = preload("user://mod/shared/scripts/GoobStyle.gd")
const TEXTURE_DIR = ModPaths.AVATAR_STUDIO_TEXTURES
const BG = Color("14162d")
const PANEL = Color("1a1d38")
const LINE = Color("2c2f55")
const TEXT = Color("f5f3ff")
const DIM = Color("b8b7d6")
const ACCENT = Color("a68bff") # Avatar Studio uses the Create colour from the Workspace menu
const CATEGORIES = [["color", "Goober"], ["hat", "Hats"], ["suit", "Bodies"], ["hand", "Weapons"], ["effect", "Effects"], ["emote", "Emotes"]]
const PAGE_SIZE = 12
const DEV_MATCH = "user://goobplayability-dev/studio-match/StudioMatch.gd"   # dev machine only, outside the mod folder, never shipped
var sandbox
var tool_ref
var stage: Control
var rotation_picker
var rotation_favorites
var theme_picker
var goober
var section_tabs: TabContainer
var customize: VBoxContainer
var looks_page: VBoxContainer
var preview_page: VBoxContainer
var catalog_grid: GridContainer
var _catalog_dirty = true
var _looks_dirty = true
var search: LineEdit
var status: Label
var summary: Label
var paging: Label
var inspector: Label
var color_controls: VBoxContainer
var texture_controls: VBoxContainer
var texture_count_label: Label
var goober_tabs: HBoxContainer
var picker: ColorPickerButton
var look_name: LineEdit
var looks_grid: GridContainer
var color_palette: HBoxContainer
var section_buttons = []
var category_buttons = {}
var history = []
var future = []
var working = {}
var session_start = {}
var library = {"version": 1, "looks": [], "favorites": [], "recent": [], "colors": [], "textures": []}
var current_look = ""
var current_texture = "default"
var category = "color"
var browser_mode = "All"
var page_index = 0
var texture_mode = false
var effects_mode = false
var effect_color: ColorPickerButton
var effect_settings = {"dash": "default", "trail": "default", "color": "9dd6bd"}
var effect_controls: VBoxContainer
var effect_menu: PopupMenu
var effect_menu_id = ""
var effect_picker: PopupPanel
var category_actions: HBoxContainer
var effect_preview = null
var importing = false
var restoring = false
var refreshing = false
var compact_grid = false   # more, smaller item cards (saved in SavedSettings)
var compact_button: Button
var selected_emote = ""
var selected_item = ""
var avatar_size = 1.0
var size_control: SpinBox
var animation = "Idle"
var animation_paused = false
var animation_loop = true
var zoom = 1.0
var zoom_control: SpinBox
var window_user_sized = false
var embedded = false       # opened from the Customize chooser: fills the home page area
var chooser = null
var fit_button: Button
var title_label: Label
var facing = -1.0
var tilt = 0.0
var dragging_preview = false
var preview_pan = Vector2.ZERO
var preview_drag_button = BUTTON_LEFT
var preview_drag_tilt = false
var playable = false
var keys = {}
var preview_velocity = Vector2.ZERO
var preview_position = Vector2.ZERO
var dash_time = 0.0
var grounded = true
var file_dialog: FileDialog
var import_dialog: ConfirmationDialog
var import_field: TextEdit
var import_feedback: Label
var pending_import = {}
var shader: Shader
var texture_cache = {}
var shader_cache = {}
var look_previews = []
var preview_skin_override = {}
var rendering_look = false
var _logged_items = -1
# Outfit per signed-in account (hashed id), so switching accounts at start
# brings back the outfit last worn on that account.
var _account_key = ""
var _startup_working = {}
var _first_account_run = false
var item_transforms = {}
var item_textures = {}     # cosmetic id -> "dots" / "stripes" / "grid" / "import_..."
var item_texture_buttons = {}
var item_texture_imports: OptionButton
var transform_controls: VBoxContainer
var transform_fields = {}
var transform_note: Label
var editing_transform = false
var transform_script
var transform_gizmo: Control
var item_drag = {}
var item_bounds = {}
var measuring_item = false
var player_lookup = null    # StudioPlayerLookup.gd (Looks page)
var dev_match = null        # DEV_MATCH, only on the developer machine

class TransformGizmo extends Control:
	var studio
	func _draw():
		if studio == null: return
		var box = studio._item_box()
		if box.size == Vector2.ZERO: return
		draw_rect(box, Color("a68bff"), false, 1.5)
		for point in studio._item_handles(box):
			draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),Color("14162d"))
			draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),Color("a68bff"),false,1.5)
var full_preview = false
var right_column: Control
var fonts = {}

class Stage:
	extends Control
	var pan = Vector2.ZERO
	var background = Color("1c1f3d")
	var floor_color = Color("8a7bd6")
	var level_theme = null # a level theme resource drawn behind the Goober
	func _draw():
		if level_theme != null:
			_draw_theme()
			return
		draw_rect(Rect2(Vector2.ZERO, rect_size), background)
		# 4.0: a few fixed stars behind the Goober.
		for i in range(28):
			var star = Vector2(fposmod(float(i * 137) + pan.x * 0.3, rect_size.x), fposmod(float(i * 89), max(rect_size.y - 80.0, 1.0)))
			draw_circle(star, 1.0 + float(i % 3) * 0.6, Color(1, 0.95, 0.8, 0.18 + float(i % 4) * 0.08))
		var ground = rect_size.y - 65 + pan.y
		draw_rect(Rect2(24 + pan.x, ground, rect_size.x - 48, 5), floor_color)
		for i in range(6):
			var x = fposmod(rect_size.x * float(i) / 5.0 + pan.x, rect_size.x)
			draw_line(Vector2(x, 0), Vector2(x, ground), Color(1, 1, 1, 0.025), 1)
		draw_circle(Vector2(rect_size.x / 2 + pan.x, ground + 16), 3, floor_color)
	func _draw_theme():
		var top = Color("6fb8ff")
		var bottom = Color("c3ded6")
		var gradient = level_theme.get("background_gradient")
		if gradient is Gradient and gradient.get_point_count() >= 2:
			bottom = gradient.get_color(0)
			top = gradient.get_color(gradient.get_point_count() - 1)
		for step in 24:
			draw_rect(Rect2(0, rect_size.y * step / 24.0, rect_size.x, rect_size.y / 24.0 + 1), top.linear_interpolate(bottom, step / 23.0))
		var art = level_theme.get_meta("background_art") if level_theme.has_meta("background_art") else null
		if art is Texture:
			draw_texture_rect(art, Rect2(Vector2.ZERO, rect_size), false)
		else:
			var horizon = level_theme.get("horizon_texture")
			if horizon is Texture:
				var height = min(rect_size.y * 0.45, horizon.get_height())
				draw_texture_rect(horizon, Rect2(0, rect_size.y - 65 - height + pan.y, rect_size.x, height), true, Color(1, 1, 1, 0.9))
		var ground = rect_size.y - 65 + pan.y
		var platform = Rect2(24 + pan.x, ground, rect_size.x - 48, 60)
		var terrain = level_theme.get("terrain_texture")
		if terrain is Texture:
			draw_texture_rect(terrain, platform, true)
		else:
			draw_rect(platform, floor_color)
		var edge = level_theme.get("terrain_color_1")
		draw_line(platform.position, platform.position + Vector2(platform.size.x, 0), edge if edge is Color else Color.white, 5.0)
		var grass = level_theme.get("front_grass_color")
		if grass is Color:
			draw_line(platform.position + Vector2(0, -2), platform.position + Vector2(platform.size.x, -2), grass, 3.0)

const SHADER_CODE = """
shader_type canvas_item;
uniform sampler2D gradient;
uniform sampler2D pattern_image;
uniform sampler2D item_image;
uniform int pattern = 0;
varying vec2 local_pos;
void vertex() { local_pos = VERTEX / 320.0; }
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
float hue_step(float from, float to) { return fract(to - from + 0.5) - 0.5; }
void fragment() {
    vec4 vertex_color = COLOR;
    vec4 sample_color = texture(TEXTURE, UV);
    vec3 grad = texture(gradient, vec2(sample_color.r, vertex_color.g)).rgb;
    vec3 result = mix(sample_color.rgb, grad, 1.0 - vertex_color.r);
    if (vertex_color.b > 0.81 && vertex_color.r > 0.99) {
        // Palette fit: slot green = hue turn that puts the item's main colour
        // next to the palette colour, blue 0.82..0.98 = palette hue. The item's
        // other colours keep their place around it, drawn a little closer, so
        // it matches without turning into one flat colour. Greys stay.
        float base = fract((vertex_color.b - 0.82) / 0.16 + 0.1);
        vec3 hsv = rgb2hsv(result);
        if (hsv.y > 0.08) {
            float h = fract(hsv.x + vertex_color.g);
            hsv.x = fract(base + hue_step(base, h) * 0.65);
        }
        result = hsv2rgb(hsv);
    } else if (vertex_color.b > 0.2 && vertex_color.b < 0.8) {
        vec2 tile = fract(local_pos * 3.0);
        float ink = 0.0;
        // Slot colour blue picks the pattern: 0.5 = the body's, other bands = an item's own.
        int p = pattern;
        float band = vertex_color.b;
        if (band < 0.35) { p = 1; } else if (band < 0.45) { p = 2; } else if (band > 0.65) { p = 5; } else if (band > 0.55) { p = 3; }
        if (p == 1) { ink = 1.0 - smoothstep(0.12, 0.2, length(tile - 0.5)); }
        if (p == 2) { ink = step(0.6, fract((local_pos.x + local_pos.y) * 4.0)); }
        if (p == 3) { ink = max(step(0.88, tile.x), step(0.88, tile.y)); }
        if (p > 0 && p < 4) { result = mix(result, result * 0.48, ink); }
        else if (p == 4) { vec4 texel = texture(pattern_image, fract(local_pos)); result = mix(result, texel.rgb * (0.65 + sample_color.r * 0.35), texel.a); }
        else if (p == 5) { vec4 texel = texture(item_image, fract(local_pos * 2.5)); result = mix(result, texel.rgb * (0.65 + sample_color.r * 0.35), texel.a); }
    }
    COLOR = vec4(result, sample_color.a);
}
"""
