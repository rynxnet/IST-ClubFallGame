extends Node
## GameManager: owns the match. Registered as an autoload, so any script can reach it
## as `GameManager`.
##
## Flow: `scenes/main.tscn` starts empty. With no map chosen (`current_map_id` empty) the game
## sits in MENU and emits `main_menu_requested`; the menu calls `load_map()`, which reloads the
## run scene, puts the map from `MAPS` in it as its `Map` child, and calls `start_match()`.
## `restart()` reloads the same map; `return_to_menu()` drops the match and shows the menu.
##
## Two modes, picked by the map:
##   - waves:   spawn the player, run `waves_to_win` waves of enemies, win if every wave is
##              cleared, lose if the player dies.
##   - mission: the map has a child "Mission" (a MissionDirector, see scripts/missions/). The
##              director runs an objective chain and spawns its own enemies; GameManager relays
##              its signals, tracks stats (time, kills, accuracy, damage), scores and stars the
##              run, and saves the best time/stars per map to `RECORDS_PATH`.
## Also owns pause and mouse capture.
##
## Listens to PlayerController / EnemyBase / MissionDirector signals and never reaches into
## their internals. Emits the signals below for UIManager; it never touches UI nodes directly.
##
## No class_name, because an autoload name and a class_name can't be the same.

signal match_started
signal match_ended(won: bool)
signal player_spawned(player: PlayerController)
signal score_changed(score: int)
signal wave_started(wave: int, total_waves: int)
signal enemies_remaining_changed(count: int)
signal pause_changed(paused: bool)
## Mission mode only. `waypoint` is where the HUD points (null = no marker).
signal objective_changed(text: String, waypoint: Node3D)
## Mission mode only. 0..1 for hold/timer objectives; a negative value hides the bar.
signal objective_progress(fraction: float, label: String)
signal objective_completed(text: String, bonus: int)
## Mission success. Keys: time, kills, headshots, shots_fired, shots_hit, accuracy (0..1),
## damage_taken, score, stars (1-3), best_time, best_stars, new_best (bool).
## Mission failure (player died) still emits match_ended(false).
signal mission_completed(stats: Dictionary)
signal main_menu_requested

enum MatchState { NONE, MENU, PLAYING, WON, LOST }

const MAIN_SCENE := "res://scenes/main.tscn"
const RECORDS_PATH := "user://records.cfg"
const MAPS := {
	&"arena": "res://scenes/maps/arena.tscn",
	&"forest": "res://scenes/maps/forest.tscn",
}
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GRUNT_SCENE := preload("res://scenes/enemies/grunt.tscn")
const SOLDIER_SCENE := preload("res://scenes/enemies/soldier.tscn")

var waves_to_win: int = 5
var time_between_waves: float = 3.0
var time_between_spawns: float = 0.6

var state: MatchState = MatchState.NONE
var score: int = 0
var wave: int = 0
var enemies_remaining: int = 0
var map: GameMap
var player: PlayerController
## &"waves" (arena survival) or &"mission" (map has a MissionDirector).
var mode: StringName = &"waves"
var current_map_id: StringName = &""
## The running MissionDirector in mission mode, else null.
var mission: MissionDirector

## Run stats, counted in both modes (mission mode reports them in `mission_completed`).
var match_time: float = 0.0
var kills: int = 0
## Kills by headshot.
var headshots: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var damage_taken: float = 0.0

var _spawn_queue: Array[PackedScene] = []
var _spawn_index: int = 0
var _wave_timer: Timer
var _spawn_timer: Timer
var _last_player_health: float = 0.0


func _ready() -> void:
	# Always process so the pause key works while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wave_timer = _make_timer(_start_wave)
	_spawn_timer = _make_timer(_spawn_next_enemy)


func _physics_process(delta: float) -> void:
	if state == MatchState.PLAYING and not get_tree().paused:
		match_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if state != MatchState.PLAYING:
		return
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused:
		_set_mouse_captured(true)


