class_name EnemyBase
extends CharacterBody3D
## Shared base every enemy extends: health, death, and a simple state machine that
## chases the player with a NavigationAgent3D.
##
## Subclasses override `_attack(target)` to decide how they hurt the player.
## Emits `died` so GameManager can count kills and waves; never touches the player directly
## except through the shared `take_damage()` contract.
##
## Expected children: Health, NavigationAgent3D, and optionally a "Body" MeshInstance3D
## that flashes when hit.

signal died(enemy: EnemyBase)

enum State { IDLE, CHASE, ATTACK }

const HIT_FLASH_MATERIAL := preload("res://resources/materials/hit_flash.tres")

@export var move_speed: float = 3.5
@export var turn_speed: float = 10.0
@export var attack_range: float = 1.6
@export var attack_cooldown: float = 1.0
@export var score_value: int = 100
## Seconds between path recalculations. Lower = tracks the player more tightly.
@export var repath_interval: float = 0.25

var state: State = State.IDLE
var target: Node3D

var _attack_timer: float = 0.0
var _repath_timer: float = 0.0

@onready var health: Health = $Health
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var body_mesh: MeshInstance3D = get_node_or_null("Body")


func _ready() -> void:
	add_to_group("enemies")
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	target = get_tree().get_first_node_in_group("player") as Node3D
	_update_state()

	var move_dir := Vector3.ZERO
	match state:
		State.CHASE:
			move_dir = _get_chase_direction(delta)
		State.ATTACK:
			_face(target.global_position - global_position, delta)
			if _attack_timer <= 0.0:
				_attack_timer = attack_cooldown
				_attack(target)

	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	if move_dir != Vector3.ZERO:
		_face(move_dir, delta)
	move_and_slide()


func take_damage(amount: float, source: Node = null) -> bool:
	return health.take_damage(amount, source)


## Override in subclasses: hurt `attack_target` (melee hit, fire a weapon, ...).
func _attack(_attack_target: Node3D) -> void:
	pass


func _update_state() -> void:
	if target == null:
		state = State.IDLE
	elif global_position.distance_to(target.global_position) <= attack_range:
		state = State.ATTACK
	else:
		state = State.CHASE


func _get_chase_direction(delta: float) -> Vector3:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		nav_agent.target_position = target.global_position

	var next := target.global_position
	# Querying a nav map before its first sync logs an error, so fall back to a straight line.
	if NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0:
		next = nav_agent.get_next_path_position()

	var dir := next - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = target.global_position - global_position
		dir.y = 0.0
	return dir.normalized()


func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


func _on_health_changed(_current: float, _maximum: float) -> void:
	if body_mesh == null:
		return
	body_mesh.material_overlay = HIT_FLASH_MATERIAL
	create_tween().tween_callback(body_mesh.set_material_overlay.bind(null)).set_delay(0.08)


func _on_died(_source: Node) -> void:
	set_physics_process(false)
	remove_from_group("enemies")
	$CollisionShape3D.set_deferred("disabled", true)
	died.emit(self)
	if body_mesh:
		var tween := create_tween()
		tween.tween_property(body_mesh, "scale", Vector3(1.4, 0.05, 1.4), 0.15)
		tween.tween_callback(queue_free)
	else:
		queue_free()
