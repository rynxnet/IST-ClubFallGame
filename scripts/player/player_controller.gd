class_name PlayerController
extends CharacterBody3D
## The local player's first-person body: movement, mouse look, health, and weapon input.
##
## Calls down into its weapons (WeaponBase children of WeaponHolder).
## Signals up: GameManager listens for `died`, UIManager for `health_changed` / `weapon_changed`.
##
## Not built yet (good next issues): crouch, aim-down-sights (`aim` action), footsteps.

signal health_changed(current: float, maximum: float)
signal weapon_changed(weapon: WeaponBase)
signal died

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
## How quickly the player reaches target speed on the ground. Higher = snappier.
@export var ground_acceleration: float = 12.0
@export var air_acceleration: float = 3.0
## Degrees of rotation per pixel of mouse movement.
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.15

var weapons: Array[WeaponBase] = []
var current_weapon: WeaponBase
## Read by the HUD (hides the crosshair while aiming).
var is_aiming: bool = false
var is_crouching: bool = false
var _weapon_index: int = 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var health: Health = $Health


func _ready() -> void:
	add_to_group("player")
	health.health_changed.connect(health_changed.emit)
	health.died.connect(_on_died)
	for child in weapon_holder.get_children():
		if child is WeaponBase:
			weapons.append(child)
			child.unequip()
	_equip(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("reload") and current_weapon:
		current_weapon.reload()
	elif event.is_action_pressed("weapon_next"):
		_equip(_weapon_index + 1)
	elif event.is_action_pressed("weapon_prev"):
		_equip(_weapon_index - 1)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).lerp(direction * speed, 1.0 - exp(-accel * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	if current_weapon:
		var trigger := Input.is_action_pressed("fire") if current_weapon.automatic \
				else Input.is_action_just_pressed("fire")
		if trigger:
			current_weapon.try_fire()


func take_damage(amount: float, source: Node = null) -> bool:
	return health.take_damage(amount, source)


func _equip(index: int) -> void:
	if weapons.is_empty():
		return
	index = wrapi(index, 0, weapons.size())
	if weapons[index] == current_weapon:
		return
	if current_weapon:
		current_weapon.unequip()
	_weapon_index = index
	current_weapon = weapons[index]
	current_weapon.equip(self, camera)
	weapon_changed.emit(current_weapon)


func _on_died(_source: Node) -> void:
	# Leave the group so enemies stop targeting us.
	remove_from_group("player")
	set_physics_process(false)
	set_process_unhandled_input(false)
	if current_weapon:
		current_weapon.unequip()
	create_tween().tween_property(head, "position:y", 0.3, 0.6) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	died.emit()
