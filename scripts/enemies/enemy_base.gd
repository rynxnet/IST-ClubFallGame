class_name EnemyBase
extends CharacterBody3D
## Shared base every enemy extends: health, hit reactions, death, line of sight, and a simple
## state machine (idle -> chase -> attack) that chases the player with a NavigationAgent3D.
##
## Subclasses override `_attack(target)` (one melee hit, ...), and optionally
## `_wants_to_attack(target)`, `_attack_update(delta)` (per-frame attack behaviour such as
## aiming and firing) and `_on_state_changed(previous)`.
## Emits `died` exactly once so GameManager can count kills and waves; never touches the player
## except through the shared `take_damage()` contract.
##
## Expected children: Health, NavigationAgent3D, a "CollisionShape3D" body hitbox, a "Head"
## CollisionShape3D (with `damage_multiplier` metadata, read by weapons for headshots), and a
## "Rig" (HumanoidRig) that the base calls down into for animation.

signal died(enemy: EnemyBase)

enum State { IDLE, CHASE, ATTACK }

## Height of the player's chest above their feet: sight lines and shots aim here.
const TARGET_CHEST_HEIGHT := 1.3

@export var move_speed: float = 3.5
## Metres per second squared; real bodies don't reach full speed instantly.
@export var acceleration: float = 18.0
@export var turn_speed: float = 10.0
@export var attack_range: float = 1.6
@export var attack_cooldown: float = 1.0
@export var score_value: int = 100
## Seconds between path recalculations. Lower = tracks the player more tightly.
@export var repath_interval: float = 0.25

@export_group("Senses")
@export var eye_height: float = 1.6
## Seconds between line-of-sight raycasts (throttled so a dozen enemies stay cheap).
@export var sight_interval: float = 0.2

@export_group("Reactions")
## After a non-lethal hit the enemy slows down and can't attack for this long.
@export var stagger_time: float = 0.35
@export_range(0.0, 1.0) var stagger_speed_scale: float = 0.3
## Seconds the body lies there after death (death animation + sinking) before it's freed.
@export var corpse_time: float = 4.0

var state: State = State.IDLE
var target: Node3D
## Cached `_has_line_of_sight(target)`, refreshed every `sight_interval`.
var can_see_target: bool = false

var _attack_timer: float = 0.0
var _repath_timer: float = 0.0
var _sight_timer: float = 0.0
var _stagger_left: float = 0.0
var _last_health: float = 0.0

@onready var health: Health = $Health
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var rig: HumanoidRig = get_node_or_null("Rig")


func _ready() -> void:
	add_to_group("enemies")
	_last_health = health.current
	_sight_timer = randf() * sight_interval
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	if rig:
		rig.footstep.connect(_on_footstep)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_stagger_left = maxf(_stagger_left - delta, 0.0)

	target = get_tree().get_first_node_in_group("player") as Node3D
	_update_sight(delta)
	_update_state()

	var move_dir := Vector3.ZERO
	match state:
		State.CHASE:
			move_dir = _get_chase_direction(delta)
		State.ATTACK:
			_attack_update(delta)

	var speed := move_speed * (stagger_speed_scale if is_staggered() else 1.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(move_dir * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if move_dir != Vector3.ZERO:
		_face(move_dir, delta)
	move_and_slide()

	if rig:
		var moved := get_real_velocity()
		rig.animate(delta, Vector2(moved.x, moved.z).length())


func take_damage(amount: float, source: Node = null) -> bool:
	return health.take_damage(amount, source)


func is_staggered() -> bool:
	return _stagger_left > 0.0


## Override in subclasses: hurt `attack_target` (melee hit, ...).
func _attack(_attack_target: Node3D) -> void:
	pass


## Override in subclasses to decide when to stop chasing and attack.
func _wants_to_attack(attack_target: Node3D) -> bool:
	return global_position.distance_to(attack_target.global_position) <= attack_range


## Runs every physics frame while in ATTACK. Default: face the target and call `_attack()`
## whenever the cooldown allows. Ranged enemies override this to aim and fire.
func _attack_update(delta: float) -> void:
	_face(target.global_position - global_position, delta)
	if _attack_timer <= 0.0 and not is_staggered():
		_attack_timer = attack_cooldown
		_attack(target)


## Called after `state` changes.
func _on_state_changed(_previous: State) -> void:
	pass


## Ray from our eyes to the target's chest against world geometry only.
func _has_line_of_sight(to: Node3D) -> bool:
	var from := global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(from, to.global_position + Vector3.UP * TARGET_CHEST_HEIGHT, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_sight(delta: float) -> void:
	if target == null:
		can_see_target = false
		return
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = sight_interval
		can_see_target = _has_line_of_sight(target)


func _update_state() -> void:
	var previous := state
	if target == null:
		state = State.IDLE
	elif _wants_to_attack(target):
		state = State.ATTACK
	else:
		state = State.CHASE
	if state != previous:
		_on_state_changed(previous)


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


func _on_health_changed(current: float, _maximum: float) -> void:
	var hurt := current < _last_health
	_last_health = current
	if not hurt:
		return
	if rig:
		rig.flash()
	if current <= 0.0:
		return
	_stagger_left = stagger_time
	Sfx.play_at(&"enemy_hurt", global_position + Vector3.UP * 1.4, self)
	if rig:
		rig.play_hit()


func _on_died(_source: Node) -> void:
	set_physics_process(false)
	remove_from_group("enemies")
	state = State.IDLE
	velocity = Vector3.ZERO
	# Corpses don't block bullets or movement.
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	Sfx.play_at(&"enemy_death", global_position + Vector3.UP, self)
	died.emit(self)
	if rig:
		rig.play_death()
	var timer := Timer.new()
	timer.one_shot = true
	timer.autostart = true
	timer.wait_time = corpse_time
	timer.timeout.connect(queue_free)
	add_child(timer)


func _on_footstep() -> void:
	Sfx.play_at(&"footstep", global_position, self, -10.0)
