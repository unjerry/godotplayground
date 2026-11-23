class_name ShelfStorage
extends Node3D

# Inclusive GridMap cell bounds. Each shelf exports its own X/Y/Z range.
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

@export_category("Shelf Aiming")
# Maximum distance from the camera ray to a slot's vertical bottle axis.
@export_range(0.04, 0.30, 0.005) var aim_radius: float = 0.14
# The selectable height extends UP from the bottle's base, not centered in Y.
@export_range(0.10, 0.55, 0.01) var aim_height: float = 0.40

@onready var grid_map: GridMap = $GridMap


func _enter_tree() -> void:
	add_to_group("shelf_storage")


func raycast_cell(world_start: Vector3, world_end: Vector3) -> Dictionary:
	# Test a bottle-sized VERTICAL segment at every permitted cell against
	# the camera ray. This selects front/back and upper/lower in ONE pass.
	# Never project downward to a shelf board after determining a Y layer:
	# that made X/Z drift to the far row when the camera looked down.
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

	var column_height: float = minf(aim_height, grid_map.cell_size.y * 0.95)
	var vertical_axis: Vector3 = grid_map.global_transform.basis.y.normalized()
	var best_score: float = INF
	var best_distance: float = INF
	var best_cell := Vector3i.ZERO
	var found: bool = false

	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				var base: Vector3 = grid_map.to_global(grid_map.map_to_local(cell))
				# cell_center_y is false. All bottle meshes are bottom-origin.
				var bottom: Vector3 = base + vertical_axis * 0.02
				var top: Vector3 = base + vertical_axis * column_height
				var closest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
					world_start, world_end, bottom, top
				)
				if closest.size() != 2:
					continue

				var miss: float = closest[0].distance_to(closest[1])
				if miss > aim_radius:
					continue
				var distance: float = world_start.distance_to(closest[0])
				if distance <= 0.10:
					continue

				# Closest to the screen center, not the first large GridMap
				# cell volume encountered. Prefer nearer cells on ties.
				var score: float = miss / distance + distance * 0.0005
				if score < best_score:
					best_score = score
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
