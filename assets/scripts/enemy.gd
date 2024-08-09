extends CharacterBody3D

class_name Enemy

@export var move_speed := 3.0
@export var attack_interval := 5.0
@export var max_health := 2
var current_health: int

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection_area: Area3D = $AreaOfDetection
@onready var attack_area: Area3D = $AreaOfAttack
@onready var arrow_spawn_point: Node3D = $ArrowSpawnPoint

@onready var synchronizer = $MultiplayerSynchronizer

enum State { IDLE, PURSUE, ATTACK }
var current_state: State = State.IDLE

var target_player: CharacterBody3D = null
var time_since_last_attack := 0.0

# Preload the arrow scene
const EnemyArrow = preload("res://assets/scenes/enemyArrow.tscn")

func _ready():
	current_health = max_health
	set_multiplayer_authority(1)
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

@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_velocity: Vector3 = Vector3.ZERO

func actor_setup():
	# Wait for the first physics frame so the NavigationServer can sync.
	await get_tree().physics_frame
	
	# Now that the navigation map is ready, set the process callback
	nav_agent.velocity_computed.connect(move)

func move(safe_velocity: Vector3):
	velocity = safe_velocity
	move_and_slide()

func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	
	match current_state:
		State.IDLE:
			idle_behavior(delta)
		State.PURSUE:
			pursue_behavior(delta)
		State.ATTACK:
			attack_behavior(delta)
	
	move_and_slide()
	
	sync_position = global_position
	sync_velocity = velocity

func _process(delta):
	if not is_multiplayer_authority():
		# Smoothly interpolate position and velocity for non-authoritative clients
		global_position = global_position.lerp(sync_position, 15 * delta)
		velocity = velocity.lerp(sync_velocity, 15 * delta)

func idle_behavior(delta):
	# Implement idle wandering behavior here
	pass

func pursue_behavior(delta):
	if target_player:
		nav_agent.target_position = target_player.global_position
		
		if nav_agent.is_navigation_finished():
			return
		
		var next_position = nav_agent.get_next_path_position()
		var new_velocity = (next_position - global_position).normalized() * move_speed
		velocity = velocity.move_toward(new_velocity, delta * 100.0)
		
		# Make the enemy face the direction it's moving
		if velocity.length() > 0.1:  # Only rotate if moving significantly
			look_at(global_position + velocity, Vector3.UP)
		
		move_and_slide()

func attack_behavior(delta):
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
func receive_damage():
	if not is_multiplayer_authority():
		return
	current_health -= 1
	print("Enemy hit! Current health: ", current_health)
	
	if current_health <= 0:
		die()

func die():
	# Implement death behavior (e.g., play death animation, spawn loot, etc.)
	print("Enemy died!")
	rpc("remove_enemy")

@rpc("call_local")
func remove_enemy():
	queue_free()
