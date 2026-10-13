class_name PlayerController
extends CharacterBody3D
## The local player's first-person body: walk/sprint/crouch/jump, mouse look, aim-down-sights,
## view recoil, damage flinch, landing dip, footsteps, health, and weapon input.
##
## Calls down into its weapons (WeaponBase children of WeaponHolder) and into WeaponHolder,
## which it feeds movement and aim state every frame so the gun is posed procedurally.
## Signals up: GameManager listens for `died`, UIManager for `health_changed` / `weapon_changed`.
## The HUD reads `is_aiming`.
##
## Movement and firing run in `_physics_process`; purely visual smoothing (FOV, eye height,
## camera offsets, gun pose) runs in `_process` so it stays smooth above the physics rate.

signal health_changed(current: float, maximum: float)
signal weapon_changed(weapon: WeaponBase)
signal died

@export_group("Movement")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var crouch_speed: float = 2.5
## Top speed while aiming down sights.
@export var aim_speed: float = 3.0
@export var jump_velocity: float = 4.5
## How quickly the player reaches target speed on the ground. Higher = snappier.
@export var ground_acceleration: float = 12.0
@export var air_acceleration: float = 3.0

@export_group("Look")
## Degrees of rotation per pixel of mouse movement at the base FOV. Scaled down while zoomed
## so the sights don't feel twitchy.
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.15
@export var base_fov: float = 80.0
## Seconds to bring the sights up to your eye (and back down).
@export var aim_transition_time: float = 0.18

@export_group("Crouch")
@export var stand_height: float = 1.8
## Jersey barriers are 1.1 m tall, so a crouched player fits fully behind one.
@export var crouch_height: float = 1.1
@export var stand_eye_height: float = 1.6
@export var crouch_eye_height: float = 0.95
## How quickly the view moves between standing and crouched eye height.
@export var crouch_transition_speed: float = 10.0

@export_group("Sprint")
## Seconds to swing the gun into (and out of) the lowered sprint pose.
@export var sprint_transition_time: float = 0.25
## After sprinting the gun can fire once it has come back up past this point (0 = fully up).
@export_range(0.0, 1.0) var sprint_fire_threshold: float = 0.2

@export_group("Recoil")
## How quickly the view snaps to the recoil kick. Higher = sharper.
@export var recoil_snappiness: float = 30.0
## How quickly the view settles back. Lower = more climb under sustained fire.
@export var recoil_recovery: float = 4.0
@export_range(0.0, 1.0) var aim_recoil_multiplier: float = 0.7
@export_range(0.0, 1.0) var crouch_recoil_multiplier: float = 0.7
## Cap on accumulated view kick, in degrees.
@export var max_recoil_degrees: float = 12.0

@export_group("Damage flinch")
## Damage in one hit that produces a full-strength shake.
@export var damage_for_full_shake: float = 35.0
@export var max_shake_degrees: float = 2.0
@export var shake_frequency: float = 20.0
## Shake strength lost per second (1.0 = a full shake lasts one second).
@export var shake_decay: float = 1.8
## View jolt in degrees for a full-strength hit.
@export var flinch_degrees: float = 4.0

@export_group("Landing")
## Falls slower than this (m/s) don't count as a landing.
@export var land_min_speed: float = 2.5
## Metres the view dips per m/s of impact speed.
@export var land_dip_per_speed: float = 0.015
@export var max_land_dip: float = 0.16
## The view also nods down this many degrees per m/s of impact speed.
@export var land_pitch_per_speed: float = 0.35
@export var land_recovery: float = 7.0

@export_group("Footsteps")
## Metres per step at crouch speed; strides lengthen up to the max at sprint speed.
@export var stride_length_min: float = 1.3
@export var stride_length_max: float = 2.4
@export var footstep_volume_db: float = -3.0
@export var sprint_footstep_volume_db: float = 0.0
@export var crouch_footstep_volume_db: float = -14.0

## How quickly the view drops into a landing dip (it recovers at `land_recovery`).
const LAND_SNAP: float = 30.0
## Below this horizontal speed the player counts as standing still.
const MIN_STRIDE_SPEED: float = 0.5

var weapons: Array[WeaponBase] = []
var current_weapon: WeaponBase
## Read by the HUD (hides the crosshair while aiming).
var is_aiming: bool = false
var is_crouching: bool = false
var is_sprinting: bool = false
var _weapon_index: int = 0
var _horizontal_speed: float = 0.0
var _aim_blend: float = 0.0
var _sprint_blend: float = 0.0
var _eye_height: float
var _land_dip: float = 0.0
var _land_dip_target: float = 0.0
## Stride phase in radians; footsteps land at 0 and PI.
var _stride_phase: float = 0.0
## Degrees the view turned since the last frame, for weapon sway.
var _look_delta := Vector2.ZERO
## Camera offsets in degrees (x pitch, y yaw, z roll) from recoil, flinches and landings.
var _view_kick := Vector3.ZERO
var _view_kick_target := Vector3.ZERO
var _shake_trauma: float = 0.0
var _shake_time: float = 0.0
var _last_health: float
var _noise := FastNoiseLite.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: WeaponHolder = $Head/Camera3D/WeaponHolder
@onready var health: Health = $Health
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = collision_shape.shape


