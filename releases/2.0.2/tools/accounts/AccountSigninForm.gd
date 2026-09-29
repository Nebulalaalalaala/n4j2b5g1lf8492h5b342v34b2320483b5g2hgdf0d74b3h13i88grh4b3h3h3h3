extends MoonlightEmailSigninForm
var manager
var remember: CheckBox

func _ready():
	# Reuse the native form, without its signup/reset/linking handlers.
	if login_button.is_connected("pressed",self,"on_login_pressed"):
		login_button.disconnect("pressed",self,"on_login_pressed")
	if password_label.is_connected("text_entered",self,"on_auth_pressed_arg"):
		password_label.disconnect("text_entered",self,"on_auth_pressed_arg")
	if back_button.is_connected("pressed",self,"emit_signal"):
		back_button.disconnect("pressed",self,"emit_signal")
	login_button.connect("pressed",self,"on_auth_pressed")
	password_label.connect("text_entered",self,"on_auth_pressed_arg")
	back_button.connect("pressed",self,"back")
	if "remember_login" in manager:
		remember = CheckBox.new()
		remember.text = "Remember login on this PC"
		remember.rect_position = forgot_password_button.rect_position
		remember.rect_min_size = Vector2(540,48)
		var face = DynamicFont.new()
		face.font_data = load("res://goodoh/fonts/ttf/Baloo2-ExtraBold.ttf")
		face.size = 24
		remember.add_font_override("font",face)
		remember.pressed = true
		remember.hint_tooltip = "Stores your email and password encrypted for this Windows account. Used only when you select this account after its saved session expires. Removing the account deletes its local saved login."
		add_child(remember)
	clear()

func clear():
	email_label.text = ""
	password_label.text = ""
	password_container.show()
	email_label.show()
	spinner.hide()
	forgot_password_button.hide()
	message_label.text = "Sign in to an existing account. No account linking or creation."

func back():
	if not manager.busy:
		password_label.text = ""
		emit_signal("back_pressed")

func on_auth_pressed():
	if manager.busy:
		return
	if email_label.text.strip_edges().empty() or password_label.text.empty():
		send_error_message("Enter your account email and password.")
		return
	enable_buttons(false)
	show_spinner()
	if remember!=null:
		manager.remember_login = remember.pressed
	var request = manager.sign_in(email_label.text.strip_edges().to_lower(),password_label.text)
	password_label.text = ""
	if request is GDScriptFunctionState:
		request = yield(request,"completed")
	if not is_inside_tree():
		return
	hide_spinner()
	enable_buttons(true)
	forgot_password_button.hide()
	if not request:
		send_error_message(manager.status)

func on_login_pressed():
	on_auth_pressed()

func on_forgot_password_pressed():
	pass

func on_socket_message_parsed(_notification,_content):
	pass
