class_name PlayerController
extends CharacterBody3D
## PlayerController: the local player's first-person body: movement, mouse look,
## jumping/crouching, health, and input for the equipped weapon.
##
## Responsibilities (to be built):
##   - Read input actions (defined in Project Settings > Input Map).
##   - Move the CharacterBody3D and rotate the camera head.
##   - Hold a WeaponBase child and tell it when to fire/reload/switch.
##   - Track health and take damage.
##
## Connects to:
##   - WeaponBase: calls down into the equipped weapon. Weapon logic lives there, not here.
##   - GameManager: emits `died` and similar signals. GameManager decides about respawns.
##   - UIManager: emits `health_changed` etc. UIManager listens, and the player never
##     calls the UI.
##
## Scene: scenes/player/player.tscn (to be created by whoever claims the player issue).

# ============================================================================
# BUILD GUIDE: comments only. Delete each hint as you implement it.
# Related issues in ARCHITECTURE.md: #4 movement, #5 mouse look, #6 health, #7 weapons.
# ============================================================================

# --- Scene tree to build in scenes/player/player.tscn ---
# PlayerController (CharacterBody3D, this script, collision layer 2 "player")
#   ├─ CollisionShape3D      CapsuleShape3D, about 1.8 m tall
#   ├─ Model (optional)      body mesh from assets/models/, usually hidden in first person
#   └─ Head (Node3D)         about 1.6 m up; rotate THIS on X for looking up/down
#        ├─ Camera3D
#        └─ WeaponHolder (Node3D)   the equipped WeaponBase scene is added here
# Rotate the body on Y for left/right, and the Head on X for up/down.

# --- Signals to declare ---
# died                         GameManager listens (respawn / game over)
# health_changed(new_health)   UIManager listens (HUD)

# --- @export settings (tweakable in the Inspector) ---
# walk_speed, sprint_speed, jump_velocity, mouse_sensitivity, max_health

# --- State to track ---
# current_health, current_weapon (a WeaponBase or null)

# --- Functions to write ---
# _ready()
#     Capture the mouse, set current_health = max_health, and add self to group "player"
#     so enemies can find you.
# _unhandled_input(event)
#     Mouse motion rotates the body and the Head (clamp the vertical angle).
#     fire / reload / weapon_next go to current_weapon.
# _physics_process(delta)
#     Apply gravity, jump when on the floor, turn input actions into a direction
#     relative to where you're facing, set velocity, then call move_and_slide().
# take_damage(amount, source)
#     Use the shared damage contract (issue #2). Lower health, emit health_changed,
#     and call die() at 0.
# die()
#     Emit died and disable input. Don't respawn yourself, since GameManager does that.
# equip_weapon(weapon_scene)
#     Instance it under WeaponHolder, free the old one, and store it in current_weapon.
