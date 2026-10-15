class_name ReachAreaObjective
extends MissionObjective
## Complete by getting within `radius` metres of the anchor (e.g. a ridge overlook).

@export var radius: float = 6.0


func _physics_process(_delta: float) -> void:
	if not active:
		return
	var waypoint := get_waypoint()
	if waypoint == null or _player_within(waypoint.global_position, radius):
		_complete()
