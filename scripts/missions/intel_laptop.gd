class_name IntelLaptop
extends StaticBody3D
## Field laptop on a crate: the InteractHoldObjective prop for the intel download. The screen
## glows blue until `set_completed()` turns it green.

@export var idle_color: Color = Color(0.3, 0.6, 1.0)
@export var done_color: Color = Color(0.3, 1.0, 0.45)

@onready var display: MeshInstance3D = $Laptop/Hinge/Display
@onready var glow: OmniLight3D = $Laptop/Glow


func _ready() -> void:
	_set_color(idle_color)


func set_completed() -> void:
	_set_color(done_color)


func _set_color(color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color * 0.4
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	display.material_override = material
	glow.light_color = color
