class_name HitscanWeapon
extends WeaponBase
## Instant-hit weapon (rifle, pistol, ...): casts a ray from the aim origin, damages the first
## thing it hits, and draws the shot: muzzle flash, tracer, impact particles, bullet holes,
## and sounds.
##
## Every child is optional, so an enemy rifle can be a bare node with this script:
##   "Model"           kicks back on fire and tilts during reloads.
##   "Model/Magazine"  drops out and goes back in during reloads.
##   "Muzzle"          Marker3D at the barrel tip where the flash and tracer start
##                     (falls back to this node's origin).
##   "MuzzleFlash"     a light shown briefly on fire.
##
## Headshots: if the CollisionShape3D that was hit has meta `damage_multiplier`, damage is
## scaled by it, and a multiplier above 1 counts as a headshot.
## Surfaces: a world body with meta `surface = "metal"` (or a metallic material) throws sparks
## and plays metal impacts; anything else throws concrete dust and chips.

enum Surface { CONCRETE, METAL, FLESH }

const BULLET_HOLE_TEXTURE := preload("res://resources/effects/bullet_hole.tres")
const GLOW_TEXTURE := preload("res://resources/effects/glow.tres")
const PUFF_TEXTURE := preload("res://resources/effects/soft_puff.tres")
## Oldest bullet holes are removed beyond this many (shared by every weapon in the scene).
const MAX_BULLET_HOLES := 60
const BULLET_HOLES_NODE := &"BulletHoles"
const TRACER_WIDTH := 0.012
const TRACER_LIFE := 0.05
const LIGHT_LIFE := 0.05

@export var max_range: float = 100.0
## How far "Model" slides back per shot, in metres (it also tips up a little).
## 0 when the wielder animates recoil itself, like the player's WeaponHolder.
@export var recoil_kick: float = 0.04
## Sfx name played at the muzzle on every shot (enemy rifles use &"enemy_shot").
@export var shot_sound: StringName = &"rifle_shot"

# Effect meshes are shared by every hitscan weapon and built once.
static var _tracer_mesh: ArrayMesh
static var _flash_mesh: QuadMesh
static var _spark_mesh: BoxMesh
static var _chip_mesh: BoxMesh
static var _dust_mesh: QuadMesh
static var _droplet_mesh: BoxMesh
static var _mist_mesh: QuadMesh
static var _fade_ramp: Gradient
static var _grow_curve: Curve
static var _shrink_curve: Curve

var _kick_tween: Tween
var _tracer: MeshInstance3D
var _tracer_tween: Tween
var _flash: Node3D
var _flash_frame: int = -1
var _light_left: float = 0.0
var _magazine_rest: Vector3

@onready var model: Node3D = get_node_or_null("Model")
@onready var magazine: Node3D = get_node_or_null("Model/Magazine")
@onready var muzzle: Node3D = get_node_or_null("Muzzle")
@onready var muzzle_flash: Node3D = get_node_or_null("MuzzleFlash")


func _ready() -> void:
	super()
	if _tracer_mesh == null:
		_build_shared_effects()
	if magazine:
		_magazine_rest = magazine.position
	if muzzle_flash:
		muzzle_flash.hide()

	_tracer = MeshInstance3D.new()
	_tracer.mesh = _tracer_mesh
	_tracer.top_level = true
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer.visible = false
	add_child(_tracer)

	_flash = _make_flash()
	(muzzle if muzzle else self as Node3D).add_child(_flash)


func _process(delta: float) -> void:
	# The flash is drawn for exactly one frame, like a real one.
	if _flash.visible and Engine.get_process_frames() > _flash_frame:
		_flash.hide()
	if _light_left > 0.0:
		_light_left -= delta
		if _light_left <= 0.0 and muzzle_flash:
			muzzle_flash.hide()
	_update_reload_pose()


