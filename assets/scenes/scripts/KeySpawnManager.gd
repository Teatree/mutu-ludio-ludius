extends	Node

class_name KeySpawnManager

@export	var	Key: PackedScene
@export	var	max_keys: int =	12 # there are 3 Players, they each need 5, this creates conflict baby!
@export	var	spawn_chance: float	= 0.5  # 50% chance	to spawn a key at each attempt

var	spawn_points: Array[Node3D]	= []
var	active_keys: Array[Node3D] = []
var	used_spawn_points: Array[Node3D] = []

func _ready():
	# Collect all child	nodes that are KeySpawnPoint type
	for	child in get_children():
		if child is Node3D and child.name.begins_with("KeySpawnPoint"):
			spawn_points.append(child)

func spawn_keys():
	# Reset	for	new	spawn attempt
	active_keys.clear()
	used_spawn_points.clear()
	
	var	available_points = spawn_points.duplicate()
	available_points.shuffle()	# Randomize	the	order of spawn points
	
	while not available_points.is_empty() and active_keys.size() < max_keys:
		var	point =	available_points.pop_front()
		if randf() <= spawn_chance:
			spawn_key(point.global_position)
		used_spawn_points.append(point)
		
		# If we've used	all	spawn points, but haven't reached max_keys,	
		# and there	are	still unused points, we reset and try again
		if available_points.is_empty() and active_keys.size() <	max_keys and used_spawn_points.size() <	spawn_points.size():
			available_points = spawn_points.filter(func(p):	return not used_spawn_points.has(p))
			available_points.shuffle()

func spawn_key(position: Vector3):
	var	key	= Key.instantiate()
	key.global_position	= position
	add_child(key)
	active_keys.append(key)
	key.tree_exiting.connect(func(): on_key_collected(key))

func on_key_collected(key: Node3D):
	active_keys.erase(key)
	# We don't automatically respawn keys in this version

func get_key_data():
	var	data = []
	for	key	in active_keys:
		data.append(key.global_position)
	return data

func spawn_keys_from_data(key_data):
	for	pos	in key_data:
		spawn_key(pos)

# This function	can	be called if you want to try respawning	keys after some	have been collected
func respawn_keys():
	var	keys_to_spawn =	max_keys - active_keys.size()
	var	available_points = spawn_points.filter(func(point):	
		return not used_spawn_points.has(point)	or (used_spawn_points.has(point) and active_keys.all(func(key):	key.global_position.distance_to(point.global_position) > 1.0))
	)
	available_points.shuffle()
	
	for	point in available_points:
		if keys_to_spawn <= 0:
			break
		if randf() <= spawn_chance:
			spawn_key(point.global_position)
			if not used_spawn_points.has(point):
				used_spawn_points.append(point)
			keys_to_spawn -= 1
