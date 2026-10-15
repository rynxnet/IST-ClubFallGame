class_name ForestVegetation
extends Node3D
## Scatters the forest over a HeightmapTerrain: conifer and broadleaf trees, wind-swaying grass,
## bushes, boulders, pebbles and fallen logs, plus a collision-free treeline on the far hills.
##
## Deterministic (fixed seed) so cover never moves between runs. Performance budget for laptops:
## everything is MultiMesh, grouped into chunks that each use visibility_range_end; grass shrinks
## out in its shader before its chunk is culled, so nothing pops. Wind runs in the shaders, so
## there is no per-frame CPU work. Collision is trunks/boulders/logs only, as shape owners on one
## StaticBody3D (layer 1). Keep this node at the map origin (positions are in terrain space).
## In group "nav_source": add_nav_geometry() adds trunks, boulders and logs as navmesh obstacles.

@export var terrain_path: NodePath = ^"../Terrain"
@export var vegetation_seed: int = 9157
@export_group("Materials")
@export var bark_material: Material
@export var conifer_material: Material
@export var broadleaf_material: Material
@export var bush_material: Material
@export var grass_material: Material
@export var rock_material: Material
@export_group("Layout")
## No vegetation at all inside these circles: (x, z, radius). Structures, pads, etc.
@export var exclusions: Array[Vector3] = []
## No trees or bushes near these segments (ax, az, bx, bz), e.g. the ridge -> outpost view.
@export var sightlines: Array[Vector4] = []
@export var sightline_width: float = 6.0
@export_group("Trees")
@export var max_trees: int = 560
@export var tree_min_spacing: float = 3.2
@export_range(0.0, 1.0) var conifer_ratio: float = 0.6
@export var tree_path_clearance: float = 3.5
@export var tree_chunk_size: float = 40.0
@export var tree_view_distance: float = 190.0
@export var far_tree_count: int = 450
@export_group("Grass")
@export var grass_per_chunk: int = 320
@export var grass_chunk_size: float = 20.0
## Grass shrinks away between 75% and 100% of this distance, then its chunk is culled.
@export var grass_view_distance: float = 42.0
@export_group("Ground cover")
@export var bush_count: int = 240
@export var boulder_count: int = 40
@export var pebble_count: int = 160
@export var log_count: int = 14

var _terrain: HeightmapTerrain
var _rng := RandomNumberGenerator.new()
var _density := FastNoiseLite.new()
## Vector2i cell -> Array of tree positions, for spacing checks.
var _occupied: Dictionary = {}
## Navmesh obstacles as [faces: PackedVector3Array, Transform3D] pairs (local to this node).
var _nav_obstacles: Array = []
var _colliders: StaticBody3D
var _cylinder_faces := PackedVector3Array()
var _counts: Dictionary = {}


func _ready() -> void:
	add_to_group(&"nav_source")
	_terrain = get_node(terrain_path) as HeightmapTerrain
	_rng.seed = vegetation_seed
	_density.seed = vegetation_seed + 1
	_density.frequency = 0.028
	var unit_cylinder := CylinderMesh.new()
	unit_cylinder.top_radius = 1.0
	unit_cylinder.bottom_radius = 1.0
	unit_cylinder.height = 1.0
	unit_cylinder.radial_segments = 8
	unit_cylinder.rings = 0
	_cylinder_faces = VegetationMeshes.faces_of(unit_cylinder)
	_colliders = StaticBody3D.new()
	_colliders.name = "Colliders"
	_colliders.collision_layer = 1
	_colliders.collision_mask = 0
	add_child(_colliders)
	_place_trees()
	_place_logs()
	_place_rocks()
	_place_bushes()
	_place_grass()
	_place_far_trees()


## Navmesh source contract (see GameMap).
func add_nav_geometry(source: NavigationMeshSourceGeometryData3D) -> void:
	for obstacle: Array in _nav_obstacles:
		source.add_faces(obstacle[0], global_transform * (obstacle[1] as Transform3D))


## Instance counts per category, for debugging and tests.
func get_counts() -> Dictionary:
	return _counts


