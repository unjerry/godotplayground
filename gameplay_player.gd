extends CharacterBody3D

# Playable prototype: loose physics bottles <-> inventory <-> shelf GridMap.
const POTIONS = preload("res://new_mesh_library.tres")
const BOTTLE_SCENE = preload("res://bottle.tscn")

@export var walk_speed: float = 5.0
@export var jump_speed: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export_range(1, 20, 1) var inventory_capacity: int = 8
@export var reach: float = 4.5

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractionRay
@onready var inventory_text: Label = $"../HUD/InventoryPanel/InventoryText"
@onready var hint_text: Label = $"../HUD/Hint"
@onready var loose_items: Node3D = $"../LooseItems"

var inventory: Array[int] = []
var selected_index: int = 0
var target: Dictionary = {}
var shelf_bounds: Dictionary = {}  # GridMap instance ID -> initial used-cell limits.

var ghost: MeshInstance3D
var ghost_item_id: int = -1
var ghost_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ray.target_position = Vector3(0, 0, -reach)
	ray.add_exception(self)

	ghost = MeshInstance3D.new()
	ghost.name = "BottlePlacementGhost"
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ghost)
	_refresh_inventory_text()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().quit()
			return
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.keycode == KEY_E:
				_pick_up()
				return
			if event.keycode >= KEY_1 and event.keycode <= KEY_8:
				var slot: int = event.keycode - KEY_1
				if slot < inventory.size():
					selected_index = slot
					_refresh_inventory_text()
				return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_place_selected()
			return
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_select_inventory(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_select_inventory(1)
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_speed

	var move_axis := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(move_axis.x, 0, move_axis.y)).normalized()
	velocity.x = direction.x * walk_speed
	velocity.z = direction.z * walk_speed
	move_and_slide()

	# Refresh the ray AFTER the player moves. All physics queries are in
	# _physics_process, so they work with threaded physics as well.
	ray.force_raycast_update()
	_refresh_target()
	_refresh_ghost()
	_refresh_hint()


func _refresh_target() -> void:
	target.clear()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not ray.is_colliding():
		return

	var hit_node: Node = ray.get_collider() as Node
	if hit_node is BottleItem:
		target = {"kind": "loose", "bottle": hit_node}
		return

	var shelf: Node3D = _find_shelf_root(hit_node)
	if shelf != null:
		var grid: GridMap = shelf.get_node("GridMap") as GridMap
		var aimed: Variant = _aimed_shelf_cell(grid)
		if aimed != null:
			target = {"kind": "shelf", "grid": grid, "cell": aimed}
		return

	var normal: Vector3 = ray.get_collision_normal()
	if normal.dot(Vector3.UP) > 0.7:
		target = {
			"kind": "floor",
			"point": ray.get_collision_point(),
			"normal": normal
		}


func _find_shelf_root(from_node: Node) -> Node3D:
	var node: Node = from_node
	while node != null:
		if String(node.name).begins_with("shelf") and node.get_node_or_null("GridMap") is GridMap:
			return node as Node3D
		node = node.get_parent()
	return null


func _get_bounds(grid: GridMap) -> Dictionary:
	var key: int = grid.get_instance_id()
	if shelf_bounds.has(key):
		return shelf_bounds[key]

	# Each authored shelf already has bottles marking the intended usable area.
	# Snapshot its bounds once: picking every bottle does not shrink the slots.
	var used: Array[Vector3i] = grid.get_used_cells()
	if used.is_empty():
		return {}
	var low: Vector3i = used[0]
	var high: Vector3i = used[0]
	for cell in used:
		low = Vector3i(
			mini(low.x, cell.x), mini(low.y, cell.y), mini(low.z, cell.z)
		)
		high = Vector3i(
			maxi(high.x, cell.x), maxi(high.y, cell.y), maxi(high.z, cell.z)
		)
	var bounds := {"min": low, "max": high}
	shelf_bounds[key] = bounds
	return bounds


