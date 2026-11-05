extends Node

export var _game: NodePath
onready var game = get_node(_game)

# Reuse rendering/input without announcing an online match or running ads.
func _enter_tree():
	pass

func _exit_tree():
	pass

func _ready():
	game.client_connection_type = NetworkGame.WEBSOCKET
	game.client_use_webrtc_if_available = false

func _process(_delta):
	pass
