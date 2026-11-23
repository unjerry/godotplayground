
extends Camera3D

@export var speed: float = 5.0
@export var sprint_multiplier: float = 4.0
@export var sensitivity: float = 0.002


func _ready() -> void:
	current = true


func _unhandled_input(event: InputEvent) -> void:
	# 按住鼠标右键，进入自由观察
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 鼠标控制相机旋转
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotation.y -= event.relative.x * sensitivity
			rotation.x -= event.relative.y * sensitivity
			rotation.x = clampf(
				rotation.x, -PI / 2.0 + 0.01, PI / 2.0 - 0.01
			)

	# ESC 释放鼠标
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	var basis_3d := global_transform.basis

	if Input.is_physical_key_pressed(KEY_W):
		direction -= basis_3d.z
	if Input.is_physical_key_pressed(KEY_S):
		direction += basis_3d.z
	if Input.is_physical_key_pressed(KEY_A):
		direction -= basis_3d.x
	if Input.is_physical_key_pressed(KEY_D):
		direction += basis_3d.x
	if Input.is_physical_key_pressed(KEY_E):
		direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		direction += Vector3.DOWN

	var move_speed := speed

	if Input.is_key_pressed(KEY_SHIFT):
		move_speed *= sprint_multiplier
	if Input.is_key_pressed(KEY_ALT):
		move_speed *= 0.25

	if direction.length_squared() > 0.0:
		global_position += direction.normalized() * move_speed * delta
