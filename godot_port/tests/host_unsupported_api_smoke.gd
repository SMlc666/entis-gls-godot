extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const VmClass = preload("res://scripts/csx_vm.gd")


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

	var unsupported_receivers: Array[Dictionary] = [
		{"receiver": CsxHostClass.HostInputFilter.new(host), "capability": "HostInputFilter"},
		{"receiver": CsxHostClass.HostResource.new("", "", -1, 0, 0, host), "capability": "HostResource"},
		{"receiver": CsxHostClass.HostToneFilter.new(host), "capability": "HostToneFilter"},
		{"receiver": CsxHostClass.HostResourceManager.new(host), "capability": "HostResourceManager"},
		{"receiver": CsxHostClass.HostFile.new(host), "capability": "HostFile"},
		{"receiver": CsxHostClass.HostSprite.new(0, host), "capability": "HostSprite"},
		{"receiver": CsxHostClass.HostWindow.new(host), "capability": "HostWindow"},
		{"receiver": VmClass.CsxInstance.new("InputFilter"), "capability": "HostInputFilter"},
		{"receiver": VmClass.CsxInstance.new("Resource"), "capability": "HostResource"},
		{"receiver": VmClass.CsxInstance.new("ToneFilter"), "capability": "HostToneFilter"},
		{"receiver": VmClass.CsxInstance.new("File"), "capability": "HostFile"},
	]
	for test_case in unsupported_receivers:
		if not _check_unsupported_member(host, test_case["receiver"], test_case["capability"]):
			return
	if not _check_supported_member(host):
		return
	if not _check_unsupported_global(host):
		return
	if not _check_pointer_buffer_error_status(host):
		return

	print("PASS host unsupported API contract")
	quit(0)


func _check_unsupported_member(host: Variant, receiver: Variant, capability: String) -> bool:
	var vm = VmClass.new(host)
	vm.image = _call_instruction(2, 1, "MissingHostMethod")
	vm.eval_stack = [receiver]
	if vm.step():
		_fail("%s.MissingHostMethod must fail its VM instruction" % capability)
		vm.shutdown_runtime()
		return false
	var expected_capability := "%s.MissingHostMethod" % capability
	if not vm.last_error.contains("当前未实现宿主能力") or not vm.last_error.contains(expected_capability):
		_fail("unsupported %s member call must expose its capability in the VM error: %s" % [capability, vm.last_error])
		vm.shutdown_runtime()
		return false
	if not host.last_error.contains(expected_capability) or not vm.eval_stack.is_empty():
		_fail("unsupported %s member call must not append a fabricated result" % capability)
		vm.shutdown_runtime()
		return false
	vm.shutdown_runtime()
	return true


func _check_supported_member(host: Variant) -> bool:
	var vm = VmClass.new(host)
	var sprite = CsxHostClass.HostSprite.new(0, host)
	vm.image = _call_instruction(2, 1, "GetBlendDegree")
	vm.eval_stack = [sprite]
	if not vm.step() or not vm.last_error.is_empty() or vm.eval_stack != [0]:
		_fail("a supported HostSprite method must retain its successful result contract")
		vm.shutdown_runtime()
		return false
	vm.shutdown_runtime()
	return true


func _check_unsupported_global(host: Variant) -> bool:
	var vm = VmClass.new(host)
	vm.image = _call_instruction(3, 0, "ProcessUserInput")
	if vm.step() or not vm.last_error.contains("未实现的全局函数: ProcessUserInput"):
		_fail("an unhandled global host API must fail rather than return a success value")
		vm.shutdown_runtime()
		return false
	if not vm.eval_stack.is_empty():
		_fail("an unhandled global host API must not append a fabricated result")
		vm.shutdown_runtime()
		return false
	vm.shutdown_runtime()
	return true


func _check_pointer_buffer_error_status(host: Variant) -> bool:
	var vm = VmClass.new(host)
	var resource = CsxHostClass.HostResource.new("", "", -1, 0, 0, host)
	vm.image = _call_instruction(2, 2, "GetPixelRect")
	vm.eval_stack = [resource, 123]
	if not vm.step() or vm.last_error != "" or vm.eval_stack != [-1]:
		_fail("unsupported pointer-buffer form must retain its explicit API error status")
		vm.shutdown_runtime()
		return false
	if not host.last_error.contains("HostResource.GetPixelRect Pointer buffer"):
		_fail("unsupported pointer-buffer form must report its capability")
		vm.shutdown_runtime()
		return false
	vm.shutdown_runtime()
	return true


func _call_instruction(mode: int, argc: int, function_name: String) -> PackedByteArray:
	var image := PackedByteArray([8, mode])
	_append_s32(image, argc)
	_append_string(image, function_name)
	return image


func _append_string(bytes: PackedByteArray, value: String) -> void:
	var utf16 := value.to_utf16_buffer()
	_append_s32(bytes, utf16.size() >> 1)
	bytes.append_array(utf16)


func _append_s32(bytes: PackedByteArray, value: int) -> void:
	var offset := bytes.size()
	bytes.resize(offset + 4)
	bytes.encode_s32(offset, value)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
