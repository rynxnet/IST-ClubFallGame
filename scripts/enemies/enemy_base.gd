class_name EnemyBase
extends CharacterBody3D
## EnemyBase: shared base class every enemy type extends.
##
## Responsibilities (to be built):
##   - Health and taking damage (same damage method the player uses).
##   - AI state (idle, chase, attack) and navigation (NavigationAgent3D).
##   - Attacking the player, optionally using a WeaponBase.
##
## Connects to:
##   - GameManager: emits `died` so GameManager can count kills and waves.
##   - PlayerController: targets the player, but never controls it directly.
##
## Concrete enemies go in scripts/enemies/<name>.gd with `extends EnemyBase`,
## and each gets a matching scene in scenes/enemies/.
