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

# ============================================================================
# BUILD GUIDE: comments only. Delete each hint as you implement it.
# Related issues in ARCHITECTURE.md: #12 core, #13 AI and navigation, #14 first enemy.
# ============================================================================

# --- Scene tree for each enemy in scenes/enemies/<name>.tscn ---
# <Name> (CharacterBody3D, script extends EnemyBase, layer 3 "enemies", mask world + player)
#   ├─ CollisionShape3D
#   ├─ Model                     imported .glb from assets/models/<name>/
#   ├─ NavigationAgent3D         pathfinding; the map needs a NavigationRegion3D (issue #3)
#   ├─ AttackCooldown (Timer)    one_shot
#   ├─ AudioStreamPlayer3D       alert, attack, and death sounds
#   └─ AnimationPlayer           idle, run, attack, and death animations

# --- Signals to declare ---
# died(enemy)                  GameManager listens (kill count, waves)
# health_changed(new_health)   optional, for floating health bars

# --- @export settings ---
# max_health, move_speed, detection_range, attack_range, attack_damage, attack_cooldown

# --- State to track ---
# current_health, target (the player), current_state
# States: IDLE -> CHASE (player within detection_range) -> ATTACK (within attack_range),
# and DEAD. An enum is the simplest way to start.

# --- Functions to write ---
# _ready()
#     Set current_health, add self to group "enemies", and find the player through
#     group "player".
# _physics_process(delta)
#     Apply gravity, then run the current state: idle waits, chase sets the
#     NavigationAgent3D target and moves toward its next path position, attack
#     hits the player when AttackCooldown allows.
# _change_state(new_state)
#     One place to switch states and play the matching animation.
# take_damage(amount, source)
#     Use the shared damage contract (issue #2), the same as the player. Call die() at 0.
# die()
#     Emit died, set state DEAD, disable collision, play the death animation, then queue_free().