func _aimed_shelf_cell(grid: GridMap) -> Variant:
	var bounds: Dictionary = _get_bounds(grid)
	if bounds.is_empty():
		return null

	var low: Vector3i = bounds["min"]
	var high: Vector3i = bounds["max"]

	# Project the central aim ray onto the front row of the shelf. This
	# deliberately does not depend on per-bottle collision shapes, and works
	# around the current shelf's single solid-box collision prototype.
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var plane_point: Vector3 = grid.to_global(
		grid.map_to_local(Vector3i(0, 0, low.z))
	)
	var normal: Vector3 = grid.global_transform.basis.z.normalized()
	var denominator: float = direction.dot(normal)
	if absf(denominator) < 0.0001:
		return null
	var distance: float = (plane_point - origin).dot(normal) / denominator
	if distance < 0.0 or distance > reach:
		return null

	var cell: Vector3i = grid.local_to_map(
		grid.to_local(origin + direction * distance)
	)
	cell.z = low.z  # Front row first; use the next row when appropriate.
	if cell.x < low.x or cell.x > high.x or cell.y < low.y or cell.y > high.y:
		return null
	return cell


func _find_shelf_slot(grid: GridMap, aimed: Vector3i, want_empty: bool) -> Variant:
	var bounds: Dictionary = _get_bounds(grid)
	if bounds.is_empty():
		return null
	var low: Vector3i = bounds["min"]
	var high: Vector3i = bounds["max"]
	for z in range(low.z, high.z + 1):
		var cell := Vector3i(aimed.x, aimed.y, z)
		var occupied: bool = grid.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM
		if occupied != want_empty:
			return cell
	return null


func _pick_up() -> void:
	if inventory.size() >= inventory_capacity:
		return

	var kind: String = target.get("kind", "")
	if kind == "loose":
		var bottle: BottleItem = target["bottle"] as BottleItem
		if not is_instance_valid(bottle) or bottle.is_queued_for_deletion():
			return
		inventory.append(bottle.item_id)
		bottle.collision_layer = 0
		bottle.queue_free()
	elif kind == "shelf":
		var grid: GridMap = target["grid"]
		var aimed: Vector3i = target["cell"]
		var picked: Variant = _find_shelf_slot(grid, aimed, false)
		if picked == null:
			return
		var cell: Vector3i = picked
		var item_id: int = grid.get_cell_item(cell)
		if not POTIONS.get_item_list().has(item_id):
			return
		inventory.append(item_id)
		grid.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	else:
		return

	selected_index = inventory.size() - 1
	_refresh_inventory_text()


func _place_selected() -> void:
	if inventory.is_empty():
		return
	var item_id: int = inventory[selected_index]
	var kind: String = target.get("kind", "")

	if kind == "shelf":
		var grid: GridMap = target["grid"]
		var aimed: Vector3i = target["cell"]
		var empty_slot: Variant = _find_shelf_slot(grid, aimed, true)
		if empty_slot == null or not grid.mesh_library.get_item_list().has(item_id):
			return
		var cell: Vector3i = empty_slot
		grid.set_cell_item(cell, item_id)
	elif kind == "floor":
		var bottle: BottleItem = BOTTLE_SCENE.instantiate() as BottleItem
		bottle.item_id = item_id
		loose_items.add_child(bottle)
		var point: Vector3 = target["point"]
		var normal: Vector3 = target["normal"]
		bottle.global_position = point + normal * 0.025
	else:
		return

	inventory.remove_at(selected_index)
	if inventory.is_empty():
		selected_index = 0
	else:
		selected_index = mini(selected_index, inventory.size() - 1)
	_refresh_inventory_text()


func _select_inventory(step: int) -> void:
	if inventory.is_empty():
		return
	selected_index = posmod(selected_index + step, inventory.size())
	_refresh_inventory_text()


func _potion_name(item_id: int) -> String:
	if not POTIONS.get_item_list().has(item_id):
		return "unknown"
	return POTIONS.get_item_name(item_id).trim_prefix("potion_").replace("_", " ")


