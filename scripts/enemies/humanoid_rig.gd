class_name HumanoidRig
extends Node3D
## Procedural, purely visual humanoid built from primitive meshes (it has no collision).
##
## The owning enemy calls down into it: `animate(delta, horizontal_speed)` every physics frame
## (walk/run cycle scaled by speed, idle breathing), plus the one-shots `play_attack()`,
## `play_hit()`, `play_death()`, `flash()` and, for rifle carriers, `set_aim(pitch, raised)`.
## It only signals up: `footstep` each time a foot lands.
##
## Node layout (see grunt.tscn / soldier.tscn): Body/Hips holds LegL|R/KneeL|R/FootL|R and
## Spine, which holds Neck and ShoulderL|R/ElbowL|R. Pivots sit at the joints, limbs hang along
## -Y and the figure faces -Z. An optional Body/Hips/RifleSocket carries a weapon; set
## `right_hand_target` / `left_hand_target` to markers on it and the arms hold it with
## two-bone IK instead of swinging.
##
## When real art arrives, give the imported model a script that extends HumanoidRig and
## overrides these same methods to drive its AnimationTree; the enemy scripts won't change.

signal footstep

const HIT_FLASH_MATERIAL := preload("res://resources/materials/hit_flash.tres")
const FLASH_TIME := 0.08
const ATTACK_TIME := 0.5
## Elbow-to-palm distance; matches the Hand mesh offset in the scenes.
const HAND_REACH := 0.3

## Speed (m/s) at which the full running pose is reached.
@export var run_speed: float = 4.0
## Random height difference between instances (0.03 = up to 3 % taller or shorter).
@export var size_variation: float = 0.03
## Hands grab these (e.g. a rifle's grip and handguard) when set.
@export var right_hand_target: Node3D
@export var left_hand_target: Node3D

@export_group("Weapon pose")
## Muzzle pitch (radians) while the weapon is carried at low ready.
@export var low_ready_pitch: float = -0.55
## How far the torso turns side-on (radians) when shouldering the weapon.
@export var aim_twist: float = -0.4
## Elbow directions for the IK, in Spine space.
@export var right_elbow_pole: Vector3 = Vector3(1.0, -0.7, 0.2)
@export var left_elbow_pole: Vector3 = Vector3(-0.6, -1.0, 0.1)

var _time: float = 0.0
var _phase: float = 0.0
## 0 = standing still, 1 = full run.
var _move: float = 0.0
var _flinch: float = 0.0
var _flinch_side: float = 1.0
## Seconds since play_attack(); negative when no attack is playing.
var _attack_t: float = -1.0
var _recoil: float = 0.0
var _aim_pitch: float = 0.0
var _raised: bool = false
var _raise: float = 0.0
var _dead: bool = false
var _meshes: Array[MeshInstance3D] = []
var _flash_tween: Tween

@onready var body: Node3D = $Body
@onready var hips: Node3D = $Body/Hips
@onready var spine: Node3D = $Body/Hips/Spine
@onready var neck: Node3D = $Body/Hips/Spine/Neck
@onready var leg_l: Node3D = $Body/Hips/LegL
@onready var leg_r: Node3D = $Body/Hips/LegR
@onready var knee_l: Node3D = $Body/Hips/LegL/KneeL
@onready var knee_r: Node3D = $Body/Hips/LegR/KneeR
@onready var foot_l: Node3D = $Body/Hips/LegL/KneeL/FootL
@onready var foot_r: Node3D = $Body/Hips/LegR/KneeR/FootR
@onready var shoulder_l: Node3D = $Body/Hips/Spine/ShoulderL
@onready var shoulder_r: Node3D = $Body/Hips/Spine/ShoulderR
@onready var elbow_l: Node3D = $Body/Hips/Spine/ShoulderL/ElbowL
@onready var elbow_r: Node3D = $Body/Hips/Spine/ShoulderR/ElbowR
@onready var weapon_socket: Node3D = get_node_or_null("Body/Hips/RifleSocket")
@onready var _hips_rest: Vector3 = hips.position
@onready var _socket_rest: Vector3 = weapon_socket.position if weapon_socket else Vector3.ZERO
@onready var _shoulder_splay: float = absf(shoulder_r.rotation.z)


func _ready() -> void:
	_meshes.assign(find_children("*", "MeshInstance3D", true, false))
	scale = Vector3.ONE * (1.0 + randf_range(-size_variation, size_variation))
	# Desync instances so a group doesn't breathe and step in lockstep.
	_phase = randf() * TAU
	_time = randf() * 10.0
	_pose()


