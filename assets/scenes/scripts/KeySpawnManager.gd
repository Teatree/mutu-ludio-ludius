extends Node

class_name KeySpawnManager

@export var max_keys: int = 12
@export var min_distance_between_keys: float = 2.0

var spawn_points: Array[Node3D] = []

func _ready():
    for child in get_children():
        if child is Node3D and child.name.begins_with("KeySpawnPoint"):
            spawn_points.append(child)

func get_spawn_points() -> Array:
    var available_points = spawn_points.duplicate()
    available_points.shuffle()

    var valid_points = []
    for point in available_points:
        if is_valid_spawn_point(point, valid_points):
            valid_points.append(point)
            if valid_points.size() >= max_keys:
                break

    return valid_points

func is_valid_spawn_point(point: Node3D, existing_points: Array) -> bool:
    for existing_point in existing_points:
        if point.global_position.distance_to(existing_point.global_position) < min_distance_between_keys:
            return false
    return true