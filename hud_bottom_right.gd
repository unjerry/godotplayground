extends Control
## Preview: count of books currently carried by the player.
## Connect to the actual inventory system later.

@export_range(0, 9999, 1) var carried_count: int = 10
@export_range(0, 9999, 1) var carry_capacity: int = 15

@onready var count_label: Label = $CarryCount


func _ready() -> void:
    refresh()


func refresh() -> void:
    count_label.text = "%d/%d" % [carried_count, carry_capacity]


func set_carried_count(count: int) -> void:
    carried_count = maxi(count, 0)
    if is_node_ready():
        refresh()


func set_carry_capacity(capacity: int) -> void:
    carry_capacity = maxi(capacity, 0)
    if is_node_ready():
        refresh()


func set_carry_state(count: int, capacity: int) -> void:
    carried_count = maxi(count, 0)
    carry_capacity = maxi(capacity, 0)
    if is_node_ready():
        refresh()
