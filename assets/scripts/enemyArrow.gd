extends CharacterBody3D

var initial_velocity: Vector3
var current_velocity: Vector3
var gravity: float = -69.8
var time_alive: float = 0
var max_lifetime: float = 10.0
var damage: int = 1
var shooter_id: int = 0

var arrow_id: int = 0
var has_dealt_damage: bool = false

@export var hit_flash_duration: float = 0.6
@export var hit_flash_color: Color = Color(1, 0, 0, 1)

@export var blood_effect_scene: PackedScene

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $ArrowMesh
@onready var collide_effect: GPUParticles3D = $CollideParticles
@onready var trail_effect: GPUParticles3D = $TrailParticles
@onready var light_spot: SpotLight3D = $SpotLight3D
@onready var smack_sound: AudioStreamPlayer3D = $SmackSound
@onready var flying_sound: AudioStreamPlayer3D = $FlyingSound

func _ready():
	set_physics_process(true)

# $$$ CHANGE $$$
func initialize(start_transform: Transform3D, initial_speed: float, shooter: Enemy):
	global_transform = start_transform
	initial_velocity = -global_transform.basis.z * initial_speed
	current_velocity = initial_velocity
	shooter_id = shooter.enemy_id
	
	scale = Vector3(0.05, 0.05, 0.05)
	
	flying_sound.play()
	
	mesh_instance.rotate_x(deg_to_rad(270))
	collision_shape.rotate_x(deg_to_rad(270))
	
	arrow_id = randi()  # Generate a unique ID for each arrow

# $$$ CHANGE $$$
func _physics_process(delta):
	time_alive += delta
	if time_alive > max_lifetime:
		queue_free()
		return

	current_velocity += Vector3(0, gravity/25, 0) * delta
	
	var movement = current_velocity * delta

	var collision = move_and_collide(movement)

	if collision and not has_dealt_damage:
		handle_collision(collision)
	
	look_at(global_position + velocity.normalized(), Vector3.UP)

# $$$ ADDED $$$
func handle_collision(collision):
	collide_effect.emitting = true
	trail_effect.emitting = false
	light_spot.visible = false
	smack_sound.play()
	flying_sound.stream_paused = true
	var collider = collision.get_collider()
	
	if collider is CharacterBody3D:
			if collider is Enemy:
				# Handle enemy hit
				collider.receive_damage_request.rpc_id(1, damage, arrow_id)
				print("enemy hit event, arrow_shooter_id: " + str(arrow_id) + " collider: " + str(collider))
			elif collider.name != str(shooter_id):
				# Handle player hit
				collider.receive_damage.rpc_id(collider.get_multiplayer_authority(), damage, arrow_id)
				print("player hit event, arrow_shooter_id: " + str(arrow_id) + " collider: " + str(collider))
			
			has_dealt_damage = true
			spawn_blood_effect(global_position)
			flash_hit_player(collider.get_path())
			queue_free()
	else:
		# Stick the arrow to non-character objects
		collision_shape.disabled = true
		set_physics_process(false)

# $$$ ADDED $$$
func spawn_blood_effect(pos: Vector3):
	if blood_effect_scene:
		var blood_effect = blood_effect_scene.instantiate()
		if blood_effect is GPUParticles3D:
			get_tree().current_scene.add_child(blood_effect)
			blood_effect.global_position = pos
			blood_effect.emitting = true
			blood_effect.finished.connect(blood_effect.queue_free)

# $$$ ADDED $$$
func flash_hit_player(hit_player_path: NodePath):
	var hit_player = get_node(hit_player_path)
	if hit_player and hit_player.has_node("PlayerModel/Armature/Skeleton3D/CharacterMesh"):
		var player_mesh = hit_player.get_node("PlayerModel/Armature/Skeleton3D/CharacterMesh")
		var original_material = player_mesh.get_surface_override_material(0)
		var flash_material = original_material.duplicate()
		flash_material.albedo_color = hit_flash_color
		
		player_mesh.set_surface_override_material(0, flash_material)
		
		get_tree().create_timer(hit_flash_duration).timeout.connect(
			func():
				player_mesh.set_surface_override_material(0, original_material)
		)
