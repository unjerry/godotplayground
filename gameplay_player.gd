extends CharacterBody3D

# Playable prototype: loose physics bottles <-> inventory <-> shelf GridMap.
const POTIONS = preload("res://new_mesh_library.tres")
const BOTTLE_SCENE = preload("res://bottle.tscn")

@export var walk_speed: float = 5.0
@export var jump_speed: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export_range(1, 20, 1) var inventory_capacity: int = 6
@export_range(0, 20, 1) var starting_bottles: int = 6
@export_range(0, 11, 1) var starting_item_id: int = 0
@export var sprint_speed_multiplier: float = 1.65
@export var reach: float = 4.5
@export var throw_speed: float = 4.0
@export_range(1, 500, 1) var total_potion_goal: int = 72

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractionRay
@onready var inventory_text: Label = $"../HUD/InventoryPanel/InventoryText"
@onready var interaction_hint: Node = $"../HUD2/Control/InteractionHint"
@onready var carry_hud: Node = $"../HUD2/Control/BottomRightCarry"
@onready var skill_book: Control = $"../HUD2/Control/SkillBook"
@onready var progress_hud: Control = $"../HUD2/Control/TopLeftStatus"
@onready var skill_hotbar: Control = $"../HUD2/Control/BottomLeftSkills"
@onready var loose_items: Node3D = $"../LooseItems"

var inventory: Array[int] = []
var selected_index: int = 0
var bottles_shelved: int = 0
var completed_groups: int = 0
var skill_levels: Dictionary = {}
var skill_cooldowns: Dictionary = {}
var skill_active_times: Dictionary = {}
var _auto_store_tick: float = 0.0
var _skill_ui_tick: float = 0.0
var _insight_highlights: Array[MeshInstance3D] = []
var _insight_item_id: int = -1
var guide_marker: MeshInstance3D
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

	# Flat XZ footprint. No vertical centering and no tall box extending
	# below/above the selected shelf board.
	var lines := ImmediateMesh.new()
	slot_material = StandardMaterial3D.new()
	slot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slot_material.no_depth_test = true
	slot_material.albedo_color = Color(0.2, 0.9, 1.0, 0.95)
	var points := [
		Vector3(-0.49, 0.012, -0.49), Vector3(0.49, 0.012, -0.49),
		Vector3(0.49, 0.012, 0.49), Vector3(-0.49, 0.012, 0.49)
	]
	lines.surface_begin(Mesh.PRIMITIVE_LINES, slot_material)
	for i in range(4):
		lines.surface_add_vertex(points[i])
		lines.surface_add_vertex(points[(i + 1) % 4])
	lines.surface_end()
	slot_marker.mesh = lines

	# In _ready(), the scene root may still be constructing its children.
	# Defer both additions to avoid "Parent node is busy setting up children".
	var root: Node = get_tree().current_scene
	root.add_child.call_deferred(ghost)
	root.add_child.call_deferred(slot_marker)
	# Existing designed bottle placements are scene-editor examples, not game progress.
	# A starting batch of six equal bottles permits a complete row immediately.
	for i in range(mini(starting_bottles, inventory_capacity)):
		if POTIONS.get_item_list().has(starting_item_id):
			inventory.append(starting_item_id)
	for node in get_tree().get_nodes_in_group("shelf_storage"):
		var shelf: ShelfStorage = node as ShelfStorage
		if shelf != null:
			shelf.group_completed.connect(_on_group_completed.bind(shelf))
	skill_book.connect("skill_upgraded", Callable(self, "_on_skill_upgraded"))
	for id in ["Sort", "ShelfGuide", "Insight", "AutoStore", "Summon", "Dash", "Jump", "Capacity2", "Capacity3"]:
		skill_levels[id] = 0
		skill_cooldowns[id] = 0.0
		skill_active_times[id] = 0.0

	guide_marker = MeshInstance3D.new()
	guide_marker.name = "ShelfGuideMarker"
	var guide_mesh := BoxMesh.new()
	guide_mesh.size = Vector3(0.19, 0.014, 0.19)
	guide_marker.mesh = guide_mesh
	var guide_mat := StandardMaterial3D.new()
	guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	guide_mat.no_depth_test = true
	guide_mat.albedo_color = Color(1.0, 0.81, 0.18, 0.78)
	guide_mat.emission_enabled = true
	guide_mat.emission = Color(1.0, 0.8, 0.2)
	guide_marker.material_override = guide_mat
	guide_marker.visible = false
	guide_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child.call_deferred(guide_marker)

	_refresh_inventory_text()
	_refresh_placement_progress()
	_update_skill_hotbar()


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
			if event.keycode >= KEY_1 and event.keycode <= KEY_5:
				var skill_index: int = event.keycode - KEY_1
				_use_skill(["Sort", "ShelfGuide", "Insight", "AutoStore", "Summon"][skill_index])
				return
			if event.keycode >= KEY_F1 and event.keycode <= KEY_F8:
				var slot: int = event.keycode - KEY_F1
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
		velocity.y = jump_speed * (1.0 + 0.15 * float(_skill_level("Jump")))

	var move_axis := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(move_axis.x, 0, move_axis.y)).normalized()
	var speed: float = walk_speed
	if _skill_level("Dash") > 0 and Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_speed_multiplier + 0.15 * float(_skill_level("Dash") - 1)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	# Refresh the ray AFTER the player moves. All physics queries are in
	# _physics_process, so they work with threaded physics as well.
	ray.force_raycast_update()
	_refresh_target()
	_refresh_slot_marker()
	_refresh_ghost()
	_refresh_hint()
	_tick_skills(delta)


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
	elif ray.is_colliding() and _find_shelf_root(ray.get_collider() as Node) != null:
		# Do not throw into a shelf when its selected cell is out of range.
		target = {"kind": "shelf_miss"}


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
		var shelf: ShelfStorage = target["shelf"] as ShelfStorage
		if shelf == null or not shelf.store_bottle(cell, item_id):
			return
		bottles_shelved += 1
		_refresh_placement_progress()
	elif kind == "shelf_miss":
		return
	else:
		_throw_bottle(item_id)

	inventory.remove_at(selected_index)
	if inventory.is_empty():
		selected_index = 0
	else:
		selected_index = mini(selected_index, inventory.size() - 1)
	_refresh_inventory_text()



