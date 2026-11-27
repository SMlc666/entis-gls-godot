extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	var host = CsxHostClass.new()
	var vm = CsxVMReader.new(host)
	var window = CsxHostClass.HostWindow.new(host)
	var scope: int = host.begin_command_scope("flush-integration-smoke")
	host.is_waiting_input = true
	if not host.push_command("ID_TEST", "ID_TEST_FULL", 4, 9, Vector2i(17, 23), window, scope):
		_fail(host, vm, "Host rejected command before FlushCommandQueue")
		return
	if host.is_waiting_input or host.pending_command_count() != 1:
		_fail(host, vm, "Accepted Host command must wake the project scheduler and remain queued")
		return

	# This records the current port policy only. Native FlushCommandQueue semantics
	# are still unknown and must not be inferred from this self-runtime test.
	var flush_result: Variant = vm._dispatch_window_method(window, "FlushCommandQueue", [0])
	if flush_result != 0 or host.pending_command_count() != 1:
		_fail(host, vm, "Current VM-to-Host dispatch policy should preserve a completed queued UI command")
		return

	var command = CsxVMReader.CsxInstance.new("Command")
	var get_result: Variant = vm._dispatch_window_method(window, "GetCommand", [command])
	if get_result != 1 or host.pending_command_count() != 0:
		_fail(host, vm, "HostWindow GetCommand should consume the queued event exactly once")
		return
	if command.get_field("strID") != "ID_TEST" or command.get_field("strFullID") != "ID_TEST_FULL":
		_fail(host, vm, "HostWindow GetCommand should transfer command identifiers through the VM dispatcher")
		return
	if command.get_field("nNotification") != 4 or command.get_field("nParameter") != 9:
		_fail(host, vm, "HostWindow GetCommand should transfer notification and parameter through the VM dispatcher")
		return
	if vm._dispatch_window_method(window, "GetCommand", [command]) != 0:
		_fail(host, vm, "HostWindow GetCommand should return empty after consuming the sole event")
		return

	vm.shutdown_runtime()
	host.shutdown_runtime()
	print("PASS VM HostWindow dispatch push -> FlushCommandQueue -> GetCommand integration (self-runtime policy; not native parity)")
	quit(0)


func _fail(host: Variant, vm: Variant, message: String) -> void:
	if vm != null:
		vm.shutdown_runtime()
	if host != null:
		host.shutdown_runtime()
	printerr("FAIL ", message)
	quit(1)
