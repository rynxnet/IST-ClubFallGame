class_name Soldier
extends EnemyBase
## Rifleman in olive gear. Chases until the player is within `attack_range` with a clear line
## of sight, then stops, shoulders the rifle and fires short bursts. The aim swings onto the
## target with some lag and a random error per burst, so a moving player is hard to hit.
## If it loses sight of the player it goes back to chasing via the navmesh.
##
## Fires an instanced WeaponBase (`weapon`, see enemy_rifle.tscn) equipped with `aim_node`
## as the aim origin, so shots travel along that node's -Z.

@export var weapon: WeaponBase
@export var aim_node: Node3D
## Seconds between first seeing the player and opening fire.
@export var reaction_time: float = 0.6
@export var burst_size: int = 3
@export var burst_pause_min: float = 1.0
@export var burst_pause_max: float = 1.8
## How quickly the aim swings onto the target; lower = more lag against a moving player.
@export var aim_speed: float = 7.0
## Random aim error per burst, in degrees, on top of the rifle's own spread.
@export var aim_error_degrees: float = 1.2
## Only starts a burst once the aim is this close (degrees) to the target.
@export var fire_cone_degrees: float = 6.0
## Keeps holding position this long after losing sight, instead of flip-flopping at corners.
@export var lose_sight_grace: float = 0.6
## Once engaged, keeps shooting until the player is this much beyond `attack_range`.
@export var disengage_margin: float = 3.0

var _aim_dir: Vector3 = Vector3.FORWARD
var _aim_offset: Vector3 = Vector3.ZERO
var _reaction_left: float = 0.0
var _burst_left: int = 0
var _pause_left: float = 0.0
var _unseen_time: float = 0.0


func _ready() -> void:
	super()
	weapon.equip(self, aim_node)


func _physics_process(delta: float) -> void:
	super(delta)
	if state != State.ATTACK:
		# Carry the rifle at low ready, pointing where we're going.
		_swing_aim(-global_basis.z, delta)
		_apply_aim(false)


func _wants_to_attack(attack_target: Node3D) -> bool:
	var reach := attack_range + (disengage_margin if state == State.ATTACK else 0.0)
	if global_position.distance_to(attack_target.global_position) > reach:
		return false
	if can_see_target:
		return true
	return state == State.ATTACK and _unseen_time < lose_sight_grace


func _on_state_changed(_previous: State) -> void:
	if state == State.ATTACK:
		_reaction_left = reaction_time * randf_range(0.8, 1.3)
		_burst_left = 0
		_pause_left = 0.0
		_unseen_time = 0.0


func _attack_update(delta: float) -> void:
	_unseen_time = 0.0 if can_see_target else _unseen_time + delta
	_reaction_left -= delta
	_pause_left -= delta
	_face(target.global_position - global_position, delta)

	var aim_point := target.global_position + Vector3.UP * TARGET_CHEST_HEIGHT + _aim_offset
	var wanted := (aim_point - aim_node.global_position).normalized()
	_swing_aim(wanted, delta)
	_apply_aim(true)

	if _reaction_left > 0.0 or not can_see_target or is_staggered():
		return
	if _burst_left <= 0:
		if _pause_left > 0.0 or rad_to_deg(_aim_dir.angle_to(wanted)) > fire_cone_degrees:
			return
		_start_burst(aim_point.distance_to(aim_node.global_position))
	if weapon.try_fire():
		_burst_left -= 1
		if rig:
			rig.play_attack()
		if _burst_left <= 0:
			_pause_left = randf_range(burst_pause_min, burst_pause_max)


func _start_burst(distance: float) -> void:
	_burst_left = burst_size
	var error := distance * tan(deg_to_rad(aim_error_degrees))
	_aim_offset = Vector3(randf_range(-1.0, 1.0), randf_range(-0.7, 0.7), randf_range(-1.0, 1.0)) * error


func _swing_aim(wanted: Vector3, delta: float) -> void:
	_aim_dir = _aim_dir.slerp(wanted, 1.0 - exp(-aim_speed * delta)).normalized()


func _apply_aim(raised: bool) -> void:
	# Basis.looking_at() can't look straight up or down.
	if absf(_aim_dir.y) < 0.99:
		aim_node.global_basis = Basis.looking_at(_aim_dir)
	if rig:
		rig.set_aim(asin(clampf(_aim_dir.y, -1.0, 1.0)), raised)
