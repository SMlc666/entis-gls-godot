extends SceneTree

const CsxHostClass = preload("res://scripts/csx_host.gd")
const CsxVMReader = preload("res://scripts/csx_vm.gd")


func _initialize() -> void:
	var host = CsxHostClass.new()
	var vm = CsxVMReader.new(host)
	var window = CsxHostClass.HostWindow.new(host)
	var other_window = CsxHostClass.HostWindow.new(host)
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
	var window_id: int = window.get_instance_id()
	if not host.is_native_command_dispatch_pending(window_id):
		_fail(host, vm, "Consuming a HostWindow command must keep its script dispatch runnable until the next empty poll")
		return
	if vm._dispatch_window_method(other_window, "GetCommand", [command]) != 0 or not host.is_native_command_dispatch_pending(window_id):
		_fail(host, vm, "An unrelated window's empty GetCommand poll must not clear another window's dispatch state")
		return
	var other_window_id: int = other_window.get_instance_id()
	if host.is_native_command_dispatch_pending(other_window_id):
		_fail(host, vm, "Per-window dispatch lookup must not treat another live window's pending dispatch as local")
		return
	var negative_probe_id := -2
	while negative_probe_id == window_id or negative_probe_id == other_window_id:
		negative_probe_id -= 1
	if host.is_native_command_dispatch_pending(negative_probe_id):
		_fail(host, vm, "Only -1 may select the global dispatch query; another negative ID must be checked exactly")
		return
	host.is_waiting_input = false
	if other_window.get_joy_button_pushed(1, 0) != 0 or not host.is_waiting_input or not host.is_native_command_dispatch_pending(window_id):
		_fail(host, vm, "A different window's advance-button poll must not be suppressed by another window's pending dispatch")
		return
	host.is_waiting_input = false
	if window.get_joy_button_pushed(1, 0) != 0 or host.is_waiting_input:
		_fail(host, vm, "An advance-button poll must not re-arm the scheduler wait while the same window's command dispatch is pending")
		return
	var input_filter: CsxHostClass.HostInputFilter = CsxHostClass.HostInputFilter.new(host)
	input_filter.open_filter(0, window)
	host.is_waiting_input = false
	if window.get_joy_button_pushed(1, 0) != 0 or host.is_waiting_input:
		_fail(host, vm, "An active input filter must preserve the same window's pending command dispatch")
		return
	host.yield_for_sprite_activation = false
	if window.get_joy_button_pushed(1, 0, true) != 0 or host.is_waiting_input or not host.yield_for_sprite_activation:
		_fail(host, vm, "A filtered activation poll must keep dispatch runnable while preserving cooperative sprite yield")
		return
	host.is_waiting_input = false
	var direct_same_window_poll: Variant = vm._dispatch_input_filter_method(input_filter, "GetJoyButtonPushed", [1, 0])
	if direct_same_window_poll != 0 or host.is_waiting_input:
		_fail(host, vm, "Direct CSX HostInputFilter polling must use its owning window's pending dispatch")
		return
	input_filter.close_filter()
	input_filter.open_filter(0, other_window)
	host.is_waiting_input = false
	var direct_other_window_poll: Variant = vm._dispatch_input_filter_method(input_filter, "GetJoyButtonPushed", [1, 0])
	if direct_other_window_poll != 0 or not host.is_waiting_input or not host.is_native_command_dispatch_pending(window_id):
		_fail(host, vm, "Direct HostInputFilter polling must not let another window's pending dispatch suppress this window's input wait")
		return
	input_filter.close_filter()
	host.is_waiting_input = false
	if vm._dispatch_window_method(window, "GetCommand", [command]) != 0:
		_fail(host, vm, "HostWindow GetCommand should return empty after consuming the sole event")
		return
	if host.is_native_command_dispatch_pending(window_id):
		_fail(host, vm, "An empty GetCommand poll must clear that window's dispatch state")
		return
	var abandoned_window: CsxHostClass.HostWindow = CsxHostClass.HostWindow.new(host)
	var abandoned_window_id: int = abandoned_window.get_instance_id()
	host.mark_native_command_dispatch(abandoned_window_id)
	if not host.is_native_command_dispatch_pending(abandoned_window_id):
		_fail(host, vm, "A live window's command dispatch state must be tracked")
		return
	abandoned_window = null
	if host.is_native_command_dispatch_pending(abandoned_window_id):
		_fail(host, vm, "A destroyed window must not leave stale command dispatch state")
		return
	host.mark_native_command_dispatch(window_id)
	host.begin_command_scope("dispatch-reset")
	if host.is_native_command_dispatch_pending():
		_fail(host, vm, "Starting a fresh command scope must clear abandoned dispatch state")
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
