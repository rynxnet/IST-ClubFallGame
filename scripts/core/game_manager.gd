extends Node
## GameManager: owns overall game and match state. Registered as an autoload,
## so any script can reach it as `GameManager`.
##
## Responsibilities (to be built):
##   - Match flow: start, pause, win/lose, restart.
##   - Loading and switching maps (scenes/maps/).
##   - Spawning and respawning the player at map spawn points.
##   - Score, kills, wave/round tracking.
##
## Connects to:
##   - PlayerController / EnemyBase: listens to their signals (died, etc.) and never
##     reaches into their internals.
##   - UIManager: emits game-state signals (score_changed, match_ended, ...) that the
##     UI listens to. GameManager never touches UI nodes directly.
##
## No class_name, because an autoload name and a class_name can't be the same.
