class_name GameMap
extends Node3D
## Root script for every playable map. A map scene must contain:
##   - PlayerSpawn         (Marker3D) where the player appears, facing its -Z.
##   - EnemySpawns         (Node3D) whose Marker3D children are enemy spawn points.
##   - NavigationRegion3D  wrapping all walkable/blocking geometry so enemies can path.
##
## Navmesh sources: CSG shapes under NavigationRegion3D (root shapes with use_collision), plus
## any node in this map in group "nav_source" that implements
##   func add_nav_geometry(source: NavigationMeshSourceGeometryData3D) -> void
## (procedural terrain, tree trunks, ...). Enemies chase in a straight line until it's ready.

## Emitted once the navmesh bake on load has finished (and the region uses it).
signal navmesh_baked

const NAV_SOURCE_GROUP := &"nav_source"

## Re-bake navigation from the CSG greybox on load, so geometry can be moved freely.
## Turn off once real level art replaces the CSG and the navmesh is baked in the editor.
@export var bake_navmesh_on_ready: bool = true
## Bake on a worker thread instead of blocking the load. Worth it for large outdoor maps.
@export var bake_async: bool = false
## Navigation map edge-merge precision while this map is loaded (0 = project default).
## Terrain navmeshes have tiny detail triangles on steep slopes; 0.001 stops them from being
## merged into the wrong edges ("Attempted to merge a navigation mesh polygon edge" errors).
@export var nav_merge_cell_scale: float = 0.0

## Milliseconds the last load-time bake took (source collection + bake); -1 until done.
var bake_time_msec: int = -1

var _bake_started_msec: int = 0

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var enemy_spawns: Node3D = $EnemySpawns
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	var merge_scale := nav_merge_cell_scale if nav_merge_cell_scale > 0.0 \
		else float(ProjectSettings.get_setting("navigation/3d/merge_rasterizer_cell_scale", 1.0))
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(get_world_3d().navigation_map, merge_scale)
	if bake_navmesh_on_ready:
		# CSG builds its geometry in a deferred call; deferring ours runs it right after.
		bake_navmesh_from_csg.call_deferred()


## Reads CSG collision geometry directly (the built-in bake reads CSG back from the GPU, which
## is slow and logs a warning), adds every "nav_source" node's geometry, then bakes.
func bake_navmesh_from_csg() -> void:
	_bake_started_msec = Time.get_ticks_msec()
	var source := NavigationMeshSourceGeometryData3D.new()
	for csg: CSGShape3D in nav_region.find_children("*", "CSGShape3D"):
		if csg.is_root_shape() and csg.use_collision:
			source.add_faces(csg.bake_collision_shape().get_faces(), csg.global_transform)
	for node in get_tree().get_nodes_in_group(NAV_SOURCE_GROUP):
		if is_ancestor_of(node) and node.has_method(&"add_nav_geometry"):
			node.add_nav_geometry(source)
	if bake_async:
		# Own copy: a restart re-instances the scene while the old bake may still be running
		# on the shared sub-resource.
		nav_region.navigation_mesh = nav_region.navigation_mesh.duplicate()
		NavigationServer3D.bake_from_source_geometry_data_async(
			nav_region.navigation_mesh, source, _on_navmesh_baked)
	else:
		NavigationServer3D.bake_from_source_geometry_data(nav_region.navigation_mesh, source)
		bake_time_msec = Time.get_ticks_msec() - _bake_started_msec
		navmesh_baked.emit()


func get_enemy_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for child in enemy_spawns.get_children():
		if child is Marker3D:
			points.append(child)
	return points


func _on_navmesh_baked() -> void:
	if not is_inside_tree():
		return
	# The region already read the (empty) mesh at the first map sync; hand it the baked one.
	bake_time_msec = Time.get_ticks_msec() - _bake_started_msec
	NavigationServer3D.region_set_navigation_mesh(nav_region.get_rid(), nav_region.navigation_mesh)
	navmesh_baked.emit()
