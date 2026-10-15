class_name EnemyBase
extends CharacterBody3D
## Shared base every enemy extends: health, hit reactions, death, line of sight, and a simple
## state machine (idle -> chase -> attack) that chases the player with a NavigationAgent3D.
##
## Awareness: by default (`starts_aware`, used by arena waves) an enemy always knows where the
## player is. Mission enemies are put "on watch" (`go_on_watch()`): unaware, they walk a patrol
## route or hold a guard post, and only engage once they spot the player (range + view cone +
## line of sight, over `spot_time`), hear something (`alert()`, e.g. a gunshot) or get hurt.
## An enemy that becomes aware alerts allies within `ally_alert_radius`.
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

@export_group("Awareness")
## True: always knows where the player is (arena waves). False: starts on watch.
@export var starts_aware: bool = true
## How far an unaware enemy can spot the player.
@export var view_distance: float = 45.0
## Half-angle of the view cone, in degrees.
@export_range(0.0, 180.0) var view_angle_degrees: float = 65.0
## Within this distance the player is noticed regardless of facing.
@export var close_detect_range: float = 3.0
## Seconds the player must stay in view before being spotted (faster up close).
@export var spot_time: float = 0.7
## Seconds between hearing something and engaging.
@export var alert_reaction_time: float = 0.6
## Allies within this distance are alerted when this enemy becomes aware.
@export var ally_alert_radius: float = 20.0
## Walking speed while patrolling, as a fraction of `move_speed`.
@export_range(0.0, 1.0) var patrol_speed_scale: float = 0.4
## Seconds spent looking around at each patrol waypoint.
@export var patrol_pause: float = 1.5
## Guards sweep their view this many degrees either side of their post's heading.
@export var guard_scan_degrees: float = 40.0

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
## False while on watch (patrolling / guarding); true once engaged.
var aware: bool = true
## Patrol waypoints walked in a loop while unaware. Empty = hold the guard post.
var patrol_points: PackedVector3Array = PackedVector3Array()

var _attack_timer: float = 0.0
var _repath_timer: float = 0.0
var _sight_timer: float = 0.0
var _stagger_left: float = 0.0
var _last_health: float = 0.0
var _stood_down: bool = false
var _post_set: bool = false
var _post_position: Vector3 = Vector3.ZERO
var _post_yaw: float = 0.0
var _patrol_index: int = 0
var _patrol_wait: float = 0.0
var _scan_time: float = 0.0
var _sees_player: bool = false
var _spot_progress: float = 0.0
var _alert_left: float = -1.0
var _alert_position: Vector3 = Vector3.ZERO

@onready var health: Health = $Health
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var rig: HumanoidRig = get_node_or_null("Rig")


func _ready() -> void:
	add_to_group("enemies")
	aware = starts_aware
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

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not aware and not _stood_down:
		_update_awareness(player, delta)
	target = player if aware and not _stood_down else null
	_update_sight(delta)
	_update_state()

	var move_dir := Vector3.ZERO
	var speed_scale := 1.0
	match state:
		State.IDLE:
			if not aware and not _stood_down:
				move_dir = _get_patrol_direction(delta)
				speed_scale = patrol_speed_scale
		State.CHASE:
			move_dir = _get_chase_direction(delta)
		State.ATTACK:
			_attack_update(delta)

	var speed := move_speed * speed_scale * (stagger_speed_scale if is_staggered() else 1.0)
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


## Puts the enemy on watch: unaware, walking `points` in a loop, or (if empty) holding its
## current position and heading as a guard post. Call after placing it in the world.
func go_on_watch(points: PackedVector3Array = PackedVector3Array()) -> void:
	aware = false
	patrol_points = points
	_patrol_index = 0
	_set_post()


## Heard something at `source_position` (a gunshot, an ally calling out): turns towards it and
## engages after `alert_reaction_time`. No effect if already aware.
func alert(source_position: Vector3) -> void:
	if aware or _stood_down or health.is_dead or _alert_left >= 0.0:
		return
	_alert_position = source_position
	_alert_left = alert_reaction_time * randf_range(0.8, 1.3)


## Stops fighting for good (mission over): stands still and ignores the player.
func stand_down() -> void:
	_stood_down = true
	_alert_left = -1.0


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
	return _get_nav_direction(target.global_position, delta)


## Direction to walk now to reach `goal` along the navmesh.
func _get_nav_direction(goal: Vector3, delta: float) -> Vector3:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		nav_agent.target_position = goal

	var next := goal
	# Querying a nav map before its first sync logs an error, so fall back to a straight line.
	if NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0:
		next = nav_agent.get_next_path_position()

	var dir := next - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = goal - global_position
		dir.y = 0.0
	return dir.normalized()


func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


# --- Awareness (only runs while unaware) ---

func _set_post() -> void:
	_post_set = true
	_post_position = global_position
	_post_yaw = rotation.y


func _update_awareness(player: Node3D, delta: float) -> void:
	if _alert_left >= 0.0:
		_alert_left -= delta
		if _alert_left <= 0.0:
			_become_aware()
		return
	if player == null:
		_sees_player = false
		_spot_progress = 0.0
		return
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = sight_interval
		_sees_player = _can_spot(player)
	if _sees_player:
		# Spotted up to twice as fast up close.
		var closeness := 1.0 - clampf(global_position.distance_to(player.global_position) / view_distance, 0.0, 1.0)
		_spot_progress += delta * (1.0 + closeness)
		if _spot_progress >= spot_time:
			_become_aware()
	else:
		_spot_progress = maxf(_spot_progress - delta * 0.5, 0.0)


func _can_spot(player: Node3D) -> bool:
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if distance > view_distance:
		return false
	if distance > close_detect_range:
		var flat := Vector3(to_player.x, 0.0, to_player.z)
		var forward := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
		if flat.length_squared() > 0.0001 and rad_to_deg(forward.angle_to(flat)) > view_angle_degrees:
			return false
	return _has_line_of_sight(player)


func _become_aware() -> void:
	if aware or _stood_down or health.is_dead:
		return
	aware = true
	_alert_left = -1.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var ally := node as EnemyBase
		if ally and ally != self and global_position.distance_to(ally.global_position) <= ally_alert_radius:
			ally.alert(global_position)


## Walk the patrol route (pausing to look around at each waypoint), or hold the guard post.
func _get_patrol_direction(delta: float) -> Vector3:
	if not _post_set:
		_set_post()
	if _alert_left >= 0.0:
		_face(_alert_position - global_position, delta)
		return Vector3.ZERO
	var guarding := patrol_points.is_empty()
	var goal := _post_position if guarding else patrol_points[_patrol_index % patrol_points.size()]
	var offset := goal - global_position
	offset.y = 0.0
	if offset.length() > 0.8:
		return _get_nav_direction(goal, delta)

	_scan_time += delta
	if guarding:
		var yaw := _post_yaw + sin(_scan_time * 0.6) * deg_to_rad(guard_scan_degrees)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-3.0 * delta))
		return Vector3.ZERO
	_patrol_wait += delta
	if _patrol_wait >= patrol_pause:
		_patrol_wait = 0.0
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_repath_timer = 0.0
	return Vector3.ZERO


func _on_health_changed(current: float, _maximum: float) -> void:
	var hurt := current < _last_health
	_last_health = current
	if not hurt:
		return
	if rig:
		rig.flash()
	if current <= 0.0:
		return
	_become_aware()
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
