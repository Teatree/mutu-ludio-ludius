extends	Node

class_name SpawnManager

var	spawn_points: Array[Node3D]	= []

func _ready():
	for	child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			spawn_points.append(child)

# $$$ CHANGE $$$
# Added	" __ " prefix to all print statements for easier identification
func get_random_spawn_point() -> Dictionary:		
	print(str(multiplayer.get_unique_id()) + " __ Checking spawn points:")
	for	sp in spawn_points:
		var	area = sp.get_node("Area3DPlayerDetectionCheese")
		if area:
			print(str(multiplayer.get_unique_id()) + " __ "	+ sp.name +	" -	Player nearby: " + str(area.is_player_nearby()))
		else:
			print(str(multiplayer.get_unique_id()) + " __ "	+ sp.name +	" -	No Area3DPlayerDetectionCheese found")

	var	available_spawn_points = spawn_points.filter(func(sp): 
		var	area = sp.get_node("Area3DPlayerDetectionCheese")
		return area	and	not	area.is_player_nearby()
	)

	print("	__ Occupied	spawn points:")
	for	sp in spawn_points:
		var	area = sp.get_node("Area3DPlayerDetectionCheese")
		if area	and	area.is_player_nearby():
			print("	__ " + sp.name + " is occupied")

	if available_spawn_points.is_empty():
		print("	__ No suitable spawn point found. All spawn	points are occupied.")
		return {"position":	Vector3.ZERO, "rotation": Vector3.ZERO}

	var	spawn_point	= available_spawn_points[randi() % available_spawn_points.size()]
	print("	__ Available Spawn points: ", str(available_spawn_points))
	print("	__ Spawn point selected: ", spawn_point.name)

	return {
		"position":	spawn_point.global_position,
		"rotation":	spawn_point.global_rotation
	}

func get_available_spawn_points() -> Array[Node3D]:
	return spawn_points.filter(func(sp):	
		var	area = sp.get_node("Area3DPlayerDetectionCheese")
		return area	and	not	area.is_player_nearby()
	)
