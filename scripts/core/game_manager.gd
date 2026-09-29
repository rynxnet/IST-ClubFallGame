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

# ============================================================================
# BUILD GUIDE: comments only. Delete each hint as you implement it.
# Related issues in ARCHITECTURE.md: #15 match flow, #16 spawning, #17 map loading.
# ============================================================================

# --- No scene of its own ---
# This is an autoload (see project.godot), so it's created once at startup and
# lives for the whole game. It works with nodes in scenes/main.tscn:
#   Main (Node)
#     └─ <current map>      GameManager swaps this child when loading maps
# Maps mark player spawns with Marker3D nodes in group "player_spawns", and
# enemy spawns with Marker3D nodes in group "enemy_spawns".

# --- Signals to declare ---
# match_started
# match_ended(player_won)
# score_changed(new_score)
# player_spawned(player)       UIManager uses this to connect to the new player's signals

# --- State to track ---
# current_state (MENU, PLAYING, PAUSED, GAME_OVER), current_map, player, score, kills

# --- Functions to write ---
# load_map(map_path)
#     Free the old map under Main, then instance and add the new one.
# start_match()
#     Reset score and kills, spawn the player, start enemy waves, emit match_started.
# spawn_player()
#     Instance scenes/player/player.tscn at a "player_spawns" marker, connect its
#     died signal, and emit player_spawned.
# _on_player_died()
#     Respawn after a delay, or end_match(false), depending on the game mode.
# _on_enemy_died(enemy)
#     Add score and kills, emit score_changed, and check for a win or next wave.
# end_match(player_won)
#     Set GAME_OVER, emit match_ended. UIManager shows the right screen.
# set_paused(paused) / restart() / quit_to_menu()
#     Called by UIManager menu buttons.
