extends CharacterBody3D

class_name Enemy

@export var move_speed := 1
@export var attack_interval := 5.0
@export var max_health := 2
var move_direction: Vector3 = Vector3.FORWARD
var move_timer: float = 0.0
const MOVE_DURATION: float = 5.0  # Move for 5 seconds before changing direction
const SPEED: float = 3.0
var current_health: int
var last_hit_arrow_id: int = -1

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection_area: Area3D = $AreaOfDetection
@onready var attack_area: Area3D = $AreaOfAttack
@onready var arrow_spawn_point: Node3D = $ArrowSpawnPoint

@onready var synchronizer = $MultiplayerSynchronizer

enum State { IDLE, PURSUE, ATTACK }
var current_state: State = State.IDLE

var target_player: CharacterBody3D = null
var time_since_last_attack := 0.0

var wait_timer: float = 0.0
const WAIT_TIME: float = 3.0
const MOVE_DISTANCE: float = 1.0

# Preload the arrow scene
const EnemyArrow = preload("res://assets/scenes/enemyArrow.tscn")
@export var enemy_id: int = 0

func _ready():
	current_health = max_health
	set_multiplayer_authority(1)
	add_to_group("enemies")
	#print("Enemy added to 'enemies' group")
	
	synchronizer.set_multiplayer_authority(1)
	
	if is_multiplayer_authority():
		set_physics_process(true)
	else:
		set_physics_process(false)
	
	# Connect area signals
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)
	
	# Set up NavigationAgent3D
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	
	# Make sure to call this when the node is ready
	call_deferred("actor_setup")
	wait_timer = WAIT_TIME
	
	if multiplayer.is_server():
		enemy_id = randi()

func actor_setup():
	await get_tree().physics_frame


func _physics_process(delta):
	if not multiplayer.is_server():
		return
	
	var current_location = global_transform.origin
	var next_location = nav_agent.get_next_path_position()
	var new_vel = current_location.direction_to(next_location) * SPEED 
	
	nav_agent.set_velocity(new_vel)
	
	
	#print("Enemy physics process running on server")
	
	#match current_state:
		#State.IDLE:
			#state_idle_behavior(delta)
		#State.PURSUE:
			#state_pursue_behavior(delta)
		#State.ATTACK:
			#state_attack_behavior(delta)


#func _process(delta):
	#if not is_multiplayer_authority():
		#if velocity.length() > 0.01:
			#look_at(global_position + velocity, Vector3.UP)


func update_target_location(target_location):
	print("updating target location, \n target location: " + str(target_location))
	nav_agent.set_target_position (target_location)

func _on_navigation_agent_3d_velocity_computed(safe_velocity):
	print(str(name) + ": found target position")
	velocity = velocity.move_toward(safe_velocity, .25)
	print(str(name) + ": velocity: " + str(velocity))
	move_and_slide()


@rpc("any_peer", "call_local")
func move_towards(target_position: Vector3):
	#print("move_towards called with target: ", target_position)
	if not is_multiplayer_authority():
		return
	
	nav_agent.set_target_position(target_position)
	
	var current_location = global_transform.origin
	var next_location = nav_agent.get_next_path_position()
	
	# Zero out the y component to prevent vertical movement if not desired
	next_location.y = current_location.y
	
	var new_vel = current_location.direction_to(next_location) * SPEED 
	
	print("nav_agent found new \n velocity:" + str(new_vel) + "\n next location: " + str(next_location))
	nav_agent.set_velocity(new_vel)
	
	move_and_slide()
	

func state_idle_behavior(delta):
	move_timer += delta
	
	if move_timer >= MOVE_DURATION:
		# Choose a new random direction
		move_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		move_timer = 0.0
	
	# Move in the current direction
	velocity = move_direction * move_speed
	
	# Make the enemy face the direction it's moving
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP)
	
	move_and_slide()


func state_pursue_behavior(delta):
	if target_player:
		nav_agent.target_position = target_player.global_position
		
		if nav_agent.is_navigation_finished():
			return
		
		var next_position = nav_agent.get_next_path_position()
		
		# Flatten the movement on the y-axis
		next_position.y = global_position.y 
		var new_velocity = (next_position - global_position).normalized() * move_speed
		velocity = velocity.move_toward(new_velocity, delta * 100.0)
		
		# Make the enemy face the direction it's moving
		if velocity.length() > 0.1:  # Only rotate if moving significantly
			look_at(global_position + velocity, Vector3.UP)
		
		move_and_slide()


func state_attack_behavior(delta):
	time_since_last_attack += delta
	if time_since_last_attack >= attack_interval:
		shoot_arrow()
		time_since_last_attack = 0

func shoot_arrow():
	rpc("spawn_arrow")

@rpc("call_local")
func spawn_arrow():
	var arrow = EnemyArrow.instantiate()
	arrow.global_transform = arrow_spawn_point.global_transform
	get_tree().root.add_child(arrow)
	arrow.initialize(arrow_spawn_point.global_transform, 20.0, self)  # Adjust speed as needed
	
	if target_player:
		var direction = (target_player.global_position - arrow_spawn_point.global_position).normalized()
		arrow.look_at(arrow_spawn_point.global_position + direction, Vector3.UP)

func _on_detection_area_body_entered(body):
	if body is CharacterBody3D and body.name.is_valid_int():  # Assuming player names are their network IDs
		target_player = body
		current_state = State.PURSUE

func _on_attack_area_body_exited(body):
	if body == target_player:
		current_state = State.PURSUE

@rpc("any_peer")
func receive_damage_request(damage: int, arrow_id: int):
	print("last_hit_arrow_id: " + str(last_hit_arrow_id) + "arrow_id: " + str(arrow_id))
	if not is_multiplayer_authority() or arrow_id == last_hit_arrow_id:
		return
		
	print("last id was: " + str(last_hit_arrow_id) + " and now arrow id is " + str(arrow_id) + " applying damage!")
	last_hit_arrow_id = arrow_id
	apply_damage(damage)

func apply_damage(damage: int):
	current_health -= damage
	print("Enemy hit! Current health: ", current_health)
	
	# Broadcast the new health to all clients
	rpc("update_health", current_health)
	
	if current_health <= 0:
		die()
	else:
		rpc("flash_hit")

@rpc("call_local")
func update_health(new_health: int):
	current_health = new_health
	if current_health <= 0:
		remove_enemy()

func die():
	print("Enemy ", enemy_id, " died!")
	rpc("remove_enemy")

@rpc("call_local")
func remove_enemy():
	queue_free()
