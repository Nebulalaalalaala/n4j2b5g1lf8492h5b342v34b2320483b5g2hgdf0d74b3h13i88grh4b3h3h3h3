extends Node

# AvatarStudio: shared state (variables, constants, signals, inner classes), in the original order.

const ModPaths = preload("user://mod/core/ModPaths.gd")

# Local editor layered over the existing renderer/catalog. No profile RPCs.
const DATA_PATH = ModPaths.AVATAR_STUDIO_DATA
const TEXTURE_DIR = ModPaths.AVATAR_STUDIO_TEXTURES
const BG = Color("181c20")
const PANEL = Color("22282c")
const LINE = Color("343c40")
const TEXT = Color("eef1ed")
const DIM = Color("9ba8ad")
const ACCENT = Color("9dd6bd")
const CATEGORIES = [["color", "Goober"], ["hat", "Hats"], ["suit", "Bodies"], ["hand", "Weapons"], ["emote", "Emotes"]]
const PAGE_SIZE = 12
var sandbox
var tool_ref
var stage: Control
var goober
var section_tabs: TabContainer
var customize: VBoxContainer
var looks_page: VBoxContainer
var preview_page: VBoxContainer
var catalog_grid: GridContainer
var search: LineEdit
var status: Label
var summary: Label
var paging: Label
var inspector: Label
var color_controls: VBoxContainer
var texture_controls: VBoxContainer
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
var category_actions: HBoxContainer
var effect_preview = null
var importing = false
var restoring = false
var refreshing = false
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
var item_transforms = {}
var transform_controls: VBoxContainer
var transform_fields = {}
var transform_note: Label
var editing_transform = false
var transform_script
var transform_gizmo: Control
var item_drag = {}
var item_bounds = {}
var measuring_item = false

class TransformGizmo extends Control:
	var studio
	func _draw():
		if studio == null: return
		var box = studio._item_box()
		if box.size == Vector2.ZERO: return
		draw_rect(box, Color("9dd6bd"), false, 1.5)
		for point in studio._item_handles(box):
			draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),Color("181c20"))
			draw_rect(Rect2(point-Vector2(4,4),Vector2(8,8)),Color("9dd6bd"),false,1.5)
var full_preview = false
var right_column: Control
var fonts = {}

class Stage:
	extends Control
	var pan = Vector2.ZERO
	var background = Color("202b30")
	var floor_color = Color("718e83")
	func _draw():
		draw_rect(Rect2(Vector2.ZERO, rect_size), background)
		var ground = rect_size.y - 65 + pan.y
		draw_rect(Rect2(24 + pan.x, ground, rect_size.x - 48, 5), floor_color)
		for i in range(6):
			var x = fposmod(rect_size.x * float(i) / 5.0 + pan.x, rect_size.x)
			draw_line(Vector2(x, 0), Vector2(x, ground), Color(1, 1, 1, 0.025), 1)
		draw_circle(Vector2(rect_size.x / 2 + pan.x, ground + 16), 3, floor_color)

const SHADER_CODE = """
shader_type canvas_item;
uniform sampler2D gradient;
uniform sampler2D pattern_image;
uniform int pattern = 0;
varying vec2 local_pos;
void vertex() { local_pos = VERTEX / 320.0; }
void fragment() {
    vec4 vertex_color = COLOR;
    vec4 sample_color = texture(TEXTURE, UV);
    vec3 grad = texture(gradient, vec2(sample_color.r, vertex_color.g)).rgb;
    vec3 result = mix(sample_color.rgb, grad, 1.0 - vertex_color.r);
    if (vertex_color.b > 0.2 && vertex_color.b < 0.8) {
        vec2 tile = fract(local_pos * 3.0);
        float ink = 0.0;
        if (pattern == 1) { ink = 1.0 - smoothstep(0.12, 0.2, length(tile - 0.5)); }
        if (pattern == 2) { ink = step(0.6, fract((local_pos.x + local_pos.y) * 4.0)); }
        if (pattern == 3) { ink = max(step(0.88, tile.x), step(0.88, tile.y)); }
        if (pattern < 4) { result = mix(result, result * 0.48, ink); }
        else { vec4 texel = texture(pattern_image, fract(local_pos)); result = mix(result, texel.rgb * (0.65 + sample_color.r * 0.35), texel.a); }
    }
    COLOR = vec4(result, sample_color.a);
}
"""
