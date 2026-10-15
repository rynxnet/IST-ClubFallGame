class_name MissionDirector
extends Node
## Runs a mission on a map. Put a scene whose root uses this script into a map as a child named
## "Mission" and GameManager runs it instead of waves (see scenes/missions/recon_extract.tscn).
##
## Its children are MissionObjective nodes, completed in tree order. Objectives find their
## places in the map by name under the map's `MissionPoints` node (`get_anchor()`), and the
## director spawns the enemies from these anchors there:
##   - OutpostGuards:  Marker3D children, one guard each, holding post facing the marker's -Z.
##   - PatrolRoutes:   Node3D children, each a route of ordered Marker3D waypoints; one
##                     patrolling enemy per route (up to `max_patrols`).
##   - Reinforcements: Marker3D children; objectives call `spawn_reinforcements()`.
## Guards and patrols start unaware (EnemyBase.go_on_watch); reinforcements come in aware.
##
## Signals up to GameManager, which relays them to the UI and scores the run with
## `get_time_bonus()` / `get_stars()`. GameManager calls down: `start()`, `notify_noise()` on
## every player shot, `stop()` and `stand_down_enemies()`.

signal objective_changed(text: String, waypoint: Node3D)
## 0..1 for the current objective; negative hides the bar.
signal objective_progress(fraction: float, label: String)
signal objective_completed(text: String, bonus: int)
## The last objective is done.
signal succeeded
signal enemy_spawned(enemy: EnemyBase)

const GRUNT_SCENE := preload("res://scenes/enemies/grunt.tscn")
const SOLDIER_SCENE := preload("res://scenes/enemies/soldier.tscn")

@export_group("Rating")
## One star for finishing at all, one for finishing within this many seconds...
@export var target_time: float = 480.0
## ...and one for taking at most this much damage.
@export var damage_budget: float = 150.0
## Score bonus for an instant finish, falling linearly to 0 at `time_bonus_zero_at` seconds.
@export var time_bonus_max: int = 2000
@export var time_bonus_zero_at: float = 900.0

@export_group("Encounters")
## Each player shot alerts unaware enemies within this many metres.
@export var hearing_radius: float = 35.0
## At most this many PatrolRoutes get a patrol.
@export var max_patrols: int = 3
## Every Nth outpost guard is a grunt; the rest are soldiers. 0 = all soldiers.
@export var guard_grunt_every: int = 3
## Reinforcements are skipped while this many enemies are alive.
@export var max_alive_enemies: int = 14

var map: GameMap
var player: PlayerController
## The map's MissionPoints node (anchors), or null.
var mission_points: Node

var _objectives: Array[MissionObjective] = []
var _index: int = -1
var _running: bool = false
var _wave_count: int = 0


## Starts the mission: places objective props, spawns the garrison, begins the first objective.
func start(on_map: GameMap, for_player: PlayerController) -> void:
	map = on_map
	player = for_player
	mission_points = map.find_child("MissionPoints", true, false)
	if mission_points == null:
		push_warning("MissionDirector: map has no MissionPoints node")
	_objectives.clear()
	for child in get_children():
		if child is MissionObjective:
			_objectives.append(child)
	for objective in _objectives:
		objective.progressed.connect(_on_objective_progressed.bind(objective))
		objective.updated.connect(_on_objective_updated.bind(objective))
		objective.done.connect(_on_objective_done.bind(objective))
		objective.setup(self)
	_spawn_garrison()
	_running = true
	_activate(0)


## Stops all objectives (match over or leaving). Safe to call repeatedly.
func stop() -> void:
	_running = false
	for objective in _objectives:
		objective.deactivate()


func is_running() -> bool:
	return _running


func get_current_objective() -> MissionObjective:
	return _objectives[_index] if _index >= 0 and _index < _objectives.size() else null


## A player shot (or other loud noise) at `noise_position`: nearby unaware enemies react.
func notify_noise(noise_position: Vector3) -> void:
	if not _running:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy and not enemy.aware and enemy.global_position.distance_to(noise_position) <= hearing_radius:
			enemy.alert(noise_position)


## Mission won: every living enemy stops fighting.
func stand_down_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase:
			(node as EnemyBase).stand_down()


func get_time_bonus(time: float) -> int:
	return roundi(time_bonus_max * clampf(1.0 - time / time_bonus_zero_at, 0.0, 1.0))


func get_stars(time: float, damage_taken: float) -> int:
	return 1 + int(time <= target_time) + int(damage_taken <= damage_budget)


