extends CharacterBody3D

var initial_velocity: Vector3
var gravity: float = -9.8
var time_alive: float = 0
var max_lifetime: float = 10.0
var damage: int = 1
var shooter_id: int = 0

@export var hit_flash_duration: float = 0.6
@export var hit_flash_color: Color = Color(1, 0, 0, 1)  # Bright red

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $arrow
@onready var collide_effect: GPUParticles3D = $GPUParticles3D

func _ready():
	set_physics_process(true)

func initialize(start_transform: Transform3D, initial_speed: float, shooter: int):
	global_transform = start_transform
	initial_velocity = -global_transform.basis.z * initial_speed
	shooter_id = shooter
	
	# Set the scale of the arrow
	scale = Vector3(0.05, 0.05, 0.05)
	
		# Rotate the mesh and collision shape 90 degrees around the X-axis
	mesh_instance.rotate_x(deg_to_rad(270))
	collision_shape.rotate_x(deg_to_rad(270))

func _physics_process(delta):
	time_alive += delta
	if time_alive > max_lifetime:
		queue_free()
		return

	var movement = initial_velocity * delta + 0.5 * Vector3(0, gravity, 0) * delta * delta
	var collision = move_and_collide(movement)

	if collision:
		var collider = collision.get_collider()
		if collider is CharacterBody3D and collider.name != str(shooter_id):
			collider.receive_damage.rpc_id(collider.get_multiplayer_authority())
			flash_hit_player.rpc(collider.get_path())
			queue_free()
		elif not collider is CharacterBody3D:
			# Stick the arrow
			collision_shape.disabled = true
			set_physics_process(false)

	# Update arrow rotation to face its movement direction
	look_at(global_position + velocity.normalized(), Vector3.UP)

func _on_area_3d_body_entered(body):
	if body is CharacterBody3D and body.name != str(shooter_id):
		collide_effect.emitting = true
		body.receive_damage.rpc_id(body.get_multiplayer_authority())
		queue_free()

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