func _place_trees() -> void:
	var meshes: Array[Mesh] = [
		VegetationMeshes.conifer(11, 11.0, 2.7, 5, bark_material, conifer_material),
		VegetationMeshes.conifer(23, 8.5, 2.3, 4, bark_material, conifer_material),
		VegetationMeshes.broadleaf(37, 9.0, 3.8, bark_material, broadleaf_material),
		VegetationMeshes.broadleaf(41, 7.0, 3.2, bark_material, broadleaf_material),
	]
	var trunk_radius: Array[float] = [0.24, 0.24, 0.22, 0.22]
	var buckets: Dictionary = {}
	var half := _terrain.get_half_size() - 1.5
	var placed := 0
	for attempt in max_trees * 8:
		if placed >= max_trees:
			break
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		var chance := clampf(0.5 + _density.get_noise_2dv(p) * 1.2, 0.1, 1.0)
		if maxf(absf(p.x), absf(p.y)) > 64.0:
			chance = 1.0
		if _rng.randf() > chance or not _tree_spot_ok(p):
			continue
		_occupy(p)
		var ground := _terrain.get_height(p.x, p.y)
		var conifer := _rng.randf() < conifer_ratio + ground * 0.02
		var variant := (0 if _rng.randf() < 0.55 else 1) + (0 if conifer else 2)
		var s := _rng.randf_range(0.75, 1.3)
		var rot_scale := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.15), s))
		var xf := Transform3D(rot_scale, Vector3(p.x, ground - 0.1, p.y))
		_bucket(buckets, p, tree_chunk_size, variant, xf)
		_add_trunk(xf.origin, trunk_radius[variant] * s)
		placed += 1
	_counts["trees"] = placed
	_emit(&"Trees", buckets, meshes, tree_view_distance, true)


func _tree_spot_ok(p: Vector2) -> bool:
	if not _is_open(p, 2.5) or _terrain.get_path_distance(p.x, p.y) < tree_path_clearance:
		return false
	if _terrain.get_flat_weight(p.x, p.y) > 0.2 or _sightline_distance(p) < sightline_width:
		return false
	if _terrain.get_normal(p.x, p.y).y < 0.8:
		return false
	return _spacing_ok(p, tree_min_spacing)


func _add_trunk(base: Vector3, radius: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 5.0
	_add_collider(shape, Transform3D(Basis(), base + Vector3(0, 2.0, 0)))
	_nav_obstacles.append([_cylinder_faces,
		Transform3D(Basis.from_scale(Vector3(radius, 4.5, radius)), base + Vector3(0, 1.75, 0))])


func _add_collider(shape: Shape3D, xf: Transform3D) -> void:
	var owner_id := _colliders.create_shape_owner(_colliders)
	_colliders.shape_owner_add_shape(owner_id, shape)
	_colliders.shape_owner_set_transform(owner_id, xf)


func _place_logs() -> void:
	var buckets: Dictionary = {}
	var half := _terrain.get_half_size() - 6.0
	var placed := 0
	for attempt in log_count * 30:
		if placed >= log_count:
			break
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		var length := _rng.randf_range(3.5, 6.5)
		var radius := _rng.randf_range(0.22, 0.36)
		var yaw := _rng.randf() * TAU
		var dir := Vector2(cos(yaw), -sin(yaw))
		var a := p + dir * length * 0.5
		var b := p - dir * length * 0.5
		var ok := true
		for q: Vector2 in [a, p, b]:
			if not _is_open(q, 2.0) or _terrain.get_path_distance(q.x, q.y) < 3.0 \
					or _terrain.get_flat_weight(q.x, q.y) > 0.2 or not _spacing_ok(q, 1.6) \
					or _terrain.get_normal(q.x, q.y).y < 0.85:
				ok = false
				break
		if not ok:
			continue
		var ha := _terrain.get_height(a.x, a.y)
		var hb := _terrain.get_height(b.x, b.y)
		var orient := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(ha - hb, length))
		var center := Vector3(p.x, (ha + hb) * 0.5 + radius * 0.6, p.y)
		_bucket(buckets, p, 1000.0, 0, Transform3D(orient * Basis.from_scale(Vector3(length, radius, radius)), center))
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = length
		var upright := orient * Basis(Vector3.BACK, -PI * 0.5)
		_add_collider(shape, Transform3D(upright, center))
		_nav_obstacles.append([_cylinder_faces,
			Transform3D(upright * Basis.from_scale(Vector3(radius, length, radius)), center)])
		placed += 1
	_counts["logs"] = placed
	_emit(&"Logs", buckets, [VegetationMeshes.log_mesh(bark_material)], tree_view_distance, true)