func _shoot() -> void:
	var aim := get_aim_transform()
	var direction := _spread_direction(aim.basis, deg_to_rad(get_spread_degrees()))
	var end := aim.origin + direction * max_range
	var query := PhysicsRayQueryParameters3D.create(aim.origin, end, hit_mask)
	if wielder:
		query.exclude = [wielder.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var muzzle_position := muzzle.global_position if muzzle else global_position
	_play_fire_feedback()
	Sfx.play_at(shot_sound, muzzle_position, self)
	if not hit.is_empty():
		end = hit.position
	_show_tracer(muzzle_position, end)
	if hit.is_empty() or hit.collider == null:
		return

	var collider: Object = hit.collider
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	if collider.has_method("take_damage"):
		var multiplier := _damage_multiplier(collider, hit.shape)
		var killed: bool = collider.take_damage(damage * multiplier, wielder) == true
		hit_landed.emit(multiplier > 1.0, killed)
		_spawn_impact(point, normal, Surface.FLESH)
	else:
		_spawn_impact(point, normal, Surface.METAL if _is_metal(collider) else Surface.CONCRETE)
		_spawn_bullet_hole(point, normal)


func _play_reload_cue(cue: StringName) -> void:
	super(cue)
	if cue == &"bolt":
		_kick_model(0.012, 0.6)


# Uniform over the cone's disc, so the crosshair gap matches where shots can land.
func _spread_direction(basis: Basis, spread: float) -> Vector3:
	var forward := -basis.z.normalized()
	if spread <= 0.0:
		return forward
	var radius := spread * sqrt(randf())
	var angle := randf() * TAU
	return forward.rotated(basis.x.normalized(), radius * sin(angle)) \
			.rotated(basis.y.normalized(), radius * cos(angle))


func _damage_multiplier(collider: Object, shape_index: int) -> float:
	var body := collider as CollisionObject3D
	if body == null:
		return 1.0
	var shape := body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as Node
	if shape and shape.has_meta(&"damage_multiplier"):
		return float(shape.get_meta(&"damage_multiplier"))
	return 1.0


func _is_metal(collider: Object) -> bool:
	if collider.has_meta(&"surface"):
		return str(collider.get_meta(&"surface")) == "metal"
	# CSG shapes expose `material`; mesh-based bodies may use material_override.
	var material: Variant = collider.get(&"material")
	if material == null and collider is GeometryInstance3D:
		material = (collider as GeometryInstance3D).material_override
	return material is BaseMaterial3D and (material as BaseMaterial3D).metallic >= 0.3


func _play_fire_feedback() -> void:
	if muzzle_flash:
		muzzle_flash.show()
		_light_left = LIGHT_LIFE
	_flash.rotation.z = randf() * TAU
	var flash_size := randf_range(0.75, 1.2)
	_flash.scale = Vector3(flash_size, flash_size, flash_size * randf_range(0.8, 1.3))
	_flash.show()
	_flash_frame = Engine.get_process_frames()
	# The player's WeaponHolder animates its own recoil, so player rifles leave this at 0.
	if recoil_kick > 0.0:
		_kick_model(recoil_kick, recoil_kick * 30.0)


func _kick_model(push: float, pitch_degrees: float) -> void:
	if model == null:
		return
	if _kick_tween:
		_kick_tween.kill()
	model.position.z = push
	model.rotation.x = deg_to_rad(pitch_degrees)
	_kick_tween = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_kick_tween.tween_property(model, "position:z", 0.0, 0.09)
	_kick_tween.tween_property(model, "rotation:x", 0.0, 0.12)


func _show_tracer(from: Vector3, to: Vector3) -> void:
	var offset := to - from
	var length := offset.length()
	if length < 1.0:
		return
	var forward := offset / length
	var up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(forward, up)
	basis.x *= TRACER_WIDTH
	basis.y *= TRACER_WIDTH
	basis.z *= length
	_tracer.global_transform = Transform3D(basis, from)
	_tracer.transparency = 0.0
	_tracer.show()
	if _tracer_tween:
		_tracer_tween.kill()
	_tracer_tween = create_tween()
	_tracer_tween.tween_property(_tracer, "transparency", 1.0, TRACER_LIFE)
	_tracer_tween.tween_callback(_tracer.hide)


func _spawn_impact(point: Vector3, normal: Vector3, surface: Surface) -> void:
	var parent := _effects_parent()
	match surface:
		Surface.FLESH:
			var mist := _burst(_mist_mesh, 4, 0.45, 0.4, 1.4, 35.0)
			mist.gravity = Vector3(0.0, -1.5, 0.0)
			mist.color_ramp = _fade_ramp
			mist.scale_amount_curve = _grow_curve
			_launch(mist, point, normal)
			_launch(_burst(_droplet_mesh, 8, 0.5, 1.5, 3.5, 45.0), point, normal)
			Sfx.play_at(&"impact_flesh", point, parent)
		Surface.METAL:
			var sparks := _burst(_spark_mesh, 10, 0.35, 3.0, 8.0, 60.0)
			sparks.particle_flag_align_y = true
			sparks.scale_amount_curve = _shrink_curve
			_launch(sparks, point, normal)
			_launch(_dust(3), point, normal)
			Sfx.play_at(&"impact_metal", point, parent)
		_:
			_launch(_dust(5), point, normal)
			_launch(_burst(_chip_mesh, 6, 0.6, 2.0, 4.5, 40.0), point, normal)
			Sfx.play_at(&"impact_concrete", point, parent)


func _dust(amount: int) -> CPUParticles3D:
	var dust := _burst(_dust_mesh, amount, 0.9, 0.5, 1.6, 25.0)
	dust.gravity = Vector3(0.0, -0.5, 0.0)
	dust.damping_min = 1.5
	dust.damping_max = 2.5
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.2
	dust.color_ramp = _fade_ramp
	dust.scale_amount_curve = _grow_curve
	return dust


# One-shot particles that free themselves. Emits along local +Y, which _launch aims at the normal.
func _burst(mesh: Mesh, amount: int, lifetime: float, speed_min: float, speed_max: float,
		spread_degrees: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.mesh = mesh
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = spread_degrees
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.finished.connect(particles.queue_free)
	return particles


func _launch(particles: CPUParticles3D, point: Vector3, normal: Vector3) -> void:
	_effects_parent().add_child(particles)
	particles.global_transform = Transform3D(_basis_facing(normal), point + normal * 0.02)
	particles.emitting = true


func _spawn_bullet_hole(point: Vector3, normal: Vector3) -> void:
	if normal.is_zero_approx():
		return
	var holes := _bullet_holes()
	while holes.get_child_count() >= MAX_BULLET_HOLES:
		var oldest := holes.get_child(0)
		holes.remove_child(oldest)
		oldest.queue_free()
	var decal := Decal.new()
	decal.texture_albedo = BULLET_HOLE_TEXTURE
	var size := randf_range(0.05, 0.075)
	decal.size = Vector3(size, 0.08, size)
	decal.normal_fade = 0.4
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 25.0
	decal.distance_fade_length = 10.0
	holes.add_child(decal)
	var basis := Basis(normal.normalized(), randf() * TAU) * _basis_facing(normal)
	decal.global_transform = Transform3D(basis, point)


# World-space container, so holes stay put even if the body that was hit moves.
func _bullet_holes() -> Node3D:
	var parent := _effects_parent()
	var holes := parent.get_node_or_null(NodePath(BULLET_HOLES_NODE)) as Node3D
	if holes == null:
		holes = Node3D.new()
		holes.name = BULLET_HOLES_NODE
		parent.add_child(holes)
	return holes


func _effects_parent() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root


func _update_reload_pose() -> void:
	if model == null:
		return
	var progress := get_reload_progress()
	var weight := 0.0
	if is_reloading():
		weight = smoothstep(0.0, 0.15, progress) - smoothstep(0.85, 1.0, progress)
	# Cant the rifle and drop it a little, as if turning the magwell towards you.
	model.rotation.z = deg_to_rad(25.0) * weight
	model.position.y = -0.04 * weight
	if magazine == null:
		return
	var drop := 0.0
	var shown := true
	if is_reloading() and _reload_cues.size() >= 2:
		var out_at: float = _reload_cues[0][0]
		var in_at: float = _reload_cues[1][0]
		if progress >= in_at:
			drop = 0.0
		elif progress >= in_at - 0.12:
			drop = 0.15 * (in_at - progress) / 0.12
		elif progress >= out_at + 0.1:
			shown = false
		elif progress >= out_at:
			drop = 0.15 * pow((progress - out_at) / 0.1, 2.0)
	magazine.position = _magazine_rest + Vector3(0.0, -drop, 0.0)
	magazine.visible = shown


static func _basis_facing(normal: Vector3) -> Basis:
	var y := normal.normalized()
	if y.is_zero_approx():
		return Basis.IDENTITY
	var helper := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := helper.cross(y).normalized()
	return Basis(x, y, x.cross(y))


func _make_flash() -> Node3D:
	var flash := Node3D.new()
	flash.visible = false
	# One quad facing back down the barrel, plus two crossed along it for the side view.
	var parts := [
		[Vector3(0.0, 0.0, -0.01), Vector3.ZERO, Vector3(0.12, 0.12, 1.0)],
		[Vector3(0.0, 0.0, -0.1), Vector3(0.0, PI / 2.0, 0.0), Vector3(0.2, 0.07, 1.0)],
		[Vector3(0.0, 0.0, -0.1), Vector3(PI / 2.0, PI / 2.0, 0.0), Vector3(0.2, 0.07, 1.0)],
	]
	for part: Array in parts:
		var quad := MeshInstance3D.new()
		quad.mesh = _flash_mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.position = part[0]
		quad.rotation = part[1]
		quad.scale = part[2]
		flash.add_child(quad)
	return flash


static func _build_shared_effects() -> void:
	_tracer_mesh = _make_tracer_mesh()
	_tracer_mesh.surface_set_material(0, _glow_material(Color(2.0, 1.35, 0.7), null, true))
	_flash_mesh = QuadMesh.new()
	_flash_mesh.material = _glow_material(Color(2.2, 1.6, 1.0), GLOW_TEXTURE, false)

	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.005, 0.04, 0.005)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(3.0, 1.7, 0.6)
	_spark_mesh.material = spark_material

	_chip_mesh = BoxMesh.new()
	_chip_mesh.size = Vector3(0.012, 0.009, 0.014)
	_chip_mesh.material = _solid_material(Color(0.42, 0.41, 0.39), 1.0)
	_droplet_mesh = BoxMesh.new()
	_droplet_mesh.size = Vector3(0.01, 0.01, 0.01)
	_droplet_mesh.material = _solid_material(Color(0.16, 0.02, 0.02), 0.35)

	_dust_mesh = _puff_mesh(Color(0.66, 0.63, 0.58), 0.25)
	_mist_mesh = _puff_mesh(Color(0.2, 0.02, 0.02), 0.2)

	_fade_ramp = Gradient.new()
	_fade_ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.7))
	_fade_ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_grow_curve = Curve.new()
	_grow_curve.add_point(Vector2(0.0, 0.4))
	_grow_curve.add_point(Vector2(1.0, 1.0))
	_shrink_curve = Curve.new()
	_shrink_curve.add_point(Vector2(0.0, 1.0))
	_shrink_curve.add_point(Vector2(1.0, 0.0))


