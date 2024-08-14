extends Node

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry
@onready var hud = $CanvasLayer/HUD
@onready var health_bar = $CanvasLayer/HUD/HealthBar
@onready var spawn_manager = $SpawnManager
@onready var key_spawn_manager = $KeySpawnManager
@onready var e_destination = $destination

const Enemy = preload("res://assets/scenes/enemy.tscn")

const Player = preload("res://assets/fpc/character.tscn")
const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()

var spawned_enemies = []

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)

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
	if multiplayer.is_server():
		spawn_enemies()

func _physics_process(delta):
	if multiplayer.is_server():
		handle_enemy_behaviour()
		

#
func handle_enemy_behaviour():
	var enemies = get_tree().get_nodes_in_group("enemies")
	var players = get_tree().get_nodes_in_group("players")
	
	for enemy in enemies:
		if enemy.has_method("get_current_state"):
			match enemy.get_current_state():
				0:  # IDLE
					# No action needed, enemy handles its own idle behavior
					pass
				1:  # PURSUE
					var nearest_player = find_nearest_player(enemy, players)
					if nearest_player:
						enemy.set_target_player(nearest_player)
					else:
						enemy.enter_idle_state()
				2:  # ATTACK
					# No action needed, enemy handles its own attack behavior
					pass

#
func find_nearest_player(enemy, players: Array):
	var nearest_player = null
	var min_distance = INF
	
	for player in players:
		var distance = enemy.global_position.distance_to(player.global_position)
		if distance < min_distance:
			min_distance = distance
			nearest_player = player
	
	return nearest_player


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

func _on_peer_connected(peer_id):
	if multiplayer.is_server():
		# Inform the new peer about existing enemies
		for enemy_data in spawned_enemies:
			rpc_id(peer_id, "spawn_enemy", enemy_data)

func spawn_enemies():
	# Spawn enemies at predefined positions or randomly on the NavMesh
	if multiplayer.is_server():
		for spawn_point in $EnemySpawnManager.get_children():
			var enemy_data = {
				"position": spawn_point.global_position,
				"id": randi()  # Generate a unique ID for each enemy
			}
			spawned_enemies.append(enemy_data)
			rpc("spawn_enemy", enemy_data)

@rpc("call_local")
func spawn_enemy(enemy_data: Dictionary):
	var enemy = Enemy.instantiate()
	enemy.name = str(enemy_data["id"])
	enemy.global_position = enemy_data["position"]
	add_child(enemy)
