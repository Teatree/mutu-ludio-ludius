extends CharacterBody3D

signal health_changed(health_value)
signal player_animation_changed(animation_name)

@export_category("Character")
@export var base_speed : float = 2.5
@export var sprint_speed : float = 3.5
@export var crouch_speed : float = 1.0

@export var acceleration : float = 10.0
@export var jump_velocity : float = 4.5
@export var mouse_sensitivity : float = 0.1
@export var immobile : bool = false
@export_file var default_reticle


@export_group("Nodes")
@export var HEAD : Node3D
@export var CAMERA : Camera3D
@export var HEADBOB_ANIMATION : AnimationPlayer
@export var JUMP_ANIMATION : AnimationPlayer
@export var CROUCH_ANIMATION : AnimationPlayer
@export var COLLISION_MESH : CollisionShape3D

@export_group("Controls")
# We are using UI controls because they are built into Godot Engine so they can be used right away
@export var JUMP : String = "ui_accept"
@export var LEFT : String = "left"
@export var RIGHT : String = "right"
@export var FORWARD : String = "up"
@export var BACKWARD : String = "down"
@export var PAUSE : String = "ui_cancel"
@export var CROUCH : String = "crouch"
@export var SPRINT : String = "sprint"

@export_group("Feature Settings")
@export var jumping_enabled : bool = true
@export var in_air_momentum : bool = true
@export var motion_smoothing : bool = true
@export var sprint_enabled : bool = true
@export var crouch_enabled : bool = true
@export_enum("Hold to Crouch", "Toggle Crouch") var crouch_mode : int = 0
@export_enum("Hold to Sprint", "Toggle Sprint") var sprint_mode : int = 0
@export var dynamic_fov : bool = true
@export var continuous_jumping : bool = true
@export var view_bobbing : bool = true
@export var jump_animation : bool = true
@export var pausing_enabled : bool = true
@export var gravity_enabled : bool = true

@export var reload_time : float = 3.0  # Time it takes to reload in seconds
@onready var reload_timer : Timer = Timer.new()
var is_loaded : bool = true  # Start with a loaded crossbow
var arrow_shoot_count: int = 0
var arrow_shooter_id: int = 0

@export var respawn_time : float = 3.0  # Time before respawn after death
@onready var respawn_timer : Timer = Timer.new()
var is_dead : bool = false

@export var Arrow: PackedScene
@export var arrow_speed = 20
@export var arrow_lifetime = 10

var last_hit_arrow_id: int = -1

@export var death_model_scene: PackedScene  # Set this in the inspector
var death_model: Node3D = null

# Member variables
const SPEED = 3.0
const SPRINT_SPEED = 5.0

var health = 2
var can_attack := true
var stamina = 100
const STAMINA_COOLDOWN = 2
@onready var stamina_cooldown_timer : Timer = Timer.new()
var is_recover_stamina = false 
const STAMINA_REC_COST = 0.5
const STAMINA_RUN_COST = 0.4
const STAMINA_JUMP_COST = 2

@onready var crossBow_AnimPlayer = $Head/crossbow/crossbowAnimation
@onready var arrow_AnimPlayer = $Head/crossbow/arrowAnimation
@onready var raycast = $Head/Camera/RayCast3D
@onready var PlayerModel = $PlayerModel
@onready var PlayerSkeleton = $PlayerModel/Armature/Skeleton3D
#animation bs
var spine
var pose

@onready var PlayerModelAnimationTree = $PlayerModel/PlayerModelAnimationTree
@onready var PlayerMesh = $PlayerModel/Armature/Skeleton3D/CharacterMesh_1
@onready var PlayerMesh_skin = $PlayerModel/Armature/Skeleton3D/CharacterMesh_1/CharacterMesh_skin_1