func _refresh_placement_progress() -> void:
	progress_hud.call("set_progress", completed_groups, 12, bottles_shelved, total_potion_goal)
	progress_hud.call("set_upgrade_message", "再完成1组（6瓶）即可升级")


func _on_group_completed(_origin: Vector3i, _item_id: int, _shelf: ShelfStorage) -> void:
	completed_groups += 1
	_refresh_placement_progress()
	var minor_point: int = 1 if completed_groups % 2 == 0 else 0
	skill_book.call("open_level_up", 1, minor_point)


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
	lines.append("Wheel / F1-F8  select | 1-5 skills")
	inventory_text.text = "\n".join(lines)
	# The visible HUD2 counter reflects the actual inventory, not preview numbers.
	carry_hud.call("set_carry_state", inventory.size(), inventory_capacity)
	progress_hud.call("set_current_book", ("药剂：" + _potion_name(inventory[selected_index])) if not inventory.is_empty() else "")


func _refresh_hint() -> void:
	var kind: String = target.get("kind", "")
	if kind == "loose":
		var bottle: BottleItem = target["bottle"] as BottleItem
		if is_instance_valid(bottle):
			if inventory.size() < inventory_capacity:
				interaction_hint.call("show_action", "E", "拾取药瓶")
			else:
				interaction_hint.call("show_notice", "背包已满")
			return

	if kind == "shelf":
		var grid: GridMap = target["grid"]
		var cell: Vector3i = target["cell"]
		var occupied: bool = grid.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM
		if occupied:
			if inventory.size() < inventory_capacity:
				interaction_hint.call("show_action", "E", "从货架取回药瓶")
			else:
				interaction_hint.call("show_notice", "背包已满")
		elif not inventory.is_empty():
			var shelf: ShelfStorage = target["shelf"] as ShelfStorage
			if shelf != null and shelf.can_store(cell, inventory[selected_index]):
				interaction_hint.call("show_action", "左键", "将药瓶放入货架")
			else:
				interaction_hint.call("show_notice", "本排应放同款药瓶")
		else:
			interaction_hint.call("show_notice", "货架空位")
		return

	if kind == "shelf_miss":
		interaction_hint.call("show_notice", "请对准货架位置")
	elif not inventory.is_empty():
		interaction_hint.call("show_action", "左键", "投掷药瓶")
	else:
		interaction_hint.call("hide_prompt")

