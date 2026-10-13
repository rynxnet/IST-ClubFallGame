class_name WeaponHolder
extends Node3D
## Procedural first-person weapon motion. Sits under the camera and poses the held gun every
## frame: hip/aim-down-sights blend, sway that trails mouse look, walk/sprint bob, the lowered
## sprint pose, per-shot kick, a landing dip, and idle breathing.
##
## Purely visual and driven from above: PlayerController calls `update_pose()` once per frame,
## plus `kick()` when a shot fires and `land()` on landing. It never reads the player.
##
## The transform authored in the scene is the hip pose. At full aim the holder sits exactly at
## the weapon's `aim_position` (camera space) with no rotation, so its sight lines up with the
## screen centre.

@export_group("Sway")
## Seconds the gun trails the view when you turn. Bigger feels heavier.
@export var sway_lag: float = 0.025
@export var max_sway_degrees: float = 5.0
## How quickly sway and bob follow their targets.
@export var sway_smoothing: float = 12.0
## Sideways/vertical shift in metres per degree of sway.
@export var sway_shift_per_degree: float = 0.003
@export_range(0.0, 1.0) var aim_sway_multiplier: float = 0.3

@export_group("Bob")
## Side-to-side (x) and up-down (y) bob in metres at walking speed. Scales with speed.
@export var bob_amplitude: Vector2 = Vector2(0.012, 0.007)
@export var bob_roll_degrees: float = 1.2
@export_range(0.0, 1.0) var aim_bob_multiplier: float = 0.12
## Idle breathing rise and fall in metres.
@export var breath_amplitude: float = 0.0015
## Breaths per second.
@export var breath_rate: float = 0.25

@export_group("Sprint pose")
## Offset from the hip pose (metres, camera space) when fully into the sprint pose.
@export var sprint_offset: Vector3 = Vector3(-0.06, -0.05, 0.05)
## Muzzle tipped down and swung across the body.
@export var sprint_rotation_degrees: Vector3 = Vector3(-18.0, 40.0, 14.0)

@export_group("Kick")
## Metres the gun slides back toward you per degree of view recoil.
@export var kickback_per_degree: float = 0.025
## Muzzle rise in degrees per degree of view recoil.
@export var kick_rise_per_degree: float = 2.5
## Random roll per shot in degrees, at one degree of view recoil.
@export var kick_roll_degrees: float = 1.0
## How quickly the gun settles after a shot. Higher = snappier.
@export var kick_recovery: float = 14.0
## Cap on stacked kick (in degrees of view recoil) during sustained fire.
@export var max_kick: float = 2.5

@export_group("Landing")
## Metres the gun drops per m/s of landing speed.
@export var land_drop_per_speed: float = 0.006
@export var max_land_drop: float = 0.06
## Muzzle dip in degrees per centimetre of drop.
@export var land_pitch_per_cm: float = 0.9
@export var land_recovery: float = 6.0

const LAND_SNAP: float = 30.0

var _hip_position: Vector3
var _hip_rotation: Vector3
var _sway := Vector2.ZERO
var _bob_weight: float = 0.0
var _breath_phase: float = 0.0
var _kick: float = 0.0
var _kick_roll: float = 0.0
var _land_target: float = 0.0
var _land: float = 0.0


func _ready() -> void:
	_hip_position = position
	_hip_rotation = rotation


## Call once per frame.
## `look_delta`: degrees the view turned this frame (x = yaw left, y = pitch up).
## `aim_blend` / `sprint_blend`: 0..1 progress into aiming / the sprint pose.
## `aim_position`: the held weapon's camera-space sight offset.
## `bob_phase`: stride phase in radians; 0 and PI are footfalls.
## `bob_weight`: horizontal speed / walk speed (0 when airborne).
func update_pose(delta: float, look_delta: Vector2, aim_blend: float, aim_position: Vector3,
		sprint_blend: float, bob_phase: float, bob_weight: float) -> void:
	var aim := smoothstep(0.0, 1.0, aim_blend)
	var sprint := smoothstep(0.0, 1.0, sprint_blend)
	var follow := 1.0 - exp(-sway_smoothing * delta)

	# Swaying against the turn rate (not the per-frame delta) keeps it framerate independent.
	var sway_target := (look_delta * (-sway_lag / maxf(delta, 0.001))).limit_length(max_sway_degrees)
	_sway = _sway.lerp(sway_target, follow)
	_bob_weight = lerpf(_bob_weight, bob_weight, follow)
	_breath_phase = fmod(_breath_phase + TAU * breath_rate * delta, TAU)
	var settle := exp(-kick_recovery * delta)
	_kick *= settle
	_kick_roll *= settle
	_land_target *= exp(-land_recovery * delta)
	_land = lerpf(_land, _land_target, 1.0 - exp(-LAND_SNAP * delta))

	var sway := _sway * lerpf(1.0, aim_sway_multiplier, aim)
	var bob := _bob_weight * lerpf(1.0, aim_bob_multiplier, aim)
	var stride_side := sin(bob_phase)

	var pos := _hip_position.lerp(aim_position, aim) + sprint_offset * sprint
	pos.x += -sway.x * sway_shift_per_degree + stride_side * bob_amplitude.x * bob
	# -cos(2 * phase) puts the low point of the bob on each footfall.
	pos.y += sway.y * sway_shift_per_degree - cos(2.0 * bob_phase) * bob_amplitude.y * bob \
			+ sin(_breath_phase) * breath_amplitude * lerpf(1.0, 0.5, aim) - _land
	pos.z += _kick * kickback_per_degree

	var rot := _hip_rotation.lerp(Vector3.ZERO, aim) + sprint_rotation_degrees * (sprint * PI / 180.0)
	rot.x += deg_to_rad(sway.y + _kick * kick_rise_per_degree - _land * 100.0 * land_pitch_per_cm)
	rot.y += deg_to_rad(sway.x)
	rot.z += deg_to_rad(sway.x * 0.5 + stride_side * bob_roll_degrees * bob + _kick_roll)
	position = pos
	rotation = rot


## A shot fired. `strength` is the view recoil it caused, in degrees.
func kick(strength: float) -> void:
	_kick = minf(_kick + strength, max_kick)
	_kick_roll = clampf(_kick_roll + randf_range(-kick_roll_degrees, kick_roll_degrees) * strength,
			-kick_roll_degrees * max_kick, kick_roll_degrees * max_kick)


## The wielder hit the ground at `impact_speed` m/s.
func land(impact_speed: float) -> void:
	_land_target = minf(_land_target + impact_speed * land_drop_per_speed, max_land_drop)
