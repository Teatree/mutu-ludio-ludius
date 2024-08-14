extends CharacterBody3D

class_name Enemy

@export var move_speed := 2.0
@export var attack_interval := 5.0
@export var max_health := 2
@export var attack_range := 10.0
@export var idle_move_radius := 5.0
@export var move_wait_time := 3.0
@export var minimum_distance := 5.0  # Minimum distance to keep from the player
@export var return_delay := 4.0  # Delay before returning to original position

var current_health: int
var last_hit_arrow_id: int = -1

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection_area: Area3D = $AreaOfDetection
@onready var attack_area: Area3D = $AreaOfAttack
@onready var arrow_spawn_point: Node3D = $ArrowSpawnPoint
@onready var synchronizer = $MultiplayerSynchronizer
@onready var move_wait_timer: Timer = $MoveWaitTimer
@onready var return_timer: Timer = $ReturnTimer

enum State { IDLE, PURSUE, ATTACK, RETURNING }
var current_state: State = State.IDLE

var target_player: CharacterBody3D = null
var time_since_last_attack := 0.0
var initial_position: Vector3
var players_in_detection: Array[CharacterBody3D] = []

const EnemyArrow = preload("res://assets/scenes/enemyArrow.tscn")
@export var enemy_id: int = 0

# $$$ CHANGE $$$
func _ready():
	current_health = max_health
	set_multiplayer_authority(1)
	add_to_group("enemies")
	
	synchronizer.set_multiplayer_authority(1)
	
	if is_multiplayer_authority():
		set_physics_process(true)
	else:
		set_physics_process(false)
	
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.body_exited.connect(_on_attack_area_body_exited)
	
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	
	call_deferred("actor_setup")
	
	initial_position = global_position
	move_wait_timer.wait_time = move_wait_time
	move_wait_timer.one_shot = true
	move_wait_timer.timeout.connect(_on_move_wait_timer_timeout)
	
	return_timer.wait_time = return_delay
	return_timer.one_shot = true
	return_timer.timeout.connect(_on_return_timer_timeout)
	
	if multiplayer.is_server():
		enemy_id = randi()

func actor_setup():
	await get_tree().physics_frame

# $$$ CHANGE $$$
func _physics_process(delta):
	if not multiplayer.is_server():
		return
	
	match current_state:
		State.IDLE:
			handle_idle_state()
		State.PURSUE:
			handle_pursue_state()
		State.ATTACK:
			handle_attack_state(delta)
		State.RETURNING:
			handle_returning_state()
	
	move_and_slide()

func handle_idle_state():
	if not nav_agent.is_navigation_finished():
		var next_position = nav_agent.get_next_path_position()
		var new_velocity = (next_position - global_position).normalized() * move_speed
		velocity = new_velocity
		look_at(global_position + new_velocity, Vector3.UP)
	elif move_wait_timer.is_stopped():
		move_wait_timer.start()

# $$$ CHANGE $$$
func handle_pursue_state():
	if target_player and players_in_detection.has(target_player):
		var distance_to_player = global_position.distance_to(target_player.global_position)
		if distance_to_player > minimum_distance:
			nav_agent.set_target_position(target_player.global_position)
			var next_position = nav_agent.get_next_path_position()
			var new_velocity = (next_position - global_position).normalized() * move_speed
			velocity = new_velocity
			look_at(global_position + new_velocity, Vector3.UP)
		else:
			velocity = Vector3.ZERO
			look_at(target_player.global_position, Vector3.UP)
			enter_attack_state()
	else:
		start_return_timer()

func handle_attack_state(delta):
	if target_player and players_in_detection.has(target_player):
		look_at(target_player.global_position, Vector3.UP)
		time_since_last_attack += delta
		if time_since_last_attack >= attack_interval:
			shoot_arrow()
			time_since_last_attack = 0
	else:
		start_return_timer()

# $$$ ADDED $$$
func handle_returning_state():
	nav_agent.set_target_position(initial_position)
	if not nav_agent.is_navigation_finished():
		var next_position = nav_agent.get_next_path_position()
		var new_velocity = (next_position - global_position).normalized() * move_speed
		velocity = new_velocity
		look_at(global_position + new_velocity, Vector3.UP)
	else:
		enter_idle_state()

func enter_idle_state():
	current_state = State.IDLE
	set_random_navigation_target()

# $$$ CHANGE $$$
func enter_pursue_state(player: CharacterBody3D):
	current_state = State.PURSUE
	target_player = player
	return_timer.stop()

func enter_attack_state():
	current_state = State.ATTACK
	velocity = Vector3.ZERO

# $$$ ADDED $$$
func enter_returning_state():
	current_state = State.RETURNING
	target_player = null

func set_random_navigation_target():
	var random_point = Vector3(randf_range(-idle_move_radius, idle_move_radius), 0, randf_range(-idle_move_radius, idle_move_radius))
	var target_position = initial_position + random_point
	nav_agent.set_target_position(target_position)

func get_current_state() -> int:
	return current_state

func set_target_player(player: CharacterBody3D):
	target_player = player
	if current_state != State.ATTACK:
		enter_pursue_state(player)

func _on_move_wait_timer_timeout():
	set_random_navigation_target()

# $$$ CHANGE $$$
func _on_detection_area_body_entered(body):
	if body is CharacterBody3D and body.name.is_valid_int():
		players_in_detection.append(body)
		if current_state == State.IDLE or current_state == State.RETURNING:
			enter_pursue_state(body)

# $$$ CHANGE $$$
func _on_detection_area_body_exited(body):
	if body is CharacterBody3D and body.name.is_valid_int():
		players_in_detection.erase(body)
		if players_in_detection.is_empty():
			start_return_timer()

func _on_attack_area_body_entered(body):
	if body == target_player:
		enter_attack_state()

# $$$ CHANGE $$$
func _on_attack_area_body_exited(body):
	if body == target_player and players_in_detection.has(target_player):
		enter_pursue_state(target_player)

# $$$ ADDED $$$
func start_return_timer():
	if current_state != State.RETURNING:
		return_timer.start()

# $$$ ADDED $$$
func _on_return_timer_timeout():
	enter_returning_state()

func shoot_arrow():
	rpc("spawn_arrow")

@rpc("call_local")
func spawn_arrow():
	var arrow = EnemyArrow.instantiate()
	arrow.global_transform = arrow_spawn_point.global_transform
	get_tree().root.add_child(arrow)
	arrow.initialize(arrow_spawn_point.global_transform, 20.0, self)
	
	if target_player:
		var direction = (target_player.global_position - arrow_spawn_point.global_position).normalized()
		arrow.look_at(arrow_spawn_point.global_position + direction, Vector3.UP)

@rpc("any_peer")
func receive_damage_request(damage: int, arrow_id: int):
	if not is_multiplayer_authority() or arrow_id == last_hit_arrow_id:
		return
		
	last_hit_arrow_id = arrow_id
	apply_damage(damage)

func apply_damage(damage: int):
	current_health -= damage
	print("Enemy hit! Current health: ", current_health)
	
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
