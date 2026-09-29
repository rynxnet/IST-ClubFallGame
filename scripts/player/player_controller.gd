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
