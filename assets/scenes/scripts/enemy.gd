extends	CharacterBody3D

class_name Enemy

signal enemy_animation_changed(animation_name)

@export	var	move_speed := 1.5
@export	var	run_speed := 2
@export	var	attack_interval	:= 1
@export	var	max_health := 1
@export	var	idle_wait_time := 6.0

var	current_health:	int
var	last_hit_arrow_id: int = -1

@export	var	detection_radius: float	= 7.0  # Default detection radius
@export	var	attack_radius: float = 4.5	# Default detection	radius

@onready var los_check_timer: Timer	= $LOSCheckTimer

@onready var nav_agent:	NavigationAgent3D =	$NavigationAgent3D
@onready var enemyAnimationTree: AnimationTree = $enemy_skel/AnimationTree
@onready var enemyDeathAnimation: AnimationPlayer =	$enemy_skel/DeathAnimation
@onready var detection_area: Area3D	= $AreaOfDetection
@onready var detection_area_coll: CollisionShape3D = $AreaOfDetection/CollisionShape3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var attack_area: Area3D = $AreaOfAttack
@onready var arrow_spawn_point:	Node3D = $ArrowSpawnPoint
@onready var synchronizer =	$MultiplayerSynchronizer
@onready var idle_timer: Timer = $IdleTimer
@onready var attack_timer: Timer = $AttackTimer

# sound
@onready var idle_sounds = [$idleSkel1,	$idleSkel2,	$idleSkel3]
@onready var step_sounds = [$stepSound1, $stepSound2, $stepSound3, $stepSound4]
@onready var w_step_sounds = [$w_stepSound1, $w_stepSound2,	$w_stepSound3, $w_stepSound4]
@onready var surface_detector: RayCast3D = $SurfaceDetector
@onready var hugh_sound: AudioStreamPlayer3D =	$hugh
@onready var crossbow_shoot_sound: AudioStreamPlayer3D = $crossbowShoot
@onready var crossbow_reload_sound:	AudioStreamPlayer3D	= $crossbowReload

var	isDead = false

enum State { IDLE, PURSUE, ATTACK }
var	current_state: State = State.IDLE

var	target_player: CharacterBody3D = null
var	initial_position: Vector3
var	players_in_detection: Array[CharacterBody3D] = []
var	players_in_attack: Array[CharacterBody3D] =	[]

const EnemyArrow = preload("res://assets/scenes/enemyArrow.tscn")
@export	var	enemy_id: int =	0

@export	var	idle_position_threshold: float = 0.1  # Distance threshold to consider position	reached
var	patrol_area_size: float	= 4.0  # Size of the square	patrol area	(4x4 meters)
var	patrol_area_center:	Vector3	 # Center of the patrol	area

# debug
var	printed_messages = {}

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
	
	nav_agent.path_desired_distance	= 0.5
	nav_agent.target_desired_distance =	0.5
	
	call_deferred("actor_setup")
	
	initial_position = global_position
	idle_timer.wait_time = idle_wait_time
	idle_timer.one_shot	= true
	idle_timer.timeout.connect(_on_idle_timer_timeout)
	
	attack_timer.wait_time = attack_interval
	attack_timer.one_shot =	true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	
	# Set up step sound	timer
	var	step_sound_timer = Timer.new()
	step_sound_timer.name =	"StepSoundTimer"
	step_sound_timer.wait_time = 0.3  # Adjust this	value to change	step sound frequency
	step_sound_timer.one_shot =	true
	add_child(step_sound_timer)

	los_check_timer	= Timer.new()
	los_check_timer.name = "LOSCheckTimer"
	los_check_timer.wait_time =	1.0	 # Check every second
	los_check_timer.one_shot = false
	los_check_timer.timeout.connect(_on_los_check_timer_timeout)
	add_child(los_check_timer)

	if multiplayer.is_server():
		enemy_id = randi()
		print(" enemy spawned and I am assigning them an ID, it's: " + str(enemy_id))

