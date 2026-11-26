extends SceneTree

const VmClass = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	_test_failed_query_restores_execution_and_clears_stale_error(failures)
	_test_timed_out_side_effect_call_keeps_mutation(failures)
	_test_sync_call_restores_return_and_nested_sync_state(failures)
	_test_constructor_failure_and_timeout_never_return_partial_objects(failures)
	_test_create_object_without_constructor_remains_compatible(failures)
	_test_clear_runtime_state_breaks_csx_reference_cycles(failures)
	if failures.is_empty():
		print("PASS synchronous VM failure state smoke test")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL ", failure)
		quit(1)


func _test_failed_query_restores_execution_and_clears_stale_error(failures: Array[String]) -> void:
	var vm = VmClass.new()
	var image := _query_instruction("ready")
	var failing_address := image.size()
	image.append_array(PackedByteArray([13, 3])) # logical-not with an empty eval stack
	vm.image = image
	vm.ip = 0
	vm.is_halted = false
	vm.pending_call_args = ["outer-arg"]
	vm.pending_return_ip = 23
	vm.call_stack.append(VmClass.StackFrame.new("outer", 17))
	vm.eval_stack = ["outer-value"]
	vm.last_return_value = "outer-return"
	vm.is_synchronous_call = true
	var result: Dictionary = vm.call_address_sync(failing_address, [], 8)
	_check(not result.get("ok", true) and str(result.get("error", "")).contains("求值栈不足"),
		"a failed synchronous query must return its VM error", failures)
	_check(not result.get("side_effects_may_have_occurred", true),
		"a zero-step pre-effect failure must report that no VM side effect could have run", failures)
	_check(vm.ip == 0 and not vm.is_halted and vm.pending_call_args == ["outer-arg"]
		and vm.pending_return_ip == 23 and vm.call_stack.size() == 1
		and vm.call_stack[0].name == "outer" and vm.eval_stack == ["outer-value"],
		"a failed synchronous query must restore the suspended VM control state", failures)
	_check(vm.last_error == result.get("error", ""),
		"the failed call must retain its diagnostic until VM execution resumes", failures)
	_check(vm.last_return_value == "outer-return" and vm.is_synchronous_call,
		"a failed nested sync call must restore last return value and synchronous mode", failures)
	_check(vm.step() and vm.eval_stack == ["outer-value", "ready"] and vm.last_error.is_empty(),
		"the next valid query instruction must run after a failed sync call", failures)


func _test_timed_out_side_effect_call_keeps_mutation(failures: Array[String]) -> void:
	var vm = VmClass.new()
	var image := PackedByteArray([4]) # enter Mutate(out)
	_append_string(image, "Mutate")
	_append_s32(image, 1)
	image.append(1) # reference parameter
	_append_string(image, "out")
	image.append_array(PackedByteArray([2, 1, 6])) # load local out
	_append_string(image, "out")
	image.append_array(PackedByteArray([2, 0, 4])) # load integer 42
	_append_s32(image, 42)
	image.append_array(PackedByteArray([3, 255])) # assign through reference
	var loop_address := image.size()
	image.append(6) # jump to itself until the sync budget expires
	_append_s32(image, loop_address - (loop_address + 5))
	var query_address := image.size()
	image.append_array(_query_instruction("resumed"))
	vm.image = image
	vm.ip = query_address
	vm.is_halted = false
	vm.eval_stack = ["outer-value"]
	var external_state := {"value": 0}
	var result: Dictionary = vm.call_address_sync(0,
		[VmClass.CsxRef.new(external_state, "value")], 4)
	_check(not result.get("ok", true) and result.get("timeout", false),
		"a budget-exhausted side-effect call must report a timeout", failures)
	_check(result.get("side_effects_may_have_occurred", false),
		"a timed-out synchronous call must tell callers that earlier side effects were retained", failures)
	_check(external_state.get("value") == 42,
		"a timed-out synchronous call must keep its explicit reference-argument side effect", failures)
	_check(vm.ip == query_address and not vm.is_halted and vm.eval_stack == ["outer-value"],
		"a timed-out synchronous call must restore interpreter control state", failures)
	_check(vm.last_return_value == null and not vm.is_synchronous_call,
		"a timed-out sync call must restore return value and synchronous mode", failures)
	_check(vm.step() and vm.eval_stack == ["outer-value", "resumed"] and vm.last_error.is_empty(),
		"the resumed VM must execute after a timed-out side-effect call", failures)


func _test_sync_call_restores_return_and_nested_sync_state(failures: Array[String]) -> void:
	var vm = VmClass.new()
	var image := PackedByteArray([2, 0, 4])
	_append_s32(image, 73)
	image.append_array(PackedByteArray([9, 0]))
	vm.image = image
	vm.last_return_value = "outer-return"
	vm.is_synchronous_call = true
	var result: Dictionary = vm.call_address_sync(0, [], 8)
	_check(result.get("ok", false) and result.get("result") == 73,
		"a successful synchronous call must return its own result", failures)
	_check(vm.last_return_value == "outer-return" and vm.is_synchronous_call,
		"a successful nested sync call must restore its caller return and sync mode", failures)