func _refresh_inventory_text() -> void:
	var lines := PackedStringArray()
	lines.append("BOTTLES   %d / %d" % [inventory.size(), inventory_capacity])
	lines.append("-----------------------")
	if inventory.is_empty():
		lines.append("(empty)")
	else:
		for i in range(inventory.size()):
			var pointer := "> " if i == selected_index else "  "
			lines.append("%s%d. %s" % [pointer, i + 1, _potion_name(inventory[i])])
	lines.append("")
	lines.append("E  pick up")
	lines.append("LMB  place / drop")
	lines.append("Wheel / 1-8  select")
	inventory_text.text = "\n".join(lines)


func _refresh_hint() -> void:
	var kind: String = target.get("kind", "")
	if kind == "loose":
		var bottle: BottleItem = target["bottle"] as BottleItem
		if is_instance_valid(bottle):
			if inventory.size() < inventory_capacity:
				hint_text.text = "E  PICK UP  " + _potion_name(bottle.item_id)
			else:
				hint_text.text = "INVENTORY FULL"
			return
	if kind == "shelf":
		var grid: GridMap = target["grid"]
		var aimed: Vector3i = target["cell"]
		var pickable: Variant = _find_shelf_slot(grid, aimed, false)
		var placeable: Variant = _find_shelf_slot(grid, aimed, true)
		var prompts := PackedStringArray()
		if pickable != null and inventory.size() < inventory_capacity:
			prompts.append("E  TAKE FROM SHELF")
		if placeable != null and not inventory.is_empty():
			prompts.append("LMB  STORE IN SHELF")
		hint_text.text = "   |   ".join(prompts)
		return
	if kind == "floor" and not inventory.is_empty():
		hint_text.text = "LMB  DROP ON FLOOR"
	else:
		hint_text.text = "Aim at a bottle, shelf slot, or floor"


func _make_ghost_mesh(item_id: int) -> void:
	ghost.mesh = null
	ghost_materials.clear()
	ghost_item_id = -1
	if not POTIONS.get_item_list().has(item_id):
		return
	var mesh: Mesh = POTIONS.get_item_mesh(item_id)
	if mesh == null:
		return

	ghost.mesh = mesh
	ghost_item_id = item_id
	for surface in range(mesh.get_surface_count()):
		var source: Material = mesh.surface_get_material(surface)
		var material := StandardMaterial3D.new()
		if source is StandardMaterial3D:
			material = source.duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission_energy_multiplier = 0.3
		ghost.set_surface_override_material(surface, material)
		ghost_materials.append(material)


func _tint_ghost(allowed: bool) -> void:
	for material in ghost_materials:
		material.albedo_color = (
			Color(0.72, 1.0, 0.86, 0.43)
			if allowed else Color(1.0, 0.34, 0.34, 0.45)
		)
		material.emission = (
			Color(0.12, 0.6, 0.45)
			if allowed else Color(0.8, 0.1, 0.1)
		)


func _refresh_ghost() -> void:
	ghost.visible = false
	if inventory.is_empty() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var kind: String = target.get("kind", "")
	if kind != "floor" and kind != "shelf":
		return

	var item_id: int = inventory[selected_index]
	if item_id != ghost_item_id:
		_make_ghost_mesh(item_id)
	if ghost.mesh == null:
		return

	if kind == "floor":
		var drop_point: Vector3 = target["point"]
		ghost.global_transform = Transform3D(Basis.IDENTITY, drop_point + Vector3.UP * 0.012)
		_tint_ghost(true)
	else:
		var grid: GridMap = target["grid"]
		var aimed: Vector3i = target["cell"]
		var candidate: Variant = _find_shelf_slot(grid, aimed, true)
		var can_place: bool = candidate != null
		var cell: Vector3i = aimed
		if can_place:
			cell = candidate
		var local_transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * grid.cell_scale),
			grid.map_to_local(cell)
		)
		ghost.global_transform = (
			grid.global_transform
			* local_transform
			* grid.mesh_library.get_item_mesh_transform(item_id)
		)
		_tint_ghost(can_place)

	ghost.visible = true
