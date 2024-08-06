extends CharacterBody3D

signal health_changed(health_value)
signal player_animation_changed(animation_name)

@onready var camera = $Camera3D
@onready var anim_player = $AnimationPlayer
@onready var blood_splat = $blood
@onready var raycast = $Camera3D/RayCast3D
@onready var PlayerModelAnimationTree = $PlayerModel/PlayerModelAnimationTree
@onready var PlayerMesh = $PlayerModel/Armature/Skeleton3D/CharacterMesh
@onready var step_sounds = [$stepSound1, $stepSound2, $stepSound3, $stepSound4]
var current_step_sound = 0
var step_distance = 2  # Distance between steps
var step_run_distance = 1.5
var distance_since_last_step = 0.0

# keys
var keys = 0
@onready var interaction_ray = $Camera3D/InteractionRay

# knife attack
@export var melee_range := 2.0  # The reach of the melee attack
@export var melee_arc_angle := 60.0  # The arc angle of the attack in degrees
@export var melee_raycast_count := 5  # Number of raycasts to use for detection

var melee_cooldown := 0.5  # Time between attacks
var can_attack := true

var health = 3
const SPEED = 3.0
const SPRINT_SPEED = 5.0
const JUMP_VELOCITY = 8.0
var current_speed = SPEED
var gravity = 20.0
var current_animation = "idle"

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready():
	if not is_multiplayer_authority():
		PlayerMesh.set_layer_mask_value(1, 1)
		PlayerMesh.set_layer_mask_value(2, 0)
		return
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	
func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * .005)
		camera.rotate_x(-event.relative.y * .005)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	if Input.is_action_just_pressed("interact"):  # Assuming "interact" is mapped to "F"
		check_door_interaction()
	
	if Input.is_action_just_pressed("shoot") and can_attack:
		perform_melee_attack()
		#play_shoot_effects.rpc()
		#play_slash_animation.rpc()
		#if raycast.is_colliding():
			#var hit_player = raycast.get_collider()
			#hit_player.receive_damage.rpc_id(hit_player.get_multiplayer_authority())

func collect_key():
	keys += 1
	print("Player %s now has %d keys" % [name, keys])

func check_door_interaction():
	print("Checking door interaction")
	if interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()
		print("Collider: ", collider.name)
		if collider.is_in_group("doors"):
			print("Trying to open door")
			collider.try_open(self)
		else:
			print("Collider is not a door")
	else:
		print("Ray is not colliding with anything")

func perform_melee_attack():
	if not is_multiplayer_authority(): return
	
	can_attack = false
	play_shoot_effects.rpc()
	play_slash_animation.rpc()
	
	var space_state = get_world_3d().direct_space_state
	var camera_global_position = camera.global_position
	
	for i in range(melee_raycast_count):
		var angle = deg_to_rad(melee_arc_angle * (i / float(melee_raycast_count - 1) - 0.5))
		var direction = -camera.global_transform.basis.z.rotated(camera.global_transform.basis.y, angle)
		var end_point = camera_global_position + direction * melee_range
		
		var query = PhysicsRayQueryParameters3D.create(camera_global_position, end_point)
		query.collision_mask = 2  # Adjust based on your collision layers
		var result = space_state.intersect_ray(query)
		
		if result and result.collider.has_method("receive_melee_damage"):
			result.collider.receive_melee_damage.rpc_id(result.collider.get_multiplayer_authority())
			break  # Exit after first hit
	
	await get_tree().create_timer(melee_cooldown).timeout
	can_attack = true

@rpc("any_peer")
func receive_melee_damage():
	health -= 1
	play_blood_splat_effects.rpc()
	if health <= 0:
		health = 3
		position = Vector3.ZERO
	health_changed.emit(health)

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if is_on_floor() and (velocity.x != 0 or velocity.z != 0) and Input.is_action_pressed("sprint") != true:
		distance_since_last_step += velocity.length() * delta
		if distance_since_last_step >= step_distance:
			rpc("play_step_sound")
			distance_since_last_step = 0.0
	if is_on_floor() and (velocity.x != 0 or velocity.z != 0) and Input.is_action_pressed("sprint"):
		distance_since_last_step += velocity.length() * delta
		if distance_since_last_step >= step_run_distance:
			rpc("play_step_sound")
			distance_since_last_step = 0.0
	
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	
	if Input.is_action_pressed("sprint"):
		current_speed = SPRINT_SPEED
	else:
		current_speed = SPEED
	
	update_animation(input_dir)
	
	move_and_slide()
	
	# This will prevent walking through other players
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_collider() is CharacterBody3D:
			# If we collide with another player, zero out our horizontal velocity
			velocity.x = 0
			velocity.z = 0

@rpc("call_local")
func play_step_sound():
	step_sounds[current_step_sound].play()
	current_step_sound = (current_step_sound + 1) % step_sounds.size()

func update_animation(input_dir):
	var new_animation = current_animation
	var forward_direction = -global_transform.basis.z
	var movement_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	var is_moving_backwards = forward_direction.dot(movement_direction) > 0
	#print("moving backwards = " + str(is_moving_backwards))
	
	if input_dir == Vector2.ZERO:
		new_animation = "idle"
	elif current_speed == SPRINT_SPEED:
		new_animation = "run"
	else:
		new_animation = "walk"
	
	if new_animation != current_animation and is_multiplayer_authority():
		change_animation.rpc(new_animation)

@rpc("call_local")
func change_animation(animation_name):
	current_animation = animation_name
	
	var anim_node_path = "parameters/%s" % animation_name
	PlayerModelAnimationTree.set(anim_node_path, AnimationNodeAnimation.PLAY_MODE_BACKWARD)
	
	match animation_name:
		"idle":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
		"walk":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 1)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
		"run":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 1)
		"slash":
			PlayerModelAnimationTree.set("parameters/playSlash2/active", true)
			
	player_animation_changed.emit(animation_name)

@rpc("call_local")
func play_slash_animation():
	PlayerModelAnimationTree.set("parameters/playSlash/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	PlayerModelAnimationTree.set("parameters/playSlash/active", true)

@rpc("call_local") 
func play_shoot_effects():
	anim_player.stop()
	anim_player.play("shoot")

@rpc("call_local") 
func play_blood_splat_effects():
	blood_splat.restart()
	#blood_splat.position = pos
	blood_splat.emitting = true

func _on_animation_player_animation_finished(anim_name):
	if anim_name == "shoot":
		anim_player.play("idle")