func _skill_level(id: String) -> int:
	return int(skill_levels.get(id, 0))


func _cooldown_length(id: String) -> float:
	var base: float = {
		"Sort": 30.0, "ShelfGuide": 60.0, "Insight": 60.0,
		"AutoStore": 100.0, "Summon": 120.0
	}.get(id, 0.0)
	return base / (1.0 + 0.20 * float(maxi(0, _skill_level(id) - 1)))


func _on_skill_upgraded(id: StringName, level: int) -> void:
	skill_levels[str(id)] = level
	match str(id):
		"Capacity2":
			inventory_capacity += 2
			_refresh_inventory_text()
		"Capacity3":
			inventory_capacity += 3
			_refresh_inventory_text()
	_update_skill_hotbar()


func _use_skill(id: String) -> void:
	if _skill_level(id) <= 0 or float(skill_cooldowns.get(id, 0.0)) > 0.0:
		return
	var used: bool = false
	match id:
		"Sort":
			if inventory.size() >= 2:
				inventory.sort()
				selected_index = 0
				_refresh_inventory_text()
				used = true
		"ShelfGuide":
			if not inventory.is_empty():
				skill_active_times[id] = 15.0
				_update_guide_marker()
				used = true
		"Insight":
			if not inventory.is_empty():
				_insight_item_id = inventory[selected_index]
				skill_active_times[id] = 15.0
				_show_insight_highlights()
				used = true
		"AutoStore":
			if not inventory.is_empty():
				skill_active_times[id] = 10.0
				_auto_store_tick = 0.0
				used = true
		"Summon":
			used = _summon_matching_bottle()
	if used:
		skill_cooldowns[id] = _cooldown_length(id)
		_update_skill_hotbar()


func _tick_skills(delta: float) -> void:
	for key in skill_cooldowns.keys():
		skill_cooldowns[key] = maxf(0.0, float(skill_cooldowns[key]) - delta)
	for key in skill_active_times.keys():
		var before: float = float(skill_active_times[key])
		if before > 0.0:
			skill_active_times[key] = maxf(0.0, before - delta)
			if before > 0.0 and float(skill_active_times[key]) == 0.0 and key == "Insight":
				_clear_insight_highlights()
	if float(skill_active_times.get("AutoStore", 0.0)) > 0.0:
		_auto_store_tick -= delta
		if _auto_store_tick <= 0.0:
			_auto_store_tick = 0.3
			_auto_store_one()
	if float(skill_active_times.get("ShelfGuide", 0.0)) > 0.0:
		_update_guide_marker()
	elif is_instance_valid(guide_marker):
		guide_marker.visible = false
	_skill_ui_tick -= delta
	if _skill_ui_tick <= 0.0:
		_skill_ui_tick = 0.15
		_update_skill_hotbar()


func _update_skill_hotbar() -> void:
	for id in ["Dash", "Jump", "ShelfGuide", "Insight", "AutoStore", "Summon"]:
		var unlocked: bool = _skill_level(id) > 0 or id == "Jump"
		var active: bool = float(skill_active_times.get(id, 0.0)) > 0.0
		if id == "Dash":
			active = unlocked and Input.is_key_pressed(KEY_SHIFT)
		skill_hotbar.call(
			"set_skill_state", StringName(id), unlocked,
			float(skill_cooldowns.get(id, 0.0)), maxf(0.001, _cooldown_length(id)), active
		)


