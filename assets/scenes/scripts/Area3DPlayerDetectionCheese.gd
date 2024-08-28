extends	Area3D

var	is_colliding_with_player: bool = false

func _ready():
	connect("body_entered",	Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body):
	if body.is_in_group("players"):
		is_colliding_with_player = true
		print(get_parent().name	+ "	is colliding with player: "	+ body.name)

func _on_body_exited(body):
	if body.is_in_group("players"):
		is_colliding_with_player = false
		print(get_parent().name	+ "	is no longer colliding with	player:	" +	body.name)

func is_player_nearby()	-> bool:
	return is_colliding_with_player