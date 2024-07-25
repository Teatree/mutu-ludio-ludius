extends Node3D
class_name HealthComponent

@export var MAX_HEALTH := 3.0
var health : float

func _ready():
	health = MAX_HEALTH

func _process(delta):
	pass

func receiveDamage():
	health -= 1
	if health <= 0:
		health = 3
		get_parent().position.x = 0
		get_parent().position.y = -2
		get_parent().position.z = 0
	return health
