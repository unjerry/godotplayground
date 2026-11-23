class_name BottleItem
extends RigidBody3D

# One item_id works in the world, the inventory, and a shelf GridMap cell.
const POTIONS = preload("res://new_mesh_library.tres")

@export_range(0, 255, 1) var item_id: int = 2

@onready var preview_model: Node3D = $Visual
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	mass = 0.2
	if not POTIONS.has_item(item_id):
		push_warning("Unknown potion item ID: %d" % item_id)
		return
	var item_mesh: Mesh = POTIONS.get_item_mesh(item_id)
	if item_mesh == null:
		return

	# The original purple GLB remains in the editor as a modeling preview.
	# At runtime the actual item mesh is chosen from the shared library.
	preview_model.visible = false
	var visual := MeshInstance3D.new()
	visual.name = "RuntimeVisual"
	add_child(visual)
	visual.mesh = item_mesh
	visual.transform = POTIONS.get_item_mesh_transform(item_id)

	# Meshes are bottom-origin (Y=0); center the collision box on the model.
	var aabb: AABB = item_mesh.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(aabb.size.x * 0.95, 0.04),
		maxf(aabb.size.y * 0.95, 0.04),
		maxf(aabb.size.z * 0.95, 0.04)
	)
	collision_shape.shape = shape
	collision_shape.position = visual.transform * aabb.get_center()
