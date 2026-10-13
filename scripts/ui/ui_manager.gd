extends CanvasLayer
## UIManager: shows and hides every screen and the HUD. Registered as an autoload,
## so it's reachable as `UIManager`.
##
## Listens to GameManager (match state), PlayerController (health), and WeaponBase (ammo)
## and only displays them. Menu buttons call into GameManager, and nothing else.
##
## No class_name, because an autoload name and a class_name can't be the same.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const GAME_OVER_SCENE := preload("res://scenes/ui/game_over_screen.tscn")

var hud: Hud
var pause_menu: PauseMenu
var game_over_screen: GameOverScreen

var _weapon: WeaponBase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HUD_SCENE.instantiate()
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	game_over_screen = GAME_OVER_SCENE.instantiate()
	for screen: Control in [hud, pause_menu, game_over_screen]:
		add_child(screen)
		screen.hide()

	GameManager.match_started.connect(_on_match_started)
	GameManager.match_ended.connect(_on_match_ended)
	GameManager.player_spawned.connect(_on_player_spawned)
	GameManager.pause_changed.connect(_on_pause_changed)
	GameManager.score_changed.connect(hud.set_score)
	GameManager.wave_started.connect(hud.set_wave)
	GameManager.enemies_remaining_changed.connect(hud.set_enemies_remaining)

	pause_menu.resume_pressed.connect(GameManager.set_paused.bind(false))
	pause_menu.restart_pressed.connect(GameManager.restart)
	pause_menu.quit_pressed.connect(GameManager.quit)
	game_over_screen.restart_pressed.connect(GameManager.restart)
	game_over_screen.quit_pressed.connect(GameManager.quit)


func _on_match_started() -> void:
	pause_menu.hide()
	game_over_screen.hide()
	hud.reset()
	hud.show()
	hud.show_banner("Survive %d waves" % GameManager.waves_to_win)


func _on_match_ended(won: bool) -> void:
	hud.hide()
	game_over_screen.open(won, GameManager.score, GameManager.wave)


func _on_pause_changed(paused: bool) -> void:
	if paused:
		pause_menu.open()
	else:
		pause_menu.hide()


func _on_player_spawned(player: PlayerController) -> void:
	player.health_changed.connect(hud.set_health)
	player.weapon_changed.connect(_track_weapon)
	hud.set_health(player.health.current, player.health.max_health)
	if player.current_weapon:
		_track_weapon(player.current_weapon)


func _track_weapon(weapon: WeaponBase) -> void:
	if is_instance_valid(_weapon):
		_weapon.ammo_changed.disconnect(hud.set_ammo)
		_weapon.reload_started.disconnect(_on_reload_started)
		_weapon.reload_finished.disconnect(_on_reload_finished)
	_weapon = weapon
	weapon.ammo_changed.connect(hud.set_ammo)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	hud.set_weapon_name(weapon.display_name)
	hud.set_ammo(weapon.ammo_in_magazine, weapon.reserve_ammo)
	hud.set_reloading(weapon.is_reloading())


func _on_reload_started() -> void:
	hud.set_reloading(true)


func _on_reload_finished() -> void:
	hud.set_reloading(false)
