extends Control
## Lightweight progress overlay matching the reference game's upper-left HUD.
## These are preview values until the sorting system supplies real progress.

@export var upgrade_hint: String = "再整理1行即可升级"
@export var completed_rows: int = 3
@export var total_rows: int = 400
@export var sorted_books: int = 265
@export var total_books: int = 3072
@export var current_book_title: String = "哲学：权力与伦理 Vol.9"

@onready var upgrade_label: Label = $UpgradeHint
@onready var rows_label: Label = $RowsValue
@onready var books_label: Label = $BooksValue
@onready var current_book_label: Label = $CurrentBook


func _ready() -> void:
    refresh()


func refresh() -> void:
    upgrade_label.text = upgrade_hint
    rows_label.text = "%d / %d" % [completed_rows, total_rows]
    books_label.text = "%d / %d" % [sorted_books, total_books]
    current_book_label.text = "› " + current_book_title
    current_book_label.visible = not current_book_title.is_empty()


func set_progress(rows_done: int, row_goal: int, books_done: int, book_goal: int) -> void:
    completed_rows = rows_done
    total_rows = row_goal
    sorted_books = books_done
    total_books = book_goal
    if is_node_ready():
        refresh()


func set_current_book(title: String) -> void:
    current_book_title = title
    if is_node_ready():
        refresh()


func set_upgrade_message(message: String) -> void:
    upgrade_hint = message
    if is_node_ready():
        refresh()
