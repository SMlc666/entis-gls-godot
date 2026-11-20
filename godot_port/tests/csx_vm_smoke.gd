extends SceneTree

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")
const TestSupport = preload("res://tests/test_support.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("FAIL Pass game directory or CSX path after --")
		quit(1)
		return

	var input_path: String = args[0]
	var csx_path := ""
	var game_dir := ""
	if input_path.ends_with(".csx"):
		csx_path = input_path
		game_dir = input_path.get_base_dir()
		if game_dir.get_file() == "system":
			game_dir = game_dir.get_base_dir()
	else:
		game_dir = input_path
		csx_path = game_dir.path_join("system").path_join("yosuga.csx")

	if not FileAccess.file_exists(csx_path):
		printerr("FAIL CSX file not found: ", csx_path)
		quit(1)
		return

	var host := CsxHostClass.new(game_dir)
	var test_save_dir := TestSupport.new_save_dir("csx_vm")
	host.save_dir = test_save_dir
	var vm := CsxVMReader.new(host)

	print("[1/5] Loading CSX from %s ..." % csx_path)
	var load_res := vm.load_csx(csx_path)
	if not load_res.get("ok", false):
		printerr("FAIL load_csx: ", load_res.get("error", ""))
		quit(1)
		return

	print("  CSX loaded: %d functions, %d prologues, %d globals, %d data" % [
		vm.functions.size(), vm.prologues.size(), vm.global_vars.size(), vm.data_vars.size()
	])

	if vm.functions.size() != 780:
		printerr("FAIL Expected 780 functions, got ", vm.functions.size())
		quit(1)
		return
	if vm.prologues.size() != 321:
		printerr("FAIL Expected 321 prologues, got ", vm.prologues.size())
		quit(1)
		return
	if vm.global_vars.size() != 41:
		printerr("FAIL Expected 41 globals, got ", vm.global_vars.size())
		quit(1)
		return
	if vm.data_vars.size() != 6:
		printerr("FAIL Expected 6 data variables, got ", vm.data_vars.size())
		quit(1)
		return

	print("[2/5] Executing 321 prologues ...")
	var pro_res := vm.execute_prologues()
	if not pro_res.get("ok", false):
		printerr("FAIL execute_prologues: ", pro_res.get("error", ""))
		quit(1)
		return
	print("  Executed %d prologues successfully (total VM instructions: %d)" % [
		pro_res.get("executed", 0), vm.executed_instructions
	])

	print("[3/5] Calling Initialize() ...")
	var init_res := vm.call_function_sync("Initialize", [], 500_000)
	if not init_res.get("ok", false):
		printerr("FAIL Initialize(): %s @ 0x%X" % [init_res.get("error", ""), init_res.get("ip", 0)])
		var Disasm = load("res://scripts/csx_bytecode.gd")
		var dis = Disasm.new()
		var dres = dis.decode(vm.image, max(0, init_res.get("ip", 0) - 20), 10)
		for inst in dres.get("instructions", []):
			print("  0x%06X: %s %s" % [inst.address, inst.opcode, str(inst.operands)])
		quit(1)
		return
	print("  Initialize() completed in %d steps" % init_res.get("steps", 0))

	# Verify scObj fields set by InitScenarioData
	var sc_obj: Variant = vm.globals_by_name.get("scObj", null)
	if sc_obj == null or not (sc_obj is CsxVMReader.CsxInstance):
		printerr("FAIL scObj not initialized properly")
		quit(1)
		return
	var family_name: String = sc_obj.get_field("familyName")
	var first_name: String = sc_obj.get_field("firstName")
	print("  Protagonist name from scObj: %s %s" % [family_name, first_name])
	if family_name != "春日野" or first_name != "悠":
		printerr("FAIL Expected 春日野 悠, got %s %s" % [family_name, first_name])
		quit(1)
		return

	# Verify frameSkin loaded frame.noa
	var frame_skin: Variant = vm.data_by_name.get("frameSkin", null)
	if frame_skin == null or not (frame_skin is CsxHostClass.HostResourceManager):
		printerr("FAIL frameSkin not instantiated")
		quit(1)
		return
	print("  frameSkin loaded archive: %s, resource cache size: %d" % [
		frame_skin.loaded_archive_name, frame_skin.resource_cache.size()
	])
	if frame_skin.resource_cache.is_empty():
		printerr("FAIL frameSkin failed to index frame.noa entries")
		quit(1)
		return

	print("[4/5] Testing scenario dispatch: SetupAdvScreen and calling sc00_Z000 ...")
	var setup_res := vm.call_function_sync("SetupAdvScreen", [], 100_000)
	print("  SetupAdvScreen execution: ok=%s, steps=%d" % [setup_res.get("ok", false), setup_res.get("steps", 0)])
	if not setup_res.get("ok", false):
		printerr("FAIL SetupAdvScreen: %s @ 0x%X" % [setup_res.get("error", "unknown error"), setup_res.get("ip", 0)])
		quit(1)
		return
	host.auto_advance = true
	var sc_res := vm.call_function_sync("sc00_Z000", [], 300_000)
	print("  sc00_Z000 execution result: ok=%s, steps=%d, ip=0x%X, last_error=%s" % [
		sc_res.get("ok", false), sc_res.get("steps", 0), sc_res.get("ip", 0), vm.last_error
	])
	for f in vm.call_stack:
		print("  call_stack frame: func=%s return_ip=0x%X" % [f.name, f.return_ip])
	print("  eval_stack size: %d" % vm.eval_stack.size())
	for i in range(min(5, vm.eval_stack.size())):
		print("    eval_stack[- %d]: %s" % [i+1, str(vm.eval_stack[vm.eval_stack.size() - 1 - i])])


	if not sc_res.get("ok", false):
		var Disasm = load("res://scripts/csx_bytecode.gd")
		var dis = Disasm.new()
		var dres = dis.decode(vm.image, max(0, sc_res.get("ip", 0) - 20), 10)
		for inst in dres.get("instructions", []):
			print("  0x%06X: %s %s" % [inst.address, inst.opcode, str(inst.operands)])
		printerr("FAIL sc00_Z000: %s @ 0x%X" % [sc_res.get("error", vm.last_error), sc_res.get("ip", 0)])
		quit(1)
		return

	print("[5/5] Checking dialogue / audio / background recorded by host ...")
	print("  Current BGM: '%s'" % host.current_bgm)
	print("  Logged messages: %d" % host.log_messages.size())
	print("  Recorded dialogue lines: %d" % host.text_history.size())
	print("  Decoded image cache: %s" % str(host.image_cache.keys()))
	print("  Decoded sound cache: %d sounds loaded" % host.sound_cache.size())
	for line in host.text_history:
		print("    [%s] %s%s" % [line.get("speaker", ""), line.get("text", ""), (" (voice: %s)" % line.get("voice")) if not line.get("voice", "").is_empty() else ""])

	TestSupport.remove_test_saves(test_save_dir)
	print("PASS CSX VM execution smoke test")
	quit(0)
