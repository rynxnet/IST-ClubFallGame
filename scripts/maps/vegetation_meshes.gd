class_name VegetationMeshes
extends RefCounted
## Procedural low-poly meshes for the forest (no image files): conifers, broadleaf trees,
## bushes, rocks, grass clumps and fallen logs. Built once at load from fixed seeds.
##
## Vertex colours carry baked shading (darker inside/underneath), which foliage.gdshader and
## grass.gdshader multiply into the albedo. Meshes are centred on the ground point at the origin.


## Accumulates primitive arrays into one surface, optionally transformed / flat-shaded.
class Parts:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func add(arrays: Array, xform: Transform3D, flat: bool = false) -> void:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null \
			else PackedColorArray()
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null \
			else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var basis := xform.basis
		if flat:
			for k in range(0, idx.size(), 3):
				var p0 := xform * v[idx[k]]
				var p1 := xform * v[idx[k + 1]]
				var p2 := xform * v[idx[k + 2]]
				# Godot front faces are clockwise, so this cross product points outward.
				var fn := (p2 - p0).cross(p1 - p0).normalized()
				for m in 3:
					var src := idx[k + m]
					indices.append(verts.size())
					verts.append([p0, p1, p2][m])
					normals.append(fn)
					colors.append(c[src] if c.size() > src else Color.WHITE)
					uvs.append(uv[src] if uv.size() > src else Vector2.ZERO)
			return
		var base := verts.size()
		for k in v.size():
			verts.append(xform * v[k])
			normals.append((basis * n[k]).normalized())
			colors.append(c[k] if c.size() > k else Color.WHITE)
			uvs.append(uv[k] if uv.size() > k else Vector2.ZERO)
		for k in idx:
			indices.append(base + k)

	func merge(other: Parts, xform: Transform3D) -> void:
		var base := verts.size()
		for k in other.verts.size():
			verts.append(xform * other.verts[k])
			normals.append((xform.basis * other.normals[k]).normalized())
		colors.append_array(other.colors)
		uvs.append_array(other.uvs)
		for k in other.indices:
			indices.append(base + k)

	func commit(mesh: ArrayMesh, material: Material) -> void:
		if verts.is_empty():
			return
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


static func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	return noise


static func _trunk(bottom: float, top: float, height: float, sink: float = 0.4) -> Parts:
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = bottom
	cyl.top_radius = top
	cyl.height = height + sink
	cyl.radial_segments = 7
	cyl.rings = 0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var parts := Parts.new()
	var arrays := cyl.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for v in verts:
		colors.append(Color.WHITE * lerpf(0.75, 1.0, (v.y + cyl.height * 0.5) / cyl.height))
	arrays[Mesh.ARRAY_COLOR] = colors
	parts.add(arrays, Transform3D(Basis(), Vector3(0, (height - sink) * 0.5, 0)))
	return parts


