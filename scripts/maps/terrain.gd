class_name HeightmapTerrain
extends Node3D
## Procedural heightmap terrain: rolling hills from FastNoiseLite, a raised ridge, a bowl-shaped
## rim at the map edge, flattened zones under structures/clearings and worn dirt paths.
##
## Everything is generated in _ready() from a fixed seed, so the layout never shifts and markers
## placed in the scene stay on the ground. Builds:
##   - a render mesh (vertex colour R = path mask, G = clearing mask, for terrain.gdshader),
##   - HeightMapShape3D collision on layer 1,
##   - a coarse, collision-free "far terrain" skirt so the horizon is never empty.
## In group "nav_source": GameMap calls add_nav_geometry() to bake the navmesh from it.
## Other scripts (vegetation) query get_height(), get_normal(), get_path_distance(), get_flat_weight().

## Side length of the playable square in metres (centred on the node).
@export var size: float = 160.0
## Grid vertices per side. (size / (resolution - 1)) is the spacing; 161 gives 1 m cells.
@export var resolution: int = 161
@export var noise_seed: int = 7031
@export var hill_height: float = 10.0
@export var hill_frequency: float = 0.012
@export_group("Ridge")
## The ridge rises along the segment ridge_start -> ridge_end (x, z).
@export var ridge_start: Vector2 = Vector2(58, -22)
@export var ridge_end: Vector2 = Vector2(44, 34)
@export var ridge_height: float = 13.0
@export var ridge_width: float = 16.0
@export_group("Edge")
## Terrain rises toward the edge of the map, forming a natural bowl.
@export var edge_rise_start: float = 62.0
@export var edge_rise_height: float = 12.0
## Extra rise of the far (non-playable) hills, reached at far_extent.
@export var far_rise_height: float = 22.0
@export var far_extent: float = 320.0
@export var far_spacing: float = 8.0
@export_group("Zones")
## Flattened areas: (x, z, radius, target height). Full flat inside radius, blends over flat_falloff.
@export var flat_zones: Array[Vector4] = []
@export var flat_falloff: float = 10.0
## Dirt paths as polylines of (x, z) points.
@export var paths: Array[PackedVector2Array] = []
@export var path_width: float = 2.6
@export_group("Rendering")
@export var material: Material
@export var cast_shadows: bool = true

## Distances to paths are only tracked up to this many metres.
const PATH_DIST_MAX := 10.0

var _noise := FastNoiseLite.new()
var _spacing: float = 1.0
var _half: float = 80.0
var _heights := PackedFloat32Array()
var _path_dist := PackedFloat32Array()
var _mesh_arrays: Array = []


func _ready() -> void:
	add_to_group(&"nav_source")
	_setup_noise()
	_build()


func _setup_noise() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = hill_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.45
	_half = size * 0.5
	_spacing = size / float(resolution - 1)


## Raw terrain height before flattening (hills + ridge + edge rim).
func natural_height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * hill_height
	var d_ridge := _distance_to_segment(Vector2(x, z), ridge_start, ridge_end)
	h += ridge_height * exp(-pow(d_ridge / ridge_width, 2.0))
	# Superellipse distance: square-ish rim with rounded corners.
	var e := pow(pow(absf(x), 4.0) + pow(absf(z), 4.0), 0.25)
	h += edge_rise_height * smoothstep(edge_rise_start, _half, e)
	h += far_rise_height * smoothstep(_half, far_extent * 0.6, e)
	return h


## Height with flattened zones applied (what the mesh and collision use).
func shaped_height(x: float, z: float) -> float:
	var h := natural_height(x, z)
	for zone in flat_zones:
		var d := Vector2(x, z).distance_to(Vector2(zone.x, zone.y))
		var w := 1.0 - smoothstep(zone.z, zone.z + flat_falloff, d)
		if w > 0.0:
			h = lerpf(h, zone.w, w)
	return h


## Terrain surface height at world (x, z), matching the rendered triangles.
func get_height(x: float, z: float) -> float:
	var gx := clampf((x - global_position.x + _half) / _spacing, 0.0, resolution - 1.001)
	var gz := clampf((z - global_position.z + _half) / _spacing, 0.0, resolution - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var ha := _heights[j * resolution + i]
	var hb := _heights[j * resolution + i + 1]
	var hc := _heights[(j + 1) * resolution + i]
	var hd := _heights[(j + 1) * resolution + i + 1]
	var h: float
	if fx + fz <= 1.0:
		h = ha + (hb - ha) * fx + (hc - ha) * fz
	else:
		h = hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)
	return h + global_position.y


## Approximate surface normal at world (x, z).
func get_normal(x: float, z: float) -> Vector3:
	var e := _spacing
	var dx := get_height(x + e, z) - get_height(x - e, z)
	var dz := get_height(x, z + e) - get_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Distance (metres) from world (x, z) to the nearest path centre line, capped at PATH_DIST_MAX.
func get_path_distance(x: float, z: float) -> float:
	var i := clampi(roundi((x - global_position.x + _half) / _spacing), 0, resolution - 1)
	var j := clampi(roundi((z - global_position.z + _half) / _spacing), 0, resolution - 1)
	return _path_dist[j * resolution + i]


