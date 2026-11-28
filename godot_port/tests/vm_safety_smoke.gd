extends SceneTree

const VmClass = preload("res://scripts/csx_vm.gd")
const BytecodeClass = preload("res://scripts/csx_bytecode.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var vm = VmClass.new()
	var bytecode = BytecodeClass.new()

	var conststr := PackedByteArray()
	_append_u32(conststr, 1)
	var string_bytes := "Sora".to_utf16_buffer()
	_append_u32(conststr, string_bytes.size() / 2)
	conststr.append_array(string_bytes)
	_append_u32(conststr, 2)
	_append_u32(conststr, 0x10203040)
	_append_u32(conststr, 0x50607080)
	var conststr_result: Dictionary = vm._decode_conststr_section(conststr)
	_check(conststr_result.get("ok", false), "conststr table must parse", failures)
	_check(conststr_result.get("strings", []) == ["Sora"], "conststr text must decode as UTF-16LE", failures)
	if conststr_result.get("ok", false):
		vm.const_strings = conststr_result["strings"]
	var string_ref := PackedByteArray()
	_append_s32(string_ref, -2147483648)
	_append_s32(string_ref, 0)
	vm.image = string_ref
	vm.ip = 0
	_check(vm._read_string() == "Sora" and vm.ip == 8, "image conststr reference must resolve and advance exactly eight bytes", failures)
	var invalid_ref := PackedByteArray()
	_append_s32(invalid_ref, -2147483648)
	_append_s32(invalid_ref, 1)
	vm.image = invalid_ref
	vm.ip = 0
	vm.last_error = ""
	_check(vm._read_string().is_empty() and not vm.last_error.is_empty(), "out-of-range conststr reference must fail explicitly", failures)
	var referenced_image := PackedByteArray([2, 0, 6]) # load immediate string
	_append_s32(referenced_image, -2147483648)
	_append_s32(referenced_image, 0)
	_check(bytecode.validate_image(referenced_image, 1).get("ok", false), "valid image conststr references must be accepted", failures)
	_check(not bytecode.validate_image(referenced_image, 0).get("ok", false), "image conststr references must be checked against the loaded table", failures)
	_check(not vm._decode_conststr_section(PackedByteArray([1, 0, 0, 0, 8, 0, 0, 0])).get("ok", false), "truncated conststr entry must fail", failures)
	_check(not vm._decode_conststr_section(PackedByteArray([0, 0, 0, 0, 1])).get("ok", false), "unrecognized conststr tail must fail", failures)

	vm = VmClass.new()
	vm.image = PackedByteArray([2, 0, 4, 1]) # load integer, truncated payload
	vm.ip = 0
	_check(not vm.step() and not vm.last_error.is_empty(), "truncated immediate must fail without reading past image", failures)

	vm = VmClass.new()
	vm.image = PackedByteArray([13, 0]) # unary with an empty evaluation stack
	vm.ip = 0
	_check(not vm.step() and vm.last_error.contains("求值栈不足"), "unary underflow must produce a VM error", failures)

	var huge_argc := PackedByteArray([8, 3])
	_append_s32(huge_argc, 2147483647)
	_append_s32(huge_argc, 0)
	_check(not bytecode.decode(huge_argc, 0, 1).get("ok", false), "huge call argc must be rejected by bytecode decoder", failures)

	var bad_branch := PackedByteArray([6, 252, 255, 255, 255, 9, 1]) # target points into the jump operand
	_check(not bytecode.validate_image(bad_branch).get("ok", false), "branch into an operand must fail image validation", failures)
	vm = VmClass.new()
	vm.image = bad_branch
	vm.ip = 0
	_check(not vm.step() and vm.last_error.contains("分支目标不是有效指令边界"), "VM must validate the whole image before executing a manually supplied buffer", failures)

	vm = VmClass.new()
	vm.max_call_depth = 1
	vm.call_stack.append(VmClass.StackFrame.new("existing"))
	vm.pending_return_ip = 0
	vm.image = PackedByteArray([4])
	_append_s32(vm.image, 1)
	vm.image.append_array("f".to_utf16_buffer())
	_append_s32(vm.image, 0)
	vm.ip = 0
	_check(not vm.step() and vm.last_error.contains("调用深度超过上限"), "recursive call depth must be capped", failures)

	var bounded_array: Array = []
	var oversized_ref := VmClass.CsxRef.new(bounded_array, 65536)
	_check(not oversized_ref.set_value("blocked") and bounded_array.is_empty(), "array reference must not expand beyond the VM limit", failures)
	vm = VmClass.new()
	var overflowing_ref := VmClass.CsxRef.new(bounded_array, 65536)
	vm._dispatch_int_method(overflowing_ref, 1, "SetBit", [0])
	_check(not vm.last_error.is_empty() and bounded_array.is_empty(), "integer mutators must report refused oversized writes", failures)
	vm = VmClass.new()
	var bounded_append: Array = []
	bounded_append.resize(65536)
	vm._dispatch_array_method(bounded_append, "Push", [1])
	_check(bounded_append.size() == 65536 and not vm.last_error.is_empty(), "array helper must reject growth past its cap", failures)
	var tagged_hash: Dictionary = {"SE270": true, "SE300": false}
	_check(vm._dispatch_hash_method(tagged_hash, "GetTagName", [0]) == "SE270", "Hash.GetTagName must return the tag at the requested index", failures)
	_check(vm._dispatch_hash_method(tagged_hash, "GetTagName", [1]) == "SE300", "Hash.GetTagName must preserve insertion order for tagged entries", failures)
	_check(vm._dispatch_hash_method(tagged_hash, "GetTagName", [2]) == "", "Hash.GetTagName must return an empty tag for an out-of-range index", failures)
	var deletion_fixture: Array = ["keep"]
	vm.last_error = ""
	vm._dispatch_array_method(deletion_fixture, "Remove", [-2147483648, 2147483647])
	_check(deletion_fixture == ["keep"] and vm.last_error.is_empty(), "malicious remove ranges must be clamped to array bounds", failures)
	vm = VmClass.new()
	vm.image = PackedByteArray([1])
	vm.eval_stack.resize(65537)
	_check(not vm.step() and vm.last_error.contains("求值栈超过上限"), "pre-filled oversized evaluation stacks must fail", failures)
	var instance = VmClass.CsxInstance.new("Fixture")
	_check(not instance.set_field_by_index(65536, "blocked") and instance.field_names.is_empty(), "instance field index must be bounded", failures)

	var valid_image := PackedByteArray([9, 1]) # return without a value
	var valid_result: Dictionary = bytecode.validate_image(valid_image)
	_check(valid_result.get("ok", false) and valid_result.get("instruction_starts", PackedInt32Array()) == PackedInt32Array([0]), "valid single-instruction image must validate", failures)

	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var real_vm = VmClass.new()
		var load_result: Dictionary = real_vm.load_csx(args[0])
		_check(load_result.get("ok", false), "real CSX must pass instruction/conststr validation: %s" % load_result.get("error", "unknown error"), failures)
		if load_result.get("ok", false):
			_check(real_vm.instruction_starts.size() > 0, "real CSX must retain verified instruction boundaries", failures)

	if failures.is_empty():
		print("PASS VM safety and conststr smoke test!")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL ", failure)
		quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _append_u32(bytes: PackedByteArray, value: int) -> void:
	var offset := bytes.size()
	bytes.resize(offset + 4)
	bytes.encode_u32(offset, value)


func _append_s32(bytes: PackedByteArray, value: int) -> void:
	var offset := bytes.size()
	bytes.resize(offset + 4)
	bytes.encode_s32(offset, value)
