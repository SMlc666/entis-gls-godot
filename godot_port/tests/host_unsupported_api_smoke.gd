extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	var host := CsxHostClass.new("")
	var redraw: Dictionary = host.call_host_function("UpdateWindow", [], null)
	if not redraw.get("handled", false) or int(redraw.get("result", -1)) != 0:
		_fail("UpdateWindow must remain a supported deferred-redraw request")
		return
	var input_pump: Dictionary = host.call_host_function("ProcessUserInput", [], null)
	if input_pump.get("handled", false):
		_fail("ProcessUserInput must not claim success without an input-pump implementation")
		return
	print("PASS host unsupported API contract")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