@onready var PlayerCollision = $Collision
@onready var crossbow_fps = $Head/crossbow/Armature/Skeleton3D/crossbow
@onready var arrow_fps = $Head/crossbow/arrow
@onready var crossbow_local = $PlayerModel/Armature/Skeleton3D/BoneAttachment3D/crossbow
@onready var step_sounds = [$stepSound1, $stepSound2, $stepSound3, $stepSound4]
@onready var w_step_sounds = [$w_stepSound1, $w_stepSound2, $w_stepSound3, $w_stepSound4]
@onready var surface_detector: RayCast3D = $SurfaceDetector
@onready var splat_sound: AudioStreamPlayer3D = $splat
@onready var crossbowReload_sounds = $crossbowReload
@onready var crossbowShoot_sounds = $crossbowShoot
var current_step_sound = 0
var step_distance = 2  # Distance between steps
var step_run_distance = 1.5
var distance_since_last_step = 0.0

# ui
@onready var ui_AnimPlayer = $UserInterface/uiAnimation
@onready var ui_root = $UserInterface
@onready var ui_stamina_bar = $UserInterface/Stamina/StaminaBar
@onready var ui_key_count = $UserInterface/key_count

# keys
var keys = 0
@onready var interaction_ray = $Head/Camera/InteractionRay

var current_animation = "idle"
var target_blend_amounts = {
	"idleToWalk2": 0.0,
	"walkToRun2": 0.0,
	"walkToCrouch": 0.0,
	"crouchIdleToWalk": 0.0
}
var current_blend_amounts = target_blend_amounts.duplicate()
const BLEND_SPEED = 5.0  # Adjust this value to change how fast the blending occurs

var speed : float = base_speed
var current_speed : float = SPEED
# States: normal, crouching, sprinting
var state : String = "normal"
var low_ceiling : bool = false # This is for when the cieling is too low and the player needs to crouch.
var was_on_floor : bool = true # Was the player on the floor last frame (for landing animation)

var RETICLE : Control
var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity") # Don't set this as a const, see the gravity section in _physics_process

var mouseInput : Vector2 = Vector2(0,0)

var accumulated_rotation_x = 0.0

var head_rotation_x

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready():
	CAMERA.current = false
	if not is_multiplayer_authority():
		PlayerMesh.set_layer_mask_value(1, 1)
		PlayerMesh.set_layer_mask_value(2, 0)
		PlayerMesh_skin.set_layer_mask_value(1, 1)
		PlayerMesh_skin.set_layer_mask_value(2, 0)
		
		crossbow_fps.set_layer_mask_value(1, 0)
		crossbow_fps.set_layer_mask_value(2, 1)
		arrow_fps.set_layer_mask_value(1, 0)
		arrow_fps.set_layer_mask_value(2, 1)
		
		crossbow_local.set_layer_mask_value(1, 1)
		crossbow_local.set_layer_mask_value(2, 0)
		return
	
	add_to_group("players")
	print("Player added to 'players' group")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	ui_root.visible = true
	
	head_rotation_x = -HEAD.rotation.x + 105
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	CAMERA.current = true
	
	# If the controller is rotated in a certain direction for game design purposes, redirect this rotation into the head.
	HEAD.rotation.y = rotation.y
	rotation.y = 0
	
	if default_reticle:
		change_reticle(default_reticle)
	
	# Reset the camera position
	# If you want to change the default head height, change these animations.
	HEADBOB_ANIMATION.play("RESET")
	JUMP_ANIMATION.play("RESET")
	CROUCH_ANIMATION.play("RESET")
	
	check_controls()
	
	reload_timer.one_shot = true
	reload_timer.wait_time = reload_time
	reload_timer.connect("timeout", Callable(self, "_on_reload_complete"))
	add_child(reload_timer)
	
	respawn_timer.one_shot = true
	respawn_timer.wait_time = respawn_time
	respawn_timer.connect("timeout", Callable(self, "_on_respawn"))
	add_child(respawn_timer)
	
	stamina_cooldown_timer.one_shot = true
	stamina_cooldown_timer.wait_time = STAMINA_COOLDOWN
	stamina_cooldown_timer.connect("timeout", Callable(self, "_on_stamina_cooldown_complete"))
	add_child(stamina_cooldown_timer)

