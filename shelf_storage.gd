class_name ShelfStorage
extends Node3D

# Bounds are inclusive, in local GridMap cell coordinates (not meters).
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

# Virtual shelf-board height relative to each GridMap layer's base, in meters.
# By default the plane is 0.2m above the board (roughly bottle mid-height),
# so looking at the bottle itself also selects the corresponding X/Z slot.
# Set this to 0 in the Inspector if you prefer aiming at the board surface.
@export_category("Shelf Aiming")
@export_range(-0.25, 0.25, 0.005) var board_height_offset: float = 0.20

@onready var grid_map: GridMap = $GridMap


func _enter_tree() -> void:
	add_to_group("shelf_storage")


func raycast_cell(world_start: Vector3, world_end: Vector3) -> Dictionary:
	# Hit a horizontal "virtual shelf board" for each Y layer, then use the
	# intersection's X/Z coordinates to select a cell in that layer.
	#
	# Unlike raycasting 3D cell boxes, the front row CANNOT swallow a ray
	# aimed at the back row. No physics collider is needed for this selection.
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

	# All intersections happen in GridMap coordinates, so rotating/moving
	# a shelf instance does not change which X/Z cell is selected.
	var from_local: Vector3 = grid_map.to_local(world_start)
	var end_local: Vector3 = grid_map.to_local(world_end)
	var ray_delta: Vector3 = end_local - from_local
	if absf(ray_delta.y) < 0.00001:
		return {}

	var best_distance: float = INF
	var best_cell := Vector3i.ZERO
	var found := false

	for y in range(low.y, high.y + 1):
		# map_to_local includes Godot's cell_center_y offset. We need the
		# bottom/support plane of the item, not the center of its cell.
		var board_y: float = grid_map.map_to_local(Vector3i(0, y, 0)).y
		if grid_map.cell_center_y:
			board_y -= grid_map.cell_size.y * 0.5
		board_y += board_height_offset

		var t: float = (board_y - from_local.y) / ray_delta.y
		if t < 0.0 or t > 1.0:
			continue

		var local_hit: Vector3 = from_local + ray_delta * t
		# Only X and Z come from the ray hit. Y is exactly the board's layer.
		var mapped: Vector3i = grid_map.local_to_map(local_hit)
		if mapped.x < low.x or mapped.x > high.x:
			continue
		if mapped.z < low.z or mapped.z > high.z:
			continue

		var hit_distance: float = world_start.distance_to(grid_map.to_global(local_hit))
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_cell = Vector3i(mapped.x, y, mapped.z)
			found = true

	if not found:
		return {}

	return {
		"shelf": self,
		"grid": grid_map,
		"cell": best_cell,
		"distance": best_distance
	}
