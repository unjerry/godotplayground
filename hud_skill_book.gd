extends Control
## Upgrade popup: editable Godot buttons and labels over an original SVG book.
## Hidden while playing, visible in the 2D scene editor for layout adjustments.
## UI skill levels and points are provisional until a persistent skill system exists.

signal skill_upgraded(skill_id: StringName, new_level: int)

const BOOK_SIZE := Vector2(1080.0, 620.0)
const ALL_SKILLS := [
    "Sort", "ShelfGuide", "Insight", "AutoStore", "Summon",
    "Dash", "Jump", "Capacity2", "Capacity3"
]
const SKILL_DATA := {
    "Sort": {"title": "排列", "group": "primary", "description": "按药剂类型自动整理背包中的药瓶，便于寻找和上架。", "cooldown": "30 秒", "duration": "立即生效", "icon": "res://ui/icons/skill_sort.svg"},
    "ShelfGuide": {"title": "货架指引", "group": "primary", "description": "短暂照亮当前选中药瓶对应的药架，帮助你找到正确的收纳位置。", "cooldown": "60 秒", "duration": "15 秒", "icon": "res://ui/icons/skill_guide.svg"},
    "Insight": {"title": "洞察之眼", "group": "primary", "description": "高亮周围同一类的药剂瓶，让散落的药剂更容易被发现。", "cooldown": "待实现", "duration": "待实现", "icon": "res://ui/icons/skill_insight.svg"},
    "AutoStore": {"title": "自动上架", "group": "primary", "description": "激活后，自动将手中匹配的药剂瓶放到准星所指的药架中。\n只对类型匹配且有空位的药架生效。", "cooldown": "100 秒", "duration": "10 秒", "icon": "res://ui/icons/skill_auto_store.svg"},
    "Summon": {"title": "手到擒来", "group": "primary", "description": "以手中选中的药瓶为线索，将附近同系列的药瓶召集到手中。", "cooldown": "120 秒", "duration": "立即生效", "icon": "res://ui/icons/skill_summon.svg"},
    "Dash": {"title": "快速移动", "group": "secondary", "description": "提高在魔法药剂馆中移动的效率。", "cooldown": "无", "duration": "被动效果", "icon": "res://ui/icons/skill_dash.svg"},
    "Jump": {"title": "跳跃强化", "group": "secondary", "description": "提升跳跃能力，帮助你探索更高的货架和楼层。", "cooldown": "无", "duration": "被动效果", "icon": "res://ui/icons/skill_jump.svg"},
    "Capacity2": {"title": "携带容量 +2", "group": "secondary", "description": "增加能够同时携带的药瓶数量。", "cooldown": "无", "duration": "被动效果", "icon": "res://ui/icons/potion_carry.svg"},
    "Capacity3": {"title": "携带容量 +3", "group": "secondary", "description": "进一步增加能够同时携带的药瓶数量。", "cooldown": "无", "duration": "被动效果", "icon": "res://ui/icons/potion_carry.svg"}
}

@export var enable_preview_hotkey: bool = true
@export_range(0, 99, 1) var primary_points: int = 0
@export_range(0, 99, 1) var secondary_points: int = 0

@onready var book: Control = $Book
@onready var primary_status: Label = $Book/PrimaryPoints
@onready var secondary_status: Label = $Book/SecondaryPoints
@onready var detail_title: Label = $Book/DetailTitle
@onready var detail_level: Label = $Book/DetailLevel
@onready var detail_description: Label = $Book/DetailDescription
@onready var detail_cooldown: Label = $Book/DetailCooldown
@onready var detail_duration: Label = $Book/DetailDuration
@onready var detail_icon: TextureRect = $Book/DetailIcon
@onready var upgrade_button: Button = $Book/UpgradeButton

var _levels: Dictionary = {}
var _selected_skill: String = "AutoStore"
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _previous_pause: bool = false


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    book.pivot_offset = BOOK_SIZE / 2.0
    resized.connect(_update_scale)
    for skill_id in ALL_SKILLS:
        _levels[skill_id] = 0
        var button: Button = book.get_node("Skill" + skill_id) as Button
        button.pressed.connect(_select_skill.bind(skill_id))
    upgrade_button.pressed.connect(_upgrade_selected)
    ($Book/CloseButton as Button).pressed.connect(close_book)
    _update_scale()
    _refresh()
    hide()  # Keep the book visible in the editor but hidden at runtime.


func _update_scale() -> void:
    var factor: float = minf(1.0, minf(size.x / 1110.0, size.y / 650.0))
    book.scale = Vector2.ONE * maxf(0.2, factor)


func open_level_up(earned_primary: int = 1, earned_secondary: int = 0) -> void:
    primary_points += maxi(0, earned_primary)
    secondary_points += maxi(0, earned_secondary)
    _refresh()
    open_book()


func open_book() -> void:
    if visible:
        return
    _previous_pause = get_tree().paused
    _previous_mouse_mode = Input.mouse_mode
    show()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    get_tree().paused = true


func close_book() -> void:
    if not visible:
        return
    hide()
    get_tree().paused = _previous_pause
    Input.mouse_mode = _previous_mouse_mode


func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    if event.keycode == KEY_ESCAPE and visible:
        close_book()
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_U and enable_preview_hotkey:
        if visible:
            close_book()
        else:
            # Debug preview only; real level-up calls open_level_up() from gameplay.
            open_level_up(1, 1)
        get_viewport().set_input_as_handled()


func _select_skill(skill_id: String) -> void:
    _selected_skill = skill_id
    _refresh()


func _upgrade_selected() -> void:
    var group: String = SKILL_DATA[_selected_skill]["group"]
    if group == "primary":
        if primary_points < 1:
            return
        primary_points -= 1
    else:
        if secondary_points < 1:
            return
        secondary_points -= 1
    _levels[_selected_skill] = int(_levels[_selected_skill]) + 1
    _refresh()
    skill_upgraded.emit(StringName(_selected_skill), int(_levels[_selected_skill]))


func _refresh() -> void:
    if not is_node_ready():
        return
    primary_status.text = "主要魔法   ↑ %d 点数" % primary_points
    secondary_status.text = "次要魔法   ↑ %d 点数" % secondary_points

    for skill_id in ALL_SKILLS:
        var button: Button = book.get_node("Skill" + skill_id) as Button
        var level_label: Label = book.get_node("Level" + skill_id) as Label
        level_label.text = "Lv.%d" % int(_levels[skill_id])
        button.modulate = Color(1.0, 0.83, 0.50) if skill_id == _selected_skill else Color.WHITE

    var data: Dictionary = SKILL_DATA[_selected_skill]
    detail_title.text = data["title"]
    detail_level.text = "✦  Lv.%d  ✦" % int(_levels[_selected_skill])
    detail_description.text = data["description"]
    detail_cooldown.text = "· 冷却时间：%s" % data["cooldown"]
    detail_duration.text = "· 持续时间：%s" % data["duration"]
    detail_icon.texture = load(data["icon"]) as Texture2D

    var available: int = primary_points if data["group"] == "primary" else secondary_points
    upgrade_button.disabled = available < 1
    upgrade_button.text = "消耗 1 点 · 升级" if available > 0 else "点数不足"
