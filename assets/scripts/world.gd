extends Node

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry
@onready var hud = $CanvasLayer/HUD
@onready var health_bar = $CanvasLayer/HUD/HealthBar
@onready var spawn_manager: SpawnManager = $SpawnManager
@onready var key_spawn_manager: KeySpawnManager = $KeySpawnManager

const Player = preload("res://assets/fpc/character.tscn")
const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

func _on_host_button_pressed():
	main_menu.hide()
	hud.show()
	
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(addPlayer)
	multiplayer.peer_disconnected.connect(removePlayer)
	
	addPlayer(multiplayer.get_unique_id())
	
	# Spawn keys when the game starts
	spawn_keys.rpc()

@rpc("call_local")
func spawn_keys():
	key_spawn_manager.spawn_keys()

func _on_join_button_pressed():
	main_menu.hide()
	hud.show()
	
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer
	
	addPlayer(multiplayer.get_unique_id())

func addPlayer(peer_id):
	var spawn_data = spawn_manager.get_random_spawn_point()
	var player = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	player.global_position = spawn_data.position
	# player.global_rotation = spawn_data.rotation # rotation breaks shit
	if player.is_multiplayer_authority():
		player.tree_exiting.connect(func(): spawn_manager.release_spawn_point(spawn_data.position))
		player.health_changed.connect(update_health_bar)
		
func removePlayer(peer_id):
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

func update_health_bar(health_value):
	health_bar.value = health_value

func _on_multiplayer_spawner_spawned(node):
	if node.is_multiplayer_authority():
		node.health_changed.connect(update_health_bar)