func _test_constructor_failure_and_timeout_never_return_partial_objects(failures: Array[String]) -> void:
	var vm = VmClass.new()
	vm.image = PackedByteArray([13, 3]) # logical-not with an empty eval stack
	vm.functions["Broken::Broken"] = 0
	var failed: Variant = vm.create_object("Broken")
	_check(failed is VmClass.CsxObjectCreationError,
		"a throwing constructor must return the explicit creation error contract", failures)
	if failed is VmClass.CsxObjectCreationError:
		_check(not failed.error.is_empty() and not failed.side_effects_may_have_occurred,
			"a zero-step constructor failure must preserve its diagnostic and side-effect status", failures)
	var query_vm = VmClass.new()
	var loop_image := PackedByteArray([6])
	_append_s32(loop_image, -5)
	query_vm.image = loop_image
	query_vm.functions["Slow::Slow"] = 0
	var timed_out: Variant = query_vm.create_object("Slow", 3)
	_check(timed_out is VmClass.CsxObjectCreationError,
		"a timed-out constructor must never return its partially initialized instance", failures)
	if timed_out is VmClass.CsxObjectCreationError:
		_check(timed_out.side_effects_may_have_occurred and timed_out.error.contains("超过步数上限"),
			"a timed-out constructor error must report its timeout and possible side effects", failures)
	var creation_vm = VmClass.new()
	var load_image := PackedByteArray([2, 0, 0])
	_append_string(load_image, "Broken")
	var broken_ctor_address := load_image.size()
	load_image.append_array(PackedByteArray([13, 3]))
	creation_vm.image = load_image
	creation_vm.functions["Broken::Broken"] = broken_ctor_address
	var result: Dictionary = creation_vm.call_address_sync(0, [], 8)
	_check(not result.get("ok", true) and str(result.get("error", "")).contains("创建 Broken 失败"),
		"VM object creation must propagate constructor errors to the creation instruction", failures)


func _test_create_object_without_constructor_remains_compatible(failures: Array[String]) -> void:
	var vm = VmClass.new()
	var value: Variant = vm.create_object("Constructorless")
	_check(value is VmClass.CsxInstance and value.type_name == "Constructorless",
		"classes without a constructor must still instantiate directly", failures)


func _test_clear_runtime_state_breaks_csx_reference_cycles(failures: Array[String]) -> void:
	var vm = VmClass.new()
	var instance = VmClass.CsxInstance.new("Cycle")
	instance.set_field("self", instance)
	var cycle: Array = []
	cycle.append(cycle)
	vm.global_vars.append({"name": "cycle", "value": instance})
	vm.globals_by_name["cycle"] = instance
	vm.data_vars.append({"name": "array", "value": cycle})
	vm.data_by_name["array"] = cycle
	vm.eval_stack = [instance, cycle]
	vm.pending_call_args = [instance]
	var frame = VmClass.StackFrame.new("suspend", 4, instance)
	frame.add_local("keep", cycle)
	vm.call_stack.append(frame)
	vm.last_return_value = instance
	_check(vm.has_method("shutdown_runtime"), "VM must expose the unified shutdown_runtime lifecycle contract", failures)
	vm.shutdown_runtime()
	_check(instance.fields.is_empty() and instance.field_names.is_empty() and cycle.is_empty(),
		"shutdown must sever cyclic CSX instance and container edges", failures)
	_check(vm.global_vars.is_empty() and vm.globals_by_name.is_empty() and vm.data_vars.is_empty()
		and vm.data_by_name.is_empty() and vm.eval_stack.is_empty() and vm.pending_call_args.is_empty()
		and vm.call_stack.is_empty() and vm.last_return_value == null and vm.host == null,
		"shutdown must clear VM roots and detach its host", failures)
	vm.shutdown_runtime()
	vm.clear_runtime_state()
	_check(vm.global_vars.is_empty() and vm.data_by_name.is_empty() and vm.host == null,
		"shutdown_runtime and its compatibility alias must be idempotent", failures)


func _query_instruction(value: String) -> PackedByteArray:
	var bytes := PackedByteArray([2, 0, 6]) # load immediate string
	_append_string(bytes, value)
	return bytes


func _append_string(bytes: PackedByteArray, value: String) -> void:
	var utf16 := value.to_utf16_buffer()
	_append_s32(bytes, utf16.size() / 2)
	bytes.append_array(utf16)


func _append_s32(bytes: PackedByteArray, value: int) -> void:
	var offset := bytes.size()
	bytes.resize(offset + 4)
	bytes.encode_s32(offset, value)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
