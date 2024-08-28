extends	CharacterBody3D

var	initial_velocity: Vector3
var	current_velocity: Vector3
var	gravity: float = -69.8
var	time_alive:	float =	0
var	max_lifetime: float	= 10.0
var	damage:	int	= 1
var	shooter_id:	int	= 0

var	arrow_id: int =	0
var	has_dealt_damage: bool = false

# Debug	Trail
@export	var	debug_trail_enabled: bool =	false
@export	var	debug_trail_length:	int	= 100
@export	var	debug_trail_interval: float	= 0.05

var	debug_trail: Array = []
var	debug_trail_timer: float = 0

@export	var	hit_flash_duration:	float =	0.6
@export	var	hit_flash_color: Color = Color(1, 0, 0, 1)	# Bright red

@export	var	blood_effect_scene:	PackedScene

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance:	MeshInstance3D = $arrow
@onready var collide_effect: GPUParticles3D	= $expolde_particles
@onready var trail_effect: GPUParticles3D =	$trail_particles
@onready var light_spot: SpotLight3D = $SpotLight3D
@onready var smack_sound: AudioStreamPlayer3D =	$smack
@onready var splat_sound: AudioStreamPlayer3D =	$splat
@onready var flying_sound: AudioStreamPlayer3D = $arrow_flight

enum ArrowState	{ FLYING, STUCK, PICKED_UP }
var	current_state: ArrowState =	ArrowState.FLYING

@onready var pickup_area: Area3D = $PickupArea

func _ready():
	set_physics_process(true)

func initialize(start_transform: Transform3D, initial_speed: float,	shooter: int, shooter_arrow_id:	int):
	global_transform = start_transform
	initial_velocity = -global_transform.basis.z * initial_speed
	current_velocity = initial_velocity
	shooter_id = shooter

	pickup_area.body_entered.connect(_on_pickup_area_body_entered)
	# Set the scale	of the arrow
	scale =	Vector3(0.05, 0.05,	0.05)
	
	flying_sound.play()
	flying_sound.stream_paused = false
	
		# Rotate the mesh and collision	shape 90 degrees around	the	X-axis
	mesh_instance.rotate_x(deg_to_rad(270))
	collision_shape.rotate_x(deg_to_rad(270))
	
	if debug_trail_enabled:
		add_debug_point() 
		
	arrow_id = shooter_arrow_id

func _physics_process(delta):
	time_alive += delta
	if time_alive >	max_lifetime:
		queue_free()
		return

	current_velocity += Vector3(0, gravity/25, 0) *	delta
	
	var	movement = current_velocity	* delta

	var	collision =	move_and_collide(movement)

	if collision and not has_dealt_damage:

		if current_state != ArrowState.FLYING:
			return	# Ignore collisions	if the arrow is already	stuck or picked	up

		collide_effect.emitting	= true
		trail_effect.emitting =	false
		light_spot.visible = false
		smack_sound.play()
		flying_sound.stream_paused = true
		var	collider = collision.get_collider()
		
		if collider	is CharacterBody3D:
			play_splat_sound()
			if collider	is Enemy:
				# Handle enemy hit
				collider.receive_damage_request.rpc_id(1, damage, arrow_id)
				#print("enemy hit event,	arrow_shooter_id: "	+ str(arrow_id)	+ "	collider: "	+ str(collider))
			elif collider.name != str(shooter_id):
				# Handle player	hit
				collider.receive_damage.rpc_id(collider.get_multiplayer_authority(), damage, arrow_id)
				#print("player hit event, arrow_shooter_id:	" +	str(arrow_id) +	" collider:	" +	str(collider))
			
			has_dealt_damage = true
			spawn_blood_effect.rpc(global_position)
			#flash_hit_player.rpc(collider.get_path())
			queue_free()
		else:
			# Stick	the	arrow to non-character objects
			setup_for_pickup()
	
	if debug_trail_enabled:
		debug_trail_timer += delta
		if debug_trail_timer >= debug_trail_interval:
			debug_trail_timer =	0
			add_debug_point()
	
	# Update arrow rotation	to face	its	movement direction
	look_at(global_position	+ velocity.normalized(), Vector3.UP)


func play_splat_sound():
	# Create and play a	separate AudioStream3D for the splat sound
	var	splat_sound_instance = AudioStreamPlayer3D.new()
	splat_sound_instance.stream	= splat_sound.stream
	splat_sound_instance.global_transform =	global_transform # Set position	to the arrow's position
	splat_sound_instance.volume_db = -20
	get_tree().root.get_node("World").add_child(splat_sound_instance)
	splat_sound_instance.play()

	# Connect the finished signal to remove	the	instance after playing
	splat_sound_instance.connect("finished", Callable(splat_sound_instance,	"queue_free"))

# This function	sets up the	arrow for pickup after it's	stuck in a surface
func setup_for_pickup():
	current_state =	ArrowState.STUCK
	collision_shape.disabled = true
	pickup_area.monitoring = true
	pickup_area.monitorable	= true
	set_physics_process(false)


# This function	is called when a player	enters the pickup area
func _on_pickup_area_body_entered(body):
	# print("Body	entered	pickup area: ", body.name)
	# print("Body	is CharacterBody3D:	", body	is CharacterBody3D)
	# print("Body	has	pickup_arrow method: ", body.has_method("pickup_arrow"))
	
	if current_state == ArrowState.STUCK and body is CharacterBody3D and body.has_method("pickup_arrow"):
		body.pickup_arrow()
		rpc("picked_up")

@rpc("call_local")
func picked_up():
	current_state =	ArrowState.PICKED_UP
	queue_free()

func add_debug_point():
	var	debug_sphere = create_debug_sphere(global_position)
	get_tree().current_scene.add_child(debug_sphere)
	debug_trail.append(debug_sphere)
	
	if debug_trail.size() >	debug_trail_length:
		var	old_point =	debug_trail.pop_front()
		old_point.queue_free()

@rpc("call_local")
func spawn_blood_effect(pos: Vector3):
	if blood_effect_scene:
		var	blood_effect = blood_effect_scene.instantiate()
		if blood_effect	is GPUParticles3D:
			get_tree().current_scene.add_child(blood_effect)
			blood_effect.global_position = pos
			blood_effect.emitting =	true
			
			# Set up the blood effect to self-destruct after it's finished
			blood_effect.finished.connect(blood_effect.queue_free)
		else:
			push_error("Blood effect scene is not a	GPUParticles3D")

# Add this function	to create a	debug sphere
func create_debug_sphere(position: Vector3,	color: Color = Color.RED) -> MeshInstance3D:
	var	sphere_mesh	= SphereMesh.new()
	sphere_mesh.radius = 0.05
	sphere_mesh.height = 0.1
	
	var	sphere_instance	= MeshInstance3D.new()
	sphere_instance.mesh = sphere_mesh
	
	var	material = StandardMaterial3D.new()
	material.albedo_color =	color
	material.flags_unshaded	= true
	sphere_instance.material_override =	material
	
	sphere_instance.global_position	= position
	return sphere_instance

func _exit_tree():
	for	point in debug_trail:
		if is_instance_valid(point):
			point.queue_free()