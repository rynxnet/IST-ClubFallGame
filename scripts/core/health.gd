class_name Health
extends Node
## Reusable health component. Add a child node named "Health" to anything that can be hurt.
##
## Damage contract (shared by player, enemies, and future breakables):
##   Anything that can be hit exposes `take_damage(amount: float, source: Node)`.
##   Weapons only ever call that method; the target forwards it to its Health node.

signal health_changed(current: float, maximum: float)
signal died(source: Node)

@export var max_health: float = 100.0

var current: float
var is_dead: bool = false


func _ready() -> void:
	current = max_health


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	health_changed.emit(current, max_health)
	if current == 0.0:
		is_dead = true
		died.emit(source)


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)
