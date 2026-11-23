extends CharacterBody3D

# Playable prototype: loose physics bottles <-> inventory <-> shelf GridMap.
const POTIONS = preload("res://new_mesh_library.tres")
const BOTTLE_SCENE = preload("res://bottle.tscn")

@export var walk_speed: float = 5.0
@export var jump_speed: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export_range(1, 20, 1) var inventory_capacity: int = 8
@export var reach: float = 4.5
@export var throw_speed: float = 4.0

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractionRay
@onready var inventory_text: Label = $"../HUD/InventoryPanel/InventoryText"
@onready var hint_text: Label = $"../HUD/Hint"
@onready var loose_items: Node3D = $"../LooseItems"

var inventory: Array[int] = []
var selected_index: int = 0
var target: Dictionary = {}

var ghost: MeshInstance3D
var ghost_item_id: int = -1
var ghost_materials: Array[StandardMaterial3D] = []

# A slot marker is visible even with an empty inventory. It is not a ground grid.
var slot_marker: MeshInstance3D
var slot_material: StandardMaterial3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ray.target_position = Vector3(0, 0, -reach)
	ray.add_exception(self)

	ghost = MeshInstance3D.new()
	ghost.name = "BottlePlacementGhost"
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	slot_marker = MeshInstance3D.new()
	slot_marker.name = "ShelfSlotMarker"
	slot_marker.visible = false
	slot_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 3D wireframe cage for the exact selected GridMap cell. Use a
	# normalized box here; the transform scales it by that shelf's cell_size.
	var lines := ImmediateMesh.new()
	slot_material = StandardMaterial3D.new()
	slot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slot_material.no_depth_test = true
	slot_material.albedo_color = Color(0.2, 0.9, 1.0, 0.95)
	var corners := [
		Vector3(-0.49, 0.02, -0.49), Vector3(0.49, 0.02, -0.49),
		Vector3(0.49, 0.02, 0.49), Vector3(-0.49, 0.02, 0.49),
		Vector3(-0.49, 0.98, -0.49), Vector3(0.49, 0.98, -0.49),
		Vector3(0.49, 0.98, 0.49), Vector3(-0.49, 0.98, 0.49)
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7]
	]
	lines.surface_begin(Mesh.PRIMITIVE_LINES, slot_material)
	for edge in edges:
		lines.surface_add_vertex(corners[edge[0]])
		lines.surface_add_vertex(corners[edge[1]])
	lines.surface_end()
	slot_marker.mesh = lines

	# In _ready(), the scene root may still be constructing its children.
	# Defer both additions to avoid "Parent node is busy setting up children".
	var root: Node = get_tree().current_scene
	root.add_child.call_deferred(ghost)
	root.add_child.call_deferred(slot_marker)
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
	_refresh_slot_marker()
	_refresh_ghost()
	_refresh_hint()


func _refresh_target() -> void:
	target.clear()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var end_point: Vector3 = origin + direction * reach

	# Find the nearest actual 3D cell struck by the camera ray across
	# every shelf. No plane projection, coordinate clamping or auto search.
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group("shelf_storage"):
		var shelf: ShelfStorage = node as ShelfStorage
		if shelf == null:
			continue
		var hit: Dictionary = shelf.raycast_cell(origin, end_point)
		if hit.is_empty():
			continue
		var distance: float = hit["distance"]
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = hit

	# Loose bottles remain physics objects. Their collider takes priority
	# only when it lies in front of the selected shelf cell.
	if ray.is_colliding():
		var hit_node: Node = ray.get_collider() as Node
		var physics_distance: float = origin.distance_to(ray.get_collision_point())

		if hit_node is BottleItem:
			if physics_distance <= nearest_distance + 0.015:
				target = {"kind": "loose", "bottle": hit_node}
				return
		elif hit_node != null and _find_shelf_root(hit_node) == null:
			if physics_distance + 0.015 < nearest_distance:
				return

	if not nearest.is_empty():
		target = nearest
		target["kind"] = "shelf"


func _find_shelf_root(from_node: Node) -> ShelfStorage:
	var node: Node = from_node
	while node != null:
		if node is ShelfStorage:
			return node as ShelfStorage
		node = node.get_parent()
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
		var cell: Vector3i = target["cell"]
		var item_id: int = grid.get_cell_item(cell)
		if item_id == GridMap.INVALID_CELL_ITEM or not POTIONS.get_item_list().has(item_id):
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
		var cell: Vector3i = target["cell"]
		# Only the EXACT highlighted cell can be filled. If occupied,
		# do not silently move the bottle to another depth or height.
		if grid.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
			return
		if grid.mesh_library == null or not grid.mesh_library.get_item_list().has(item_id):
			return
		grid.set_cell_item(cell, item_id)
	else:
		_throw_bottle(item_id)

	inventory.remove_at(selected_index)
	if inventory.is_empty():
		selected_index = 0
	else:
		selected_index = mini(selected_index, inventory.size() - 1)
	_refresh_inventory_text()


func _throw_bottle(item_id: int) -> void:
	var bottle: BottleItem = BOTTLE_SCENE.instantiate() as BottleItem
	bottle.item_id = item_id
	loose_items.add_child(bottle)

	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	bottle.global_position = camera.global_position + forward * 0.85 - Vector3.UP * 0.12
	bottle.linear_velocity = forward * throw_speed + Vector3.UP * 0.7 + velocity * 0.35
	bottle.angular_velocity = camera.global_transform.basis.x * 2.0


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
	lines.append("LMB  shelf / throw")
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
		var cell: Vector3i = target["cell"]
		var occupied: bool = grid.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM
		var messages := PackedStringArray()
		if occupied and inventory.size() < inventory_capacity:
			messages.append("E  TAKE FROM SHELF")
		if not occupied and not inventory.is_empty():
			messages.append("LMB  STORE IN SHELF")
		if messages.is_empty():
			messages.append("SHELF SLOT: " + ("OCCUPIED" if occupied else "EMPTY"))
		hint_text.text = "  |  ".join(messages)
		return

	if inventory.is_empty():
		hint_text.text = "E  PICK UP A BOTTLE"
	else:
		hint_text.text = "LMB  THROW BOTTLE"


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


func _refresh_slot_marker() -> void:
	slot_marker.visible = false
	if not slot_marker.is_inside_tree() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if target.get("kind", "") != "shelf":
		return

	var grid: GridMap = target["grid"]
	var cell: Vector3i = target["cell"]
	var occupied: bool = grid.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM
	if inventory.is_empty():
		slot_material.albedo_color = (
			Color(0.15, 0.8, 1.0, 0.95)
			if occupied else Color(0.55, 0.6, 0.65, 0.5)
		)
	else:
		slot_material.albedo_color = (
			Color(1.0, 0.3, 0.3, 0.95)
			if occupied else Color(0.2, 1.0, 0.45, 0.95)
		)

	slot_marker.global_transform = Transform3D(
		grid.global_transform.basis.scaled(grid.cell_size),
		grid.to_global(grid.map_to_local(cell))
	)
	slot_marker.visible = true


func _refresh_ghost() -> void:
	ghost.visible = false
	if not ghost.is_inside_tree():
		return
	if inventory.is_empty() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if target.get("kind", "") != "shelf":
		return

	var item_id: int = inventory[selected_index]
	if item_id != ghost_item_id:
		_make_ghost_mesh(item_id)
	if ghost.mesh == null:
		return

	var grid: GridMap = target["grid"]
	var cell: Vector3i = target["cell"]
	var can_place: bool = grid.get_cell_item(cell) == GridMap.INVALID_CELL_ITEM

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
