class_name WeaponBase
extends Node3D
## Shared base every weapon extends. Handles ammo, fire rate, and reloading.
## Subclasses override `_shoot()` to decide what one shot does (raycast, projectile, ...).
##
## The owner (player or enemy) calls `equip()`, `try_fire()`, and `reload()`.
## UIManager listens to `ammo_changed` / `reload_started` / `reload_finished`.

signal ammo_changed(in_magazine: int, reserve: int)
signal fired
signal reload_started
signal reload_finished

@export var display_name: String = "Weapon"
@export var damage: float = 20.0
## Shots per second.
@export var fire_rate: float = 8.0
## Hold to keep firing. If false, one shot per click.
@export var automatic: bool = true
@export var magazine_size: int = 30
@export var reserve_ammo: int = 300
@export var reload_time: float = 1.5
## What shots can hit. Default: world + enemies.
@export_flags_3d_physics var hit_mask: int = 0b101

var ammo_in_magazine: int
var is_equipped: bool = false
## The body holding this weapon. Excluded from hits so you can't shoot yourself.
var wielder: CollisionObject3D
## Shots travel along this node's -Z. For the player that's the camera, so shots
## land on the crosshair rather than coming out of the gun model.
var aim_origin: Node3D

var _cooldown: float = 0.0
var _reload_left: float = 0.0


func _ready() -> void:
	ammo_in_magazine = magazine_size


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


func is_reloading() -> bool:
	return _reload_left > 0.0


func equip(new_wielder: CollisionObject3D, new_aim_origin: Node3D) -> void:
	wielder = new_wielder
	aim_origin = new_aim_origin
	is_equipped = true
	show()
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)


func unequip() -> void:
	is_equipped = false
	_reload_left = 0.0
	hide()


func can_fire() -> bool:
	return is_equipped and _cooldown <= 0.0 and not is_reloading() and ammo_in_magazine > 0


## Fires one shot if possible. Returns true if a shot happened.
func try_fire() -> bool:
	if not can_fire():
		if is_equipped and ammo_in_magazine == 0:
			reload()
		return false
	_cooldown = 1.0 / fire_rate
	ammo_in_magazine -= 1
	_shoot()
	fired.emit()
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)
	return true


func reload() -> void:
	if not is_equipped or is_reloading() or ammo_in_magazine == magazine_size or reserve_ammo <= 0:
		return
	_reload_left = reload_time
	reload_started.emit()


func get_aim_transform() -> Transform3D:
	return aim_origin.global_transform if aim_origin else global_transform


## Override in subclasses: perform one shot.
func _shoot() -> void:
	pass


func _finish_reload() -> void:
	_reload_left = 0.0
	var taken := mini(magazine_size - ammo_in_magazine, reserve_ammo)
	reserve_ammo -= taken
	ammo_in_magazine += taken
	reload_finished.emit()
	ammo_changed.emit(ammo_in_magazine, reserve_ammo)
