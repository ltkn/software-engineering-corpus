class_name JumpLogic
extends RefCounted

@export var coyote_time := 0.1
@export var buffer_time := 0.12
## Fraction of upward velocity kept when jump is released early.
@export var cut_factor := 0.5


## Call once per physics frame. Returns true when a jump should start this frame.
func update(delta: float, on_floor: bool, jump_just_pressed: bool) -> bool:
	return on_floor and jump_just_pressed


## Upward velocity is negative in Godot 2D.
func cut_velocity(velocity_y: float, jump_released: bool) -> float:
	return velocity_y
