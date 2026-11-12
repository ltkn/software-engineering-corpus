extends "res://tests/test_case.gd"

const DT := 1.0 / 60.0


## Run frames of [on_floor, pressed]; return the frame indexes where a jump started.
func run(frames: Array) -> Array[int]:
	var logic := JumpLogic.new()
	var jumps: Array[int] = []
	for i in frames.size():
		if logic.update(DT, frames[i][0], frames[i][1]):
			jumps.append(i)
	return jumps


func repeat(frame: Array, n: int) -> Array:
	var out := []
	for i in n:
		out.append(frame)
	return out


func test_plain_jump() -> bool:
	check_eq(run([[true, false], [true, true], [false, false]]), [1] as Array[int], "jump on press")
	return true


func test_buffered_press_jumps_on_landing() -> bool:
	# Press 5 frames (~83 ms) before landing.
	var frames := [[false, true]] + repeat([false, false], 4) + [[true, false], [true, false]]
	check_eq(run(frames), [5] as Array[int], "jumps on the landing frame")
	return true


func test_press_too_early_is_forgotten() -> bool:
	# Press 12 frames (200 ms) before landing: longer than the buffer.
	var frames := [[false, true]] + repeat([false, false], 11) + [[true, false], [true, false]]
	check_eq(run(frames), [] as Array[int], "no jump")
	return true


func test_coyote_jump_after_leaving_a_ledge() -> bool:
	# Walk off the ledge, press 4 frames (~67 ms) later.
	var frames := [[true, false], [true, false]] + repeat([false, false], 3) + [[false, true]]
	check_eq(run(frames), [5] as Array[int], "coyote jump")
	return true


func test_coyote_time_runs_out() -> bool:
	var frames := [[true, false]] + repeat([false, false], 9) + [[false, true]]
	check_eq(run(frames), [] as Array[int], "too late")
	return true


func test_no_double_jump_from_coyote_time() -> bool:
	var frames := [[true, true], [false, false], [false, true], [false, false]]
	check_eq(run(frames), [0] as Array[int], "one jump only")
	return true


func test_one_press_gives_one_jump() -> bool:
	# A buffered press that already caused a jump must not fire again on the next landing.
	var frames := [[false, true], [true, false], [false, false], [false, false], [true, false]]
	check_eq(run(frames), [1] as Array[int], "single jump")
	return true


func test_variable_jump_height() -> bool:
	var logic := JumpLogic.new()
	check_eq(logic.cut_velocity(-400.0, true), -200.0, "rising and released: cut")
	check_eq(logic.cut_velocity(-400.0, false), -400.0, "still held: unchanged")
	check_eq(logic.cut_velocity(150.0, true), 150.0, "falling: unchanged")
	return true
