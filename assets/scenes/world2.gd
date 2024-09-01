extends	Node

const Player = preload("res://assets/scenes/character.tscn")
const PORT = 9999

var	enet_peer =	ENetMultiplayerPeer.new()

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry
@onready var hud = $CanvasLayer/HUD

func _ready():
	pass

func _on_join_button_pressed():
	main_menu.hide()
	hud.show()

	var	ip = address_entry.text	if address_entry.text else "localhost"
	enet_peer.create_client(ip,	PORT)
	multiplayer.multiplayer_peer = enet_peer

func _on_peer_disconnected(id):
	print("Disconnected: ", id)
	if has_node(str(id)):
		get_node(str(id)).queue_free()

@rpc("authority", "call_local")
func spawn_player(peer_id):
	print("spawn_player")
	if not has_node(str(peer_id)):
		addPlayer(peer_id)

@rpc("authority")
func test_local():
	print("test_local")

func addPlayer(peer_id):
	print("addPlayer")
	var	player = Player.instantiate()
	player.name	= str(peer_id)
	add_child(player)
	player.global_position = Vector3(0,	0, 0)

@rpc("authority")
func sync_players(player_ids):
	for	id in player_ids:
		if not has_node(str(id)):
			addPlayer(id)