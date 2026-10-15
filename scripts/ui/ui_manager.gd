extends CanvasLayer
## UIManager: shows and hides every screen and the HUD. Registered as an autoload,
## so it's reachable as `UIManager`.
##
## Listens to GameManager (match state), PlayerController (health), and WeaponBase (ammo,
## hits) and only displays them. Menu buttons call into GameManager, and nothing else.
## Each frame it reads the player's spread and aiming state for the dynamic crosshair, and
## hands the player's camera to the HUD for the mission waypoint marker.
##
## Screens: main menu (on main_menu_requested), HUD (during a match; mission mode adds the
## objective tracker), pause menu, game over (waves result or mission failure), and
## mission complete (on mission_completed).
##
## No class_name, because an autoload name and a class_name can't be the same.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const GAME_OVER_SCENE := preload("res://scenes/ui/game_over_screen.tscn")
const MISSION_COMPLETE_SCENE := preload("res://scenes/ui/mission_complete_screen.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")

var hud: Hud
var pause_menu: PauseMenu
var game_over_screen: GameOverScreen
var mission_complete_screen: MissionCompleteScreen
var main_menu: MainMenu

var _player: PlayerController
var _weapon: WeaponBase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HUD_SCENE.instantiate()
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	game_over_screen = GAME_OVER_SCENE.instantiate()
	mission_complete_screen = MISSION_COMPLETE_SCENE.instantiate()
	main_menu = MAIN_MENU_SCENE.instantiate()
	for screen: Control in [hud, pause_menu, game_over_screen, mission_complete_screen, main_menu]:
		add_child(screen)
		screen.hide()

	GameManager.match_started.connect(_on_match_started)
	GameManager.match_ended.connect(_on_match_ended)
	GameManager.player_spawned.connect(_on_player_spawned)
	GameManager.pause_changed.connect(_on_pause_changed)
	GameManager.score_changed.connect(hud.set_score)
	GameManager.wave_started.connect(hud.set_wave)
	GameManager.enemies_remaining_changed.connect(hud.set_enemies_remaining)
	GameManager.objective_changed.connect(hud.set_objective)
	GameManager.objective_progress.connect(hud.set_objective_progress)
	GameManager.objective_completed.connect(hud.show_objective_complete)
	GameManager.mission_completed.connect(_on_mission_completed)
	GameManager.main_menu_requested.connect(_on_main_menu_requested)

	pause_menu.resume_pressed.connect(GameManager.set_paused.bind(false))
	# A restart starts over, so the old objective (and its freed waypoint) goes first.
	for screen: Control in [pause_menu, game_over_screen, mission_complete_screen]:
		screen.restart_pressed.connect(_restart)
		screen.main_menu_pressed.connect(GameManager.return_to_menu)
		screen.quit_pressed.connect(GameManager.quit)
	main_menu.map_selected.connect(GameManager.load_map)
	main_menu.quit_pressed.connect(GameManager.quit)


func _process(_delta: float) -> void:
	if not hud.visible or not is_instance_valid(_player):
		return
	hud.update_waypoint(_player.camera, _player.is_aiming)
	if not is_instance_valid(_weapon):
		return
	# is_sprinting is read loosely so the HUD works with or without a sprint state.
	var hide_crosshair: bool = _player.is_aiming or _player.get(&"is_sprinting") == true or not _weapon.is_equipped
	hud.set_crosshair(_weapon.get_spread_degrees(), _player.camera.fov, not hide_crosshair)


func _on_match_started() -> void:
	var mission := GameManager.mode == &"mission"
	main_menu.hide()
	pause_menu.hide()
	game_over_screen.hide()
	mission_complete_screen.hide()
	hud.reset()
	hud.set_mission_mode(mission)
	hud.show()
	if not mission:
		hud.show_banner("Survive %d waves" % GameManager.waves_to_win)


func _on_match_ended(won: bool) -> void:
	hud.hide()
	var mission := GameManager.mode == &"mission"
	# A mission win is shown by mission_completed instead.
	if mission and won:
		return
	game_over_screen.open(won, GameManager.score, GameManager.wave, mission)


func _on_mission_completed(stats: Dictionary) -> void:
	hud.hide()
	hud.clear_objective()
	pause_menu.hide()
	game_over_screen.hide()
	var map_name: String = MainMenu.MAP_NAMES.get(GameManager.current_map_id, "Mission")
	mission_complete_screen.open(stats, map_name)


func _on_main_menu_requested() -> void:
	hud.clear_objective()
	for screen: Control in [hud, pause_menu, game_over_screen, mission_complete_screen]:
		screen.hide()
	var bests := {}
	for map_id: StringName in MainMenu.MAP_NAMES:
		bests[map_id] = GameManager.get_best(map_id)
	main_menu.open(bests)


func _restart() -> void:
	hud.clear_objective()
	GameManager.restart()


func _on_pause_changed(paused: bool) -> void:
	if paused:
		pause_menu.open()
	else:
		pause_menu.hide()


func _on_player_spawned(player: PlayerController) -> void:
	_player = player
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
		_weapon.hit_landed.disconnect(_on_hit_landed)
	_weapon = weapon
	weapon.ammo_changed.connect(hud.set_ammo)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.hit_landed.connect(_on_hit_landed)
	hud.set_weapon_name(weapon.display_name)
	hud.set_magazine_size(weapon.magazine_size)
	hud.set_ammo(weapon.ammo_in_magazine, weapon.reserve_ammo)
	hud.set_reloading(weapon.is_reloading())


func _on_reload_started() -> void:
	hud.set_reloading(true)


func _on_reload_finished() -> void:
	hud.set_reloading(false)


func _on_hit_landed(headshot: bool, killed: bool) -> void:
	hud.show_hit_marker(headshot, killed)
	if headshot:
		Sfx.play(&"headshot", self)
	if killed:
		Sfx.play(&"kill_confirm", self)
	elif not headshot:
		Sfx.play(&"hitmarker", self)
