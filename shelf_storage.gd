class_name ShelfStorage
extends Node3D

# Inclusive GridMap cell indices. Adjust each shelf's XYZ limits in Inspector.
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

@export_category("Sorting Rules")
## XZ cell dimensions of one sorting group on each Y layer.
## Wide shelf = (6, 1); small shelf = (3, 2).
@export var group_size: Vector2i = Vector2i(6, 1)
@export var clear_demo_items_on_start: bool = true

signal group_completed(group_origin: Vector3i, item_id: int)

const INVALID_SLOT := Vector3i(-9999, -9999, -9999)
const MIXED_GROUP_ITEM := -2

@onready var grid_map: GridMap = $GridMap
var _awarded_groups: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("shelf_storage")


func _ready() -> void:
	if not _valid_group_size():
		push_error("ShelfStorage group_size must have positive X and Z dimensions.")
		return
	var bounds: Array[Vector3i] = _ordered_bounds()
	var low: Vector3i = bounds[0]
	var high: Vector3i = bounds[1]
	if (high.x - low.x + 1) % group_size.x != 0 or (high.z - low.z + 1) % group_size.y != 0:
		push_warning("Shelf bounds do not fit complete groups; leftover cells are not usable.")
	if clear_demo_items_on_start:
		grid_map.clear()


func _valid_group_size() -> bool:
	return group_size.x > 0 and group_size.y > 0


func _ordered_bounds() -> Array[Vector3i]:
	return [
		Vector3i(mini(min_cell.x, max_cell.x), mini(min_cell.y, max_cell.y), mini(min_cell.z, max_cell.z)),
		Vector3i(maxi(min_cell.x, max_cell.x), maxi(min_cell.y, max_cell.y), maxi(min_cell.z, max_cell.z))
	]


func contains_cell(cell: Vector3i) -> bool:
	var bounds: Array[Vector3i] = _ordered_bounds()
	var low: Vector3i = bounds[0]
	var high: Vector3i = bounds[1]
	return cell.x >= low.x and cell.x <= high.x and cell.y >= low.y and cell.y <= high.y and cell.z >= low.z and cell.z <= high.z


func _valid_group_origin(origin: Vector3i) -> bool:
	if not _valid_group_size() or not contains_cell(origin):
		return false
	var high: Vector3i = _ordered_bounds()[1]
	return origin.x + group_size.x - 1 <= high.x and origin.z + group_size.y - 1 <= high.z


func get_group_origin(cell: Vector3i) -> Vector3i:
	if not contains_cell(cell) or not _valid_group_size():
		return INVALID_SLOT
	var low: Vector3i = _ordered_bounds()[0]
	var group_x: int = floori(float(cell.x - low.x) / float(group_size.x))
	var group_z: int = floori(float(cell.z - low.z) / float(group_size.y))
	var origin := Vector3i(low.x + group_x * group_size.x, cell.y, low.z + group_z * group_size.y)
	return origin if _valid_group_origin(origin) else INVALID_SLOT


func _group_item_id(origin: Vector3i) -> int:
	if not _valid_group_origin(origin):
		return MIXED_GROUP_ITEM
	var kind: int = GridMap.INVALID_CELL_ITEM
	for z in range(origin.z, origin.z + group_size.y):
		for x in range(origin.x, origin.x + group_size.x):
			var item: int = grid_map.get_cell_item(Vector3i(x, origin.y, z))
			if item == GridMap.INVALID_CELL_ITEM:
				continue
			if kind != GridMap.INVALID_CELL_ITEM and kind != item:
				return MIXED_GROUP_ITEM
			kind = item
	return kind


func can_store(cell: Vector3i, item_id: int) -> bool:
	if not contains_cell(cell) or grid_map.mesh_library == null:
		return false
	if not grid_map.mesh_library.get_item_list().has(item_id):
		return false
	if grid_map.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
		return false
	var origin: Vector3i = get_group_origin(cell)
	if not _valid_group_origin(origin):
		return false
	var kind: int = _group_item_id(origin)
	return kind == GridMap.INVALID_CELL_ITEM or kind == item_id


func _group_is_complete(origin: Vector3i, item_id: int) -> bool:
	if not _valid_group_origin(origin):
		return false
	for z in range(origin.z, origin.z + group_size.y):
		for x in range(origin.x, origin.x + group_size.x):
			if grid_map.get_cell_item(Vector3i(x, origin.y, z)) != item_id:
				return false
	return true


func store_bottle(cell: Vector3i, item_id: int) -> bool:
	if not can_store(cell, item_id):
		return false
	grid_map.set_cell_item(cell, item_id)
	var origin: Vector3i = get_group_origin(cell)
	if not _awarded_groups.has(origin) and _group_is_complete(origin, item_id):
		_awarded_groups[origin] = true
		group_completed.emit(origin, item_id)
	return true


func find_slot_in_group(item_id: int, aimed_cell: Vector3i) -> Vector3i:
	# Only fill the group under the crosshair, including both Z rows on small shelves.
	var origin: Vector3i = get_group_origin(aimed_cell)
	if not _valid_group_origin(origin):
		return INVALID_SLOT
	for z in range(origin.z, origin.z + group_size.y):
		for x in range(origin.x, origin.x + group_size.x):
			var cell := Vector3i(x, origin.y, z)
			if can_store(cell, item_id):
				return cell
	return INVALID_SLOT


func find_suitable_slot(item_id: int) -> Vector3i:
	# Finish an existing matching group before starting an empty one.
	if not _valid_group_size():
		return INVALID_SLOT
	var bounds: Array[Vector3i] = _ordered_bounds()
	var low: Vector3i = bounds[0]
	var high: Vector3i = bounds[1]
	for matching_only in [true, false]:
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1, group_size.y):
				for x in range(low.x, high.x + 1, group_size.x):
					var origin := Vector3i(x, y, z)
					if not _valid_group_origin(origin):
						continue
					var kind: int = _group_item_id(origin)
					if matching_only and kind != item_id:
						continue
					if not matching_only and kind != GridMap.INVALID_CELL_ITEM:
						continue
					var slot: Vector3i = find_slot_in_group(item_id, origin)
					if contains_cell(slot):
						return slot
	return INVALID_SLOT


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
