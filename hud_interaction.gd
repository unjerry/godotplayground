extends Control
## A lightweight contextual prompt. Gameplay calls show_action/show_notice/hide_prompt.

@onready var leading_text: Label = $Center/PromptPanel/Content/Lead
@onready var key_frame: PanelContainer = $Center/PromptPanel/Content/KeyFrame
@onready var key_text: Label = $Center/PromptPanel/Content/KeyFrame/Key
@onready var action_text: Label = $Center/PromptPanel/Content/Action

var _last_mode: String = ""
var _last_key: String = ""
var _last_text: String = ""


func show_action(key: String, action: String) -> void:
    if _last_mode == "action" and _last_key == key and _last_text == action:
        return
    _last_mode = "action"
    _last_key = key
    _last_text = action
    leading_text.visible = true
    key_frame.visible = true
    key_text.text = key
    action_text.text = action
    visible = true


func show_notice(message: String) -> void:
    if _last_mode == "notice" and _last_text == message:
        return
    _last_mode = "notice"
    _last_key = ""
    _last_text = message
    leading_text.visible = false
    key_frame.visible = false
    action_text.text = message
    visible = true


func hide_prompt() -> void:
    if _last_mode == "hidden":
        return
    _last_mode = "hidden"
    visible = false
