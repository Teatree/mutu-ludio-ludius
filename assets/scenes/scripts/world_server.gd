extends	Node

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry
@onready var hud = $CanvasLayer/HUD
@onready var ui_blood_splat	= $CanvasLayer/HUD/blood_splat
@onready var spawn_manager = $SpawnManager
@onready var key_spawn_manager = $KeySpawnManager
@onready var e_destination = $destination
@onready var waiting_message = $CanvasLayer/HUD/WaitingMessage
@onready var match_timer_label : Label = $CanvasLayer/HUD/HBoxContainer/MatchTimerLabel
@onready var match_timer : Timer = $MatchTimer

# Water
@onready var water:	MeshInstance3D = $water	 # Make	sure this points to your water object
const WATER_RISE_HEIGHT	= 4.0  # 4 meters
const WATER_RISE_DURATION =	20.0  # 20 seconds

const Enemy	= preload("res://assets/scenes/enemy.tscn")
const Player = preload("res://assets/scenes/character.tscn")

const PORT = 9999
var	enet_peer =	ENetMultiplayerPeer.new()

var	dropped_keys = {}
const KeyScene = preload("res://assets/scenes/key.tscn")

var	spawned_enemies	= []
var	connected_players =	[]
var	game_started = false
# Players needed to spawn
var	players_needed = 3

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	match_timer.timeout.connect(_on_match_timer_timeout)

	_on_host_button_pressed()

func _unhandled_input(event):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

func _on_host_button_pressed():
	main_menu.hide()
	hud.show()
	waiting_message.show()
	waiting_message.text = "Waiting	for	2 more Players"
	
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	# multiplayer.peer_connected.connect(addPlayer)
	# multiplayer.peer_disconnected.connect(removePlayer)
	
	var	host_id	= multiplayer.get_unique_id()
	connected_players.append(host_id)
	players_needed -= 1
	update_waiting_message()
	addPlayer(host_id)
	
	# Spawn	keys when the game starts
	spawn_keys.rpc()
	
	if multiplayer.is_server():
		spawn_enemies()

func _on_join_button_pressed():
	main_menu.hide()
	hud.show()
	waiting_message.show()
	waiting_message.text = "Connecting..."
	
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer

	addPlayer(multiplayer.get_unique_id())

func _physics_process(delta):
	if multiplayer.is_server():
		handle_enemy_behaviour()

	update_match_timer_ui()

func update_match_timer_ui():
	var	time_left =	int(match_timer.time_left)
	if time_left > 0:
		var	minutes	= time_left	/ 60
		var	seconds	= time_left	% 60
		match_timer_label.text = "Time left: %d:%02d" %	[minutes, seconds]
	else:
		match_timer_label.text = "Time for a swim!"

func _on_match_timer_timeout():
	# Call update_match_timer_ui() one last	time to set	the	"Time for a	swim!" message
	update_match_timer_ui()
	
	# Trigger any "swim	time" events here
	start_swim_phase()

func start_swim_phase():
	print("Swim	phase started!")
	
	# Get the initial water	position
	var	initial_water_position = water.position
	
	# Calculate	the	target position
	var	target_position	= initial_water_position + Vector3(0, WATER_RISE_HEIGHT, 0)
	
	# Create a new Tween
	var	tween =	create_tween()
	
	# Set up the tween to animate the water's position
	tween.tween_property(water,	"position",	target_position, WATER_RISE_DURATION).set_trans(Tween.TRANS_LINEAR)
	
	# Optional:	Connect	to tween completion	signal if you want to trigger anything after the water finishes	rising
	tween.connect("finished", _on_water_rise_completed)
	
	# Notify all players about the swim	phase
	rpc("notify_swim_phase_start")

@rpc func notify_swim_phase_start():
	print("Swim	phase notification received")

func _on_water_rise_completed():
	print("Water has finished rising")

func handle_enemy_behaviour():
	var	enemies	= get_tree().get_nodes_in_group("enemies")
	var	players	= get_tree().get_nodes_in_group("players")
	
	for	enemy in enemies:
		if enemy.has_method("get_current_state"):
			match enemy.get_current_state():
				0:	# IDLE
					# No action	needed,	enemy handles its own idle behavior
					pass
				1:	# PURSUE
					var	nearest_player = find_nearest_player(enemy,	players)
					if nearest_player:
						enemy.set_target_player(nearest_player)
					else:
						enemy.enter_idle_state()
				2:	# ATTACK
					# No action	needed,	enemy handles its own attack behavior
					pass


func find_nearest_player(enemy,	players: Array):
	var	nearest_player = null
	var	min_distance = INF
	
	for	player in players:
		var	distance = enemy.global_position.distance_to(player.global_position)
		if distance	< min_distance:
			min_distance = distance
			nearest_player = player
	
	return nearest_player


@rpc("call_local")
func spawn_keys():
	if multiplayer.is_server():
		key_spawn_manager.spawn_keys()
		# Sync the spawned keys	with all clients
		rpc("sync_keys", key_spawn_manager.get_key_data())

@rpc("call_local")
func sync_keys(key_data):
	if not multiplayer.is_server():
		key_spawn_manager.spawn_keys_from_data(key_data)