func _ready() -> void:
	add_to_group("player")
	camera.fov = base_fov
	_eye_height = stand_eye_height
	head.position.y = _eye_height
	_set_capsule_height(stand_height)
	_noise.seed = randi()
	_noise.frequency = 1.0
	_last_health = health.current
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	for child in weapon_holder.get_children():
		if child is WeaponBase:
			weapons.append(child)
			child.unequip()
			child.fired.connect(_on_weapon_fired.bind(child))
	_equip(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := mouse_sensitivity * camera.fov / base_fov
		var pitch_before := head.rotation.x
		rotate_y(deg_to_rad(-event.relative.x * sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * sensitivity))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
		_look_delta.x -= event.relative.x * sensitivity
		_look_delta.y += rad_to_deg(head.rotation.x - pitch_before)
	elif event.is_action_pressed(&"reload") and current_weapon:
		current_weapon.reload()
	elif event.is_action_pressed(&"weapon_next"):
		_equip(_weapon_index + 1)
	elif event.is_action_pressed(&"weapon_prev"):
		_equip(_weapon_index - 1)


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	_update_crouch()
	if not was_on_floor:
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed(&"jump") and not is_crouching:
		velocity.y = jump_velocity

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	is_aiming = Input.is_action_pressed(&"aim") and current_weapon != null \
			and not current_weapon.is_reloading()
	# Needs real speed too, so leaning into a wall doesn't drop the gun into the sprint pose.
	is_sprinting = Input.is_action_pressed(&"sprint") and input_dir.y < -0.5 \
			and not is_aiming and not is_crouching and _horizontal_speed > 1.0

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var accel := ground_acceleration if was_on_floor else air_acceleration
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).lerp(direction * _get_target_speed(),
			1.0 - exp(-accel * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var fall_speed := -velocity.y
	move_and_slide()

	var on_floor := is_on_floor()
	_horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if on_floor and not was_on_floor and fall_speed >= land_min_speed:
		_on_landed(fall_speed)
	elif on_floor:
		_advance_stride(delta)

	if current_weapon:
		current_weapon.set_handling(is_aiming, _horizontal_speed / sprint_speed, not on_floor, is_crouching)
		# The gun is lowered while sprinting and needs a moment to come back up.
		if not is_sprinting and _sprint_blend <= sprint_fire_threshold:
			var trigger := Input.is_action_pressed(&"fire") if current_weapon.automatic \
					else Input.is_action_just_pressed(&"fire")
			if trigger:
				current_weapon.try_fire()


func _process(delta: float) -> void:
	_aim_blend = move_toward(_aim_blend, 1.0 if is_aiming else 0.0,
			delta / maxf(aim_transition_time, 0.001))
	_sprint_blend = move_toward(_sprint_blend, 1.0 if is_sprinting else 0.0,
			delta / maxf(sprint_transition_time, 0.001))
	var aim_fov := current_weapon.aim_fov if current_weapon else base_fov
	camera.fov = lerpf(base_fov, aim_fov, smoothstep(0.0, 1.0, _aim_blend))

	var target_eye := crouch_eye_height if is_crouching else stand_eye_height
	_eye_height = lerpf(_eye_height, target_eye, 1.0 - exp(-crouch_transition_speed * delta))
	_land_dip_target = lerpf(_land_dip_target, 0.0, 1.0 - exp(-land_recovery * delta))
	_land_dip = lerpf(_land_dip, _land_dip_target, 1.0 - exp(-LAND_SNAP * delta))
	head.position.y = _eye_height - _land_dip

	_update_camera_offset(delta)

	var aim_position := current_weapon.aim_position if current_weapon else Vector3.ZERO
	var bob_weight := _horizontal_speed / walk_speed if is_on_floor() else 0.0
	weapon_holder.update_pose(delta, _look_delta, _aim_blend, aim_position, _sprint_blend,
			_stride_phase, bob_weight)
	_look_delta = Vector2.ZERO


func take_damage(amount: float, source: Node = null) -> bool:
	return health.take_damage(amount, source)


func _get_target_speed() -> float:
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed
	if is_aiming:
		speed = minf(speed, aim_speed)
	return speed


func _update_crouch() -> void:
	if Input.is_action_pressed(&"crouch"):
		if not is_crouching:
			is_crouching = true
			_set_capsule_height(crouch_height)
	elif is_crouching and not test_move(global_transform, Vector3.UP * (stand_height - crouch_height)):
		is_crouching = false
		_set_capsule_height(stand_height)


# Keeps the capsule's bottom at the body origin so the feet stay on the floor.
func _set_capsule_height(height: float) -> void:
	_capsule.height = height
	collision_shape.position.y = height * 0.5


func _advance_stride(delta: float) -> void:
	if _horizontal_speed < MIN_STRIDE_SPEED:
		return
	var pace := clampf(inverse_lerp(crouch_speed, sprint_speed, _horizontal_speed), 0.0, 1.0)
	var stride := lerpf(stride_length_min, stride_length_max, pace)
	var previous := _stride_phase
	_stride_phase += PI * _horizontal_speed * delta / stride
	if _stride_phase >= TAU:
		_stride_phase -= TAU
		_play_footstep()
	elif previous < PI and _stride_phase >= PI:
		_play_footstep()


func _play_footstep() -> void:
	var volume := footstep_volume_db
	if is_crouching:
		volume = crouch_footstep_volume_db
	elif is_sprinting:
		volume = sprint_footstep_volume_db
	Sfx.play(&"footstep", self, volume)


func _on_landed(fall_speed: float) -> void:
	_land_dip_target = minf(_land_dip_target + fall_speed * land_dip_per_speed, max_land_dip)
	_view_kick_target.x -= fall_speed * land_pitch_per_speed
	# A landing is a footfall: restart the stride so the next step comes a full stride later.
	_stride_phase = 0.0
	weapon_holder.land(fall_speed)
	Sfx.play(&"land", self, clampf(remap(fall_speed, land_min_speed, 9.0, -10.0, 0.0), -10.0, 0.0))


func _update_camera_offset(delta: float) -> void:
	_view_kick_target = _view_kick_target.lerp(Vector3.ZERO, 1.0 - exp(-recoil_recovery * delta))
	_view_kick = _view_kick.lerp(_view_kick_target, 1.0 - exp(-recoil_snappiness * delta))
	var offset := _view_kick
	if _shake_trauma > 0.0:
		_shake_trauma = maxf(_shake_trauma - shake_decay * delta, 0.0)
		_shake_time += delta * shake_frequency
		# Squaring trauma makes small hits subtle and big hits violent.
		var shake := _shake_trauma * _shake_trauma * max_shake_degrees
		offset.x += shake * _noise.get_noise_2d(_shake_time, 0.0)
		offset.y += shake * _noise.get_noise_2d(_shake_time, 50.0)
		offset.z += shake * _noise.get_noise_2d(_shake_time, 100.0)
	# Keep head pitch + kick short of straight up so the view can't flip over.
	offset.x = minf(offset.x, 89.5 - rad_to_deg(head.rotation.x))
	camera.rotation = Vector3(deg_to_rad(offset.x), deg_to_rad(offset.y), deg_to_rad(offset.z))


func _on_weapon_fired(weapon: WeaponBase) -> void:
	var strength := 1.0
	if is_aiming:
		strength *= aim_recoil_multiplier
	if is_crouching:
		strength *= crouch_recoil_multiplier
	_view_kick_target.x = minf(_view_kick_target.x + weapon.recoil_pitch * strength, max_recoil_degrees)
	_view_kick_target.y = clampf(
			_view_kick_target.y + randf_range(-weapon.recoil_yaw, weapon.recoil_yaw) * strength,
			-max_recoil_degrees, max_recoil_degrees)
	weapon_holder.kick(weapon.recoil_pitch * strength)


func _on_health_changed(current: float, maximum: float) -> void:
	if current < _last_health:
		_flinch(_last_health - current)
	_last_health = current
	health_changed.emit(current, maximum)


func _flinch(damage: float) -> void:
	var strength := clampf(damage / damage_for_full_shake, 0.15, 1.0)
	_shake_trauma = minf(_shake_trauma + strength, 1.0)
	var jolt := flinch_degrees * strength
	_view_kick_target += Vector3(randf_range(-0.5, 1.0) * jolt, randf_range(-1.0, 1.0) * jolt,
			(1.0 if randf() < 0.5 else -1.0) * randf_range(0.5, 1.0) * jolt)
	Sfx.play(&"player_hurt", self)


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
	set_process(false)
	set_process_unhandled_input(false)
	is_aiming = false
	is_sprinting = false
	if current_weapon:
		current_weapon.unequip()
	var tween := create_tween().set_parallel()
	tween.tween_property(head, "position:y", 0.3, 0.6) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "fov", base_fov, 0.4)
	tween.tween_property(camera, "rotation", Vector3(0.0, 0.0, deg_to_rad(18.0)), 0.6)
	died.emit()
