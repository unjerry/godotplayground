extends Control
## Context tutorial panel. The current text describes implemented potion controls.
## A future tutorial manager can call set_tutorial() for subsequent lessons.

@export var tutorial_title: String = "药剂整理指南"
@export_multiline var tutorial_text: String = "捡起散落的魔法药瓶，将它们摆进货架空位。\n\nE  拾取 / 取回\n左键  放置 / 投掷\n滚轮  切换药瓶"
@export var show_on_start: bool = true

@onready var title_label: Label = $Title
@onready var body_label: Label = $Body


func _ready() -> void:
    title_label.text = tutorial_title
    body_label.text = tutorial_text
    visible = show_on_start


func set_tutorial(title: String, description: String) -> void:
    tutorial_title = title
    tutorial_text = description
    if is_node_ready():
        title_label.text = tutorial_title
        body_label.text = tutorial_text
        visible = true


func dismiss_tutorial() -> void:
    visible = false


func show_tutorial() -> void:
    visible = true
