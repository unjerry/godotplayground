class_name ShelfStorage
extends Node3D

# Grid coordinates are local to this shelf's GridMap, not world meters.
# All six bounds are inclusive and editable for each shelf in the Inspector.
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

@onready var grid_map: GridMap = $GridMap


func _enter_tree() -> void:
	add_to_group("shelf_storage")


func raycast_cell(world_start: Vector3, world_end: Vector3) -> Dictionary:
	# Test a real 3D ray segment against every permitted cell box.
	# This is independent of the shelf's (currently solid-box) collision
	# proxy, and never snaps a hit to a different Y layer or Z row.
	if grid_map.mesh_library == null:
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

	var count: int = (high.x - low.x + 1) * (high.y - low.y + 1) * (high.z - low.z + 1)
	if count > 4096:
		return {}

	var from_local: Vector3 = grid_map.to_local(world_start)
	var to_local_point: Vector3 = grid_map.to_local(world_end)
	var extent: Vector3 = grid_map.cell_size
	var offset := Vector3(
		-0.5 * extent.x if grid_map.cell_center_x else 0.0,
		-0.5 * extent.y if grid_map.cell_center_y else 0.0,
		-0.5 * extent.z if grid_map.cell_center_z else 0.0
	)

	var best_distance: float = INF
	var best_cell := Vector3i.ZERO
	var found := false

	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				var box := AABB(grid_map.map_to_local(cell) + offset, extent)
				var intersection: Variant = box.intersects_segment(from_local, to_local_point)
				if intersection == null:
					continue

				var world_hit: Vector3 = grid_map.to_global(intersection)
				var distance: float = world_start.distance_to(world_hit)
				if distance < best_distance - 0.0001:
					best_distance = distance
					best_cell = cell
					found = true

	if not found:
		return {}

	return {
		"shelf": self,
		"grid": grid_map,
		"cell": best_cell,
		"distance": best_distance
	}
