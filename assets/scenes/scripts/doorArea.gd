extends StaticBody3D

@onready var animation_player = $"../keyanim/AnimationPlayer"
const KEYS_REQUIRED = 5

func _ready():
	add_to_group("doors")
	#print("Door added to 'doors' group")

func try_open(player):
	print("Trying to open door")
	if player.keys >= KEYS_REQUIRED:
		rpc("open_door")
		player.keys -= KEYS_REQUIRED
		player.initiate_escape()
		print("Player %s opened the door and escaped. Remaining keys: %d" % [player.name, player.keys])
	else:
		print("Player %s doesn't have enough keys. Current keys: %d" % [player.name, player.keys])
		
@rpc("any_peer", "call_local")
func open_door():
	print("Opening door")
	animation_player.stop()
	animation_player.play("open")

	await get_tree().create_timer(4).timeout
	queue_free()
