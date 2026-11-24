extends Control
## Display-only skill hotbar for potion sorting. Gameplay actions are separate.

const SKILL_IDS: Array[StringName] = [
    &"Dash", &"Jump", &"ShelfGuide", &"Insight", &"AutoStore", &"Summon"
]

@export var preview_all_unlocked: bool = true

var _states: Dictionary = {}


func _ready() -> void:
    for skill_id in SKILL_IDS:
        if not _states.has(skill_id):
            _states[skill_id] = {
                "unlocked": preview_all_unlocked,
                "cooldown_remaining": 0.0,
                "cooldown_total": 1.0,
                "active": false
            }
        _refresh_slot(skill_id)


func set_skill_state(
    skill_id: StringName,
    unlocked: bool,
    cooldown_remaining: float = 0.0,
    cooldown_total: float = 1.0,
    active: bool = false
) -> void:
    if not SKILL_IDS.has(skill_id):
        push_warning("Unknown skill HUD slot: " + str(skill_id))
        return
    _states[skill_id] = {
        "unlocked": unlocked,
        "cooldown_remaining": maxf(0.0, cooldown_remaining),
        "cooldown_total": maxf(0.001, cooldown_total),
        "active": active
    }
    if is_node_ready():
        _refresh_slot(skill_id)


func _refresh_slot(skill_id: StringName) -> void:
    var state: Dictionary = _states[skill_id]
    var slot: Control = get_node(NodePath(str(skill_id))) as Control
    var frame: Panel = slot.get_node("Frame") as Panel
    var overlay: ColorRect = slot.get_node("Frame/CooldownMask") as ColorRect
    var seconds: Label = slot.get_node("Frame/CooldownText") as Label

    var unlocked: bool = state["unlocked"]
    var remaining: float = state["cooldown_remaining"]
    var total: float = state["cooldown_total"]
    var active: bool = state["active"]

    slot.modulate = Color.WHITE if unlocked else Color(0.45, 0.42, 0.39, 0.8)
    frame.self_modulate = Color(0.74, 1.0, 0.87, 1.0) if active and unlocked else Color.WHITE
    overlay.visible = unlocked and remaining > 0.0
    seconds.visible = overlay.visible

    if overlay.visible:
        var fraction: float = clampf(remaining / total, 0.0, 1.0)
        overlay.position.y = 38.0 * (1.0 - fraction)
        overlay.size.y = 38.0 * fraction
        seconds.text = str(ceili(remaining))
