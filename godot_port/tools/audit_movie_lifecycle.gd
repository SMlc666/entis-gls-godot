extends SceneTree

# Read-only CSX bytecode audit. Usage:
# godot --headless --path godot_port --script res://tools/audit_movie_lifecycle.gd -- GAME_DIR

const CsxVMReader = preload("res://scripts/csx_vm.gd")
const CsxHostClass = preload("res://scripts/csx_host.gd")

const TARGET_FUNCTIONS := ["Starting", "OpeningMovie", "ScPlayMovie", "PlayMovie"]
const MOVIE_METHODS := ["OpenMovie", "PlayMovie", "IsMoviePlaying", "StopMovie", "CloseMovie", "Release"]
const RELEVANT_GLOBAL_CALLS := ["Starting", "OpeningMovie", "ScPlayMovie", "PlayMovie"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var game_dir := args[0] if not args.is_empty() else OS.get_environment("YOSUGA_GAME_DIR")
	if game_dir.is_empty():
		printerr("Pass the original game directory after --")
		quit(2)
		return
	var csx_path := game_dir.path_join("system/yosuga.csx")
	var vm := CsxVMReader.new(CsxHostClass.new(game_dir))
	var loaded: Dictionary = vm.load_csx(csx_path)
	if not loaded.get("ok", false):
		printerr("Could not load original CSX: %s" % loaded.get("error", "unknown error"))
		quit(1)
		return
	var functions := _sorted_functions(vm.functions)
	var instructions: Array[Dictionary] = []
	var cursor := 0
	while cursor < vm.image.size():
		var batch: Dictionary = vm.bytecode_decoder.decode(vm.image, cursor, 10000)
		if not batch.get("ok", false):
			printerr("CSX decode failed: %s" % batch.get("error", "unknown error"))
			quit(1)
			return
		instructions.append_array(batch.get("instructions", []))
		var next_address := int(batch.get("next_address", cursor))
		if next_address <= cursor:
			printerr("CSX decoder made no progress at 0x%X" % cursor)
			quit(1)
			return
		cursor = next_address

	print("Original CSX: %s" % csx_path)
	print("Decoded %d instructions; %d named functions." % [instructions.size(), functions.size()])
	for target_name in TARGET_FUNCTIONS:
		var target_address := int(vm.functions.get(target_name, -1))
		if target_address < 0:
			print("\nFUNCTION %s: not present" % target_name)
			continue
		var end_address := _next_function_address(functions, target_address, vm.image.size())
		print("\n===== FUNCTION %s @ 0x%X .. 0x%X =====" % [target_name, target_address, end_address])
		var emitted := 0
		for instruction: Dictionary in instructions:
			var address := int(instruction.get("address", -1))
			if address < target_address or address >= end_address:
				continue
			print(_format_instruction(instruction, _function_owner(functions, address)))
			emitted += 1
		if emitted == 0:
			print("(no decoded instructions in this function range)")

	print("\n===== MovieSprite constructions across the full image =====")
	var construction_count := 0
	for instruction: Dictionary in instructions:
		if not _is_movie_sprite_construction(instruction):
			continue
		construction_count += 1
		print(_format_instruction(instruction, _function_owner(functions, int(instruction.address))))
	if construction_count == 0:
		print("No `new MovieSprite` instruction was decoded; construction may be indirect or type-erased.")

	print("\n===== Lifecycle method calls across the full image =====")
	var lifecycle_count := 0
	for instruction: Dictionary in instructions:
		if int(instruction.get("opcode", -1)) != 8:
			continue
		var operands: Dictionary = instruction.get("operands", {})
		if not MOVIE_METHODS.has(str(operands.get("name", ""))):
			continue
		lifecycle_count += 1
		print(_format_instruction(instruction, _function_owner(functions, int(instruction.address))))
	if lifecycle_count == 0:
		print("No lifecycle member calls found.")

	print("\n===== Calls into movie-related script helpers =====")
	var helper_call_count := 0
	for instruction: Dictionary in instructions:
		if int(instruction.get("opcode", -1)) != 8:
			continue
		var operands: Dictionary = instruction.get("operands", {})
		if not RELEVANT_GLOBAL_CALLS.has(str(operands.get("name", ""))):
			continue
		helper_call_count += 1
		print(_format_instruction(instruction, _function_owner(functions, int(instruction.address))))
	if helper_call_count == 0:
		print("No calls into the selected movie helpers found.")
	quit(0)


func _sorted_functions(functions: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for name: String in functions:
		result.append({"name": name, "address": int(functions[name])})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.address) == int(b.address):
			return str(a.name) < str(b.name)
		return int(a.address) < int(b.address)
	)
	return result


func _function_owner(functions: Array[Dictionary], address: int) -> String:
	var owner := "<before first function>"
	for item: Dictionary in functions:
		if int(item.address) > address:
			break
		owner = "%s@0x%X" % [str(item.name), int(item.address)]
	return owner


func _next_function_address(functions: Array[Dictionary], address: int, image_size: int) -> int:
	for item: Dictionary in functions:
		var candidate := int(item.address)
		if candidate > address:
			return candidate
	return image_size


func _is_movie_sprite_construction(instruction: Dictionary) -> bool:
	var opcode := int(instruction.get("opcode", -1))
	var operands: Dictionary = instruction.get("operands", {})
	if opcode == 0:
		return str(operands.get("class", "")) == "MovieSprite"
	if opcode == 2:
		var value: Dictionary = operands.get("value", {})
		return int(operands.get("mode", -1)) == 0 and int(value.get("type", -1)) == 0 and str(value.get("class", "")) == "MovieSprite"
	return false


func _format_instruction(instruction: Dictionary, owner: String) -> String:
	var address := int(instruction.get("address", -1))
	var opcode := int(instruction.get("opcode", -1))
	var op_name := str(instruction.get("name", "?"))
	var operands: Dictionary = instruction.get("operands", {})
	var details := ""
	match opcode:
		0: # new
			details = "mode=%s type=%s class=%s name=%s" % [
				str(operands.get("mode", "?")), str(operands.get("type", "?")),
				str(operands.get("class", "?")), str(operands.get("name", "?"))]
		2: # load / variable or immediate reference
			details = "mode=%s value=%s" % [str(operands.get("mode", "?")), str(operands.get("value", "?"))]
		3: # store / assign, kind 255 is plain assignment
			details = "assignment_kind=%s (255=plain assignment)" % str(operands.get("kind", "?"))
		4: # enter or exception block
			details = "name=%s args=%s target=%s" % [str(operands.get("name", "")), str(operands.get("args", [])), str(operands.get("target", ""))]
		6, 7: # jump / conditional jump
			details = "condition=%s relative=%s target=0x%X" % [
				str(operands.get("condition", "")), str(operands.get("relative", "?")), int(operands.get("target", -1))]
		8: # call
			details = "mode=%s argc=%s name=%s" % [str(operands.get("mode", "?")), str(operands.get("argc", "?")), str(operands.get("name", "?"))]
		_:
			details = str(operands)
	return "0x%06X %-18s %-14s %s" % [address, owner, op_name, details]
