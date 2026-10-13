class_name Sfx
extends RefCounted
## Sound effects, called from anywhere: `Sfx.play_at(&"rifle_shot", global_position, self)`.
##
## Sound names: rifle_shot, enemy_shot, dry_fire, reload_out, reload_in, bolt, footstep,
## land, hitmarker, headshot, kill_confirm, player_hurt, enemy_hurt, enemy_death,
## impact_concrete, impact_metal, impact_flesh.
##
## STUB: not implemented yet; calls are silent no-ops.


## Positional sound at a world position. `parent` is any node in the scene tree.
static func play_at(_sound: StringName, _position: Vector3, _parent: Node, _volume_db: float = 0.0) -> void:
	pass


## Non-positional sound (UI, the player's own gun).
static func play(_sound: StringName, _parent: Node, _volume_db: float = 0.0) -> void:
	pass