## The node called `anchor_name` under the map's MissionPoints, or null.
func get_anchor(anchor_name: StringName) -> Node3D:
	if mission_points == null or anchor_name == &"":
		return null
	return mission_points.get_node_or_null(NodePath(String(anchor_name))) as Node3D


## The Marker3D children of an anchor (e.g. &"Reinforcements").
func get_markers(anchor_name: StringName) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var anchor_node := get_anchor(anchor_name)
	if anchor_node:
		for child in anchor_node.get_children():
			if child is Marker3D:
				markers.append(child)
	return markers


## Instances `scene` into the map at the anchor's transform. Returns null if either is missing.
func add_prop(scene: PackedScene, anchor_name: StringName) -> Node3D:
	var anchor_node := get_anchor(anchor_name)
	if scene == null or anchor_node == null:
		push_warning("MissionDirector: can't place a prop at missing anchor '%s'" % anchor_name)
		return null
	var prop: Node3D = scene.instantiate()
	map.add_child(prop)
	prop.global_transform = anchor_node.global_transform
	return prop


## Spawns an enemy at `where` (only the yaw of its basis is used) and reports it to GameManager.
func spawn_enemy(scene: PackedScene, where: Transform3D) -> EnemyBase:
	var enemy: EnemyBase = scene.instantiate()
	map.add_child(enemy)
	var forward := -where.basis.z
	enemy.global_transform = Transform3D(Basis(Vector3.UP, atan2(-forward.x, -forward.z)), where.origin + Vector3.UP * 0.1)
	enemy_spawned.emit(enemy)
	return enemy


## Spawns `count` aware enemies spread over the Reinforcements markers (soldiers and grunts
## alternating), keeping the total alive under `max_alive_enemies`.
func spawn_reinforcements(count: int) -> void:
	var markers := get_markers(&"Reinforcements")
	if not _running or markers.is_empty():
		return
	count = mini(count, max_alive_enemies - get_tree().get_nodes_in_group("enemies").size())
	for i in count:
		var slot := _wave_count + i
		var marker := markers[slot % markers.size()]
		# A second enemy on the same marker stands 1.5 m off it.
		var ring := floori(float(i) / markers.size())
		var offset := Vector3.ZERO if ring == 0 else Vector3(1.5, 0.0, 0.0).rotated(Vector3.UP, ring * 2.1)
		var scene := SOLDIER_SCENE if slot % 2 == 0 else GRUNT_SCENE
		spawn_enemy(scene, Transform3D(marker.global_basis, marker.global_position + offset))
	_wave_count += 1


func _spawn_garrison() -> void:
	var guards := get_markers(&"OutpostGuards")
	for i in guards.size():
		var grunt := guard_grunt_every > 0 and i % guard_grunt_every == guard_grunt_every - 1
		var guard := spawn_enemy(GRUNT_SCENE if grunt else SOLDIER_SCENE, guards[i].global_transform)
		guard.go_on_watch()

	var routes := get_anchor(&"PatrolRoutes")
	if routes == null:
		return
	var patrols := 0
	for route in routes.get_children():
		if patrols >= max_patrols:
			break
		var points := PackedVector3Array()
		for waypoint in route.get_children():
			if waypoint is Marker3D:
				points.append((waypoint as Marker3D).global_position)
		if points.is_empty():
			continue
		var scene := SOLDIER_SCENE if patrols % 2 == 0 else GRUNT_SCENE
		var start_at := Transform3D(Basis(), points[0])
		if points.size() > 1:
			start_at = start_at.looking_at(points[1], Vector3.UP)
		var patrol := spawn_enemy(scene, start_at)
		patrol.go_on_watch(points)
		patrols += 1


func _activate(index: int) -> void:
	_index = index
	if index >= _objectives.size():
		_running = false
		succeeded.emit()
		return
	var objective := _objectives[index]
	objective_changed.emit(objective.get_text(), objective.get_waypoint())
	objective.begin()


func _on_objective_progressed(fraction: float, label: String, objective: MissionObjective) -> void:
	if _running and objective == get_current_objective():
		objective_progress.emit(fraction, label)


func _on_objective_updated(objective: MissionObjective) -> void:
	if _running and objective == get_current_objective():
		objective_changed.emit(objective.get_text(), objective.get_waypoint())


func _on_objective_done(objective: MissionObjective) -> void:
	if not _running or objective != get_current_objective():
		return
	objective_progress.emit(-1.0, "")
	objective_completed.emit(objective.text, objective.bonus)
	_activate(_index + 1)