func check_controls(): # If you add a control, you might want to add a check for it here.
	# The actions are being disabled so the engine doesn't halt the entire project in debug mode
	if !InputMap.has_action(JUMP):
		push_error("No control mapped for jumping. Please add an input map control. Disabling jump.")
		jumping_enabled = false
	if !InputMap.has_action(LEFT):
		push_error("No control mapped for move left. Please add an input map control. Disabling movement.")
		immobile = true
	if !InputMap.has_action(RIGHT):
		push_error("No control mapped for move right. Please add an input map control. Disabling movement.")
		immobile = true
	if !InputMap.has_action(FORWARD):
		push_error("No control mapped for move forward. Please add an input map control. Disabling movement.")
		immobile = true
	if !InputMap.has_action(BACKWARD):
		push_error("No control mapped for move backward. Please add an input map control. Disabling movement.")
		immobile = true
	if !InputMap.has_action(PAUSE):
		push_error("No control mapped for pause. Please add an input map control. Disabling pausing.")
		pausing_enabled = false
	if !InputMap.has_action(CROUCH):
		push_error("No control mapped for crouch. Please add an input map control. Disabling crouching.")
		crouch_enabled = false
	if !InputMap.has_action(SPRINT):
		push_error("No control mapped for sprint. Please add an input map control. Disabling sprinting.")
		sprint_enabled = false


func change_reticle(reticle): # Yup, this function is kinda strange
	if not is_multiplayer_authority(): return
	if RETICLE:
		RETICLE.queue_free()
	
	RETICLE = load(reticle).instantiate()
	RETICLE.character = self
	$UserInterface.add_child(RETICLE)


func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	handle_head_rotation()
	
	if is_dead: return
	
	current_speed = Vector3.ZERO.distance_to(get_real_velocity())
	$UserInterface/DebugPanel.add_property("Speed", snappedf(current_speed, 0.001), 1)
	$UserInterface/DebugPanel.add_property("Target speed", speed, 2)
	var cv : Vector3 = get_real_velocity()
	var vd : Array[float] = [
		snappedf(cv.x, 0.001),
		snappedf(cv.y, 0.001),
		snappedf(cv.z, 0.001)
	]
	var readable_velocity : String = "X: " + str(vd[0]) + " Y: " + str(vd[1]) + " Z: " + str(vd[2])
	$UserInterface/DebugPanel.add_property("Velocity", readable_velocity, 3)
	
	PlayerModel.rotation.y = HEAD.rotation.y
	var isWalkingOrRunning = HEADBOB_ANIMATION.current_animation == "walk" or HEADBOB_ANIMATION.current_animation == "sprinting"
	change_bone_rot.rpc(isWalkingOrRunning)
	
	# Gravity
	#gravity = ProjectSettings.get_setting("physics/3d/default_gravity") # If the gravity changes during your game, uncomment this code
	if not is_on_floor() and gravity and gravity_enabled:
		velocity.y -= gravity * delta
	
	handle_jumping()
	
	var input_dir = Vector2.ZERO
	if !immobile: # Immobility works by interrupting user input, so other forces can still be applied to the player
		input_dir = Input.get_vector(LEFT, RIGHT, FORWARD, BACKWARD)
	handle_movement(delta, input_dir)
	
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
	
	# The player is not able to stand up if the ceiling is too low
	low_ceiling = $CrouchCeilingDetection.is_colliding()
	
	handle_state(input_dir)
	if dynamic_fov: # This may be changed to an AnimationPlayer
		update_camera_fov()
	
	if view_bobbing:
		headbob_animation(input_dir)
	
	if jump_animation:
		if !was_on_floor and is_on_floor(): # The player just landed
			match randi() % 2: #TODO: Change this to detecting velocity direction
				0:
					JUMP_ANIMATION.play("land_left", 0.25)
				1:
					JUMP_ANIMATION.play("land_right", 0.25)
	
	was_on_floor = is_on_floor() # This must always be at the end of physics_process
	
	update_animation(input_dir)

