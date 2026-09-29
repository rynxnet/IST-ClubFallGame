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

# ============================================================================
# BUILD GUIDE: comments only. Delete each hint as you implement it.
# Related issues in ARCHITECTURE.md: #8 core, #9 hitscan, #10 projectile, #11 feedback.
# ============================================================================

# --- Scene tree for each weapon in scenes/weapons/<name>.tscn ---
# <Name> (Node3D, script extends WeaponBase)
#   ├─ Model                 imported .glb from assets/models/<name>/
#   ├─ Muzzle (Marker3D)     where shots, flashes, and projectiles start
#   ├─ RayCast3D             hitscan only; point it forward (-Z), mask = world + enemies
#   ├─ FireRateTimer (Timer) one_shot; blocks firing until it times out
#   ├─ ReloadTimer (Timer)   one_shot; wait_time = reload_time
#   ├─ AudioStreamPlayer3D   fire and reload sounds
#   └─ AnimationPlayer       recoil and reload animations (optional at first)

# --- Signals to declare ---
# ammo_changed(in_magazine, in_reserve)   UIManager listens (HUD)
# fired                                   hook for effects and sound
# reloaded

# --- @export settings (each weapon subclass sets its own values) ---
# damage, fire_rate (shots per second), magazine_size, max_reserve_ammo,
# reload_time, max_range, is_automatic

# --- State to track ---
# ammo_in_magazine, ammo_in_reserve, is_reloading

# --- Functions to write ---
# can_fire() -> bool
#     Has ammo, isn't reloading, and FireRateTimer has stopped.
# fire()
#     Called by the owner (player/enemy). Check can_fire(), use 1 ammo, start
#     FireRateTimer, call _shoot(), emit fired and ammo_changed.
# _shoot()
#     OVERRIDE in subclasses. A hitscan subclass reads the RayCast3D hit. A projectile
#     subclass spawns a projectile scene at Muzzle. Either way, call _apply_hit().
# _apply_hit(target, hit_position)
#     If target follows the damage contract (issue #2), deal damage. Spawn an impact effect.
# reload()
#     Start ReloadTimer. When it finishes, move ammo from reserve to magazine and emit
#     reloaded and ammo_changed.
# equip() / unequip()
#     Show or hide the model, and emit ammo_changed so the HUD updates on switch.
