extends Node3D

# Prototype pile: deterministic but mixed potion types, with collisions and gravity.
const BOTTLE_SCENE = preload("res://bottle.tscn")
const POTIONS = preload("res://new_mesh_library.tres")

@export_range(0, 60, 1) var bottle_count: int = 20
@export var random_seed: int = 20261123


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var ids: PackedInt32Array = POTIONS.get_item_list()
	if ids.is_empty():
		return

	for i in range(bottle_count):
		var bottle: BottleItem = BOTTLE_SCENE.instantiate() as BottleItem
		bottle.item_id = ids[i % ids.size()]
		add_child(bottle)

		# A few staggered rows fall into an untidy pile on the floor.
		var row: int = floori(float(i) / 5.0)
		var column: int = i % 5
		bottle.position = Vector3(
			(float(column) - 2.0) * 0.22 + rng.randf_range(-0.04, 0.04),
			0.7 + float(row) * 0.42,
			rng.randf_range(-0.3, 0.3)
		)
		bottle.rotation = Vector3(
			rng.randf_range(-0.6, 0.6),
			rng.randf_range(-PI, PI),
			rng.randf_range(-0.6, 0.6)
		)