func animate(delta: float, horizontal_speed: float) -> void:
	if _dead:
		return
	_time += delta
	_move = lerpf(_move, clampf(horizontal_speed / run_speed, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	if horizontal_speed > 0.05:
		var previous := _phase
		# Strides lengthen with speed, so cadence rises more slowly than speed (as in real gait).
		_phase += TAU * horizontal_speed / (1.1 + 0.35 * horizontal_speed) * delta
		if horizontal_speed > 0.5 and floori(_phase / PI) != floori(previous / PI):
			footstep.emit()
		_phase = fmod(_phase, TAU)
	_flinch = move_toward(_flinch, 0.0, delta / 0.3)
	_recoil = move_toward(_recoil, 0.0, delta / 0.09)
	_raise = move_toward(_raise, 1.0 if _raised else 0.0, delta / 0.25)
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t > ATTACK_TIME:
			_attack_t = -1.0
	_pose()


## Melee lunge, or a recoil kick when holding a weapon.
func play_attack() -> void:
	if _dead:
		return
	if weapon_socket:
		_recoil = 1.0
	else:
		_attack_t = 0.0


## Flinch from a hit.
func play_hit() -> void:
	if _dead:
		return
	_flinch = 1.0
	_flinch_side = -1.0 if randf() < 0.5 else 1.0


## Rifle carriers: `pitch` in radians (positive = up). Raised means shouldered and aiming;
## otherwise the weapon is carried at low ready.
func set_aim(pitch: float, raised: bool) -> void:
	_aim_pitch = pitch
	_raised = raised


## White overlay on every mesh for a moment.
func flash() -> void:
	_set_overlay(HIT_FLASH_MATERIAL)
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_callback(_set_overlay.bind(null)).set_delay(FLASH_TIME)


## Knees buckle, the body topples over from the feet, then sinks into the ground (~3.9 s).
## The owner frees the whole enemy afterwards.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	var backward := randf() < 0.65
	var fall := 1.42 if backward else -1.38
	var limp := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	limp.tween_property(hips, "position:y", _hips_rest.y - 0.22, 0.3).set_ease(Tween.EASE_IN)
	limp.tween_property(leg_l, "rotation:x", 0.6, 0.3)
	limp.tween_property(leg_r, "rotation:x", 0.35, 0.3)
	limp.tween_property(knee_l, "rotation:x", -1.1, 0.3)
	limp.tween_property(knee_r, "rotation:x", -0.7, 0.3)
	limp.tween_property(spine, "rotation:x", -0.25 if backward else -0.45, 0.35)
	limp.tween_property(neck, "rotation:x", 0.35 if backward else -0.3, 0.6)
	if weapon_socket:
		limp.tween_property(weapon_socket, "rotation:x", -1.1, 0.4)
	else:
		limp.tween_property(shoulder_l, "rotation", Vector3(0.4, 0.0, -0.5), 0.45)
		limp.tween_property(shoulder_r, "rotation", Vector3(0.2, 0.0, 0.6), 0.45)
	# Topple from the feet, speeding up like a falling body, then settle with a small bounce.
	limp.chain().tween_property(body, "rotation:x", fall, 0.55).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_IN)
	limp.tween_property(body, "rotation:z", randf_range(-0.3, 0.3), 0.55)
	if not backward:
		# Buckled knees would end up in the floor when falling on your face; straighten them.
		limp.tween_property(hips, "position:y", _hips_rest.y - 0.04, 0.4)
		limp.tween_property(leg_l, "rotation:x", 0.1, 0.4)
		limp.tween_property(leg_r, "rotation:x", 0.1, 0.4)
		limp.tween_property(knee_l, "rotation:x", -0.12, 0.4)
		limp.tween_property(knee_r, "rotation:x", -0.12, 0.4)
	limp.chain().tween_property(body, "rotation:x", fall * 0.93, 0.09).set_ease(Tween.EASE_OUT)
	limp.chain().tween_property(body, "rotation:x", fall, 0.12).set_ease(Tween.EASE_IN)
	limp.chain().tween_interval(1.6)
	limp.chain().tween_property(body, "position:y", -0.6, 1.2).set_ease(Tween.EASE_IN)


func _pose() -> void:
	var m := _move
	# Fades the gait in from a standstill so the first step isn't a pop.
	var gait := clampf(m * 6.0, 0.0, 1.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var breathe := sin(_time * 1.7) * (1.0 - m)

	# Thighs swing opposite each other; a knee folds while its leg swings forward.
	var swing := (0.3 + 0.35 * m) * gait
	var fold := (0.3 + 1.0 * m) * gait
	_pose_leg(leg_l, knee_l, foot_l, swing * s, fold * maxf(c, 0.0) + 0.1 * m)
	_pose_leg(leg_r, knee_r, foot_r, -swing * s, fold * maxf(-c, 0.0) + 0.1 * m)

	# Body is highest at mid-stance (twice per cycle) and drops a little when running.
	var bob := (0.015 + 0.02 * m) * gait * cos(2.0 * _phase)
	hips.position = _hips_rest + Vector3(0.0, bob - 0.05 * m, 0.0)
	hips.rotation = Vector3(0.0, 0.12 * m * s * gait, 0.02 * sin(_time * 0.7) * (1.0 - m))

	var lean := -0.22 * m
	spine.rotation = Vector3(lean + 0.02 * breathe + 0.3 * _flinch, -0.18 * m * s * gait,
			0.12 * _flinch * _flinch_side)
	neck.rotation = Vector3(-0.7 * lean + 0.2 * _flinch, 0.25 * sin(_time * 0.37) * (1.0 - m), 0.0)
	body.position = Vector3.ZERO

	if weapon_socket and right_hand_target and left_hand_target:
		_pose_weapon()
	else:
		_pose_free_arms(s, m, gait, breathe)


func _pose_leg(leg: Node3D, knee: Node3D, foot: Node3D, thigh: float, bend: float) -> void:
	leg.rotation.x = thigh
	knee.rotation.x = -bend
	# Keep the sole roughly level with the ground.
	foot.rotation.x = (bend - thigh) * 0.8


func _pose_free_arms(s: float, m: float, gait: float, breathe: float) -> void:
	var swing := (0.12 + 0.5 * m) * gait
	var bend := 0.15 + 1.2 * m
	var splay := _shoulder_splay + 0.02 * breathe
	shoulder_l.rotation = Vector3(-swing * s, 0.0, -splay)
	shoulder_r.rotation = Vector3(swing * s, 0.0, splay)
	elbow_l.rotation.x = bend + 0.3 * m * maxf(s, 0.0)
	elbow_r.rotation.x = bend + 0.3 * m * maxf(-s, 0.0)
	if _attack_t < 0.0:
		return
	# Wind up (right shoulder back, fist cocked), then lunge and strike.
	var wind := _bump(_attack_t, 0.0, 0.1, 0.2)
	var strike := _bump(_attack_t, 0.1, 0.2, ATTACK_TIME)
	var guard := maxf(wind, strike)
	shoulder_r.rotation.x = lerpf(lerpf(shoulder_r.rotation.x, -0.7, wind), 1.5, strike)
	elbow_r.rotation.x = lerpf(lerpf(elbow_r.rotation.x, 1.8, wind), 0.15, strike)
	shoulder_l.rotation.x = lerpf(shoulder_l.rotation.x, 0.7, guard)
	elbow_l.rotation.x = lerpf(elbow_l.rotation.x, 1.6, guard)
	spine.rotation.y += -0.35 * wind + 0.5 * strike
	spine.rotation.x += 0.08 * wind - 0.3 * strike
	body.position.z = 0.06 * wind - 0.35 * strike


func _pose_weapon() -> void:
	var low := 1.0 - _raise
	var pitch := lerpf(low_ready_pitch, _aim_pitch, _raise)
	# Low ready: muzzle down and angled across the body. Raised: stock in the shoulder.
	weapon_socket.position = _socket_rest + Vector3(0.0, -0.17, -0.02) * low \
			+ Vector3(0.0, 0.0, 0.03 * _recoil)
	weapon_socket.rotation = Vector3(pitch + 0.05 * _recoil, 0.2 * low, 0.0)
	var twist := lerpf(aim_twist * 0.5, aim_twist, _raise)
	spine.rotation.y += twist
	spine.rotation.x += 0.35 * _aim_pitch * _raise - 0.04 * _recoil
	neck.rotation.y = -0.9 * twist
	neck.rotation.x += 0.3 * _aim_pitch * _raise - 0.1 * _raise
	# At low ready the right elbow hangs down instead of winging out.
	_reach(shoulder_r, elbow_r, right_hand_target.global_position, right_elbow_pole + Vector3.DOWN * low)
	_reach(shoulder_l, elbow_l, left_hand_target.global_position, left_elbow_pole)


## Two-bone IK in Spine space: aims the shoulder so the elbow bends toward `pole` and the
## palm (HAND_REACH down the forearm) lands on `goal`, or as close as the arm can reach.
func _reach(shoulder: Node3D, elbow: Node3D, goal: Vector3, pole: Vector3) -> void:
	var to_goal := spine.global_transform.affine_inverse() * goal - shoulder.position
	var upper := elbow.position.length()
	var dist := clampf(to_goal.length(), absf(upper - HAND_REACH) + 0.01, upper + HAND_REACH - 0.001)
	var dir := to_goal.normalized()
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.DOWN - dir * dir.y
	bend = bend.normalized()
	var cos_a := clampf((upper * upper + dist * dist - HAND_REACH * HAND_REACH) / (2.0 * upper * dist), -1.0, 1.0)
	var to_elbow := dir * cos_a + bend * sqrt(1.0 - cos_a * cos_a)
	# Limbs hang along -Y; X is the elbow hinge, normal to the plane of the arm.
	var x_axis := dir.cross(bend)
	var y_axis := -to_elbow
	shoulder.basis = Basis(x_axis, y_axis, x_axis.cross(y_axis))
	var hand := shoulder.basis.inverse() * (dir * dist) - elbow.position
	elbow.rotation = Vector3(atan2(-hand.z, -hand.y), 0.0, 0.0)


func _set_overlay(material: Material) -> void:
	for mesh in _meshes:
		mesh.material_overlay = material


## 0 outside [start, end], easing up to 1 at `peak` and back down.
func _bump(t: float, start: float, peak: float, end: float) -> float:
	if t <= start or t >= end:
		return 0.0
	if t < peak:
		return smoothstep(start, peak, t)
	return 1.0 - smoothstep(peak, end, t)
