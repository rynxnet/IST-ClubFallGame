class_name SupplyCache
extends StaticBody3D
## Breakable stack of supply crates (a DestroyTargetsObjective target). Follows the damage
## contract: a `Health` child and `take_damage()`. Only the player can wreck it: shots from
## enemies are ignored. Below `damaged_fraction` health the top crate is knocked askew and
## scorched; at zero it bursts into a fireball, leaves charred debris and emits `destroyed`.
##
## Expected children: Health, CollisionShape3D, Intact (crate meshes, with TopCrate),
## Debris (hidden), Blast (one-shot CPUParticles3D), Flash (OmniLight3D, off).

signal destroyed(cache: SupplyCache)

@export_range(0.0, 1.0) var damaged_fraction: float = 0.5
@export var scorched_material: Material

var is_destroyed: bool = false

var _damaged: bool = false

@onready var health: Health = $Health
@onready var intact: Node3D = $Intact
@onready var top_crate: MeshInstance3D = $Intact/TopCrate
@onready var debris: Node3D = $Debris
@onready var blast: CPUParticles3D = $Blast
@onready var flash: OmniLight3D = $Flash


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)


func take_damage(amount: float, source: Node = null) -> bool:
	if source and source.is_in_group("enemies"):
		return false
	return health.take_damage(amount, source)


func _on_health_changed(current: float, maximum: float) -> void:
	if _damaged or is_destroyed or current <= 0.0 or current > maximum * damaged_fraction:
		return
	_damaged = true
	top_crate.rotation = Vector3(0.12, 0.5, -0.2)
	top_crate.position += Vector3(0.1, -0.05, 0.08)
	if scorched_material:
		top_crate.material_override = scorched_material
	Sfx.play_at(&"impact_metal", global_position + Vector3.UP, self, 2.0)


func _on_died(_source: Node) -> void:
	is_destroyed = true
	intact.hide()
	debris.show()
	$CollisionShape3D.set_deferred(&"disabled", true)
	blast.restart()
	flash.visible = true
	create_tween().tween_property(flash, ^"light_energy", 0.0, 0.6).from(6.0)
	Sfx.play_at(&"impact_metal", global_position + Vector3.UP, self, 6.0)
	Sfx.play_at(&"enemy_death", global_position + Vector3.UP, self, 4.0)
	destroyed.emit(self)