func _place_rocks() -> void:
	var variants: Array = []
	var meshes: Array[Mesh] = []
	for k in 3:
		var built: Array = VegetationMeshes.rock(70 + k, rock_material)
		variants.append(built)
		meshes.append(built[0])
	var boulders: Dictionary = {}
	var pebbles: Dictionary = {}
	var half := _terrain.get_half_size() - 3.0
	var placed := 0
	for attempt in boulder_count * 30:
		if placed >= boulder_count:
			break
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		var n := _terrain.get_normal(p.x, p.y)
		# Boulders favour slopes (the ridge flanks and the rim).
		if n.y > 0.97 and _rng.randf() < 0.75:
			continue
		if not _is_open(p, 2.0) or _terrain.get_path_distance(p.x, p.y) < 3.0 \
				or _terrain.get_flat_weight(p.x, p.y) > 0.3 or not _spacing_ok(p, 2.5):
			continue
		_occupy(p)
		var s := _rng.randf_range(1.0, 2.6)
		var variant := _rng.randi_range(0, 2)
		var rot := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
		var origin := Vector3(p.x, _terrain.get_height(p.x, p.y) - 0.12 * s, p.y)
		_bucket(boulders, p, tree_chunk_size, variant, Transform3D(rot.scaled(Vector3.ONE * s), origin))
		var points := PackedVector3Array()
		for v: Vector3 in variants[variant][1]:
			points.append(v * s)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		_add_collider(shape, Transform3D(rot, origin))
		_nav_obstacles.append([variants[variant][2], Transform3D(rot.scaled(Vector3.ONE * s), origin)])
		placed += 1
	_counts["boulders"] = placed
	_emit(&"Boulders", boulders, meshes, tree_view_distance, true)
	var small := 0
	for attempt in pebble_count * 4:
		if small >= pebble_count:
			break
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if not _is_open(p, 0.5) or _terrain.get_path_distance(p.x, p.y) < 1.0:
			continue
		var s := _rng.randf_range(0.15, 0.5)
		var rot := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		var origin := Vector3(p.x, _terrain.get_height(p.x, p.y) - 0.1 * s, p.y)
		_bucket(pebbles, p, tree_chunk_size, _rng.randi_range(0, 2), Transform3D(rot, origin))
		small += 1
	_counts["pebbles"] = small
	_emit(&"Pebbles", pebbles, meshes, 60.0, false)


func _place_bushes() -> void:
	var meshes: Array[Mesh] = [VegetationMeshes.bush(51, bush_material), VegetationMeshes.bush(52, bush_material)]
	var buckets: Dictionary = {}
	var half := _terrain.get_half_size() - 2.0
	var placed := 0
	for attempt in bush_count * 6:
		if placed >= bush_count:
			break
		var p := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if _rng.randf() > clampf(0.45 + _density.get_noise_2dv(p), 0.15, 1.0):
			continue
		if not _is_open(p, 1.5) or _terrain.get_path_distance(p.x, p.y) < 2.2 \
				or _terrain.get_flat_weight(p.x, p.y) > 0.6 or _sightline_distance(p) < sightline_width * 0.5 \
				or _terrain.get_normal(p.x, p.y).y < 0.75:
			continue
		var s := _rng.randf_range(0.7, 1.6)
		var rot_scale := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.2), s))
		_bucket(buckets, p, tree_chunk_size, _rng.randi_range(0, 1),
			Transform3D(rot_scale, Vector3(p.x, _terrain.get_height(p.x, p.y) - 0.1, p.y)))
		placed += 1
	_counts["bushes"] = placed
	_emit(&"Bushes", buckets, meshes, 110.0, false)


