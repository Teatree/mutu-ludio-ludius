extends CharacterBody3D

class_name Enemy

signal enemy_animation_changed(animation_name)

@export var move_speed := 1.5
@export var run_speed := 2.0
@export var attack_interval := 5.0
@export var max_health := 1
@export var idle_wait_time := 5.0

var current_health: int
var last_hit_arrow_id: int = -1

@export var detection_radius: float = 7.0  # Default detection radius
@export var attack_radius: float = 5.0  # Default detection radius

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var enemyAnimationTree: AnimationTree = $enemy_skel/AnimationTree
@onready var detection_area: Area3D = $AreaOfDetection
@onready var detection_area_coll: CollisionShape3D = $AreaOfDetection/CollisionShape3D
@onready var attack_area: Area3D = $AreaOfAttack
@onready var arrow_spawn_point: Node3D = $ArrowSpawnPoint
@onready var synchronizer = $MultiplayerSynchronizer
@onready var idle_timer: Timer = $IdleTimer
@onready var attack_timer: Timer = $AttackTimer

enum State { IDLE, PURSUE, ATTACK }
var current_state: State = State.IDLE

var target_player: CharacterBody3D = null
var initial_position: Vector3
var players_in_detection: Array[CharacterBody3D] = []
var players_in_attack: Array[CharacterBody3D] = []

const EnemyArrow = preload("res://assets/scenes/enemyArrow.tscn")
@export var enemy_id: int = 0

@export var idle_position_threshold: float = 0.1  # Distance threshold to consider position reached
var patrol_area_size: float = 4.0  # Size of the square patrol area (4x4 meters)
var patrol_area_center: Vector3  # Center of the patrol area

# debug
var printed_messages = {}

func _ready():
	current_health = max_health
	set_multiplayer_authority(1)
	add_to_group("enemies")
	
	patrol_area_center = global_position
	
	synchronizer.set_multiplayer_authority(1)
	
	if is_multiplayer_authority():
		set_physics_process(true)
	else:
		set_physics_process(false)
	
	set_detection_radius(detection_radius)
	
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)
	
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	
	call_deferred("actor_setup")
	
	initial_position = global_position
	idle_timer.wait_time = idle_wait_time
	idle_timer.one_shot = true
	idle_timer.timeout.connect(_on_idle_timer_timeout)
	
	attack_timer.wait_time = attack_interval
	attack_timer.one_shot = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	
	if multiplayer.is_server():
		enemy_id = randi()

func actor_setup():
	await get_tree().physics_frame

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	
	match current_state:
		State.IDLE:
			handle_idle_state()
		State.PURSUE:
			handle_pursue_state()
		State.ATTACK:
			handle_attack_state()
	
	if not velocity == Vector3.ZERO:
		change_animation.rpc("walking")
	else:
		change_animation.rpc("idle")

	move_and_slide()

func set_detection_radius(radius: float):
	var shape = detection_area.get_node("CollisionShape3D")
	if shape and shape.shape is CylinderShape3D:
		shape.shape.radius = radius
		# print("Detection radius set to: " + str(radius))
	else:
		print("Error: DetectionArea should have a CollisionShape3D with a SphereShape3D")

func set_attack_radius(radius: float):
	var shape = attack_area.get_node("CollisionShape3D")
	if shape and shape.shape is CylinderShape3D:
		shape.shape.radius = radius
		# print("Detection radius set to: " + str(radius))
	else:
		print("Error: DetectionArea should have a CollisionShape3D with a SphereShape3D")

# Debug Trash, prints only once, duh
func print_once(message: String):
	if not printed_messages.has(message):
		print(message)
		printed_messages[message] = true

func handle_idle_state():
	if not nav_agent.is_navigation_finished():
		var next_position = nav_agent.get_next_path_position()
		var distance_to_next = global_position.distance_to(next_position)
		
		if distance_to_next > idle_position_threshold:
			velocity = (next_position - global_position).normalized() * move_speed
			look_at(global_position + velocity, Vector3.UP)
			# print_once("IDLE: Moving to next position")
		else:
			velocity = Vector3.ZERO
			# print_once("IDLE: Reached target position")
	elif idle_timer.is_stopped():
		velocity = Vector3.ZERO
		# print("IDLE: Setting new random target")
		set_random_idle_target()
	else:
		velocity = Vector3.ZERO
		# print_once("IDLE: Waiting at current position")

func handle_pursue_state():
	if target_player and players_in_detection.has(target_player):
		nav_agent.set_target_position(target_player.global_position)
		var next_position = nav_agent.get_next_path_position()
		velocity = (next_position - global_position).normalized() * run_speed
		look_at(global_position + velocity, Vector3.UP)
		
		# print_once("PURSUE: Moving towards player")
		
		if players_in_attack.has(target_player):
			# print("PURSUE: Player in attack range")
			enter_attack_state()
	else:
		# print("PURSUE: Lost player, entering idle state")
		enter_idle_state()

func handle_attack_state():
	if target_player and players_in_attack.has(target_player) and players_in_detection.has(target_player):
		look_at(target_player.global_position, Vector3.UP)
		velocity = Vector3.ZERO
		if attack_timer.is_stopped():
			# print("ATTACK: Shooting arrow")
			shoot_arrow()
			attack_timer.start()
	else:
		print("ATTACK: Lost target, entering idle state")
		enter_idle_state()

func enter_idle_state():
	current_state = State.IDLE
	target_player = null
	set_random_idle_target()
	set_detection_radius(detection_radius)
	set_attack_radius(attack_radius)
	play_subtract_aim_animation.rpc()
	# print_once("ENTER STATE: Idle")
	# print("Current position: " + str(global_position))

