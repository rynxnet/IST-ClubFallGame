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