# Registers	a dropped key across the network
@rpc("call_local")
func register_dropped_key(key_path:	NodePath, key_position:	Vector3):
	var	key_id = str(key_path)
	dropped_keys[key_id] = key_position
	
	if not multiplayer.is_server():
		return
	
	# If this is the server, sync the new key with all clients
	rpc("sync_dropped_key",	key_id,	key_position)

# Syncs	a dropped key with all clients
@rpc("call_local")
func sync_dropped_key(key_id: String, key_position:	Vector3):
	if multiplayer.is_server():
		return
	
	if not dropped_keys.has(key_id):
		var	key	= KeyScene.instantiate()
		add_child(key)
		key.global_position	= key_position
		dropped_keys[key_id] = key_position

# $$$ ADD $$$
# Removes a	collected key from the dropped keys	list
@rpc("call_local")
func remove_dropped_key(key_id:	String):
	dropped_keys.erase(key_id)


func addPlayer(peer_id):
	var	spawn_data = spawn_manager.get_random_spawn_point()

	var	player = Player.instantiate()
	player.name	= str(peer_id)
	add_child(player)
	
	if player.is_multiplayer_authority():
		player.health_changed.connect(show_blood_splat)

	player.disable_movement()

	player.global_position = Vector3(0,22,0)
	# player.global_position = spawn_data.position
	# player.global_rotation = spawn_data.rotation
	# player.head_rotation_x = spawn_data.rotation.x
	
	# Inform all clients about the new player
	rpc("sync_new_player", peer_id,	spawn_data)

func removePlayer(peer_id):
	var	player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

@rpc("call_local")
func sync_new_player(peer_id, position,	rotation):
	if not has_node(str(peer_id)):
		var	player = Player.instantiate()
		player.name	= str(peer_id)
		add_child(player)
		player.global_position = position
		player.global_rotation = rotation
		print("New player added: ", peer_id)

func show_blood_splat(health_value):
	# health value is not needed but I keep	it anyway in case I	want to display	a health bar in the	future
	ui_blood_splat.visible	= true

func _on_multiplayer_spawner_spawned(node):
	if node.is_multiplayer_authority():
		node.health_changed.connect(show_blood_splat)

func _on_peer_connected(peer_id):
	if multiplayer.is_server():
		connected_players.append(peer_id)
		players_needed -= 1
		update_waiting_message()

		rpc_id(peer_id,	"sync_keys", key_spawn_manager.get_key_data())

		# Sync dropped keys
		for	key_id in dropped_keys:
			rpc_id(peer_id,	"sync_dropped_key",	key_id,	dropped_keys[key_id])

		# Inform the new peer about	existing enemies
		for	enemy_data in spawned_enemies:
			rpc_id(peer_id,	"spawn_enemy", enemy_data)
		
		addPlayer(peer_id)
		
		if players_needed == 0:
			start_game()

func update_waiting_message():
	var	message	= ""
	if players_needed >	0:
		message	= "Waiting for %d more Player%s" % [players_needed,	"s"	if players_needed >	1 else ""]
	else:
		message	= "Match starting..."
	
	# for host
	waiting_message.text = message

	# for clients
	rpc("set_waiting_message", message)

@rpc func set_waiting_message(message: String):
	waiting_message.text = message

func spawn_enemies():
	# Spawn	enemies	at predefined positions	or randomly	on the NavMesh
	if multiplayer.is_server():
		for	spawn_point	in $EnemySpawnManager.get_children():
			var	enemy_data = {
				"position":	spawn_point.global_position,
				"id": randi()  # Generate a	unique ID for each enemy
			}
			spawned_enemies.append(enemy_data)
			rpc("spawn_enemy", enemy_data)

@rpc("call_local")
func spawn_enemy(enemy_data: Dictionary):
	var	enemy =	Enemy.instantiate()
	enemy.name = str(enemy_data["id"])
	enemy.global_position =	enemy_data["position"]
	add_child(enemy)
	enemy.enter_idle_state()  # Set	initial	state to IDLE

func start_game():
	# for host
	waiting_message.text = "Match starting..."
	get_tree().create_timer(3.0).timeout.connect(enable_player_movement)

	# for clients
	rpc("begin_match")

# Begins the match for all clients
@rpc func begin_match():
	waiting_message.text = "Match starting..."
	get_tree().create_timer(3.0).timeout.connect(enable_player_movement)

# Enables movement for all players
func enable_player_movement():
	waiting_message.hide()
	match_timer_label.show()
	match_timer.start()

	for	player in get_tree().get_nodes_in_group("players"):
		if player.has_method("enable_movement"):
			player.enable_movement()


# End Game
# Checks if all	players	have escaped or died
func check_game_end():
	var	players	= get_tree().get_nodes_in_group("players")
	var	all_escaped_or_dead	= true
	
	for	player in players:
		if not player.has_escaped and player.health	> 0:
			all_escaped_or_dead	= false
			break
	
	if all_escaped_or_dead:
		end_game()

# Ends the game	and	shows the result screen
func end_game():
	# Implement	game end logic here
	print("Game	Over - All players have	escaped	or died")
	# You can add a	game over screen or restart	the	game here
