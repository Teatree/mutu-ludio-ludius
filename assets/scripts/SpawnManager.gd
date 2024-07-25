extends Node

class_name SpawnManager

var spawn_points: Array[Node3D] = []
var used_spawn_points: Array[Node3D] = []

func _ready():
	# Collect all child nodes that are SpawnPoint type
	for child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			spawn_points.append(child)

func get_random_spawn_point() -> Vector3:
	if spawn_points.is_empty():
		# If all spawn points are used, reset the list
		spawn_points = used_spawn_points.duplicate()
		used_spawn_points.clear()
	
	var spawn_point = spawn_points.pick_random()
	spawn_points.erase(spawn_point)
	used_spawn_points.append(spawn_point)
	
	return spawn_point.global_position

func release_spawn_point(position: Vector3):
	for point in used_spawn_points:
		if point.global_position.is_equal_approx(position):
			used_spawn_points.erase(point)
			spawn_points.append(point)
			break
