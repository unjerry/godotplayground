class_name ShelfStorage
extends Node3D

# Inclusive placement limits in GridMap cell indices.
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

@onready var grid_map: GridMap = $GridMap


func _enter_tree() -> void:
	add_to_group("shelf_storage")


func raycast_cell(world_start: Vector3, world_end: Vector3) -> Dictionary:
	# Determine Y from the ray at the center of the shelf's depth.
	# Then intersect only that Y layer's BASE plane to obtain X and Z.
	# Never search for a lower layer if this layer misses.
	if grid_map.mesh_library == null or grid_map.cell_center_y:
		return {}

	var low := Vector3i(
		mini(min_cell.x, max_cell.x),
		mini(min_cell.y, max_cell.y),
		mini(min_cell.z, max_cell.z)
	)
	var high := Vector3i(
		maxi(min_cell.x, max_cell.x),
		maxi(min_cell.y, max_cell.y),
		maxi(min_cell.z, max_cell.z)
	)
	var from_local: Vector3 = grid_map.to_local(world_start)
	var to_local_point: Vector3 = grid_map.to_local(world_end)
	var delta: Vector3 = to_local_point - from_local
	var size: Vector3 = grid_map.cell_size

	if size.y <= 0.0 or absf(delta.z) < 0.00001:
		return {}

	# A vertical reference plane at shelf mid-depth tells us which
	# Y layer the crosshair is pointing into (not the closest board plane).
	var first_z: float = grid_map.map_to_local(Vector3i(0, 0, low.z)).z
	var last_z: float = grid_map.map_to_local(Vector3i(0, 0, high.z)).z
	var mid_depth: float = (first_z + last_z) * 0.5
	var t_depth: float = (mid_depth - from_local.z) / delta.z
	if t_depth < 0.0 or t_depth > 1.0:
		return {}

	# cell_center_y is false, so grid zero Y is the BOTTOM plane.
	var zero_y: float = grid_map.map_to_local(Vector3i.ZERO).y
	var y_at_depth: float = from_local.y + t_depth * delta.y
	var layer: int = floori((y_at_depth - zero_y) / size.y)
	if layer < low.y or layer > high.y:
		return {}

	# The same ray now intersects only this layer's actual bottle base.
	if absf(delta.y) < 0.00001:
		return {}
	var base_y: float = grid_map.map_to_local(Vector3i(0, layer, 0)).y
	var t_board: float = (base_y - from_local.y) / delta.y
	if t_board < 0.0 or t_board > 1.0:
		return {}

	var hit_local: Vector3 = from_local + delta * t_board
	var hit_cell: Vector3i = grid_map.local_to_map(hit_local)
	if hit_cell.x < low.x or hit_cell.x > high.x:
		return {}
	if hit_cell.z < low.z or hit_cell.z > high.z:
		return {}

	return {
		"shelf": self,
		"grid": grid_map,
		"cell": Vector3i(hit_cell.x, layer, hit_cell.z),
		"distance": world_start.distance_to(grid_map.to_global(hit_local))
	}
