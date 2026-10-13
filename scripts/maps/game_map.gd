class_name GameMap
extends Node3D
## Root script for every playable map. A map scene must contain:
##   - PlayerSpawn         (Marker3D) where the player appears, facing its -Z.
##   - EnemySpawns         (Node3D) whose Marker3D children are enemy spawn points.
##   - NavigationRegion3D  wrapping all walkable/blocking geometry so enemies can path.

## Re-bake navigation from the CSG greybox on load, so geometry can be moved freely.
## Turn off once real level art replaces the CSG and the navmesh is baked in the editor.
@export var bake_navmesh_on_ready: bool = true

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var enemy_spawns: Node3D = $EnemySpawns
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	if bake_navmesh_on_ready:
		# CSG builds its geometry in a deferred call; deferring ours runs it right after.
		bake_navmesh_from_csg.call_deferred()


## Reads CSG collision geometry directly. The built-in bake reads CSG back from the GPU,
## which is slow and logs a warning.
func bake_navmesh_from_csg() -> void:
	var source := NavigationMeshSourceGeometryData3D.new()
	for csg: CSGShape3D in nav_region.find_children("*", "CSGShape3D"):
		if csg.is_root_shape() and csg.use_collision:
			source.add_faces(csg.bake_collision_shape().get_faces(), csg.global_transform)
	NavigationServer3D.bake_from_source_geometry_data(nav_region.navigation_mesh, source)


func get_enemy_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for child in enemy_spawns.get_children():
		if child is Marker3D:
			points.append(child)
	return points
