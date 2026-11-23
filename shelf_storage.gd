class_name ShelfStorage
extends Node3D

# Inclusive GridMap cell indices. Adjust each shelf's XYZ limits in Inspector.
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

@onready var grid_map: GridMap = $GridMap


func _enter_tree() -> void:
	add_to_group("shelf_storage")


func raycast_cell(world_start: Vector3, world_end: Vector3) -> Dictionary:
	# Ray-plane targeting: each permitted Y layer is a horizontal shelf board.
	# 1. Find where the camera ray FIRST reaches a shelf-board plane.
	# 2. Convert that SAME intersection point to its X/Z GridMap cell.
	#
	# Never pick the closest bottle axis or extrapolate a second time to
	# another height. A nearer board blocks targets on boards behind it.
	# Loose bottles are still physics bodies (handled by gameplay_player.gd).
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

	# Working in GridMap-local space also handles rotated/moved shelves.
	var origin: Vector3 = grid_map.to_local(world_start)
	var finish: Vector3 = grid_map.to_local(world_end)
	var direction: Vector3 = finish - origin
	if absf(direction.y) < 0.00001:
		return {}  # A horizontal ray does not hit a horizontal board.

	# X and Z have centered cells; their limits are half a cell beyond
	# the first/last cell centers. Y does NOT get a half-cell offset.
	var half_x: float = grid_map.cell_size.x * 0.5
	var half_z: float = grid_map.cell_size.z * 0.5
	var first_center: Vector3 = grid_map.map_to_local(Vector3i(low.x, 0, low.z))
	var last_center: Vector3 = grid_map.map_to_local(Vector3i(high.x, 0, high.z))
	var x_min: float = minf(first_center.x, last_center.x) - half_x
	var x_max: float = maxf(first_center.x, last_center.x) + half_x
	var z_min: float = minf(first_center.z, last_center.z) - half_z
	var z_max: float = maxf(first_center.z, last_center.z) + half_z

	var first_t: float = INF
	var first_cell := Vector3i.ZERO
	var first_hit := Vector3.ZERO
	var found := false

	for y in range(low.y, high.y + 1):
		# With cell_center_y=false, map_to_local is the bottle-bottom plane.
		var board_y: float = grid_map.map_to_local(Vector3i(0, y, 0)).y
		var t: float = (board_y - origin.y) / direction.y
		if t < 0.0 or t > 1.0 or t >= first_t:
			continue

		var hit: Vector3 = origin + direction * t
		# Only intersect permitted shelf-board area. Never clamp an
		# out-of-range hit onto the nearest shelf cell.
		if hit.x < x_min or hit.x >= x_max:
			continue
		if hit.z < z_min or hit.z >= z_max:
			continue

		# X/Z are read at EXACTLY this board intersection, not projected
		# farther along the ray. Y is the selected board's discrete layer.
		var mapped: Vector3i = grid_map.local_to_map(hit)
		if mapped.x < low.x or mapped.x > high.x:
			continue
		if mapped.z < low.z or mapped.z > high.z:
			continue

		first_t = t
		first_cell = Vector3i(mapped.x, y, mapped.z)
		first_hit = hit
		found = true

	if not found:
		return {}

	return {
		"shelf": self,
		"grid": grid_map,
		"cell": first_cell,
		"distance": world_start.distance_to(grid_map.to_global(first_hit))
	}
