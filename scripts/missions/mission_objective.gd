class_name MissionObjective
extends Node
## One step of a MissionDirector's chain. Add it as a child of the director; steps run in tree
## order. Subclasses watch the player each physics frame while `active` and call `_complete()`.
##
## Lifecycle (called by the director): `setup()` once at mission start (place props),
## `begin()` when it becomes the current objective, `deactivate()` when it ends or the mission
## stops. Signals up: `progressed` (shown as the HUD bar), `updated` (text or waypoint changed),
## `done`.

signal progressed(fraction: float, label: String)
signal updated
signal done

## Shown on the HUD while this is the current objective.
@export var text: String = ""
## Score awarded on completion.
@export var bonus: int = 250
## Node under the map's MissionPoints that this objective is about; also the HUD waypoint.
@export var anchor: StringName = &""

var director: MissionDirector
var active: bool = false

var _last_fraction: float = -2.0
var _last_label: String = ""


func setup(mission: MissionDirector) -> void:
	director = mission
	if anchor != &"" and director.get_anchor(anchor) == null:
		push_warning("%s: MissionPoints/%s is missing" % [name, anchor])


func begin() -> void:
	active = true


func deactivate() -> void:
	active = false


## Objective text, possibly with live counts.
func get_text() -> String:
	return text


## Where the HUD should point, or null.
func get_waypoint() -> Node3D:
	return director.get_anchor(anchor) if director else null


## The player, or null once it's gone.
func _player() -> PlayerController:
	if director == null or not is_instance_valid(director.player):
		return null
	return director.player


## True if the player is within `radius` metres of `point` horizontally (and not far above or
## below it, so a cliff top doesn't count for the valley under it).
func _player_within(point: Vector3, radius: float, vertical_slack: float = 4.0) -> bool:
	var player := _player()
	if player == null:
		return false
	var offset := player.global_position - point
	return Vector2(offset.x, offset.z).length() <= radius and absf(offset.y) <= vertical_slack


## Emits `progressed` only when something changed.
func _report(fraction: float, label: String) -> void:
	if is_equal_approx(fraction, _last_fraction) and label == _last_label:
		return
	_last_fraction = fraction
	_last_label = label
	progressed.emit(fraction, label)


func _complete() -> void:
	if not active:
		return
	deactivate()
	done.emit()
