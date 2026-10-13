extends Node
## GameManager: owns the match. Registered as an autoload, so any script can reach it
## as `GameManager`.
##
## Current loop: spawn the player, run `waves_to_win` waves of enemies, win if every wave
## is cleared, lose if the player dies. Also owns pause and mouse capture.
##
## Listens to PlayerController / EnemyBase signals and never reaches into their internals.
## Emits the signals below for UIManager; it never touches UI nodes directly.
##
## No class_name, because an autoload name and a class_name can't be the same.

signal match_started
signal match_ended(won: bool)
signal player_spawned(player: PlayerController)
signal score_changed(score: int)
signal wave_started(wave: int, total_waves: int)
signal enemies_remaining_changed(count: int)
signal pause_changed(paused: bool)

enum MatchState { NONE, PLAYING, WON, LOST }

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

var _spawn_queue: Array[PackedScene] = []
var _spawn_index: int = 0
var _wave_timer: Timer
var _spawn_timer: Timer


func _ready() -> void:
	# Always process so the pause key works while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wave_timer = _make_timer(_start_wave)
	_spawn_timer = _make_timer(_spawn_next_enemy)


func _unhandled_input(event: InputEvent) -> void:
	if state != MatchState.PLAYING:
		return
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused:
		_set_mouse_captured(true)


func start_match(new_map: GameMap) -> void:
	_stop_timers()
	map = new_map
	score = 0
	wave = 0
	enemies_remaining = 0
	_spawn_queue.clear()
	state = MatchState.PLAYING
	get_tree().paused = false

	Sfx.warm_up()
	_spawn_player()
	_set_mouse_captured(true)
	match_started.emit()
	score_changed.emit(score)
	_wave_timer.start(time_between_waves)


func restart() -> void:
	_stop_timers()
	state = MatchState.NONE
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit() -> void:
	get_tree().quit()


func set_paused(value: bool) -> void:
	if state != MatchState.PLAYING:
		return
	get_tree().paused = value
	_set_mouse_captured(not value)
	pause_changed.emit(value)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	map.add_child(player)
	player.global_transform = map.player_spawn.global_transform
	player.died.connect(_on_player_died)
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
	score += enemy.score_value
	enemies_remaining -= 1
	score_changed.emit(score)
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
	_set_mouse_captured(false)
	match_ended.emit(won)


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