func _auto_store_one() -> void:
	if inventory.is_empty() or target.get("kind", "") != "shelf":
		return
	var shelf: ShelfStorage = target["shelf"] as ShelfStorage
	if shelf == null:
		return
	var aimed_cell: Vector3i = target["cell"]
	# Act only on the group that is currently under the crosshair.
	for index in range(inventory.size()):
		var item_id: int = inventory[index]
		var destination: Vector3i = shelf.find_slot_in_group(item_id, aimed_cell)
		if shelf.contains_cell(destination) and shelf.store_bottle(destination, item_id):
			inventory.remove_at(index)
			selected_index = mini(selected_index, maxi(0, inventory.size() - 1))
			bottles_shelved += 1
			_refresh_inventory_text()
			_refresh_placement_progress()
			return


func _summon_matching_bottle() -> bool:
	if inventory.is_empty() or inventory.size() >= inventory_capacity:
		return false
	var item_id: int = inventory[selected_index]
	var found: BottleItem = null
	var nearest: float = 10.0
	for child in loose_items.get_children():
		var bottle: BottleItem = child as BottleItem
		if bottle == null or bottle.is_queued_for_deletion() or bottle.item_id != item_id:
			continue
		var distance: float = global_position.distance_to(bottle.global_position)
		if distance < nearest:
			nearest = distance
			found = bottle
	if found == null:
		return false
	inventory.append(found.item_id)
	selected_index = inventory.size() - 1
	found.collision_layer = 0
	found.queue_free()
	_refresh_inventory_text()
	return true


func _update_guide_marker() -> void:
	if not is_instance_valid(guide_marker) or not guide_marker.is_inside_tree():
		return
	guide_marker.visible = false
	if inventory.is_empty():
		return
	var item_id: int = inventory[selected_index]
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("shelf_storage"):
		var shelf: ShelfStorage = node as ShelfStorage
		if shelf == null:
			continue
		var cell: Vector3i = shelf.find_suitable_slot(item_id)
		if not shelf.contains_cell(cell):
			continue
		var position_world: Vector3 = shelf.grid_map.to_global(shelf.grid_map.map_to_local(cell))
		var distance: float = global_position.distance_squared_to(position_world)
		if distance < best_distance:
			best_distance = distance
			guide_marker.global_transform = Transform3D(shelf.grid_map.global_transform.basis, position_world + Vector3.UP * 0.012)
			guide_marker.visible = true


func _show_insight_highlights() -> void:
	_clear_insight_highlights()
	for child in loose_items.get_children():
		var bottle: BottleItem = child as BottleItem
		if bottle == null or bottle.item_id != _insight_item_id or bottle.is_queued_for_deletion():
			continue
		var source: BoxShape3D = bottle.collision_shape.shape as BoxShape3D
		if source == null:
			continue
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = source.size * 1.06
		marker.mesh = mesh
		marker.position = bottle.collision_shape.position
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.albedo_color = Color(0.32, 0.95, 1.0, 0.23)
		material.emission_enabled = true
		material.emission = Color(0.2, 0.8, 1.0)
		marker.material_override = material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bottle.add_child(marker)
		_insight_highlights.append(marker)


func _clear_insight_highlights() -> void:
	for marker in _insight_highlights:
		if is_instance_valid(marker) and not marker.is_queued_for_deletion():
			marker.queue_free()
	_insight_highlights.clear()


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
		var shelf: ShelfStorage = target["shelf"] as ShelfStorage
		var can_place: bool = shelf != null and shelf.can_store(cell, inventory[selected_index])
		slot_material.albedo_color = (
			Color(0.2, 1.0, 0.45, 0.95)
			if can_place else Color(1.0, 0.3, 0.3, 0.95)
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
	var shelf: ShelfStorage = target["shelf"] as ShelfStorage
	var can_place: bool = shelf != null and shelf.can_store(cell, item_id)

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
