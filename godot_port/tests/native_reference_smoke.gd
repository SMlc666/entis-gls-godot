extends SceneTree

const Host = preload("res://scripts/csx_host.gd")
const VM = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := OS.get_cmdline_user_args()[0]
	var host := Host.new(game_dir)
	var save_dir := TestSupport.new_save_dir("native_reference")
	host.save_dir = save_dir
	var vm := VM.new(host)
	if not vm.load_csx(game_dir.path_join("system/yosuga.csx")).get("ok", false):
		_fail("Cannot load original script")
		return
	vm.execute_prologues()
	if not vm.call_function_sync("Initialize", [], 500000).get("ok", false):
		_fail("Cannot initialize original script")
		return
	var values := {"alias": "悠", "display": "", "true_name": ""}
	var result := vm.call_function_sync("CheckTrueName", [
		VM.CsxRef.new(values, "alias"),
		VM.CsxRef.new(values, "display"),
		VM.CsxRef.new(values, "true_name")
	])
	if not result.get("ok", false) or values["display"] != "悠" or values["true_name"] != "悠":
		_fail("CheckTrueName must write both names through reference arguments: %s" % values)
		return
	TestSupport.remove_test_saves(save_dir)
	print("PASS Original name reference arguments")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
