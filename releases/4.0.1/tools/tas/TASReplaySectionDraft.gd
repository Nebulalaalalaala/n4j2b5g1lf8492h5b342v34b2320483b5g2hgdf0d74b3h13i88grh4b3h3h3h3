extends Reference
const Route = preload("user://mod/tools/tas/TASReplayRoute.gd")
signal changed
var controller
var tool
var sections = []
var samples = []
var revision = 0
var segmented = false
var spacing = 3.0
var message = ""
var next_id = -1

func setup(owner, route: Array) -> void:
	controller = owner
	tool = owner.tool
	samples = route
	regenerate()

func regenerate() -> void:
	sections = Route.generate(samples,spacing)
	for section in sections: _fill(section)
	touch()

func _fill(section: Dictionary) -> void:
	section.id = next_id
	next_id -= 1
	section.name = "Section %d" % (sections.size()+1)
	section.target_id = section.id
	section.takes = []
	section.best = -1
	section.used = 0

func touch() -> void:
	message = Route.retime(sections,samples)
	revision += 1

func zone_for(section: Dictionary): return section.get("zone")
func first_open_segment() -> int: return 0
func make_map_boxes() -> int:
	regenerate()
	return sections.size()
func add_stop_box(zone: Rect2, source := "manual") -> int:
	if sections.size()>=256 or zone.size.x<8 or zone.size.y<8: return -1
	var section = {"start":-1,"end":-1,"zone":zone,"source":source,"done":false}
	_fill(section)
	sections.append(section)
	touch()
	emit_signal("changed")
	return sections.size()-1
func normalize_section_order() -> void:
	for index in sections.size(): sections[index].name = "Section %d" % (index+1)
func move_section(index: int, target: int) -> bool:
	if index<0 or index>=sections.size() or target<0 or target>=sections.size(): return false
	var section = sections[index]
	sections.remove(index)
	sections.insert(target,section)
	normalize_section_order()
	touch()
	emit_signal("changed")
	return true