func handle_jumping():
	if jumping_enabled:
		
		if continuous_jumping: # Hold down the jump button
			if Input.is_action_pressed(JUMP) and is_on_floor() and !low_ceiling:
				if jump_animation:
					JUMP_ANIMATION.play("jump", 0.25)
					stamina -= STAMINA_JUMP_COST
					stamina_cooldown_timer.stop()
				velocity.y += jump_velocity # Adding instead of setting so jumping on slopes works properly
				is_recover_stamina = false
				stamina_cooldown_timer.stop()
		else:
			if Input.is_action_just_pressed(JUMP) and is_on_floor() and !low_ceiling:
				if jump_animation:
					JUMP_ANIMATION.play("jump", 0.25)
				velocity.y += jump_velocity


func handle_movement(delta, input_dir):
	var direction = input_dir.rotated(-HEAD.rotation.y)
	direction = Vector3(direction.x, 0, direction.y)
	move_and_slide()
	
	if in_air_momentum:
		if is_on_floor():
			if motion_smoothing:
				velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
				velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
			else:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
	else:
		if motion_smoothing:
			velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
		else:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed

func handle_head_rotation():
	HEAD.rotation_degrees.y -= mouseInput.x * mouse_sensitivity
	HEAD.rotation_degrees.x -= mouseInput.y * mouse_sensitivity
	
	mouseInput = Vector2.ZERO
	HEAD.rotation.x = clamp(HEAD.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
@rpc("call_local")
func change_bone_rot(isWalkingOrRunning):
	spine = PlayerSkeleton.find_bone("mixamorig_Spine")
	pose = PlayerSkeleton.get_bone_global_pose_no_override(spine)
	
	var rotation_quaternion_y
	if isWalkingOrRunning == true:
		head_rotation_x = -HEAD.rotation.x - 1.6
		rotation_quaternion_y = Quaternion(Vector3(0, 0, 1), 0.6)
		#print("this " + str(isWalkingOrRunning))
	elif isWalkingOrRunning == false:
		head_rotation_x = -HEAD.rotation.x - 1.6
		rotation_quaternion_y = Quaternion(Vector3(0, 0, 1), 0.6)
	
	var rotation_quaternion_x = Quaternion(Vector3(1, 0, 0), head_rotation_x)
	var combined_rotation = rotation_quaternion_y * rotation_quaternion_x 
	var new_basis = Basis(combined_rotation)
	pose.basis = new_basis

	PlayerSkeleton.set_bone_global_pose_override(spine, pose, 1.0, true)

func handle_state(moving):
	if crouch_enabled:
		if crouch_mode == 0:
			if Input.is_action_pressed(CROUCH) and state != "sprinting":
				if state != "crouching":
					enter_crouch_state()
			elif state == "crouching" and !$CrouchCeilingDetection.is_colliding():
				enter_normal_state()
		elif crouch_mode == 1:
			if Input.is_action_just_pressed(CROUCH):
				match state:
					"normal":
						enter_crouch_state()
					"crouching":
						if !$CrouchCeilingDetection.is_colliding():
							enter_normal_state()
	
	if stamina <= 0:
		enter_normal_state()
	else:
		if state == "sprinting":
			stamina -= STAMINA_RUN_COST
			is_recover_stamina = false
			stamina_cooldown_timer.stop()
		
		if sprint_enabled:
			if sprint_mode == 0:
				if Input.is_action_pressed(SPRINT) and state != "crouching":
					if moving:
						if state != "sprinting" and stamina > 0:
							enter_sprint_state()
					else:
						if state == "sprinting":
							enter_normal_state()
				elif state == "sprinting":
					enter_normal_state()
			elif sprint_mode == 1:
				if moving:
					# holding sprint button
					if Input.is_action_pressed(SPRINT) and state == "normal"  and stamina > 0:
						enter_sprint_state()
					if Input.is_action_just_pressed(SPRINT):
						match state:
							"normal":
								enter_sprint_state()
							"sprinting":
								enter_normal_state()
				elif state == "sprinting":
					enter_normal_state()
# Any enter state function should only be called once when you want to enter that state, not every frame.


func enter_normal_state():
	#print("entering normal state")
	var prev_state = state
	if prev_state == "crouching":
		CROUCH_ANIMATION.play_backwards("crouch")
	state = "normal"
	speed = base_speed


func enter_crouch_state():
	#print("entering crouch state")
	var prev_state = state
	state = "crouching"
	speed = crouch_speed
	CROUCH_ANIMATION.play("crouch")


func enter_sprint_state():
	#print("entering sprint state")
	var prev_state = state
	if prev_state == "crouching":
		CROUCH_ANIMATION.play_backwards("crouch")
	state = "sprinting"
	speed = sprint_speed


func update_camera_fov():
	if state == "sprinting":
		CAMERA.fov = lerp(CAMERA.fov, 85.0, 0.3)
	else:
		CAMERA.fov = lerp(CAMERA.fov, 75.0, 0.3)


func headbob_animation(moving):
	if moving and is_on_floor():
		var use_headbob_animation : String
		match state:
			"normal","crouching":
				use_headbob_animation = "walk"
			"sprinting":
				use_headbob_animation = "sprint"
		
		var was_playing : bool = false
		if HEADBOB_ANIMATION.current_animation == use_headbob_animation:
			was_playing = true
		
		HEADBOB_ANIMATION.play(use_headbob_animation, 0.25)
		HEADBOB_ANIMATION.speed_scale = (current_speed / base_speed) * 1.75
		if !was_playing:
			HEADBOB_ANIMATION.seek(float(randi() % 2)) # Randomize the initial headbob direction
		
	else:
		if HEADBOB_ANIMATION.current_animation == "sprint" or HEADBOB_ANIMATION.current_animation == "walk":
			HEADBOB_ANIMATION.speed_scale = 1
			HEADBOB_ANIMATION.play("RESET", 1)


func _process(delta):
	if not is_multiplayer_authority(): return
	if is_dead:
		$UserInterface/DebugPanel.add_property("State", "Dead", 4)
	else:
		$UserInterface/DebugPanel.add_property("FPS", Performance.get_monitor(Performance.TIME_FPS), 0)
		var status : String = state
		if !is_on_floor():
			status += " in the air"
		$UserInterface/DebugPanel.add_property("State", status, 4)
	
	if pausing_enabled:
		if Input.is_action_just_pressed(PAUSE):
			match Input.mouse_mode:
				Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				Input.MOUSE_MODE_VISIBLE:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	handle_stamina()


func handle_stamina():
	ui_stamina_bar.value = stamina
	
	if stamina >= 100:
		ui_stamina_bar.visible = false
	else:
		ui_stamina_bar.visible = true
	
	if is_recover_stamina == true:
		#print("starting to recover stamina")
		if(stamina < 100):
			stamina += STAMINA_REC_COST
	
	if stamina == 0 or is_recover_stamina == false and stamina_cooldown_timer.is_stopped() and state != "sprinting":
		#print("should start timer")
		stamina_cooldown_timer.start()

func _on_stamina_cooldown_complete():
	#print("stamina cooldown over")
	is_recover_stamina = true

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouseInput.x += event.relative.x
		mouseInput.y += event.relative.y
	
	if is_dead: return
	
	if Input.is_action_just_pressed("interact"):  # Assuming "interact" is mapped to "F"
		check_door_interaction()
		
	if Input.is_action_just_pressed("shoot") and is_loaded and crossBow_AnimPlayer.current_animation != "SHOOT_ARROW":
		shoot()
	
	if Input.is_action_just_pressed("reload"):
		start_reload()

func shoot():
	if is_multiplayer_authority():
		spawn_arrow.rpc()
	play_shoot_effects.rpc()
	play_shoot_sound.rpc()
	is_loaded = false

@rpc("call_local")
func spawn_arrow():
	var arrow = Arrow.instantiate()
	get_parent().add_child(arrow)  # Add to scene before initializing
	
	# Calculate spawn position 1 meter in front of the head
	var spawn_transform = HEAD.global_transform
	spawn_transform.origin += -HEAD.global_transform.basis.z  # Move 1 meter along the negative Z-axis
	
	print("spawning_arrow " + str(get_multiplayer_authority()))
	arrow_shoot_count = arrow_shoot_count + 1
	print(" arrow_shoot_count: " + str(arrow_shoot_count))
	arrow_shooter_id = get_multiplayer_authority() + arrow_shoot_count
	
	arrow.initialize(spawn_transform, arrow_speed, get_multiplayer_authority(), arrow_shooter_id) #randi for a random arror id
	arrow.max_lifetime = arrow_lifetime
	
	# Set the shooter's collision layer to ignore
	arrow.set_collision_layer_value(get_collision_layer(), false)
	arrow.set_collision_mask_value(get_collision_layer(), false)

func start_reload():
	if not is_loaded and not reload_timer.is_stopped():
		print("Already reloading")
		return
	if is_loaded:
		print("Crossbow is already loaded")
		return
	print("Starting reload")
	reload_timer.start()
	play_reload_effects.rpc()
	play_reload_sound.rpc()

func _on_reload_complete():
	is_loaded = true
	print("Reload complete")
	reset_weapon_animations.rpc()

func collect_key():
	keys += 1
	ui_key_count.text = str(keys)+"/5"
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


@rpc("call_local")
func change_animation(animation_name):
	current_animation = animation_name
	
	var anim_node_path = "parameters/%s" % animation_name
	PlayerModelAnimationTree.set(anim_node_path, AnimationNodeAnimation.PLAY_MODE_BACKWARD)
	
	match animation_name:
		"idle":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToCrouch/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/crouchIdleToWalk/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/jump/blend_amount", 0)
		"walk":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 1)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToCrouch/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/crouchIdleToWalk/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/jump/blend_amount", 0)
		"run":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 1)
			PlayerModelAnimationTree.set("parameters/walkToCrouch/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/crouchIdleToWalk/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/jump/blend_amount", 0)
		"crouch idle":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToCrouch/blend_amount", 1)
			PlayerModelAnimationTree.set("parameters/crouchIdleToWalk/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/jump/blend_amount", 0)
		"crouch walk":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToCrouch/blend_amount", 1)
			PlayerModelAnimationTree.set("parameters/crouchIdleToWalk/blend_amount", 1)
			PlayerModelAnimationTree.set("parameters/jump/blend_amount", 0)
		"jumping":
			PlayerModelAnimationTree.set("parameters/idleToWalk2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToRun2/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/walkToCrouch/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/crouchIdleToWalk/blend_amount", 0)
			PlayerModelAnimationTree.set("parameters/jump/blend_amount", 1)
			
	player_animation_changed.emit(animation_name)