func actor_setup():
	await get_tree().physics_frame

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	
	if isDead:
		return

	match current_state:
		State.IDLE:
			handle_idle_state()
		State.PURSUE:
			handle_pursue_state()
		State.ATTACK:
			handle_attack_state()
	
	if not velocity	== Vector3.ZERO:
		change_animation.rpc("walking")

		if not $StepSoundTimer.is_stopped():
			play_step_sound()
			$StepSoundTimer.start()
	else:
		change_animation.rpc("idle")

	move_and_slide()

func set_detection_radius(radius: float):
	var	shape =	detection_area.get_node("CollisionShape3D")
	if shape and shape.shape is CylinderShape3D:
		shape.shape.radius = radius
		# print("Detection radius set to: "	+ str(radius))
	else:
		print("Error: DetectionArea	should have	a CollisionShape3D with	a SphereShape3D")

func set_attack_radius(radius: float):
	var	shape =	attack_area.get_node("CollisionShape3D")
	if shape and shape.shape is CylinderShape3D:
		shape.shape.radius = radius
		# print("Detection radius set to: "	+ str(radius))
	else:
		print("Error: DetectionArea	should have	a CollisionShape3D with	a SphereShape3D")

# Debug	Trash, prints only once, duh
func print_once(message: String):
	if not printed_messages.has(message):
		print(message)
		printed_messages[message] =	true

func handle_idle_state():
	if not nav_agent.is_navigation_finished():
		var	next_position =	nav_agent.get_next_path_position()
		var	distance_to_next = global_position.distance_to(next_position)
		
		if distance_to_next	> idle_position_threshold:
			velocity = (next_position -	global_position).normalized() *	move_speed
			look_at(global_position	+ velocity,	Vector3.UP)
			# print_once("IDLE:	Moving to next position")
		else:
			velocity = Vector3.ZERO
			# print_once("IDLE:	Reached	target position")
	elif idle_timer.is_stopped():
		velocity = Vector3.ZERO
		# print("IDLE: Setting new random target")
		set_random_idle_target()
	else:
		velocity = Vector3.ZERO
		# print_once("IDLE:	Waiting	at current position")

func handle_pursue_state():
	if target_player and players_in_detection.has(target_player):
		nav_agent.set_target_position(target_player.global_position)
		var	next_position =	nav_agent.get_next_path_position()
		velocity = (next_position -	global_position).normalized() *	run_speed
		look_at(global_position	+ velocity,	Vector3.UP)
		
		# print_once("PURSUE: Moving towards player")
		
		if players_in_attack.has(target_player):
			# print("PURSUE: Player	in attack range")
			enter_attack_state()
	else:
		# print("PURSUE: Lost player, entering idle	state")
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
		print("ATTACK: Lost	target,	entering idle state")
		enter_idle_state()

func enter_idle_state():
	current_state =	State.IDLE
	target_player =	null
	set_random_idle_target()
	set_detection_radius(detection_radius)
	set_attack_radius(attack_radius)
	play_subtract_aim_animation.rpc()
	# print_once("ENTER	STATE: Idle")
	# print("Current position: " + str(global_position))

func enter_pursue_state(player:	CharacterBody3D):
	current_state =	State.PURSUE
	target_player =	player
	set_detection_radius(detection_radius*3)
	attack_timer.wait_time = attack_interval # resetting of the hacky way of making a quick initial attack
	#set_attack_radius(attack_radius)
	# print_once("ENTER	STATE: Pursue")
	# print("Target	player position: " + str(player.global_position))

func enter_attack_state():
	current_state =	State.ATTACK
	attack_timer.start()
	set_attack_radius(attack_radius*2)
	play_add_aim_animation.rpc()
	# print_once("ENTER	STATE: Attack")
	# print("Attack	timer started, duration: " + str(attack_timer.wait_time))

func set_random_idle_target():
	var	random_x = randf_range(-patrol_area_size/2,	patrol_area_size/2)
	var	random_z = randf_range(-patrol_area_size/2,	patrol_area_size/2)
	var	random_point = Vector3(random_x, 0, random_z)
	var	target_position	= patrol_area_center + random_point
	nav_agent.set_target_position(target_position)
	idle_timer.start()
	
	play_random_idle_sound()

	# Create debug cube
	#create_debug_cube(target_position)
	#print("IDLE: New target set at " +	str(target_position))

