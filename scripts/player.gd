class_name VoxelPlayer
extends CharacterBody3D

@export var move_speed: float = 20.0
@export var gravity: float = 40.0
@export var jump_velocity: float = 16.0

var terrain_ready: bool = false

func _physics_process(delta: float) -> void:
	# Hold position until terrain has loaded beneath us
	if not terrain_ready:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()
