extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@export_range(1.0, 30.0, 0.5) var placement_reach: float = 6.0

@onready var camera: Camera3D = $Camera3D
@onready var grid_map: GridMap = $"../GridMap"

var selected_index: int = 0
var placement_layer: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# Keep the existing escape hatch, even when the cursor is released.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().quit()
			return
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.keycode == KEY_R:
				placement_layer += 1
				print("Placement layer: ", placement_layer)
				return
			if event.keycode == KEY_F:
				placement_layer -= 1
				print("Placement layer: ", placement_layer)
				return

	if event is InputEventMouseButton and event.pressed:
		# First click after Esc only captures the mouse; it does not place.
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				edit_grid(false)
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				edit_grid(true)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				select_item(1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				select_item(-1)
		return

	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
			camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
			camera.rotation.x = clampf(
				camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0)
			)


func _physics_process(delta: float) -> void:
	# Godot 原生角色移动逻辑
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector(
		"ui_left", "ui_right", "ui_up", "ui_down"
	)

	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


func select_item(step: int) -> void:
	if grid_map.mesh_library == null:
		return

	var ids: PackedInt32Array = grid_map.mesh_library.get_item_list()
	if ids.is_empty():
		return

	selected_index = posmod(selected_index + step, ids.size())
	var item_id: int = ids[selected_index]
	print("Selected: ", grid_map.mesh_library.get_item_name(item_id))


func edit_grid(erase: bool) -> void:
	if grid_map.mesh_library == null:
		return

	# Intersect the camera's aim with a horizontal GridMap layer.
	# This works even though the current MeshLibrary has no collision shapes.
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var plane_point: Vector3 = grid_map.to_global(
		grid_map.map_to_local(Vector3i(0, placement_layer, 0))
	)
	var plane_normal: Vector3 = grid_map.global_transform.basis.y.normalized()
	var denominator: float = direction.dot(plane_normal)
	if absf(denominator) < 0.0001:
		return

	var distance: float = (plane_point - origin).dot(plane_normal) / denominator
	if distance <= 0.0 or distance > placement_reach:
		return

	var hit_position: Vector3 = origin + direction * distance
	var cell: Vector3i = grid_map.local_to_map(grid_map.to_local(hit_position))
	cell.y = placement_layer

	var existing_item: int = grid_map.get_cell_item(cell)
	if erase:
		if existing_item != GridMap.INVALID_CELL_ITEM:
			grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
		return

	# Do not overwrite an occupied slot.
	if existing_item != GridMap.INVALID_CELL_ITEM:
		return

	var ids: PackedInt32Array = grid_map.mesh_library.get_item_list()
	if ids.is_empty():
		return

	var item_id: int = ids[selected_index % ids.size()]
	grid_map.set_cell_item(cell, item_id)
	print("Placed ", grid_map.mesh_library.get_item_name(item_id), " at ", cell)
