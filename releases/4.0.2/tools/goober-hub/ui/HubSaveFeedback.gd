extends Node
# Acknowledgment belongs to the clicked button, not a page-wide redraw.
# Failure stays retryable; only a successful import flashes "Saved".
var service
var key = ""
var button
var original = ""
var elapsed = 0.0

func configure(target, source, code):
	button = target
	service = source
	key = code
	original = button.caption
	var font = button.caption_label.get_font("font")
	button.rect_min_size.x = max(button.rect_min_size.x,font.get_string_size("Saved").x+40)
	service.connect("item_saved",self,"_saved")
	set_process(false)

func _saved(code):
	if code!=key or not is_instance_valid(button): return
	button.caption = "Saved"
	button.caption_label.text = "Saved"
	button.disabled = true
	button.hint_tooltip = "Saved successfully to the original tool."
	elapsed = 0.0
	set_process(true)

func _process(delta):
	elapsed += delta
	if elapsed<2.5: return
	button.caption = original
	button.caption_label.text = original
	button.disabled = false
	button.hint_tooltip = ""
	set_process(false)
