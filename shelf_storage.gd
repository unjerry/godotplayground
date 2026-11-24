class_name ShelfStorage
extends Node3D

# Inclusive GridMap cell indices. Adjust each shelf's XYZ limits in Inspector.
@export_category("Placement Bounds (GridMap Cells)")
@export var min_cell: Vector3i = Vector3i(0, 0, -2)
@export var max_cell: Vector3i = Vector3i(2, 3, -1)

@export_category("Sorting Rules")
@export var clear_demo_items_on_start: bool = true
@export_range(1, 12, 1) var bottles_per_row: int = 6

signal row_completed(row_y: int, row_z: int, item_id: int)

@onready var grid_map: GridMap = $GridMap
var _awarded_rows: Dictionary = {}


func _ready() -> void:
    # Keep editor-designed GridMap decorations; begin gameplay with empty shelves.
    if clear_demo_items_on_start:
        grid_map.clear()


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


func row_item_id(row_y: int, row_z: int) -> int:
    var bounds: Array[Vector3i] = _ordered_bounds()
    var low: Vector3i = bounds[0]
    var high: Vector3i = bounds[1]
    var kind: int = GridMap.INVALID_CELL_ITEM
    for x in range(low.x, high.x + 1):
        var item: int = grid_map.get_cell_item(Vector3i(x, row_y, row_z))
        if item == GridMap.INVALID_CELL_ITEM:
            continue
        if kind != GridMap.INVALID_CELL_ITEM and kind != item:
            return -2  # An old mixed row cannot accept more bottles.
        kind = item
    return kind


func can_store(cell: Vector3i, item_id: int) -> bool:
    if not contains_cell(cell) or grid_map.mesh_library == null:
        return false
    if not grid_map.mesh_library.get_item_list().has(item_id):
        return false
    if grid_map.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
        return false
    var kind: int = row_item_id(cell.y, cell.z)
    return kind == GridMap.INVALID_CELL_ITEM or kind == item_id


func store_bottle(cell: Vector3i, item_id: int) -> bool:
    if not can_store(cell, item_id):
        return false
    grid_map.set_cell_item(cell, item_id)
    var row_key := Vector2i(cell.y, cell.z)
    if not _awarded_rows.has(row_key) and _row_is_complete(cell.y, cell.z, item_id):
        _awarded_rows[row_key] = true
        row_completed.emit(cell.y, cell.z, item_id)
    return true


func _row_is_complete(y: int, z: int, item_id: int) -> bool:
    var bounds: Array[Vector3i] = _ordered_bounds()
    var low: Vector3i = bounds[0]
    var high: Vector3i = bounds[1]
    if high.x - low.x + 1 != bottles_per_row:
        return false
    for x in range(low.x, high.x + 1):
        if grid_map.get_cell_item(Vector3i(x, y, z)) != item_id:
            return false
    return true


func find_slot_in_row(item_id: int, row_y: int, row_z: int) -> Vector3i:
    var bounds: Array[Vector3i] = _ordered_bounds()
    var low: Vector3i = bounds[0]
    var high: Vector3i = bounds[1]
    if row_y < low.y or row_y > high.y or row_z < low.z or row_z > high.z:
        return Vector3i(-9999, -9999, -9999)
    for x in range(low.x, high.x + 1):
        var cell := Vector3i(x, row_y, row_z)
        if can_store(cell, item_id):
            return cell
    return Vector3i(-9999, -9999, -9999)


func find_suitable_slot(item_id: int) -> Vector3i:
    # Prioritize partially filled rows of this exact potion type.
    var bounds: Array[Vector3i] = _ordered_bounds()
    var low: Vector3i = bounds[0]
    var high: Vector3i = bounds[1]
    for matching_only in [true, false]:
        for y in range(low.y, high.y + 1):
            for z in range(low.z, high.z + 1):
                var row_type: int = row_item_id(y, z)
                if matching_only and row_type != item_id:
                    continue
                if not matching_only and row_type != GridMap.INVALID_CELL_ITEM:
                    continue
                var cell: Vector3i = find_slot_in_row(item_id, y, z)
                if contains_cell(cell):
                    return cell
    return Vector3i(-9999, -9999, -9999)



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
