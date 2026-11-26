extends SceneTree

const VmClass = preload("res://scripts/csx_vm.gd")
const HostClass = preload("res://scripts/csx_host.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var image := PackedByteArray()
	_append_integer(image, 40)
	_append_global_call(image, "Sleep", 1)
	var async_resume_address := image.size()
	_append_integer(image, 9)
	image.append_array(PackedByteArray([9, 0]))
	var sync_address := image.size()
	_append_integer(image, 35)
	_append_global_call(image, "Sleep", 1)
	_append_integer(image, 73)
	image.append_array(PackedByteArray([9, 0]))

	var host = HostClass.new("")
	var vm = VmClass.new(host)
	vm.image = image
	vm.ip = 0
	vm.is_halted = false
	if not vm.step() or not vm.step():
		_fail("The asynchronous Sleep bytecode should execute")
		return
	var sleep_ip: int = vm.ip
	var sleep_instruction_count: int = vm.executed_instructions
	var sleep_deadline: int = vm.cooperative_sleep_deadline_usec
	if not vm.cooperative_yield_requested or sleep_deadline <= Time.get_ticks_usec() or vm.eval_stack != [0]:
		_fail("Sleep must return success and suspend after its call instruction")
		return

	# Synchronous CSX calls may run from UI callbacks while the outer VM waits.
	# They must be able to execute, and the outer deadline/control state must survive.
	var nested_result: Dictionary = vm.call_address_sync(sync_address, [], 32)
	if not nested_result.get("ok", false) or nested_result.get("result") != 73:
		_fail("A synchronous call containing Sleep should fast-forward its wait")
		return
	if vm.ip != sleep_ip or vm.cooperative_sleep_deadline_usec != sleep_deadline or not vm.cooperative_yield_requested:
		_fail("A nested synchronous call must preserve the sleeping outer VM")
		return

	var before_blocked_step: int = vm.executed_instructions
	if not vm.step() or vm.ip != sleep_ip or vm.executed_instructions != before_blocked_step:
		_fail("Repeated step calls before the deadline must not execute or consume instructions")
		return
	var waited_frames := 0
	while Time.get_ticks_usec() < sleep_deadline and waited_frames < 30:
		await process_frame
		waited_frames += 1
	if vm.refresh_cooperative_sleep():
		_fail("The asynchronous Sleep deadline should expire without blocking the SceneTree (remaining %d us)" % (vm.cooperative_sleep_deadline_usec - Time.get_ticks_usec()))
		return
	if not vm.step() or vm.eval_stack != [0, 9]:
		_fail("The VM should resume at the instruction after Sleep when its timer expires")
		return
	if not vm.step() or not vm.is_halted or vm.last_return_value != 9:
		_fail("The resumed bytecode should finish normally")
		return

	var sync_vm = VmClass.new(host)
	sync_vm.image = image
	var direct_sync_result: Dictionary = sync_vm.call_address_sync(sync_address, [], 32)
	if not direct_sync_result.get("ok", false) or direct_sync_result.get("result") != 73 or sync_vm.cooperative_sleep_deadline_usec != 0:
		_fail("Synchronous Sleep must fast-forward without leaving a wall-clock timer")
		return

	vm.shutdown_runtime()
	sync_vm.shutdown_runtime()
	host.shutdown_runtime()
	print("PASS CSX Sleep cooperative yield, frame safety and synchronous fast-forward")
	quit(0)


func _append_integer(image: PackedByteArray, value: int) -> void:
	image.append_array(PackedByteArray([2, 0, 4]))
	_append_s32(image, value)


func _append_global_call(image: PackedByteArray, name: String, argument_count: int) -> void:
	image.append(8)
	image.append(5)
	_append_s32(image, argument_count)
	_append_string(image, name)


func _append_string(image: PackedByteArray, value: String) -> void:
	var utf16 := value.to_utf16_buffer()
	_append_s32(image, utf16.size() / 2)
	image.append_array(utf16)


func _append_s32(image: PackedByteArray, value: int) -> void:
	var offset := image.size()
	image.resize(offset + 4)
	image.encode_s32(offset, value)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)
