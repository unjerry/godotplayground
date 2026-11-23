extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@export_range(1.0, 30.0, 0.5) var placement_reach: float = 6.0

@onready var camera: Camera3D = $Camera3D
@onready var grid_map: GridMap = get_node_or_null("../GridMap") as GridMap

var selected_index: int = 0
var placement_layer: int = 0

# Runtime-only ghost: it uses the same mesh as the GridMap cell, but no collision.
var placement_preview: MeshInstance3D
var preview_item_id: int = -1
var preview_materials: Array[StandardMaterial3D] = []
var preview_occupied: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if grid_map == null:
		return
	placement_preview = MeshInstance3D.new()
	placement_preview.name = "PlacementGhost"
	placement_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	placement_preview.visible = false
	grid_map.add_child(placement_preview)
	_refresh_preview_mesh()


func _process(_delta: float) -> void:
	if grid_map != null:
		_update_placement_preview()


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
	# Godot native character movement, gravity and jumping.
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
	_refresh_preview_mesh()
	print("Selected: ", grid_map.mesh_library.get_item_name(item_id))


func _get_target_cell() -> Variant:
	if grid_map == null or grid_map.mesh_library == null:
		return null

	# Shoot the camera's central ray onto the chosen horizontal grid layer.
	# The MeshLibrary has no collision shapes, so a physics ray would miss it.
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var plane_point: Vector3 = grid_map.to_global(
		grid_map.map_to_local(Vector3i(0, placement_layer, 0))
	)
	var plane_normal: Vector3 = grid_map.global_transform.basis.y.normalized()
	var denominator: float = direction.dot(plane_normal)
	if absf(denominator) < 0.0001:
		return null

	var distance: float = (plane_point - origin).dot(plane_normal) / denominator
	if distance <= 0.0 or distance > placement_reach:
		return null

	var hit_position: Vector3 = origin + direction * distance
	var cell: Vector3i = grid_map.local_to_map(grid_map.to_local(hit_position))
	cell.y = placement_layer
	return cell


func _refresh_preview_mesh() -> void:
	placement_preview.visible = false
	placement_preview.mesh = null
	preview_materials.clear()
	preview_item_id = -1

	if grid_map.mesh_library == null:
		return
	var library: MeshLibrary = grid_map.mesh_library
	var ids: PackedInt32Array = library.get_item_list()
	if ids.is_empty():
		return

	var item_id: int = ids[selected_index % ids.size()]
	var item_mesh: Mesh = library.get_item_mesh(item_id)
	if item_mesh == null:
		return

	placement_preview.mesh = item_mesh
	preview_item_id = item_id

	for surface in range(item_mesh.get_surface_count()):
		# Duplicate material resources, so the real bottles stay opaque.
		var source: Material = item_mesh.surface_get_material(surface)
		var ghost_material := StandardMaterial3D.new()
		if source is StandardMaterial3D:
			ghost_material = source.duplicate() as StandardMaterial3D

		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.emission_enabled = true
		ghost_material.emission_energy_multiplier = 0.35
		placement_preview.set_surface_override_material(surface, ghost_material)
		preview_materials.append(ghost_material)

	preview_occupied = false
	_tint_preview(false)


func _tint_preview(occupied: bool) -> void:
	preview_occupied = occupied
	for material in preview_materials:
		# Keep the potion texture visible beneath the translucent tint.
		material.albedo_color = (
			Color(1.0, 0.32, 0.32, 0.46)
			if occupied else Color(0.78, 1.0, 0.93, 0.42)
		)
		material.emission = (
			Color(0.95, 0.12, 0.12)
			if occupied else Color(0.12, 0.75, 0.55)
		)


func _update_placement_preview() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or preview_item_id < 0:
		placement_preview.visible = false
		return

	var hit: Variant = _get_target_cell()
	if hit == null:
		placement_preview.visible = false
		return

	var cell: Vector3i = hit
	var occupied: bool = (
		grid_map.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM
	)
	if occupied != preview_occupied:
		_tint_preview(occupied)

	# Match GridMap's placement offset, cell scale and MeshLibrary transform.
	var cell_transform := Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * grid_map.cell_scale),
		grid_map.map_to_local(cell)
	)
	placement_preview.transform = (
		cell_transform
		* grid_map.mesh_library.get_item_mesh_transform(preview_item_id)
	)
	placement_preview.visible = true


func edit_grid(erase: bool) -> void:
	var hit: Variant = _get_target_cell()
	if hit == null:
		return

	var cell: Vector3i = hit
	var existing_item: int = grid_map.get_cell_item(cell)
	if erase:
		if existing_item != GridMap.INVALID_CELL_ITEM:
			grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
		return

	if existing_item != GridMap.INVALID_CELL_ITEM:
		return

	var ids: PackedInt32Array = grid_map.mesh_library.get_item_list()
	if ids.is_empty():
		return
	var item_id: int = ids[selected_index % ids.size()]
	grid_map.set_cell_item(cell, item_id)
	print("Placed ", grid_map.mesh_library.get_item_name(item_id), " at ", cell)
