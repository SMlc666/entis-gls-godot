extends SceneTree

const Host = preload("res://scripts/csx_host.gd")
const VM = preload("res://scripts/csx_vm.gd")
const TestSupport = preload("res://tests/test_support.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_dir := OS.get_cmdline_user_args()[0]
	var host := Host.new(game_dir)
	var save_dir := TestSupport.new_save_dir("native_activation_input")
	host.save_dir = save_dir
	var vm := VM.new(host)
	if not vm.load_csx(game_dir.path_join("system/yosuga.csx")).get("ok", false):
		_fail("Cannot load original script")
		return
	vm.execute_prologues()
	if not vm.call_function_sync("Initialize", [], 500000).get("ok", false):
		_fail("Cannot initialize original script")
		return
	var sprite := Host.HostSprite.new(1, host)
	sprite.set_transparency(256)
	sprite.set_blending_envelope(0)
	sprite.begin_activation(5000)
	vm.ip = vm.functions["WaitUntilSpriteActive"]
	vm.pending_call_args = [sprite, -1]
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()
	vm.is_halted = false
	host.skip_input_pending = true
	while not vm.is_halted and not host.yield_for_sprite_activation:
		if not await _step_vm_cooperatively(vm, host):
			_fail(vm.last_error)
			return
	if host.skip_input_pending or not sprite.is_activating:
		_fail("Original function must clear an earlier input before waiting")
		return
	var player = load("res://scenes/adv_player.tscn").instantiate()
	player.host = host
	player.is_running = true
	var event := InputEventKey.new()
	event.keycode = KEY_CTRL
	event.pressed = true
	player._unhandled_input(event)
	player.free()
	host.yield_for_sprite_activation = false
	var steps := 0
	while not vm.is_halted and steps < 1000:
		if not await _step_vm_cooperatively(vm, host):
			_fail(vm.last_error)
			return
		steps += 1
	if not vm.is_halted or sprite.is_activating or sprite.transparency != 0 or vm.last_return_value != -1:
		_fail("Control must make the original function finish the active transition")
		return
	sprite.set_transparency(256)
	sprite.begin_activation(5000)
	vm.ip = vm.functions["WaitUntilSpriteActive"]
	vm.pending_call_args = [sprite, 0]
	vm.pending_return_ip = -1
	vm.call_stack.clear()
	vm.eval_stack.clear()
	vm.is_halted = false
	host.yield_for_sprite_activation = false
	while not vm.is_halted and not host.yield_for_sprite_activation:
		if not await _step_vm_cooperatively(vm, host):
			_fail(vm.last_error)
			return
	host.skip_input_pending = true
	for frame in range(3):
		host.yield_for_sprite_activation = false
		while not vm.is_halted and not host.yield_for_sprite_activation:
			if not await _step_vm_cooperatively(vm, host):
				_fail(vm.last_error)
				return
	if vm.is_halted or not sprite.is_activating:
		_fail("A transition with skipping disabled must continue")
		return
	host.advance_sprite_animations(5.0)
	host.yield_for_sprite_activation = false
	while not vm.is_halted:
		if not await _step_vm_cooperatively(vm, host):
			_fail(vm.last_error)
			return
	if vm.last_return_value != 0:
		_fail("A completed unskippable transition must report normal completion")
		return
	TestSupport.remove_test_saves(save_dir)
	print("PASS Original animation skip input")
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL ", message)
	quit(1)


func _step_vm_cooperatively(vm: Variant, host: Variant) -> bool:
	if not vm.step():
		return false
	while vm.refresh_cooperative_sleep():
		host.advance_sprite_animations(1.0 / 60.0)
		await process_frame
	return true