@rpc("call_local") 
func play_shoot_effects():
	ui_AnimPlayer.stop()
	ui_AnimPlayer.play("SHOOT")
	crossBow_AnimPlayer.stop()
	crossBow_AnimPlayer.play("SHOOT_ARROW")
	arrow_AnimPlayer.stop()
	arrow_AnimPlayer.play("SHOOT_ARROW")
	
@rpc("call_local") 
func play_reload_effects():
	ui_AnimPlayer.stop()
	ui_AnimPlayer.play("RELOAD")
	crossBow_AnimPlayer.stop()
	crossBow_AnimPlayer.play("RELOAD")
	PlayerModelAnimationTree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	PlayerModelAnimationTree.set("parameters/reload/active", true)

@rpc("call_local")
func reset_weapon_animations():
	#crossBow_AnimPlayer.stop()
	#crossBow_AnimPlayer.play("RESET")
	arrow_AnimPlayer.stop()
	arrow_AnimPlayer.play("RESET")

@rpc("call_local")
func play_step_sound():
	var sound_array = w_step_sounds if is_on_water() else step_sounds
	var random_sound_index = randi() % sound_array.size()
	sound_array[random_sound_index].play()

func is_on_water() -> bool:
	if surface_detector.is_colliding():
		var collider = surface_detector.get_collider()
		if collider is StaticBody3D:
			#print("")
			var parent = collider.get_parent()
			if parent is MeshInstance3D and parent.name.to_lower() == "water":
				return true
	return false

