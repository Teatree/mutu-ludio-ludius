extends	Area3D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body	is CharacterBody3D:	 # Assuming	your Player	script extends CharacterBody3D
		if body.has_method("collect_key"):
			body.collect_key()
			rpc("remove_key")

@rpc("call_local")
func remove_key():
	var	world =	get_tree().current_scene
	if world.has_method("remove_dropped_key"):
		world.remove_dropped_key.rpc(str(get_path()))
	get_parent().queue_free()  # This will remove the entire key object