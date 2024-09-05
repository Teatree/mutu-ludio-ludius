extends	Control

signal sensitivity_changed(value: float)
signal volume_changed(value: float)
signal request_quit

@onready var sensitivity_slider	= $PanelContainer/VBoxContainer/HBoxContainer/HSlider
@onready var volume_slider	= $PanelContainer/VBoxContainer/HBoxContainer2/HSlider
@onready var exit_button = $PanelContainer/VBoxContainer/ExitButton

var bus_index: int

func _ready():
	sensitivity_slider.value_changed.connect(_on_sensitivity_slider_value_changed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	
	# Set up the slider	with a default value of 1.0
	sensitivity_slider.min_value = 0.1
	sensitivity_slider.max_value = 2.0
	sensitivity_slider.step	= 0.1
	sensitivity_slider.value = 1.0

	# Set up the volume	slider
	volume_slider.min_value	= 0.0
	volume_slider.max_value	= 1.0
	volume_slider.step = 0.01
	var	initial_volume_db =	AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	bus_index = AudioServer.get_bus_index("Master")
	volume_slider.value	= db_to_linear(initial_volume_db)

# $$$ CHANGE $$$
# Ensure that input	events are not propagated when interacting with	UI
func _unhandled_input(event):
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()

func _on_sensitivity_slider_value_changed(value: float):
	sensitivity_changed.emit(value)

# Handle volume	slider value changes
func _on_volume_slider_value_changed(value:	float):
	AudioServer.set_bus_volume_db(
		bus_index,
		linear_to_db(value)
	)
	volume_changed.emit(value)

func _on_exit_button_pressed():
	request_quit.emit()