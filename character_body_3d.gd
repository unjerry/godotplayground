
extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# F10：随时退出游戏
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F10:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().quit()
			return

		# Esc：释放鼠标
		if event.pressed and event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

	# 左键：重新锁定鼠标
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Minecraft 式鼠标视角
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
			camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
			camera.rotation.x = clampf(
				camera.rotation.x,
				deg_to_rad(-89.0),
				deg_to_rad(89.0)
			)


func _physics_process(delta: float) -> void:
	# Godot 原生角色移动逻辑
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector(
		"ui_left", "ui_right", "ui_up", "ui_down"
	)

	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
