class_name WeaponBase
extends Node3D
## WeaponBase: shared base class every weapon extends (rifle, pistol, shotgun, ...).
##
## Responsibilities (to be built):
##   - Common interface: fire, reload, equip/unequip, ammo counts, fire rate.
##   - Hit detection (hitscan raycast or spawning projectiles).
##   - Applying damage to whatever was hit (players/enemies share one damage method).
##   - Hooks for effects: muzzle flash, sound, recoil animation.
##
## Connects to:
##   - PlayerController (or an EnemyBase) owns the weapon and calls its methods.
##   - UIManager: emits `ammo_changed` for the HUD to display.
##
## Concrete weapons go in scripts/weapons/<name>.gd with `extends WeaponBase`,
## and each gets a matching scene in scenes/weapons/.
