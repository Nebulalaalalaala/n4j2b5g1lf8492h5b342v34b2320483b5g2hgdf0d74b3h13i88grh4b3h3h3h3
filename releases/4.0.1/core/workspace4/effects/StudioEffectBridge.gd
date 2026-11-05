extends Reference
const Document = preload("user://mod/core/workspace4/effects/EffectDocument.gd")

static func runtime(studio):
	for node in studio.get_tree().get_nodes_in_group("goob_effect_runtime"):
		if is_instance_valid(node): return node
	return null

static func link(studio):
	var service = runtime(studio)
	if service==null: return
	studio.effect_settings["custom_effect"] = Document.export_data(service.worn) if not service.worn.empty() else {}
	studio.sandbox.call("_commit_change",false)
	studio.status.text = "Current effect linked. Save or update your Look to keep it."

static func follow(studio):
	studio.effect_settings.erase("custom_effect")
	studio.sandbox.call("_commit_change",false)
	studio.status.text = "This Look follows your global worn effect."

static func restore(studio,settings):
	if not settings.has("custom_effect"): return # Existing looks retain global behavior.
	var service = runtime(studio)
	if service==null: return
	var document = Document.clean(settings.custom_effect)
	if document.empty(): service.take_off()
	else: service.wear(document)

static func preview(studio,target):
	if target!=studio.goober or not is_instance_valid(target) or target.get_parent()==null: return
	var parent = target.get_parent()
	if parent.get_node_or_null("StudioCustomEffectPreview")!=null: return
	var view = load("user://mod/core/workspace4/effects/StudioEffectPreview.gd").new()
	view.name = "StudioCustomEffectPreview"
	view.studio = studio
	view.source = target
	parent.add_child(view)

static func open_editor(studio):
	var menu = studio.tool_ref.get("_workspace_menu") if is_instance_valid(studio.tool_ref) else null
	if is_instance_valid(menu): menu.select("effects")
