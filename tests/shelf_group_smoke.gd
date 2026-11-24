extends SceneTree
# godot --headless --path . --script res://tests/shelf_group_smoke.gd
# Uses the real shelf scenes and mesh library.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)


func _make_shelf(path: String) -> ShelfStorage:
	var scene: PackedScene = load(path) as PackedScene
	var shelf: ShelfStorage = scene.instantiate() as ShelfStorage
	root.add_child(shelf)
	return shelf


func _run() -> void:
	var wide: ShelfStorage = _make_shelf("res://shelf_01.tscn")
	var small: ShelfStorage = _make_shelf("res://shelf_02.tscn")
	var tall: ShelfStorage = _make_shelf("res://shelf_03.tscn")
	var ids: PackedInt32Array = small.grid_map.mesh_library.get_item_list()
	if ids.size() < 2:
		printerr("Need two potion types to run grouping tests")
		quit(1)
		return
	var a: int = ids[0]
	var b: int = ids[1]

	_check(wide.group_size == Vector2i(6, 1), "Wide shelf should group 6x1")
	_check(small.group_size == Vector2i(3, 2), "Small shelf should group 3x2")
	_check(tall.group_size == Vector2i(3, 2), "Tall shelf should group 3x2")
	var wide_hits: Array[Vector3i] = []
	wide.group_completed.connect(func(origin: Vector3i, _kind: int) -> void: wide_hits.append(origin))
	var first_wide := Vector3i(1, 0, -2)
	_check(wide.store_bottle(first_wide, a), "Wide first bottle")
	_check(not wide.can_store(Vector3i(2, 0, -2), b), "Wide group should reject different item")
	_check(wide.can_store(Vector3i(1, 0, -1), b), "Wide second row independent")
	for x in range(2, 7):
		_check(wide.store_bottle(Vector3i(x, 0, -2), a), "Wide fill x=%d" % x)
	_check(wide_hits.size() == 1, "Wide group awards once after six")
	wide.grid_map.set_cell_item(first_wide, GridMap.INVALID_CELL_ITEM)
	_check(wide.store_bottle(first_wide, a), "Wide reinsert")
	_check(wide_hits.size() == 1, "Wide group cannot award twice")

	var small_hits: Array[Vector3i] = []
	small.group_completed.connect(func(origin: Vector3i, _kind: int) -> void: small_hits.append(origin))
	var first_small := Vector3i(0, 0, -2)
	_check(small.store_bottle(first_small, a), "Small first bottle")
	_check(not small.can_store(Vector3i(1, 0, -1), b), "Small group rejects wrong item across both rows")
	_check(small.find_slot_in_group(a, Vector3i(2, 0, -1)) == Vector3i(1, 0, -2), "Auto-fill uses both Z rows")
	for z in range(-2, 0):
		for x in range(3):
			var cell := Vector3i(x, 0, z)
			if cell != first_small:
				_check(small.store_bottle(cell, a), "Small group fill %s" % str(cell))
	_check(small_hits.size() == 1, "Small 3x2 group awards after six")
	_check(not small.contains_cell(small.find_slot_in_group(a, first_small)), "Full small group has no vacancy")
	small.grid_map.set_cell_item(first_small, GridMap.INVALID_CELL_ITEM)
	_check(small.store_bottle(first_small, a), "Small reinsert")
	_check(small_hits.size() == 1, "Small group cannot award twice")

	var layer0 := Vector3i(0, 0, -2)
	var layer1 := Vector3i(0, 1, -2)
	_check(tall.store_bottle(layer0, a), "Tall shelf layer zero")
	_check(tall.store_bottle(layer1, b), "Tall shelf layer one independent")
	_check(tall.get_group_origin(Vector3i(2, 0, -1)) == layer0, "Rear row joins same group")
	_check(tall.get_group_origin(Vector3i(2, 1, -1)) == layer1, "Different heights use different groups")
	_check(tall.find_suitable_slot(a) == Vector3i(1, 0, -2), "Guide prioritizes matching group")

	wide.queue_free()
	small.queue_free()
	tall.queue_free()
	if failures.is_empty():
		print("PASS shelf groups: 6x1, 3x2, reward-once and skill targeting")
	quit(0 if failures.is_empty() else 1)
