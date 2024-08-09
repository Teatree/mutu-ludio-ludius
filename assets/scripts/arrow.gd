extends CharacterBody3D

var initial_velocity: Vector3
var current_velocity: Vector3
var gravity: float = -69.8
var time_alive: float = 0
var max_lifetime: float = 10.0
var damage: int = 1
var shooter_id: int = 0

# Debug Trail
@export var debug_trail_enabled: bool = false
@export var debug_trail_length: int = 100
@export var debug_trail_interval: float = 0.05

var debug_trail: Array = []
var debug_trail_timer: float = 0

@export var hit_flash_duration: float = 0.6
@export var hit_flash_color: Color = Color(1, 0, 0, 1)  # Bright red

@export var blood_effect_scene: PackedScene

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $arrow
@onready var collide_effect: GPUParticles3D = $expolde_particles
@onready var trail_effect: GPUParticles3D = $trail_particles
@onready var light_spot: SpotLight3D = $SpotLight3D
@onready var smack_sound: AudioStreamPlayer3D = $smack
@onready var flying_sound: AudioStreamPlayer3D = $arrow_flight

func _ready():
	set_physics_process(true)

func initialize(start_transform: Transform3D, initial_speed: float, shooter: int):
	global_transform = start_transform
	initial_velocity = -global_transform.basis.z * initial_speed
	current_velocity = initial_velocity
	shooter_id = shooter
	
	# Set the scale of the arrow
	scale = Vector3(0.05, 0.05, 0.05)
	
	flying_sound.play()
	flying_sound.stream_paused = false
	
		# Rotate the mesh and collision shape 90 degrees around the X-axis
	mesh_instance.rotate_x(deg_to_rad(270))
	collision_shape.rotate_x(deg_to_rad(270))
	
	if debug_trail_enabled:
		add_debug_point()  # Add the first point immediately

func _physics_process(delta):
	time_alive += delta
	if time_alive > max_lifetime:
		queue_free()
		return

	current_velocity += Vector3(0, gravity/25, 0) * delta
	
	var movement = current_velocity * delta

	var collision = move_and_collide(movement)

	if collision:
		collide_effect.emitting = true
		trail_effect.emitting = false
		light_spot.visible = false
		smack_sound.play()
		flying_sound.stream_paused = true
		var collider = collision.get_collider()
		if collider is CharacterBody3D and collider.name != str(shooter_id):
			collider.receive_damage.rpc_id(collider.get_multiplayer_authority())
			spawn_blood_effect.rpc(global_position)
			flash_hit_player.rpc(collider.get_path())
			queue_free()
		elif not collider is CharacterBody3D:
			# Stick the arrow
			collision_shape.disabled = true
			set_physics_process(false)
	
	if debug_trail_enabled:
		debug_trail_timer += delta
		if debug_trail_timer >= debug_trail_interval:
			debug_trail_timer = 0
			add_debug_point()
	
	# Update arrow rotation to face its movement direction
	look_at(global_position + velocity.normalized(), Vector3.UP)

func add_debug_point():
	var debug_sphere = create_debug_sphere(global_position)
	get_tree().current_scene.add_child(debug_sphere)
	debug_trail.append(debug_sphere)
	
	if debug_trail.size() > debug_trail_length:
		var old_point = debug_trail.pop_front()
		old_point.queue_free()

func _on_area_3d_body_entered(body):
	if body is CharacterBody3D and body.get_instance_id() != shooter_id:
		collide_effect.emitting = true
		spawn_blood_effect.rpc(global_position)
		
		if body.has_method("receive_damage"):
			if body.name.is_valid_int():  # Player
				body.receive_damage.rpc_id(body.get_multiplayer_authority())
			else:  # Enemy
				body.receive_damage.rpc()
		queue_free()
	else:
		print("Invalid target or shooter hit themselves")

@rpc("call_local")
func spawn_blood_effect(pos: Vector3):
	if blood_effect_scene:
		var blood_effect = blood_effect_scene.instantiate()
		if blood_effect is GPUParticles3D:
			get_tree().current_scene.add_child(blood_effect)
			blood_effect.global_position = pos
			blood_effect.emitting = true
			
			# Set up the blood effect to self-destruct after it's finished
			blood_effect.finished.connect(blood_effect.queue_free)
		else:
			push_error("Blood effect scene is not a GPUParticles3D")

@rpc("call_local")
func flash_hit_player(hit_player_path: NodePath):
	var hit_player = get_node(hit_player_path)
	if hit_player and hit_player.has_node("PlayerModel/Armature/Skeleton3D/CharacterMesh"):
		var player_mesh = hit_player.get_node("PlayerModel/Armature/Skeleton3D/CharacterMesh")
		var original_material = player_mesh.get_surface_override_material(0)
		# Create the flash material
		var flash_material = original_material.duplicate()
		flash_material.albedo_color = hit_flash_color
		
		player_mesh.set_surface_override_material(0, flash_material)
		
		get_tree().create_timer(hit_flash_duration).timeout.connect(
			func():
				player_mesh.set_surface_override_material(0, original_material)
		)

# Add this function to create a debug sphere
func create_debug_sphere(position: Vector3, color: Color = Color.RED) -> MeshInstance3D:
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.05
	sphere_mesh.height = 0.1
	
	var sphere_instance = MeshInstance3D.new()
	sphere_instance.mesh = sphere_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.flags_unshaded = true
	sphere_instance.material_override = material
	
	sphere_instance.global_position = position
	return sphere_instance

func _exit_tree():
	for point in debug_trail:
		if is_instance_valid(point):
			point.queue_free()
