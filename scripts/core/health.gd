class_name Health
extends Node
## Reusable health component. Add a child node named "Health" to anything that can be hurt.
##
## Damage contract (shared by player, enemies, and future breakables):
##   Anything that can be hit exposes `take_damage(amount: float, source: Node) -> bool`,
##   returning true if that hit killed it. Weapons only ever call that method; the target
##   forwards it to its Health node.

signal health_changed(current: float, maximum: float)
signal died(source: Node)

@export var max_health: float = 100.0
## Seconds without taking damage before regeneration starts. Only used if regen_per_second > 0.
@export var regen_delay: float = 5.0
@export var regen_per_second: float = 0.0

var current: float
var is_dead: bool = false

var _since_hit: float = 0.0


func _ready() -> void:
	current = max_health
	set_process(regen_per_second > 0.0)


func _process(delta: float) -> void:
	if is_dead or current >= max_health:
		return
	_since_hit += delta
	if _since_hit >= regen_delay:
		heal(regen_per_second * delta)


## Returns true if this hit killed the owner.
func take_damage(amount: float, source: Node = null) -> bool:
	if is_dead or amount <= 0.0:
		return false
	_since_hit = 0.0
	current = maxf(current - amount, 0.0)
	health_changed.emit(current, max_health)
	if current == 0.0:
		is_dead = true
		died.emit(source)
		return true
	return false


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)
