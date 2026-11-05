extends Control

var kind = "window"
var font: Font
const MINT = Color("9dd6bd")
const INK = Color("eef1ed")
const MUTED = Color("9ba8ad")
const BLUE = Color("78b8dc")

func text_at(at: Vector2, text: String, color = INK) -> void:
	if font != null:
		draw_string(font, at, text, color)

func box(rect: Rect2, color = MINT) -> void:
	draw_rect(rect, Color(color.r, color.g, color.b, 0.22))
	draw_rect(rect, color, false, 2)

func arrow(a: Vector2, b: Vector2, color = MINT) -> void:
	draw_line(a, b, color, 2, true)
	var direction = (b - a).normalized()
	var side = Vector2(-direction.y, direction.x)
	draw_colored_polygon(PoolVector2Array([b, b - direction * 9 + side * 5, b - direction * 9 - side * 5]), color)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(rect_size.x / 600.0, rect_size.y / 150.0))
	draw_rect(Rect2(0, 0, 600, 150), Color("20282c"))
	match kind:
		"tool_flow":
			for i in 3:
				box(Rect2(20+i*200,35,150,80),MINT if i==2 else BLUE)
				text_at(Vector2(36+i*200,78),["1  Choose","2  Inspect","3  Act"][i])
				if i<2:
					arrow(Vector2(177+i*200,75),Vector2(213+i*200,75))
		"window":
			box(Rect2(175, 20, 220, 110))
			draw_line(Vector2(175, 48), Vector2(395, 48), MINT, 2)
			text_at(Vector2(187, 39), "Editor+")
			text_at(Vector2(191, 76), "−    100%    +    Fit")
			text_at(Vector2(22, 34), "Drag title")
			arrow(Vector2(100, 32), Vector2(165, 32))
			arrow(Vector2(380, 115), Vector2(399, 134))
			text_at(Vector2(425, 131), "Resize corner")
		"move":
			box(Rect2(45, 40, 44, 44)); box(Rect2(113, 70, 44, 44))
			arrow(Vector2(215, 72), Vector2(365, 72))
			text_at(Vector2(241, 56), "Nudge +1 X")
			box(Rect2(425, 40, 44, 44)); box(Rect2(493, 70, 44, 44))
			text_at(Vector2(62, 137), "Before"); text_at(Vector2(448, 137), "After")
		"size":
			box(Rect2(65, 25, 100, 100)); box(Rect2(270, 75, 100, 50)); box(Rect2(475, 100, 100, 25))
			text_at(Vector2(79, 18), "Height 1"); text_at(Vector2(274, 65), "Height 0.5"); text_at(Vector2(474, 90), "Height 0.25")
			draw_line(Vector2(30, 128), Vector2(585, 128), MUTED, 1)
		"properties":
			box(Rect2(50, 35, 85, 65), BLUE); box(Rect2(160, 35, 85, 65), BLUE)
			text_at(Vector2(65, 72), "Field A"); text_at(Vector2(175, 72), "Field B")
			arrow(Vector2(278, 70), Vector2(378, 70))
			box(Rect2(412, 35, 155, 65)); text_at(Vector2(430, 72), "Strength = 3")
			text_at(Vector2(75, 131), "Select both"); text_at(Vector2(436, 131), "Apply once")
		"tween":
			box(Rect2(50, 38, 60, 32)); box(Rect2(460, 38, 60, 32), BLUE)
			arrow(Vector2(130, 49), Vector2(442, 49)); arrow(Vector2(442, 96), Vector2(130, 96), BLUE)
			text_at(Vector2(218, 35), "Key 1: 3, 0 · 2s"); text_at(Vector2(213, 126), "Key 2: 0, 0 · 2s")
		"group":
			box(Rect2(50, 30, 210, 90), BLUE)
			for x in [70, 135, 200]:
				box(Rect2(x, 60, 38, 38))
			text_at(Vector2(69, 50), "Bridge")
			arrow(Vector2(285, 75), Vector2(360, 75))
			text_at(Vector2(381, 62), "Select group")
			text_at(Vector2(381, 88), "Recall all 3 objects", MUTED)
		"layers":
			box(Rect2(70, 27, 190, 75), BLUE)
			draw_rect(Rect2(154, 65, 190, 66), Color("344f43"))
			box(Rect2(154, 65, 190, 66))
			text_at(Vector2(370, 49), "Layer 0 · behind", BLUE)
			text_at(Vector2(370, 102), "Layer 1 · in front", MINT)
		"opacity":
			for i in range(3):
				var x = 90 + i * 180
				draw_line(Vector2(x - 25, 78), Vector2(x + 105, 78), MUTED, 2)
				var color = MINT
				color.a = [1.0, 0.5, 0.0][i]
				draw_rect(Rect2(x, 35, 80, 80), color)
				text_at(Vector2(x + 14, 139), ["100%", "50%", "0%"][i])
		"laser":
			box(Rect2(35, 44, 140, 40), BLUE)
			box(Rect2(175, 44, 145, 40), Color("e3c078"))
			box(Rect2(320, 44, 240, 40), MINT)
			text_at(Vector2(74, 70), "Pause"); text_at(Vector2(215, 70), "Charge"); text_at(Vector2(414, 70), "Beam")
			draw_line(Vector2(180, 102), Vector2(555, 102), MINT, 2)
			text_at(Vector2(265, 128), "Active ticks include charging")
		"library":
			box(Rect2(40, 28, 175, 100), BLUE)
			text_at(Vector2(59, 58), "Projects / Racing"); text_at(Vector2(70, 91), "My level.json")
			arrow(Vector2(245, 77), Vector2(325, 77))
			box(Rect2(350, 39, 190, 32)); box(Rect2(350, 84, 190, 32))
			text_at(Vector2(375, 62), "#practice"); text_at(Vector2(375, 107), "#precision")
		"recovery":
			for i in range(3):
				box(Rect2(35 + i * 210, 42, 145, 60), BLUE if i == 1 else MINT)
				text_at(Vector2(49 + i * 210, 78), ["Save snapshot", "Experiment", "Restore copy"][i])
			arrow(Vector2(185, 73), Vector2(238, 73)); arrow(Vector2(395, 73), Vector2(448, 73))