@rpc("call_local")
func play_shoot_sound():
	crossbowShoot_sounds.play()

@rpc("call_local")
func play_reload_sound():
	crossbowReload_sounds.play()

func update_animation(input_dir):
	var new_animation = current_animation
	var forward_direction = -global_transform.basis.z
	var movement_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	var is_moving_backwards = forward_direction.dot(movement_direction) > 0
	#print("moving backwards = " + str(is_moving_backwards))
	
	#print("state: " + str(state))
	
	if is_on_floor() == false: 
		new_animation = "jumping"
	elif input_dir == Vector2.ZERO and state != "crouching":
		new_animation = "idle"
	elif state == "sprinting":
		new_animation = "run"
	elif input_dir == Vector2.ZERO and state == "crouching":
		new_animation = "crouch idle"
	elif input_dir != Vector2.ZERO and state == "crouching":
		new_animation = "crouch walk"
	elif input_dir != Vector2.ZERO and state != "crouching":
		new_animation = "walk"
	
	if new_animation != current_animation and is_multiplayer_authority():
		change_animation.rpc(new_animation)

@rpc("any_peer")
func receive_damage(damage_amount: int, arrow_id: int):
	if not is_multiplayer_authority() or arrow_id == last_hit_arrow_id:
		return
	
	health -= damage_amount
	last_hit_arrow_id = arrow_id
	splat_sound.play()
	health_changed.emit(health)
	
	if health <= 0:
		die()
	
	health_changed.emit(health)

