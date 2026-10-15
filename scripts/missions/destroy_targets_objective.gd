class_name DestroyTargetsObjective
extends MissionObjective
## Destroy every target placed at `anchors` (e.g. supply caches). Targets are instanced at
## mission start, so ones wrecked early still count. A target scene needs a `destroyed` signal
## and an `is_destroyed` property (see SupplyCache). The waypoint is the next intact target.

@export var target_scene: PackedScene
@export var anchors: Array[StringName] = [&"Cache1", &"Cache2"]
@export var progress_label: String = "Supply caches destroyed"

var targets: Array[Node3D] = []


func setup(mission: MissionDirector) -> void:
	super(mission)
	for anchor_name in anchors:
		var target := director.add_prop(target_scene, anchor_name)
		if target == null:
			continue
		targets.append(target)
		if target.has_signal(&"destroyed"):
			target.connect(&"destroyed", _on_target_destroyed.unbind(1))


func begin() -> void:
	super()
	_report_count()


func get_text() -> String:
	return "%s (%d/%d)" % [text, destroyed_count(), targets.size()]


func get_waypoint() -> Node3D:
	for target in targets:
		if is_instance_valid(target) and not target.get(&"is_destroyed"):
			return target
	return null


func destroyed_count() -> int:
	var count := 0
	for target in targets:
		if not is_instance_valid(target) or target.get(&"is_destroyed"):
			count += 1
	return count


func _physics_process(_delta: float) -> void:
	if active and destroyed_count() >= targets.size():
		_complete()


func _on_target_destroyed() -> void:
	if not active:
		return
	updated.emit()
	_report_count()


func _report_count() -> void:
	if targets.is_empty():
		return
	var count := destroyed_count()
	_report(float(count) / targets.size(), "%s %d/%d" % [progress_label, count, targets.size()])