func _place_grass() -> void:
	if grass_material is ShaderMaterial:
		var mat := grass_material as ShaderMaterial
		mat.set_shader_parameter(&"fade_start", grass_view_distance * 0.75)
		mat.set_shader_parameter(&"fade_end", grass_view_distance)
	var meshes: Array[Mesh] = [VegetationMeshes.grass_clump(5, 7, grass_material)]
	var buckets: Dictionary = {}
	var half := _terrain.get_half_size() - 1.0
	var chunks := ceili(half * 2.0 / grass_chunk_size)
	var placed := 0
	for cz in chunks:
		for cx in chunks:
			var corner := Vector2(-half + cx * grass_chunk_size, -half + cz * grass_chunk_size)
			var count := 0
			for attempt in grass_per_chunk * 2:
				if count >= grass_per_chunk:
					break
				var p := corner + Vector2(_rng.randf(), _rng.randf()) * grass_chunk_size
				if absf(p.x) > half or absf(p.y) > half:
					continue
				# Meadow patches are lush, forest floor is sparser.
				if _rng.randf() > clampf(0.65 - _density.get_noise_2dv(p) * 0.8, 0.25, 1.0):
					continue
				if not _is_open(p, 0.0) or _terrain.get_path_distance(p.x, p.y) < 1.1 + _rng.randf() * 1.2 \
						or _terrain.get_normal(p.x, p.y).y < 0.84:
					continue
				var s := _rng.randf_range(0.7, 1.25)
				var rot_scale := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.3), s))
				_bucket(buckets, p, grass_chunk_size, 0,
					Transform3D(rot_scale, Vector3(p.x, _terrain.get_height(p.x, p.y) - 0.04, p.y)))
				count += 1
			placed += count
	_counts["grass"] = placed
	_emit(&"Grass", buckets, meshes, grass_view_distance + grass_chunk_size * 0.75, false)


## A treeline on the far hills so the horizon reads as forest. No collision, no shadows.
func _place_far_trees() -> void:
	var meshes: Array[Mesh] = [
		VegetationMeshes.conifer(11, 11.0, 2.7, 5, bark_material, conifer_material),
		VegetationMeshes.conifer(23, 8.5, 2.3, 4, bark_material, conifer_material),
	]
	var buckets: Dictionary = {}
	var inner := _terrain.get_half_size() + 3.0
	var outer := inner + 55.0
	var placed := 0
	for attempt in far_tree_count * 4:
		if placed >= far_tree_count:
			break
		var p := Vector2(_rng.randf_range(-outer, outer), _rng.randf_range(-outer, outer))
		if absf(p.x) < inner and absf(p.y) < inner:
			continue
		var s := _rng.randf_range(0.9, 1.6)
		var rot_scale := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		var origin := Vector3(p.x, _terrain.natural_height(p.x, p.y) - 0.8, p.y)
		_bucket(buckets, p, 80.0, _rng.randi_range(0, 1), Transform3D(rot_scale, origin))
		placed += 1
	_counts["far_trees"] = placed
	_emit(&"FarTrees", buckets, meshes, 0.0, false)


func _bucket(buckets: Dictionary, p: Vector2, chunk: float, variant: int, xf: Transform3D) -> void:
	var key := Vector3i(floori(p.x / chunk), floori(p.y / chunk), variant)
	if not buckets.has(key):
		buckets[key] = []
	(buckets[key] as Array).append(xf)


func _emit(group_name: StringName, buckets: Dictionary, meshes: Array, view_distance: float,
		shadows: bool) -> void:
	var holder := Node3D.new()
	holder.name = group_name
	add_child(holder)
	for key: Vector3i in buckets:
		var xforms: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.z]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = view_distance
		holder.add_child(mmi)


func _is_open(p: Vector2, margin: float) -> bool:
	for e in exclusions:
		if p.distance_to(Vector2(e.x, e.y)) < e.z + margin:
			return false
	return true


func _sightline_distance(p: Vector2) -> float:
	var best := INF
	for line in sightlines:
		var a := Vector2(line.x, line.y)
		var ab := Vector2(line.z, line.w) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _spacing_ok(p: Vector2, min_distance: float) -> bool:
	var cell := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2 in _occupied.get(cell + Vector2i(dx, dz), []):
				if p.distance_to(q) < min_distance:
					return false
	return true


func _occupy(p: Vector2) -> void:
	var cell := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	if not _occupied.has(cell):
		_occupied[cell] = []
	(_occupied[cell] as Array).append(p)
