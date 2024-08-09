# EnemyArrow.gd
extends CharacterBody3D

var initial_velocity: Vector3
var current_velocity: Vector3
var gravity: float = -9.8
var time_alive: float = 0
var max_lifetime: float = 10.0
var damage: int = 1
var shooter_id: int = 0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $ArrowMesh

func _ready():
	set_physics_process(true)

func initialize(start_transform: Transform3D, initial_speed: float, shooter: Node):
	global_transform = start_transform
	initial_velocity = -global_transform.basis.z * initial_speed
	current_velocity = initial_velocity
	shooter_id = shooter.get_instance_id()
	
	# Set the scale of the arrow (adjust as needed)
	scale = Vector3(0.05, 0.05, 0.05)
	
	# Rotate the mesh and collision shape if needed
	mesh_instance.rotate_x(deg_to_rad(270))
	collision_shape.rotate_x(deg_to_rad(270))

func _physics_process(delta):
	time_alive += delta
	if time_alive > max_lifetime:
		queue_free()
		return

	current_velocity += Vector3(0, gravity, 0) * delta
	
	var movement = current_velocity * delta

	var collision = move_and_collide(movement)

	if collision:
		var collider = collision.get_collider()
		if collider is CharacterBody3D and collider.get_instance_id() != shooter_id:
			if collider.has_method("receive_damage"):
				collider.receive_damage.rpc_id(collider.get_multiplayer_authority())
			queue_free()
		else:
			# Stick the arrow
			collision_shape.disabled = true
			set_physics_process(false)
	
	# Update arrow rotation to face its movement direction
	look_at(global_position + current_velocity.normalized(), Vector3.UP)

func _on_area_3d_body_entered(body):
	if body is CharacterBody3D and body.get_instance_id() != shooter_id:
		if body.has_method("receive_damage"):
			body.receive_damage.rpc_id(body.get_multiplayer_authority())
		queue_free()