func die():
	is_dead = true
	spawn_death_model.rpc()
	hide_player_mesh.rpc()
	respawn_timer.start()
	PlayerModel.visible = false
	crossbow_fps.visible = false
	arrow_fps.visible = false

@rpc("call_local")
func hide_player_mesh():
	PlayerMesh.set_layer_mask_value(1, 0)
	PlayerMesh.set_layer_mask_value(2, 1) 
	PlayerMesh_skin.set_layer_mask_value(1, 0)
	PlayerMesh_skin.set_layer_mask_value(2, 1) 
	crossbow_local.set_layer_mask_value(1, 0)
	crossbow_local.set_layer_mask_value(2, 1) 
	PlayerCollision.disabled = true

@rpc("call_local")
func spawn_death_model():
	death_model = death_model_scene.instantiate()
	get_parent().add_child(death_model)
	
	death_model.global_transform = global_transform
	death_model.rotation.y = HEAD.global_rotation.y
	
	# Play the death animation
	var death_anim_player = death_model.get_node("AnimationPlayer")
	death_anim_player.play("Die")
	
func _on_respawn():
	is_dead = false
	health = 2
	position = Vector3.ZERO  # Or use your spawn point logic here
	reset_player_state.rpc()
	crossbow_fps.visible = true
	if death_model:
		death_model.queue_free()
		death_model = null

@rpc("call_local")
func reset_player_state():
	# Reset animations, weapon state, etc.
	PlayerModelAnimationTree.set("parameters/death/active", false)
	change_animation.rpc("idle")
	is_loaded = true
	reset_weapon_animations.rpc()
	health_changed.emit(health)
	PlayerMesh.set_layer_mask_value(1, 1)  # Turn on visibility on layer 1
	PlayerMesh.set_layer_mask_value(2, 0)
	PlayerMesh_skin.set_layer_mask_value(1, 1)  # Turn on visibility on layer 1
	PlayerMesh_skin.set_layer_mask_value(2, 0)
	crossbow_local.set_layer_mask_value(1, 1)  # Turn on visibility on layer 1
	crossbow_local.set_layer_mask_value(2, 0)
	PlayerCollision.disabled = false