func enter_pursue_state(player: CharacterBody3D):
	current_state = State.PURSUE
	target_player = player
	set_detection_radius(detection_radius*2)
	set_attack_radius(attack_radius)
	# print_once("ENTER STATE: Pursue")
	# print("Target player position: " + str(player.global_position))

func enter_attack_state():
	current_state = State.ATTACK
	attack_timer.start()
	set_attack_radius(attack_radius*1.5)
	play_add_aim_animation.rpc()
	# print_once("ENTER STATE: Attack")
	# print("Attack timer started, duration: " + str(attack_timer.wait_time))

func set_random_idle_target():
	var random_x = randf_range(-patrol_area_size/2, patrol_area_size/2)
	var random_z = randf_range(-patrol_area_size/2, patrol_area_size/2)
	var random_point = Vector3(random_x, 0, random_z)
	var target_position = patrol_area_center + random_point
	nav_agent.set_target_position(target_position)
	idle_timer.start()
	
	# Create debug cube
	#create_debug_cube(target_position)
	#print("IDLE: New target set at " + str(target_position))

func create_debug_cube(position: Vector3):
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(.5, 3, .5)  # 0.5x3x0.5 meter cube
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = cube_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 0, 0.5)  # Semi-transparent red
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	
	mesh_instance.global_position = position
	get_tree().current_scene.add_child(mesh_instance)
	
	# Remove the cube after 5 seconds
	get_tree().create_timer(5.0).timeout.connect(func(): mesh_instance.queue_free())

func get_current_state() -> int:
	return current_state

func set_target_player(player: CharacterBody3D):
	target_player = player
	if current_state != State.ATTACK:
		enter_pursue_state(player)

func _on_idle_timer_timeout():
	set_random_idle_target()

func _on_detection_area_body_entered(body):
	if body is CharacterBody3D and body.name.is_valid_int():
		players_in_detection.append(body)
		if current_state == State.IDLE:
			enter_pursue_state(body)

func _on_detection_area_body_exited(body):
	if body is CharacterBody3D and body.name.is_valid_int():
		players_in_detection.erase(body)
		if players_in_detection.is_empty() and players_in_attack.is_empty():
			enter_idle_state()

func _on_attack_area_body_entered(body):
	if body is CharacterBody3D and body.name.is_valid_int():
		players_in_attack.append(body)
		if body == target_player and current_state == State.PURSUE:
			enter_attack_state()

func _on_attack_area_body_exited(body):
	if body is CharacterBody3D and body.name.is_valid_int():
		players_in_attack.erase(body)
		if body == target_player and current_state == State.ATTACK:
			if players_in_detection.has(target_player):
				enter_pursue_state(target_player)
			else:
				enter_idle_state()

func _on_attack_timer_timeout():
	if current_state == State.ATTACK and target_player and players_in_attack.has(target_player) and players_in_detection.has(target_player):
		shoot_arrow()
		attack_timer.start()

func shoot_arrow():
	rpc("spawn_arrow")


@rpc("call_local")
func spawn_arrow():
	var arrow = EnemyArrow.instantiate()
	arrow.global_transform = arrow_spawn_point.global_transform
	get_tree().root.add_child(arrow)
	arrow.initialize(arrow_spawn_point.global_transform, 20.0, self)

	# Play Reload Animation
	enemyAnimationTree.set("parameters/reloadTrigger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	enemyAnimationTree.set("parameters/reloadTrigger/active", true)
	
	if target_player:
		var direction = (target_player.global_position - arrow_spawn_point.global_position).normalized()
		arrow.look_at(arrow_spawn_point.global_position + direction, Vector3.UP)


@rpc("call_local")
func change_animation(animation_name):
	#current_animation = animation_name
	
	var anim_node_path = "parameters/%s" % animation_name
	enemyAnimationTree.set(anim_node_path, AnimationNodeAnimation.PLAY_MODE_BACKWARD)
	
	match animation_name:
		"idle":
			enemyAnimationTree.set("parameters/idleToWalk/blend_amount", 0)
		"walking":
			enemyAnimationTree.set("parameters/idleToWalk/blend_amount", 1)

	enemy_animation_changed.emit(animation_name)


@rpc("call_local")
func play_add_aim_animation():
	enemyAnimationTree.set("parameters/addAiming/add_amount", 1)

@rpc("call_local")
func play_subtract_aim_animation():
	enemyAnimationTree.set("parameters/addAiming/add_amount", 0)



@rpc("any_peer")
func receive_damage_request(damage: int, arrow_id: int):
	if not is_multiplayer_authority() or arrow_id == last_hit_arrow_id:
		return
		
	last_hit_arrow_id = arrow_id
	apply_damage(damage)

func apply_damage(damage: int):
	current_health -= damage
	# print("Enemy hit! Current health: ", current_health)
	
	rpc("update_health", current_health)
	
	if current_health <= 0:
		die()
	else:
		rpc("flash_hit")
		
	# Enter pursue state if hit by a player
	var attacker = get_tree().get_nodes_in_group("players").filter(func(player): return player.arrow_shooter_id == last_hit_arrow_id)
	if attacker.size() > 0:
		enter_pursue_state(attacker[0])

@rpc("call_local")
func update_health(new_health: int):
	current_health = new_health
	if current_health <= 0:
		remove_enemy()

func die():
	# print("Enemy ", enemy_id, " died!")
	rpc("remove_enemy")

@rpc("call_local")
func remove_enemy():
	queue_free()

@rpc("call_local")
func flash_hit():
	# Implement hit flash effect here
	pass
