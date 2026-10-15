class_name InteractHoldObjective
extends MissionObjective
## Hold the `action` key for `hold_time` seconds within `interact_radius` of a prop placed at
## the anchor (e.g. download intel from a laptop). Leaving the radius or taking damage cancels
## the progress; after damage the key has to be pressed again. Progress shows on the HUD bar.
## When done, calls `set_completed()` on the prop if it has one.

## Instanced at the anchor at mission start.
@export var prop_scene: PackedScene
@export var action: StringName = &"interact"
@export var hold_time: float = 3.0
@export var interact_radius: float = 1.8
@export var prompt_label: String = "Hold [F] to download intel"
@export var progress_label: String = "Downloading intel..."

var prop: Node3D

var _held: float = 0.0
var _needs_release: bool = false
var _last_health: float = -1.0


func setup(mission: MissionDirector) -> void:
	super(mission)
	if prop_scene:
		prop = director.add_prop(prop_scene, anchor)


func get_waypoint() -> Node3D:
	return prop if prop else super()


func get_progress() -> float:
	return _held / hold_time


func _physics_process(delta: float) -> void:
	if not active:
		return
	var player := _player()
	var waypoint := get_waypoint()
	if player == null or waypoint == null:
		return
	var health := player.health.current
	var hurt := _last_health >= 0.0 and health < _last_health
	_last_health = health

	var in_range := _player_within(waypoint.global_position, interact_radius, 2.0)
	var pressed := Input.is_action_pressed(action)
	if not pressed:
		_needs_release = false
	if hurt:
		_needs_release = true
	if not in_range or hurt or not pressed or _needs_release:
		_held = 0.0
	else:
		_held += delta
		if _held >= hold_time:
			if prop and prop.has_method(&"set_completed"):
				prop.call(&"set_completed")
			_complete()
			return

	if not in_range:
		_report(-1.0, "")
	else:
		_report(_held / hold_time, progress_label if _held > 0.0 else prompt_label)
