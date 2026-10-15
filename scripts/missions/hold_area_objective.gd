class_name HoldAreaObjective
extends MissionObjective
## Reach the anchor and stay within `radius` metres for `hold_time` seconds in total (e.g. hold
## the LZ until extraction). The timer only runs while the player is inside. From the first
## entry, the director spawns `wave_size` reinforcements every `wave_interval` seconds until it's
## over. Shows a translucent ring around the zone while active.

@export var radius: float = 10.0
@export var hold_time: float = 60.0
## Seconds after first entering before the first reinforcement wave.
@export var first_wave_delay: float = 2.0
@export var wave_interval: float = 15.0
@export var wave_size: int = 3
@export var show_zone: bool = true
@export var zone_color: Color = Color(0.35, 0.95, 0.45, 0.18)
@export var reach_label: String = "Reach the LZ"
## `%d` is replaced with the seconds left.
@export var hold_label: String = "Extraction in %ds"
@export var outside_label: String = "Get back to the LZ!"

var _held: float = 0.0
var _entered: bool = false
var _wave_timer: Timer
var _zone: MeshInstance3D


func setup(mission: MissionDirector) -> void:
	super(mission)
	_wave_timer = Timer.new()
	_wave_timer.one_shot = true
	_wave_timer.timeout.connect(_on_wave_timer)
	add_child(_wave_timer)


func begin() -> void:
	super()
	var waypoint := get_waypoint()
	if show_zone and waypoint:
		_zone = _make_zone()
		director.map.add_child(_zone)
		_zone.global_position = waypoint.global_position + Vector3.UP * 0.7
	_report(0.0, reach_label)


func deactivate() -> void:
	super()
	if _wave_timer:
		_wave_timer.stop()
	if is_instance_valid(_zone):
		_zone.queue_free()


func get_held_time() -> float:
	return _held


func _physics_process(delta: float) -> void:
	if not active:
		return
	var waypoint := get_waypoint()
	if waypoint == null:
		_complete()
		return
	var inside := _player_within(waypoint.global_position, radius)
	if inside:
		if not _entered:
			_entered = true
			_wave_timer.start(first_wave_delay)
		_held += delta
		if _held >= hold_time:
			_complete()
			return
		_report(_held / hold_time, hold_label % ceili(hold_time - _held))
	else:
		_report(_held / hold_time, outside_label if _entered else reach_label)


func _on_wave_timer() -> void:
	if not active:
		return
	director.spawn_reinforcements(wave_size)
	_wave_timer.start(wave_interval)


func _make_zone() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.4
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = zone_color
	mesh.material = material
	var zone := MeshInstance3D.new()
	zone.name = "ExtractionZone"
	zone.mesh = mesh
	zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return zone
