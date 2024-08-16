extends Area3D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is CharacterBody3D:  # Assuming your Player script extends CharacterBody3D
		if body.has_method("collect_key"):
			body.collect_key()
			rpc("remove_key")

@rpc("call_local")
func remove_key():
	get_parent().queue_free()  # This will remove the entire key object
