extends CharacterBody2D

const SPEED := 220.0
const JUMP_VELOCITY := -420.0

var jump := JumpLogic.new()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if jump.update(delta, is_on_floor(), Input.is_action_just_pressed("jump")):
		velocity.y = JUMP_VELOCITY
	velocity.y = jump.cut_velocity(velocity.y, Input.is_action_just_released("jump"))
	velocity.x = Input.get_axis("move_left", "move_right") * SPEED
	move_and_slide()
