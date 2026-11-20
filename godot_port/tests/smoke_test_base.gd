extends SceneTree

var _expectation_failed := false


func expect(condition: bool, message: String = "expectation failed") -> void:
	if condition:
		return
	_expectation_failed = true
	printerr("FAIL: ", message)
	quit(1)


func finish_success(pass_message: String) -> void:
	if _expectation_failed:
		quit(1)
		return
	print(pass_message)
	quit(0)
