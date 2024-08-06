extends StaticBody3D

@onready var animation_player = $"../keyanim/AnimationPlayer"
const KEYS_REQUIRED = 5

func _ready():
	add_to_group("doors")
	print("Door added to 'doors' group")

func try_open(player):
	print("Trying to open door")
	if player.keys >= KEYS_REQUIRED:
		rpc("open_door")
		player.keys -= KEYS_REQUIRED
		print("Player %s opened the door. Remaining keys: %d" % [player.name, player.keys])
	else:
		print("Player %s doesn't have enough keys. Current keys: %d" % [player.name, player.keys])

@rpc("call_local")
func open_door():
	print("Opening door")
	animation_player.play("open")
