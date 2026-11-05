extends Node
var editor
func _input(event):
	if editor==null or not is_instance_valid(editor.menu): return
	if editor.menu.active!="effects" or not editor.menu.tabs.is_visible_in_tree(): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var focus = editor.name_field.get_focus_owner() if is_instance_valid(editor.name_field) else null
	if focus is LineEdit or focus is TextEdit: return
	if event.control and event.scancode==KEY_Z:
		if event.shift: editor._redo()
		else: editor._undo()
	elif event.control and event.scancode==KEY_Y: editor._redo()
	elif event.control and event.scancode==KEY_S: editor._save()
	else: return
	get_tree().set_input_as_handled()