# Two crossed ribbons from z = 0 (muzzle) to z = -1 (hit), faded out near the muzzle so the
# tracer doesn't flare right in front of the shooter's face.
static func _make_tracer_mesh() -> ArrayMesh:
	var stops := [[0.0, 0.0], [0.15, 1.0], [1.0, 1.0]]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for half: Vector3 in [Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.5, 0.0)]:
		for i in stops.size() - 1:
			var near := Vector3(0.0, 0.0, -stops[i][0])
			var far := Vector3(0.0, 0.0, -stops[i + 1][0])
			var near_color := Color(1.0, 1.0, 1.0, stops[i][1])
			var far_color := Color(1.0, 1.0, 1.0, stops[i + 1][1])
			vertices.append_array([near - half, near + half, far + half, near - half, far + half, far - half])
			colors.append_array([near_color, near_color, far_color, near_color, far_color, far_color])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Unshaded, additive, double-sided: for light-emitting effects. Colours above 1 feed the glow.
static func _glow_material(color: Color, texture: Texture2D, use_vertex_color: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = use_vertex_color
	return material


static func _solid_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


# Camera-facing soft puff whose colour/alpha follow the particle colour ramp.
static func _puff_mesh(color: Color, size: float) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.albedo_texture = PUFF_TEXTURE
	material.roughness = 1.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	mesh.material = material
	return mesh