## 1 inside a flattened zone, fading to 0 at the end of its falloff.
func get_flat_weight(x: float, z: float) -> float:
	var w := 0.0
	for zone in flat_zones:
		var d := Vector2(x - global_position.x, z - global_position.z).distance_to(Vector2(zone.x, zone.y))
		w = maxf(w, 1.0 - smoothstep(zone.z, zone.z + flat_falloff, d))
	return w


## Half the side length of the playable square.
func get_half_size() -> float:
	return _half


## Navmesh source contract (see GameMap): contributes the playable terrain triangles.
func add_nav_geometry(source: NavigationMeshSourceGeometryData3D) -> void:
	if not _mesh_arrays.is_empty():
		source.add_mesh_array(_mesh_arrays, global_transform)


func _build() -> void:
	var n := resolution
	_heights.resize(n * n)
	_path_dist.resize(n * n)
	_path_dist.fill(PATH_DIST_MAX)
	for path in paths:
		for k in path.size() - 1:
			_rasterize_segment(path[k], path[k + 1])
	for j in n:
		var z := -_half + j * _spacing
		for i in n:
			_heights[j * n + i] = shaped_height(-_half + i * _spacing, z)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var path_half := path_width * 0.5
	for j in n:
		var z := -_half + j * _spacing
		for i in n:
			var idx := j * n + i
			var x := -_half + i * _spacing
			verts[idx] = Vector3(x, _heights[idx], z)
			var hl := _heights[j * n + maxi(i - 1, 0)]
			var hr := _heights[j * n + mini(i + 1, n - 1)]
			var hu := _heights[maxi(j - 1, 0) * n + i]
			var hd := _heights[mini(j + 1, n - 1) * n + i]
			normals[idx] = Vector3(hl - hr, 2.0 * _spacing, hu - hd).normalized()
			var path_mask := 1.0 - smoothstep(path_half, path_half + 1.4, _path_dist[idx])
			colors[idx] = Color(path_mask, get_flat_weight(x, z), 0.0, 1.0)
	var indices := _grid_indices(n, n)

	_mesh_arrays.resize(Mesh.ARRAY_MAX)
	_mesh_arrays[Mesh.ARRAY_VERTEX] = verts
	_mesh_arrays[Mesh.ARRAY_INDEX] = indices
	var render_arrays := _mesh_arrays.duplicate()
	render_arrays[Mesh.ARRAY_NORMAL] = normals
	render_arrays[Mesh.ARRAY_COLOR] = colors
	_add_mesh_instance("TerrainMesh", render_arrays, cast_shadows)

	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = _heights
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D samples are 1 unit apart; scale to the grid spacing.
	col.scale = Vector3(_spacing, 1.0, _spacing)
	body.add_child(col)
	add_child(body)

	_build_far_terrain()


## Collision-free low-res terrain around the playable square, sunk below it inside.
func _build_far_terrain() -> void:
	var m := int(far_extent * 2.0 / far_spacing) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(m * m)
	normals.resize(m * m)
	colors.resize(m * m)
	for j in m:
		var z := -far_extent + j * far_spacing
		for i in m:
			var x := -far_extent + i * far_spacing
			var h := natural_height(x, z)
			if absf(x) < _half - 0.1 and absf(z) < _half - 0.1:
				h = shaped_height(x, z) - 3.0
			var idx := j * m + i
			verts[idx] = Vector3(x, h, z)
			var e := far_spacing * 0.5
			var dx := natural_height(x + e, z) - natural_height(x - e, z)
			var dz := natural_height(x, z + e) - natural_height(x, z - e)
			normals[idx] = Vector3(-dx, 2.0 * e, -dz).normalized()
			colors[idx] = Color(0, 0, 0, 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _grid_indices(m, m)
	_add_mesh_instance("FarTerrainMesh", arrays, false)


func _add_mesh_instance(node_name: String, arrays: Array, shadows: bool) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Two clockwise (front-facing up) triangles per grid cell; matches HeightMapShape3D's split.
func _grid_indices(w: int, d: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize((w - 1) * (d - 1) * 6)
	var k := 0
	for j in d - 1:
		for i in w - 1:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var e := c + 1
			indices[k] = a
			indices[k + 1] = b
			indices[k + 2] = c
			indices[k + 3] = b
			indices[k + 4] = e
			indices[k + 5] = c
			k += 6
	return indices


## Writes min distance-to-segment into the grid cells near one path segment.
func _rasterize_segment(a: Vector2, b: Vector2) -> void:
	var n := resolution
	var r := PATH_DIST_MAX
	var i0 := clampi(int((minf(a.x, b.x) - r + _half) / _spacing), 0, n - 1)
	var i1 := clampi(int((maxf(a.x, b.x) + r + _half) / _spacing) + 1, 0, n - 1)
	var j0 := clampi(int((minf(a.y, b.y) - r + _half) / _spacing), 0, n - 1)
	var j1 := clampi(int((maxf(a.y, b.y) + r + _half) / _spacing) + 1, 0, n - 1)
	for j in range(j0, j1 + 1):
		var z := -_half + j * _spacing
		for i in range(i0, i1 + 1):
			var p := Vector2(-_half + i * _spacing, z)
			# Gentle wobble so paths don't look ruler-straight.
			var d := _distance_to_segment(p, a, b) + _noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.6
			var idx := j * n + i
			if d < _path_dist[idx]:
				_path_dist[idx] = maxf(d, 0.0)


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
