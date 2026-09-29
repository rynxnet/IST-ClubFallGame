extends CanvasLayer
## UIManager: shows and hides every screen and the HUD. Registered as an autoload,
## so it's reachable as `UIManager`.
##
## Responsibilities (to be built):
##   - HUD: health, ammo, crosshair, score.
##   - Menus: main menu, pause, settings, game over.
##   - Loading screens from scenes/ui/.
##
## Connects to:
##   - Listens to signals from GameManager (match state), PlayerController (health),
##     and WeaponBase (ammo). It only reads and displays, and never drives gameplay.
##   - Menu buttons call into GameManager (e.g. "restart"), and nothing else.
##
## No class_name, because an autoload name and a class_name can't be the same.

# ============================================================================
# BUILD GUIDE: comments only. Delete each hint as you implement it.
# Related issues in ARCHITECTURE.md: #18 HUD, #19 main menu, #20 pause, #21 settings, #22 game over.
# ============================================================================

# --- No scene of its own ---
# This is an autoload, so it adds UI scenes as its own children at runtime. Build each
# screen as a separate scene in scenes/ui/ so different people can own different screens:
#   scenes/ui/hud.tscn         Control (full rect)
#                                ├─ Crosshair (TextureRect, centered)
#                                ├─ HealthLabel / HealthBar
#                                ├─ AmmoLabel (bottom right)
#                                └─ ScoreLabel (top)
#   scenes/ui/main_menu.tscn   Play, Settings, and Quit buttons
#   scenes/ui/pause_menu.tscn  Resume, Settings, and Quit to Menu buttons
#   scenes/ui/settings.tscn    sensitivity, volume, and graphics options
#   scenes/ui/game_over.tscn   win/lose text and Restart / Menu buttons
# Each screen's script goes in scripts/ui/<screen>.gd.

# --- State to track ---
# References to each instanced screen (hud, main_menu, pause_menu, ...).

# --- Functions to write ---
# _ready()
#     Set process_mode to ALWAYS so the pause menu still works when the game is paused.
#     Connect to GameManager's signals: match_started, match_ended, score_changed,
#     player_spawned.
# _unhandled_input(event)
#     The "pause" action toggles the pause menu and calls GameManager.set_paused().
# show_screen(screen)
#     Hide everything else and show this one. Show or capture the mouse cursor to match.
# _on_player_spawned(player)
#     Connect player.health_changed and the weapon's ammo_changed to the HUD.
# _on_match_ended(player_won)
#     Show game_over with the right text.
# Rule: this script only DISPLAYS state and forwards button presses to GameManager.
# No gameplay logic here.