## Called by the run scene (main.gd) once it's in the tree: shows the menu if no map is
## chosen, otherwise instances the chosen map as its `Map` child and starts the match.
func begin_run(run_scene: Node) -> void:
	var path: String = MAPS.get(current_map_id, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		current_map_id = &""
		_enter_menu()
		return
	var new_map: GameMap = (load(path) as PackedScene).instantiate()
	new_map.name = "Map"
	run_scene.add_child(new_map)
	start_match(new_map)


func start_match(new_map: GameMap) -> void:
	_stop_timers()
	map = new_map
	score = 0
	wave = 0
	enemies_remaining = 0
	_spawn_queue.clear()
	_reset_stats()
	state = MatchState.PLAYING
	get_tree().paused = false
	mission = map.get_node_or_null(^"Mission") as MissionDirector
	mode = &"mission" if mission else &"waves"

	Sfx.warm_up()
	_spawn_player()
	_set_mouse_captured(true)
	match_started.emit()
	score_changed.emit(score)
	if mission:
		_start_mission()
	else:
		_wave_timer.start(time_between_waves)


## Loads a map from MAPS into the run scene and starts it.
func load_map(map_id: StringName) -> void:
	if not MAPS.has(map_id):
		push_warning("GameManager.load_map: unknown map '%s'" % map_id)
		return
	current_map_id = map_id
	_leave_match()
	get_tree().change_scene_to_file(MAIN_SCENE)


## Starts the same map over.
func restart() -> void:
	_leave_match()
	get_tree().change_scene_to_file(MAIN_SCENE)


## Leaves the match and shows the main menu.
func return_to_menu() -> void:
	current_map_id = &""
	_leave_match()
	_enter_menu()
	get_tree().change_scene_to_file(MAIN_SCENE)


func quit() -> void:
	get_tree().quit()


func set_paused(value: bool) -> void:
	if state != MatchState.PLAYING:
		return
	get_tree().paused = value
	_set_mouse_captured(not value)
	pause_changed.emit(value)


## Saved records for a map: {"best_time": float, "best_stars": int}, or {} if none.
func get_best(map_id: StringName) -> Dictionary:
	var records := ConfigFile.new()
	var section := String(map_id)
	if records.load(RECORDS_PATH) != OK or not records.has_section(section):
		return {}
	return {
		"best_time": float(records.get_value(section, "best_time", 0.0)),
		"best_stars": int(records.get_value(section, "best_stars", 0)),
	}


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	map.add_child(player)
	player.global_transform = map.player_spawn.global_transform
	player.died.connect(_on_player_died)
	_last_player_health = player.health.current
	player.health_changed.connect(_on_player_health_changed)
	for weapon in player.weapons:
		weapon.fired.connect(_on_player_fired)
		weapon.hit_landed.connect(_on_player_hit_landed)
	player_spawned.emit(player)


func _start_wave() -> void:
	wave += 1
	_spawn_queue = _build_wave(wave)
	enemies_remaining = _spawn_queue.size()
	wave_started.emit(wave, waves_to_win)
	enemies_remaining_changed.emit(enemies_remaining)
	_spawn_next_enemy()


## Wave composition: `1 + 2 × wave` enemies. Wave 1 is all grunts (melee rushers); from wave 2
## on, each wave swaps one more grunt for a rifle-armed soldier, mixed into the spawn order.
func _build_wave(wave_number: int) -> Array[PackedScene]:
	var total := 1 + wave_number * 2
	var soldiers := clampi(wave_number - 1, 0, total)
	var scenes: Array[PackedScene] = []
	for i in total:
		scenes.append(SOLDIER_SCENE if i < soldiers else GRUNT_SCENE)
	scenes.shuffle()
	return scenes


# Enemies trickle in one at a time so they don't spawn inside each other.
func _spawn_next_enemy() -> void:
	if state != MatchState.PLAYING or _spawn_queue.is_empty():
		return
	var spawn_points := map.get_enemy_spawn_points()
	var spawn_point := spawn_points[_spawn_index % spawn_points.size()]
	_spawn_index += 1

	var enemy: EnemyBase = _spawn_queue.pop_back().instantiate()
	enemy.move_speed *= 1.0 + 0.08 * (wave - 1)
	map.add_child(enemy)
	enemy.global_position = spawn_point.global_position
	enemy.died.connect(_on_enemy_died)

	if not _spawn_queue.is_empty():
		_spawn_timer.start(time_between_spawns)


func _on_enemy_died(enemy: EnemyBase) -> void:
	if state != MatchState.PLAYING:
		return
	kills += 1
	score += enemy.score_value
	score_changed.emit(score)
	if mode == &"mission":
		return
	enemies_remaining -= 1
	enemies_remaining_changed.emit(enemies_remaining)
	if enemies_remaining > 0:
		return
	if wave >= waves_to_win:
		_end_match(true)
	else:
		_wave_timer.start(time_between_waves)


func _on_player_died() -> void:
	_end_match(false)


func _end_match(won: bool) -> void:
	if state != MatchState.PLAYING:
		return
	state = MatchState.WON if won else MatchState.LOST
	_stop_timers()
	if mission:
		mission.stop()
	_set_mouse_captured(false)
	match_ended.emit(won)


func _on_player_health_changed(current: float, _maximum: float) -> void:
	if state == MatchState.PLAYING and current < _last_player_health:
		damage_taken += _last_player_health - current
	_last_player_health = current


func _on_player_fired() -> void:
	if state != MatchState.PLAYING:
		return
	shots_fired += 1
	if mission and is_instance_valid(player):
		mission.notify_noise(player.global_position)


func _on_player_hit_landed(headshot: bool, killed: bool) -> void:
	if state != MatchState.PLAYING:
		return
	shots_hit += 1
	if headshot and killed:
		headshots += 1


# --- Mission mode ---

func _start_mission() -> void:
	mission.objective_changed.connect(objective_changed.emit)
	mission.objective_progress.connect(objective_progress.emit)
	mission.objective_completed.connect(_on_objective_completed)
	mission.enemy_spawned.connect(_on_mission_enemy_spawned)
	mission.succeeded.connect(_on_mission_succeeded)
	mission.start(map, player)


func _on_mission_enemy_spawned(enemy: EnemyBase) -> void:
	enemy.died.connect(_on_enemy_died)


func _on_objective_completed(text: String, bonus: int) -> void:
	if state != MatchState.PLAYING:
		return
	score += bonus
	score_changed.emit(score)
	objective_completed.emit(text, bonus)


func _on_mission_succeeded() -> void:
	if state != MatchState.PLAYING:
		return
	state = MatchState.WON
	_stop_timers()
	mission.stop()
	mission.stand_down_enemies()
	score += mission.get_time_bonus(match_time)
	score_changed.emit(score)
	var stars := mission.get_stars(match_time, damage_taken)
	var new_best := _save_record(current_map_id, match_time, stars)
	var best := get_best(current_map_id)
	_set_mouse_captured(false)
	mission_completed.emit({
		"time": match_time,
		"kills": kills,
		"headshots": headshots,
		"shots_fired": shots_fired,
		"shots_hit": shots_hit,
		"accuracy": float(shots_hit) / shots_fired if shots_fired > 0 else 0.0,
		"damage_taken": damage_taken,
		"score": score,
		"stars": stars,
		"best_time": float(best.get("best_time", match_time)),
		"best_stars": int(best.get("best_stars", stars)),
		"new_best": new_best,
	})


## Keeps the fastest time and the most stars seen on a map. True if either improved.
func _save_record(map_id: StringName, time: float, stars: int) -> bool:
	if map_id == &"":
		return false
	var records := ConfigFile.new()
	records.load(RECORDS_PATH)  # A missing file just means no records yet.
	var section := String(map_id)
	var had_record := records.has_section(section)
	var best_time := float(records.get_value(section, "best_time", INF))
	var best_stars := int(records.get_value(section, "best_stars", 0))
	records.set_value(section, "best_time", minf(time, best_time))
	records.set_value(section, "best_stars", maxi(stars, best_stars))
	records.save(RECORDS_PATH)
	return not had_record or time < best_time or stars > best_stars


# --- Flow helpers ---

func _reset_stats() -> void:
	match_time = 0.0
	kills = 0
	headshots = 0
	shots_fired = 0
	shots_hit = 0
	damage_taken = 0.0


## Stops whatever is running before the run scene is swapped out.
func _leave_match() -> void:
	_stop_timers()
	if is_instance_valid(mission):
		mission.stop()
	mission = null
	map = null
	player = null
	state = MatchState.NONE
	if get_tree().paused:
		get_tree().paused = false
		pause_changed.emit(false)


func _enter_menu() -> void:
	var announced := state == MatchState.MENU
	state = MatchState.MENU
	_set_mouse_captured(false)
	if not announced:
		main_menu_requested.emit()


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _make_timer(on_timeout: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	# GameManager itself always processes; its timers should still stop while paused.
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	timer.timeout.connect(on_timeout)
	add_child(timer)
	return timer


func _stop_timers() -> void:
	_wave_timer.stop()
	_spawn_timer.stop()
