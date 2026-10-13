class_name Grunt
extends EnemyBase
## Basic melee enemy: runs at the player and hits them when in reach.

@export var melee_damage: float = 10.0


func _attack(attack_target: Node3D) -> void:
	if attack_target.has_method("take_damage"):
		attack_target.take_damage(melee_damage, self)
	if body_mesh:
		var tween := create_tween()
		tween.tween_property(body_mesh, "position:z", -0.35, 0.08)
		tween.tween_property(body_mesh, "position:z", 0.0, 0.15)
