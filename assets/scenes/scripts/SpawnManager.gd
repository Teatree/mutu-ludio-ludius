extends	Node

class_name SpawnManager

var	spawn_points: Array[Node3D]	= []
var	available_spawn_points:	Array[Node3D] =	[]

func _ready():
	for	child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			spawn_points.append(child)
	reset_available_spawn_points()

func reset_available_spawn_points():
	available_spawn_points = spawn_points.duplicate()
	available_spawn_points.shuffle()

# $$$ CHANGE $$$
func get_random_spawn_point() -> Dictionary:
	if available_spawn_points.is_empty():
		reset_available_spawn_points()

	for	i in range(available_spawn_points.size()):
		var	spawn_point	= available_spawn_points[i]
		var	area = spawn_point.get_node("Area3DPlayerDetectionCheese")
		
		if area:
			var	overlapping_bodies = area.get_overlapping_bodies()
			print("SpawnPoint ", spawn_point.name, " overlapping bodies:")
			for	body in overlapping_bodies:
				print("	 - ", body.name, " (Group: ", body.get_groups(), ")")
			
			var	players_nearby = overlapping_bodies.filter(func(body): return body.is_in_group("players"))
			if players_nearby.is_empty():
				available_spawn_points.remove_at(i)
				print("Spawn point selected: ", spawn_point.name)
				
				#var	mesh_instance =	spawn_point.get_node("MeshInstance3D")
				return {
					"position":	spawn_point.global_position,
					"rotation":	spawn_point.global_rotation
				}
			else:
				print("Players nearby, cannot use this spawn point")
		else:
			print("Warning:	Area3D not found for SpawnPoint	", spawn_point.name)
	
	print("No suitable spawn point found. All spawn	points are occupied.")
	return {
		"position":	Vector3.ZERO,
		"rotation":	Vector3.ZERO
	}

func get_available_spawn_points() -> Array[Node3D]:
	return available_spawn_points