func create_debug_cube(position: Vector3):
	var	cube_mesh =	BoxMesh.new()
	cube_mesh.size = Vector3(.5, 3, .5)	 # 0.5x3x0.5 meter cube
	
	var	mesh_instance =	MeshInstance3D.new()
	mesh_instance.mesh = cube_mesh
	
	var	material = StandardMaterial3D.new()
	material.albedo_color =	Color(1, 0, 0, 0.5)	 # Semi-transparent	red
	material.transparency =	BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override	= material
	
	mesh_instance.global_position =	position
	get_tree().current_scene.add_child(mesh_instance)
	
	# Remove the cube after	5 seconds
	get_tree().create_timer(5.0).timeout.connect(func(): mesh_instance.queue_free())

func get_current_state() -> int:
	return current_state

# $$$ CHANGE $$$
# Checks if there's	a clear	line of sight to the target
func has_line_of_sight(target: CharacterBody3D)	-> bool:
	var	space_state	= get_world_3d().direct_space_state
	
	# Adjust the start and end positions to be at a	more appropriate height
	var	start_position = global_position + Vector3(0, 1.0, 0)  # Raise 1 meter from	the	ground
	var	end_position = target.global_position +	Vector3(0, 1.0,	0)	# Raise	1 meter	from the ground
	
	var	query =	PhysicsRayQueryParameters3D.create(start_position, end_position)
	query.collision_mask = 1  # Set	this to match your world geometry collision	layer
	query.collide_with_bodies =	true
	query.collide_with_areas = false
	query.exclude =	[self, target]	# Exclude the enemy	itself and the target from the check

	var	result = space_state.intersect_ray(query)
	#print("has line	of sight: "	+ str(result))

	return result.is_empty()  # If the result is empty,	there's	a clear	line of sight

func set_target_player(player: CharacterBody3D):
	target_player =	player
	if current_state != State.ATTACK:
		enter_pursue_state(player)

func _on_idle_timer_timeout():
	set_random_idle_target()

func _on_detection_area_body_entered(body):
	if body	is CharacterBody3D and body.name.is_valid_int():
		if has_line_of_sight(body):
			players_in_detection.append(body)
			if current_state == State.IDLE:
				enter_pursue_state(body)
		else:
			# Start	a timer	to periodically	check for line of sight
			start_los_check_timer(body)

# Starts the timer for checking	line of sight
func start_los_check_timer(body: CharacterBody3D):
	los_check_timer.start()
	# Store	the	body we're checking	for
	los_check_timer.set_meta("target_body",	body)

# Called when the LOS check	timer times	out
func _on_los_check_timer_timeout():
	var	body = los_check_timer.get_meta("target_body")
	if body	and	is_instance_valid(body)	and	has_line_of_sight(body):
		players_in_detection.append(body)
		if current_state == State.IDLE:
			enter_pursue_state(body)
		los_check_timer.stop()
	elif not detection_area.overlaps_body(body):
		# If the body is no longer in the detection	area, stop checking
		los_check_timer.stop()

func _on_detection_area_body_exited(body):
	if body	is CharacterBody3D and body.name.is_valid_int():
		players_in_detection.erase(body)
		if players_in_detection.is_empty() and players_in_attack.is_empty():
			enter_idle_state()
		
		# Stop the LOS check timer if it's running for this	body
		if los_check_timer.is_stopped()	== false and los_check_timer.get_meta("target_body") == body:
			los_check_timer.stop()

func _on_attack_area_body_entered(body):
	if body	is CharacterBody3D and body.name.is_valid_int():
		players_in_attack.append(body)
		if body	== target_player and current_state == State.PURSUE:
			enter_attack_state()

func _on_attack_area_body_exited(body):
	if body	is CharacterBody3D and body.name.is_valid_int():
		players_in_attack.erase(body)
		if body	== target_player and current_state == State.ATTACK:
			if players_in_detection.has(target_player):
				enter_pursue_state(target_player)
			else:
				enter_idle_state()

func _on_attack_timer_timeout():
	if current_state == State.ATTACK and target_player and players_in_attack.has(target_player)	and	players_in_detection.has(target_player):
		shoot_arrow()
		attack_timer.wait_time = attack_interval * 5 # Don't be alarmed, this is so you can get that initial fast attack
		attack_timer.start()

