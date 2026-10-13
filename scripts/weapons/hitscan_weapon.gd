class_name HitscanWeapon
extends WeaponBase
## Instant-hit weapon (rifle, pistol, ...): casts a ray from the aim origin and damages
## the first thing it hits. Optional children: "Model" (kicks back on fire) and
## "MuzzleFlash" (a light shown briefly on fire).

@export var max_range: float = 100.0
@export var recoil_kick: float = 0.04

var _impact_mesh: SphereMesh
var _kick_tween: Tween

@onready var model: Node3D = get_node_or_null("Model")
@onready var muzzle_flash: Node3D = get_node_or_null("MuzzleFlash")


func _ready() -> void:
	super()
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = 0.06
	_impact_mesh.height = 0.12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.4)
	_impact_mesh.material = material


func _shoot() -> void:
	var aim := get_aim_transform()
	var direction := -aim.basis.z
	var spread := deg_to_rad(get_spread_degrees())
	if spread > 0.0:
		direction = direction.rotated(aim.basis.x, randf_range(-spread, spread))
		direction = direction.rotated(aim.basis.y, randf_range(-spread, spread))

	var query := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin + direction * max_range, hit_mask)
	if wielder:
		query.exclude = [wielder.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	_play_fire_feedback()
	if hit.is_empty():
		return
	if hit.collider.has_method("take_damage"):
		var killed: bool = hit.collider.take_damage(damage, wielder)
		hit_landed.emit(false, killed)
	_spawn_impact(hit.position)


func _play_fire_feedback() -> void:
	if muzzle_flash:
		muzzle_flash.show()
		create_tween().tween_callback(muzzle_flash.hide).set_delay(0.05)
	if model:
		if _kick_tween:
			_kick_tween.kill()
		model.position.z = recoil_kick
		_kick_tween = create_tween()
		_kick_tween.tween_property(model, "position:z", 0.0, 0.08)


func _spawn_impact(at: Vector3) -> void:
	var impact := MeshInstance3D.new()
	impact.mesh = _impact_mesh
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(impact)
	impact.global_position = at
	var tween := impact.create_tween()
	tween.tween_property(impact, "scale", Vector3.ONE * 0.1, 0.15)
	tween.tween_callback(impact.queue_free)
