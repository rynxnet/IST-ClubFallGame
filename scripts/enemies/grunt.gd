class_name Grunt
extends EnemyBase
## Melee rusher in dark tactical gear: runs at the player and strikes with a lunge.
## The blow lands a moment after the lunge starts, so stepping back in time avoids it.

@export var melee_damage: float = 15.0
## Seconds from starting the lunge to the blow landing.
@export var strike_delay: float = 0.18
## How far beyond `attack_range` the lunge still connects.
@export var strike_reach: float = 0.5


func _attack(_attack_target: Node3D) -> void:
	if rig:
		rig.play_attack()
	create_tween().tween_callback(_land_strike).set_delay(strike_delay)


func _land_strike() -> void:
	# `target` is re-read every frame, so it's null if the player died during the wind-up.
	if health.is_dead or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > attack_range + strike_reach:
		return
	if target.has_method("take_damage"):
		target.take_damage(melee_damage, self)
