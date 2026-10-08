extends Node

export var visible_when_guest_account: = false
export var visible_when_email_account: = false
export var visible_when_linked_to_platform: = false
export var visible_when_logged_out: = false
export var invert: = false

onready var parent: = get_parent() as CanvasItem


func _ready() -> void:
	if parent == null:
		return
	var moonlight = get_node_or_null("/root/Moonlight")
	if moonlight == null:
		return
	moonlight.connect("on_authentication_succeeded", self, "update_label")
	moonlight.connect("on_log_out", self, "update_label")
	var storage = moonlight.get("storage")
	if storage != null:
		storage.call("observe", "account", self, "on_account_changed")
	update_label()


func on_account_changed(_diff) -> void:
	update_label()


func update_label() -> void:
	if parent == null:
		return
	var moonlight = get_node_or_null("/root/Moonlight")
	if moonlight == null or moonlight.get("auth") == null:
		parent.visible = visible_when_logged_out
		return
	var auth = moonlight.get("auth")
	if bool(auth.call("is_logged_in")):
		if bool(auth.call("is_guest_account")):
			parent.visible = visible_when_guest_account
		elif bool(auth.call("is_account_linked_to_email")):
			parent.visible = visible_when_email_account
		elif bool(auth.call("is_account_linked_to_platform")):
			parent.visible = visible_when_linked_to_platform
		else:
			parent.visible = not visible_when_logged_out
	else:
		parent.visible = visible_when_logged_out
	if invert:
		parent.visible = not parent.visible