## Stacked jagged cones. Roughly `height` tall and `radius` wide at the lowest tier.
static func conifer(seed_value: int, height: float, radius: float, tiers: int,
		bark: Material, leaves: Material) -> ArrayMesh:
	var noise := _noise(seed_value, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trunk := _trunk(0.26, 0.08, height * 0.7)
	var foliage := Parts.new()
	var bare := height * 0.16
	for t in tiers:
		var f := float(t) / float(tiers)
		var y0 := bare + (height - bare) * f * 0.8
		var r := radius * lerpf(1.0, 0.25, f) * rng.randf_range(0.9, 1.1)
		var tier_h := (height - y0) if t == tiers - 1 else (height - bare) * 0.42 * lerpf(1.0, 0.7, f)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r
		cone.height = tier_h
		cone.radial_segments = 10
		cone.rings = 0
		cone.cap_top = false
		var arrays := cone.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors := PackedColorArray()
		colors.resize(verts.size())
		var shade := lerpf(0.62, 1.0, f)
		for k in verts.size():
			var v := verts[k]
			var radial := Vector2(v.x, v.z)
			var is_cap := normals[k].y < -0.9
			if radial.length() > 0.001:
				var dir := radial.normalized()
				var j := noise.get_noise_3d(dir.x * 2.0, dir.y * 2.0, t * 5.0)
				var k_r := 1.0 + j * 0.45
				v.x *= k_r
				v.z *= k_r
				v.y -= maxf(k_r - 0.8, 0.0) * 0.35 * r
				normals[k] = Vector3(dir.x, 0.8, dir.y).normalized() if not is_cap else Vector3.DOWN
				colors[k] = Color.WHITE * (0.36 if is_cap else shade * (0.8 + 0.25 * (j + 0.5)))
			elif is_cap:
				# Pull the underside centre up into the cone so it reads as a hollow skirt.
				v.y += tier_h * 0.35
				colors[k] = Color.WHITE * 0.3
			else:
				normals[k] = Vector3.UP
				colors[k] = Color.WHITE * (shade + 0.15)
			verts[k] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		foliage.add(arrays, Transform3D(yaw, Vector3(0, y0 + tier_h * 0.5, 0)))
	var mesh := ArrayMesh.new()
	trunk.commit(mesh, bark)
	foliage.commit(mesh, leaves)
	return mesh


## Lumpy blob cluster, used for broadleaf canopies and bushes.
static func _blobs(parts: Parts, rng: RandomNumberGenerator, noise: FastNoiseLite,
		center: Vector3, spread: Vector3, count: int, blob_radius: float, squash: float) -> void:
	var total := spread.y + blob_radius
	for b in count:
		var offset := Vector3(rng.randf_range(-1, 1) * spread.x, rng.randf_range(-1, 1) * spread.y,
			rng.randf_range(-1, 1) * spread.z)
		if b == 0:
			offset = Vector3.ZERO
		var br := blob_radius * rng.randf_range(0.75, 1.1)
		var sphere := SphereMesh.new()
		sphere.radius = br
		sphere.height = br * 2.0 * squash
		sphere.radial_segments = 8
		sphere.rings = 5
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors := PackedColorArray()
		colors.resize(verts.size())
		var c := center + offset
		for k in verts.size():
			var p := verts[k] + c
			var bump := noise.get_noise_3dv(p * 1.6)
			p += normals[k] * bump * br * 0.35
			verts[k] = p - c
			var out := (p - center)
			normals[k] = (out.normalized() + normals[k]).normalized()
			var height_shade := clampf((p.y - (center.y - total)) / (2.0 * total), 0.0, 1.0)
			colors[k] = Color.WHITE * lerpf(0.42, 1.08, height_shade) * (0.92 + bump * 0.2)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		parts.add(arrays, Transform3D(Basis(), c))


static func broadleaf(seed_value: int, height: float, radius: float,
		bark: Material, leaves: Material) -> ArrayMesh:
	var noise := _noise(seed_value, 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trunk := _trunk(0.24, 0.1, height * 0.72)
	# Two short limbs leaning out into the canopy.
	for side in [-1.0, 1.0]:
		var limb := _trunk(0.09, 0.04, height * 0.3, 0.0)
		var tilt := Basis(Vector3.FORWARD, side * 0.7).rotated(Vector3.UP, rng.randf() * TAU)
		trunk.merge(limb, Transform3D(tilt, Vector3(0, height * 0.42, 0)))
	var canopy := Parts.new()
	var center := Vector3(0, height * 0.68, 0)
	_blobs(canopy, rng, noise, center, Vector3(radius * 0.5, height * 0.12, radius * 0.5), 6,
		radius * 0.55, 0.85)
	var mesh := ArrayMesh.new()
	trunk.commit(mesh, bark)
	canopy.commit(mesh, leaves)
	return mesh


static func bush(seed_value: int, leaves: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts := Parts.new()
	_blobs(parts, rng, _noise(seed_value, 1.4), Vector3(0, 0.35, 0), Vector3(0.45, 0.1, 0.45), 4,
		0.55, 0.75)
	var mesh := ArrayMesh.new()
	parts.commit(mesh, leaves)
	return mesh


## Faceted boulder about 1 m across, flattened underneath.
## Returns [mesh, collision points, triangle faces (for navmesh baking)].
static func rock(seed_value: int, material: Material) -> Array:
	var noise := _noise(seed_value, 0.8)
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for k in verts.size():
		var v := verts[k]
		v *= 1.0 + noise.get_noise_3dv(v * 2.0) * 0.45
		v.y *= 0.7
		if v.y < -0.1:
			v.y = -0.1 + (v.y + 0.1) * 0.35
		verts[k] = v
		colors[k] = Color.WHITE * lerpf(0.7, 1.05, clampf(v.y + 0.5, 0.0, 1.0))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var parts := Parts.new()
	parts.add(arrays, Transform3D(), true)
	var mesh := ArrayMesh.new()
	parts.commit(mesh, material)
	return [mesh, verts, parts.verts]


## A clump of tapered blades; UV.y runs 0 (root) -> 1 (tip) for the wind shader.
static func grass_clump(seed_value: int, blades: int, material: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for b in blades:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.2)
		var h := rng.randf_range(0.32, 0.7)
		var w := rng.randf_range(0.035, 0.06)
		var facing := rng.randf() * TAU
		var side := Vector3(cos(facing), 0, sin(facing)) * w
		var lean := (root.normalized() if root.length() > 0.01 else Vector3.RIGHT) \
			* rng.randf_range(0.08, 0.28) * h
		var tone := rng.randf_range(0.8, 1.1)
		var base := verts.size()
		var mid := root + lean * 0.3 + Vector3(0, h * 0.5, 0)
		verts.append_array([root - side, root + side, mid - side * 0.7, mid + side * 0.7,
			root + lean + Vector3(0, h, 0)])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 1)])
		for m in 5:
			colors.append(Color(tone, tone, tone))
		indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3,
			base + 2, base + 4, base + 3])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## Triangle soup (3 vertices per face) of a primitive, built on the CPU. Feeding meshes to the
## navmesh baker directly would read them back from the GPU.
static func faces_of(primitive: PrimitiveMesh) -> PackedVector3Array:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var faces := PackedVector3Array()
	for k: int in arrays[Mesh.ARRAY_INDEX]:
		faces.append(verts[k])
	return faces


## Unit log lying along X (1 m long, 1 m radius); scale per instance.
static func log_mesh(bark: Material) -> ArrayMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 0
	var parts := Parts.new()
	parts.add(cyl.get_mesh_arrays(), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	var mesh := ArrayMesh.new()
	parts.commit(mesh, bark)
	return mesh
