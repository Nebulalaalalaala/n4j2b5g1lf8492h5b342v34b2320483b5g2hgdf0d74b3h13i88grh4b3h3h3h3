extends VBoxContainer

# Segmented tabs at the top of a 4.0 page. add_tab() returns the tab's
# content column; only the selected one is shown. The last tab is remembered
# per page key for this game session.

const Galaxy = preload("user://mod/core/workspace4/Galaxy.gd")
const MEMORY = "goob_v4_page_tabs"

var key := ""
var font: Font = null
var _bar: GridContainer = null
var _buttons := []
var _pages := []
var _icons := []
var _current := -1


func setup(page_key: String, tab_font: Font) -> void:
	key = page_key
	font = tab_font
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_constant_override("separation", 14)
	var strip = PanelContainer.new()
	var style = Galaxy.box(Galaxy.color("surface"), Galaxy.color("border"), 4, 12)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	strip.add_stylebox_override("panel", style)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(strip)
	_bar = GridContainer.new()
	_bar.add_constant_override("hseparation", 4)
	_bar.add_constant_override("vseparation", 4)
	strip.add_child(_bar)
	_bar.connect("resized",self,"_fit_tabs")
	var ancestor = get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			ancestor.connect("resized",self,"_fit_tabs")
			break
		ancestor = ancestor.get_parent()


func add_tab(title: String, icon_name: String) -> VBoxContainer:
	var index = _pages.size()
	var tab = Button.new()
	tab.text = title
	tab.focus_mode = Control.FOCUS_NONE
	tab.rect_min_size = Vector2(0, 34)
	tab.add_font_override("font", font)
	tab.add_constant_override("hseparation", 7)
	tab.connect("pressed", self, "select", [index])
	_bar.add_child(tab)
	_buttons.append(tab)
	_bar.columns = _buttons.size()
	_icons.append(icon_name)
	var page = VBoxContainer.new()
	page.add_constant_override("separation", 12)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.visible = false
	add_child(page)
	_pages.append(page)
	return page


func finish() -> void:
	var memory = Engine.get_meta(MEMORY) if Engine.has_meta(MEMORY) else {}
	var start = int(memory.get(key, 0))
	select(clamp(start, 0, _pages.size() - 1), false)
	call_deferred("_fit_tabs")

func _fit_tabs() -> void:
	if _buttons.empty(): return
	var available = _bar.rect_size.x
	var ancestor = get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			available = max(1,ancestor.rect_size.x-40)
			break
		ancestor = ancestor.get_parent()
	var total = 0.0
	var widest = 1.0
	for button in _buttons:
		var width = button.get_combined_minimum_size().x+4
		total += width
		widest = max(widest,width)
	_bar.columns = _buttons.size() if total<=available else int(clamp(floor(available/widest),1,_buttons.size()))


func select(index: int, animate: bool = true) -> void:
	if index < 0 or index >= _pages.size():
		return
	_current = index
	var memory = Engine.get_meta(MEMORY) if Engine.has_meta(MEMORY) else {}
	memory[key] = index
	Engine.set_meta(MEMORY, memory)
	for i in range(_pages.size()):
		_pages[i].visible = i == index
		_style_tab(i, i == index)
	if animate and not bool(SavedSettings.get_value("workspace_reduced_motion", false)):
		var page: Control = _pages[index]
		page.modulate.a = 0.0
		var tween = Tween.new()
		page.add_child(tween)
		tween.interpolate_property(page, "modulate:a", 0.0, 1.0, 0.16, Tween.TRANS_SINE, Tween.EASE_OUT)
		tween.connect("tween_all_completed", tween, "queue_free")
		tween.start()


func _style_tab(i: int, on: bool) -> void:
	var tab: Button = _buttons[i]
	var accent = Galaxy.color("accent")
	var ink = Galaxy.color("accent_ink") if on else Galaxy.color("muted")
	for state in ["font_color", "font_color_hover", "font_color_pressed"]:
		tab.add_color_override(state, ink if on or state != "font_color_hover" else Galaxy.color("ink"))
	var normal = Galaxy.primary_box(accent, 14) if on else Galaxy.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 14, 9)
	var hover = normal if on else Galaxy.box(Galaxy.color("hover"), Color(0, 0, 0, 0), 14, 9)
	if on:
		normal.shadow_size = 0
	tab.add_stylebox_override("normal", normal)
	tab.add_stylebox_override("hover", hover)
	tab.add_stylebox_override("pressed", normal)
	tab.add_stylebox_override("focus", StyleBoxEmpty.new())
	tab.icon = Galaxy.icon(_icons[i], ink, 18) if not str(_icons[i]).empty() else null
