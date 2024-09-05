extends	Control

signal sensitivity_changed(value: float)
signal request_quit

@onready var sensitivity_slider	= $PanelContainer/VBoxContainer/HBoxContainer/HSlider
@onready var exit_button = $PanelContainer/VBoxContainer/ExitButton

func _ready():
	sensitivity_slider.value_changed.connect(_on_sensitivity_slider_value_changed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	
	# Set up the slider	with a default value of 1.0
	sensitivity_slider.min_value = 0.1
	sensitivity_slider.max_value = 2.0
	sensitivity_slider.step	= 0.1
	sensitivity_slider.value = 1.0

# $$$ CHANGE $$$
# Ensure that input	events are not propagated when interacting with	UI
func _unhandled_input(event):
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()

func _on_sensitivity_slider_value_changed(value: float):
	sensitivity_changed.emit(value)

# Emit a signal to request quitting instead of directly quitting
func _on_exit_button_pressed():
	request_quit.emit()