func shoot_arrow():
	hugh_sound.play()
	if not multiplayer.is_server():
		return
	
	await get_tree().create_timer(1).timeout

	rpc("spawn_arrow", enemy_id)
	play_crossbow_shoot_sound()


@rpc("call_local")
func spawn_arrow(arr_id):
	var	arrow =	EnemyArrow.instantiate()
	arrow.global_transform = arrow_spawn_point.global_transform
	get_tree().root.add_child(arrow)
	arrow.initialize(arrow_spawn_point.global_transform, 20.0, self)

	# Play Reload Animation
	enemyAnimationTree.set("parameters/reloadTrigger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	enemyAnimationTree.set("parameters/reloadTrigger/active", true)
	play_crossbow_reload_sound()
	
	if target_player:
		var	direction =	(target_player.global_position - arrow_spawn_point.global_position).normalized()
		arrow.look_at(arrow_spawn_point.global_position	+ direction, Vector3.UP)


@rpc("call_local")
func change_animation(animation_name):
	#current_animation = animation_name
	
	var	anim_node_path = "parameters/%s" % animation_name
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

@rpc("call_local")
func play_add_die_animation():
	enemyAnimationTree.set("parameters/addDie/add_amount", 1)

@rpc("call_local")
func play_subtract_die_animation():
	enemyAnimationTree.set("parameters/addDie/add_amount", 0)


@rpc("any_peer")
func receive_damage_request(damage:	int, arrow_id: int):
	if not is_multiplayer_authority() or arrow_id == last_hit_arrow_id:
		return
		
	last_hit_arrow_id =	arrow_id
	apply_damage(damage)


func apply_damage(damage: int):
	current_health -= damage
	# print("Enemy hit!	Current	health:	", current_health)
	
	rpc("update_health_and_die", current_health)

	# Enter	pursue state if hit	by a player
	var	attacker = get_tree().get_nodes_in_group("players").filter(func(player): return	player.arrow_shooter_id	== last_hit_arrow_id)
	if attacker.size() > 0:
		enter_pursue_state(attacker[0])

@rpc("call_local")
func update_health_and_die(new_health: int):
	current_health = new_health
	if current_health <= 0:
		# Die
		enemyAnimationTree.get_tree().paused = false
		enemyDeathAnimation.play("die")
		
		change_animation.rpc("idle")
		enemyAnimationTree.set("parameters/idleTimeScale/scale", 0)
		enemyAnimationTree.set("parameters/reloadTrigger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		enemyAnimationTree.set("parameters/reloadTrigger/active", false)
		
		collision_shape.disabled = true
		detection_area.body_entered.disconnect(_on_detection_area_body_entered)
		detection_area.body_exited.disconnect(_on_detection_area_body_exited)
		attack_area.body_entered.disconnect(_on_attack_area_body_entered)
		attack_area.body_exited.disconnect(_on_attack_area_body_exited)
		attack_timer.timeout.disconnect(_on_attack_timer_timeout)
		idle_timer.timeout.disconnect(_on_attack_timer_timeout)
		isDead = true
		play_add_die_animation.rpc()
		play_subtract_aim_animation.rpc()

		#queue_free()


# $$$ ADD $$$
# Plays	a random step sound	based on the surface type
func play_step_sound():
	var	sound_array	= w_step_sounds	if is_on_water() else step_sounds
	var	random_sound_index = randi() % sound_array.size()
	sound_array[random_sound_index].play()

# $$$ ADD $$$
# Checks if the	enemy is on water
func is_on_water() -> bool:
	if surface_detector.is_colliding():
		var	collider = surface_detector.get_collider()
		if collider	is StaticBody3D:
			var	parent = collider.get_parent()
			if parent is MeshInstance3D	and	parent.name.to_lower() == "water":
				return true
	return false


# Plays	the	crossbow shoot sound
func play_crossbow_shoot_sound():
	crossbow_shoot_sound.play()

# Plays	the	crossbow reload	sound
func play_crossbow_reload_sound():
	crossbow_reload_sound.play()

# Plays	a random idle sound
func play_random_idle_sound():
	if not idle_sounds.is_empty() and not isDead:
		var	random_sound_index = randi() % idle_sounds.size()
		idle_sounds[random_sound_index].play()