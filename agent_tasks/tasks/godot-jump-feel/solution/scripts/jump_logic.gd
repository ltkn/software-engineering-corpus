class_name JumpLogic
extends RefCounted

@export var coyote_time := 0.1
@export var buffer_time := 0.12
## Fraction of upward velocity kept when jump is released early.
@export var cut_factor := 0.5

## Time since the player was last on the floor (INF while a jump has used it up).
var _since_floor := INF
## Time since jump was pressed (INF when there is no pending press).
var _since_press := INF


## Call once per physics frame. Returns true when a jump should start this frame.
func update(delta: float, on_floor: bool, jump_just_pressed: bool) -> bool:
	_since_floor = 0.0 if on_floor else _since_floor + delta
	_since_press = 0.0 if jump_just_pressed else _since_press + delta
	var can_jump := _since_floor <= coyote_time
	var wants_jump := _since_press <= buffer_time
	if can_jump and wants_jump:
		# Consume both: one press gives one jump, and no second jump from coyote time.
		_since_floor = INF
		_since_press = INF
		return true
	return false


## Upward velocity is negative in Godot 2D.
func cut_velocity(velocity_y: float, jump_released: bool) -> float:
	if jump_released and velocity_y < 0.0:
		return velocity_y * cut_factor
	return velocity_y
