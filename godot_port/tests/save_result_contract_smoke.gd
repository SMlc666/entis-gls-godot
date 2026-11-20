extends "res://tests/smoke_test_base.gd"

const AdvPlayerScript = preload("res://scripts/adv_player.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMClass = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_save_dir := TestSupport.new_save_dir("save_result_contract")
	var absolute_dir := ProjectSettings.globalize_path(test_save_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK:
		printerr("FAIL Unable to create isolated save result fixture directory: %s" % error_string(mkdir_error))
		quit(1)
		return

	# Keep the player off-tree: this exercises its success contract without
	# starting the game or initializing any user save state.
	var player = AdvPlayerScript.new()
	var success_cases: Array[Dictionary] = [
		{"response": {"ok": true, "result": 0}, "expected": true, "label": "integer zero"},
		{"response": {"ok": true, "result": 0.0}, "expected": true, "label": "float zero"},
		{"response": {"ok": true, "result": true}, "expected": true, "label": "boolean true"},
	]
	for test_case: Dictionary in success_cases:
		expect(
			player._is_csx_operation_success(test_case["response"]) == test_case["expected"],
			"CSX save/load success contract should accept %s" % test_case["label"]
		)

	var failure_cases: Array[Dictionary] = [
		{"response": {"ok": true, "result": 1}, "label": "integer failure status"},
		{"response": {"ok": true, "result": -1}, "label": "negative failure status"},
		{"response": {"ok": true, "result": 0.5}, "label": "nonzero float status"},
		{"response": {"ok": true, "result": false}, "label": "boolean false"},
		{"response": {"ok": false, "result": 0}, "label": "VM execution failure"},
		{"response": {"ok": true}, "label": "missing business result"},
		{"response": {"ok": true, "result": "0"}, "label": "string status"},
	]
	for test_case: Dictionary in failure_cases:
		expect(
			not player._is_csx_operation_success(test_case["response"]),
			"CSX save/load success contract must reject %s" % test_case["label"]
		)

	var host = CsxHostClass.new("")
	host.save_dir = test_save_dir
	var vm = CsxVMClass.new(host)
	player.host = host
	var source = CsxVMClass.CsxInstance.new("SaveResultFixture")
	var save_response: Dictionary = host.call_host_function("SaveObject", ["normal_result.json", source], vm)
	expect(save_response.get("handled", false), "SaveObject must report that the host handled the request")
	expect(save_response.get("result", -1) is int and save_response.get("result", -1) == 0, "Successful SaveObject business result must be integer zero")
	expect(player._is_csx_operation_success(_as_vm_result(save_response)), "Successful SaveObject business result must count as success")
	expect(
		player._is_valid_save_document(host.get_save_path("normal_result.json")),
		"A successful SaveObject must leave a valid snapshot document"
	)

	var restored = CsxVMClass.CsxInstance.new("SaveResultFixture")
	var load_response: Dictionary = host.call_host_function("LoadObject", ["normal_result.json", restored], vm)
	expect(load_response.get("handled", false), "LoadObject must report that the host handled the request")
	expect(load_response.get("result", -1) is int and load_response.get("result", -1) == 0, "Successful LoadObject business result must be integer zero")
	expect(player._is_csx_operation_success(_as_vm_result(load_response)), "Successful LoadObject business result must count as success")

	var failed_save: Dictionary = host.call_host_function("SaveObject", ["missing-argument"], vm)
	expect(
		failed_save.get("handled", false) and failed_save.get("result", 0) == 1,
		"Failed SaveObject must return a nonzero business result"
	)
	expect(
		not player._is_csx_operation_success(_as_vm_result(failed_save)),
		"A normally completed VM call with failed SaveObject result must not count as success"
	)
	var missing_target = CsxVMClass.CsxInstance.new("SaveResultFixture")
	var failed_load: Dictionary = host.call_host_function("LoadObject", ["missing.json", missing_target], vm)
	expect(
		failed_load.get("handled", false) and failed_load.get("result", 0) == 1,
		"Missing save must return a nonzero LoadObject business result"
	)
	expect(
		not player._is_csx_operation_success(_as_vm_result(failed_load)),
		"A normally completed VM call with failed LoadObject result must not count as success"
	)
	expect(
		not player._is_valid_save_document(host.get_save_path("missing.json")),
		"Missing save document must not pass save/load validation"
	)

	var broken_path := host.get_save_path("broken.json")
	var broken_file := FileAccess.open(broken_path, FileAccess.WRITE)
	expect(broken_file != null, "Non-object JSON fixture must be writable inside the isolated test directory")
	if broken_file != null:
		broken_file.store_string("[]")
		broken_file.close()
	expect(not player._is_valid_save_document(broken_path), "JSON that is not an object must not count as a valid save document")

	TestSupport.remove_test_saves(test_save_dir)
	player.free()
	finish_success("PASS Save/load business-result and document-validation contract smoke test")


func _as_vm_result(host_result: Dictionary) -> Dictionary:
	return {
		"ok": host_result.get("handled", false),
		"result": host_result.get("result"),
	}
